import Foundation
import CryptoKit

nonisolated enum ClipKind: Int, Sendable {
    case text = 0
    // Phase 2 — déjà prévus dans le schéma :
    case image = 1
    case fileURL = 2
    case richText = 3
}

nonisolated struct ClipItem: Identifiable, Hashable, Sendable {
    var id: Int64
    var kind: ClipKind
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

    /// Aperçu une ligne (espaces repliés), calculé une fois.
    var preview: String

    init(id: Int64, kind: ClipKind = .text, text: String, hash: String, createdAt: Date, lastCopiedAt: Date,
         copyCount: Int = 1, pinned: Bool = false, sourceBundleID: String? = nil, sourceAppName: String? = nil,
         isDictation: Bool = false, blobPath: String? = nil) {
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
        self.preview = ClipItem.makePreview(text)
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
        let digest = SHA256.hash(data: Data(basis.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
