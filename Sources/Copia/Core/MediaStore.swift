import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

nonisolated enum ImageStorage: String, CaseIterable, Identifiable, Sendable {
    case heic, original
    var id: String { rawValue }
    var label: String { self == .heic ? "Optimisé (HEIC)" : "Original (sans perte)" }
}

/// Fichiers binaires des copies (images, miniatures, texte riche) dans
/// `~/Library/Application Support/Copia/Blobs`. Tout est appelable hors du thread principal.
nonisolated enum BlobStore {
    static let directory: URL = {
        let dir = ClipDatabase.defaultURL.deletingLastPathComponent().appendingPathComponent("Blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let io = DispatchQueue(label: "com.thibault.copia.blobs", qos: .utility)

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func exists(_ name: String?) -> Bool {
        guard let name else { return false }
        return FileManager.default.fileExists(atPath: url(name).path)
    }

    static func newName(ext: String) -> String { UUID().uuidString.lowercased() + "." + ext }

    @discardableResult
    static func write(_ data: Data, name: String) -> Bool {
        do { try data.write(to: url(name), options: .atomic); return true }
        catch { NSLog("Copia: écriture blob \(name) — \(error.localizedDescription)"); return false }
    }

    static func read(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: url(name), options: .mappedIfSafe)
    }

    static func remove(_ names: [String]) {
        guard !names.isEmpty else { return }
        io.async {
            for n in names where !n.isEmpty && !n.contains("/") { try? FileManager.default.removeItem(at: url(n)) }
        }
    }

    /// Supprime les fichiers qui ne sont plus référencés (crash, ancienne version…).
    static func sweep(keeping referenced: Set<String>) {
        io.async {
            let fm = FileManager.default
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
            for n in names where !referenced.contains(n) && !n.hasPrefix(".") {
                try? fm.removeItem(at: url(n))
            }
        }
    }

    static func size(_ name: String?) -> Int {
        guard let name, let v = try? url(name).resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return v.fileSize ?? 0
    }

    // MARK: - Texte riche

    /// Les représentations riches (RTF, RTFD, HTML) dans un seul fichier plist.
    static func encodeRich(_ payload: [String: Data]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
    }

    static func readRich(_ name: String?) -> [String: Data]? {
        guard let data = read(name),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data]
        else { return nil }
        return obj
    }
}

/// Traitement d'une image copiée : stockage compressé, miniature Retina, OCR.
nonisolated enum ImageProcessor {
    struct Result: Sendable {
        var meta: ClipMeta
        var blobName: String
    }

    static let thumbPixels = 240
    static let ocrMaxPixels = 2_600

    /// Encode et range l'image (rapide). L'OCR se fait à part, avec `recognizeText(blob:)`.
    static func process(data: Data, sourceType: String, storage: ImageStorage) -> Result? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        var w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) { swap(&w, &h) }
        guard w > 0, h > 0 else { return nil }

        // 1. Fichier principal.
        let srcExt = ContentClassifier.fileExtension(forImageType: sourceType)
        var stored: Data = data
        var ext = srcExt
        switch (storage, srcExt) {
        case (_, "gif"), (_, "jpg"), (_, "heic"):
            break // déjà compressé (ou animé) : on garde tel quel
        case (.original, "tiff"):
            if let png = encode(src, type: .png) { stored = png; ext = "png" }
        case (.original, _):
            break
        case (.heic, _):
            if let heic = encode(src, type: .heic, quality: 0.9), heic.count < data.count {
                stored = heic; ext = "heic"
            } else if srcExt == "tiff", let png = encode(src, type: .png) {
                stored = png; ext = "png"
            }
        }
        let blobName = BlobStore.newName(ext: ext)
        guard BlobStore.write(stored, name: blobName) else { return nil }

        // 2. Miniature (2× pour un affichage net à ~110 pt).
        var thumbName: String?
        var thumbBytes = 0
        if let thumb = thumbnail(src, maxPixels: thumbPixels), let png = encode(cgImage: thumb, type: .png) {
            let name = blobName.replacingOccurrences(of: ".\(ext)", with: "_t.png")
            if BlobStore.write(png, name: name) { thumbName = name; thumbBytes = png.count }
        }

        let meta = ClipMeta(width: w, height: h, bytes: stored.count + thumbBytes, format: ext, thumb: thumbName)
        return Result(meta: meta, blobName: blobName)
    }

    /// Texte contenu dans une image déjà rangée (le premier appel charge le modèle Vision : plusieurs secondes).
    static func recognizeText(blob: String) async -> String {
        guard let big = downsampled(blob: blob, maxPixels: ocrMaxPixels) else { return "" }
        return await recognizeText(in: big)
    }

    // MARK: - OCR

    static func recognizeText(in image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "fr-FR"), Locale.Language(identifier: "en-US")]
        guard let observations = try? await request.perform(on: image) else { return "" }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n")
        return joined.count > 20_000 ? String(joined.prefix(20_000)) : joined
    }

    // MARK: - Utilitaires

    static func thumbnail(_ src: CGImageSource, maxPixels: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Image réduite à partir d'un fichier du dossier Blobs (aperçu).
    static func downsampled(blob: String?, maxPixels: Int) -> CGImage? {
        guard let blob, let src = CGImageSourceCreateWithURL(BlobStore.url(blob) as CFURL, nil) else { return nil }
        return thumbnail(src, maxPixels: maxPixels)
    }

    static func encode(_ src: CGImageSource, type: UTType, quality: Double? = nil) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func encode(cgImage: CGImage, type: UTType) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Conversion pour le presse-papier (PNG ou TIFF), à la demande.
    static func convert(blob: String?, to type: UTType) -> Data? {
        guard let data = BlobStore.read(blob), let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return encode(src, type: type)
    }
}
