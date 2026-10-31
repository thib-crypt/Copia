import Foundation
import SQLite3

/// Importe l'historique de CopyClip (Core Data → SQLite) sans jamais toucher à ses fichiers :
/// la base et son WAL sont copiés dans un dossier temporaire avant lecture.
nonisolated enum CopyClipImporter {
    struct Entry: Sendable {
        let text: String
        let date: Date
        let appName: String?
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.fiplab.clipboard/Data/Library/Application Support/CopyClip/copyclip.sqlite")
    }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }

    enum ImportError: LocalizedError {
        /// macOS bloque l'accès au conteneur d'une autre app tant que l'utilisateur ne l'a pas choisi lui-même.
        case accessDenied
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied: "macOS protège les données de CopyClip. Sélectionne son dossier pour autoriser l'accès."
            case .unreadable(let s): s
            }
        }
    }

    /// - Parameter folder: dossier contenant `copyclip.sqlite` (choisi par l'utilisateur), sinon l'emplacement par défaut.
    static func readEntries(from folder: URL? = nil) throws -> [Entry] {
        let fm = FileManager.default
        let source = folder?.appendingPathComponent("copyclip.sqlite") ?? databaseURL
        let tmp = fm.temporaryDirectory.appendingPathComponent("copia-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: source.path + suffix)
            guard fm.fileExists(atPath: src.path) else {
                if suffix.isEmpty { throw ImportError.unreadable("copyclip.sqlite introuvable dans ce dossier.") }
                continue
            }
            // Lecture brute (pas de copie d'attributs étendus), pour isoler un refus d'accès en lecture.
            let data: Data
            do {
                data = try Data(contentsOf: src)
            } catch {
                // Le fichier existe mais n'est pas lisible : c'est la protection des conteneurs de macOS.
                NSLog("Copia import: lecture refusée \(src.lastPathComponent) — \(error)")
                throw ImportError.accessDenied
            }
            try data.write(to: tmp.appendingPathComponent("copyclip.sqlite" + suffix))
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.appendingPathComponent("copyclip.sqlite").path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw ImportError.unreadable("Base CopyClip illisible.")
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT c.ZCONTENTS, c.ZDATERECORDED, a.ZNAME
        FROM ZCLIPPING c LEFT JOIN ZSOURCEAPP a ON a.Z_PK = c.ZSOURCE
        WHERE c.ZCONTENTS IS NOT NULL AND (c.ZTYPE IS NULL OR c.ZTYPE LIKE '%text%')
        ORDER BY c.ZDATERECORDED DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.unreadable("Format CopyClip inattendu.")
        }
        defer { sqlite3_finalize(stmt) }

        var out: [Entry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            let text = String(cString: c)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // Core Data stocke les dates en secondes depuis le 1er janvier 2001.
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 1))
            let app = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            out.append(Entry(text: text, date: date, appName: app))
        }
        return out
    }
}
