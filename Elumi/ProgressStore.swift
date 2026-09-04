import Foundation
import SwiftUI

/// Reine Datenstruktur für den User-Fortschritt — Codable, einfach zu
/// persistieren, leicht zu testen.
struct UserProgress: Codable, Equatable {
    var totalXP: Int = 0
    var arcadeCredits: Int = 3
    var currentStreak: Int = 0
    var bestStreak: Int = 0

    /// Day-Index (Unix-Time / 86400, 6-Uhr-Rollover) des letzten Tages, an
    /// dem eine vollständige Session abgeschlossen wurde. Wird vom Streak-
    /// Update genutzt, um „heute schon gezählt" zu erkennen.
    var lastSessionDayIndex: Int = -1

    /// Day-Index des letzten Tages, an dem der Daily-Completion-Bonus
    /// gewährt wurde — verhindert Mehrfach-Bonus pro Tag.
    var lastDailyBonusDayIndex: Int = -1

    /// Streak-Tage, an denen der einmalige Streak-Milestone-Bonus
    /// (siehe `GamificationConfig.creditsForStreakMilestones`) bereits
    /// vergeben wurde. So bekommt der User Tag-7-Bonus nur einmal,
    /// nicht jedes Mal wenn die Streak 7 berührt.
    var awardedStreakMilestones: Set<Int> = []

    /// **Mini-Session-Streak (2026-08-08)** — Day-Index, für den
    /// `todayCorrectCount` zählt. Weicht er vom aktuellen Tag ab, ist der
    /// Zähler aus einem Vortag und muss vor der nächsten Buchung auf 0.
    var todayCorrectDayIndex: Int = -1
    /// Wie viele Aufgaben heute schon korrekt beantwortet wurden — Basis
    /// für den entkoppelten Streak-Trigger (siehe
    /// `GamificationConfig.streakMiniSessionThreshold`).
    var todayCorrectCount: Int = 0

    var level: Int { GamificationConfig.level(forXP: totalXP) }
    var levelProgress: Double { GamificationConfig.progressTowardNextLevel(totalXP: totalXP) }

    /// `true`, wenn der Tages-Completion-Bonus für den aktuellen Day-Index
    /// noch NICHT vergeben wurde. Eine View kann darauf einen „heute noch
    /// offen"-Hinweis schalten; sobald der nächste qualifizierte Session-
    /// Abschluss durchläuft, setzt `ProgressService` den Flag automatisch.
    var isDailyBonusAvailable: Bool {
        lastDailyBonusDayIndex != GamificationConfig.currentDayIndex
    }
}

/// Persistierter Container für `UserProgress`. ObservableObject, damit
/// SwiftUI-Views (HomeView-Bar, Session-Summary etc.) reaktiv aktualisieren.
///
/// Single Source of Truth: legacy `@AppStorage`-Keys (XP, Streak, Credits)
/// werden hier weiterhin gelesen/geschrieben — andere Stellen, die noch
/// auf die alten Keys zugreifen, bleiben kompatibel. Mittelfristig sollten
/// alle Reads/Writes über diesen Store laufen.
@MainActor
final class ProgressStore: ObservableObject {
    /// App-weiter Singleton — vermeidet, dass jede View-Hierarchie eine
    /// eigene Container-Reference durchreichen muss. Module rufen einfach
    /// `ProgressStore.shared` (oder noch besser: `ProgressService.shared`)
    /// auf. Der `AppRuntimeContainer` referenziert dieselbe Instanz.
    static let shared = ProgressStore()

    @Published private(set) var progress: UserProgress

