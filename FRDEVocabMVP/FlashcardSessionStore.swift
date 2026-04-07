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
