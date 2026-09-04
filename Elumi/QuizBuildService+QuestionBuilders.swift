import Foundation

extension QuizBuildService {
    /// **V1b Lernjahr-Filter (2026-04-28)** — Pro-Liste-Slice via
    /// Resolver, BEVOR der flache Pool entsteht. Hierarchische Listen
    /// (A1 mit cumulativeChildren) liefern ihren Y_1...Y_max-Slice;
    /// klassische Listen ihre vollen items unverändert.
    ///
    /// `lernjahrMax` ist Pflicht-Param (Cache-Key-Komponente). Defense-
    /// in-Depth: filtert hier zusätzlich zum Cache-Layer, schützt vor
    /// künftigen Callern, die `makeMergedItems` direkt ohne Cache
    /// aufrufen.
    ///
    /// **Infinitiv-Karten (2026-09-03)** — nach dem Dedupe kommen die
    /// Grundformen der vorkommenden Verben dazu, damit aus „il pleut"
    /// auch `pleuvoir` abgefragt wird. Siehe `VerbInfinitiveSynthesizer`.
    /// Bewusst **nach** dem Dedupe: der Synthesizer prüft selbst gegen
    /// die bereits vorhandenen Einträge und wirft nichts weg, was der
    /// User eingelesen hat.
    static func makeMergedItems(
        from lists: [VocabularyList],
        direction: Direction,
        lernjahrMax: Int?
    ) -> [VocabularyItem] {
        var seen = Set<String>()

        let deduped = lists
            .flatMap { VocabularyListSelectionResolver.effectiveItems(for: $0, lernjahrMax: lernjahrMax) }
            .filter { $0.sourceLanguage == direction.sourceLanguage }
            .filter { item in
                let key = [
                    normalizedLookupText(item.french),
                    normalizedLookupText(item.german),
                    item.cardType.rawValue
                ].joined(separator: "|")

                guard !key.isEmpty, !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }

        return VerbInfinitiveSynthesizer.augmentedWithInfinitives(
            deduped,
            language: direction.sourceLanguage
        )
    }

