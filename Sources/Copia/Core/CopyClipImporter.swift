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

    static func readEntries() throws -> [Entry] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("copia-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: databaseURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: tmp.appendingPathComponent("copyclip.sqlite" + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.appendingPathComponent("copyclip.sqlite").path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw NSError(domain: "Copia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Base CopyClip illisible"])
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
            throw NSError(domain: "Copia", code: 2, userInfo: [NSLocalizedDescriptionKey: "Format CopyClip inattendu"])
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
