import SwiftUI
import AppKit

enum MotionStyle: String, CaseIterable, Identifiable {
    case instant, subtle, expressive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .instant: "Instantané"
        case .subtle: "Sobre"
        case .expressive: "Expressif"
        }
    }
    var detail: String {
        switch self {
        case .instant: "Aucune animation, comme Raycast. Le plus rapide pour un outil utilisé 100 fois par jour."
        case .subtle: "Fondu + léger zoom depuis le curseur, 180 ms, sans rebond. Les actions au clavier restent instantanées."
        case .expressive: "Ressort doux, cascade des lignes, flou de transition. Pour le plaisir des yeux."
        }
    }
}

/// Courbes personnalisées : les courbes système manquent de nerf.
enum Curve {
    /// Ease-out fort : entrées, sorties, retours de pression.
    static func easeOut(_ d: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: d) }
    /// Ease-in-out fort : déplacements à l'écran.
    static func easeInOut(_ d: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: d) }
    /// Changement de couleur / survol.
    static func ease(_ d: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: d) }
}

/// Toutes les décisions de mouvement au même endroit.
/// Règles : jamais d'animation pour une action clavier répétée, ease-out pour entrer/sortir,
/// sortie plus rapide que l'entrée, < 300 ms, jamais depuis scale(0), origine = déclencheur.
struct Motion {
    let prefs: Preferences

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var k: Double { prefs.slowMotion ? 5 : 1 }
    private var style: MotionStyle { prefs.motionStyle }

    // MARK: Panneau

    func panelEnter(byKeyboard: Bool) -> Animation? {
        if style == .instant || (byKeyboard && !prefs.animateKeyboardOpen) { return nil }
        if reduceMotion { return Curve.ease(0.15 * k) }
        return style == .expressive ? .spring(duration: 0.28 * k, bounce: 0.12) : Curve.easeOut(0.18 * k)
    }

    /// Sortie toujours plus rapide que l'entrée ; instantanée après une action clavier.
    func panelExit(byKeyboard: Bool) -> (Animation?, TimeInterval) {
        if style == .instant || (byKeyboard && !prefs.animateKeyboardOpen) { return (nil, 0) }
        let d = (style == .expressive ? 0.14 : 0.12) * k
        return (reduceMotion ? Curve.ease(d) : Curve.easeOut(d), d)
    }

    var enterScale: CGFloat {
        if reduceMotion { return 1 }
        return style == .expressive ? 0.95 : 0.97
    }
    var enterOffset: CGFloat {
        if reduceMotion { return 0 }
        return style == .expressive ? 8 : 4
    }
    var enterBlur: CGFloat {
        if reduceMotion { return 0 }
        return style == .expressive ? 4 : 2
    }

    // MARK: Liste

    var stagger: Bool { prefs.staggerRows && style != .instant && !reduceMotion }

    func rowEnter(index: Int) -> Animation? {
        guard stagger else { return nil }
        return Curve.easeOut(0.22 * k).delay(Double(min(index, 8)) * 0.03 * k)
    }

    /// Navigation ↑↓ : instantanée sauf demande explicite.
    var keyboardSelection: Animation? {
        guard prefs.animateKeyboardNav, style != .instant else { return nil }
        return reduceMotion ? nil : Curve.easeOut(0.12 * k)
    }

    /// Survol : instantané (des dizaines de fois par jour).
    var hoverSelection: Animation? { nil }

    /// Épingler / supprimer : évite un saut brutal de la liste.
    var listChange: Animation? {
        guard style != .instant else { return nil }
        return reduceMotion ? Curve.ease(0.15 * k) : Curve.easeOut(0.2 * k)
    }

    /// Petits éléments (bouton effacer, badges).
    var micro: Animation? {
        guard style != .instant else { return nil }
        return Curve.easeOut(0.15 * k)
    }

    // MARK: Aperçu au survol (une infobulle)

    /// 150 ms ease-out pour le premier ; les suivants s'affichent sans animation.
    var previewEnter: Animation? {
        guard style != .instant else { return nil }
        return reduceMotion ? Curve.ease(0.12 * k) : Curve.easeOut(0.15 * k)
    }
    var previewExit: (Animation?, TimeInterval) {
        guard style != .instant else { return (nil, 0) }
        let d = 0.1 * k
        return (reduceMotion ? Curve.ease(d) : Curve.easeOut(d), d)
    }
    var previewScale: CGFloat { reduceMotion ? 1 : 0.97 }

    // MARK: Réglages (rares : un peu de plaisir permis)

    var pageChange: Animation {
        reduceMotion ? Curve.ease(0.15 * k) : Curve.easeOut(0.22 * k)
    }
    var delight: Animation {
        reduceMotion ? Curve.ease(0.15 * k) : .spring(duration: 0.3 * k, bounce: 0.2)
    }
}

/// Retour de pression subtil (0.97) pour tout élément cliquable.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Curve.easeOut(0.12), value: configuration.isPressed)
    }
}
