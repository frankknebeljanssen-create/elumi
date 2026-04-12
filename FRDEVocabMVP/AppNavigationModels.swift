import SwiftUI
import Foundation

enum AppScreen: Hashable {
    case train(TrainingLaunchContext?)
    case flashcards(FlashcardLaunchContext?)
    case quiz(QuizLaunchContext?)
    case hearts
    case lists(ListLaunchContext?)
    case lexicon
    case scan
    case settings
    case account
    case info
}

private struct AppOpenAccountActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct AppOpenScanActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct AppUsesGlobalChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appOpenAccountAction: (() -> Void)? {
        get { self[AppOpenAccountActionKey.self] }
        set { self[AppOpenAccountActionKey.self] = newValue }
    }

    var appOpenScanAction: (() -> Void)? {
        get { self[AppOpenScanActionKey.self] }
        set { self[AppOpenScanActionKey.self] = newValue }
    }

    var appUsesGlobalChrome: Bool {
        get { self[AppUsesGlobalChromeKey.self] }
        set { self[AppUsesGlobalChromeKey.self] = newValue }
    }
}

struct TrainingLaunchContext: Hashable {
    let preferredListID: UUID?
    let preferredLanguage: StudyLanguage?
    let preferredDirection: Direction?
    let preferredCardType: CardType?
    let preferredMode: TrainingMode?
    let shouldAutoStart: Bool

    init(
        preferredListID: UUID? = nil,
        preferredLanguage: StudyLanguage? = nil,
        preferredDirection: Direction? = nil,
        preferredCardType: CardType? = nil,
        preferredMode: TrainingMode? = nil,
        shouldAutoStart: Bool = false
    ) {
        self.preferredListID = preferredListID
        self.preferredLanguage = preferredLanguage
        self.preferredDirection = preferredDirection
        self.preferredCardType = preferredCardType
        self.preferredMode = preferredMode
        self.shouldAutoStart = shouldAutoStart
    }
}

struct FlashcardLaunchContext: Hashable {
    let preferredListID: UUID?
    let preferredLanguage: StudyLanguage?
    let preferredDirection: Direction?
    let preferredCardType: CardType?
    let preferredItemIDs: [UUID]?
    let shouldAutoStart: Bool
}

struct QuizLaunchContext: Hashable {
    let preferredListID: UUID?
    let shouldAutoStart: Bool
}

struct ListLaunchContext: Hashable {
    let preferredListID: UUID?
}


struct ImportCompletionContext: Hashable {
    let importedCount: Int
    let targetListID: UUID
    let targetListName: String
    let language: StudyLanguage
    let preferredDirection: Direction?
    let cardType: CardType
    let importedItemIDs: [UUID]

    var summaryText: String {
        switch cardType {
        case .words:
            return importedCount == 1 ? "1 Vokabel wurde gespeichert" : "\(importedCount) Vokabeln wurden gespeichert"
        case .phrases:
            return importedCount == 1 ? "1 Phrase wurde gespeichert" : "\(importedCount) Phrasen wurden gespeichert"
        }
    }

    var trainingLaunchContext: TrainingLaunchContext {
        TrainingLaunchContext(
            preferredListID: targetListID,
            preferredLanguage: language,
            preferredDirection: preferredDirection,
            preferredCardType: cardType
        )
    }

    var flashcardLaunchContext: FlashcardLaunchContext {
        FlashcardLaunchContext(
            preferredListID: targetListID,
            preferredLanguage: language,
            preferredDirection: preferredDirection,
            preferredCardType: cardType,
            preferredItemIDs: importedItemIDs,
            shouldAutoStart: true
        )
    }

    var quizLaunchContext: QuizLaunchContext {
        QuizLaunchContext(preferredListID: targetListID, shouldAutoStart: true)
    }

    var listLaunchContext: ListLaunchContext {
        ListLaunchContext(preferredListID: targetListID)
    }
}
