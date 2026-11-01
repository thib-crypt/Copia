import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case welcome, general, panel, animations, history, dictation, privacy, media, performance, importer, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Bienvenue"
        case .general: "Général"
        case .panel: "Panneau"
        case .animations: "Animations"
        case .history: "Historique"
        case .dictation: "Dictée intelligente"
        case .privacy: "Confidentialité"
        case .media: "Images & fichiers"
        case .performance: "Performance"
        case .importer: "Importer"
        case .about: "À propos"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Trois étapes pour remplacer CopyClip."
        case .general: "Raccourci, démarrage et enregistrement."
        case .panel: "Où et comment s'ouvre ton historique."
        case .animations: "Du mouvement là où il aide, rien là où il ralentit."
        case .history: "Combien de copies garder, combien en montrer."
        case .dictation: "Fini les allers-retours de VoiceInk dans l'historique."
        case .privacy: "Ce que Copia ne doit jamais retenir."
        case .media: "Captures d'écran, images et fichiers copiés."
        case .performance: "Réglé pour ton Mac Apple Silicon."
        case .importer: "Récupère ton historique CopyClip."
        case .about: "Ta version personnelle de CopyClip."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .general: "gearshape.fill"
        case .panel: "macwindow"
        case .animations: "wand.and.rays"
        case .history: "clock.arrow.circlepath"
        case .dictation: "waveform"
        case .privacy: "hand.raised.fill"
        case .media: "photo.on.rectangle.angled"
        case .performance: "bolt.fill"
        case .importer: "square.and.arrow.down.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: .purple
        case .general: .gray
        case .panel: .blue
        case .animations: .mint
        case .history: .indigo
        case .dictation: .pink
        case .privacy: .red
        case .media: .green
        case .performance: .orange
        case .importer: .teal
        case .about: .gray
        }
    }

    static let groups: [[SettingsPage]] = [
        [.welcome],
        [.general, .panel, .animations, .history],
        [.dictation, .privacy, .media],
        [.performance, .importer, .about],
    ]
}

@Observable
final class SettingsState {
    var page: SettingsPage = .general
}

/// Tout ce dont les réglages ont besoin.
struct AppContext {
    let prefs: Preferences
    let store: ClipStore
    let coordinator: CaptureCoordinator
    let watcher: PasteboardWatcher
    let state: SettingsState
}

struct SettingsRootView: View {
    let ctx: AppContext
    @Bindable var state: SettingsState

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { state.page }, set: { if let p = $0 { state.page = p } })) {
                ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { page in
                            SidebarRow(page: page).tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 228, ideal: 236, max: 260)
        } detail: {
            ZStack {
                page(state.page)
                    .id(state.page)
                    .transition(.asymmetric(
                        insertion: Motion(prefs: ctx.prefs).reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity.animation(Curve.easeOut(0.1))))
            }
            .animation(Motion(prefs: ctx.prefs).pageChange, value: state.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    @ViewBuilder
    private func page(_ p: SettingsPage) -> some View {
        switch p {
        case .welcome: WelcomePage(ctx: ctx)
        case .general: GeneralPage(ctx: ctx)
        case .panel: PanelPage(prefs: ctx.prefs)
        case .animations: AnimationsPage(prefs: ctx.prefs)
        case .history: HistoryPage(ctx: ctx)
        case .dictation: DictationPage(prefs: ctx.prefs)
        case .privacy: PrivacyPage(prefs: ctx.prefs)
        case .media: MediaPage(prefs: ctx.prefs)
        case .performance: PerformancePage(ctx: ctx)
        case .importer: ImportPage(ctx: ctx)
        case .about: AboutPage(ctx: ctx)
        }
    }
}

struct SidebarRow: View {
    let page: SettingsPage
    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: page.symbol, tint: page.tint, size: 22)
            Text(page.title)
            if page == .media {
                Spacer()
                Text("Bientôt")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 1)
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.18), tint],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: tint.opacity(0.35), radius: size * 0.08, y: size * 0.04)
    }
}

