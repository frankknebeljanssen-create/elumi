import Foundation
import SwiftUI

@MainActor
final class FlashcardSessionStore: ObservableObject {
    @Published var customDeck: FlashcardDeck?
    @Published var selectedDeckID: String {
        didSet {
            repository.persistSelectedDeckID(selectedDeckID, key: selectedDeckKey)
            ensureValidSession()
        }
    }
    @Published var selectedDirection: Direction {
        didSet {
            repository.persistSelectedDirection(selectedDirection, key: selectedDirectionKey)
            ensureValidSession()
        }
    }
    @Published var session: FlashcardSessionState? {
        didSet { persistSessionIfNeeded() }
    }

    let sessionKey = "FRDEVocabMVP.flashcardSession.v1"
    let selectedDeckKey = "FRDEVocabMVP.flashcardDeck.v1"
    let selectedDirectionKey = appDirectionKey
    let sessionSaveDelay: TimeInterval = 0.18
    let repository: FlashcardSessionRepository
    var pendingSessionSaveWorkItem: DispatchWorkItem?
    var lastPersistedSessionData: Data?

    /// In-Memory-Puffer der zuletzt gezeigten Karten-IDs. Dient dazu,
    /// Wiederholungen kurz hintereinander zu vermeiden — nicht persistiert,
    /// weil der Buffer nur für die aktuelle Abfrage-Serie relevant ist.
    /// FIFO mit Cap; siehe `chooseNextCard(avoiding:)`.
    var recentCardIDs: [String] = []

    /// Anzahl richtiger Antworten hintereinander, nach der eine Karte aus dem
    /// Stapel fällt. Wird beim Start aus den Setup-Einstellungen gesetzt.
    /// `@Published`, damit die abgeleiteten `masteredCount` / `almostMasteredCount`
    /// / `openCount` und der `progressText`-View neu rendern, sobald sich der
    /// Wert im Setup ändert. Default 2 (wie bisher).
    @Published var masteryThreshold: Int = 2

    /// Live-Combo: Anzahl direkt aufeinanderfolgender richtiger Antworten in
    /// der aktuellen Session. Reset bei `markWrong()` und Session-Restart.
    /// Wird vom `ProgressService` für den Combo-Bonus ausgelesen. Läuft
    /// zentral über `SessionStreak` — Karteikarten haben pro Karte genau
    /// einen Antwort-Tap, `firstAttempt` ist deshalb immer `true`.
    // Nicht `private(set)`, damit Extensions (in separaten Files) den
    // Streak mutieren dürfen — Antwort-Pfad lebt in
    // `FlashcardSessionStore+SessionFlow.swift`.
    var streak = SessionStreak()
    var sessionCurrentCombo: Int { streak.current }
    var sessionLongestCombo: Int { streak.longest }
    /// Anzahl der Karten, die in dieser Session NEU gemastered wurden
    /// (also gerade jetzt aus dem Stapel fielen). Für die Mastery-XP-Vergabe.
    var sessionMasteredThisRun: Int = 0
    /// Snapshot „wurde diese Session schon ausgewertet?" — verhindert
    /// doppelte XP-Buchung bei mehrfachem `onAppear` der Completion-Card.
    var sessionRewardConsumed: Bool = false

    init(
        repository: FlashcardSessionRepository = FlashcardSessionRepository(),
        snapshot: FlashcardSessionStoreSnapshot? = nil
    ) {
        self.repository = repository
        let defaultDeckID = DataStore.flashcardDecks.first?.id ?? "flashcards-1"
        let resolvedSnapshot = snapshot ?? repository.loadSnapshot(
            defaultDeckID: defaultDeckID,
            selectedDeckKey: selectedDeckKey,
            selectedDirectionKey: selectedDirectionKey,
            sessionKey: sessionKey
        )
        self.selectedDeckID = resolvedSnapshot.selectedDeckID
        self.selectedDirection = resolvedSnapshot.selectedDirection
        self.session = resolvedSnapshot.session
        self.lastPersistedSessionData = resolvedSnapshot.session.flatMap { try? JSONEncoder().encode($0) }

        if isTransientCustomDeckID(selectedDeckID) {
            self.selectedDeckID = defaultDeckID
        }

        if let session, isTransientCustomDeckID(session.deckID) {
            self.session = nil
        }

        ensureValidSession()
    }

}
