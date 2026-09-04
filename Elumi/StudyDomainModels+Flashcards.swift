import Foundation

struct FlashcardDeckCard: Identifiable, Codable, Equatable {
    let id: String
    let french: String
    let german: String
    let sourceLanguage: StudyLanguage
    let cardType: CardType

    init(id: String, french: String, german: String, sourceLanguage: StudyLanguage, cardType: CardType = .words) {
        self.id = id
        self.french = french
        self.german = german
        self.sourceLanguage = sourceLanguage
        self.cardType = cardType
    }

    private enum CodingKeys: String, CodingKey {
        case id, french, german, sourceLanguage, cardType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.french = try container.decode(String.self, forKey: .french)
        self.german = try container.decode(String.self, forKey: .german)
        self.sourceLanguage = try container.decode(StudyLanguage.self, forKey: .sourceLanguage)
        // Abwärtskompatibel: ältere Codings ohne cardType als Wörter behandeln.
        self.cardType = try container.decodeIfPresent(CardType.self, forKey: .cardType) ?? .words
    }

    func card(for direction: Direction) -> FlashCard {
        // Karteikarten sind reine Render-Schicht — KEINE eigene Artikel-/Casing-
        // Logik. Exakt die gleichen zentralen Display-Helfer wie Training/Quiz
        // nutzen, damit ein Eintrag in allen Modi identisch dargestellt wird.
        //
        // `frenchStudyCardDisplayText` / `germanStudyCardDisplayText` sind die
        // Single-Source-of-Truth: TextCasingRules, `isNonNoun`-Check,
        // `leadingFrenchArticle`-Kurzschluss und Nomen-Artikel-Heuristik sind
        // dort zentral gekapselt. Alles, was die Karteikarte früher selbst an
        // Artikeln voranstellte (mit eigenen Pronoun-/Funktionswort-Listen),
        // wurde entfernt.
        let studyFrench = frenchStudyCardDisplayText(
            french,
            matchingGerman: german,
            cardType: cardType,
            sourceLanguage: sourceLanguage
        )
        let studyGerman = germanStudyCardDisplayText(
            german,
            matchingFrench: french,
            cardType: cardType
        )
        let synchronizedPair = synchronizedPairTerminalSentencePunctuation(
            source: studyFrench,
            target: studyGerman,
            sourceLanguage: sourceLanguage,
            cardType: cardType
        )

        switch direction {
        case .frenchToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "fr-FR",
                answerLanguageCode: "de-DE",
                category: "Karteikarte",
                wordClass: nil
            )
        case .germanToFrench:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "fr-FR",
                category: "Karteikarte",
                wordClass: nil
            )
        case .englishToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "en-US",
                answerLanguageCode: "de-DE",
                category: "Karteikarte",
                wordClass: nil
            )
        case .germanToEnglish:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "en-US",
                category: "Karteikarte",
                wordClass: nil
            )
        }
    }

}

struct FlashcardDeck: Identifiable, Equatable {
    let id: String
    let name: String
    let sourceLanguage: StudyLanguage
    let cards: [FlashcardDeckCard]
}

enum MasteryLevel: String, Codable {
    case open
    case almostMastered
    case mastered

    var label: String {
        switch self {
        case .open: return "Offen"
        case .almostMastered: return "Fast sicher"
        case .mastered: return "Sicher"
        }
    }

    var color: String {
        switch self {
        case .open: return "red"
        case .almostMastered: return "yellow"
        case .mastered: return "green"
        }
    }
}

struct CardMastery: Codable, Equatable {
    var consecutiveCorrect: Int = 0
    /// Sticky-Flag: Sobald eine Karte mind. einmal falsch beantwortet wurde,
    /// bleibt `hasBeenWrong` true — auch wenn später richtig geantwortet wird.
    /// Ermöglicht die rote „Problem"-Markierung im Fortschrittsbalken.
    var hasBeenWrong: Bool = false

    /// Dynamischer Level-Lookup: `threshold` bestimmt, wann eine Karte aus dem
    /// Stapel fällt. 1× richtig → direkt mastered. Bei 2×/3× gibt es eine
    /// „fast"-Zwischen-Stufe für alle Karten, die schon mindestens einmal
    /// richtig waren, aber die Schwelle noch nicht erreicht haben.
    func level(threshold: Int) -> MasteryLevel {
        let effective = max(1, threshold)
        if consecutiveCorrect >= effective { return .mastered }
        if consecutiveCorrect > 0 { return .almostMastered }
        return .open
    }

    mutating func markCorrect() {
        consecutiveCorrect += 1
    }

    mutating func markWrong() {
        consecutiveCorrect = 0
        hasBeenWrong = true
    }

    private enum CodingKeys: String, CodingKey {
        case consecutiveCorrect, hasBeenWrong
    }

