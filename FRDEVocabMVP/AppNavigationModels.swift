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
    /// **Word Runner** — Phase 7.5: jetzt als echte Navigation-Destination
    /// (vorher FullScreenCover aus GameHub), damit der globale Footer
    /// während des Start-Screens sichtbar bleibt — analog zur Arcade.
    case wordRunner
    case lists(ListLaunchContext?)
    case lexicon
    case scan
    case scanDraftDetail(UUID)   // **Phase D (2026-05-20)** — Scan-Entwurf-Detail
    case accents(AccentsLaunchContext?)   // Akzent-Modul (é, è, ê, ç)
    case settings
    case account
    case info
    /// **Pokal-Tab** (Footer): sammelt die ausführlichen Status-/
    /// Fortschritts-Cards (Streak, Level/XP, Lernstatus), die früher
    /// dominant auf Home lagen. Home zeigt nur noch eine kompakte
    /// Status-Card; Detail-Ansichten leben hier.
    case trophy
    /// **Elumi-Tab** (Phase 8): persönlicher Begleiter-Screen. Zeigt
    /// Begrüßung + Axolotl, die aktuell empfohlene nächste Lern-Einheit
    /// (V1: fest „Karteikarten") und einen kompakten Streak/Level/XP-
    /// Status. Bewusst schlank — **kein** Modul-Grid, keine Stats-Tiefe,
    /// keine Tools. Abgrenzung zu Home (Auswahl) / Spielen / Fortschritt /
    /// Wörterbuch: Elumi = „dein nächster Schritt".
    case elumi

    /// **Léa-Chat** (2026-05-10, Branch `feature/lea-chat-mvp`) —
    /// Konversation mit der Persona Léa (15 Jahre, Paris, FR). Backend
    /// proxt zu Anthropic Claude Haiku. Erreicht über die „Live Chat"-
    /// Card auf Home (Section zwischen Daily-Drop und Training).
    case leaChat

    /// **Training-Hub** (2026-05-06, Home-Refactor Hybrid γ v3) — Sub-
    /// Screen, der über die „Training"-Card auf Home erreicht wird.
    /// Bündelt die fünf Lern-Modi: Vokabeln (Allgemein-Slot, einzeln)
    /// und Nomen / Verben / Artikel / Verbformen (Spezial-Slot, 2×2)
    /// plus Akzente quer am Ende. Vorher waren Vokabeln + die vier
    /// Spezial-Modi direkt auf Home verteilt; mit dem Refactor sind
    /// sie hinter einer Card zusammengefasst, damit Home schlanker
    /// und auf vier zentrale Methoden fokussiert ist.
    case trainingHub

    /// **Trainings-Chain Pre-Screen** (Stufe 2, 2026-04-30, Branch
    /// `feature/training-session-flow`). Wird zwischen Slot-Reveal und
    /// erstem Modul-Open gepusht. Zeigt Mini-Cards für jeden Slot des
    /// aktuellen Spin-Results (Modul-Slots mit Zeit-Anteil, Game-Slots
    /// mit Tickets-Marker), erlaubt dem User einen letzten
    /// „Plan-anschauen"-Moment vor dem Start. „Übung starten"-CTA pusht
    /// aufs erste Modul; Back-Chevron räumt die Chain ab und kehrt zum
    /// Tab zurück (slot-result bleibt sichtbar, R12-Spec). Bei Jackpot
    /// (3× Game): CTA disabled, Hint „Drehe noch mal für Übungen".
    case trainingChainOverview(TrainingChainContext)

    /// **Trainings-Chain End-Summary-Platzhalter** (Stufe 3, 2026-05-01,
    /// Branch `feature/training-session-flow`). Wird gepusht, wenn der
    /// letzte Modul-Step der Chain via „Training abschließen"-CTA
    /// abgeschlossen ist. Stufe 5 ersetzt die View durch eine
    /// aggregierte End-Summary auf Basis von
    /// `TrainingChainStore.shared.stepOutcomes`. Stufe 3 zeigt einen
    /// minimalen Platzhalter mit einem „Zur Startseite"-CTA, der die
    /// Chain räumt und nach Home zurücknavigiert.
    case trainingChainComplete
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

