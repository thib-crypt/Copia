import Foundation
import AppKit

// Intégration avec Forma (convertisseur / compresseur de Thibault).
// Pas de dépendance directe : un type de presse-papier documenté, la commande `forma … --json`
// et une notification distribuée quand l'historique de Forma change.

/// Ce que Forma joint à une image du presse-papier qu'il vient d'optimiser (`com.thibault.forma.clipboard`).
nonisolated struct FormaStamp: Codable, Sendable, Equatable {
    static let pasteboardType = "com.thibault.forma.clipboard"

    var version: Int?
    /// Hash (au format Copia) de l'image remplacée : retrouve la copie d'origine dans l'historique.
    var originalHash: String?
    var originalBytes: Int64?
    var bytes: Int64?
    var format: String?
    var ext: String?
    var rule: String?
    var savingsPercent: Int?
    /// App où l'image avait été copiée (Forma écrit le presse-papier à sa place).
    var sourceApp: String?
    var file: String?

    static func decode(_ data: Data?) -> FormaStamp? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(FormaStamp.self, from: data)
    }
}

/// Trace d'un passage par Forma, gardée dans `ClipMeta`.
nonisolated struct FormaInfo: Codable, Hashable, Sendable {
    var savingsPercent: Int?
    var format: String?
    var rule: String?
    /// Opération qui a créé cette copie (« WebP », « ×2 »…). nil = optimisation sur place.
    var operation: String?
    // L'original, conservé pour « Coller l'original » / « Revenir à l'original ».
    var originalBlob: String?
    var originalThumb: String?
    var originalFormat: String?
    var originalWidth: Int?
    var originalHeight: Int?
    var originalBytes: Int?
    var originalHash: String?

    var hasOriginal: Bool { originalBlob != nil }

    /// Texte du badge dans le panneau.
    var badge: String {
        if let op = operation { return op }
        if let s = savingsPercent, s > 0 { return "−\(s) %" }
        return "Forma"
    }
}

/// Appelle Forma en ligne de commande (fonctionne même si l'app n'est pas ouverte).
nonisolated enum FormaBridge {
    static let bundleID = "com.thibault.forma"
    static let historyChanged = Notification.Name("com.thibault.forma.historyChanged")

    enum Request: Sendable, Equatable {
        case optimize
        case convert(String)
        case upscale

        var label: String {
            switch self {
            case .optimize: "Optimisation"
            case .convert(let f): "Conversion en \(FormaBridge.formatName(f))"
            case .upscale: "Agrandissement ×2"
            }
        }
    }

    static let convertChoices = ["WEBP", "JPEG", "PNG", "HEIC", "AVIF"]

    static func formatName(_ id: String) -> String {
        ["WEBP": "WebP", "JPEG": "JPEG", "PNG": "PNG", "HEIC": "HEIC", "AVIF": "AVIF"][id] ?? id
    }

    static var appURL: URL? {
        let fixed = URL(fileURLWithPath: "/Applications/Forma.app")
        if FileManager.default.fileExists(atPath: fixed.path) { return fixed }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var executable: URL? {
        guard let app = appURL else { return nil }
        let exe = app.appendingPathComponent("Contents/MacOS/Forma")
        return FileManager.default.isExecutableFile(atPath: exe.path) ? exe : nil
    }

    static var isInstalled: Bool { executable != nil }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Résultats JSON

    struct Optimized: Decodable, Sendable {
        var status: String
        var output: String?
        var format: String?
        var ext: String?
        var rule: String?
        var reason: String?
        var savingsPercent: Int?
        var inputSize: Int64?
        var outputSize: Int64?
        var error: String?
    }

    struct Converted: Decodable, Sendable {
        struct Output: Decodable, Sendable { var path: String; var size: Int64 }
        var input: String
        var status: String
        var outputs: [Output]?
        var savingsPercent: Int?
        var error: String?
        var note: String?
    }

    // MARK: Appels

    static func optimize(_ files: [URL], app: String?, outputDir: URL?) async throws -> [Optimized] {
        var args = ["optimize"] + files.map(\.path) + ["--force", "--json"]
        if let app { args += ["--app", app] }
        if let outputDir { args += ["-o", outputDir.path] }
        return try JSONDecoder().decode([Optimized].self, from: try await run(args))
    }

    /// `outputDir` nil = réglages de sortie de Forma (à côté des originaux par défaut).
    static func convert(_ files: [URL], request: Request, outputDir: URL?) async throws -> [Converted] {
        var args: [String]
        switch request {
        case .convert(let f): args = ["convert"] + files.map(\.path) + ["--to", f]
        case .upscale: args = ["upscale"] + files.map(\.path)
        case .optimize: args = ["compress"] + files.map(\.path)
        }
        args += ["--json", "--origin", "copia"]
        if let outputDir { args += ["-o", outputDir.path] }
        return try JSONDecoder().decode([Converted].self, from: try await run(args))
    }

    static func run(_ args: [String]) async throws -> Data {
        guard let exe = executable else { throw Failure(message: "Forma n'est pas installé dans /Applications.") }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = exe
                p.arguments = args
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(throwing: error); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if data.isEmpty {
                    cont.resume(throwing: Failure(message: "Forma n'a rien renvoyé (code \(p.terminationStatus))."))
                } else {
                    cont.resume(returning: data)
                }
            }
        }
    }

    /// Dossier de travail pour les images à envoyer à Forma.
    static func workDirectory() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("Copia/Forma/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func openForma(_ urls: [URL] = []) {
        guard let app = appURL else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        if urls.isEmpty { NSWorkspace.shared.openApplication(at: app, configuration: cfg) }
        else { NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: cfg) }
    }
}
