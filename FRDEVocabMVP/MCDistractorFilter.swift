import Foundation

/// Zentrale Distraktor-Auswahl für Multiple-Choice-Pools (Nomen, Verben,
/// Artikel, generelle Vokabel-MC). Bis hierher haben wir aus allen
/// passenden Einträgen im Master-Lexikon frei gemischt — das brachte
/// störende Ausreißer in einfache Übungen („Portfolio" neben „Auto",
/// „Menstruationsbeschwerden" neben „Kopf", „das Mikrofon im Besprechungs-
/// raum" neben „Tisch"). Dieser Filter kappelt die Auswahl an drei klaren
/// Heuristiken:
///
/// 1. **Level-Bucket**: A1/A2 = `.basic`, B1/B2 = `.intermediate`,
///    C1/C2 = `.advanced`. Ein einfaches Wort bekommt nie einen C2-
///    Distraktor vorgesetzt. Fällt die korrekte Antwort außerhalb der
///    Buckets (unbekanntes Level) → alle Buckets zulässig.
/// 2. **Wortanzahl**: Einzelwort → Distraktoren sind Einzelwörter
///    (oder „Artikel + Wort" bei Nomen). Mehrwortphrasen bleiben
///    untereinander. Verhindert, dass bei „Tisch" plötzlich eine
///    3-Wort-Phrase als Distraktor kommt.
/// 3. **Länge**: Distraktor-Zeichenzahl innerhalb ±60 % der Zielwort-
///    Länge (min. 3 Zeichen Toleranz). Filtert die Extreme weg.
///
/// Alle drei Regeln werden in dieser Reihenfolge angewandt; fallen
/// durch harten Filter zu wenige Kandidaten übrig, lockert die Funktion
/// die Regeln **schrittweise** (Nachbar-Bucket → gesamtes Lexikon),
/// damit garantiert `requestedCount` Distraktoren zurückkommen.
enum MCDistractorFilter {

    /// Ein Kandidat aus dem Distraktor-Pool — abstrahiert die Herkunft
    /// (Master-Lexikon-`Entry`, später evtl. andere Quellen). Alle Felder
    /// außer `display` sind optional, damit die Filter tolerant bleiben.
    struct Candidate {
        /// Anzeigewert, wie er in der MC-Option auftauchen soll (Original-
        /// Schreibweise mit Groß/Klein + Akzenten).
        let display: String
        /// CEFR-Level-String aus dem Lexikon (z. B. „A1", „B2", „C1").
        /// `nil` bei Quellen ohne Level-Info.
        let level: String?
        /// Topic-Tag aus dem Lexikon — für spätere Themennähe-Heuristik.
        /// Aktuell als Tiebreaker: bei zu vielen Treffern werden Einträge
        /// mit gleichem Topic wie die korrekte Antwort leicht bevorzugt.
        let topic: String?
    }

    /// Vereinfachte Level-Klassen — wir fassen CEFR-Niveaus paarweise
    /// zusammen, weil eine A1-Distraktor-Menge sonst zu klein wird
    /// (Lexikon hat pro Wortart + exaktem Level oft < 50 Kandidaten).
    enum LevelBucket: Int {
        case basic         // A1, A2
        case intermediate  // B1, B2
        case advanced      // C1, C2

        /// Bucket-Mapping: akzeptiert sowohl die CEFR-Strings aus dem
        /// Master-Lexikon („A1"…„C2") als auch die deutschen `VocabularyLevel`-
        /// RawValues („Anfänger", „Mittel", „Fortgeschritten") — der
        /// Training-Flow gibt uns Letztere, der Lexikon-Pool Ersteres.
        static func bucket(for levelString: String?) -> LevelBucket? {
            guard let raw = levelString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            let upper = raw.uppercased()
            switch upper {
            case "A1", "A2":  return .basic
            case "B1", "B2":  return .intermediate
            case "C1", "C2":  return .advanced
            default: break
            }
            // `VocabularyLevel.rawValue`-Fallback — die App-weite
            // Level-Enum lebt auf Deutsch.
            switch raw {
            case "Anfänger":        return .basic
            case "Mittel":          return .intermediate
            case "Fortgeschritten": return .advanced
            default: return nil
            }
        }

