import SwiftUI

extension HeartsView {

    // MARK: - Identitäts-Spiegel aus ProfileStore
    //
    // Profil-Anzeigename zentral aus dem ProfileStore. Leer-String bleibt
    // leer, damit Abfrage-Stellen (heroSubtitle, introSubtitle) auf einen
    // neutralen Fallback fallen können.
    var displayName: String {
        profileStore.hasName ? profileStore.displayName : ""
    }

    // MARK: - Level-Berechnung (Elumi-Tier-System)
    //
    // Dieser Screen nutzt weiterhin das bestehende Elumi-Tier-System mit
    // benannten Leveln (Anemonen-Forscher, Erforscher, Challenger …) und
    // fixen XP-Schwellen. Das ist bewusst unabhängig von `GamificationConfig`
    // (lineare 250-XP-Levels) — die emotionale Tier-Benennung lebt nur
    // hier, der Rest der App nutzt die numerischen Levels.
    var currentLevel: ElumiLevelTier {
        elumiLevelTier(for: collectedXP)
    }

    var nextLevel: ElumiLevelTier? {
        nextElumiLevelTier(for: collectedXP)
    }

    /// XP bis zum nächsten Tier. 0 wenn Max-Level erreicht.
    var xpToNextLevel: Int {
        guard let nextLevel else { return 0 }
        return max(0, nextLevel.threshold - collectedXP)
    }

    /// Anteil 0…1 zum nächsten Tier — für die Hero-Progress-Bar.
    var levelProgress: CGFloat {
        guard let nextLevel else { return 1 }
        let lowerBound = currentLevel.threshold
        let span = max(1, nextLevel.threshold - lowerBound)
        let raw = CGFloat(collectedXP - lowerBound) / CGFloat(span)
        return min(max(raw, 0), 1)
    }

    // MARK: - Streak-Kontext

    /// Multiplikator-Stand je nach aktueller Streak (Elumi-Tabelle).
    var activeMultiplier: Double {
        elumiStreakMultiplier(for: currentStreak)
    }

    /// Nächster Streak-Meilenstein — `nil`, wenn kein Meilenstein mehr
    /// offen ist (User hat 30+ Tage, alle Schwellen erreicht).
    var nextStreakMilestone: Int? {
        if currentStreak < 7 { return 7 }
        if currentStreak < 30 { return 30 }
        return nil
    }

    /// Streak-Meilenstein-Footerzeile im Lernstand-Strip. Bewusst kurz —
    /// bei 0-Streak erscheint sie nicht, damit der Lernstand ruhig bleibt.
    var streakMilestoneTagline: String? {
        guard let next = nextStreakMilestone else {
            return currentStreak >= 30 ? "Max-Streak gehalten — stark!" : nil
        }
        let diff = max(0, next - currentStreak)
        if diff == 0 { return nil }
        if diff == 1 { return "Noch 1 Tag bis zum nächsten Streak-Meilenstein" }
        return "Noch \(diff) Tage bis zum nächsten Streak-Meilenstein"
    }

    // MARK: - Sektions-Subtexte

    // MARK: - Daily-Challenge Footer (Progress-Hub-Integration Phase 5)
    //
    // Leicht eingebundene Zeilen im Lernstand-Strip — der Hub bekommt
    // *nichts* Missiv-Haftes, keinen eigenen Mission-Block, sondern nur
    // eine dezente kontextuelle Zeile zum aktuellen Tages-Status.

    var dailyChallengeFooterText: String? {
        guard let c = dailyChallengeStore.challenge else { return nil }
        switch c.status {
        case .done:
            return "Tagesaufgabe erledigt — Streak gesichert"
        case .inProgress:
            return "Tagesaufgabe: \(c.currentProgress)/\(c.target)"
        case .open:
            return "Tagesaufgabe: \(c.type.title)"
        }
    }

    var dailyChallengeFooterIcon: String {
        switch dailyChallengeStore.challenge?.status {
        case .done: return "checkmark.circle.fill"
        default: return dailyChallengeStore.challenge?.type.systemImage ?? "sparkles"
        }
    }

    var dailyChallengeFooterTint: Color {
        switch dailyChallengeStore.challenge?.status {
        case .done: return AppTheme.Colors.success
        default: return AppTheme.Colors.cta
        }
    }

    /// Subline des Lernstand-Sektionskopfs — leicht kontextuell:
    /// bei aktiver Streak einen persönlichen Touch, sonst neutral.
    var learningStandSubtitle: String {
        if currentStreak <= 0 {
            return "Startet mit deiner ersten Session."
        }
        if let name = profileStore.hasName ? profileStore.displayName : nil {
            return "\(name), du ziehst das durch."
        }
        return "Du ziehst das durch."
    }
}