    static func nextMultipleChoiceQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: inout Set<String>,
        usedQuestionSignatures: inout Set<String>
    ) -> QuizQuestion? {
        guard let (question, consumedIDs) = makeMultipleChoiceQuestion(
            from: candidates,
            usedPromptKeys: &usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else {
            return nil
        }

        let wrappedQuestion = QuizQuestion.multipleChoice(question)
        let signature = signature(wrappedQuestion)
        guard usedQuestionSignatures.insert(signature).inserted else { return nil }
        usedCandidateIDs.formUnion(consumedIDs)
        return wrappedQuestion
    }

    static func nextMatchingQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: inout Set<String>,
        usedQuestionSignatures: inout Set<String>
    ) -> QuizQuestion? {
        guard let (question, consumedIDs) = makeMatchingQuestion(
            from: candidates,
            usedPromptKeys: &usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else {
            return nil
        }

        let wrappedQuestion = QuizQuestion.matching(question)
        let signature = signature(wrappedQuestion)
        guard usedQuestionSignatures.insert(signature).inserted else { return nil }
        usedCandidateIDs.formUnion(consumedIDs)
        return wrappedQuestion
    }

    static func makeMultipleChoiceQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: Set<String>
    ) -> (QuizMultipleChoiceQuestion, Set<String>)? {
        guard let correctCandidate = nextQuizPromptCandidate(
            from: candidates,
            usedPromptKeys: usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else {
            return nil
        }

        let distractors = bestDistractors(
            for: correctCandidate,
            in: candidates,
            usedCandidateIDs: usedCandidateIDs
        )
        guard !distractors.isEmpty else { return nil }

        // **2026-08-06** — Schlusspunkt bei allen Optionen entfernen
        // (User-Report: zu „Je cherche." standen „nächste Woche",
        // „bar bezahlen", „ich suche" und „Ich heiße." zur Auswahl —
        // nur eine Option trug einen Punkt).
        //
        // Gleiche Klasse von Fehler wie das Fragezeichen weiter unten in
        // `bestDistractors`: Interpunktion, die nur an einer Option
        // hängt, macht sie erkennbar, ohne dass man die Vokabel können
        // muss. Fragezeichen bleiben unangetastet — dort sorgt der
        // Satzart-Abgleich dafür, dass alle vier Optionen dieselbe Form
        // haben, und das Zeichen trägt dort echte Bedeutung.
        let answerLang = correctCandidate.answerLanguageCode
        let correctAnswer = Self.normalizedQuizOption(correctCandidate.answer, languageCode: answerLang)
        let options = Array(
            ([correctAnswer] + distractors.map {
                Self.normalizedQuizOption($0.answer, languageCode: answerLang)
            }).shuffled()
        )
        usedPromptKeys[correctCandidate.promptKey, default: 0] += 1

        return (
            QuizMultipleChoiceQuestion(
                prompt: correctCandidate.prompt,
                correctAnswer: correctAnswer,
                options: options,
                category: correctCandidate.category
            ),
            [correctCandidate.id]
        )
    }

    static func makeMatchingQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: Set<String>
    ) -> (QuizMatchingQuestion, Set<String>)? {
        let available = candidates
            .filter { !usedCandidateIDs.contains($0.id) }
            .filter { usedPromptKeys[$0.promptKey, default: 0] == 0 }
            .uniqued(by: \.promptKey)
            .uniqued(by: \.answerKey)

        let targetPairCount = min(4, available.count)
        guard targetPairCount >= 2 else { return nil }

        let selectedCandidates = Array(available.shuffled().prefix(targetPairCount))
        // **2026-08-06** — Schlusspunkt auf beiden Seiten entfernen
        // (User-Report: „Je crois que." / „Ich glaube, dass." trugen
        // einen Punkt, „mille"/„tausend" und „propre"/„sauber" nicht).
        //
        // Beim Paare-Finden ist das kein Verräter wie beim Multiple
        // Choice, aber eine sichtbare Unruhe: acht Kacheln nebeneinander,
        // zwei davon mit Punkt. Gleiche Behandlung wie dort, damit alle
        // Kacheln gleich aussehen.
        let pairs = selectedCandidates.map {
            QuizMatchingPair(
                prompt: Self.normalizedQuizOption($0.prompt, languageCode: $0.promptLanguageCode),
                answer: Self.normalizedQuizOption($0.answer, languageCode: $0.answerLanguageCode)
            )
        }

        let answerKeys = Set(selectedCandidates.map { $0.answerKey })
        guard answerKeys.count == selectedCandidates.count else { return nil }

        for candidate in selectedCandidates {
            usedPromptKeys[candidate.promptKey, default: 0] += 1
        }

        return (
            QuizMatchingQuestion(
                pairs: pairs,
                shuffledAnswers: pairs.shuffled(),
                category: pairs.count == 1 ? selectedCandidates[0].category : "Paare"
            ),
            Set(selectedCandidates.map(\.id))
        )
    }

    // MARK: - Word Combo (Verb + Noun matching)

    static func nextWordComboQuestion(
        from candidates: [QuizCandidate],
        items: [VocabularyItem],
        direction: Direction,
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: inout Set<String>,
        usedQuestionSignatures: inout Set<String>
    ) -> QuizQuestion? {
        let matchingPairs = VerbNounPairLoader.matchingPairs(for: items)
        guard matchingPairs.count >= 3 else { return nil }

        // Pick 3-4 unique pairs
        let targetCount = min(4, matchingPairs.count)
        var selected: [VerbNounPairLoader.VerbNounPair] = []
        var usedVerbs = Set<String>()
        var usedNouns = Set<String>()

        for pair in matchingPairs.shuffled() {
            let verbKey = pair.verbFr.lowercased()
            let nounKey = pair.nounFr.lowercased()
            guard !usedVerbs.contains(verbKey), !usedNouns.contains(nounKey) else { continue }
            selected.append(pair)
            usedVerbs.insert(verbKey)
            usedNouns.insert(nounKey)
            if selected.count >= targetCount { break }
        }

        guard selected.count >= 3 else { return nil }

        // Build matching pairs: verb = prompt, noun = answer
        let isFrenchSide = direction == .frenchToGerman
        let quizPairs = selected.map { pair in
            QuizMatchingPair(
                prompt: isFrenchSide ? pair.verbFr : pair.verbDe,
                answer: isFrenchSide ? pair.nounFr : pair.nounDe
            )
        }

        let question = QuizMatchingQuestion(
            pairs: quizPairs,
            shuffledAnswers: quizPairs.shuffled(),
            category: "Ausdruck",
            isWordCombo: true
        )

        let wrappedQuestion = QuizQuestion.matching(question)
        let signature = signature(wrappedQuestion)
        guard usedQuestionSignatures.insert(signature).inserted else { return nil }
        return wrappedQuestion
    }

    // MARK: - Fill-in-the-Blanks (from pre-generated sentences)
    //
    // Design-Entscheidung (#7 aus Review): Hier läuft **kein**
    // `MCDistractorFilter`. FillBlank-Distraktoren sind kuratierte
    // **Funktionswörter** (Artikel, Präpositionen, Pronomen) — siehe
    // `FillBlankSentences.tsv` → Spalte `distractors`. Sie sind
    // didaktisch genau auf das jeweilige Blank-Wort und den
    // grammatischen Kontext zugeschnitten (z. B. `le / un / la / du`
    // bei einem Blank-Wort `le`). `MCDistractorFilter` operiert auf
    // Content-Wörtern (Nomen/Verben) mit Level-Bucket/Länge — die
    // beiden Distraktor-Modelle liegen bewusst orthogonal zueinander,
    // eine Vereinheitlichung würde hier die Qualität senken, nicht heben.

    static func nextFillBlanksQuestion(
        items: [VocabularyItem],
        usedSignatures: inout Set<String>
    ) -> QuizQuestion? {
        let matching = FillBlankSentenceLoader.matchingSentences(for: items)
        guard !matching.isEmpty else { return nil }

        // Pick a random sentence that hasn't been used
        for sentence in matching.shuffled() {
            let blankWord = sentence.blankWord
            let sentenceWithBlank = sentence.sentenceFr.replacingOccurrences(
                of: blankWord,
                with: "_____",
                options: [.caseInsensitive],
                range: sentence.sentenceFr.range(of: blankWord, options: .caseInsensitive)
            )

            // Skip if blank replacement didn't work
            guard sentenceWithBlank.contains("_____") else { continue }

            var options = [blankWord] + sentence.distractors.prefix(3)
            options.shuffle()

            let question = QuizFillBlanksQuestion(
                sentenceWithBlank: sentenceWithBlank,
                fullSentence: sentence.sentenceFr,
                translationHint: sentence.sentenceDe,
                correctAnswer: blankWord,
                options: options,
                category: "Lückentext"
            )

            let wrapped = QuizQuestion.fillBlanks(question)
            let sig = signature(wrapped)
            guard usedSignatures.insert(sig).inserted else { continue }
            return wrapped
        }

        return nil
    }

    static func makeQuizCandidates(from items: [VocabularyItem], direction: Direction) -> [QuizCandidate] {
        var seen = Set<String>()
        var candidates: [QuizCandidate] = []

        for item in items {
            // **2026-08-06** — Französische Nomen tragen im Quiz jetzt
            // ihren Artikel (User-Spec: "im Quiz müssen französische
            // Nomen immer mit dem Artikel stehen, zum Beispiel Pizza, da
            // muss stehen la Pizza ... oder l'aéroport").
            //
            // Ohne Artikel ist eine Vokabel unvollständig gelernt: im
            // Französischen gehört das Genus zum Wort, und man sieht es
            // ihm nicht an. `displayFrench(for:)` gab es dafür längst,
            // sie hing bisher aber nur an der Listen-Detailansicht — das
            // Quiz las `item.french` roh. Die Funktion ergänzt nur bei
            // Einzelwort-Nomen und lässt einen schon vorhandenen Artikel
            // unangetastet, Phrasen und Verben bleiben unverändert.
            let frenchRaw = FrenchLemmaFormatter.displayFrench(for: item)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let germanRaw = item.german.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !frenchRaw.isEmpty, !germanRaw.isEmpty else { continue }

            let isFrToDE = direction == .frenchToGerman
            let promptLang = isFrToDE ? "fr-FR" : "de-DE"
            let answerLang = isFrToDE ? "de-DE" : "fr-FR"
            let category = item.cardType.categoryName

            // Lightweight text processing (skip expensive card(for:) pipeline)
            let frenchHint = frenchRaw
            let prompt: String
            let answer: String

            if promptLang == "fr-FR" {
                prompt = frenchRaw.lowercased()
            } else {
                prompt = quizGermanWordCasing(germanRaw, sourceHint: frenchHint)
            }

            if answerLang == "fr-FR" {
                answer = frenchRaw.lowercased()
            } else {
                answer = quizGermanWordCasing(germanRaw, sourceHint: frenchHint)
            }

            let promptKey = fastKey(prompt)
            let answerKey = fastKey(answer)

            guard !promptKey.isEmpty, !answerKey.isEmpty else { continue }
            let uniqueKey = [promptKey, answerKey, category].joined(separator: "|")
            guard seen.insert(uniqueKey).inserted else { continue }

            let hasArticle = startsWithGermanArticle(answer)
            candidates.append(
                QuizCandidate(
                    id: uniqueKey,
                    prompt: prompt,
                    answer: answer,
                    category: category,
                    promptLanguageCode: promptLang,
                    answerLanguageCode: answerLang,
                    promptKey: promptKey,
                    answerKey: answerKey,
                    promptWordCount: prompt.split(separator: " ").count,
                    answerWordCount: answer.split(separator: " ").count,
                    answerCharacterCount: answer.count,
                    answerHasArticle: hasArticle,
                    answerLeadingArticle: leadingGermanArticle(in: answer),
                    answerInitial: answerKey.split(separator: " ").dropFirst(hasArticle ? 1 : 0).first.map { String($0.prefix(1)) } ?? String(answerKey.prefix(1)),
                    isPhrase: category == CardType.phrases.categoryName,
                    // Level durchreichen für das Distraktor-Niveau-Gating.
                    // `VocabularyLevel.rawValue` ist auf Deutsch (Anfänger/
                    // Mittel/Fortgeschritten); `MCDistractorFilter.LevelBucket`
                    // versteht auch diese Strings.
                    level: item.level?.rawValue
                )
            )
        }

        return candidates
    }

    static func nextTypingQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: inout Set<String>,
        usedQuestionSignatures: inout Set<String>
    ) -> QuizQuestion? {
        guard let candidate = nextQuizPromptCandidate(
            from: candidates,
            usedPromptKeys: usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else { return nil }

        let question = QuizTypingQuestion(
            prompt: candidate.prompt,
            correctAnswer: candidate.answer,
            category: candidate.category,
            promptLanguageCode: candidate.promptLanguageCode,
            answerLanguageCode: candidate.answerLanguageCode
        )

        let wrappedQuestion = QuizQuestion.typing(question)
        let sig = QuizBuildService.signature(wrappedQuestion)
        guard usedQuestionSignatures.insert(sig).inserted else { return nil }
        usedPromptKeys[candidate.promptKey, default: 0] += 1
        usedCandidateIDs.insert(candidate.id)
        return wrappedQuestion
    }

    static func nextQuizPromptCandidate(
        from candidates: [QuizCandidate],
        usedPromptKeys: [String: Int],
        usedCandidateIDs: Set<String>
    ) -> QuizCandidate? {
        let sorted = candidates
            .filter { !usedCandidateIDs.contains($0.id) }
            .shuffled()
            .sorted { lhs, rhs in
                let lhsUsage = usedPromptKeys[lhs.promptKey, default: 0]
                let rhsUsage = usedPromptKeys[rhs.promptKey, default: 0]
                return lhsUsage < rhsUsage
            }

        return sorted.first
    }

    /// Entfernt einen abschließenden Punkt. Siehe Begründung in
    /// `makeMultipleChoiceQuestion`.
    ///
    /// Nur der einzelne Schlusspunkt — Auslassungspunkte („…", „...")
    /// bleiben stehen, die sind Teil der Aussage und nicht bloß
    /// Satzschluss.
    static func strippingTerminalPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..") else { return trimmed }
        return String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Punkt entfernen **und** die Groß-/Kleinschreibung neu bestimmen.
    ///
    /// **2026-08-06** — Der Großbuchstabe am Anfang war die zweite Hälfte
    /// desselben Problems wie der Punkt (User-Report: „Ich heiße." stand
    /// zwischen „nächste Woche", „bar bezahlen", „ich suche"). Er
    /// entsteht nicht aus den Daten, sondern aus der Satzanfang-Regel in
    /// `TextNormalizationEngine`: Wo ein Schlusszeichen steht, wird das
    /// erste Wort großgeschrieben. Nimmt man nur den Punkt weg, bleibt
    /// das große „Ich" als schwächerer Verräter übrig.
    ///
    /// Deshalb nach dem Kürzen einmal neu durch die Engine: ohne
    /// Schlusszeichen greift die Satzanfang-Regel nicht mehr, „Ich
    /// heiße" wird zu „ich heiße" — während Nomen („Bibliothek",
    /// „die Bibliothek") großgeschrieben bleiben, weil die Engine
    /// Funktionswörter und Nomen auseinanderhält. Genau dafür ist sie
    /// da; hier wird nichts nachgebaut.
    ///
    /// Nur für Deutsch — französische Antworten haben andere Regeln und
    /// laufen unverändert durch.
    static func normalizedQuizOption(_ text: String, languageCode: String) -> String {
        let stripped = strippingTerminalPeriod(text)
        guard languageCode == "de-DE" else { return stripped }
        return TextNormalizationEngine.normalize(stripped, language: .german)
    }

    /// Ob ein Antworttext eine Frage ist. Grundlage für den Satzart-
    /// Abgleich in `bestDistractors` — siehe Begründung dort.
    ///
    /// Bewusst nur am Fragezeichen festgemacht, nicht an Fragewörtern:
    /// „Wo ist der Bahnhof" ohne Zeichen ist im Datenbestand genauso
    /// eine Aussage-Schreibweise wie „Das ist gut", und eine
    /// Heuristik über Fragewörter würde bei Nebensätzen („Ich weiß, wo
    /// er ist") falsch anschlagen. Das sichtbare Zeichen ist genau das,
    /// was die Antwort verraten hat.
    static func isQuestionForm(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }

    static func bestDistractors(
        for correctCandidate: QuizCandidate,
        in candidates: [QuizCandidate],
        usedCandidateIDs: Set<String>
    ) -> [QuizCandidate] {
        // **2026-08-06, Bug-Fix** — Satzart muss übereinstimmen
        // (User-Report: Frage „C'est elle ?", darunter drei Antworten mit
        // Punkt und genau eine mit Fragezeichen — „da ist ja schon
        // offensichtlich, was die richtige Antwort ist"). Eine
        // Übersetzungsaufgabe darf sich nicht über die Interpunktion
        // verraten; wer die Vokabel nicht kann, soll trotzdem raten
        // müssen.
        let correctIsQuestion = Self.isQuestionForm(correctCandidate.answer)
        let exactStructurePool = candidates.filter {
            $0.id != correctCandidate.id &&
            !usedCandidateIDs.contains($0.id) &&
            $0.answerKey != correctCandidate.answerKey &&
            $0.category == correctCandidate.category &&
            $0.isPhrase == correctCandidate.isPhrase &&
            Self.isQuestionForm($0.answer) == correctIsQuestion
        }

        // Level-Gating: aus dem strukturell passenden Pool zuerst die
        // Kandidaten im **gleichen Level-Bucket** wie die korrekte
        // Antwort versuchen (A1/A2 = .basic, B1/B2 = .intermediate,
        // C1/C2 = .advanced). Erst wenn dort zu wenig Treffer → Fallback
        // auf den vollen Struktur-Pool, dann auf alle Kandidaten. Das
        // verhindert „Portfolio" als Distraktor bei „Auto" ohne den
        // bestehenden Scoring-Kern zu brechen.
        let correctBucket = MCDistractorFilter.LevelBucket.bucket(for: correctCandidate.level)
        let levelMatchedPool: [QuizCandidate]
        if let correctBucket {
            levelMatchedPool = exactStructurePool.filter {
                MCDistractorFilter.LevelBucket.bucket(for: $0.level) == correctBucket
            }
        } else {
            levelMatchedPool = []
        }

        // **2026-08-06** — Letzte Stufe war bisher `candidates` (alles).
        // Damit hätte der Satzart-Filter oben nichts genützt, sobald zu
        // wenige strukturgleiche Kandidaten übrig sind: die Frage-/
        // Aussage-Mischung wäre über den Fallback zurückgekommen. Jetzt
        // eine Zwischenstufe, die nur die Satzart erzwingt, und erst
        // ganz zuletzt der ungefilterte Pool.
        let questionMatchedPool = candidates.filter {
            $0.id != correctCandidate.id &&
            $0.answerKey != correctCandidate.answerKey &&
            Self.isQuestionForm($0.answer) == correctIsQuestion
        }

        let scoringPool: [QuizCandidate]
        if levelMatchedPool.count >= 3 {
            scoringPool = levelMatchedPool
        } else if exactStructurePool.count >= 3 {
            scoringPool = exactStructurePool
        } else if questionMatchedPool.count >= 3 {
            scoringPool = questionMatchedPool
        } else {
            scoringPool = candidates
        }

        let coarseRanked = scoringPool.compactMap { candidate -> (QuizCandidate, Double)? in
            guard candidate.id != correctCandidate.id else { return nil }
            guard candidate.answerKey != correctCandidate.answerKey else { return nil }
            guard normalizedLookupText(candidate.answer) != normalizedLookupText(correctCandidate.answer) else { return nil }
            guard candidate.answer.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(correctCandidate.answer.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame else { return nil }

            let score = coarseDistractorScore(candidate, against: correctCandidate)
            guard score > 0 else { return nil }
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.answer.localizedCaseInsensitiveCompare(rhs.0.answer) == .orderedAscending
            }
            return lhs.1 > rhs.1
        }
        .prefix(16)

        let scored = coarseRanked.map { candidate, coarseScore in
            (candidate, coarseScore + lexicalDistractorScore(candidate, against: correctCandidate))
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.answer.localizedCaseInsensitiveCompare(rhs.0.answer) == .orderedAscending
            }
            return lhs.1 > rhs.1
        }

        var selected: [QuizCandidate] = []
        var seenAnswerKeys = Set<String>()

        for (candidate, _) in scored {
            guard seenAnswerKeys.insert(candidate.answerKey).inserted else { continue }
            selected.append(candidate)
            if selected.count == 3 { break }
        }

        if selected.count < 2 {
            let fallback = scoringPool.shuffled().filter {
                $0.id != correctCandidate.id &&
                !usedCandidateIDs.contains($0.id) &&
                $0.answerKey != correctCandidate.answerKey &&
                !seenAnswerKeys.contains($0.answerKey)
            }
            for candidate in fallback {
                guard seenAnswerKeys.insert(candidate.answerKey).inserted else { continue }
                selected.append(candidate)
                if selected.count == 3 { break }
            }
        }

        return selected
    }

    static func coarseDistractorScore(_ candidate: QuizCandidate, against correctCandidate: QuizCandidate) -> Double {
        var score = 0.0

        if candidate.category == correctCandidate.category {
            score += 4.0
        }

        if candidate.isPhrase == correctCandidate.isPhrase {
            score += 2.2
        }

        let answerWordDelta = abs(candidate.answerWordCount - correctCandidate.answerWordCount)
        score += max(0, 3.0 - Double(answerWordDelta))

        let answerCharacterDelta = abs(candidate.answerCharacterCount - correctCandidate.answerCharacterCount)
        score += max(0, 2.5 - Double(answerCharacterDelta) / 4.0)

        if candidate.answerHasArticle == correctCandidate.answerHasArticle {
            score += 1.5
        }

        if candidate.answerLeadingArticle == correctCandidate.answerLeadingArticle {
            score += 1.7
        }

        if candidate.answerInitial == correctCandidate.answerInitial {
            score += 1.2
        }

        if candidate.answer.contains(",") == correctCandidate.answer.contains(",") {
            score += 0.8
        }

        if candidate.promptWordCount == correctCandidate.promptWordCount {
            score += 0.7
        }

        // Level-Match-Bonus — greift nur, wenn beide Kandidaten ein
        // erkennbares Level haben. Zweistufig: exakt-selber-Bucket (+2.5)
        // oder Nachbar-Bucket (+0.8). Falls die Pools bereits nach
        // Level gefiltert wurden (siehe `bestDistractors`), addiert der
        // Bonus nur noch die feinere Ordnung zwischen gleich-gebucketen.
        if let candidateBucket = MCDistractorFilter.LevelBucket.bucket(for: candidate.level),
           let correctBucket = MCDistractorFilter.LevelBucket.bucket(for: correctCandidate.level) {
            if candidateBucket == correctBucket {
                score += 2.5
            } else if correctBucket.neighbors.contains(candidateBucket) {
                score += 0.8
            } else {
                // Ferne Buckets (A1 vs C2) werden aktiv abgestraft —
                // Fallback-Kaskade darf sie nur zulassen, wenn gar nichts
                // Passendes übrig bleibt.
                score -= 2.0
            }
        }

        return score
    }

    static func lexicalDistractorScore(_ candidate: QuizCandidate, against correctCandidate: QuizCandidate) -> Double {
        let lexicalDistance = Double(levenshteinDistance(candidate.answerKey, correctCandidate.answerKey))
        let normalizedDistance = lexicalDistance / Double(max(correctCandidate.answerKey.count, candidate.answerKey.count, 1))
        var score = max(0, 2.2 - normalizedDistance * 3.0)

        if normalizedDistance < 0.08 {
            score -= 8
        }

        return score
    }

    static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var distances = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count {
            distances[i][0] = i
        }
        for j in 0...b.count {
            distances[0][j] = j
        }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    distances[i][j] = distances[i - 1][j - 1]
                } else {
                    distances[i][j] = min(
                        distances[i - 1][j] + 1,
                        distances[i][j - 1] + 1,
                        distances[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return distances[a.count][b.count]
    }
}
