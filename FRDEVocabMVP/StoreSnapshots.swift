import Foundation

struct VocabularyListStoreSnapshot {
    let customLists: [VocabularyList]
    let selectedListID: UUID
}

struct FlashcardSessionStoreSnapshot {
    let selectedDeckID: String
    let selectedDirection: Direction
    let session: FlashcardSessionState?
}
