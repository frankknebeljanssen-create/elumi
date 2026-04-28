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

    // **Per-Account-Namespace** (Phase E.2): Die drei UserDefaults-Keys
    // werden pro Access durch `AccountStore.namespacedKey(_:)` gereicht.
    // Vor dem ersten Onboarding liefert der Helper den Legacy-Slot
    // (ohne Präfix) zurück — Kompatibilität mit dem bisherigen
    // Single-User-Verhalten. Sobald ein Account aktiv ist, sitzen
    // die Daten pro Account isoliert.
    var customListsKey: String { AccountStore.shared.namespacedKey("FRDEVocabMVP.customLists.v2") }
    var selectedListKey: String { AccountStore.shared.namespacedKey("FRDEVocabMVP.selectedListID.v2") }
    var sampleListsSeededKey: String { AccountStore.shared.namespacedKey("FRDEVocabMVP.sampleListsSeeded.v1") }

    // **Lazy-Materialisierung** (Start-Performance): die 57k Built-in-
    // Einträge werden NICHT mehr im Init aufgebaut — das hat den First-
    // Frame vorher um ~195 ms blockiert. Stattdessen:
    //   • `DataStore.prewarmBuiltInLaunchData()` läuft im `listWarmupTask`
    //     detached und populiert die statische `DataStore.builtInVocabularyItems`.
    //   • Die drei `lazy var`-Properties unten kapseln List-Wrap +
    //     Filter; sie initialisieren on-demand (erste Modul-Öffnung)
    //     und treffen dank BG-Prewarm auf einen bereits materialisierten
    //     `DataStore`-Cache — die Kosten in der lazy-Init sind dann nur
    //     noch VocabularyList-Struct + zwei Filter (~15-20 ms zusammen).
    //   • Solange der User auf Home bleibt, wird keine dieser Properties
    //     berührt, die Items-Liste bleibt komplett off-main.
    private lazy var builtInListStorage: VocabularyList = {
        let items = DataStore.builtInVocabularyItems
        return VocabularyList(
            id: Self.builtInListID,
            name: "Standardpaket",
            items: items,
            isBuiltIn: true
        )
    }()
    private lazy var builtInWordsCountStorage: Int = {
        builtInListStorage.items.filter { $0.cardType == .words }.count
    }()
    private lazy var builtInPhrasesCountStorage: Int = {
        builtInListStorage.items.filter { $0.cardType == .phrases }.count
    }()

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

        let start = CFAbsoluteTimeGetCurrent()
        if let snapshot {
            apply(snapshot: snapshot)
            print("⏱ [ListStore.init] apply(snapshot): \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")
        } else {
            loadState()
            print("⏱ [ListStore.init] loadState: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")
        }

        // One-shot Dual-Form-Migration (User-Wunsch): bestehende
        // Custom-Listen-Einträge wie „mon ami/mon amie" oder
        // „l'école, les écoles" werden einmalig in separate Einträge
        // aufgesplittet. Geguarded durch UserDefaults-Flag, läuft also
        // nur einmal pro Installation.
        //
        // Darf das `customLists`-didSet-Save triggern — ist okay, die
        // Migration ist genau der Moment, wo wir das aufgeräumte
        // Ergebnis persistieren wollen.
        let didMigrate = VocabularyListDualFormMigration.applyIfNeeded(to: &customLists)
        #if DEBUG
        if didMigrate {
            print("⏱ [ListStore.init] dual-form migration applied; lists updated.")
        }
        #endif

        // One-shot Phrase-Noun-Capitalization-Migration (User-Wunsch
        // 2026-04-22): in Phrasen-Einträgen wird jedes deutsche Wort
        // kapitalisiert, das im Nomen-Lexikon vorkommt. Geguarded durch
        // UserDefaults-Flag, läuft also nur einmal pro Installation.
        let didCapitalize = PhraseNounCapitalizationMigration.applyIfNeeded(to: &customLists)
        #if DEBUG
        if didCapitalize {
            print("⏱ [ListStore.init] phrase-noun capitalization migration applied.")
        }
        #endif

        // One-shot Known-Bad-Entries-Migration (User-Wunsch 2026-04-22
        // Abend): korrigiert bekannte Fehleinträge in Custom-Listen
        // (z. B. „dur" → „gekochtes Ei" ersetzen durch „l'œuf dur"
        // → „das gekochte Ei"). Zentrale Liste in
        // `VocabularyKnownBadEntriesMigration.corrections`.
        let didFixKnownBad = VocabularyKnownBadEntriesMigration.applyIfNeeded(to: &customLists)
        #if DEBUG
        if didFixKnownBad {
            print("⏱ [ListStore.init] known-bad-entries migration applied.")
        }
        #endif

        print("⏱ [ListStore.init] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")

        // **Phase E.2** — auf Account-Switches reagieren: die
        // `AccountStore.didSwitchAccount`-Notification triggert einen
        // Reload aus dem neuen Account-Namespace. Abo läuft fürs
        // gesamte Store-Leben; deinit wird für dieses Singleton-artige
        // Container-Objekt nie regulär gerufen, deshalb kein
        // removeObserver nötig.
        NotificationCenter.default.addObserver(
            forName: AccountStore.didSwitchAccount,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadForCurrentAccount()
            }
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
        customLists
        + StandardVocabularyLoader.levelLists
        + StandardVocabularyLoader.topicLists
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
