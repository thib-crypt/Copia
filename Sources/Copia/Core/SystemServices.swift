import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Collage (⌘V simulé)

enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Envoie ⌘V directement à l'app au premier plan, sans passer par AppleScript.
    static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        // Évite que des modificateurs encore enfoncés (⌥ du raccourci) se mélangent au ⌘V.
        src?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

// MARK: - Position du curseur de texte (Accessibilité)

enum CaretLocator {
    /// Rectangle du curseur de texte de l'app active, en coordonnées AppKit (origine en bas à gauche).
    static func caretRect() -> NSRect? {
        guard Paster.isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.12)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeRef, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect),
              rect.origin != .zero || rect.size != .zero else { return nil }
        // Quartz (origine en haut à gauche de l'écran principal) → AppKit.
        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.maxY - rect.maxY
        return NSRect(x: rect.minX, y: flippedY, width: max(rect.width, 1), height: max(rect.height, 14))
    }
}

// MARK: - Raccourci global (Carbon, sans dépendance)

private nonisolated func copiaHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeyCenter.shared.fire() }
    }
    return noErr
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onPress: (() -> Void)?
    private(set) var lastRegistrationFailed = false
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func fire() { onPress?() }

    @discardableResult
    func register(_ combo: KeyCombo?) -> Bool {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        lastRegistrationFailed = false
        guard let combo else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x43505941), id: 1) // 'CPYA'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetEventDispatcherTarget(), 0, &newRef)
        if status == noErr { ref = newRef } else { lastRegistrationFailed = true }
        return status == noErr
    }

    /// Suspend le raccourci pendant l'enregistrement d'un nouveau dans les réglages.
    func suspend() { if let ref { UnregisterEventHotKey(ref); self.ref = nil } }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), copiaHotKeyHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

extension KeyCombo {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        let isFunctionKey = (96...122).contains(Int(event.keyCode))
        guard m & UInt32(cmdKey | optionKey | controlKey) != 0 || isFunctionKey else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: m)
    }

    /// Touches séparées pour l'affichage en « keycaps » : ["⌥", "⌘", "V"].
    var symbols: [String] {
        var s: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { s.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { s.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { s.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { s.append("⌘") }
        s.append(Self.keyName(keyCode))
        return s
    }

    var displayString: String { symbols.joined() }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Space: "Espace", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[Int(code)] { return s }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "?" }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            guard status == noErr, len > 0 else { return "?" }
            return String(utf16CodeUnits: chars, count: len).uppercased()
        }
    }
}

// MARK: - Lancement à l'ouverture de session

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Copia: lancement au démarrage — \(error.localizedDescription)")
        }
    }
}

// MARK: - Icônes d'apps (cache)

final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]
    private var names: [String: String] = [:]

    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let img = cache[bundleID] { return img }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[bundleID] = img
        return img
    }

    func name(for bundleID: String) -> String {
        if let n = names[bundleID] { return n }
        var n = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            n = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        names[bundleID] = n
        return n
    }

    func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

// MARK: - Mémoire utilisée

enum ProcessStats {
    static var residentMegabytes: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}
