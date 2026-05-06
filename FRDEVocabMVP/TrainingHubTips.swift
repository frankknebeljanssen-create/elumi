// TrainingHubTips.swift
// **2026-05-06** — Lern-Tipp-Pool für die TrainingHubView. Vorher
// hatte der Hub-Screen unterhalb der Spezial-Sektion freien Raum;
// mit dem Polish-Pass (Hybrid γ v3 Iteration 3) sitzt dort jetzt ein
// Maskottchen + ein wechselnder Lern-Tipp aus diesem Pool.
//
// Auswahl: Random pro Hub-Visit (`.onAppear`-Trigger), nicht
// persistent — `@State` reicht und wird beim View-Re-Mount neu
// gewürfelt. Pattern-Vorlage: `ElumiHints.swift` (ELUMI-Tab-Header).
//
// Tipps sind kindgerecht (11–17 Jahre), Französisch-Schul-Kontext,
// kurz genug für die Hub-Card-Breite. Bei Erweiterung max. ~60
// Zeichen pro Eintrag, sonst bricht der Text auf schmalen Geräten
// um.

import Foundation

/// Lern-Tipp-Pool für die TrainingHubView. Pool-Erweiterung passiert
/// hier in einem Schritt — Caller liest immer `random()`.
enum TrainingHubTips {
    /// Aktueller Pool. Sieben kindgerechte Tipps zu den Lern-Modi
    /// im Hub: Vokabeln (Allgemein), Nomen / Verben / Artikel /
    /// Verbformen (Spezial), Akzente (quer). Mischung aus
    /// Wissen-Häppchen, Praxis-Tipps und kleinen Motivationen.
    static let pool: [String] = [
        "Tipp: Nomen üben hilft beim Schreiben.",
        "Wusstest du? Akzente ändern die Bedeutung!",
        "Spezial-Übungen sind perfekt für Hausaufgaben.",
        "Verben sind das Herz jedes Satzes.",
        "Artikel — le, la, l' — am besten gleich mitlernen.",
        "Verbformen üben macht das Sprechen leichter.",
        "Schon 5 Minuten am Tag bringen dich voran."
    ]

    /// Liefert einen zufällig gewählten Tipp. Fallback auf den
    /// ersten Eintrag, falls der Pool leer ist (defensiv).
    static func random() -> String {
        pool.randomElement() ?? pool.first ?? "Tipp: Übe regelmäßig!"
    }
}
