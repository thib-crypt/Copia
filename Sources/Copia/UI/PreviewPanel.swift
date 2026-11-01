import AppKit
import SwiftUI

/// Grand aperçu (façon infobulle) du contenu complet d'une copie, affiché à côté du panneau
/// après un survol prolongé, ou avec ⌘Y.
@Observable
final class PreviewModel {
    var item: ClipItem?
    var text = ""
    var terms: [String] = []
    var stats = ""
    var hiddenChars = 0
    var monospaced = false
    var cardHeight: CGFloat = 200
    // Images
    var image: NSImage?
    var imageHeight: CGFloat = 0
    // Texte riche
    var rich: NSAttributedString?
    var richHeight: CGFloat = 0
    // Fichiers
    var files: [FileEntry] = []
    /// Le côté du panneau d'où l'aperçu grandit.
    var anchor: UnitPoint = .leading
    var isPresented = false
}

struct FileEntry: Identifiable {
    let url: URL
    let name: String
    let detail: String
    let exists: Bool
    let icon: NSImage
    var id: String { url.path }

    static func make(_ url: URL) -> FileEntry {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        var parts: [String] = []
        if !exists {
            parts.append("Introuvable")
        } else if isDir.boolValue {
            let n = (try? fm.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? 0
            parts.append("Dossier · \(n) élément\(n > 1 ? "s" : "")")
        } else {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey])
            if let t = v?.localizedTypeDescription { parts.append(t) }
            if let b = v?.fileSize { parts.append(Bytes.string(b)) }
        }
        return FileEntry(url: url, name: fm.displayName(atPath: url.path), detail: parts.joined(separator: " · "),
                         exists: exists, icon: ThumbnailCache.icon(for: url))
    }
}

