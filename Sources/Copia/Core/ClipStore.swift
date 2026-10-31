import Foundation
import Observation

/// Historique en mémoire (trié du plus récent au plus ancien) + persistance asynchrone.
@Observable
final class ClipStore {
    private(set) var items: [ClipItem] = [] { didSet { onChange?() } }

    /// Appelé après chaque modification (le panneau ouvert se met à jour en direct).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let db: ClipDatabase
    @ObservationIgnored private var byHash: [String: Int64] = [:]
    @ObservationIgnored private var searchKeys: [Int64: String] = [:]
    @ObservationIgnored private var nextID: Int64 = 1

    init(db: ClipDatabase) {
        self.db = db
        items = db.loadAll()
        rebuildIndexes()
    }

    var count: Int { items.count }
    var pinnedCount: Int { items.lazy.filter(\.pinned).count }
    var dictationCount: Int { items.lazy.filter(\.isDictation).count }

    func item(hash: String) -> ClipItem? {
        guard let id = byHash[hash] else { return nil }
        return items.first { $0.id == id }
    }

    func item(id: Int64) -> ClipItem? { items.first { $0.id == id } }

    // MARK: - Mutations

    @discardableResult
    func insert(text: String, hash: String, sourceBundleID: String?, sourceAppName: String?,
                isDictation: Bool, at date: Date = .now) -> ClipItem {
        let item = ClipItem(id: nextID, text: text, hash: hash, createdAt: date, lastCopiedAt: date,
                            sourceBundleID: sourceBundleID, sourceAppName: sourceAppName, isDictation: isDictation)
        nextID += 1
        items.insert(item, at: 0)
        byHash[hash] = item.id
        searchKeys[item.id] = TextNormalizer.searchKey(for: text)
        db.upsert([item])
        return item
    }

    /// Fusion d'un doublon : remonte en haut, incrémente le compteur.
    func bump(id: Int64, at date: Date = .now, latestText: String? = nil, markDictation: Bool = false) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: idx)
        item.lastCopiedAt = date
        item.copyCount += 1
        if markDictation { item.isDictation = true }
        if let latestText, latestText != item.text {
            item.text = latestText
            item.preview = ClipItem.makePreview(latestText)
        }
        items.insert(item, at: 0)
        db.upsert([item])
    }

    func markDictation(hash: String) {
        guard let id = byHash[hash], let idx = items.firstIndex(where: { $0.id == id }),
              !items[idx].isDictation else { return }
        items[idx].isDictation = true
        db.upsert([items[idx]])
    }

    func togglePin(id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        db.upsert([items[idx]])
    }

    func delete(id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        forget(removed)
        db.delete(ids: [removed.id])
    }

    func clear(keepPinned: Bool) {
        let removed = keepPinned ? items.filter { !$0.pinned } : items
        items = keepPinned ? items.filter(\.pinned) : []
        removed.forEach(forget)
        db.deleteAll(keepPinned: keepPinned)
    }

    /// Applique la taille maximale et la durée de conservation. Les épinglés ne sont jamais supprimés.
    func enforceLimits(maxItems: Int, retentionDays: Int) {
        var toDelete: [ClipItem] = []
        if retentionDays > 0 {
            let cutoff = Date.now.addingTimeInterval(-Double(retentionDays) * 86_400)
            toDelete += items.filter { !$0.pinned && $0.lastCopiedAt < cutoff }
        }
        let doomed = Set(toDelete.map(\.id))
        var unpinnedSeen = 0
        for it in items where !it.pinned && !doomed.contains(it.id) {
            unpinnedSeen += 1
            if unpinnedSeen > maxItems { toDelete.append(it) }
        }
        guard !toDelete.isEmpty else { return }
        let ids = Set(toDelete.map(\.id))
        items.removeAll { ids.contains($0.id) }
        toDelete.forEach(forget)
        db.delete(ids: Array(ids))
    }

    /// Import en masse (historique CopyClip). Retourne le nombre de clips ajoutés.
    func importClips(_ entries: [CopyClipImporter.Entry], trimWhitespace: Bool) -> Int {
        var added: [ClipItem] = []
        for e in entries {
            let h = ClipHasher.hash(e.text, trimWhitespace: trimWhitespace)
            guard byHash[h] == nil else { continue }
            let item = ClipItem(id: nextID, text: e.text, hash: h, createdAt: e.date, lastCopiedAt: e.date,
                                sourceAppName: e.appName ?? "CopyClip")
            nextID += 1
            byHash[h] = item.id
            searchKeys[item.id] = TextNormalizer.searchKey(for: e.text)
            added.append(item)
        }
        guard !added.isEmpty else { return 0 }
        items = (items + added).sorted { $0.lastCopiedAt > $1.lastCopiedAt }
        db.upsert(added)
        return added.count
    }

    // MARK: - Recherche

    func searchCandidates() -> [SearchCandidate] {
        let n = max(items.count - 1, 1)
        return items.enumerated().map { i, it in
            SearchCandidate(id: it.id, key: searchKeys[it.id] ?? TextNormalizer.searchKey(for: it.text),
                            recency: 1 - Double(i) / Double(n), pinned: it.pinned)
        }
    }

    func flush() { db.flush() }

    // MARK: - Index

    private func forget(_ item: ClipItem) {
        if byHash[item.hash] == item.id { byHash[item.hash] = nil }
        searchKeys[item.id] = nil
    }

    private func rebuildIndexes() {
        byHash.removeAll(keepingCapacity: true)
        searchKeys.removeAll(keepingCapacity: true)
        // Parcours du plus ancien au plus récent : le hash pointe sur la dernière occurrence.
        for it in items.reversed() {
            byHash[it.hash] = it.id
            searchKeys[it.id] = TextNormalizer.searchKey(for: it.text)
        }
        nextID = (items.map(\.id).max() ?? 0) + 1
    }
}
