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
    case trainNouns
    case trainArticles
    case trainVerbs
    case trainVerbforms
    case flashcards
    case quiz
    case hearts
    case lists
    case scan
    case lexicon
    case accents
    /// **Elumi-Tab** — Companion-Screen-Style. Akzent in `elumiPink`,
    /// damit der persönliche Character-Tab auch farblich klar zur
    /// Mascot-Identität gehört (nicht zu einem spezifischen Lern-Modul).
    case elumi

    var accent: Color {
        switch self {
        case .home:
            return AppTheme.Colors.primary
        case .train:
            return AppTheme.Colors.modulePractice
        case .trainNouns:
            return AppTheme.Colors.moduleNomen
        case .trainArticles:
            return AppTheme.Colors.moduleArticles
        case .trainVerbs:
            return AppTheme.Colors.moduleVerbs
        case .trainVerbforms:
            return AppTheme.Colors.moduleVerbforms
        case .flashcards:
            return AppTheme.Colors.moduleFlashcards
        case .quiz:
            return AppTheme.Colors.moduleQuiz
        case .hearts:
            return AppTheme.Colors.moduleHearts
        case .lists:
            return AppTheme.Colors.moduleSpecial
        case .scan:
            return AppTheme.Colors.moduleScan
        case .lexicon:
            return AppTheme.Colors.moduleLexicon
        case .accents:
            return AppTheme.Colors.moduleAccents
        case .elumi:
            return AppTheme.Colors.elumiPink
        }
    }

    /// Convenience-Fassade: bündelt die am häufigsten genutzten
    /// abgeleiteten Modul-Farben (Accent, drei Standard-Tint-Intensitäten,
    /// Chip-BG, Icon-/Progress-Farbe) in einem einzigen Value.
    ///
    /// Spart in Views die immer wiederkehrende Zeile
    /// `style.accent.opacity(AppTheme.CardIntensity.soft)` — stattdessen
    /// `style.style.tintSoft`. Die Werte werden aus `accent` und
    /// `AppTheme.CardIntensity` **abgeleitet**, nicht neu definiert —
    /// Single Source of Truth bleibt `AppTheme.Colors` + `CardIntensity`.
    var style: ModuleStyle {
        let base = accent
        return ModuleStyle(
            accent: base,
            tintSoft: base.opacity(AppTheme.CardIntensity.soft),
            tintMedium: base.opacity(AppTheme.CardIntensity.medium),
            tintStrong: base.opacity(AppTheme.CardIntensity.strong),
            chipBackground: base.opacity(AppTheme.CardIntensity.gentle),
            chipText: AppTheme.Colors.textPrimary,
            icon: base,
            progress: base
        )
    }
}

/// Fertig berechnete Modul-Farbwerte für den breiten Masse-Fall (Cards
/// in `soft`/`medium`/`strong`, Chip, Icon, Progress). Wird über
/// `AppSectionStyle.style` erzeugt — nicht direkt instanziieren.
struct ModuleStyle {
    let accent: Color
    let tintSoft: Color
    let tintMedium: Color
    let tintStrong: Color
    let chipBackground: Color
    let chipText: Color
    let icon: Color
    let progress: Color
}