        /// Nachbar-Buckets — erste Lockerungsstufe, falls die strikte
        /// Filterung zu wenig Kandidaten liefert. Beispiel: `.intermediate`
        /// → `[.basic, .advanced]` (beide eine Stufe weg).
        var neighbors: [LevelBucket] {
            switch self {
            case .basic:        return [.intermediate]
            case .intermediate: return [.basic, .advanced]
            case .advanced:     return [.intermediate]
            }
        }
    }

    // MARK: - Public API

    /// Wählt bis zu `count` Distraktoren aus `pool`, passend zu
    /// `correctAnswer`. Garantiert deduplication gegen `correctAnswer`
    /// und mehrfache identische Distraktoren (case-insensitive).
    ///
    /// Fallback-Kaskade (in dieser Reihenfolge, bis `count` Kandidaten
    /// gefunden sind):
    ///   1. Strikte Regel: Level-Bucket gleich, Wortanzahl gleich,
    ///      Länge in Toleranz.
    ///   2. Nachbar-Buckets + Wortanzahl + Länge.
    ///   3. Wortanzahl + Länge (Level egal).
    ///   4. Wortanzahl (Länge egal).
    ///   5. Rest des Pools (Notnagel — passiert praktisch nur bei
    ///      extrem kleinen Pools).
    static func pickDistractors(
        correctAnswer: String,
        correctLevel: String?,
        from pool: [Candidate],
        count: Int = 7
    ) -> [String] {
        let trimmedCorrect = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCorrect.isEmpty, count > 0 else { return [] }

        let correctKey = trimmedCorrect.lowercased()
        let correctWordCount = wordCount(of: trimmedCorrect)
        let correctLengthStripped = normalizedLength(of: trimmedCorrect)
        let correctBucket = LevelBucket.bucket(for: correctLevel)

        // Doppelten Distraktor-Ausschluss case-insensitive, inkl. der
        // korrekten Antwort.
        var seen: Set<String> = [correctKey]

        // Vorfilter: dedup + keine leeren Displays. Spiegel des bisherigen
        // Pool-Aufbaus in `prepareVerbMCOptions` / `prepareNounMCOptions`.
        var dedupedPool: [Candidate] = []
        dedupedPool.reserveCapacity(pool.count)
        var seenKeysPool: Set<String> = [correctKey]
        for cand in pool {
            let trimmed = cand.display.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seenKeysPool.insert(key).inserted else { continue }
            dedupedPool.append(
                Candidate(display: trimmed, level: cand.level, topic: cand.topic)
            )
        }

        // 1) Strikte Regel
        var chosen: [String] = []
        addDistractors(
            from: dedupedPool,
            matching: { cand in
                guard matchesWordCount(cand.display, correct: correctWordCount) else { return false }
                guard matchesLength(cand.display, correctLength: correctLengthStripped) else { return false }
                if let correctBucket {
                    return LevelBucket.bucket(for: cand.level) == correctBucket
                }
                return true
            },
            into: &chosen,
            seen: &seen,
            limit: count
        )
        if chosen.count >= count { return shuffled(chosen, limit: count) }

        // 2) Nachbar-Buckets
        if let correctBucket {
            let allowedBuckets = Set([correctBucket] + correctBucket.neighbors)
            addDistractors(
                from: dedupedPool,
                matching: { cand in
                    guard matchesWordCount(cand.display, correct: correctWordCount) else { return false }
                    guard matchesLength(cand.display, correctLength: correctLengthStripped) else { return false }
                    guard let b = LevelBucket.bucket(for: cand.level) else { return false }
                    return allowedBuckets.contains(b)
                },
                into: &chosen,
                seen: &seen,
                limit: count
            )
            if chosen.count >= count { return shuffled(chosen, limit: count) }
        }

        // 3) Wortanzahl + Länge (Level egal)
        addDistractors(
            from: dedupedPool,
            matching: { cand in
                matchesWordCount(cand.display, correct: correctWordCount)
                    && matchesLength(cand.display, correctLength: correctLengthStripped)
            },
            into: &chosen,
            seen: &seen,
            limit: count
        )
        if chosen.count >= count { return shuffled(chosen, limit: count) }

        // 4) Wortanzahl (Länge egal)
        addDistractors(
            from: dedupedPool,
            matching: { cand in matchesWordCount(cand.display, correct: correctWordCount) },
            into: &chosen,
            seen: &seen,
            limit: count
        )
        if chosen.count >= count { return shuffled(chosen, limit: count) }

        // 5) Notnagel: Rest des Pools
        addDistractors(
            from: dedupedPool,
            matching: { _ in true },
            into: &chosen,
            seen: &seen,
            limit: count
        )
        return shuffled(chosen, limit: count)
    }

