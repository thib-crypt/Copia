import Foundation
import SQLite3

/// Persistance SQLite minimaliste. Toutes les écritures passent par une file série
/// de priorité « utility » : le thread principal n'attend jamais le disque.
nonisolated final class ClipDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.thibault.copia.db", qos: .utility)

    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copia", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("copia.sqlite")
    }

    init(url: URL = ClipDatabase.defaultURL) {
        queue.sync {
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
                NSLog("Copia: impossible d'ouvrir la base \(url.path)")
                return
            }
            exec("PRAGMA journal_mode=WAL;")
            exec("PRAGMA synchronous=NORMAL;")
            exec("PRAGMA temp_store=MEMORY;")
            exec("""
            CREATE TABLE IF NOT EXISTS clips(
              id INTEGER PRIMARY KEY,
              kind INTEGER NOT NULL DEFAULT 0,
              text TEXT NOT NULL,
              hash TEXT NOT NULL,
              created REAL NOT NULL,
              last_copied REAL NOT NULL,
              copy_count INTEGER NOT NULL DEFAULT 1,
              pinned INTEGER NOT NULL DEFAULT 0,
              source_bundle TEXT,
              source_name TEXT,
              is_dictation INTEGER NOT NULL DEFAULT 0,
              blob_path TEXT,
              meta TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_clips_last ON clips(last_copied DESC);
            CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(hash);
            """)
            migrate()
        }
    }

    deinit { sqlite3_close_v2(db) }

    /// v1 → v2 : colonne `meta` (images, fichiers, texte riche).
    private func migrate() {
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW {
            version = sqlite3_column_int(stmt, 0)
        }
        sqlite3_finalize(stmt)
        if version < 2 {
            var hasMeta = false
            if sqlite3_prepare_v2(db, "PRAGMA table_info(clips)", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if Self.string(stmt, 1) == "meta" { hasMeta = true }
                }
            }
            sqlite3_finalize(stmt)
            if !hasMeta { exec("ALTER TABLE clips ADD COLUMN meta TEXT;") }
            exec("PRAGMA user_version = 2;")
        }
    }

    // MARK: - Lecture (au lancement uniquement)

    func loadAll() -> [ClipItem] {
        queue.sync {
            var items: [ClipItem] = []
            let sql = """
            SELECT id, kind, text, hash, created, last_copied, copy_count, pinned,
                   source_bundle, source_name, is_dictation, blob_path, meta
            FROM clips ORDER BY last_copied DESC
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(ClipItem(
                    id: sqlite3_column_int64(stmt, 0),
                    kind: ClipKind(rawValue: Int(sqlite3_column_int(stmt, 1))) ?? .text,
                    text: Self.string(stmt, 2) ?? "",
                    hash: Self.string(stmt, 3) ?? "",
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                    copyCount: Int(sqlite3_column_int(stmt, 6)),
                    pinned: sqlite3_column_int(stmt, 7) != 0,
                    sourceBundleID: Self.string(stmt, 8),
                    sourceAppName: Self.string(stmt, 9),
                    isDictation: sqlite3_column_int(stmt, 10) != 0,
                    blobPath: Self.string(stmt, 11),
                    meta: ClipMeta.decode(Self.string(stmt, 12))
                ))
            }
            return items
        }
    }

    // MARK: - Écritures asynchrones

    func upsert(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        queue.async { [self] in
            exec("BEGIN;")
            let sql = """
            INSERT OR REPLACE INTO clips(id, kind, text, hash, created, last_copied, copy_count, pinned,
                                         source_bundle, source_name, is_dictation, blob_path, meta)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { exec("ROLLBACK;"); return }
            for it in items {
                sqlite3_bind_int64(stmt, 1, it.id)
                sqlite3_bind_int(stmt, 2, Int32(it.kind.rawValue))
                sqlite3_bind_text(stmt, 3, it.text, -1, Self.transient)
                sqlite3_bind_text(stmt, 4, it.hash, -1, Self.transient)
                sqlite3_bind_double(stmt, 5, it.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 6, it.lastCopiedAt.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 7, Int32(it.copyCount))
                sqlite3_bind_int(stmt, 8, it.pinned ? 1 : 0)
                Self.bind(stmt, 9, it.sourceBundleID)
                Self.bind(stmt, 10, it.sourceAppName)
                sqlite3_bind_int(stmt, 11, it.isDictation ? 1 : 0)
                Self.bind(stmt, 12, it.blobPath)
                Self.bind(stmt, 13, it.meta.encoded())
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_finalize(stmt)
            exec("COMMIT;")
        }
    }

    func delete(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        queue.async { [self] in
            exec("BEGIN;")
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
                for id in ids {
                    sqlite3_bind_int64(stmt, 1, id)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
                sqlite3_finalize(stmt)
            }
            exec("COMMIT;")
        }
    }

    func deleteAll(keepPinned: Bool) {
        queue.async { [self] in
            exec(keepPinned ? "DELETE FROM clips WHERE pinned = 0;" : "DELETE FROM clips;")
            exec("PRAGMA wal_checkpoint(TRUNCATE);")
            exec("VACUUM;")
        }
    }

    /// Attend la fin des écritures en cours (à la fermeture de l'app).
    func flush() { queue.sync {} }

    // MARK: - Utilitaires

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let ok = sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK
        if let err { NSLog("Copia SQLite: \(String(cString: err))"); sqlite3_free(err) }
        return ok
    }

    private static func string(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    private static func bind(_ stmt: OpaquePointer?, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(stmt, i, v, -1, transient) } else { sqlite3_bind_null(stmt, i) }
    }
}
