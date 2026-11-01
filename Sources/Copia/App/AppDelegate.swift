import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences.shared
    private var store: ClipStore!
    private var watcher: PasteboardWatcher!
    private var coordinator: CaptureCoordinator!
    private var panel: PanelController!
    private var statusItem: StatusItemController!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipStore(db: ClipDatabase())
        store.enforceLimits(maxItems: prefs.maxStored, retentionDays: prefs.retentionDays)
        store.enforceDiskQuota(maxBytes: prefs.diskQuotaBytes)
        BlobStore.sweep(keeping: store.referencedBlobs)

        watcher = PasteboardWatcher(interval: prefs.pollingMode.interval)
        coordinator = CaptureCoordinator(store: store, watcher: watcher, prefs: prefs)
        panel = PanelController(store: store, coordinator: coordinator, prefs: prefs)

        let state = SettingsState()
        settings = SettingsWindowController(ctx: AppContext(prefs: prefs, store: store, coordinator: coordinator,
                                                            watcher: watcher, state: state))

        statusItem = StatusItemController(prefs: prefs)
        statusItem.onLeftClick = { [weak self] rect in self?.panel.toggle(.statusItem(rect)) }
        statusItem.onOpenPanel = { [weak self] in self?.panel.show(.hotKey) }
        statusItem.onOpenSettings = { [weak self] in self?.settings.show() }
        statusItem.onClearHistory = { [weak self] keepPinned in self?.store.clear(keepPinned: keepPinned) }
        panel.setStatusItemFrameProvider { [weak self] in self?.statusItem.buttonFrame }
        panel.onOpenSettings = { [weak self] in self?.settings.show() }

        prefs.onDedupConfigChange = { [weak self] in self?.coordinator.refreshConfig() }
        prefs.onPollingChange = { [weak self] in
            guard let self else { return }
            self.watcher.baseInterval = self.prefs.pollingMode.interval
        }
        prefs.onLimitsChange = { [weak self] in
            guard let self else { return }
            self.store.enforceLimits(maxItems: self.prefs.maxStored, retentionDays: self.prefs.retentionDays)
            self.store.enforceDiskQuota(maxBytes: self.prefs.diskQuotaBytes)
        }
        prefs.onCaptureOptionsChange = { [weak self] in self?.coordinator.refreshCaptureOptions() }
        prefs.onHotKeyChange = { [weak self] in
            HotKeyCenter.shared.register(self?.prefs.hotKey)
            self?.statusItem.rebuildMenu()
        }

        HotKeyCenter.shared.onPress = { [weak self] in self?.panel.toggle(.hotKey) }
        HotKeyCenter.shared.register(prefs.hotKey)
        watcher.start()

        // Purge quotidienne pour la durée de conservation (timer très tolérant).
        let purge = Timer(timeInterval: 3_600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.store.enforceLimits(maxItems: self.prefs.maxStored, retentionDays: self.prefs.retentionDays)
            }
        }
        purge.tolerance = 600
        RunLoop.main.add(purge, forMode: .common)

        if !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            LaunchAtLogin.set(true)
            settings.show(page: .welcome)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
    }

    /// Relancer l'app (ex. depuis le Finder) ouvre les réglages.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}

// MARK: - Barre des menus

final class StatusItemController: NSObject, NSMenuDelegate {
    var onLeftClick: ((NSRect) -> Void)?
    var onOpenPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onClearHistory: ((Bool) -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let prefs: Preferences
    private var menu = NSMenu()

    init(prefs: Preferences) {
        self.prefs = prefs
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = "Copia"
        }
        updateIcon()
        rebuildMenu()
        observePause()
    }

    var buttonFrame: NSRect? { item.button?.window?.frame }

    private func observePause() {
        withObservationTracking { _ = prefs.paused } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateIcon()
                self?.rebuildMenu()
                self?.observePause()
            }
        }
    }

    private func updateIcon() {
        let name = prefs.paused ? "pause.circle" : "list.clipboard"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Copia")
        img?.isTemplate = true
        item.button?.image = img?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        item.button?.appearsDisabled = prefs.paused
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true || event?.modifierFlags.contains(.option) == true {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else if let frame = buttonFrame {
            onLeftClick?(frame)
        }
    }

    func rebuildMenu() {
        menu = NSMenu()
        let open = NSMenuItem(title: "Ouvrir l'historique", action: #selector(openPanel), keyEquivalent: "")
        if let hk = prefs.hotKey { open.title += "   \(hk.displayString)" }
        menu.addItem(open)
        menu.addItem(withTitle: prefs.paused ? "Reprendre l'enregistrement" : "Mettre en pause l'enregistrement",
                     action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Effacer l'historique…", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Copia", action: #selector(quit), keyEquivalent: "q")
        for i in menu.items { i.target = self }
    }

    @objc private func openPanel() { onOpenPanel?() }
    @objc private func togglePause() { prefs.paused.toggle() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Effacer l'historique ?"
        alert.informativeText = "Cette action est définitive."
        alert.addButton(withTitle: "Garder les épinglées")
        alert.addButton(withTitle: "Tout effacer")
        alert.addButton(withTitle: "Annuler")
        alert.buttons[1].hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: onClearHistory?(true)
        case .alertSecondButtonReturn: onClearHistory?(false)
        default: break
        }
    }
}

// MARK: - Fenêtre de réglages

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let ctx: AppContext
    private var window: NSWindow?

    init(ctx: AppContext) { self.ctx = ctx }

    func show(page: SettingsPage? = nil) {
        if let page { ctx.state.page = page }
        if window == nil {
            let host = NSHostingController(rootView: SettingsRootView(ctx: ctx, state: ctx.state))
            let w = NSWindow(contentViewController: host)
            w.title = "Copia"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 820, height: 600))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("CopiaSettings")
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Libère la hiérarchie SwiftUI : aucune mise à jour en arrière-plan.
        DispatchQueue.main.async { self.window = nil }
    }
}