    // **Per-Account-Namespace** (Phase E): alle Keys werden pro Read/
    // Write durch `AccountStore.namespacedKey(_:)` geschickt. Wenn kein
    // Account aktiv ist (Startup pre-onboarding), fällt der Helper auf
    // den globalen Base-Key zurück — Verhalten kompatibel zur V1.
    private var xpKey: String { AccountStore.shared.namespacedKey(appElumiXPKey) }
    private var creditsKey: String { AccountStore.shared.namespacedKey(appArcadeCreditsKey) }
    private var streakKey: String { AccountStore.shared.namespacedKey(appElumiCurrentStreakKey) }
    private var bestStreakKey: String { AccountStore.shared.namespacedKey(appElumiBestStreakKey) }
    private var lastSessionDayKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.lastSessionDay.v1")
    }
    private var lastDailyBonusDayKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.lastDailyBonusDay.v1")
    }
    private var awardedMilestonesKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.awardedStreakMilestones.v1")
    }
    private var todayCorrectDayKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.todayCorrectDay.v1")
    }
    private var todayCorrectCountKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.todayCorrectCount.v1")
    }

    init() {
        self.progress = Self.loadSnapshot()
    }

    /// Lädt eine frische `UserProgress`-Instanz aus dem aktuell
    /// aktiven Account-Namespace. Statisch, damit der Init-Pfad und
    /// der Reload-Pfad (siehe unten) denselben Code nutzen.
    private static func loadSnapshot() -> UserProgress {
        let defaults = UserDefaults.standard
        let scope = AccountStore.shared
        var loaded = UserProgress()
        loaded.totalXP = defaults.integer(forKey: scope.namespacedKey(appElumiXPKey))
        loaded.currentStreak = defaults.integer(forKey: scope.namespacedKey(appElumiCurrentStreakKey))
        loaded.bestStreak = defaults.integer(forKey: scope.namespacedKey(appElumiBestStreakKey))
        loaded.lastSessionDayIndex = defaults.object(forKey: scope.namespacedKey("elumi.gamification.lastSessionDay.v1")) as? Int ?? -1
        loaded.lastDailyBonusDayIndex = defaults.object(forKey: scope.namespacedKey("elumi.gamification.lastDailyBonusDay.v1")) as? Int ?? -1
        if let credits = defaults.object(forKey: scope.namespacedKey(appArcadeCreditsKey)) as? Int {
            loaded.arcadeCredits = credits
        } else {
            loaded.arcadeCredits = 3
        }
        if let data = defaults.data(forKey: scope.namespacedKey("elumi.gamification.awardedStreakMilestones.v1")),
           let arr = try? JSONDecoder().decode([Int].self, from: data) {
            loaded.awardedStreakMilestones = Set(arr)
        }
        loaded.todayCorrectDayIndex = defaults.object(forKey: scope.namespacedKey("elumi.gamification.todayCorrectDay.v1")) as? Int ?? -1
        loaded.todayCorrectCount = defaults.integer(forKey: scope.namespacedKey("elumi.gamification.todayCorrectCount.v1"))
        return loaded
    }

    /// Schreibt eine geänderte `UserProgress`-Instanz zurück und persistiert
    /// alle Felder. Aufrufer mutieren über die `mutate`-Closure, damit der
    /// Store atomar updaten kann.
    func mutate(_ change: (inout UserProgress) -> Void) {
        var copy = progress
        change(&copy)
        progress = copy
        persist(copy)
    }

    /// Wird vom `AccountStore` nach einem Account-Switch gerufen —
    /// re-liest die Per-Account-Daten und publisht sie. Views, die auf
    /// `progress` binden, aktualisieren automatisch auf den neuen Stand.
    func reloadForCurrentAccount() {
        let snapshot = Self.loadSnapshot()
        progress = snapshot
        // **Codeaudit 2026-09-03, Stufe 3 (Punkt 18)** — der Bare-Slot
        // gehoert jetzt ausschliesslich diesem Store; die Swap-Maschine
        // im `AccountStore` fasst ihn nicht mehr an. Also muss der Store
        // ihn hier selbst nachziehen, sonst zeigten Footer-Credits, XP
        // und Streak nach einem Account-Wechsel noch die Zahlen des
        // vorigen Kindes, bis zufaellig der naechste `persist` laeuft.
        mirrorIntoBareSlot(snapshot)
    }

    /// Spiegelt die vier Werte mit `@AppStorage`-Lesern in den globalen
    /// Slot. Einzige Stelle neben `persist`, die den Bare-Key schreibt.
    private func mirrorIntoBareSlot(_ snapshot: UserProgress) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.totalXP, forKey: appElumiXPKey)
        defaults.set(snapshot.arcadeCredits, forKey: appArcadeCreditsKey)
        defaults.set(snapshot.currentStreak, forKey: appElumiCurrentStreakKey)
        defaults.set(snapshot.bestStreak, forKey: appElumiBestStreakKey)
    }

    private func persist(_ snapshot: UserProgress) {
        let defaults = UserDefaults.standard
        // **Per-Account namespaced** (primary).
        defaults.set(snapshot.totalXP, forKey: xpKey)
        defaults.set(snapshot.arcadeCredits, forKey: creditsKey)
        defaults.set(snapshot.currentStreak, forKey: streakKey)
        defaults.set(snapshot.bestStreak, forKey: bestStreakKey)
        defaults.set(snapshot.lastSessionDayIndex, forKey: lastSessionDayKey)
        defaults.set(snapshot.lastDailyBonusDayIndex, forKey: lastDailyBonusDayKey)
        if let data = try? JSONEncoder().encode(Array(snapshot.awardedStreakMilestones)) {
            defaults.set(data, forKey: awardedMilestonesKey)
        }
        defaults.set(snapshot.todayCorrectDayIndex, forKey: todayCorrectDayKey)
        defaults.set(snapshot.todayCorrectCount, forKey: todayCorrectCountKey)

        // **Bare-Key Mirror** (2026-05-09) — wenn ein Account aktiv ist
        // (`AccountStore.currentAccountID != nil`), divergieren die
        // `namespacedKey`-Pfade oben vom unpräfixten Bare-Key. Etliche
        // `@AppStorage(appArcadeCreditsKey)`-Reader (Footer-Credits,
        // ElumiTabView, GameHub, FlashcardsView, TrainingView, QuizView,
        // WordRunnerGameView, ElumiArcadeViews, ElumiFooterFeastButton,
        // ElumiArcadeGameView+PlayCredits) und analog `appElumiXPKey`/
        // `appElumiCurrentStreakKey`/`appElumiBestStreakKey` lesen aber
        // weiterhin den Bare-Key. Ohne Mirror sehen sie das Reset/Update
        // nicht — User-Befund: „Credits zurücksetzen in Settings wirkt
        // nicht im Footer".
        //
        // Dual-Write mirrort jeden persist-Call in beide Slots —
        // Read-Pfade (namespaced via ProgressStore + bare via @AppStorage)
        // sehen jetzt synchron denselben Wert.
        mirrorIntoBareSlot(snapshot)
    }
}