private final class PreviewWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    // Ne vole jamais le clavier au panneau principal (sinon il se fermerait).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PreviewController {
    static let width: CGFloat = 400
    static let pad: CGFloat = 24
    static let headerHeight: CGFloat = 50
    static let footerHeight: CGFloat = 30
    static let bodyPadding: CGFloat = 14
    static let maxBodyHeight: CGFloat = 420
    static let maxChars = 20_000
    static let lineSpacing: CGFloat = 2.5
    static let fileRowHeight: CGFloat = 40
    static let ocrHeaderHeight: CGFloat = 30
    static var contentWidth: CGFloat { width - bodyPadding * 2 }

    let model = PreviewModel()
    private let window = PreviewWindow()
    private let prefs: Preferences
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var pendingID: Int64?
    private var generation = 0
    private var cardRect: NSRect = .zero

    init(prefs: Preferences) {
        self.prefs = prefs
        let host = NSHostingView(rootView: PreviewCardView(model: model, prefs: prefs))
        host.sizingOptions = []
        window.contentView = host
    }

    private var motion: Motion { Motion(prefs: prefs) }
    var isVisible: Bool { model.isPresented }
    var shownID: Int64? { isVisible ? model.item?.id : nil }

    // MARK: - Survol

    /// Le pointeur est sur une ligne : délai la première fois, bascule instantanée ensuite.
    func hover(item: ClipItem, terms: [String], panelCard: NSRect) {
        cancelHide()
        guard prefs.hoverPreview else { return }
        if isVisible {
            if model.item?.id != item.id {
                present(item, terms: terms, panelCard: panelCard, top: NSEvent.mouseLocation.y + 26, animated: false)
            }
            return
        }
        guard pendingID != item.id else { return }
        pendingID = item.id
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingID = nil
            self.present(item, terms: terms, panelCard: panelCard, top: NSEvent.mouseLocation.y + 26, animated: true)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + prefs.hoverPreviewDelay, execute: work)
    }

    /// Le pointeur quitte une ligne : on laisse le temps de rejoindre l'aperçu.
    func hoverEnded() {
        showWork?.cancel()
        pendingID = nil
        if isVisible { scheduleHide(after: 0.3) }
    }

    /// Navigation clavier : l'aperçu ouvert suit la sélection, à la même hauteur.
    func follow(item: ClipItem, terms: [String], panelCard: NSRect) {
        guard isVisible, model.item?.id != item.id else { return }
        present(item, terms: terms, panelCard: panelCard, top: cardRect.maxY, animated: false)
    }

    /// ⌘Y : ouvre / ferme l'aperçu de la sélection, même si le survol est désactivé.
    func toggle(item: ClipItem, terms: [String], panelCard: NSRect) {
        if isVisible { hide(animated: false); return }
        present(item, terms: terms, panelCard: panelCard, top: panelCard.maxY - 57, animated: false)
    }

    func hide(animated: Bool = true) {
        showWork?.cancel()
        pendingID = nil
        cancelHide()
        guard model.isPresented else { return }
        generation += 1
        let gen = generation
        let (animation, duration) = animated ? motion.previewExit : (nil, 0)
        guard let animation else {
            model.isPresented = false
            window.orderOut(nil)
            return
        }
        withAnimation(animation) { model.isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == gen, !self.model.isPresented else { return }
            self.window.orderOut(nil)
        }
    }

    // MARK: - Fermeture différée

    /// Tant que le pointeur est dans l'aperçu (pour le faire défiler), on le garde.
    /// Vérification géométrique : un panneau non clé ne reçoit pas toujours les survols.
    private func scheduleHide(after delay: TimeInterval) {
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.isPresented else { return }
            if self.cardRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                self.scheduleHide(after: 0.2)
            } else {
                self.hide()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    // MARK: - Présentation

    private func present(_ item: ClipItem, terms: [String], panelCard: NSRect, top desiredTop: CGFloat, animated: Bool) {
        let full = item.text.trimmingCharacters(in: .newlines)
        let total = full.count
        let text = total > Self.maxChars ? String(full.prefix(Self.maxChars)) : full
        let mono = item.kind == .text && Self.looksLikeCode(text)
        var image: NSImage?
        var imageHeight: CGFloat = 0
        var rich: NSAttributedString?
        var richHeight: CGFloat = 0
        var files: [FileEntry] = []
        var content: CGFloat

        switch item.kind {
        case .text:
            content = Self.measure(text, monospaced: mono)
        case .richText:
            if let a = RichText.attributed(for: item) {
                rich = a
                richHeight = Self.measure(attributed: a, width: Self.contentWidth - 24) + 20
                content = richHeight
            } else {
                content = Self.measure(text, monospaced: false)
            }
        case .image:
            let w = CGFloat(item.meta.width ?? 4), h = CGFloat(item.meta.height ?? 3)
            // Jamais agrandie au-delà de sa taille réelle (en points Retina).
            let displayW = min(Self.contentWidth, w / 2)
            imageHeight = min(displayW * h / w, Self.maxBodyHeight - Self.bodyPadding * 2)
            image = ThumbnailCache.shared.cached(ThumbnailCache.key(for: item, size: 80))
            content = imageHeight
            if !text.isEmpty { content += Self.ocrHeaderHeight + Self.measure(text, monospaced: false) }
        case .fileURL:
            files = item.fileURLs.map(FileEntry.make)
            content = CGFloat(files.count) * Self.fileRowHeight
        }
        let bodyHeight = min(content + Self.bodyPadding * 2, Self.maxBodyHeight)
        let height = Self.headerHeight + 1 + bodyHeight + Self.footerHeight

        // Côté droit du panneau, sinon gauche, sinon recadré à l'écran.
        let center = NSPoint(x: panelCard.midX, y: panelCard.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let gap: CGFloat = 10
        let x: CGFloat
        let onRight: Bool
        if panelCard.maxX + gap + Self.width <= vf.maxX - 8 {
            x = panelCard.maxX + gap; onRight = true
        } else if panelCard.minX - gap - Self.width >= vf.minX + 8 {
            x = panelCard.minX - gap - Self.width; onRight = false
        } else {
            x = vf.maxX - 8 - Self.width; onRight = true
        }
        let top = max(min(desiredTop, vf.maxY - 8), vf.minY + 8 + height)
        cardRect = NSRect(x: x, y: top - height, width: Self.width, height: height)

        // L'aperçu grandit depuis le bord collé au panneau, à hauteur du pointeur.
        let mouseY = NSEvent.mouseLocation.y
        model.anchor = UnitPoint(x: onRight ? 0 : 1, y: min(max((top - mouseY) / height, 0), 1))
        model.item = item
        model.text = text
        model.terms = terms
        model.monospaced = mono
        model.hiddenChars = item.kind == .fileURL ? 0 : total - text.count
        model.stats = Self.stats(for: full, item: item, files: files)
        model.cardHeight = height
        model.image = image
        model.imageHeight = imageHeight
        model.rich = rich
        model.richHeight = richHeight
        model.files = files
        if item.kind == .image { loadFullImage(item) }

        generation += 1 // annule un orderOut de sortie en cours
        window.setFrame(cardRect.insetBy(dx: -Self.pad, dy: -Self.pad), display: false)
        guard !model.isPresented else { return }
        window.orderFront(nil)
        if animated, let enter = motion.previewEnter {
            DispatchQueue.main.async { [self] in withAnimation(enter) { model.isPresented = true } }
        } else {
            model.isPresented = true
        }
    }

    /// Image nette pour l'aperçu, décodée hors du thread principal (la miniature s'affiche en attendant).
    private func loadFullImage(_ item: ClipItem) {
        let blob = item.blobPath
        let id = item.id
        let px = Int(Self.contentWidth * 2)
        Task { [weak self] in
            let cg = await Task.detached(priority: .userInitiated) { ImageProcessor.downsampled(blob: blob, maxPixels: px) }.value
            guard let self, let cg, self.model.item?.id == id else { return }
            self.model.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    // MARK: - Mesures

    private static func measure(attributed a: NSAttributedString, width: CGFloat) -> CGFloat {
        let sample = a.length > 6_000 ? a.attributedSubstring(from: NSRange(location: 0, length: 6_000)) : a
        let rect = sample.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height) + 4
    }

    static func font(monospaced: Bool) -> NSFont {
        monospaced ? .monospacedSystemFont(ofSize: 11.5, weight: .regular) : .systemFont(ofSize: 12.5)
    }

    private static func measure(_ text: String, monospaced: Bool) -> CGFloat {
        // Au-delà de quelques milliers de caractères, on atteint de toute façon la hauteur max.
        let sample = text.count > 4_000 ? String(text.prefix(4_000)) : text
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let attr = NSAttributedString(string: sample.isEmpty ? " " : sample,
                                      attributes: [.font: font(monospaced: monospaced), .paragraphStyle: style])
        let rect = attr.boundingRect(with: NSSize(width: width - bodyPadding * 2, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height) + 4
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let sample = text.prefix(2_000)
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return false }
        let symbols = sample.filter { "{};=<>()[]".contains($0) }.count
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        return Double(symbols) / Double(max(sample.count, 1)) > 0.04 || Double(indented) / Double(lines.count) > 0.3
    }

    private static func stats(for text: String, item: ClipItem, files: [FileEntry]) -> String {
        switch item.kind {
        case .image:
            var parts: [String] = []
            if let w = item.meta.width, let h = item.meta.height { parts.append("\(w) × \(h)") }
            if let f = item.meta.format { parts.append(f.uppercased()) }
            if let b = item.meta.bytes { parts.append(Bytes.string(b)) }
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            if words > 0 { parts.append("\(words) mot\(words > 1 ? "s" : "") reconnu\(words > 1 ? "s" : "")") }
            return parts.joined(separator: " · ")
        case .fileURL:
            let missing = files.filter { !$0.exists }.count
            var parts = ["\(files.count) élément\(files.count > 1 ? "s" : "")"]
            if missing > 0 { parts.append("\(missing) introuvable\(missing > 1 ? "s" : "")") }
            parts.append("⌘R pour afficher dans le Finder")
            return parts.joined(separator: " · ")
        case .richText:
            return "Mis en forme (\(RichText.formatLabel(item))) · \(text.count.formatted()) car."
        case .text:
            break
        }
        let chars = text.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        var parts = ["\(chars.formatted()) car.", "\(words.formatted()) mot\(words > 1 ? "s" : "")"]
        if lines > 1 { parts.append("\(lines.formatted()) lignes") }
        if item.copyCount > 1 { parts.append("copié \(item.copyCount)×") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Vue

struct PreviewCardView: View {
    let model: PreviewModel
    let prefs: Preferences

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    private var motion: Motion { Motion(prefs: prefs) }

    var body: some View {
        ZStack {
            if let item = model.item {
                card(item)
                    .frame(width: PreviewController.width, height: model.cardHeight)
                    .scaleEffect(model.isPresented ? 1 : motion.previewScale, anchor: model.anchor)
                    .opacity(model.isPresented ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ item: ClipItem) -> some View {
        styled(
            VStack(spacing: 0) {
                header(item)
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                ScrollView(.vertical) {
                    Group {
                        switch item.kind {
                        case .text: plainBody
                        case .richText: richBody
                        case .image: imageBody
                        case .fileURL: filesBody
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PreviewController.bodyPadding)
                }
                .scrollIndicators(.automatic)
                .id(item.id) // revient en haut à chaque nouvelle copie
                footer
            }
        )
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
    }

    @ViewBuilder
    private func styled(_ v: some View) -> some View {
        if prefs.panelMaterial == .glass {
            v.glassEffect(.regular, in: shape)
        } else {
            v.background(VisualEffectBackground(material: .popover)).clipShape(shape)
        }
    }

    // MARK: - Corps selon le type

    private var plainBody: some View {
        Text(highlighted)
            .font(Font(PreviewController.font(monospaced: model.monospaced)))
            .lineSpacing(PreviewController.lineSpacing)
    }

    /// Le texte riche est rendu sur une « page » claire : fidèle à ce qui sera collé, même en mode sombre.
    @ViewBuilder
    private var richBody: some View {
        if let rich = model.rich {
            RichTextView(text: rich)
                .frame(height: model.richHeight - 20)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .environment(\.colorScheme, .light)
        } else {
            plainBody
        }
    }

    private var imageBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05))
                if let img = model.image {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: model.imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !model.text.isEmpty {
                Label("Texte reconnu", systemImage: "text.viewfinder")
                    .font(.system(size: 10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                    .frame(height: PreviewController.ocrHeaderHeight, alignment: .bottomLeading)
                    .padding(.bottom, 4)
                plainBody.textSelection(.enabled)
            }
        }
    }

    private var filesBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.files) { f in
                HStack(spacing: 10) {
                    Image(nsImage: f.icon).resizable().frame(width: 28, height: 28).opacity(f.exists ? 1 : 0.45)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(f.exists ? f.detail : "Introuvable · \(f.url.deletingLastPathComponent().path.abbreviatedPath)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(f.exists ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                            .lineLimit(1).truncationMode(.head)
                    }
                }
                .frame(height: PreviewController.fileRowHeight, alignment: .leading)
            }
        }
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            SourceIcon(item: item, isSelected: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.sourceAppName?.isEmpty == false ? item.sourceAppName! : "Source inconnue")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(RelativeTime.string(for: item.lastCopiedAt)) · \(item.lastCopiedAt.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "fr_FR"))))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.isDictation {
                Label("Dictée", systemImage: "waveform")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.pink.opacity(0.14), in: Capsule())
                    .foregroundStyle(.pink)
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(40))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: PreviewController.headerHeight)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.stats).monospacedDigit()
            Spacer(minLength: 0)
            if model.hiddenChars > 0 {
                Text("+\(model.hiddenChars.formatted()) car. non affichés")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: PreviewController.footerHeight)
        .background(Color.primary.opacity(0.035))
    }

    private var highlighted: AttributedString {
        var a = AttributedString(model.text)
        let s = model.text
        var budget = 300 // évite de surligner des milliers d'occurrences
        for t in model.terms where !t.isEmpty {
            var range = s.startIndex..<s.endIndex
            while budget > 0, let r = s.range(of: t, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
                if let ar = Range(r, in: a) {
                    a[ar].backgroundColor = Color.yellow.opacity(0.38)
                }
                range = r.upperBound..<s.endIndex
                budget -= 1
            }
        }
        return a
    }
}
