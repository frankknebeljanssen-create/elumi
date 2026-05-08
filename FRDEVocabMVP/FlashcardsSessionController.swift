import Foundation
import SwiftUI

@MainActor
final class FlashcardsSessionController: ObservableObject {
    @Published var lastResult: ScoreResult?
    @Published var showingSolution = false
    @Published var isFlashcardFlipped = false

    /// **User-Revision 2026-04-22**: Bei einer falschen Antwort bleibt
    /// die Karte auf der Rückseite sichtbar, **bis** der User den
    /// „Weiter"-Button in der Antwort-Card drückt. Vorher lief nach
    /// 1,5 s ein Auto-Advance — der wird durch diesen Flag pausiert.
    /// Der Flag wird nur durch `continueAfterWrongAnswer(...)` oder
    /// einen expliziten Kartenwechsel (Swipe) wieder auf false gesetzt.
    @Published var isAwaitingContinueAfterWrong: Bool = false

    /// **Peek-Protection (User-Revision 2026-04-22)**: Wenn der User
    /// die Karte manuell umdreht (revealSolution), ohne sie vorher
    /// beantwortet zu haben, wird sie als „nicht gekonnt" gewertet.
    /// Dieser Flag hält die CardID, die im aktuellen Durchgang bereits
    /// gepeekt wurde. Wird beim Karten-Wechsel wieder auf nil gesetzt.
    @Published var peekedCurrentCardID: String? = nil

    /// UI-Toast: „Karte als nicht gekonnt gewertet" — kurz nach Peek
    /// sichtbar (0,3 s Fade-in, 1,5 s zu sehen, 0,3 s Fade-out). Wird
    /// vom Flashcard-View als Overlay unter der Karte genutzt.
    @Published var peekToastVisible: Bool = false
    @Published var cardFlyOutOffset: CGFloat = 0
    @Published var cardFlyOutRotation: Double = 0
    @Published var cardFlyOutOpacity = 1.0
    @Published var typedAnswer = ""
    @Published var showingTypedAnswerInput = false

    /// **Sweep C — AnswerMode (2026-05-07)** — Aktiver Sprechen/Tippen-
    /// Modus für die Karteikarten-Session. Initial-Wert kommt aus
    /// `@AppStorage` (`appAnswerModeKarteikartenKey`); Setup-Screen
    /// schreibt durch via `karteikartenAnswerModeBinding` (siehe
    /// `FlashcardsView.swift`). Slot-launched Sessions starten mit
    /// dem persistierten Wert.
    ///
    /// Render-Branch in `FlashcardsView+InputActionComponents`:
    ///   • `.speech` — Mikrofon + Speaker primär, Tastatur als Reveal-
    ///     on-tap-Fallback (existing Behavior).
    ///   • `.tap` — Typed-Answer-Card direkt sichtbar, kein Mikrofon.
    @Published var answerMode: AnswerMode = {
        let raw = UserDefaults.standard.string(forKey: appAnswerModeKarteikartenKey)
        return raw.flatMap { AnswerMode(rawValue: $0) } ?? .speech
    }()
    @Published var isMicPulseVisible = false
    @Published var displayedFlashCard: FlashCard?

    /// Live-Offset, während der User die Karte mit dem Finger zieht.
    /// 0 = Ruheposition. Negativer Wert = nach links (Weiter), positiv = rechts (Zurück).
    @Published var swipeDragOffset: CGFloat = 0
    /// Wird nach dem ersten erfolgreichen Swipe in UserDefaults persistiert,
    /// damit der „wischen"-Hint danach dauerhaft ausgeblendet bleibt.
    /// Migrations-Key v2: nach Layout-Umbau einmalig neu zeigen.
    @Published var hasSeenSwipeHint: Bool = UserDefaults.standard.bool(forKey: "FRDEVocabMVP.flashcards.hasSeenSwipeHint.v2")

    func markSwipeHintSeen() {
        guard !hasSeenSwipeHint else { return }
        hasSeenSwipeHint = true
        UserDefaults.standard.set(true, forKey: "FRDEVocabMVP.flashcards.hasSeenSwipeHint.v2")
    }

    var shouldEvaluateAfterStop = false
    var wasSpeakerSpeaking = false
    var pendingFeedbackTask: DispatchWorkItem?
    var flashcardHistory: [HistoryEntry] = []

    var currentFlashCard: FlashCard? {
        displayedFlashCard
    }

    var canRestorePreviousFlashcard: Bool {
        !flashcardHistory.isEmpty
    }

    deinit {
        pendingFeedbackTask?.cancel()
    }
}