    // MARK: - Helpers

    /// Fügt passende Kandidaten in gemischter Reihenfolge in `chosen` ein,
    /// bis `limit` erreicht oder der Pool erschöpft ist. Mutation statt
    /// Return, damit die Kaskaden-Aufrufe in der Hauptfunktion
    /// übersichtlich bleiben.
    private static func addDistractors(
        from pool: [Candidate],
        matching predicate: (Candidate) -> Bool,
        into chosen: inout [String],
        seen: inout Set<String>,
        limit: Int
    ) {
        guard chosen.count < limit else { return }
        let filtered = pool.filter(predicate).shuffled()
        for cand in filtered {
            let key = cand.display.lowercased()
            guard seen.insert(key).inserted else { continue }
            chosen.append(cand.display)
            if chosen.count >= limit { break }
        }
    }

    /// Finales Shuffle auf dem gesammelten Ergebnis — verhindert, dass
    /// die Bucket-Reihenfolge (erst strikt, dann gelockert) sichtbar
    /// wird. `limit` schneidet auf die gewünschte Anzahl zu.
    private static func shuffled(_ items: [String], limit: Int) -> [String] {
        Array(items.shuffled().prefix(limit))
    }

    /// Wortanzahl (nach Whitespace) — 1 für „Tisch", 3 für „le chat noir".
    private static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Nur bei gleicher Wortanzahl-Klasse: Einzelwörter unter sich,
    /// 2-Wort-Ausdrücke tolerieren 1–2 Wörter (Artikel-Variationen),
    /// 3+-Wort-Phrasen brauchen mindestens 3 Wörter beim Distraktor.
    private static func matchesWordCount(_ text: String, correct: Int) -> Bool {
        let n = wordCount(of: text)
        switch correct {
        case 1:     return n == 1
        case 2:     return n == 1 || n == 2
        default:    return n >= 3
        }
    }

    /// Normierte Länge ohne führende Artikel — „der Tisch" wird als
    /// „Tisch" gemessen, damit ein simpler 5-Zeichen-Name nicht durch
    /// den Artikel in eine Phrasen-Klasse rutscht.
    private static func normalizedLength(of text: String) -> Int {
        let stripped = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
        // Einfacher Heuristik-Strip: erster Token ist Artikel, wenn er in
        // der bekannten Artikel-Menge liegt.
        let articles: Set<String> = [
            "der", "die", "das",
            "le", "la", "les", "l'", "un", "une", "des", "du",
        ]
        if let first = stripped.first, articles.contains(String(first)) {
            return stripped.dropFirst().joined(separator: " ").count
        }
        return text.count
    }

    /// Länge innerhalb ±60 % (min. 3 Zeichen Toleranz beidseitig). Bei
    /// kurzen Wörtern („ami") wäre 60 % zu restriktiv, deshalb das
    /// Minimum. Bei langen Wörtern kappt die 60 %-Regel extreme
    /// Ausreißer wie „Menstruationsbeschwerden" neben „Arm".
    private static func matchesLength(_ candidate: String, correctLength: Int) -> Bool {
        guard correctLength > 0 else { return true }
        let candidateLength = normalizedLength(of: candidate)
        let tolerance = max(3, Int(Double(correctLength) * 0.6))
        let lower = max(1, correctLength - tolerance)
        let upper = correctLength + tolerance
        return candidateLength >= lower && candidateLength <= upper
    }
}