    init(consecutiveCorrect: Int = 0, hasBeenWrong: Bool = false) {
        self.consecutiveCorrect = consecutiveCorrect
        self.hasBeenWrong = hasBeenWrong
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.consecutiveCorrect = try container.decodeIfPresent(Int.self, forKey: .consecutiveCorrect) ?? 0
        // Abwärtskompatibel: ältere Session-Snapshots ohne Flag → false.
        self.hasBeenWrong = try container.decodeIfPresent(Bool.self, forKey: .hasBeenWrong) ?? false
    }
}

struct FlashcardSessionState: Codable, Equatable {
    var deckID: String
    var direction: Direction
    var remainingCardIDs: [String]
    var currentCardID: String?
    var correctCount: Int
    var wrongCount: Int
    var isCompleted: Bool
    var cardMastery: [String: CardMastery] = [:]
    /// Streak-Snapshot für Session-Resume — ohne diesen würde ein
    /// unterbrochener und fortgesetzter Flashcard-Durchlauf den Combo-
    /// Zähler auf 0 zurücksetzen, obwohl der User gerade 4× in Folge
    /// richtig beantwortet hat. Default-Instanz auf Snapshot-Ebene,
    /// damit alte persistierte JSON-Dumps (ohne dieses Feld) weiter
    /// dekodieren (siehe `init(from:)`).
    var streak: SessionStreak = SessionStreak()

    /// Anzahl Karten, die bei dem gegebenen `threshold` schon aus dem Stapel
    /// gefallen sind (consecutiveCorrect >= threshold).
    func masteredCardCount(threshold: Int) -> Int {
        cardMastery.values.filter { $0.level(threshold: threshold) == .mastered }.count
    }

    /// Karten im Stapel, die schon einmal richtig waren, aber die Schwelle
    /// noch nicht erreicht haben. Bei threshold = 1 gibt es keinen Zwischen-
    /// Zustand → immer 0.
    func almostMasteredCardCount(threshold: Int) -> Int {
        cardMastery.values.filter { $0.level(threshold: threshold) == .almostMastered }.count
    }

    /// Karten, die noch nicht richtig beantwortet wurden (consecutiveCorrect = 0).
    func openCardCount(threshold: Int) -> Int {
        let mastered = masteredCardCount(threshold: threshold)
        let almost = almostMasteredCardCount(threshold: threshold)
        let allCardCount = remainingCardIDs.count + mastered
        return allCardCount - mastered - almost
    }

    /// Anzahl Karten, die mind. einmal falsch beantwortet wurden und noch im
    /// Stapel sind (also nicht gemastered). Für die rote Problem-Markierung im
    /// Fortschrittsbalken — `wrongCount` (globale Antwort-Summe) ist etwas
    /// anderes und wird nur im Text-Label angezeigt.
    func wrongAnsweredCardCount(threshold: Int) -> Int {
        cardMastery.values.filter {
            $0.hasBeenWrong && $0.level(threshold: threshold) != .mastered
        }.count
    }

    // MARK: - Codable (abwärtskompatibel)

    private enum CodingKeys: String, CodingKey {
        case deckID, direction, remainingCardIDs, currentCardID
        case correctCount, wrongCount, isCompleted, cardMastery
        case streak
    }

    init(
        deckID: String,
        direction: Direction,
        remainingCardIDs: [String],
        currentCardID: String?,
        correctCount: Int,
        wrongCount: Int,
        isCompleted: Bool,
        cardMastery: [String: CardMastery] = [:],
        streak: SessionStreak = SessionStreak()
    ) {
        self.deckID = deckID
        self.direction = direction
        self.remainingCardIDs = remainingCardIDs
        self.currentCardID = currentCardID
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.isCompleted = isCompleted
        self.cardMastery = cardMastery
        self.streak = streak
    }

    /// Abwärtskompatibler Decode: ältere Session-Snapshots haben kein
    /// `streak`-Feld (wurde erst mit dem zentralen `SessionStreak`-
    /// Refactor eingeführt). Fehlt es, bekommt der Restore einen frischen
    /// Streak — die laufende Serie beginnt sauber bei 0, der User verliert
    /// nur den Live-Combo-Stand, nicht die Session selbst.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deckID = try container.decode(String.self, forKey: .deckID)
        self.direction = try container.decode(Direction.self, forKey: .direction)
        self.remainingCardIDs = try container.decode([String].self, forKey: .remainingCardIDs)
        self.currentCardID = try container.decodeIfPresent(String.self, forKey: .currentCardID)
        self.correctCount = try container.decode(Int.self, forKey: .correctCount)
        self.wrongCount = try container.decode(Int.self, forKey: .wrongCount)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.cardMastery = try container.decodeIfPresent([String: CardMastery].self, forKey: .cardMastery) ?? [:]
        self.streak = try container.decodeIfPresent(SessionStreak.self, forKey: .streak) ?? SessionStreak()
    }
}
