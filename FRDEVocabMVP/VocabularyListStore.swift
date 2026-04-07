import Foundation
import SwiftUI

@MainActor
final class VocabularyListStore: ObservableObject {
    nonisolated static let builtInListID = UUID(uuidString: "5A30AE93-0F08-4A96-B55A-A77E3F4D2A9B")!
    nonisolated static let allCustomVocabularyListID = UUID(uuidString: "E0E54C25-C9F2-426A-B9CB-F4575B4C9B59")!
    nonisolated static let dictionaryListID = dictionaryVocabularyListID

    @Published var customLists: [VocabularyList] = [] {
        didSet {
            rebuildDerivedLists()
            guard !isApplyingStoredState else { return }
            saveCustomLists()
        }
    }
    @Published var selectedListID: UUID = builtInListID {
        didSet {
            guard !isApplyingStoredState else { return }
            saveSelectedListID()
        }
    }

    let customListsKey = "FRDEVocabMVP.customLists.v2"
    let selectedListKey = "FRDEVocabMVP.selectedListID.v2"
    let sampleListsSeededKey = "FRDEVocabMVP.sampleListsSeeded.v1"
    private let builtInListStorage: VocabularyList
    private let builtInWordsCountStorage: Int
    private let builtInPhrasesCountStorage: Int
    let repository: VocabularyListStoreRepository
    var isApplyingStoredState = false
    var sortedCustomListsStorage: [VocabularyList] = []
    var allCustomVocabularyListStorage: VocabularyList?
    var practiceListsStorage: [VocabularyList] = []

    init(
        repository: VocabularyListStoreRepository = VocabularyListStoreRepository(),
        snapshot: VocabularyListStoreSnapshot? = nil
    ) {
        self.repository = repository
        let builtInList = VocabularyList(
            id: Self.builtInListID,
            name: "Standardpaket",
            items: DataStore.builtInVocabularyItems,
            isBuiltIn: true
        )
        self.builtInListStorage = builtInList
        self.builtInWordsCountStorage = builtInList.items.filter { $0.cardType == .words }.count
        self.builtInPhrasesCountStorage = builtInList.items.filter { $0.cardType == .phrases }.count
        if let snapshot {
            apply(snapshot: snapshot)
        } else {
            loadState()
        }
    }

    var builtInList: VocabularyList {
        builtInListStorage
    }

    var builtInWordsCount: Int {
        builtInWordsCountStorage
    }

    var builtInPhrasesCount: Int {
        builtInPhrasesCountStorage
    }

    var allLists: [VocabularyList] {
        [builtInList] + customLists
    }

    var sortedCustomLists: [VocabularyList] {
        sortedCustomListsStorage
    }

    var allCustomVocabularyList: VocabularyList? {
        allCustomVocabularyListStorage
    }

    var practiceLists: [VocabularyList] {
        practiceListsStorage
    }

    var selectedList: VocabularyList {
        allLists.first(where: { $0.id == selectedListID }) ?? builtInList
    }

    var selectedCustomList: VocabularyList? {
        customLists.first(where: { $0.id == selectedListID })
    }
}
