import Foundation

extension TrainingSessionController {
    var placeholderDictionaryTrainingList: VocabularyList {
        VocabularyList(
            id: VocabularyListStore.dictionaryListID,
            name: "Wörterbuch",
            items: [],
            isBuiltIn: false,
            collectionPreset: .other
        )
    }

    func dictionaryTrainingList() -> VocabularyList? {
        loadedDictionaryTrainingList
    }

    func isDictionaryTrainingSelected() -> Bool {
        selectedTrainingListID == VocabularyListStore.dictionaryListID
    }

    func shouldPrepareDictionaryTrainingList(launchContext: TrainingLaunchContext?) -> Bool {
        showingTrainingListPicker ||
        isDictionaryTrainingSelected() ||
        launchContext?.preferredListID == VocabularyListStore.dictionaryListID
    }

    func availableTrainingLists(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> [VocabularyList] {
        var lists = listStore.practiceLists
            + StandardVocabularyLoader.levelLists
            + StandardVocabularyLoader.topicLists

        // „Komplettes Wörterbuch" (allInOneList) nur im Vokabel-Modus zur Auswahl bieten.
        // Andere Module (Nomen, Verben, Verbformen, Artikel) wären zu groß
        // und unspezifisch, wenn das ganze Lexikon mitgewählt wird.
        if trainingMode == .vocabulary {
            lists.append(StandardVocabularyLoader.allInOneList)
        }

        return lists
    }

    func selectedTrainingList(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> VocabularyList? {
        let availableLists = availableTrainingLists(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )

        if let selectedTrainingListID {
            return availableLists.first(where: { $0.id == selectedTrainingListID }) ?? availableLists.first
        }
        return availableLists.first
    }

    func activeItems(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> [VocabularyItem] {
        // Multi-select: merge items from all selected lists
        let allAvailable = availableTrainingLists(from: listStore, selectedAppDirection: selectedAppDirection, launchContext: launchContext)
        let selectedLists: [VocabularyList]
        if !selectedTrainingListIDs.isEmpty {
            // **2026-08-06** — Verwaiste IDs abfangen: Seit dem Niveau-
            // Neuzuschnitt gibt es keine C1/C2-Lernlisten mehr. Eine noch
            // gespeicherte C2-Auswahlträfe hier auf keine Liste und
            // ergäbe einen leeren Pool („Keine Karten") ohne Erklärung.
            // `prunedSelectedListIDs` fällt in dem Fall auf den
            // A1-Grundwortschatz zurück.
            //
            // **Bugfix 2026-08-05** — Auflösungs-Menge ≠ Picker-Menge
            // (User-Report: „in Artikel üben kommen Vokabeln, die gar
            // nicht in der angewählten Liste waren"). `availableTraining
            // Lists` lässt in allen Nicht-Vokabel-Modi bewusst das
            // „Komplette Wörterbuch" aus der AUSWAHL weg — dieselbe
            // Menge diente hier aber auch zum AUFLÖSEN der bereits
            // getroffenen Auswahl. Wer also das Wörterbuch (oder eine
            // andere hier nicht angebotene Liste) gewählt hatte, dessen
            // ID überlebte das Pruning nicht und wurde still durch den
            // A1-Grundwortschatz ersetzt: fremde Vokabeln, ohne Hinweis.
            // Jetzt wird gegen ALLE real existierenden Listen aufgelöst;
            // der Fallback greift nur noch bei wirklich verwaisten IDs.
            var resolvableLists = allAvailable
            let knownIDs = Set(allAvailable.map(\.id))
            for list in listStore.allLists where !knownIDs.contains(list.id) {
                resolvableLists.append(list)
            }
            if !resolvableLists.contains(where: { $0.id == StandardVocabularyLoader.allInOneList.id }) {
                resolvableLists.append(StandardVocabularyLoader.allInOneList)
            }
            if let dictionaryList = dictionaryTrainingList(),
               !resolvableLists.contains(where: { $0.id == dictionaryList.id }) {
                resolvableLists.append(dictionaryList)
            }

            let usableIDs = VocabularyListSelectionResolver.prunedSelectedListIDs(
                selectedTrainingListIDs,
                knownListIDs: Set(resolvableLists.map(\.id))
            )
            selectedLists = resolvableLists.filter { usableIDs.contains($0.id) }
        } else if let single = selectedTrainingList(from: listStore, selectedAppDirection: selectedAppDirection, launchContext: launchContext) {
            selectedLists = [single]
        } else {
            return []
        }

        // **V1b Lernjahr-Filter (2026-04-28)** — Per-Liste-Slice via
        // Resolver, BEVOR der flache Pool entsteht. Hierarchische Listen
        // (A1 mit cumulativeChildren) liefern ihren Y_1...Y_max-Slice;
        // klassische Listen (Découvertes, Custom) ihre vollen items.
        // Mode-Filter (vocabulary/nouns/articles/verbs/accents) greift
        // nachgelagert orthogonal.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let allItems = selectedLists
            .flatMap { VocabularyListSelectionResolver.effectiveItems(for: $0, lernjahrMax: lernjahrMax) }
            .filter { $0.sourceLanguage == selectedAppDirection.sourceLanguage }

        // Spezialpfad für Verben: Aus ALLEN Items (auch Phrasen) die eindeutigen
        // Verb-LEMMATA extrahieren und als synthetische Trainings-Items zurückgeben.
        // Damit wird aus „je ne sais pas" → „savoir" trainiert (Infinitiv-Form).
        if trainingMode == .verbs {
            return Self.synthesizeVerbInfinitiveItems(
                from: allItems,
                language: selectedAppDirection.sourceLanguage
            )
        }

        return allItems.filter { item in
            switch trainingMode {
            case .vocabulary:
                return item.cardType == cardType
            case .nouns:
                // System-Regel (Nomen/Artikel): reine Artikel-Tokens
                // („le", „la", „les", „le/la" …) dürfen NICHT im Pool
                // landen — sie sind weder Nomen noch sinnvolle Abfrage-
                // Einträge. Greift **vor** den beiden Inklusions-Checks,
                // damit ein als „noun" falsch klassifizierter Artikel
                // nicht über die resolved-Word-Class-Abkürzung doch
                // wieder hereinkommt.
                if Self.isPureFrenchArticle(item.french) { return false }
                // Zentrale Auflösung: Wort-Nomen UND Nomen-Phrasen (z.B. „la maison blanche").
                if StandardVocabularyLoader.resolvedWordClass(forItem: item) == "noun" {
                    return true
                }
                return item.cardType == .words && Self.hasFrenchArticle(item.french)
            case .articles:
                // Der Artikel-Modus läuft seit der Single-Source-Umstellung
                // **ausschließlich** über den `ArticleModeClassifier` (siehe
                // `ArticleModeClassifier.swift`). Der Classifier ist die
                // einzige Instanz, die bestimmt, ob ein Eintrag überhaupt
                // abfragbar ist — er kickt:
                //   • reine Artikel („le", „la", „le/la"),
                //   • Possessiv-/Demonstrativ-Phrasen ohne erkennbaren Kern,
                //   • Nicht-Nomen (Adverbien, Interjektionen, Verben …),
                //   • Einträge mit unbestimmbarem Genus,
                //   • Phrasen (`cardType == .phrases`).
                // So kann später in der UI der Prompt (`articlePromptText`)
                // und die erwartete Antwort (`correctArticle`) denselben
                // Classifier konsultieren und sich nicht widersprechen.
                //
                // Wichtig: Die `.articles`-Regelung bleibt **strikt lokal**
                // in diesem Case — alle anderen Trainingsmodi und der
                // Karteikartenmodus sind nicht betroffen.
                return ArticleModeClassifier.classify(item).estValidePourExerciceArticle
            case .verbs:
                return false  // siehe Spezialpfad oben
            case .verbforms:
                // Konjugations-Training: nur Einzelwort-Verben (Infinitive),
                // weil wir eine sauber konjugierbare Lemma-Form brauchen.
                // **Block C (2026-05-03)** — zusätzlich
                // `isSingleVerbLemma`-Defense-Layer gegen DB-Tagging-
                // Drift: ausschließt Mehrwort-Einträge wie „aller voir
                // un film", die fälschlich `wordClass == "verb"` UND
                // `cardType == .words` tragen können. Reflexive
                // Verben (`s'amuser`, `se laver`) bleiben drin.
                return item.cardType == .words
                    && StandardVocabularyLoader.isVerb(item.french)
                    && StandardVocabularyLoader.isSingleVerbLemma(item.french)
            }
        }
    }

    /// Verb-Training: aus den Items einer Liste (Wörter + Phrasen) die EINDEUTIGEN
    /// Verb-Lemmata via zentralem Analyzer ziehen und als synthetische
    /// VocabularyItems im Infinitiv zurückgeben.
    /// Beispiel: Liste hat „je ne sais pas" + „je sais" + „tu sais" + „je m'appelle"
    /// → trainiert wird `savoir` (1×) und `s'appeler` (1×) — nicht die 4 Phrasen.
    static func synthesizeVerbInfinitiveItems(
        from items: [VocabularyItem],
        language: StudyLanguage
    ) -> [VocabularyItem] {
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: items)
        var synthesized: [VocabularyItem] = []
        // **Block C (2026-05-03)** — Defense-in-Depth gegen DB-
        // Tagging-Drift: nur Single-Verb-Lemmas synthetisieren.
        // Mehrwort-Einträge wie „aller voir un film", die fälschlich
        // mit `wordClass == "verb"` getaggt sind, werden hier
        // ausgefiltert. Reflexive Verben (`s'amuser`, `se laver`)
        // bleiben drin — siehe `isSingleVerbLemma` Doc.
        for lemma in stats.verbLemmas where StandardVocabularyLoader.isSingleVerbLemma(lemma) {
            // DE-Übersetzung aus der Master-DB (z.B. savoir → wissen, s'appeler → heißen)
            let germanRaw = SupplementalFreeDictLexicon.germanTranslation(
                forFrenchLemma: lemma,
                wordClassHint: "verb"
            ) ?? ""
            let germanClean = germanRaw
                .components(separatedBy: ";")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? germanRaw
            guard !germanClean.isEmpty else { continue }
            let item = VocabularyItem(
                rawFrench: lemma,
                rawGerman: germanClean,
                cardType: .words,
                sourceLanguage: language,
                wordClass: "verb"
            )
            synthesized.append(item)
        }
        return synthesized
    }

    nonisolated private static let frenchArticles: Set<String> = ["le", "la", "l'", "les", "un", "une", "des", "du"]

    nonisolated static func hasFrenchArticle(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Das Token ist selbst ein Artikel („le", „la", „les" …) → kein weiterer davor.
        if frenchArticles.contains(lower) { return true }
        for article in frenchArticles {
            // Klassische Muster: „le chien", „la voiture", „l'ami".
            if lower.hasPrefix(article + " ") || lower.hasPrefix(article + "'") {
                return true
            }
            // Alternativ-Ausdrücke wie „le/la", „un|une" — das erste Segment ist
            // bereits ein Artikel, also keinen weiteren voranstellen.
            if lower.hasPrefix(article + "/") || lower.hasPrefix(article + "|") {
                return true
            }
        }
        return false
    }

    /// `true` genau dann, wenn `text` **ausschließlich** aus einem oder
    /// mehreren französischen Artikeln besteht — ohne anschließendes Nomen.
    ///
    /// Erkennt die drei typischen Formen:
    ///   • reines Einzel-Token („le", „la", „les", „un", „une", „du", …)
    ///   • Slash-Kombinationen („le/la", „un/une")
    ///   • Pipe-Kombinationen („le|la")
    ///
    /// Genutzt als **System-Regel in Nomen/Artikel-Modus**: reine Artikel-
    /// Einträge sind im Trainings-Pool unbrauchbar — „welcher Artikel
    /// gehört zu 'le'?" ist nonsense. Der Filter in `activeItems(…)`
    /// schließt solche Items sauber aus, ohne den restlichen Noun-Pool zu
    /// verkleinern.
    ///
    /// Unterschied zu `hasFrenchArticle(_:)`: dort gibt „le/la"
    /// historisch auch `true` zurück, weil der Prefix-Match greift — wir
    /// wollten aber gerade diese Einträge hier **ausschließen**, also
    /// braucht es den strengeren Pure-Match.
    nonisolated static func isPureFrenchArticle(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        // Direktes Einzel-Token (z. B. „le", „la", „les", „un").
        if frenchArticles.contains(lower) { return true }
        // Kombinationen via „/" oder „|" — jedes Segment muss selbst ein
        // Artikel sein, damit die Gesamt-Form als „reiner Artikel"
        // gilt. Ist nur ein Segment kein Artikel („le chien/la chienne"),
        // greift diese Regel nicht und das Item bleibt im Pool.
        let separators = CharacterSet(charactersIn: "/|")
        let parts = lower
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { frenchArticles.contains($0) }
    }

    nonisolated static func determineFrenchArticle(_ item: VocabularyItem) -> String {
        // 1. Try extracting from French text (e.g., "le chien")
        if let article = extractFrenchArticle(from: item.french) {
            return article
        }

        // Helper: check if word starts with vowel or mute h → needs l'
        let french = item.french.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let needsElision: Bool = {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u", "â", "ê", "î", "ô", "û", "é", "è", "ë", "ï", "ü", "à", "ù", "h"]
            return french.first.map { vowels.contains($0) } ?? false
        }()

        // Helper: convert gender to article with elision check
        func articleForGender(_ gender: String) -> String {
            if needsElision { return "l'" }
            if gender == "feminine" { return "la" }
            return "le"
        }

        // 2. Query supplemental lexicon database for gender (source-only, most reliable)
        if let genderStr = SupplementalFreeDictLexicon.sourceOnlyGender(for: item.french) {
            return articleForGender(genderStr)
        }
        // 2b. Try exact pair match as fallback
        if let genderPair = SupplementalFreeDictLexicon.exactGenderInfo(
            sourceTerm: item.french, targetTerm: item.german
        ), let frenchGender = genderPair.french {
            if frenchGender.gender == .plural { return "les" }
            return articleForGender(frenchGender.gender == .feminine ? "feminine" : "masculine")
        }
        // 3. Use lexicon gender inference (suffix rules, head overrides)
        if let genderInfo = frenchGenderInfo(for: item.french, cardType: .words) {
            if genderInfo.gender == .plural { return "les" }
            return articleForGender(genderInfo.gender == .feminine ? "feminine" : "masculine")
        }
        // 4. Derive from German article (der→le, die→la, das→le)
        let german = item.german.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needsElision { return "l'" }
        if german.hasPrefix("der ") { return "le" }
        if german.hasPrefix("die ") { return "la" }
        if german.hasPrefix("das ") { return "le" }
        // 5. Default: le
        return "le"
    }

    nonisolated static func extractFrenchArticle(from text: String) -> String? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Check l' first (before le/la)
        if lower.hasPrefix("l'") || lower.hasPrefix("l'") { return "l'" }
        for article in ["le", "la", "les", "un", "une", "des", "du"] {
            if lower.hasPrefix(article + " ") { return article }
        }
        return nil
    }

    nonisolated static func strippingFrenchArticle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("l'") || lower.hasPrefix("l'") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        for article in ["le", "la", "les", "un", "une", "des", "du"] {
            if lower.hasPrefix(article + " ") {
                return String(trimmed.dropFirst(article.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    nonisolated private static let knownFrenchVerbs: Set<String> = [
        "aller", "avoir", "être", "faire", "dire", "pouvoir", "vouloir", "devoir",
        "savoir", "voir", "venir", "prendre", "mettre", "parler", "manger", "boire",
        "dormir", "écrire", "lire", "ouvrir", "fermer", "acheter", "chercher", "trouver",
        "donner", "jouer", "aimer", "détester", "préférer", "habiter", "travailler",
        "étudier", "apprendre", "comprendre", "répondre", "demander", "commencer",
        "finir", "choisir", "partir", "sortir", "entrer", "arriver", "rester",
        "tomber", "monter", "descendre", "courir", "marcher", "nager", "danser",
        "chanter", "écouter", "regarder", "attendre", "croire", "connaître",
        "penser", "espérer", "essayer", "payer", "envoyer", "recevoir",
        "perdre", "gagner", "tenir", "sentir", "vivre", "mourir", "naître",
        "appeler", "rappeler", "conduire", "construire", "produire", "traduire",
        "cuire", "suivre", "rire", "sourire", "plaire", "se lever", "se coucher",
        "s'appeler", "se promener", "s'asseoir", "se souvenir"
    ]

    nonisolated static func looksLikeFrenchVerb(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = lower.split(separator: " ")
        guard let firstWord = words.first else { return false }
        let verb = String(firstWord)
        return knownFrenchVerbs.contains(lower) || knownFrenchVerbs.contains(verb)
    }

    func selectedTrainingListLanguages(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> [StudyLanguage] {
        let languages = Set(
            selectedTrainingList(
                from: listStore,
                selectedAppDirection: selectedAppDirection,
                launchContext: launchContext
            )?.items.map(\.sourceLanguage) ?? []
        )
        return StudyLanguage.allCases.filter { languages.contains($0) }
    }
}
