import Foundation

/// Normalisation partagée : minuscules, sans accents, largeur unifiée.
nonisolated enum TextNormalizer {
    static let maxKeyLength = 4_000

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Clé de recherche mise en cache pour un clip (tronquée pour borner le coût).
    static func searchKey(for text: String) -> String {
        let head = text.count > maxKeyLength ? String(text.prefix(maxKeyLength)) : text
        return normalize(head)
    }

    static func tokens(of query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

nonisolated struct SearchCandidate: Sendable {
    let id: Int64
    let key: String
    /// 0 (ancien) … 1 (le plus récent)
    let recency: Double
    let pinned: Bool
}

nonisolated struct SearchHit: Sendable, Equatable {
    let id: Int64
    let score: Double
}

/// Recherche « par proximité » :
/// 1. sous-chaîne exacte (bonus début de mot / phrase entière)
/// 2. mot approchant (fautes de frappe, Damerau-Levenshtein ≤ 1 ou 2)
/// 3. sous-séquence compacte (« trnscr » → « transcription »)
/// Tous les mots de la requête doivent trouver une correspondance, dans n'importe quel ordre.
nonisolated enum FuzzySearch {

    static func search(_ query: String, in candidates: [SearchCandidate], limit: Int = 60) -> [SearchHit] {
        let tokens = TextNormalizer.tokens(of: query)
        guard !tokens.isEmpty else { return [] }
        let phrase = tokens.joined(separator: " ")

        var hits: [SearchHit] = []
        hits.reserveCapacity(min(candidates.count, 256))
        for c in candidates {
            if Task.isCancelled { return [] }
            guard var s = score(tokens: tokens, phrase: phrase, key: c.key) else { continue }
            s += c.recency * 8
            if c.pinned { s += 3 }
            hits.append(SearchHit(id: c.id, score: s))
        }
        hits.sort { $0.score > $1.score }
        return Array(hits.prefix(limit))
    }

    static func score(tokens: [String], phrase: String, key: String) -> Double? {
        var total = 0.0
        if tokens.count > 1, let r = key.range(of: phrase) {
            total += 40
            if r.lowerBound == key.startIndex { total += 10 }
        }
        var words: [Substring]? = nil
        for t in tokens {
            if let s = exactScore(t, in: key) {
                total += s
                continue
            }
            if words == nil { words = splitWords(key) }
            if let s = typoScore(t, words: words!) {
                total += s
                continue
            }
            if let s = subsequenceScore(t, in: key) {
                total += s
                continue
            }
            return nil
        }
        return total
    }

    // MARK: - Niveaux de correspondance

    static func exactScore(_ t: String, in key: String) -> Double? {
        guard let r = key.range(of: t) else { return nil }
        var s = 20.0 + Double(min(t.count, 12))
        if r.lowerBound == key.startIndex {
            s += 12
        } else {
            let before = key[key.index(before: r.lowerBound)]
            if !(before.isLetter || before.isNumber) { s += 8 }
        }
        return s
    }

    static func typoScore(_ t: String, words: [Substring]) -> Double? {
        let tChars = Array(t.unicodeScalars)
        guard tChars.count >= 3, let first = tChars.first else { return nil }
        let maxDist = tChars.count <= 5 ? 1 : 2
        var best: Int? = nil
        for w in words.prefix(800) {
            // Filtres bon marché avant toute allocation.
            guard w.unicodeScalars.first == first else { continue }
            let wLen = w.unicodeScalars.count
            guard wLen + maxDist >= tChars.count else { continue }
            let wChars = Array(w.unicodeScalars)
            // Compare au mot entier et à son préfixe de même longueur (saisie en cours).
            let prefix = Array(wChars.prefix(tChars.count))
            let d1 = damerau(tChars, prefix, limit: maxDist)
            let d = wChars.count <= tChars.count + maxDist ? min(d1, damerau(tChars, wChars, limit: maxDist)) : d1
            if d <= maxDist {
                best = min(best ?? d, d)
                if d == 0 { break }
            }
        }
        guard let d = best else { return nil }
        return 14.0 - Double(d) * 4
    }

    static func subsequenceScore(_ t: String, in key: String) -> Double? {
        let tChars = Array(t.unicodeScalars)
        guard tChars.count >= 3 else { return nil }
        var i = 0
        var start: Int? = nil
        var pos = 0
        let window = tChars.count * 3
        for ch in key.unicodeScalars {
            if ch == tChars[i] {
                if i == 0 { start = pos }
                i += 1
                if i == tChars.count {
                    let span = pos - (start ?? pos) + 1
                    return span <= window ? 4.0 + Double(tChars.count) / Double(span) * 4 : nil
                }
            } else if let s = start, pos - s > window {
                // Fenêtre dépassée : on redémarre la recherche.
                i = 0
                start = nil
                if ch == tChars[0] { start = pos; i = 1 }
            }
            pos += 1
        }
        return nil
    }

    static func splitWords(_ key: String) -> [Substring] {
        key.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
    }

    /// Distance de Damerau-Levenshtein (transpositions adjacentes) avec arrêt anticipé.
    static func damerau(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], limit: Int) -> Int {
        let n = a.count, m = b.count
        if abs(n - m) > limit { return limit + 1 }
        if n == 0 { return m }
        if m == 0 { return n }
        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var cur = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, prev2[j - 2] + 1)
                }
                cur[j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev2, &prev)
            swap(&prev, &cur)
        }
        return prev[m]
    }
}
