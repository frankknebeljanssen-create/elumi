import Foundation

/// Thin Convenience-Layer für die Module-Hooks.
///
/// Ohne Recorder müsste jeder Aufrufer (FlashcardSessionStore,
/// TrainingSessionController, VerbformsSessionController,
/// QuizSessionController) selbst direkt auf den Store zugreifen und die
/// Quiz-Spezialität (Prompt↔Answer-Mapping je nach Direction) implementieren.
/// Der Recorder zentralisiert genau diese Logik, damit die Hook-Stellen
/// in den Controllern einzeilig bleiben.
enum ItemLearningStatusRecorder {

    /// Standard-Path für Flashcards/Training/Verbformen — die Module
    /// wissen direkt, was french/german/cardType ist.
    @MainActor
    static func record(
        french: String,
        german: String,
        cardType: CardType,
        correct: Bool
    ) {
        ItemLearningStatusStore.shared.recordAnswer(
            french: french,
            german: german,
            cardType: cardType,
            correct: correct
        )
    }

    /// Quiz-Spezial-Pfad: im Quiz hängt die French/German-Zuordnung an
    /// der aktiven Direction ab. Bei `.frenchToGerman` ist der Prompt
    /// das französische Wort und die correctAnswer das deutsche — bei
    /// `.germanToFrench` genau umgekehrt.
    ///
    /// **MVP-Scope**: nur FR↔DE wird getrackt. Die beiden englischen
    /// Direction-Varianten (`.englishToGerman` / `.germanToEnglish`) sind
    /// für Scan-/Import-Zwecke vorgesehen und liefern hier keinen sinnvollen
    /// FR/DE-Tupel — der Recorder ignoriert sie geräuschlos.
    @MainActor
    static func recordFromQuiz(
        prompt: String,
        correctAnswer: String,
        direction: Direction,
        cardType: CardType,
        correct: Bool
    ) {
        let french: String
        let german: String
        switch direction {
        case .frenchToGerman:
            french = prompt
            german = correctAnswer
        case .germanToFrench:
            french = correctAnswer
            german = prompt
        case .englishToGerman, .germanToEnglish:
            return
        }
        record(french: french, german: german, cardType: cardType, correct: correct)
    }
}
