import Foundation
import SwiftUI

struct PreparedLexiconEntry: Identifiable {
    let id: String
    let entries: [LexiconEntry]
    let displayCardType: CardType
    let displayCountryCode: String
    let frenchGender: LexiconGenderInfo?
    let germanGender: LexiconGenderInfo?
    let sourceText: String
    let targetText: String
    let targetVariants: [String]
    let sourceSearchKey: String
    let targetSearchKey: String

    /// Grouped translations by word class
    var nounTranslations: [String] {
        entries.filter { $0.isGermanNoun }.map(\.targetTerm).uniqued()
    }

    var nonNounTranslations: [String] {
        entries.filter { !$0.isGermanNoun }.map(\.targetTerm).uniqued()
    }

    var hasMultipleWordClasses: Bool {
        !nounTranslations.isEmpty && !nonNounTranslations.isEmpty
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum LexiconWordClassMarker: String {
    case noun = "[nom]"
    case adjective = "[adj]"
    case verb = "[verb]"
}

@MainActor
final class LexiconViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var mergedEntries: [LexiconEntry] = []
    @Published var selectedEntry: PreparedLexiconEntry?
    @Published var isLoadingLexiconEntries = false
    @Published var isSearchingLexicon = false
    @Published var preparedEntries: [PreparedLexiconEntry] = []

    var lexiconReloadGeneration = 0
    var lexiconSearchGeneration = 0

    var allEntries: [PreparedLexiconEntry] {
        preparedEntries
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasActiveSearch: Bool {
        !trimmedSearchText.isEmpty
    }
}