/// **Trophy-Action** (2026-05-04). Zentrale Aktion für den Pokal-Footer-
/// Button, parallel zu `AppOpenGameHubActionKey`. Vorher war der Trophy-
/// Pfad nur als direkter `onTrophy:`-Callback in `HomeView` /
/// `RootContentView` verdrahtet — andere Screens (insbesondere Sheets)
/// hatten keinen Zugriff auf die Trophy-Navigation und mussten den
/// Pokal-Button mit `nil`-Callback dimmen lassen. Mit diesem
/// Environment-Key kann jeder Screen den Pokal-Button auf eine globale
/// Trophy-Aktion zurückfallen lassen, analog zum Wörterbuch/Game-Hub-
/// Pattern.
private struct AppOpenTrophyActionKey: EnvironmentKey {
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

/// **Elumi-Tab-Action** (Phase 8): öffnet `AppScreen.elumi` — den
/// persönlichen Begleiter-Screen. Vom Elumi-Footer-Button verwendet,
/// damit das Axolotl-Icon im Footer jetzt zum Companion-Screen führt
/// statt in die Arcade. Arcade/Spiele bleiben weiterhin über den
/// „Spiele"-Button (Snack-Icon) erreichbar.
private struct AppOpenElumiActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct AppUsesGlobalChromeKey: EnvironmentKey {
    static let defaultValue = false
}

/// **Trainings-Chain Advance Action** (Stufe 3, 2026-05-01, Branch
/// `feature/training-session-flow`). Wird vom `AppDestinationHost`
/// pro Modul-Destination als Environment installiert. Modul-Views
/// rufen diesen Closure aus dem `onPrimaryCTA`-Pfad ihres
/// `SessionSummaryView`s auf, sobald der User „Weiter zu …" oder
/// „Training abschließen" tippt — der optionale `outcome` wird im
/// `TrainingChainStore` für die spätere End-Summary-Aggregation
/// (Stufe 5) abgelegt; danach räumt der Host via `replaceTopWith(...)`
/// den Modul-Screen aus dem Stack und pusht den nächsten Step (oder
/// die `trainingChainComplete`-Platzhalter-Route).
///
/// Default = `nil` → Modul-Views erkennen daran „nicht im Chain-
/// Modus", branchen also auf das vorhandene Setup-Reset/Home-CTA.
private struct AppChainAdvanceActionKey: EnvironmentKey {
    static let defaultValue: ((SessionRewardOutcome?) -> Void)? = nil
}

/// **Léa-Chat MVP — Polish (2026-05-10)** — Closure, mit dem Sub-Screens
/// (aktuell nur `ChatView`) den globalen Footer suppressen können, solange
/// das System-Keyboard sichtbar ist. Spiegelt das `appSetImmersiveArcadeAction`-
/// Pattern: `RootContentView` installiert die Closure, sie schreibt in
/// `AppNavigationCoordinator.isChatKeyboardActive`. Default `nil` →
/// Screens, die nicht eingehängt sind, sind no-op.
private struct AppSetChatKeyboardActiveActionKey: EnvironmentKey {
    static let defaultValue: ((Bool) -> Void)? = nil
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

    var appOpenTrophyAction: (() -> Void)? {
        get { self[AppOpenTrophyActionKey.self] }
        set { self[AppOpenTrophyActionKey.self] = newValue }
    }

    var appOpenArcadeAction: ((Bool) -> Void)? {
        get { self[AppOpenArcadeActionKey.self] }
        set { self[AppOpenArcadeActionKey.self] = newValue }
    }

    var appOpenElumiAction: (() -> Void)? {
        get { self[AppOpenElumiActionKey.self] }
        set { self[AppOpenElumiActionKey.self] = newValue }
    }

