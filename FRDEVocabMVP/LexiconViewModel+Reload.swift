import Foundation

extension LexiconViewModel {
    func reloadEntries(
        customLists: [VocabularyList],
        selectedDirection: Direction,
        showLoadingState: Bool
    ) async {
        lexiconReloadGeneration += 1
        let generation = lexiconReloadGeneration
        isLoadingLexiconEntries = true

        let customItems = customLists
            .flatMap(\.items)
            .filter { $0.sourceLanguage == .french }

        let curatedEntries = await Task.detached(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let entries = DataStore.curatedLexiconEntries(with: customItems)
            appDebugLog("⏱ [Lexikon] curatedLexiconEntries: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(entries.count) entries)")
            return entries
        }.value

        guard generation == lexiconReloadGeneration else { return }
        mergedEntries = curatedEntries
        isLoadingLexiconEntries = false

        if hasActiveSearch {
            await performSearch(
                for: searchText,
                customLists: customLists,
                selectedDirection: selectedDirection
            )
        }
    }

    func performSearch(
        for rawQuery: String,
        customLists: [VocabularyList],
        selectedDirection: Direction
    ) async {
        lexiconSearchGeneration += 1
        let generation = lexiconSearchGeneration
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            isSearchingLexicon = false
            preparedEntries = []
            return
        }

        let mergedEntriesSnapshot = mergedEntries
        if mergedEntriesSnapshot.isEmpty, isLoadingLexiconEntries {
            return
        }
        let customItemsSnapshot = customLists
            .flatMap(\.items)
            .filter { $0.sourceLanguage == .french }
        isSearchingLexicon = true

        let matchingEntries: [LexiconEntry] = await Task.detached(priority: .userInitiated) {
            let curatedEntries: [LexiconEntry]
            if !mergedEntriesSnapshot.isEmpty {
                curatedEntries = mergedEntriesSnapshot
            } else {
                curatedEntries = DataStore.curatedLexiconEntries(with: customItemsSnapshot)
            }

            return DataStore.searchLexiconEntries(
                query: query,
                curatedEntries: curatedEntries
            )
        }.value

        guard generation == lexiconSearchGeneration else { return }
        await rebuildPreparedEntries(
            from: matchingEntries,
            query: query,
            selectedDirection: selectedDirection
        )
        guard generation == lexiconSearchGeneration else { return }
        isSearchingLexicon = false
    }
}
