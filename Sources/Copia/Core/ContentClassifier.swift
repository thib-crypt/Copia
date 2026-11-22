import Foundation

/// Ce que Copia accepte d'enregistrer.
nonisolated struct CaptureOptions: Sendable, Equatable {
    var images = true
    var files = true
    var richText = true
    /// Au-delà, l'image n'est pas enregistrée (octets bruts sur le presse-papier).
    var maxImageBytes = 40 * 1_048_576
}

/// Décide quel type de contenu représente le presse-papier. Logique pure, testée dans CopiaTests.
///
/// Ordre de priorité :
/// 1. fichiers (le Finder met aussi le nom en texte et l'icône en TIFF : les fichiers gagnent) ;
/// 2. image, si aucun texte n'accompagne l'image (ou seulement une URL, ex. « Copier l'image » d'un navigateur) ;
/// 3. texte riche (RTF, RTFD ou HTML accompagnés de texte brut) ;
/// 4. texte brut.
nonisolated enum ContentClassifier {
    enum Kind: Equatable, Sendable {
        case files
        case image(type: String)
        case richText(types: [String])
        case text
        case none
    }

    static let fileURLType = "public.file-url"
    static let rtf = "public.rtf"
    static let rtfd = "com.apple.flat-rtfd"
    static let html = "public.html"
    static let richTypes = [rtf, rtfd, html]

    /// Du meilleur au moins bon pour le stockage.
    static let imageTypes = ["public.png", "public.heic", "public.jpeg", "com.compuserve.gif",
                             "org.webmproject.webp", "public.avif", "public.jpeg-xl", "public.tiff"]

    /// Image optimisée par Forma : elle arrive avec son fichier, mais c'est bien une image.
    static let formaStampType = FormaStamp.pasteboardType

    static func classify(types: [String], plainText: String?, options: CaptureOptions) -> Kind {
        let set = Set(types)
        let text = plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasText = !text.isEmpty

        if set.contains(formaStampType), options.images, let t = imageTypes.first(where: set.contains) {
            return .image(type: t)
        }
        if options.files && set.contains(fileURLType) { return .files }

        if let imageType = imageTypes.first(where: set.contains), !hasText || isSingleURL(text) {
            if options.images { return .image(type: imageType) }
            // Images désactivées : on garde l'URL éventuelle comme texte.
            return hasText ? .text : .none
        }

        guard hasText else { return .none }

        if options.richText {
            let rich = richTypes.filter(set.contains)
            if !rich.isEmpty { return .richText(types: rich) }
        }
        return .text
    }

    static func isSingleURL(_ s: String) -> Bool {
        guard !s.contains(where: \.isWhitespace) else { return false }
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://")
            || lower.hasPrefix("data:image/")
    }

    static func fileExtension(forImageType type: String) -> String {
        switch type {
        case "public.png": "png"
        case "public.heic": "heic"
        case "public.jpeg": "jpg"
        case "com.compuserve.gif": "gif"
        case "org.webmproject.webp": "webp"
        case "public.avif": "avif"
        case "public.jpeg-xl": "jxl"
        default: "tiff"
        }
    }
}