    var appSetImmersiveArcadeAction: ((Bool) -> Void)? {
        get { self[AppSetImmersiveArcadeActionKey.self] }
        set { self[AppSetImmersiveArcadeActionKey.self] = newValue }
    }

    var appUsesGlobalChrome: Bool {
        get { self[AppUsesGlobalChromeKey.self] }
        set { self[AppUsesGlobalChromeKey.self] = newValue }
    }

    var appChainAdvanceAction: ((SessionRewardOutcome?) -> Void)? {
        get { self[AppChainAdvanceActionKey.self] }
        set { self[AppChainAdvanceActionKey.self] = newValue }
    }

    var appSetChatKeyboardActiveAction: ((Bool) -> Void)? {
        get { self[AppSetChatKeyboardActiveActionKey.self] }
        set { self[AppSetChatKeyboardActiveActionKey.self] = newValue }
    }
}

struct TrainingLaunchContext: Hashable {
    let preferredListID: UUID?
    let preferredLanguage: StudyLanguage?
    let preferredDirection: Direction?
    let preferredCardType: CardType?
    let preferredMode: TrainingMode?
    let shouldAutoStart: Bool
    /// **Stufe 1 (2026-04-30)**: optionaler Chain-Context, gesetzt wenn
    /// das Modul als Step einer auto-verketteten Trainings-Sequenz
    /// gestartet wird. `nil` = normale Modul-Sitzung. Stufe 2 nutzt
    /// das Feld in den Done-CTAs zum Weiter-Springen.
    let chainContext: TrainingChainContext?
    /// **Daily Drop Modul 1 (2026-05-23)** — Count-Cap für den Anzahl-
    /// Modus. Non-nil → die Session endet nach genau N beantworteten
    /// Aufgaben (Count-Guard vor dem Reshuffle, siehe
    /// `TrainingView.loadNextTrainingCard`). `nil` = unverändertes
    /// (endloses) Verhalten — regressionssicher nil-gated.
    let dailyDropCount: Int?

    init(
        preferredListID: UUID? = nil,
        preferredLanguage: StudyLanguage? = nil,
        preferredDirection: Direction? = nil,
        preferredCardType: CardType? = nil,
        preferredMode: TrainingMode? = nil,
        shouldAutoStart: Bool = false,
        chainContext: TrainingChainContext? = nil,
        dailyDropCount: Int? = nil
    ) {
        self.preferredListID = preferredListID
        self.preferredLanguage = preferredLanguage
        self.preferredDirection = preferredDirection
        self.preferredCardType = preferredCardType
        self.preferredMode = preferredMode
        self.shouldAutoStart = shouldAutoStart
        self.chainContext = chainContext
        self.dailyDropCount = dailyDropCount
    }
}

struct FlashcardLaunchContext: Hashable {
    let preferredListID: UUID?
    let preferredLanguage: StudyLanguage?
    let preferredDirection: Direction?
    let preferredCardType: CardType?
    let preferredItemIDs: [UUID]?
    let shouldAutoStart: Bool
    /// **Stufe 1 (2026-04-30)**: siehe `TrainingLaunchContext.chainContext`.
    let chainContext: TrainingChainContext?

    init(
        preferredListID: UUID? = nil,
        preferredLanguage: StudyLanguage? = nil,
        preferredDirection: Direction? = nil,
        preferredCardType: CardType? = nil,
        preferredItemIDs: [UUID]? = nil,
        shouldAutoStart: Bool = false,
        chainContext: TrainingChainContext? = nil
    ) {
        self.preferredListID = preferredListID
        self.preferredLanguage = preferredLanguage
        self.preferredDirection = preferredDirection
        self.preferredCardType = preferredCardType
        self.preferredItemIDs = preferredItemIDs
        self.shouldAutoStart = shouldAutoStart
        self.chainContext = chainContext
    }
}

struct QuizLaunchContext: Hashable {
    let preferredListID: UUID?
    let shouldAutoStart: Bool
    /// **Stufe 1 (2026-04-30)**: siehe `TrainingLaunchContext.chainContext`.
    let chainContext: TrainingChainContext?
    /// **Daily Drop Modul 1 (2026-05-23)** — Count-Cap (Anzahl-Modus).
    /// Non-nil → Quiz wird auf genau N Fragen gesetzt (über
    /// `questionCountOption`) und endet natürlich am Terminal-Gate.
    /// `nil` = unverändertes Verhalten.
    let dailyDropCount: Int?
    /// **Daily Drop Modul 1 (2026-05-23)** — Atomar-Modus: nur
    /// MultipleChoice + Tippen (kein Matching/Combo/FillBlanks), damit
    /// `questions.count == N` exakt bleibt. Nur im Daily-Drop-Pfad true.
    let atomicOnly: Bool