/// Gabarit commun : en-tête « héro » + formulaire groupé natif.
struct SettingsPageScaffold<Content: View>: View {
    let page: SettingsPage
    @ViewBuilder var content: Content
    @State private var appeared = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    IconTile(symbol: page.symbol, tint: page.tint, size: 52)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .rotationEffect(.degrees(appeared ? 0 : -4))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title).font(.system(size: 22, weight: .bold))
                        Text(page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            let m = Motion(prefs: Preferences.shared)
            if m.reduceMotion || Preferences.shared.motionStyle == .instant { appeared = true; return }
            withAnimation(m.delight) { appeared = true }
        }
    }
}

struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(value.formatted())
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Bienvenue

struct WelcomePage: View {
    let ctx: AppContext
    @State private var trusted = Paster.isTrusted
    @State private var importResult: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Les messages de succès commencent par le nombre de copies importées.
    private var importSucceeded: Bool { importResult?.first?.isNumber == true }

    var body: some View {
        SettingsPageScaffold(page: .welcome) {
            Section {
                StepRow(number: 1, done: trusted, title: "Autoriser l'accessibilité",
                        detail: "Pour coller directement au curseur et ouvrir le panneau là où tu écris.") {
                    Button(trusted ? "Autorisé" : "Ouvrir les réglages") {
                        Paster.requestTrust(); Paster.openAccessibilitySettings()
                    }
                    .disabled(trusted)
                }
                StepRow(number: 2, done: importSucceeded, title: "Importer ton historique CopyClip",
                        detail: importResult ?? (CopyClipImporter.isAvailable
                                                 ? "Les copies de CopyClip seront ajoutées, sans doublons."
                                                 : "CopyClip introuvable sur ce Mac.")) {
                    Button("Importer") { importResult = ImportPage.runImport(ctx: ctx) }
                        .disabled(!CopyClipImporter.isAvailable || importSucceeded)
                }
                StepRow(number: 3, done: false, title: "Essayer le raccourci",
                        detail: "Appuie n'importe où pour ouvrir l'historique, tape pour chercher, ↩ pour coller.") {
                    if let hk = ctx.prefs.hotKey {
                        HStack(spacing: 3) { ForEach(hk.symbols, id: \.self) { KeyCap(key: $0) } }
                    }
                }
            }
            Section {
                Label {
                    Text("Quand tout te convient, quitte CopyClip et retire-le des éléments d'ouverture : Copia prend le relais.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                }
            }
        }
        .onReceive(timer) { _ in trusted = Paster.isTrusted }
    }
}

struct StepRow<Accessory: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor)
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.25), value: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Général

struct GeneralPage: View {
    let ctx: AppContext
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var trusted = Paster.isTrusted

    var body: some View {
        @Bindable var prefs = ctx.prefs
        SettingsPageScaffold(page: .general) {
            Section("Raccourci") {
                LabeledContent("Ouvrir l'historique") {
                    HotKeyRecorder(prefs: ctx.prefs)
                }
                if HotKeyCenter.shared.lastRegistrationFailed {
                    Label("Ce raccourci est déjà utilisé par une autre app.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.system(size: 12))
                }
            }
            Section("Démarrage") {
                Toggle("Ouvrir Copia à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v); launchAtLogin = LaunchAtLogin.isEnabled }
            }
            Section("Enregistrement") {
                Toggle(isOn: $prefs.paused) {
                    Text("Mettre en pause l'enregistrement")
                    Text("Copia ignore le presse-papier tant que la pause est active.")
                }
            }
            Section("Permissions") {
                LabeledContent {
                    if trusted {
                        Label("Autorisé", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Button("Autoriser…") { Paster.requestTrust(); Paster.openAccessibilitySettings() }
                    }
                } label: {
                    Text("Accessibilité")
                    Text("Nécessaire pour coller au curseur et repérer le curseur de texte.")
                }
            }
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in trusted = Paster.isTrusted }
    }
}

struct HotKeyRecorder: View {
    let prefs: Preferences
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                HStack(spacing: 3) {
                    if recording {
                        Text("Tape le raccourci…").foregroundStyle(Color.accentColor)
                    } else if let hk = prefs.hotKey {
                        ForEach(hk.symbols, id: \.self) { KeyCap(key: $0) }
                    } else {
                        Text("Aucun").foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 120, minHeight: 22)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: recording ? 1.5 : 0.5))
                .animation(Curve.easeOut(0.15), value: recording)
            }
            .buttonStyle(.plain)
            if prefs.hotKey != nil && !recording {
                Button { prefs.hotKey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help("Supprimer le raccourci")
            }
            if prefs.hotKey != .default && !recording {
                Button("Par défaut") { prefs.hotKey = .default }.controlSize(.small)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if let combo = KeyCombo(event: event) {
                prefs.hotKey = combo
                stop()
                return nil
            }
            NSSound.beep()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeyCenter.shared.register(prefs.hotKey) }
        recording = false
    }
}

// MARK: - Panneau

struct PanelPage: View {
    @Bindable var prefs: Preferences

