import Foundation

/// **Phase-3b-Provider — strict-live mode**.
///
/// Erzeugt `RunnerTask`s **ausschließlich** aus der aktuell gewählten
/// Vokabelliste des Users. **Kein Seed-Fallback, kein Seed-Mix.** Wenn
/// die gewählte Liste zu wenige artikelfähige Nomen enthält (oder gar
/// keine Liste gewählt ist), liefert der Provider `nil`, und die
/// Call-Site (View) zeigt einen Empty-State statt zu spielen.
///
/// **Hintergrund der Umstellung (User-Feedback 2026-04)**: Der vorherige
/// Mix „Live + Seed-Fallback" war verwirrend — Spieler sahen plötzlich
/// Verben oder Distraktoren, die nichts mit ihrer Liste zu tun hatten.
/// Der strict-Mode liefert jetzt ein **konsistentes Lernerlebnis**:
/// Nur Wörter, die der User tatsächlich gewählt hat, erscheinen im Spiel.
///
/// **Was wird live generiert?**
///   • **Article-Tasks**: Prompt = Nomen, Optionen = `[le, la, les]`,
///     korrekt = Nomen-Genus.
///   • **Reverse-Article-Tasks**: Prompt = `"le ___"` (o. `la / les`),
///     Optionen = drei Nomen mit unterschiedlichem Genus — alle aus
///     **derselben** Liste des Users.
///
/// **Was nicht?**
///   • Verbformen — keine Konjugationsdaten im `VocabularyItem`-Modell.
///     Fallen in strict-Mode einfach weg (statt Seed-Verbformen zu
///     mischen).
///
/// **Genus-Quelle**: `VocabularyItem.variants[0].tag` (m/f/n/pl), sonst
/// Artikel-Präfix im `french`-String („le …" / „la …" / „les …" /
/// „l'…" / „un …" / „une …"). Items ohne eindeutige Genus-Zuordnung
/// werden ignoriert.
///
/// Thread-Modell: `@MainActor` — `VocabularyListStore` ist ebenfalls
/// MainActor-isoliert.
@MainActor
final class LiveListRunnerTaskProvider: RunnerTaskProvider {

    private let listStore: VocabularyListStore

    /// Pool wird bei Bedarf neu gebaut (nach Erschöpfung). Keine
    /// Fallback-Quelle — strict-Live-only.
    private var pool: [RunnerTask] = []

    init(listStore: VocabularyListStore) {
        self.listStore = listStore
        rebuildPool()
    }

    /// Erzwingt einen Pool-Rebuild — z. B. nachdem der User auf dem
    /// Start-Screen eine andere Liste ausgewählt hat. Die nächste
    /// `nextTask()`-Anfrage liefert dann Items aus der neu gewählten
    /// Liste statt aus dem alten Pool-Rest.
    func refreshPool() {
        rebuildPool()
    }

    func nextTask() -> RunnerTask? {
        if pool.isEmpty {
            rebuildPool()
        }
        // Nach Rebuild immer noch leer → der User hat zwar eine Liste
        // gewählt, die aber keine artikelfähigen Nomen enthält. Wir
        // liefern `nil`; der Runner respektiert das und spawnt
        // Gap-Wellen (reiner Dodge). Die Call-Site sollte diesen Fall
        // ohnehin vorher abfangen (`hasUsableContent(in:)`), damit
        // der User gar nicht erst in den Run geht.
        guard !pool.isEmpty else { return nil }
        let task = pool.removeLast()
        guard task.isWellFormed else {
            return pool.isEmpty ? nil : nextTask()
        }
        return task
    }

    // MARK: - Empty-State-Check (static)

