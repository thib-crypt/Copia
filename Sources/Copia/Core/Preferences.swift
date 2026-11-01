import Foundation
import Observation
import Carbon.HIToolbox

enum PanelPosition: String, CaseIterable, Identifiable {
    case textCaret, mouse, center, menuBar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .textCaret: "Au curseur de texte"
        case .mouse: "Au pointeur de la souris"
        case .center: "Au centre de l'écran"
        case .menuBar: "Sous la barre des menus"
        }
    }
}

enum PollingMode: String, CaseIterable, Identifiable {
    case eco, balanced, instant
    var id: String { rawValue }
    var label: String {
        switch self {
        case .eco: "Économie"
        case .balanced: "Équilibré"
        case .instant: "Instantané"
        }
    }
    var interval: TimeInterval {
        switch self {
        case .eco: 0.6
        case .balanced: 0.3
        case .instant: 0.15
        }
    }
}

enum PanelMaterial: String, CaseIterable, Identifiable {
    case frosted, glass
    var id: String { rawValue }
    var label: String { self == .frosted ? "Givré" : "Liquid Glass" }
}

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | optionKey))
}

/// Réglages persistés dans UserDefaults.
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored var onDedupConfigChange: (() -> Void)?
    @ObservationIgnored var onLimitsChange: (() -> Void)?
    @ObservationIgnored var onPollingChange: (() -> Void)?
    @ObservationIgnored var onHotKeyChange: (() -> Void)?
    @ObservationIgnored var onCaptureOptionsChange: (() -> Void)?

    // Historique
    var maxStored: Int { didSet { d.set(maxStored, forKey: "maxStored"); onLimitsChange?() } }
    var displayCount: Int { didSet { d.set(displayCount, forKey: "displayCount") } }
    var previewLines: Int { didSet { d.set(previewLines, forKey: "previewLines") } }
    var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays"); onLimitsChange?() } }
    var mergeDuplicates: Bool { didSet { d.set(mergeDuplicates, forKey: "mergeDuplicates"); onDedupConfigChange?() } }
    var trimWhitespaceForDedup: Bool { didSet { d.set(trimWhitespaceForDedup, forKey: "trimWhitespace") } }

    // Dictée intelligente
    var smartDictation: Bool { didSet { d.set(smartDictation, forKey: "smartDictation"); onDedupConfigChange?() } }
    var dictationWindow: Double { didSet { d.set(dictationWindow, forKey: "dictationWindow"); onDedupConfigChange?() } }
    var dictationApps: [String] { didSet { d.set(dictationApps, forKey: "dictationApps"); onDedupConfigChange?() } }
    var bumpOnRestore: Bool { didSet { d.set(bumpOnRestore, forKey: "bumpOnRestore"); onDedupConfigChange?() } }
    var keepDictations: Bool { didSet { d.set(keepDictations, forKey: "keepDictations"); onDedupConfigChange?() } }

    // Confidentialité
    var ignoreConcealed: Bool { didSet { d.set(ignoreConcealed, forKey: "ignoreConcealed"); onDedupConfigChange?() } }
    var respectTransient: Bool { didSet { d.set(respectTransient, forKey: "respectTransient"); onDedupConfigChange?() } }
    var excludedApps: [String] { didSet { d.set(excludedApps, forKey: "excludedApps"); onDedupConfigChange?() } }
    var paused: Bool { didSet { d.set(paused, forKey: "paused") } }

    // Panneau
    var panelPosition: PanelPosition { didSet { d.set(panelPosition.rawValue, forKey: "panelPosition") } }
    var panelMaterial: PanelMaterial { didSet { d.set(panelMaterial.rawValue, forKey: "panelMaterial") } }
    var pasteOnSelect: Bool { didSet { d.set(pasteOnSelect, forKey: "pasteOnSelect") } }
    var showShortcutNumbers: Bool { didSet { d.set(showShortcutNumbers, forKey: "showShortcutNumbers") } }
    var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    /// Grand aperçu du contenu complet après un survol prolongé.
    var hoverPreview: Bool { didSet { d.set(hoverPreview, forKey: "hoverPreview") } }
    var hoverPreviewDelay: Double { didSet { d.set(hoverPreviewDelay, forKey: "hoverPreviewDelay") } }
    var hotKey: KeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) { d.set(data, forKey: "hotKey") }
            else { d.set(Data(), forKey: "hotKey") }
            onHotKeyChange?()
        }
    }

    // Animations
    var motionStyle: MotionStyle { didSet { d.set(motionStyle.rawValue, forKey: "motionStyle") } }
    var animateKeyboardOpen: Bool { didSet { d.set(animateKeyboardOpen, forKey: "animateKeyboardOpen") } }
    var animateKeyboardNav: Bool { didSet { d.set(animateKeyboardNav, forKey: "animateKeyboardNav") } }
    var staggerRows: Bool { didSet { d.set(staggerRows, forKey: "staggerRows") } }
    var slowMotion: Bool { didSet { d.set(slowMotion, forKey: "slowMotion") } }

    // Performance
    var pollingMode: PollingMode { didSet { d.set(pollingMode.rawValue, forKey: "pollingMode"); onPollingChange?() } }

    // Images, fichiers, texte riche
    var captureImages: Bool { didSet { d.set(captureImages, forKey: "captureImages"); onCaptureOptionsChange?() } }
    var captureFiles: Bool { didSet { d.set(captureFiles, forKey: "captureFiles"); onCaptureOptionsChange?() } }
    var captureRichText: Bool { didSet { d.set(captureRichText, forKey: "captureRichText"); onCaptureOptionsChange?() } }
    var ocrImages: Bool { didSet { d.set(ocrImages, forKey: "ocrImages") } }
    var imageStorage: ImageStorage { didSet { d.set(imageStorage.rawValue, forKey: "imageStorage") } }
    var maxImageMB: Int { didSet { d.set(maxImageMB, forKey: "maxImageMB"); onCaptureOptionsChange?() } }
    var diskQuotaMB: Int { didSet { d.set(diskQuotaMB, forKey: "diskQuotaMB"); onLimitsChange?() } }
    /// Le texte riche se colle sans mise en forme par défaut (⌥↩ inverse).
    var pastePlainByDefault: Bool { didSet { d.set(pastePlainByDefault, forKey: "pastePlainByDefault") } }

    // Statistiques
    var statMerged: Int { didSet { d.set(statMerged, forKey: "statMerged") } }
    var statRestoresSilenced: Int { didSet { d.set(statRestoresSilenced, forKey: "statRestoresSilenced") } }
    var statDictations: Int { didSet { d.set(statDictations, forKey: "statDictations") } }
    var statIgnoredPrivate: Int { didSet { d.set(statIgnoredPrivate, forKey: "statIgnoredPrivate") } }
    var statPastes: Int { didSet { d.set(statPastes, forKey: "statPastes") } }

    var hasLaunchedBefore: Bool { didSet { d.set(hasLaunchedBefore, forKey: "hasLaunchedBefore") } }

    static let knownDictationApps: [(id: String, name: String)] = [
        ("com.prakashjoshipax.VoiceInk", "VoiceInk"),
        ("com.superduper.superwhisper", "superwhisper"),
        ("com.electron.wispr-flow", "Wispr Flow"),
        ("com.goodsnooze.MacWhisper", "MacWhisper"),
        ("com.aquavoice.app", "Aqua Voice"),
        ("com.spokenly.app", "Spokenly"),
    ]

    private init() {
        d.register(defaults: [
            "maxStored": 300, "displayCount": 20, "previewLines": 2, "retentionDays": 0,
            "mergeDuplicates": true, "trimWhitespace": true,
            "smartDictation": true, "dictationWindow": 4.0, "bumpOnRestore": false, "keepDictations": true,
            "dictationApps": Preferences.knownDictationApps.map(\.id),
            "ignoreConcealed": true, "respectTransient": true,
            "excludedApps": ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
                             "com.apple.Passwords", "com.bitwarden.desktop"],
            "paused": false,
            "panelPosition": PanelPosition.textCaret.rawValue, "panelMaterial": PanelMaterial.frosted.rawValue,
            "pasteOnSelect": true, "showShortcutNumbers": true, "playSound": false,
            "hoverPreview": true, "hoverPreviewDelay": 0.7,
            "pollingMode": PollingMode.balanced.rawValue, "captureImages": true,
            "captureFiles": true, "captureRichText": true, "ocrImages": true,
            "imageStorage": ImageStorage.heic.rawValue, "maxImageMB": 40, "diskQuotaMB": 1024,
            "pastePlainByDefault": false,
            "motionStyle": MotionStyle.subtle.rawValue, "animateKeyboardOpen": false,
            "animateKeyboardNav": false, "staggerRows": false, "slowMotion": false,
        ])
        motionStyle = MotionStyle(rawValue: d.string(forKey: "motionStyle") ?? "") ?? .subtle
        animateKeyboardOpen = d.bool(forKey: "animateKeyboardOpen")
        animateKeyboardNav = d.bool(forKey: "animateKeyboardNav")
        staggerRows = d.bool(forKey: "staggerRows")
        slowMotion = d.bool(forKey: "slowMotion")
        maxStored = d.integer(forKey: "maxStored")
        displayCount = d.integer(forKey: "displayCount")
        previewLines = d.integer(forKey: "previewLines")
        retentionDays = d.integer(forKey: "retentionDays")
        mergeDuplicates = d.bool(forKey: "mergeDuplicates")
        trimWhitespaceForDedup = d.bool(forKey: "trimWhitespace")
        smartDictation = d.bool(forKey: "smartDictation")
        dictationWindow = d.double(forKey: "dictationWindow")
        dictationApps = d.stringArray(forKey: "dictationApps") ?? []
        bumpOnRestore = d.bool(forKey: "bumpOnRestore")
        keepDictations = d.bool(forKey: "keepDictations")
        ignoreConcealed = d.bool(forKey: "ignoreConcealed")
        respectTransient = d.bool(forKey: "respectTransient")
        excludedApps = d.stringArray(forKey: "excludedApps") ?? []
        paused = d.bool(forKey: "paused")
        panelPosition = PanelPosition(rawValue: d.string(forKey: "panelPosition") ?? "") ?? .textCaret
        panelMaterial = PanelMaterial(rawValue: d.string(forKey: "panelMaterial") ?? "") ?? .frosted
        pasteOnSelect = d.bool(forKey: "pasteOnSelect")
        showShortcutNumbers = d.bool(forKey: "showShortcutNumbers")
        playSound = d.bool(forKey: "playSound")
        hoverPreview = d.bool(forKey: "hoverPreview")
        hoverPreviewDelay = d.double(forKey: "hoverPreviewDelay")
        if let data = d.data(forKey: "hotKey") {
            hotKey = data.isEmpty ? nil : (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .default
        } else {
            hotKey = .default
        }
        pollingMode = PollingMode(rawValue: d.string(forKey: "pollingMode") ?? "") ?? .balanced
        captureImages = d.bool(forKey: "captureImages")
        captureFiles = d.bool(forKey: "captureFiles")
        captureRichText = d.bool(forKey: "captureRichText")
        ocrImages = d.bool(forKey: "ocrImages")
        imageStorage = ImageStorage(rawValue: d.string(forKey: "imageStorage") ?? "") ?? .heic
        maxImageMB = d.integer(forKey: "maxImageMB")
        diskQuotaMB = d.integer(forKey: "diskQuotaMB")
        pastePlainByDefault = d.bool(forKey: "pastePlainByDefault")
        statMerged = d.integer(forKey: "statMerged")
        statRestoresSilenced = d.integer(forKey: "statRestoresSilenced")
        statDictations = d.integer(forKey: "statDictations")
        statIgnoredPrivate = d.integer(forKey: "statIgnoredPrivate")
        statPastes = d.integer(forKey: "statPastes")
        hasLaunchedBefore = d.bool(forKey: "hasLaunchedBefore")
    }

    var captureOptions: CaptureOptions {
        CaptureOptions(images: captureImages, files: captureFiles, richText: captureRichText,
                       maxImageBytes: max(maxImageMB, 1) * 1_048_576)
    }

    var diskQuotaBytes: Int { max(diskQuotaMB, 50) * 1_048_576 }

    var dedupConfig: DedupConfig {
        DedupConfig(smartDictation: smartDictation, dictationWindow: dictationWindow,
                    dictationApps: Set(dictationApps), bumpOnRestore: bumpOnRestore,
                    keepDictations: keepDictations, mergeDuplicates: mergeDuplicates,
                    ignoreConcealed: ignoreConcealed, respectTransient: respectTransient,
                    excludedApps: Set(excludedApps))
    }
}
