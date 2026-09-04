import Foundation
import SwiftUI

/// Tages-Aktivitäts-Store für die Home-Status-Card.
///
/// Rolle im System (abgegrenzt):
///   • `ProgressStore`         → XP / Level / Credits / Streak
///   • `DailyChallengeStore`   → Tages-Task (Ziel-Logik)
///   • **`DailyStatsStore`**   → **Tages-Feedback**: wie viele Aktionen hat
///     der User heute bereits ausgeführt? Bewusst **kein** Zielsystem —
///     die Zahl ist Feedback, nicht Steuerung.
///
/// „Aktion" = beantwortete Frage, bearbeitete Karteikarte, absolvierte
/// Trainings-Einheit. Die konkrete Zählung passiert zentral in
/// `ProgressService.record(session:)` via `recordSession(actionsCount:)` —
/// jedes Modul meldet nur die eigene Session-Summe, nicht jeden Tap.
///
/// **Reset:** automatisch, wenn `GamificationConfig.currentDayIndex`
/// wechselt (6-Uhr-Rollover, konsistent mit DailyChallenge/Streak-Logik).
///
/// Persistenz: drei UserDefaults-Keys, flach statt Codable — die Daten
/// sind trivial und fetzen keine JSON-Migration.
@MainActor
final class DailyStatsStore: ObservableObject {
    static let shared = DailyStatsStore()

    /// Aktionen, die der User heute bereits ausgeführt hat. Reset bei
    /// Tageswechsel (6-Uhr-Rollover).
    @Published private(set) var actionsToday: Int = 0

    /// Letzter Session-Beitrag des aktuellen Tages — für die sekundäre
    /// Zeile „+5 seit letzter Session". 0, wenn heute noch keine Session
    /// abgeschlossen wurde oder der Tag gerade gewechselt hat.
    @Published private(set) var lastSessionDelta: Int = 0

    /// Tages-Index, zu dem `actionsToday` / `lastSessionDelta` gehören.
    /// Wird beim Load verglichen — stimmt er nicht mit dem aktuellen Tag
    /// überein, gilt heute als „noch nichts passiert".
    @Published private(set) var dayIndex: Int = GamificationConfig.currentDayIndex

    // MARK: - Keys

    private let actionsKey = "elumi.dailyStats.actionsToday.v1"
    private let deltaKey   = "elumi.dailyStats.lastSessionDelta.v1"
    private let dayKey     = "elumi.dailyStats.dayIndex.v1"

    // MARK: - Init

    init() {
        load()
        refreshForTodayIfNeeded()

        // **Codeaudit 2026-09-03, Stufe 3 (Punkt 18)** — Singleton,
        // ueberlebt den Account-Wechsel. Ohne Reload zaehlte die
        // Tagesaktivitaet des vorigen Kindes beim neuen weiter.
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

    /// Liest die Tagesaktivitaet des jetzt aktiven Accounts neu ein.
    func reloadForCurrentAccount() {
        load()
        refreshForTodayIfNeeded()
    }

    // MARK: - Public API

    /// Wird am Ende jeder Session aufgerufen (zentral in `ProgressService.
    /// record(session:)`). `count` = Anzahl der in dieser Session erfassten
    /// Aktionen (richtige + falsche Antworten, also alles was der User
    /// tatsächlich bearbeitet hat).
    ///
    /// Nicht-positive Werte werden ignoriert — leere Sessions sollen die
    /// „seit letzter Session"-Zeile nicht auf 0 zurücksetzen.
    func recordSession(actionsCount: Int) {
        guard actionsCount > 0 else { return }
        refreshForTodayIfNeeded()
        actionsToday += actionsCount
        lastSessionDelta = actionsCount
        persist()
    }

    /// Idempotenter Day-Rollover-Check. Öffentlich, damit die `HomeView`
    /// beim Erscheinen einen Sync triggern kann, falls die App lange im
    /// Hintergrund war und der Tag inzwischen gewechselt hat.
    func refreshForTodayIfNeeded() {
        let today = GamificationConfig.currentDayIndex
        guard today != dayIndex else { return }
        dayIndex = today
        actionsToday = 0
        lastSessionDelta = 0
        persist()
    }

    /// Setzt alle Tages-Werte auf 0 und den Day-Index auf heute.
    /// Wird vom `GameStateResetService` (User-sichtbarer „Spielstand
    /// zurücksetzen"-Button) und vom `DebugResetService` (DEBUG-Dev-
    /// Card) aufgerufen — `#if DEBUG`-Wrapper wurde entfernt, damit
    /// der produktive Reset-Pfad die Methode im Release-Build
    /// aufrufen kann. Name von `resetForDebugging` → `reset`, weil
    /// die Methode nicht mehr nur für Debug genutzt wird.
    func reset() {
        dayIndex = GamificationConfig.currentDayIndex
        actionsToday = 0
        lastSessionDelta = 0
        persist()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        self.dayIndex = defaults.object(forKey: dayKey) as? Int
            ?? GamificationConfig.currentDayIndex
        self.actionsToday = defaults.integer(forKey: actionsKey)
        self.lastSessionDelta = defaults.integer(forKey: deltaKey)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(dayIndex, forKey: dayKey)
        defaults.set(actionsToday, forKey: actionsKey)
        defaults.set(lastSessionDelta, forKey: deltaKey)
    }
}