    /// Prüft, ob die aktuell gewählte Liste **genug** artikelfähige
    /// Nomen für den strict-Live-Mode enthält. Wird von der View vor
    /// dem Start des Runs aufgerufen — ist das `false`, zeigen wir
    /// statt der Game-Arena einen Empty-State mit Hinweis + Button
    /// „Zu den Listen".
    ///
    /// `minimum` = 3 ist absichtlich niedrig (permissiv): selbst kleine
    /// User-Listen mit 3 Nomen sollen spielbar sein. Der Pool wird bei
    /// Erschöpfung automatisch wieder aufgefüllt (shuffle-Repeat).
    static func hasUsableContent(
        in listStore: VocabularyListStore?,
        minimum: Int = 3
    ) -> Bool {
        guard let store = listStore else { return false }
        let selectedID = store.selectedListID
        let allLists = [store.builtInList] + store.customLists
        guard let selected = allLists.first(where: { $0.id == selectedID }) else {
            return false
        }
        let nouns = selected.items.filter { $0.cardType == .words }
        var count = 0
        for item in nouns {
            if parseNounInfo(item) != nil {
                count += 1
                if count >= minimum { return true }
            }
        }
        return false
    }

    // MARK: - Pool-Rebuild

    private func rebuildPool() {
        let articleTasks = generateArticleTasks()
        let reverseTasks = generateReverseArticleTasks(from: articleTasks)
        // Strict: nur Live-Tasks, kein Seed-Mischen. Wenn Articles +
        // Reverses zusammen < handvoll sind, ist das okay — Pool wird
        // nach Erschöpfung neu gemischt, Wiederholung ist akzeptabler
        // als Fremdmaterial.
        pool = (articleTasks + reverseTasks).shuffled()
    }

    // MARK: - Live-Article-Generierung

    private func generateArticleTasks() -> [RunnerTask] {
        let items = currentNounItems()
        var tasks: [RunnerTask] = []
        for item in items {
            guard let info = Self.parseNounInfo(item) else { continue }
            let correctIndex: Int = {
                switch info.gender {
                case .masculine, .neuter: return 0   // le
                case .feminine:           return 1   // la
                case .plural:             return 2   // les
                }
            }()
            tasks.append(RunnerTask(
                category: .article,
                prompt: info.noun,
                options: ["le", "la", "les"],
                correctIndex: correctIndex
            ))
        }
        return tasks
    }

    /// Reverse-Tasks: pro Article (`le / la / les`) je bis zu drei
    /// Aufgaben, wenn wir ein passendes Nomen + zwei Distraktor-Nomen
    /// (anderes Genus) **aus derselben Liste** haben. Vermeidet
    /// Nonsense-Distraktoren — alle Optionen sind echte User-Vokabeln.
    private func generateReverseArticleTasks(from sourcePool: [RunnerTask]) -> [RunnerTask] {
        let masculines = sourcePool.filter { $0.options[$0.correctIndex] == "le" }.map { $0.prompt }
        let feminines  = sourcePool.filter { $0.options[$0.correctIndex] == "la" }.map { $0.prompt }
        let plurals    = sourcePool.filter { $0.options[$0.correctIndex] == "les" }.map { $0.prompt }

        var reverse: [RunnerTask] = []

        func addReverse(article: String, target: [String], otherA: [String], otherB: [String], correctIndex: Int) {
            for tgt in target.prefix(3) {
                guard let dA = otherA.randomElement(),
                      let dB = otherB.randomElement(),
                      dA != tgt, dB != tgt else { continue }
                var opts = ["", "", ""]
                opts[correctIndex] = tgt
                let distractorIndices = [0, 1, 2].filter { $0 != correctIndex }
                opts[distractorIndices[0]] = dA
                opts[distractorIndices[1]] = dB
                reverse.append(RunnerTask(
                    category: .article,
                    prompt: "\(article) ___",
                    options: opts,
                    correctIndex: correctIndex
                ))
            }
        }

        addReverse(article: "le",  target: masculines, otherA: feminines, otherB: plurals, correctIndex: 0)
        addReverse(article: "la",  target: feminines,  otherA: masculines, otherB: plurals, correctIndex: 1)
        addReverse(article: "les", target: plurals,    otherA: masculines, otherB: feminines, correctIndex: 2)
        return reverse
    }

    // MARK: - Item-Filtering + Parsing

