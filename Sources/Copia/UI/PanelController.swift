import AppKit
import SwiftUI
import Carbon.HIToolbox

struct RowData: Identifiable, Equatable {
    let item: ClipItem
    let display: String
    /// Ligne secondaire : texte reconnu d'une image, dossier des fichiers.
    var detail: String? = nil
    var id: Int64 { item.id }

    static func make(_ item: ClipItem, terms: [String]) -> RowData {
        switch item.kind {
        case .text, .richText:
            return RowData(item: item, display: terms.isEmpty ? item.preview : Snippet.make(for: item, terms: terms))
        case .image:
            let ocr = item.hasPlainText ? (terms.isEmpty ? item.preview : Snippet.make(for: item, terms: terms)) : nil
            return RowData(item: item, display: item.title, detail: ocr)
        case .fileURL:
            let folder = item.fileURLs.first?.deletingLastPathComponent().path.abbreviatedPath
            return RowData(item: item, display: item.title, detail: folder)
        }
    }
}

enum KindFilter: Int, CaseIterable, Identifiable {
    case all, text, images, files
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .all: "Tout"
        case .text: "Texte"
        case .images: "Images"
        case .files: "Fichiers"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.stack"
        case .text: "text.alignleft"
        case .images: "photo"
        case .files: "doc"
        }
    }
    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: true
        case .text: item.kind == .text || item.kind == .richText
        case .images: item.kind == .image
        case .files: item.kind == .fileURL
        }
    }
}

@Observable
final class PanelModel {
    var query = "" { didSet { if query != oldValue { onQueryChange?() } } }
    var filter: KindFilter = .all { didSet { if filter != oldValue { onQueryChange?() } } }
    /// L'historique contient-il des images ou des fichiers ? (sinon les filtres sont masqués)
    var hasMedia = false
    var pinned: [RowData] = []
    var rows: [RowData] = []
    var selectedID: Int64?
    var keyboardDriven = false
    var isPresented = false
    var isMounted = false
    var focusToken = 0
    var highlightTerms: [String] = []
    var totalCount = 0
    var hiddenCount = 0
    /// Point d'où le panneau grandit (le déclencheur : curseur de texte, souris ou icône).
    var anchor: UnitPoint = .top
    /// Le panneau vient d'au-dessus (+1), d'en dessous (-1) ou est centré comme une modale (0).
    var enterDirection: CGFloat = 1
    /// L'ouverture en cours est-elle animée ? (sinon pas de cascade non plus)
    var animatedOpen = false
    var needsAccessibility = false

    @ObservationIgnored var onQueryChange: (() -> Void)?

    var flat: [RowData] { pinned + rows }
}

final class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Panneau d'historique : non activant (l'app en cours garde le focus), ce qui permet de
/// coller directement à l'endroit du curseur.
final class PanelController {
    enum Origin {
        case hotKey
        case statusItem(NSRect)
    }

    static let cardSize = NSSize(width: 448, height: 528)
    static let shadowPad: CGFloat = 28
    static var windowSize: NSSize {
        NSSize(width: cardSize.width + shadowPad * 2, height: cardSize.height + shadowPad * 2)
    }

    let model = PanelModel()
    let preview: PreviewController
    var onOpenSettings: (() -> Void)?

    private let panel = FloatingPanel(size: PanelController.windowSize)
    private let store: ClipStore
    private let coordinator: CaptureCoordinator
    private let prefs: Preferences
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var searchTask: Task<Void, Never>?
    private var lastHide = Date.distantPast
    private var statusItemFrame: () -> NSRect? = { nil }
    /// Position du pointeur à l'ouverture : tant qu'il n'a pas bougé, pas d'aperçu au survol.
    private var openMouse: NSPoint?

    init(store: ClipStore, coordinator: CaptureCoordinator, prefs: Preferences) {
        self.store = store
        self.coordinator = coordinator
        self.prefs = prefs
        self.preview = PreviewController(prefs: prefs)
        let root = ClipPanelView(model: model, prefs: prefs, coordinator: coordinator, controller: self)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        panel.contentView = host
        panel.onResignKey = { [weak self] in self?.hide() }
        model.onQueryChange = { [weak self] in
            self?.preview.hide(animated: false)
            self?.refresh()
        }
        store.onChange = { [weak self] in
            guard let self, self.model.isMounted else { return }
            self.refresh()
        }
    }

    func setStatusItemFrameProvider(_ provider: @escaping () -> NSRect?) { statusItemFrame = provider }

    var isVisible: Bool { model.isPresented }

    // MARK: - Affichage