    init(
        preferredListID: UUID? = nil,
        shouldAutoStart: Bool = false,
        chainContext: TrainingChainContext? = nil,
        dailyDropCount: Int? = nil,
        atomicOnly: Bool = false
    ) {
        self.preferredListID = preferredListID
        self.shouldAutoStart = shouldAutoStart
        self.chainContext = chainContext
        self.dailyDropCount = dailyDropCount
        self.atomicOnly = atomicOnly
    }
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

// MARK: - HomeHeroModule

/// Modul-Identität für die Hero-Sektion und app-weite Modul-Mappings.
/// **Wanderte 2026-05-07** aus `HomeHeroLearningSection.swift` hierher,
/// als die drei Home-Section-Files (`HomeHeroLearningSection`,
/// `HomeMoreExercisesSection`, `HomeToolsSection`) als toter Code
/// entfernt wurden. Das Enum bleibt produktiv — `ElumiTabView`-Slot-
/// Maschine, `TrainingGeneratorSlotMachine`, `TrainingChainOverviewView`,
/// `ScanImportSupportViews` und die `chainScreen(...)`-Extension unten
/// arbeiten alle damit. Eigenes Enum (statt direkt `HomeModuleIcon` o.ä.),
/// damit das Mapping auf Icon + Title + Color + Route zentral hier lebt.
enum HomeHeroModule: String, Identifiable, CaseIterable {
    case karteikarten
    case nomen
    case artikel
    case verben
    case verbformen
    case vokabeln
    case quiz
    case akzente

    var id: String { rawValue }

    var title: String {
        switch self {
        case .karteikarten: return "Karteikarten"
        case .nomen:        return "Nomen"
        case .artikel:      return "Artikel"
        case .verben:       return "Verben"
        case .verbformen:   return "Verbformen"
        case .vokabeln:     return "Vokabeln"
        case .quiz:         return "Quiz"
        case .akzente:      return "Akzente"
        }
    }

    var icon: HomeModuleIcon {
        switch self {
        case .karteikarten: return .karteikarten
        case .nomen:        return .nomen
        case .artikel:      return .artikel
        case .verben:       return .verben
        case .verbformen:   return .verbformen
        case .vokabeln:     return .vokabeln
        case .quiz:         return .quiz
        case .akzente:      return .akzente
        }
    }

    var accent: Color {
        switch self {
        case .karteikarten: return AppTheme.Colors.moduleFlashcards
        case .nomen:        return AppTheme.Colors.moduleNomen
        case .artikel:      return AppTheme.Colors.moduleArticles
        case .verben:       return AppTheme.Colors.moduleVerbs
        case .verbformen:   return AppTheme.Colors.moduleVerbforms
        case .vokabeln:     return AppTheme.Colors.moduleVocabulary
        case .quiz:         return AppTheme.Colors.moduleQuiz
        case .akzente:      return AppTheme.Colors.moduleAccents
        }
    }

