import Foundation

/// **Streak-Joker (2026-08-08)** — begrenztes, kostenloses Sicherheitsnetz
/// für den Tages-Streak.
///
/// Evidenzgrundlage: Sharif & Shu (2017, Journal of Marketing Research) —
/// ein hartes Ziel MIT begrenzten "Emergency Reserves" erreicht bis zu
/// 40 % höhere Zielerreichung als sowohl das harte als auch das weiche
/// Ziel ohne Reserve, und eine deutlich höhere Rückkehrquote nach einem
/// verpassten Tag (55 % statt 37 %). Der Mechanismus wirkt, WEIL die
/// Reserve knapp ist — deshalb bewusst:
///   • **nicht kaufbar** (keine Monetarisierung von Angst bei Minderjährigen)
///   • **fest begrenzt** (2 pro Kalendermonat, siehe `maxPerMonth`)
///   • **sichtbar** (die Knappheit muss der User spüren können)
///
/// Ein Joker deckt genau einen versäumten Tag — kein Teil-Verbrauch.
/// Reset am Kalendermonatswechsel (nicht rollierend), damit "wie viele
/// habe ich noch diesen Monat" eine einfache, im Kopf nachvollziehbare
/// Frage bleibt.
@MainActor
final class StreakJokerStore: ObservableObject {
    static let shared = StreakJokerStore()

    static let maxPerMonth = 2

    @Published private(set) var usedThisMonth: Int = 0
    private var monthKey: String = ""

    private var monthKeyStorageKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.streakJoker.monthKey.v1")
    }
    private var usedCountStorageKey: String {
        AccountStore.shared.namespacedKey("elumi.gamification.streakJoker.usedCount.v1")
    }

    init() {
        load()
    }

    /// Wie viele Joker diesen Monat noch verfügbar sind.
    var jokersRemaining: Int {
        refreshMonthIfNeeded()
        return max(0, Self.maxPerMonth - usedThisMonth)
    }

    /// Verbraucht `count` Joker. Der Aufrufer (`ProgressStore.advanceStreakIfNeeded`)
    /// prüft vorher über `jokersRemaining`, ob genug verfügbar sind — hier
    /// wird bewusst NICHT geclampt, damit ein Aufrufer-Fehler sichtbar
    /// bleibt statt sich still in falschen Zahlen zu verstecken.
    func consume(_ count: Int) {
        guard count > 0 else { return }
        refreshMonthIfNeeded()
        usedThisMonth += count
        persist()
    }

    /// Wird vom `AccountStore` nach einem Account-Switch gerufen.
    func reloadForCurrentAccount() {
        load()
    }

    private static func currentMonthKey(reference: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = .current
        return formatter.string(from: reference)
    }

    private func refreshMonthIfNeeded() {
        let current = Self.currentMonthKey()
        guard current != monthKey else { return }
        monthKey = current
        usedThisMonth = 0
        persist()
    }

    private func load() {
        let defaults = UserDefaults.standard
        monthKey = defaults.string(forKey: monthKeyStorageKey) ?? Self.currentMonthKey()
        usedThisMonth = defaults.integer(forKey: usedCountStorageKey)
        refreshMonthIfNeeded()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(monthKey, forKey: monthKeyStorageKey)
        defaults.set(usedThisMonth, forKey: usedCountStorageKey)
    }
}
