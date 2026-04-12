import SwiftUI
import Foundation

private struct FlashcardsOpenTimingState {
    let startedAt: CFTimeInterval
}

let curatedLexiconEntriesCacheLock = NSLock()
var curatedLexiconEntriesCache: [CuratedLexiconEntriesCacheKey: [LexiconEntry]] = [:]
private let flashcardsOpenTimingLock = NSLock()
private var flashcardsOpenTimingState: FlashcardsOpenTimingState?

func curatedLexiconEntriesCacheKey(for customItems: [VocabularyItem]) -> CuratedLexiconEntriesCacheKey {
    var hasher = Hasher()
    hasher.combine(customItems.count)

    for item in customItems {
        hasher.combine(item.id)
        hasher.combine(item.french)
        hasher.combine(item.german)
        hasher.combine(item.cardType.rawValue)
        hasher.combine(item.sourceLanguage.rawValue)
        hasher.combine(item.level?.rawValue)
    }

    return CuratedLexiconEntriesCacheKey(
        itemCount: customItems.count,
        fingerprint: hasher.finalize()
    )
}

func startFlashcardsOpenTiming(_ reason: String) {
    let state = FlashcardsOpenTimingState(startedAt: CFAbsoluteTimeGetCurrent())
    flashcardsOpenTimingLock.lock()
    flashcardsOpenTimingState = state
    flashcardsOpenTimingLock.unlock()
    NSLog("[FlashcardsOpenTiming] start reason=%@", reason)
}

func markFlashcardsOpenTiming(_ event: String) {
    flashcardsOpenTimingLock.lock()
    let state = flashcardsOpenTimingState
    flashcardsOpenTimingLock.unlock()
    guard let state else { return }

    let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - state.startedAt) * 1000).rounded())
    NSLog("[FlashcardsOpenTiming] %@ elapsed=%dms", event, elapsedMS)
}

func endFlashcardsOpenTiming(_ event: String) {
    flashcardsOpenTimingLock.lock()
    let state = flashcardsOpenTimingState
    flashcardsOpenTimingState = nil
    flashcardsOpenTimingLock.unlock()
    guard let state else { return }

    let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - state.startedAt) * 1000).rounded())
    NSLog("[FlashcardsOpenTiming] %@ elapsed=%dms", event, elapsedMS)
}

enum AppSectionStyle {
    case home
    case train
    case trainArticles
    case trainVerbs
    case flashcards
    case quiz
    case hearts
    case lists
    case scan
    case lexicon

    var accent: Color {
        switch self {
        case .home:
            return AppTheme.Colors.primary
        case .train:
            return AppTheme.Colors.modulePractice
        case .trainArticles:
            return AppTheme.Colors.moduleArticles
        case .trainVerbs:
            return AppTheme.Colors.moduleVerbs
        case .flashcards:
            return AppTheme.Colors.moduleFlashcards
        case .quiz:
            return AppTheme.Colors.moduleQuiz
        case .hearts:
            return AppTheme.Colors.error
        case .lists:
            return AppTheme.Colors.moduleSpecial
        case .scan:
            return AppTheme.Colors.moduleScan
        case .lexicon:
            return AppTheme.Colors.moduleLexicon
        }
    }
}
