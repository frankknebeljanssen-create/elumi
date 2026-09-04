import Foundation

/// **Infinitiv-Karten (2026-09-03)** — User-Spec: „wenn man z.B. „il pleut"
/// als „es regnet" in eine Liste einliest, sollen die Übungen nicht nur
/// „es regnet" abfragen, sondern auch immer den Infinitiv des Verbs".
///
/// Ein gescanntes Schulbuch liefert Verben fast nie im Infinitiv, sondern
/// konjugiert und im Satzkontext: „il pleut", „il fait froid", „je ne sais
/// pas". Genau das steht dann in der Liste — und genau das wird geübt. Die
/// Grundform, die man eigentlich lernen muss, kam bisher nur im
/// Verben-Trainingsmodus vor (`TrainingMode.verbs`), der die Phrasen durch
/// ihre Lemmata **ersetzt**. In Karteikarten, Quiz und Vokabel-Training
/// tauchte sie überhaupt nicht auf.
///
/// Dieser Synthesizer schließt die Lücke: Er zieht aus einer Item-Menge die
/// eindeutigen Verb-Lemmata und gibt sie als **zusätzliche** Karten zurück
/// — „pleuvoir → regnen" neben „il pleut → es regnet".
///
/// **Datenquelle** — nichts davon muss gespeichert werden, alles steht
/// bereits im gebündelten `ElumiMasterLexicon.sqlite`:
///   • Konjugierte Form → Infinitiv über die `forms`-Tabelle
///     (`FrenchEntryAnalyzer` → `EntryLemmas.verbs`, gecached in
///     `FrenchListStatisticsAggregator`)
///   • Infinitiv → deutsche Übersetzung über
///     `SupplementalFreeDictLexicon.germanTranslation(forFrenchLemma:)`
/// Deshalb greift das rückwirkend auch für alles, was längst in den Listen
/// steht — keine Migration, kein Re-Scan nötig.
///
/// **Nicht betroffen**: die Listen selbst. Die Infinitiv-Karten entstehen
/// zur Laufzeit im Übungs-Pool und werden nirgends persistiert — die Liste
/// zeigt weiter genau das, was der User eingelesen hat.
enum VerbInfinitiveSynthesizer {

    /// Die eindeutigen Verb-Lemmata einer Item-Menge als eigenständige
    /// Infinitiv-Items. Ohne die Ursprungs-Items — wer beides will, nimmt
    /// `augmentedWithInfinitives`.
    ///
    /// Beispiel: „je ne sais pas" + „je sais" + „tu sais" + „je m'appelle"
    /// → `savoir` (1×) und `s'appeler` (1×), nicht die vier Phrasen.
    static func infinitiveItems(
        from items: [VocabularyItem],
        language: StudyLanguage
    ) -> [VocabularyItem] {
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: items)
        var synthesized: [VocabularyItem] = []
        // **Block C (2026-05-03)** — Defense-in-Depth gegen DB-Tagging-
        // Drift: nur Single-Verb-Lemmas synthetisieren. Mehrwort-Einträge
        // wie „aller voir un film", die fälschlich mit `wordClass == "verb"`
        // getaggt sind, werden hier ausgefiltert. Reflexive Verben
        // (`s'amuser`, `se laver`) bleiben drin — siehe `isSingleVerbLemma`.
        for lemma in stats.verbLemmas where StandardVocabularyLoader.isSingleVerbLemma(lemma) {
            guard let german = germanInfinitive(for: lemma) else { continue }
            synthesized.append(
                VocabularyItem(
                    rawFrench: lemma,
                    rawGerman: german,
                    cardType: .words,
                    sourceLanguage: language,
                    wordClass: "verb"
                )
            )
        }
        return synthesized
    }

    /// Ergänzt eine Item-Menge um die Infinitive der darin vorkommenden
    /// Verben. Das ist der Einstieg für Karteikarten, Quiz und
    /// Vokabel-Training.
    ///
    /// **Dedupe**: Steht der Infinitiv bereits als eigener Eintrag in der
    /// Liste (die Liste hat „faire → machen" und „il fait froid → es ist
    /// kalt"), wird er nicht ein zweites Mal erzeugt. Sonst käme dasselbe
    /// Wort zweimal in derselben Runde dran.
    ///
    /// Reihenfolge: Original-Items zuerst, Infinitive angehängt. Wer mischt
    /// (alle Übungsmodule tun das), merkt davon nichts; wer die Menge
    /// deckelt, verliert im Zweifel eher eine Zusatzkarte als einen
    /// Original-Eintrag.
    static func augmentedWithInfinitives(
        _ items: [VocabularyItem],
        language: StudyLanguage
    ) -> [VocabularyItem] {
        // Der Analyzer arbeitet auf Französisch — für andere Richtungen
        // gibt es weder Lemma-Tabelle noch sinnvolle Grundform.
        guard language == .french else { return items }

        let frenchItems = items.filter { $0.sourceLanguage == .french }
        guard !frenchItems.isEmpty else { return items }

        var existing = Set(frenchItems.map { normalized($0.french) })
        var additions: [VocabularyItem] = []
        for candidate in infinitiveItems(from: frenchItems, language: language) {
            let key = normalized(candidate.french)
            guard existing.insert(key).inserted else { continue }
            additions.append(candidate)
        }

        guard !additions.isEmpty else { return items }
        return items + additions
    }

    // MARK: - Helfer

    /// Deutsche Grundform zu einem französischen Verb-Lemma. Die Master-DB
    /// liefert teils mehrere Bedeutungen mit „;" getrennt („savoir →
    /// wissen; können") — für eine Karteikarte nimmt man die erste.
    ///
    /// **Cache**: `SupplementalFreeDictLexicon.germanTranslation` öffnet
    /// die SQLite-Datei bei **jedem** Aufruf neu. Der Karteikarten-Setup-
    /// Screen zählt seinen Stapel in einer computed property, also bei
    /// jedem Render — ohne Memo wären das dutzende DB-Öffnungen pro
    /// Frame. Der Inhalt ist ein statisches Bundle-Lexikon, das sich zur
    /// Laufzeit nie ändert; ein unbegrenzter Memo ist damit unkritisch
    /// (Obergrenze ist die Zahl der Verb-Lemmata im Lexikon).
    private static func germanInfinitive(for lemma: String) -> String? {
        let key = lemma.lowercased()

        germanCacheLock.lock()
        if let cached = germanCache[key] {
            germanCacheLock.unlock()
            return cached
        }
        germanCacheLock.unlock()

        let raw = SupplementalFreeDictLexicon.germanTranslation(
            forFrenchLemma: lemma,
            wordClassHint: "verb"
        ) ?? ""
        let clean = raw
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? raw
        let result: String? = clean.isEmpty ? nil : clean

        germanCacheLock.lock()
        germanCache[key] = result
        germanCacheLock.unlock()
        return result
    }

    /// `[String: String?]` — ein gecachter Fehlschlag (Lemma ohne
    /// deutsche Entsprechung) muss auch als Treffer gelten, sonst wird
    /// er bei jedem Render neu in der DB gesucht.
    nonisolated(unsafe) private static var germanCache: [String: String?] = [:]
    private static let germanCacheLock = NSLock()

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
