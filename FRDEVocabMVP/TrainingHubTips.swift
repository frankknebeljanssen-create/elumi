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
    /// Aktueller Pool. Sieben kindgerechte Tipps in Teen-Sprache —
    /// **Naming-Sweep 2026-05-06**: Pool komplett neu geschrieben
    /// (vorher generischere Lehrer-Sprache; jetzt direkter, ehrlicher,
    /// kürzer). Mix aus Akzent/Verben/Artikel-Tipps und Konsistenz-
    /// Motivation („lieber 10 Min täglich als 1 Stunde am Sonntag").
    static let pool: [String] = [
        "Akzente sind tricky. Üben hilft.",
        "Verben? Brauchst du in jedem Satz.",
        "5 Min Speed-Modus reicht.",
        "Le, la oder l'? Mit Übung kein Problem.",
        "Lieber 10 Min täglich als 1 Stunde am Sonntag.",
        "Imparfait nervt? Ja, alle.",
        "Heute 5 Min. Morgen wieder 5. Reicht."
    ]

    /// Liefert einen zufällig gewählten Tipp. Fallback auf den
    /// ersten Eintrag, falls der Pool leer ist (defensiv).
    static func random() -> String {
        pool.randomElement() ?? pool.first ?? "Tipp: Übe regelmäßig!"
    }
}
