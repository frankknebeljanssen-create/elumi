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
            selectedLists = allAvailable.filter { selectedTrainingListIDs.contains($0.id) }
        } else if let single = selectedTrainingList(from: listStore, selectedAppDirection: selectedAppDirection, launchContext: launchContext) {
            selectedLists = [single]
        } else {
            return []
        }

        let allItems = selectedLists.flatMap(\.items)
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
                // Zentrale Auflösung: Wort-Nomen UND Nomen-Phrasen (z.B. „la maison blanche").
                if StandardVocabularyLoader.resolvedWordClass(forItem: item) == "noun" {
                    return true
                }
                return item.cardType == .words && Self.hasFrenchArticle(item.french)
            case .articles:
                if StandardVocabularyLoader.resolvedWordClass(forItem: item) == "noun" {
                    return true
                }
                return item.cardType == .words && Self.hasFrenchArticle(item.french)
            case .verbs:
                return false  // siehe Spezialpfad oben
            case .verbforms:
                // Konjugations-Training: nur Einzelwort-Verben (Infinitive),
                // weil wir eine sauber konjugierbare Lemma-Form brauchen.
                return item.cardType == .words && StandardVocabularyLoader.isVerb(item.french)
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
        for lemma in stats.verbLemmas {
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
        return frenchArticles.contains(where: { lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + "'") })
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
