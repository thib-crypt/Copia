import SwiftUI
import AppKit

struct AnimationsPage: View {
    @Bindable var prefs: Preferences

    var body: some View {
        let motion = Motion(prefs: prefs)
        SettingsPageScaffold(page: .animations) {
            Section {
                MotionPreview(prefs: prefs)
                    .frame(height: 210)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Picker("Style", selection: $prefs.motionStyle) {
                    ForEach(MotionStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(prefs.motionStyle.detail)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            } header: {
                Text("Style de mouvement")
            }
            if prefs.motionStyle != .instant {
                Section {
                    Toggle(isOn: $prefs.animateKeyboardOpen) {
                        Text("Animer l'ouverture au raccourci clavier")
                        Text("Désactivé (recommandé) : un geste répété 100 fois par jour doit être instantané. Le clic sur l'icône reste animé.")
                    }
                    Toggle(isOn: $prefs.animateKeyboardNav) {
                        Text("Animer la navigation ↑ ↓")
                        Text("Désactivé (recommandé) : la sélection suit tes touches sans aucun retard.")
                    }
                    Toggle(isOn: $prefs.staggerRows) {
                        Text("Cascade des lignes à l'ouverture")
                        Text("Décoratif : 30 ms entre chaque ligne, uniquement quand l'ouverture est animée.")
                    }
                } header: {
                    Text("Où animer")
                }
            }
            Section {
                LabeledContent {
                    if motion.reduceMotion {
                        Label("Actif", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Inactif").foregroundStyle(.secondary)
                    }
                } label: {
                    Text("« Réduire les animations » de macOS")
                    Text("Toujours respecté : fondus seulement, ni zoom, ni déplacement, ni cascade.")
                }
                Button("Ouvrir les réglages d'accessibilité…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            } header: {
                Text("Accessibilité")
            }
            Section {
                Toggle(isOn: $prefs.slowMotion) {
                    Text("Ralenti ×5")
                    Text("Pour examiner chaque transition image par image. Pense à le désactiver ensuite.")
                }
            } header: {
                Text("Atelier")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Principes appliqués : jamais d'animation sur une action clavier répétée · ease-out fort (0.23, 1, 0.32, 1) · moins de 300 ms · sortie plus rapide que l'entrée · jamais depuis zéro (≥ 0,95) · le panneau grandit depuis le curseur.")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Mini-bureau qui rejoue l'ouverture du panneau avec les réglages en cours.
private struct MotionPreview: View {
    let prefs: Preferences
    @State private var shown = true
    @State private var animatedOpen = false
    @State private var selected = 0
    @State private var lastTrigger = "clic"

    private var motion: Motion { Motion(prefs: prefs) }
    private let rows = ["Réunion déplacée à 15 h", "npm run ota:hotfix", "La transcription audio est prête", "thibault@exemple.fr"]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color.mint.opacity(0.18), Color.indigo.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Le déclencheur : un curseur de texte.
                HStack(spacing: 2) {
                    Text("Bonjour,").font(.system(size: 12)).foregroundStyle(.secondary)
                    Rectangle().fill(Color.accentColor).frame(width: 1.5, height: 14)
                }
                .padding(.leading, 28).padding(.top, 14)

                miniPanel
                    .padding(.leading, 40).padding(.top, 36)
            }
            .clipped()
            HStack(spacing: 8) {
                Button { replay(byKeyboard: false) } label: { Label("Rejouer au clic", systemImage: "cursorarrow.click") }
                Button { replay(byKeyboard: true) } label: { Label("Rejouer au raccourci", systemImage: "keyboard") }
                Spacer()
                Text("Dernier : \(lastTrigger)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .controlSize(.small)
            .buttonStyle(PressableStyle())
            .padding(10)
            .background(.background.opacity(0.6))
        }
    }

    private var cascade: Bool { motion.stagger && animatedOpen }

    private var miniPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text("Rechercher…").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 26)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                Text(r)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(i == selected ? Color.white : Color.primary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if i == selected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor)
                        }
                    }
                    .opacity(!cascade || shown ? 1 : 0)
                    .offset(y: !cascade || shown ? 0 : 6)
                    .animation(cascade ? motion.rowEnter(index: i) : nil, value: shown)
            }
        }
        .padding(5)
        .frame(width: 250)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .scaleEffect(shown ? 1 : motion.enterScale, anchor: UnitPoint(x: 0.12, y: 0))
        .offset(y: shown ? 0 : -motion.enterOffset)
        .opacity(shown ? 1 : 0)
        .blur(radius: shown ? 0 : motion.enterBlur)
        .onTapGesture { selected = (selected + 1) % rows.count }
    }

    private func replay(byKeyboard: Bool) {
        lastTrigger = byKeyboard ? "raccourci" : "clic"
        let (exit, exitDuration) = motion.panelExit(byKeyboard: byKeyboard)
        withAnimation(exit) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration + 0.35) {
            let enter = motion.panelEnter(byKeyboard: byKeyboard)
            animatedOpen = enter != nil
            if let enter { withAnimation(enter) { shown = true } } else { shown = true }
        }
    }
}
