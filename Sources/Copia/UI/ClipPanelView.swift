import SwiftUI
import AppKit

struct ClipPanelView: View {
    @Bindable var model: PanelModel
    let prefs: Preferences
    let coordinator: CaptureCoordinator
    let controller: PanelController

    @FocusState private var searchFocused: Bool
    @Namespace private var selectionNS

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    private var motion: Motion { Motion(prefs: prefs) }

    var body: some View {
        ZStack {
            if model.isMounted {
                // Entrée : depuis le déclencheur, jamais depuis scale(0) ; « Réduire les animations » = fondu seul.
                card
                    .scaleEffect(model.isPresented ? 1 : motion.enterScale, anchor: model.anchor)
                    .offset(y: model.isPresented ? 0 : -motion.enterOffset * model.enterDirection)
                    .opacity(model.isPresented ? 1 : 0)
                    .blur(radius: model.isPresented ? 0 : motion.enterBlur)
            }
        }
        .frame(width: PanelController.windowSize.width, height: PanelController.windowSize.height)
    }

    // MARK: - Carte

    private var card: some View {
        styled(
            VStack(spacing: 0) {
                header
                if model.hasMedia { filterBar }
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                content
                if model.needsAccessibility { accessibilityBanner }
                footer
            }
        )
        .frame(width: PanelController.cardSize.width, height: PanelController.cardSize.height)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
        // Ombre contenue dans la marge de la fenêtre (28 pt) : jamais coupée, donc jamais carrée.
        .shadow(color: .black.opacity(0.16), radius: 9, y: 5)
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

    // MARK: - En-tête / recherche

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.query.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))

            TextField("", text: $model.query,
                      prompt: Text(model.totalCount > 1 ? "Rechercher parmi \(model.totalCount) copies…" : "Rechercher…"))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)

            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if prefs.paused {
                Label("En pause", systemImage: "pause.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }

            Button { controller.openSettings() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .help("Réglages (⌘,)")
        }
        .padding(.leading, 18).padding(.trailing, 12)
        .frame(height: 56)
        .animation(motion.micro, value: model.query.isEmpty)
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    // MARK: - Filtres

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(KindFilter.allCases) { f in
                let active = model.filter == f
                Button { withAnimation(motion.micro) { model.filter = f } } label: {
                    Label(f.label, systemImage: f.symbol)
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .padding(.horizontal, 9).frame(height: 22)
                        .background {
                            if active {
                                Capsule().fill(Color.accentColor.opacity(0.16))
                                    .matchedGeometryEffect(id: "filter", in: selectionNS)
                            }
                        }
                        .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) { KeyCap(key: "⌘"); KeyCap(key: "←"); KeyCap(key: "→") }
                .foregroundStyle(.tertiary)
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    // MARK: - Liste

    @ViewBuilder
    private var content: some View {
        if model.flat.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if !model.pinned.isEmpty {
                            SectionLabel(title: "Épinglés", systemImage: "pin.fill")
                            ForEach(Array(model.pinned.enumerated()), id: \.element.id) { i, row in
                                rowView(row, index: i)
                            }
                        }
                        if !model.rows.isEmpty {
                            SectionLabel(title: sectionTitle,
                                         systemImage: model.query.isEmpty ? "clock" : "sparkle.magnifyingglass")
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                                rowView(row, index: model.pinned.count + i)
                            }
                        }
                        if model.hiddenCount > 0 {
                            Text("\(model.hiddenCount) autres copies dans l'historique — tapez pour les retrouver")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedID) { _, id in
                    guard let id, model.keyboardDriven else { return }
                    withAnimation(motion.keyboardSelection) { proxy.scrollTo(id) }
                }
                .onChange(of: model.query) { _, _ in
                    if let first = model.flat.first?.id { proxy.scrollTo(first, anchor: .top) }
                }
            }
        }
    }

    private var cascade: Bool { motion.stagger && model.animatedOpen }

    private var sectionTitle: String {
        if model.query.isEmpty { return "Récents" }
        return model.rows.count == 1 ? "1 résultat" : "\(model.rows.count) résultats"
    }

    private func rowView(_ row: RowData, index: Int) -> some View {
        ClipRowView(row: row,
                    index: index,
                    isSelected: model.selectedID == row.id,
                    isCurrent: row.item.hash == coordinator.currentHash,
                    terms: model.highlightTerms,
                    lines: prefs.previewLines,
                    showNumber: prefs.showShortcutNumbers && index < 9,
                    namespace: selectionNS)
            .id(row.id)
            // Cascade optionnelle (décorative, désactivée par défaut).
            .opacity(!cascade || model.isPresented ? 1 : 0)
            .offset(y: !cascade || model.isPresented ? 0 : 6)
            .animation(cascade ? motion.rowEnter(index: index) : nil, value: model.isPresented)
            .onTapGesture { controller.activate(row.id, copyOnly: false, plain: NSEvent.modifierFlags.contains(.option)) }
            .onDrag { controller.dragProvider(row.id) }
            .onContinuousHover { phase in
                switch phase {
                case .active: controller.hoverSelect(row.id)
                case .ended: controller.hoverEnded()
                }
            }
            .contextMenu {
                Button(prefs.pasteOnSelect ? "Coller" : "Copier") { controller.activate(row.id, copyOnly: false) }
                Button("Copier seulement") { controller.activate(row.id, copyOnly: true) }
                switch row.item.kind {
                case .richText:
                    Button(prefs.pastePlainByDefault ? "Coller avec la mise en forme" : "Coller en texte brut") {
                        controller.activate(row.id, copyOnly: false, plain: true)
                    }
                case .image:
                    if row.item.hasPlainText {
                        Button("Copier le texte reconnu") { controller.activate(row.id, copyOnly: true, plain: true) }
                    }
                    Button("Ouvrir dans Aperçu") { controller.open(row.id) }
                    Button("Afficher dans le Finder") { controller.reveal(row.id) }
                case .fileURL:
                    Button("Coller les chemins") { controller.activate(row.id, copyOnly: false, plain: true) }
                    Button("Ouvrir") { controller.open(row.id) }
                    Button("Afficher dans le Finder") { controller.reveal(row.id) }
                case .text:
                    EmptyView()
                }
                Divider()
                Button(row.item.pinned ? "Désépingler" : "Épingler") { controller.togglePin(row.id) }
                Button("Supprimer", role: .destructive) { controller.delete(row.id) }
            }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: !model.query.isEmpty ? "text.magnifyingglass" : model.filter == .all ? "doc.on.clipboard" : model.filter.symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(!model.query.isEmpty ? "Aucun résultat" : model.filter == .all ? "Ton historique est vide" : "Rien dans « \(model.filter.label) »")
                .font(.system(size: 14, weight: .semibold))
            Text(model.query.isEmpty
                 ? "Copie du texte, une image ou des fichiers : ils apparaîtront ici."
                 : "Rien ne ressemble à « \(model.query) ».")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .transition(.opacity)
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Autorise l'accessibilité pour coller automatiquement.")
                .font(.system(size: 11.5))
            Spacer()
            Button("Autoriser") { controller.requestAccessibility() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
    }

    // MARK: - Pied

    /// Raccourci utile pour la sélection : ⌥↩ sur du texte riche, des fichiers ou une image lisible.
    @ViewBuilder
    private var contextualHint: some View {
        let item = model.flat.first { $0.id == model.selectedID }?.item
        switch item?.kind {
        case .richText: KeyHint(keys: ["⌥", "↩"], label: prefs.pastePlainByDefault ? "Mis en forme" : "Texte brut")
        case .fileURL: KeyHint(keys: ["⌘", "R"], label: "Finder")
        case .image: KeyHint(keys: ["⌘", "O"], label: "Ouvrir")
        default: KeyHint(keys: ["⌘", "P"], label: "Épingler")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            KeyHint(keys: ["↩"], label: prefs.pasteOnSelect ? "Coller" : "Copier")
            KeyHint(keys: ["⌘", "↩"], label: "Copier")
            contextualHint
            KeyHint(keys: ["⌘", "Y"], label: "Aperçu")
            Spacer(minLength: 0)
            Text("\(model.flat.count) / \(model.totalCount)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .fixedSize()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.primary.opacity(0.035))
    }
}

// MARK: - Ligne

struct ClipRowView: View {
    let row: RowData
    let index: Int
    let isSelected: Bool
    let isCurrent: Bool
    let terms: [String]
    let lines: Int
    let showNumber: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ClipLeadingView(item: row.item, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 3) {
                Text(attributedText)
                    .font(.system(size: 13, weight: isMedia ? .medium : .regular))
                    .lineLimit(isMedia ? 1 : lines)
                    .truncationMode(isMedia ? .middle : .tail)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                if let detail = row.detail, !detail.isEmpty {
                    Text(highlight(detail, size: 11.5))
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(row.item.kind == .fileURL ? .head : .tail)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
                metaLine
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                if row.item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .rotationEffect(.degrees(40))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(Color.orange))
                }
                if showNumber {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.84)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var isMedia: Bool { row.item.kind == .image || row.item.kind == .fileURL }

    private var filesMissing: Bool {
        row.item.kind == .fileURL && !row.item.fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var metaLine: some View {
        HStack(spacing: 5) {
            switch row.item.kind {
            case .richText:
                KindBadge(label: "Mis en forme", symbol: "textformat", tint: .purple, isSelected: isSelected)
            case .image where row.item.meta.hasOCR == true && row.detail == nil:
                KindBadge(label: "Texte", symbol: "text.viewfinder", tint: .teal, isSelected: isSelected)
            case .fileURL where filesMissing:
                KindBadge(label: "Introuvable", symbol: "exclamationmark.triangle.fill", tint: .red, isSelected: isSelected)
            default:
                EmptyView()
            }
            if row.item.isDictation {
                Label("Dictée", systemImage: "waveform")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(isSelected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(Color.pink.opacity(0.14)),
                                in: Capsule())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.pink))
            }
            if isCurrent {
                HStack(spacing: 3) {
                    Circle().fill(isSelected ? Color.white : Color.green).frame(width: 5, height: 5)
                    Text("Actuel")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.green))
            }
            Text(metaText)
                .font(.system(size: 10.5))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.78)) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }

    private var metaText: String {
        var parts = [RelativeTime.string(for: row.item.lastCopiedAt)]
        if let app = row.item.sourceAppName, !app.isEmpty { parts.append(app) }
        if row.item.copyCount > 1 { parts.append("×\(row.item.copyCount)") }
        switch row.item.kind {
        case .text, .richText:
            let n = row.item.text.count
            if n > 280 { parts.append(n >= 10_000 ? "\(n / 1000) k car." : "\(n.formatted()) car.") }
        case .image:
            if let b = row.item.meta.bytes { parts.append(Bytes.string(b)) }
        case .fileURL:
            break
        }
        return parts.joined(separator: " · ")
    }

    private var attributedText: AttributedString { highlight(row.display, size: 13) }

    private func highlight(_ s: String, size: CGFloat) -> AttributedString {
        var a = AttributedString(s)
        guard !terms.isEmpty else { return a }
        for t in terms where !t.isEmpty {
            var searchRange = s.startIndex..<s.endIndex
            while let r = s.range(of: t, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let ar = Range(r, in: a) {
                    a[ar].backgroundColor = isSelected ? Color.white.opacity(0.28) : Color.yellow.opacity(0.38)
                    a[ar].font = .system(size: size, weight: .semibold)
                }
                searchRange = r.upperBound..<s.endIndex
            }
        }
        return a
    }
}

struct SourceIcon: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.primary.opacity(0.08)))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    }
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Petits composants

struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .contentTransition(.numericText())
    }
}

struct KeyCap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) { ForEach(keys, id: \.self) { KeyCap(key: $0) } }
            Text(label)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.08 : 0))))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Curve.ease(0.15), value: hovering)
            .animation(Curve.easeOut(0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

enum RelativeTime {
    static func string(for date: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(date)
        switch s {
        case ..<45: return "à l'instant"
        case ..<3_600: return "il y a \(Int(s / 60) == 0 ? 1 : Int(s / 60)) min"
        case ..<86_400: return "il y a \(Int(s / 3_600)) h"
        default:
            if Calendar.current.isDateInYesterday(date) { return "hier" }
            let days = Int(s / 86_400)
            if days < 7 { return "il y a \(days) j" }
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}
