import Foundation
import SwiftUI
import Combine

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

    /// **Persönlicher Trainingsmodus** (Phase 8): wenn die aktuelle
    /// Session aus einem `PersonalDeck` gestartet wurde, hält dieses Feld
    /// dessen ID. Nicht persistiert — wird beim Session-Start gesetzt und
    /// bei Session-Ende (Sync) wieder auf nil geworfen. Alle
    /// personal-deck-spezifischen UI-Hooks (Badge, Tag-Label-Variante,
    /// Fortschritts-Sync) prüfen auf diesen Wert.
    @Published var activePersonalDeckID: UUID? = nil

    /// Combine-Subscriptions für den Per-Card-Auto-Save des
    /// Persönlichen Trainingsmodus. Lebt so lange wie der Store —
    /// der Store selbst ist im AppRuntimeContainer pro App-Session
    /// einmalig allokiert.
    private var personalDeckCancellables: Set<AnyCancellable> = []

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
        setupPersonalDeckAutoSave()
    }

    // MARK: - Personal-Deck Per-Card Auto-Save (Phase 8)

    /// Registriert einen Combine-Sink auf `session.currentCardID`.
    /// Jede Kartenpositions-Änderung während einer Personal-Deck-Session
    /// triggert `savePersonalDeckProgressIfNeeded()`. `removeDuplicates()`
    /// verhindert redundante Saves bei No-Op-Publishes des Session-
    /// State-Objekts (z. B. bei `session.streak`-Updates, die den Snapshot
    /// neu emittieren, aber die Karten-Position nicht ändern).
    ///
    /// Der Sink feuert auch während regulärer (Nicht-Personal-Deck-)
    /// Sessions — dort schützt der Guard in `savePersonalDeckProgressIfNeeded`
    /// (prüft `activePersonalDeckID`). Bei nil-Case No-Op, keine I/O.
    private func setupPersonalDeckAutoSave() {
        $session
            .compactMap { $0?.currentCardID }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.savePersonalDeckProgressIfNeeded()
            }
            .store(in: &personalDeckCancellables)
    }

    /// Per-Card-Save: schreibt den aktuellen Personal-Deck-Fortschritt
    /// (`currentIndex` + `masteredCardIDs`) sofort in den
    /// `PersonalDeckStore`. **Unterschied zum Teardown-Sync in
    /// `FlashcardsView+PersonalDeck.syncPersonalDeckProgressIfNeeded`**:
    ///   • Kein `activePersonalDeckID = nil` → Session bleibt aktiv
    ///   • Kein `lastAccessedAt = Date()` → bleibt unberührt, der
    ///     Zeitstempel dokumentiert ausschließlich „Stapel verlassen",
    ///     nicht „Karte gespielt".
    ///
    /// No-Op, wenn `activePersonalDeckID == nil` (reguläre Session) oder
    /// wenn der Stapel zwischenzeitlich gelöscht wurde.
    func savePersonalDeckProgressIfNeeded() {
        guard let deckID = activePersonalDeckID,
              let deck = PersonalDeckStore.shared.deck(withID: deckID),
              let session = session else {
            // Diagnose: warum sind wir kein-op?
            if activePersonalDeckID != nil {
                appDebugLog("⚠️ savePersonalDeckProgress no-op: deck=\(PersonalDeckStore.shared.deck(withID: activePersonalDeckID!) != nil) session=\(session != nil)")
            }
            return
        }

        // currentIndex: Position der aktuell sichtbaren Karte im
        // unveränderlichen `cardOrder`-Array. Fallback auf den bisherigen
        // `deck.currentIndex`, falls die ID nicht im Array gefunden wird
        // (z. B. weil das Deck nachträglich mutiert wurde).
        let computedIndex: Int = {
            guard let cardIDString = session.currentCardID,
                  let uuid = UUID(uuidString: cardIDString),
                  let idx = deck.cardOrder.firstIndex(of: uuid) else {
                return deck.currentIndex
            }
            return idx
        }()

        // Gemeisterte Karten: alle IDs in `session.cardMastery`, die den
        // aktiven Threshold erreicht haben. `union` mit dem bestehenden
        // Set, damit nie etwas verloren geht, falls der Sink mehrmals
        // hintereinander feuert.
        let threshold = masteryThreshold
        let newlyMastered: [UUID] = session.cardMastery.compactMap { pair in
            guard pair.value.level(threshold: threshold) == .mastered,
                  let uuid = UUID(uuidString: pair.key) else { return nil }
            return uuid
        }
        let updatedMasteredSet = deck.masteredCardIDs.union(newlyMastered)

        // No-Op, wenn weder Index noch Mastery-Set sich geändert haben —
        // schont UserDefaults-Writes bei schnellen Re-Publishes.
        guard computedIndex != deck.currentIndex
                || updatedMasteredSet != deck.masteredCardIDs else {
            return
        }

        PersonalDeckStore.shared.update(id: deckID) { mutableDeck in
            mutableDeck.currentIndex = computedIndex
            mutableDeck.masteredCardIDs = updatedMasteredSet
            // `lastAccessedAt` bleibt absichtlich unverändert — siehe
            // Doc-Header oben.
        }
        appDebugLog("💾 perCardSave deckID=\(deckID) currentIndex=\(computedIndex) mastered=\(updatedMasteredSet.count)/\(deck.cardOrder.count)")
    }
}
