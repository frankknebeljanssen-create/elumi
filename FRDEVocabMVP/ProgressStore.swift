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
        progress = Self.loadSnapshot()
    }

    private func persist(_ snapshot: UserProgress) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.totalXP, forKey: xpKey)
        defaults.set(snapshot.arcadeCredits, forKey: creditsKey)
        defaults.set(snapshot.currentStreak, forKey: streakKey)
        defaults.set(snapshot.bestStreak, forKey: bestStreakKey)
        defaults.set(snapshot.lastSessionDayIndex, forKey: lastSessionDayKey)
        defaults.set(snapshot.lastDailyBonusDayIndex, forKey: lastDailyBonusDayKey)
        if let data = try? JSONEncoder().encode(Array(snapshot.awardedStreakMilestones)) {
            defaults.set(data, forKey: awardedMilestonesKey)
        }
    }
}
