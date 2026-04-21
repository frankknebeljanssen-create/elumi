import SwiftUI
import Foundation

enum AppScreen: Hashable {
    case train(TrainingLaunchContext?)
    case flashcards(FlashcardLaunchContext?)
    case quiz(QuizLaunchContext?)
    case hearts      // Progress Hub (Fortschritt) — reached via Home Board tap
    case lernstatus  // Lernstatus-Detail (cross-modular per-Vokabel) — reached via HomeLernstatusCard tap
    case gameHub     // Game Hub (Reward + Spiel-Start) — reached via Footer-Snack
    case arcade(autoStart: Bool)  // Das eigentliche Spiel — Start-Overlay oder Direkt-Start
    case lists(ListLaunchContext?)
    case lexicon
    case scan
    case accents(AccentsLaunchContext?)   // Akzent-Modul (é, è, ê, ç)
    case settings
    case account
    case info
    /// **Pokal-Tab** (Footer): sammelt die ausführlichen Status-/
    /// Fortschritts-Cards (Streak, Level/XP, Lernstatus), die früher
    /// dominant auf Home lagen. Home zeigt nur noch eine kompakte
    /// Status-Card; Detail-Ansichten leben hier.
    case trophy
}

private struct AppOpenAccountActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct AppOpenScanActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// Zentrale Aktion, um den Lexikon-Screen (Wörterbuch-Button im Footer)
/// zu öffnen. Vorher war der Wörterbuch-Button fälschlich auf
/// `appOpenScanAction` gefallen, wenn kein expliziter Callback vorlag —
/// Ergebnis: Tap auf „Wörterbuch" öffnete den Scanner statt das
/// Lexikon. Dieser eigene Environment-Key räumt das sauber auf.
private struct AppOpenLexiconActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// Zentrale Aktion, um den Game Hub zu öffnen — vom Footer-Snack-Button genutzt.
private struct AppOpenGameHubActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// Zentrale Aktion, um die Arcade-Route (`.arcade`) zu öffnen. `autoStart`:
///   • `false` → Start-Overlay wird angezeigt, Footer bleibt sichtbar
///   • `true`  → direkt ins Spiel, Footer verschwindet sofort
/// Typischer Aufruf: Elumi-Mascot (autoStart=false), GameHub-CTA (autoStart=true).
private struct AppOpenArcadeActionKey: EnvironmentKey {
    static let defaultValue: ((Bool) -> Void)? = nil
}

/// Setzt den Immersive-Arcade-Flag — ElumiArcadeGameView nutzt ihn, um
/// den globalen Footer auszublenden, sobald das Spiel tatsächlich läuft.
private struct AppSetImmersiveArcadeActionKey: EnvironmentKey {
    static let defaultValue: ((Bool) -> Void)? = nil
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

    var appOpenLexiconAction: (() -> Void)? {
        get { self[AppOpenLexiconActionKey.self] }
        set { self[AppOpenLexiconActionKey.self] = newValue }
    }

    var appOpenGameHubAction: (() -> Void)? {
        get { self[AppOpenGameHubActionKey.self] }
        set { self[AppOpenGameHubActionKey.self] = newValue }
    }

    var appOpenArcadeAction: ((Bool) -> Void)? {
        get { self[AppOpenArcadeActionKey.self] }
        set { self[AppOpenArcadeActionKey.self] = newValue }
    }

    var appSetImmersiveArcadeAction: ((Bool) -> Void)? {
        get { self[AppSetImmersiveArcadeActionKey.self] }
        set { self[AppSetImmersiveArcadeActionKey.self] = newValue }
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
        return importedCount == 1 ? "1 Eintrag wurde gespeichert" : "\(importedCount) Eintr\u{00E4}ge wurden gespeichert"
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