    /// Aktuelle Nomen-Items aus der gewählten Liste. Filtert auf
    /// `cardType == .words` — Phrasen sind für Article-Tasks ungeeignet.
    private func currentNounItems() -> [VocabularyItem] {
        let selectedID = listStore.selectedListID
        let allLists = [listStore.builtInList] + listStore.customLists
        guard let selected = allLists.first(where: { $0.id == selectedID }) else {
            return []
        }
        return selected.items.filter { $0.cardType == .words }
    }

    /// Extrahiert Nomen + Genus aus einem `VocabularyItem`.
    /// Als `static`, damit der Empty-State-Check die **identische**
    /// Logik nutzt wie die Live-Generierung — keine Divergenz.
    ///
    /// **Strict-Filter (User-Wunsch „als Fragen nur Nomen, keine
    /// Phrasen")**:
    ///   1. `cardType == .words` — Phrasen-Typen werden direkt
    ///      verworfen, auch wenn sie artikelähnlich beginnen.
    ///   2. Nach Artikel-Strip muss das Ergebnis ein **Einzelwort**
    ///      sein — keine Leerzeichen, keine Phrasen. Bindestrich und
    ///      Apostroph sind erlaubt („grand-mère", „l'école").
    ///
    /// Damit kommen nur saubere Nomen in den Aufgaben-Pool — keine
    /// „le chat noir" als Frage, keine „une belle journée" etc.
    fileprivate static func parseNounInfo(_ item: VocabularyItem) -> NounInfo? {
        // Hartes Gate: keine Phrasen zulassen, auch wenn `cardType`
        // von woanders falsch gesetzt sein sollte.
        guard item.cardType == .words else { return nil }

        // (1) Variant-Tag
        if let variant = item.variants?.first {
            if let gender = LexiconNounGender(rawValue: variant.tag + ".") ?? tagMap[variant.tag] {
                let noun = stripArticle(from: variant.french)
                guard isSingleNoun(noun) else { return nil }
                return NounInfo(noun: noun, gender: gender)
            }
        }

        // (2) Artikel-Präfix
        let raw = item.french.trimmingCharacters(in: .whitespaces)
        let lower = raw.lowercased()
        for (prefix, gender) in articlePrefixes {
            if lower.hasPrefix(prefix) {
                let noun = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                guard isSingleNoun(noun) else { return nil }
                return NounInfo(noun: noun, gender: gender)
            }
        }

        return nil
    }

    /// Ist `s` ein **Einzelwort** (genau ein Wort, egal wie lang)?
    /// Phrasen fallen dadurch raus. Bindestriche und Apostrophe sind
    /// keine Trenner (sprachlich ein Wort: „grand-mère",
    /// „l'école" → nach Strip ist's „école").
    private static func isSingleNoun(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // Keine Leerzeichen → Einzelwort.
        return !trimmed.contains(" ")
    }

    private static func stripArticle(from s: String) -> String {
        let lower = s.lowercased()
        for (prefix, _) in articlePrefixes {
            if lower.hasPrefix(prefix) {
                return String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    fileprivate struct NounInfo {
        let noun: String
        let gender: LexiconNounGender
    }

    /// Mapping kurze-Tags → Lexicon-Gender. `LexiconNounGender`
    /// erwartet rawValues mit Punkt („m." / „f." / „n." / „pl."),
    /// die Variant-Tags speichern oft nur „m" / „f" / „pl".
    private static let tagMap: [String: LexiconNounGender] = [
        "m":  .masculine,
        "f":  .feminine,
        "n":  .neuter,
        "pl": .plural
    ]

    /// Geordnet nach Länge (längster Präfix zuerst), damit „les" vor
    /// „le" matched.
    private static let articlePrefixes: [(String, LexiconNounGender)] = [
        ("les ",  .plural),
        ("la ",   .feminine),
        ("le ",   .masculine),
        ("l'",    .feminine),     // ambig — meistens .fem; pragmatischer Default
        ("une ",  .feminine),
        ("un ",   .masculine)
    ]
}