    var body: some View {
        SettingsPageScaffold(page: .panel) {
            Section("Ouverture") {
                Picker("Position au raccourci", selection: $prefs.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.label).tag($0) }
                }
                Text("« Au curseur de texte » ouvre le panneau juste sous l'endroit où tu écris (repli sur la souris si l'app ne l'expose pas). Le clic sur l'icône de la barre des menus ouvre toujours dessous.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Section("Apparence") {
                Picker("Matériau", selection: $prefs.panelMaterial) {
                    ForEach(PanelMaterial.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper(value: $prefs.previewLines, in: 1...4) {
                    LabeledContent("Lignes d'aperçu par copie", value: "\(prefs.previewLines)")
                }
                Toggle("Afficher les raccourcis ⌘1 … ⌘9", isOn: $prefs.showShortcutNumbers)
            }
            Section("Aperçu au survol") {
                Toggle(isOn: $prefs.hoverPreview.animation(Curve.easeOut(0.2))) {
                    Text("Afficher le contenu complet au survol")
                    Text("Garde le pointeur sur une copie : un grand aperçu s'ouvre à côté du panneau. Tu peux le faire défiler. ⌘Y l'ouvre aussi au clavier.")
                }
                if prefs.hoverPreview {
                    LabeledContent {
                        HStack(spacing: 10) {
                            Slider(value: $prefs.hoverPreviewDelay, in: 0.3...1.5, step: 0.1)
                                .frame(width: 170)
                            Text("\(prefs.hoverPreviewDelay.formatted(.number.precision(.fractionLength(1)))) s")
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    } label: {
                        Text("Délai avant ouverture")
                        Text("Une fois l'aperçu ouvert, passer d'une copie à l'autre est instantané.")
                    }
                }
            }
            Section("Action") {
                Toggle(isOn: $prefs.pasteOnSelect) {
                    Text("Coller directement au curseur")
                    Text("Sinon, ↩ copie seulement. ⌘↩ copie toujours sans coller.")
                }
                Toggle("Son de confirmation discret", isOn: $prefs.playSound)
            }
        }
    }
}

// MARK: - Historique

struct HistoryPage: View {
    let ctx: AppContext
    @State private var confirmClear = false

    private let retentionOptions: [(Int, String)] = [(0, "Illimitée"), (7, "7 jours"), (30, "30 jours"),
                                                     (90, "3 mois"), (365, "1 an")]

    var body: some View {
        @Bindable var prefs = ctx.prefs
        SettingsPageScaffold(page: .history) {
            Section {
                HStack(spacing: 10) {
                    StatTile(value: ctx.store.count, label: "copies en mémoire", symbol: "tray.full.fill", tint: .indigo)
                    StatTile(value: ctx.store.pinnedCount, label: "épinglées", symbol: "pin.fill", tint: .orange)
                    StatTile(value: prefs.statPastes, label: "collages via Copia", symbol: "arrow.down.doc.fill", tint: .blue)
                }
                .animation(Curve.easeOut(0.2), value: ctx.store.count)
            }
            Section("Capacité") {
                LabeledContent {
                    HStack {
                        Slider(value: Binding(get: { Double(prefs.maxStored) },
                                              set: { prefs.maxStored = Int($0 / 50) * 50 }),
                               in: 50...5000)
                            .frame(width: 200)
                        Text("\(prefs.maxStored)").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("Copies conservées")
                    Text("Les épinglées ne comptent pas et ne sont jamais supprimées.")
                }
                Stepper(value: $prefs.displayCount, in: 5...60, step: 5) {
                    LabeledContent {
                        Text("\(prefs.displayCount)").monospacedDigit()
                    } label: {
                        Text("Copies affichées")
                        Text("La recherche porte toujours sur tout l'historique.")
                    }
                }
                Picker("Conservation", selection: $prefs.retentionDays) {
                    ForEach(retentionOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
            Section("Doublons") {
                Toggle(isOn: $prefs.mergeDuplicates) {
                    Text("Fusionner les copies identiques")
                    Text("Un texte déjà présent remonte en haut au lieu d'être ajouté une deuxième fois.")
                }
                Toggle(isOn: $prefs.trimWhitespaceForDedup) {
                    Text("Ignorer les espaces de début et de fin")
                    Text("« Bonjour » et « Bonjour␣» comptent comme une seule copie.")
                }
            }
            Section {
                Button("Effacer l'historique…", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Effacer l'historique ?", isPresented: $confirmClear) {
                        Button("Effacer (garder les épinglées)", role: .destructive) { ctx.store.clear(keepPinned: true) }
                        Button("Tout effacer", role: .destructive) { ctx.store.clear(keepPinned: false) }
                    } message: {
                        Text("Cette action est définitive.")
                    }
            }
        }
    }
}

// MARK: - Dictée intelligente

struct DictationPage: View {
    @Bindable var prefs: Preferences

    var body: some View {
        SettingsPageScaffold(page: .dictation) {
            Section {
                Toggle(isOn: $prefs.smartDictation.animation(Curve.easeOut(0.2))) {
                    Text("Dictée intelligente").font(.system(size: 13, weight: .semibold))
                    Text("Quand ton app de dictée colle la transcription puis remet ton ancien presse-papier, Copia garde la transcription une seule fois et ignore la restauration.")
                }
                DictationDiagram(enabled: prefs.smartDictation)
                    .padding(.vertical, 4)
            }
            if prefs.smartDictation {
                Section {
                    HStack(spacing: 10) {
                        StatTile(value: prefs.statRestoresSilenced, label: "restaurations ignorées",
                                 symbol: "arrow.uturn.backward.circle.fill", tint: .pink)
                        StatTile(value: prefs.statDictations, label: "dictées reconnues", symbol: "waveform", tint: .purple)
                        StatTile(value: prefs.statMerged, label: "doublons fusionnés",
                                 symbol: "square.on.square.fill", tint: .indigo)
                    }
                }
                Section("Comportement") {
                    Toggle(isOn: $prefs.keepDictations) {
                        Text("Garder les transcriptions dans l'historique")
                        Text("Badgées « Dictée » pour les repérer et les filtrer d'un coup d'œil.")
                    }
                    Toggle(isOn: $prefs.bumpOnRestore) {
                        Text("Remonter l'ancien presse-papier après une dictée")
                        Text("Désactivé (recommandé) : la transcription reste en tête de liste.")
                    }
                    LabeledContent {
                        HStack {
                            Slider(value: $prefs.dictationWindow, in: 1...10, step: 0.5).frame(width: 180)
                            Text(prefs.dictationWindow.formatted(.number.precision(.fractionLength(1))) + " s")
                                .monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        Text("Fenêtre de détection")
                        Text("Délai max. entre la transcription et la restauration (A → B → A).")
                    }
                }
                Section("Apps de dictée") {
                    ForEach(Preferences.knownDictationApps, id: \.id) { app in
                        let installed = AppIconCache.shared.isInstalled(app.id)
                        Toggle(isOn: Binding(
                            get: { prefs.dictationApps.contains(app.id) },
                            set: { on in
                                if on { prefs.dictationApps.append(app.id) } else { prefs.dictationApps.removeAll { $0 == app.id } }
                            })) {
                            HStack(spacing: 8) {
                                AppIconImage(bundleID: app.id)
                                Text(app.name)
                                if installed {
                                    Text("installée").font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .opacity(installed ? 1 : 0.55)
                    }
                    ForEach(prefs.dictationApps.filter { id in !Preferences.knownDictationApps.contains { $0.id == id } }, id: \.self) { id in
                        AppListRow(bundleID: id) { prefs.dictationApps.removeAll { $0 == id } }
                    }
                    Button("Ajouter une app…") {
                        if let id = AppPicker.pickBundleID() , !prefs.dictationApps.contains(id) { prefs.dictationApps.append(id) }
                    }
                }
            }
        }
    }
}

/// Petit schéma animé : A → B (dictée) → A (restauration).
struct DictationDiagram: View {
    let enabled: Bool
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            chip("A", "Ton texte", tint: .blue, active: phase >= 0)
            arrow(active: phase >= 1)
            chip("B", "Dictée", tint: .pink, active: phase >= 1)
            arrow(active: phase >= 2)
            ZStack {
                chip("A", enabled ? "Ignoré" : "Doublon", tint: enabled ? .gray : .red, active: phase >= 2)
                    .opacity(enabled && phase >= 2 ? 0.45 : 1)
                if enabled && phase >= 2 {
                    Image(systemName: "line.diagonal")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Historique").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Text(enabled ? "B · A" : "A · B · A")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(enabled ? Color.green : Color.red)
                    .contentTransition(.numericText())
            }
        }
        .animation(Curve.easeOut(0.25), value: phase)
        .animation(Curve.easeOut(0.2), value: enabled)
        .onReceive(timer) { _ in phase = (phase + 1) % 4 }
    }

    private func chip(_ letter: String, _ caption: String, tint: Color, active: Bool) -> some View {
        VStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(active ? 0.9 : 0.15)))
                .foregroundStyle(active ? .white : tint)
                .scaleEffect(active ? 1 : 0.88)
            Text(caption).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
    }

    private func arrow(active: Bool) -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
            .offset(y: -7)
    }
}

// MARK: - Confidentialité

struct PrivacyPage: View {
    @Bindable var prefs: Preferences

    var body: some View {
        SettingsPageScaffold(page: .privacy) {
            Section("Protection automatique") {
                Toggle(isOn: $prefs.ignoreConcealed) {
                    Text("Ignorer les mots de passe")
                    Text("Respecte le marqueur nspasteboard « Concealed » posé par les gestionnaires de mots de passe.")
                }
                Toggle(isOn: $prefs.respectTransient) {
                    Text("Ignorer les contenus temporaires")
                    Text("Respecte le marqueur « Transient » (ex. superwhisper en mode discret).")
                }
                LabeledContent("Éléments ignorés jusqu'ici", value: prefs.statIgnoredPrivate.formatted())
            }
            Section {
                ForEach(prefs.excludedApps, id: \.self) { id in
                    AppListRow(bundleID: id) { prefs.excludedApps.removeAll { $0 == id } }
                }
                Button("Ajouter une app…") {
                    if let id = AppPicker.pickBundleID(), !prefs.excludedApps.contains(id) {
                        withAnimation { prefs.excludedApps.append(id) }
                    }
                }
            } header: {
                Text("Apps exclues")
            } footer: {
                Text("Tout ce qui est copié depuis ces apps n'est jamais enregistré.")
            }
        }
    }
}

struct AppIconImage: View {
    let bundleID: String
    var size: CGFloat = 20
    var body: some View {
        if let icon = AppIconCache.shared.icon(for: bundleID) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").frame(width: size, height: size).foregroundStyle(.tertiary)
        }
    }
}

struct AppListRow: View {
    let bundleID: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            AppIconImage(bundleID: bundleID)
            VStack(alignment: .leading, spacing: 0) {
                Text(AppIconCache.shared.name(for: bundleID))
                Text(bundleID).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: { withAnimation(Curve.easeOut(0.2)) { onRemove() } }) {
                Image(systemName: "minus.circle.fill").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(hovering ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
            .onHover { hovering = $0 }
        }
    }
}

enum AppPicker {
    static func pickBundleID() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

// MARK: - Images & fichiers (phase 2)

struct MediaPage: View {
    @Bindable var prefs: Preferences

    var body: some View {
        SettingsPageScaffold(page: .media) {
            Section {
                Toggle(isOn: .constant(false)) {
                    Text("Enregistrer les images et captures d'écran")
                    Text("Arrive dans la prochaine version.")
                }
                .disabled(true)
            }
            Section("Au programme") {
                RoadmapRow(symbol: "photo", title: "Images & captures", detail: "Stockées en HEIC compressé, miniatures nettes Retina, doublons détectés.")
                RoadmapRow(symbol: "doc", title: "Fichiers du Finder", detail: "Recopie les fichiers copiés, avec leurs icônes.")
                RoadmapRow(symbol: "textformat", title: "Texte riche", detail: "Garde la mise en forme, ⌥↩ pour coller en texte brut.")
                RoadmapRow(symbol: "text.viewfinder", title: "Recherche dans les images", detail: "Le texte des captures (OCR Vision) devient cherchable.")
                RoadmapRow(symbol: "internaldrive", title: "Plafond disque", detail: "Taille maximale réglable, purge automatique des plus anciennes.")
            }
        }
    }
}

struct RoadmapRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.green).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Performance

struct PerformancePage: View {
    let ctx: AppContext
    @State private var memory = ProcessStats.residentMegabytes
    @State private var checks = 0.0

    var body: some View {
        @Bindable var prefs = ctx.prefs
        SettingsPageScaffold(page: .performance) {
            Section {
                HStack(spacing: 10) {
                    MetricTile(value: memory.formatted(.number.precision(.fractionLength(1))), unit: "Mo",
                               label: "mémoire utilisée", tint: .orange)
                    MetricTile(value: checks.formatted(.number.precision(.fractionLength(1))), unit: "/s",
                               label: "vérifications du presse-papier", tint: .yellow)
                    MetricTile(value: "0", unit: "", label: "requête réseau (CopyClip : pubs FIPLAB)", tint: .green)
                }
            }
            Section {
                Picker("Réactivité", selection: $prefs.pollingMode) {
                    ForEach(PollingMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(description(prefs.pollingMode))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            } header: {
                Text("Surveillance")
            }
            Section("Optimisations actives") {
                RoadmapRow(symbol: "moon.zzz.fill", title: "Pause en veille et écran verrouillé",
                           detail: "Aucune activité quand tu n'es pas devant ton Mac.")
                RoadmapRow(symbol: "timer", title: "Réveils regroupés",
                           detail: "Timer à tolérance : macOS peut aligner les réveils de Copia sur les siens.")
                RoadmapRow(symbol: "tortoise.fill", title: "Ralenti automatique",
                           detail: "Après 2 min sans copie, la fréquence diminue jusqu'à la prochaine.")
                RoadmapRow(symbol: "rectangle.dashed", title: "Interface démontée",
                           detail: "Panneau fermé = aucun rendu SwiftUI en arrière-plan.")
                RoadmapRow(symbol: "cpu", title: "Natif Apple Silicon",
                           detail: "Binaire arm64 optimisé, SQLite en WAL, écritures hors du thread principal.")
            }
        }
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        withAnimation(Curve.easeOut(0.2)) {
            memory = ProcessStats.residentMegabytes
            checks = ctx.watcher.checksPerSecond
        }
    }

    private func description(_ m: PollingMode) -> String {
        switch m {
        case .eco: "Vérifie toutes les 0,6 s. Le plus sobre ; une dictée très rapide peut exceptionnellement échapper."
        case .balanced: "Vérifie toutes les 0,3 s. Le meilleur compromis, idéal avec VoiceInk."
        case .instant: "Vérifie toutes les 0,15 s. Pour les enchaînements de copies très rapides."
        }
    }
}

struct MetricTile: View {
    let value: String
    let unit: String
    let label: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.09)))
    }
}

// MARK: - Import

struct ImportPage: View {
    let ctx: AppContext
    @State private var result: String?
    @State private var running = false

    var body: some View {
        SettingsPageScaffold(page: .importer) {
            Section {
                LabeledContent {
                    if CopyClipImporter.isAvailable {
                        Label("Trouvé", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Introuvable", systemImage: "xmark.circle").foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 8) {
                        AppIconImage(bundleID: "com.fiplab.clipboard", size: 26)
                        VStack(alignment: .leading) {
                            Text("CopyClip")
                            Text("Lecture seule : ses fichiers ne sont jamais modifiés.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    if let result {
                        Label(result, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            .transition(.opacity.combined(with: .offset(x: -6)))
                    }
                    Spacer()
                    Button {
                        running = true
                        withAnimation(Curve.easeOut(0.22)) { result = Self.runImport(ctx: ctx) }
                        running = false
                    } label: {
                        if running { ProgressView().controlSize(.small) } else { Text("Importer l'historique") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!CopyClipImporter.isAvailable || running)
                }
            }
        }
    }

    static func runImport(ctx: AppContext) -> String {
        do {
            let entries: [CopyClipImporter.Entry]
            do {
                entries = try CopyClipImporter.readEntries()
            } catch CopyClipImporter.ImportError.accessDenied {
                // macOS exige que l'utilisateur désigne lui-même le dossier d'une autre app.
                guard let folder = pickCopyClipFolder() else { return "Import annulé." }
                entries = try CopyClipImporter.readEntries(from: folder)
            }
            let added = ctx.store.importClips(entries, trimWhitespace: ctx.prefs.trimWhitespaceForDedup)
            ctx.store.enforceLimits(maxItems: ctx.prefs.maxStored, retentionDays: ctx.prefs.retentionDays)
            let skipped = entries.count - added
            return "\(added) copies importées" + (skipped > 0 ? " · \(skipped) doublons ignorés" : "")
        } catch {
            return "Échec : \(error.localizedDescription)"
        }
    }

    private static func pickCopyClipFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Autoriser l'accès à CopyClip"
        panel.message = "macOS protège les données de CopyClip. Clique simplement sur « Autoriser » : le dossier est déjà sélectionné."
        panel.prompt = "Autoriser"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        let folder = CopyClipImporter.databaseURL.deletingLastPathComponent()
        panel.directoryURL = folder.deletingLastPathComponent()
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        // Accepte le dossier ou directement le fichier copyclip.sqlite.
        return url.pathExtension == "sqlite" ? url.deletingLastPathComponent() : url
    }
}

// MARK: - À propos

struct AboutPage: View {
    let ctx: AppContext
    @State private var spin = false

    var body: some View {
        SettingsPageScaffold(page: .about) {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 72, height: 72)
                        .rotation3DEffect(.degrees(spin ? 360 : 0), axis: (x: 0, y: 1, z: 0))
                        .onTapGesture { withAnimation(.spring(duration: 0.9, bounce: 0.2)) { spin.toggle() } }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Copia").font(.system(size: 20, weight: .bold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .foregroundStyle(.secondary)
                        Text("Natif Swift · zéro dépendance · zéro réseau").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Raccourcis du panneau") {
                ShortcutRow(keys: ["↑", "↓"], label: "Naviguer")
                ShortcutRow(keys: ["↩"], label: "Coller au curseur")
                ShortcutRow(keys: ["⌘", "↩"], label: "Copier sans coller")
                ShortcutRow(keys: ["⌘", "1…9"], label: "Coller la copie n°1 à 9")
                ShortcutRow(keys: ["⌘", "Y"], label: "Aperçu du contenu complet")
                ShortcutRow(keys: ["⌘", "P"], label: "Épingler / désépingler")
                ShortcutRow(keys: ["⌘", "⌫"], label: "Supprimer")
                ShortcutRow(keys: ["⎋"], label: "Effacer la recherche, puis fermer")
            }
            Section("Données") {
                LabeledContent("Emplacement") {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClipDatabase.defaultURL])
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

struct ShortcutRow: View {
    let keys: [String]
    let label: String
    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 3) { ForEach(keys, id: \.self) { KeyCap(key: $0) } }
        }
    }
}
