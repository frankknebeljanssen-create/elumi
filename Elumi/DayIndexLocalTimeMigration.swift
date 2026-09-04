import Foundation

/// **Codeaudit 2026-09-03, Stufe 3 (Punkt 20)** — einmalige Umrechnung
/// aller persistierten Tagesindizes von der alten UTC-Rechnung auf die
/// neue Ortszeit-Rechnung.
///
/// Warum das nötig ist: Ein Tagesindex ist für sich genommen bedeutungslos,
/// er zählt nur im Vergleich mit „heute". Ändert sich die Rechnung, ohne
/// dass die gespeicherten Werte mitwandern, vergleicht die App plötzlich
/// zwei verschiedene Maßstäbe. Der letzte Übungstag sähe je nach Vorzeichen
/// aus wie „schon heute gebucht" (die Serie rückt nie wieder vor) oder wie
/// „lange her" (die Serie reißt und Joker verbrennen). Beides beim ersten
/// Start nach dem Update, ohne dass der Nutzer etwas falsch gemacht hätte.
///
/// Die Verschiebung ist für alle Werte dieselbe: die Differenz zwischen
/// neuer und alter Rechnung für **jetzt**. Damit bleiben alle Abstände
/// erhalten — was gestern war, ist danach immer noch gestern.
///
/// **Multi-Account**: Die Indizes liegen teils im globalen Slot, teils
/// unter `<uuid>/<key>`. Die Migration läuft deshalb über alle Keys, die
/// auf einen der bekannten Basis-Keys enden, und erfasst so jedes Kind
/// auf dem Gerät in einem Durchlauf.
///
/// **Bewusst ausgenommen**: `appElumiLastRewardDayIndexKey`. Dieser Wert
/// wurde schon immer mit `elumiRewardDayIndex` in Ortszeit gerechnet und
/// steht deshalb bereits auf dem neuen Maßstab.
enum DayIndexLocalTimeMigration {

    private static let migratedFlagKey = "elumi.migration.localDayIndex.v1"

    /// Basis-Keys, deren Werte Tagesindizes der alten UTC-Rechnung sind.
    private static let dayIndexBaseKeys: [String] = [
        "elumi.gamification.lastSessionDay.v1",
        "elumi.gamification.lastDailyBonusDay.v1",
        "elumi.gamification.todayCorrectDay.v1",
        "elumi.dailyStats.dayIndex.v1",
        appDailyWrapUpDayKey
    ]

    /// Läuft einmal pro Installation, so früh wie möglich beim App-Start —
    /// **vor** dem ersten Zugriff auf einen der betroffenen Stores, sonst
    /// liest der Store noch den alten Wert und schreibt ihn später zurück.
    static func runIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard !defaults.bool(forKey: migratedFlagKey) else { return }
        defer { defaults.set(true, forKey: migratedFlagKey) }

        let delta = GamificationConfig.dayIndex(for: now)
            - GamificationConfig.legacyUTCDayIndex(for: now)
        guard delta != 0 else {
            appDebugLog("ℹ️ [DayIndexMigration] Differenz 0 — nichts umzurechnen")
            return
        }

        var shifted = 0
        for key in defaults.dictionaryRepresentation().keys where matchesDayIndexKey(key) {
            // `object(forKey:)` statt `integer(forKey:)`: ein fehlender
            // oder andersartiger Wert soll nicht als 0 durchgehen und
            // dadurch einen Index erfinden, den es nie gab.
            guard let value = defaults.object(forKey: key) as? Int else { continue }
            defaults.set(value + delta, forKey: key)
            shifted += 1
        }

        // Die Tages-Challenge trägt ihren Index in einem JSON-Blob. Sie
        // wird bewusst NICHT umgerechnet: passt der Index nicht zu heute,
        // legt der `DailyChallengeStore` von selbst eine neue an. Der
        // Preis ist der heutige Challenge-Fortschritt, einmalig, beim
        // Update — billiger als eine Decode-/Encode-Runde über einen
        // Blob, dessen Format sich ändern kann.
        appDebugLog("✅ [DayIndexMigration] \(shifted) Tagesindizes um \(delta) verschoben (UTC → Ortszeit)")
    }

    private static func matchesDayIndexKey(_ key: String) -> Bool {
        dayIndexBaseKeys.contains { base in
            key == base || key.hasSuffix("\(AccountStore.keyNamespaceSeparator)\(base)")
        }
    }
}