    func toggle(_ origin: Origin) {
        if model.isPresented {
            if case .hotKey = origin { hide(byKeyboard: true) } else { hide() }
            return
        }
        if case .statusItem = origin, Date.now.timeIntervalSince(lastHide) < 0.3 { return }
        show(origin)
    }

    private var motion: Motion { Motion(prefs: prefs) }

    func show(_ origin: Origin) {
        let byKeyboard: Bool
        if case .hotKey = origin { byKeyboard = true } else { byKeyboard = false }
        model.query = ""
        model.filter = .all
        refresh()
        model.selectedID = model.flat.first?.id
        model.needsAccessibility = prefs.pasteOnSelect && !Paster.isTrusted
        openMouse = NSEvent.mouseLocation

        let placement = targetCardRect(for: origin)
        model.anchor = placement.anchor
        model.enterDirection = placement.direction
        panel.setFrame(placement.rect.insetBy(dx: -Self.shadowPad, dy: -Self.shadowPad), display: false)

        let animation = motion.panelEnter(byKeyboard: byKeyboard)
        model.animatedOpen = animation != nil
        model.isMounted = true
        if animation == nil { model.isPresented = true }
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        model.focusToken += 1
        if let animation {
            // Un tour de boucle pour que l'état initial soit rendu avant l'animation d'entrée.
            DispatchQueue.main.async { [self] in withAnimation(animation) { model.isPresented = true } }
        }
    }

    /// - Parameter byKeyboard: fermeture provoquée par une touche (↩, ⎋, ⌘1…) → instantanée.
    func hide(byKeyboard: Bool = false, completion: (() -> Void)? = nil) {
        guard model.isPresented else { completion?(); return }
        removeMonitors()
        lastHide = .now
        let (animation, duration) = motion.panelExit(byKeyboard: byKeyboard)
        preview.hide(animated: animation != nil)
        let finish = { [weak self] in
            guard let self else { return }
            if !self.model.isPresented {
                self.panel.orderOut(nil)
                self.model.isMounted = false
                self.searchTask?.cancel()
            }
        }
        guard let animation else {
            model.isPresented = false
            finish()
            completion?()
            return
        }
        withAnimation(animation) { model.isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            finish()
            completion?()
        }
    }

    // MARK: - Contenu

    func refresh() {
        let q = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = model.filter
        model.totalCount = store.count
        model.hasMedia = store.items.contains { $0.kind == .image || $0.kind == .fileURL }
        if !model.hasMedia && filter != .all { model.filter = .all; return }
        searchTask?.cancel()
        if q.isEmpty {
            model.highlightTerms = []
            let visible = store.items.lazy.filter(filter.matches)
            model.pinned = visible.filter(\.pinned).map { RowData.make($0, terms: []) }
            let recent = visible.filter { !$0.pinned }.prefix(max(prefs.displayCount, 1))
            model.rows = recent.map { RowData.make($0, terms: []) }
            let total = filter == .all ? store.count : visible.count
            model.hiddenCount = max(total - model.pinned.count - model.rows.count, 0)
            fixSelection(preferFirst: false)
            return
        }
        let allowed = filter == .all ? nil : Set(store.items.lazy.filter(filter.matches).map(\.id))
        let candidates = store.searchCandidates().filter { allowed?.contains($0.id) ?? true }
        let terms = q.split(whereSeparator: \.isWhitespace).map(String.init)
        searchTask = Task { [weak self] in
            let hits = await Task.detached(priority: .userInitiated) {
                FuzzySearch.search(q, in: candidates, limit: 60)
            }.value
            guard !Task.isCancelled, let self,
                  self.model.query.trimmingCharacters(in: .whitespacesAndNewlines) == q else { return }
            let byID = Dictionary(self.store.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.model.pinned = []
            self.model.rows = hits.compactMap { byID[$0.id] }.map { RowData.make($0, terms: terms) }
            self.model.highlightTerms = terms
            self.model.hiddenCount = 0
            self.fixSelection(preferFirst: true)
        }
    }

    private func fixSelection(preferFirst: Bool) {
        let flat = model.flat
        if preferFirst || !flat.contains(where: { $0.id == model.selectedID }) {
            model.selectedID = flat.first?.id
        }
    }

    // MARK: - Actions

    /// - Parameter plain: ⌥ : texte brut (texte riche sans mise en forme, chemins des fichiers, texte d'une image).
    func activate(_ id: Int64, copyOnly: Bool, plain: Bool = false, byKeyboard: Bool = false) {
        guard let item = store.item(id: id) else { return }
        let asPlain = item.kind == .richText ? plain != prefs.pastePlainByDefault : plain
        guard coordinator.copyToPasteboard(item, plain: asPlain) else {
            NSSound.beep() // ex. image sans texte reconnu en mode « texte brut »
            return
        }
        prefs.statPastes += 1
        if prefs.playSound { NSSound(named: "Pop")?.play() }
        let shouldPaste = prefs.pasteOnSelect && !copyOnly
        // Le collage n'attend jamais la fin d'une animation : on ferme instantanément.
        hide(byKeyboard: byKeyboard || shouldPaste) {
            guard shouldPaste else { return }
            if Paster.isTrusted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { Paster.sendCommandV() }
            } else {
                Paster.requestTrust()
            }
        }
    }