    /// Welcher AppScreen soll geöffnet werden? — wird vom Aufrufer
    /// genutzt, damit das Modul-Mapping Navigation-frei bleibt.
    var screen: AppScreen {
        switch self {
        case .karteikarten: return .flashcards(nil)
        case .nomen:        return .train(TrainingLaunchContext(preferredMode: .nouns))
        case .artikel:      return .train(TrainingLaunchContext(preferredMode: .articles))
        case .verben:       return .train(TrainingLaunchContext(preferredMode: .verbs))
        case .verbformen:   return .train(TrainingLaunchContext(preferredMode: .verbforms))
        case .vokabeln:     return .train(TrainingLaunchContext(preferredMode: .vocabulary))
        case .quiz:         return .quiz(nil)
        case .akzente:      return .accents(nil)
        }
    }
}

// MARK: - HomeHeroModule → AppScreen (Chain-Aware)

extension HomeHeroModule {
    /// **Stufe 2 (2026-04-30, Branch `feature/training-session-flow`)** —
    /// Mappt einen Modul-Slot der Trainings-Chain auf den `AppScreen`,
    /// der gepusht werden soll, inkl. injiziertem `chainContext` damit
    /// die Modul-View den Done-CTA „Weiter (Step n+1)" rendern kann.
    ///
    /// Vorher lebte die Logik privat in `ElumiTabView.screenForChainStep`.
    /// Stufe 2 braucht dieselbe Mapping-Funktion zusätzlich im
    /// `AppDestinationHost` (Pre-Screen-CTA-Closure ruft sie für den
    /// ersten Chain-Step auf), darum die Hochziehung in eine Extension.
    /// `screenForChainStep` ist jetzt nur noch Wrapper.
    ///
    /// **R4-Mapping:** Vokabeln/Nomen/Artikel/Verben/Verbformen laufen
    /// alle über `.train(TrainingLaunchContext)`, der `preferredMode`
    /// schaltet die TrainingView intern auf den richtigen Modus.
    /// Karteikarten → `.flashcards`, Quiz → `.quiz`, Akzente →
    /// `.accents` mit `preferredMode = .uben` (Üben-Modus).
    ///
    /// `shouldAutoStart` ist immer `true` — die Modul-Views starten
    /// direkt in die Session, kein Setup-Modal.
    func chainScreen(chainContext: TrainingChainContext) -> AppScreen {
        switch self {
        case .karteikarten:
            return .flashcards(FlashcardLaunchContext(
                shouldAutoStart: true,
                chainContext: chainContext
            ))
        case .quiz:
            return .quiz(QuizLaunchContext(
                shouldAutoStart: true,
                chainContext: chainContext,
                // **Daily Drop Modul 2 (2026-05-23)** — Count-Modus: Cap auf
                // perStepCount. Im Zeit-Modus nil → unverändert.
                // **Modul 2.12 (2026-05-23)** — `atomicOnly` zurückgenommen:
                // der Daily-Drop-Quiz baut wieder ALLE Fragetypen (MC,
                // Tippen, Matching, Combo, Lückentext). Da combo/Lückentext
                // separat eingefügt werden und `questions.count` über N
                // heben können, hält der Runtime-Cap in
                // `QuizView.completeCurrentQuestion` den Quiz-Anteil exakt
                // bei `dailyDropCount`.
                dailyDropCount: chainContext.perStepCount,
                atomicOnly: false
            ))
        case .akzente:
            return .accents(AccentsLaunchContext(
                preferredMode: .uben,
                shouldAutoStart: true,
                chainContext: chainContext
            ))
        case .nomen, .artikel, .verben, .verbformen, .vokabeln:
            let mode: TrainingMode
            switch self {
            case .nomen:      mode = .nouns
            case .artikel:    mode = .articles
            case .verben:     mode = .verbs
            case .verbformen: mode = .verbforms
            case .vokabeln:   mode = .vocabulary
            default:          mode = .vocabulary
            }
            return .train(TrainingLaunchContext(
                preferredMode: mode,
                shouldAutoStart: true,
                chainContext: chainContext,
                // **Daily Drop Modul 2 (2026-05-23)** — Count-Cap je Step;
                // nil im Zeit-Modus → unverändert.
                dailyDropCount: chainContext.perStepCount
            ))
        }
    }
}