// MARK: - Streak (entkoppelt vom Tagesziel, 2026-08-08)

/// Ergebnis eines Streak-Vergabe-Versuchs. `advanced == false` heißt: heute
/// war schon gebucht, es ist nichts passiert (idempotent).
struct StreakAdvanceOutcome: Equatable {
    let advanced: Bool
    let newStreak: Int
    let milestoneCredits: Int
    /// Wie viele Joker-Tage verbraucht wurden, um die Lücke zu überbrücken.
    /// 0 im Normalfall (nahtlose Fortsetzung oder frischer Start).
    let jokersConsumed: Int
}

extension ProgressStore {
    /// Rückt den Streak für `today` vor — **einmal pro Tag**, unabhängig
    /// davon, WELCHE Session-Aktivität es war. Ersetzt den bisherigen
    /// Trigger über die volle Daily Challenge (siehe
    /// `DailyChallengeStore`): Aufrufer ist jetzt `ProgressService`, sobald
    /// `GamificationConfig.streakMiniSessionThreshold` an korrekten
    /// Antworten heute erreicht ist.
    ///
    /// **Joker-Logik**: Liegt zwischen dem letzten gebuchten Tag und heute
    /// eine Lücke, wird zuerst versucht, sie mit `StreakJokerStore` zu
    /// überbrücken (ein Joker deckt genau einen versäumten Tag). Reicht
    /// das Kontingent nicht, startet der Streak bei 1 neu — kein
    /// Teil-Verbrauch, kein stilles Clamping.
    @discardableResult
    func advanceStreakIfNeeded(today: Int) -> StreakAdvanceOutcome {
        guard progress.lastSessionDayIndex != today else {
            return StreakAdvanceOutcome(
                advanced: false,
                newStreak: progress.currentStreak,
                milestoneCredits: 0,
                jokersConsumed: 0
            )
        }

        var milestoneCredits = 0
        var jokersConsumed = 0

        mutate { p in
            let gap = today - p.lastSessionDayIndex
            if p.lastSessionDayIndex < 0 {
                p.currentStreak = 1
            } else if gap == 1 {
                p.currentStreak += 1
            } else {
                let missedDays = gap - 1
                let available = StreakJokerStore.shared.jokersRemaining
                if missedDays <= available {
                    StreakJokerStore.shared.consume(missedDays)
                    jokersConsumed = missedDays
                    p.currentStreak += 1
                } else {
                    p.currentStreak = 1
                }
            }
            p.bestStreak = max(p.bestStreak, p.currentStreak)
            p.lastSessionDayIndex = today

            if let bonus = GamificationConfig.creditsForStreakMilestones[p.currentStreak],
               !p.awardedStreakMilestones.contains(p.currentStreak) {
                p.arcadeCredits += bonus
                p.awardedStreakMilestones.insert(p.currentStreak)
                milestoneCredits = bonus
            }
        }

        return StreakAdvanceOutcome(
            advanced: true,
            newStreak: progress.currentStreak,
            milestoneCredits: milestoneCredits,
            jokersConsumed: jokersConsumed
        )
    }
}
