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
            scheduleSave()
        }
    }
    @Published var selectedListID: UUID = builtInListID {
        didSet {
            guard !isApplyingStoredState else { return }
            saveSelectedListID()
        }
    }

    private var pendingSaveWorkItem: DispatchWorkItem?

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveCustomLists()
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
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
        let totalStart = CFAbsoluteTimeGetCurrent()
        self.repository = repository

        var start = CFAbsoluteTimeGetCurrent()
        let items = DataStore.builtInVocabularyItems
        print("⏱ [ListStore.init] builtInVocabularyItems: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(items.count) items)")

        start = CFAbsoluteTimeGetCurrent()
        let builtInList = VocabularyList(
            id: Self.builtInListID,
            name: "Standardpaket",
            items: items,
            isBuiltIn: true
        )
        self.builtInListStorage = builtInList
        self.builtInWordsCountStorage = builtInList.items.filter { $0.cardType == .words }.count
        self.builtInPhrasesCountStorage = builtInList.items.filter { $0.cardType == .phrases }.count
        print("⏱ [ListStore.init] builtInList+filters: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")

        start = CFAbsoluteTimeGetCurrent()
        if let snapshot {
            apply(snapshot: snapshot)
            print("⏱ [ListStore.init] apply(snapshot): \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")
        } else {
            loadState()
            print("⏱ [ListStore.init] loadState: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")
        }
        print("⏱ [ListStore.init] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")
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