    /// Ouvre le fichier copié ou l'image (dans Aperçu).
    func open(_ id: Int64) {
        guard let item = store.item(id: id) else { return }
        switch item.kind {
        case .fileURL:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { NSSound.beep(); return }
            hide(byKeyboard: true) { urls.forEach { NSWorkspace.shared.open($0) } }
        case .image:
            guard let url = exportImage(item) else { NSSound.beep(); return }
            hide(byKeyboard: true) { NSWorkspace.shared.open(url) }
        default:
            NSSound.beep()
        }
    }

    /// Affiche les fichiers copiés dans le Finder.
    func reveal(_ id: Int64) {
        guard let item = store.item(id: id) else { return }
        let urls: [URL]
        switch item.kind {
        case .fileURL: urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        case .image: urls = exportImage(item).map { [$0] } ?? []
        default: urls = []
        }
        guard !urls.isEmpty else { NSSound.beep(); return }
        hide(byKeyboard: true) { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// Copie l'image dans un fichier temporaire au nom lisible (« Image Copia 14-32-05.heic »).
    private func exportImage(_ item: ClipItem) -> URL? {
        guard let blob = item.blobPath, BlobStore.exists(blob) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Copia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = item.createdAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("Image Copia \(stamp).\(item.meta.format ?? "png")")
        try? FileManager.default.removeItem(at: url)
        do { try FileManager.default.copyItem(at: BlobStore.url(blob), to: url) } catch { return nil }
        return url
    }

    /// Glisser une ligne vers une autre app.
    func dragProvider(_ id: Int64) -> NSItemProvider {
        guard let item = store.item(id: id) else { return NSItemProvider() }
        switch item.kind {
        case .image:
            if let url = exportImage(item), let p = NSItemProvider(contentsOf: url) { return p }
        case .fileURL:
            if let url = item.fileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let p = NSItemProvider(contentsOf: url) { return p }
        default:
            break
        }
        return NSItemProvider(object: item.plainText as NSString)
    }

    func cycleFilter(_ delta: Int) {
        guard model.hasMedia else { return }
        let all = KindFilter.allCases
        let next = (model.filter.rawValue + delta + all.count) % all.count
        withAnimation(motion.micro) { model.filter = all[next] }
    }

    func togglePin(_ id: Int64) {
        withAnimation(motion.listChange) {
            store.togglePin(id: id)
            refresh()
        }
    }

    func delete(_ id: Int64) {
        let flat = model.flat
        let idx = flat.firstIndex { $0.id == id } ?? 0
        if preview.shownID == id { preview.hide(animated: false) }
        withAnimation(motion.listChange) {
            store.delete(id: id)
            refresh()
            let newFlat = model.flat
            if !newFlat.isEmpty { model.selectedID = newFlat[min(idx, newFlat.count - 1)].id }
        }
    }

    func openSettings() {
        hide { [weak self] in self?.onOpenSettings?() }
    }

    func requestAccessibility() {
        Paster.requestTrust()
        hide()
    }

    private func move(_ delta: Int) {
        let flat = model.flat
        guard !flat.isEmpty else { return }
        let idx = flat.firstIndex { $0.id == model.selectedID } ?? -1
        let next = (idx + delta + flat.count) % flat.count
        model.keyboardDriven = true
        withAnimation(motion.keyboardSelection) { model.selectedID = flat[next].id }
        preview.follow(item: flat[next].item, terms: model.highlightTerms, panelCard: cardFrame)
    }

    private var cardFrame: NSRect { panel.frame.insetBy(dx: Self.shadowPad, dy: Self.shadowPad) }

    /// Sélection au survol : instantanée. Un survol prolongé ouvre l'aperçu complet.
    func hoverSelect(_ id: Int64) {
        if model.selectedID != id {
            model.keyboardDriven = false
            withAnimation(motion.hoverSelection) { model.selectedID = id }
        }
        if let openMouse {
            guard NSEvent.mouseLocation != openMouse else { return }
            self.openMouse = nil
        }
        guard let item = store.item(id: id) else { return }
        preview.hover(item: item, terms: model.highlightTerms, panelCard: cardFrame)
    }

    func hoverEnded() { preview.hoverEnded() }

    private func togglePreview() {
        guard let id = model.selectedID, let item = store.item(id: id) else { return }
        preview.toggle(item: item, terms: model.highlightTerms, panelCard: cardFrame)
    }

    // MARK: - Clavier

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model.isPresented else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private static let digitKeys: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                           kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    private func handleKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let code = Int(e.keyCode)
        switch code {
        case kVK_DownArrow: move(1)
        case kVK_UpArrow: move(-1)
        case kVK_Tab: move(flags.contains(.shift) ? -1 : 1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let id = model.selectedID {
                activate(id, copyOnly: cmd, plain: flags.contains(.option), byKeyboard: true)
            }
        case kVK_ANSI_O where cmd:
            if let id = model.selectedID { open(id) }
        case kVK_ANSI_R where cmd:
            if let id = model.selectedID { reveal(id) }
        case kVK_LeftArrow where cmd:
            cycleFilter(-1)
        case kVK_RightArrow where cmd:
            cycleFilter(1)
        case kVK_Escape:
            if model.query.isEmpty { hide(byKeyboard: true) } else { model.query = "" }
        case kVK_Delete where cmd:
            if let id = model.selectedID { delete(id) }
        case kVK_ANSI_P where cmd:
            if let id = model.selectedID { togglePin(id) }
        case kVK_ANSI_Y where cmd:
            togglePreview()
        case kVK_ANSI_Comma where cmd:
            openSettings()
        case _ where cmd && Self.digitKeys.contains(code):
            let n = Self.digitKeys.firstIndex(of: code)!
            let flat = model.flat
            if n < flat.count { activate(flat[n].id, copyOnly: false, byKeyboard: true) }
        default:
            return false
        }
        return true
    }

    // MARK: - Position

    private struct Placement {
        let rect: NSRect
        let anchor: UnitPoint
        let direction: CGFloat
    }

    private func targetCardRect(for origin: Origin) -> Placement {
        let size = Self.cardSize
        let mouse = NSEvent.mouseLocation

        func screen(containing p: NSPoint) -> NSScreen {
            NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        }

        /// Place la carte sous (ou au-dessus de) le déclencheur, et fait grandir le panneau
        /// depuis le point exact du déclencheur, même après recadrage au bord de l'écran.
        func below(_ anchorRect: NSRect, centered: Bool) -> Placement {
            let vf = screen(containing: NSPoint(x: anchorRect.midX, y: anchorRect.midY)).visibleFrame
            var x = centered ? anchorRect.midX - size.width / 2 : anchorRect.minX - 18
            var y = anchorRect.minY - 6 - size.height
            var above = false
            if y < vf.minY + 8 {
                // Pas la place en dessous : on ouvre au-dessus.
                y = anchorRect.maxY + 6
                above = true
            }
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
            y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
            let ax = min(max((anchorRect.midX - x) / size.width, 0), 1)
            let anchor = UnitPoint(x: centered ? 0.5 : ax, y: above ? 1 : 0)
            return Placement(rect: NSRect(origin: NSPoint(x: x, y: y), size: size), anchor: anchor,
                             direction: above ? -1 : 1)
        }

        /// Mode « centre de l'écran » : se comporte comme une modale, donc centré.
        func centered() -> Placement {
            let vf = screen(containing: mouse).visibleFrame
            let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + vf.height * 0.08)
            return Placement(rect: NSRect(origin: origin, size: size), anchor: .center, direction: 0)
        }

        switch origin {
        case .statusItem(let rect):
            return below(rect, centered: true)
        case .hotKey:
            switch prefs.panelPosition {
            case .textCaret:
                if let caret = CaretLocator.caretRect() { return below(caret, centered: false) }
                return below(NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), centered: false)
            case .mouse:
                return below(NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), centered: false)
            case .center:
                return centered()
            case .menuBar:
                if let r = statusItemFrame() { return below(r, centered: true) }
                return centered()
            }
        }
    }
}

/// Extrait centré sur la première correspondance quand elle est loin dans le texte.
enum Snippet {
    static func make(for item: ClipItem, terms: [String]) -> String {
        guard let first = terms.first else { return item.preview }
        if let r = item.preview.range(of: first, options: [.caseInsensitive, .diacriticInsensitive]),
           item.preview.distance(from: item.preview.startIndex, to: r.lowerBound) < 70 {
            return item.preview
        }
        guard let r = item.text.range(of: first, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return item.preview
        }
        let start = item.text.index(r.lowerBound, offsetBy: -32, limitedBy: item.text.startIndex) ?? item.text.startIndex
        return "…" + ClipItem.makePreview(String(item.text[start...]))
    }
}
