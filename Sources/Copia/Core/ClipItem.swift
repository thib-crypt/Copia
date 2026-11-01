import Foundation
import CryptoKit

nonisolated enum ClipKind: Int, Sendable, Codable {
    case text = 0
    case image = 1
    case fileURL = 2
    case richText = 3
}

/// Métadonnées des copies non textuelles (stockées en JSON dans la colonne `meta`).
nonisolated struct ClipMeta: Codable, Hashable, Sendable {
    /// Dimensions en pixels (images).
    var width: Int?
    var height: Int?
    /// Taille sur disque de tous les fichiers de la copie (blob + miniature).
    var bytes: Int?
    /// Format stocké : "png", "heic", "jpeg", "gif"…
    var format: String?
    /// Nom de la miniature dans le dossier Blobs.
    var thumb: String?
    /// Types conservés pour le texte riche (public.rtf, public.html…).
    var richTypes: [String]?
    /// L'image est encore en cours de traitement (encodage, miniature, OCR).
    var processing: Bool?
    /// Texte reconnu dans l'image (OCR Vision).
    var hasOCR: Bool?

    static let empty = ClipMeta()

    var isEmpty: Bool { self == .empty }

    func encoded() -> String? {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ s: String?) -> ClipMeta {
        guard let s, let data = s.data(using: .utf8),
              let m = try? JSONDecoder().decode(ClipMeta.self, from: data) else { return .empty }
        return m
    }
}

nonisolated struct ClipItem: Identifiable, Hashable, Sendable {
    var id: Int64
    var kind: ClipKind
    /// Texte brut. Images : texte reconnu (OCR). Fichiers : chemins, un par ligne.
    var text: String
    var hash: String
    var createdAt: Date
    var lastCopiedAt: Date
    var copyCount: Int
    var pinned: Bool
    var sourceBundleID: String?
    var sourceAppName: String?
    var isDictation: Bool
    var blobPath: String?
    var meta: ClipMeta

    /// Aperçu une ligne (espaces repliés), calculé une fois.
    var preview: String

    init(id: Int64, kind: ClipKind = .text, text: String, hash: String, createdAt: Date, lastCopiedAt: Date,
         copyCount: Int = 1, pinned: Bool = false, sourceBundleID: String? = nil, sourceAppName: String? = nil,
         isDictation: Bool = false, blobPath: String? = nil, meta: ClipMeta = .empty) {
        self.id = id
        self.kind = kind
        self.text = text
        self.hash = hash
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.pinned = pinned
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.isDictation = isDictation
        self.blobPath = blobPath
        self.meta = meta
        self.preview = ClipItem.makePreview(text)
    }

    mutating func setText(_ t: String) {
        text = t
        preview = ClipItem.makePreview(t)
    }

    // MARK: - Fichiers

    var fileURLs: [URL] {
        guard kind == .fileURL else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    // MARK: - Affichage

    /// Titre d'une ligne du panneau.
    var title: String {
        switch kind {
        case .text, .richText:
            return preview
        case .image:
            if let w = meta.width, let h = meta.height { return "Image \(w) × \(h)" }
            return meta.processing == true ? "Image (traitement…)" : "Image"
        case .fileURL:
            let urls = fileURLs
            guard let first = urls.first else { return "Fichier" }
            let name = FileManager.default.displayName(atPath: first.path)
            return urls.count > 1 ? "\(name) + \(urls.count - 1) autre\(urls.count > 2 ? "s" : "")" : name
        }
    }

    /// Le texte que donne « Coller en texte brut ».
    var plainText: String { text }

    var hasPlainText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Mots-clés ajoutés à la clé de recherche (taper « image » ou « pdf » retrouve ces copies).
    var searchExtras: String {
        switch kind {
        case .text: return ""
        case .richText: return " texte riche mis en forme"
        case .image: return " image photo capture \(meta.format ?? "")"
        case .fileURL:
            let names = fileURLs.map(\.lastPathComponent).joined(separator: " ")
            return " fichier \(names)"
        }
    }

    static func makePreview(_ text: String, limit: Int = 600) -> String {
        var out = ""
        out.reserveCapacity(min(text.count, limit))
        var lastWasSpace = true
        for ch in text.prefix(limit * 2) {
            if ch.isWhitespace || ch.isNewline {
                if !lastWasSpace { out.append(" "); lastWasSpace = true }
            } else {
                out.append(ch)
                lastWasSpace = false
            }
            if out.count >= limit { break }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

nonisolated enum ClipHasher {
    static func hash(_ text: String, trimWhitespace: Bool) -> String {
        let basis = trimWhitespace ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
        return hex(SHA256.hash(data: Data(basis.utf8)))
    }

    static func hash(data: Data, prefix: String) -> String {
        prefix + hex(SHA256.hash(data: data))
    }

    static func hash(files: [URL]) -> String {
        hash(data: Data(files.map(\.path).joined(separator: "\n").utf8), prefix: "file:")
    }

    private static func hex(_ d: SHA256.Digest) -> String {
        d.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
