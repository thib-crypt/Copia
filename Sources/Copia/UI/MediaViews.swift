import AppKit
import SwiftUI
import QuickLookThumbnailing

// MARK: - Miniatures (cache)

/// Miniatures des images et des fichiers, chargées hors du thread principal et gardées en cache.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 300 }

    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    static func key(for item: ClipItem, size: CGFloat) -> String {
        "\(item.id)|\(item.meta.thumb ?? item.text.prefix(200).description)|\(Int(size))"
    }

    func load(for item: ClipItem, size: CGFloat) async -> NSImage? {
        let key = Self.key(for: item, size: size)
        if let img = cached(key) { return img }
        let img: NSImage?
        switch item.kind {
        case .image:
            guard let thumb = item.meta.thumb else { return nil }
            img = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: BlobStore.url(thumb)) }.value
        case .fileURL:
            guard let url = item.fileURLs.first else { return nil }
            img = await Self.fileThumbnail(url, size: size)
        default:
            return nil
        }
        if let img { cache.setObject(img, forKey: key as NSString) }
        return img
    }

    /// Aperçu Quick Look du fichier (image, PDF, vidéo…), sinon son icône Finder.
    static func fileThumbnail(_ url: URL, size: CGFloat) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: 2, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func icon(for url: URL) -> NSImage {
        if FileManager.default.fileExists(atPath: url.path) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .data)
    }
}

// MARK: - Visuel de tête de ligne

/// Icône de l'app source (texte), miniature (image) ou icône Quick Look (fichiers).
struct ClipLeadingView: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        switch item.kind {
        case .text, .richText:
            SourceIcon(item: item, isSelected: isSelected)
        case .image:
            ImageThumb(item: item, isSelected: isSelected)
        case .fileURL:
            FileThumb(item: item)
        }
    }
}

private struct ImageThumb: View {
    let item: ClipItem
    let isSelected: Bool
    @State private var image: NSImage?

    private let size: CGFloat = 40
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }

    var body: some View {
        ZStack {
            // Damier discret : les images transparentes restent lisibles.
            shape.fill(.primary.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .transition(.opacity)
            } else {
                Image(systemName: item.meta.processing == true ? "hourglass" : "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                    .symbolEffect(.pulse, isActive: item.meta.processing == true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(isSelected ? 0.45 : 0), lineWidth: 1))
        .overlay(shape.strokeBorder(.primary.opacity(isSelected ? 0 : 0.10), lineWidth: 0.5))
        .task(id: ThumbnailCache.key(for: item, size: 80)) {
            if let cached = ThumbnailCache.shared.cached(ThumbnailCache.key(for: item, size: 80)) {
                image = cached
                return
            }
            let img = await ThumbnailCache.shared.load(for: item, size: 80)
            withAnimation(Curve.easeOut(0.18)) { image = img }
        }
    }
}

private struct FileThumb: View {
    let item: ClipItem
    @State private var image: NSImage?

    var body: some View {
        let urls = item.fileURLs
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: image ?? urls.first.map(ThumbnailCache.icon(for:)) ?? NSWorkspace.shared.icon(for: .data))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
            if urls.count > 1 {
                Text("\(urls.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(Color.accentColor))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    .offset(x: 4, y: 3)
            }
        }
        .frame(width: 40, height: 32) // même colonne que les miniatures d'images
        .task(id: ThumbnailCache.key(for: item, size: 64)) {
            image = await ThumbnailCache.shared.load(for: item, size: 64)
        }
    }
}

// MARK: - Badge

struct KindBadge: View {
    let label: String
    let symbol: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(isSelected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Texte riche (lecture seule)

struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSTextView {
        let v = NSTextView()
        v.isEditable = false
        v.isSelectable = false
        v.drawsBackground = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = false
        v.textStorage?.setAttributedString(text)
        return v
    }

    func updateNSView(_ v: NSTextView, context: Context) {
        if v.textStorage?.isEqual(to: text) == false { v.textStorage?.setAttributedString(text) }
    }
}

enum RichText {
    /// Reconstruit la mise en forme à partir des représentations conservées.
    static func attributed(for item: ClipItem) -> NSAttributedString? {
        guard item.kind == .richText, let payload = BlobStore.readRich(item.blobPath) else { return nil }
        if let rtfd = payload[ContentClassifier.rtfd], let a = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
            return a
        }
        if let rtf = payload[ContentClassifier.rtf], let a = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return a
        }
        // Le HTML passe par WebKit (plus lent) : on se limite aux extraits raisonnables.
        if let html = payload[ContentClassifier.html], html.count < 400_000,
           let a = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                 .characterEncoding: String.Encoding.utf8.rawValue],
                                           documentAttributes: nil) {
            return a
        }
        return nil
    }

    static func formatLabel(_ item: ClipItem) -> String {
        let types = item.meta.richTypes ?? []
        if types.contains(ContentClassifier.rtfd) { return "RTFD" }
        if types.contains(ContentClassifier.rtf) { return "RTF" }
        if types.contains(ContentClassifier.html) { return "HTML" }
        return "riche"
    }
}

// MARK: - Formats

enum Bytes {
    static func string(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

extension String {
    /// Chemin raccourci façon Finder : ~/Documents/…
    var abbreviatedPath: String { (self as NSString).abbreviatingWithTildeInPath }
}
