// FeatureFlags.swift
// **2026-06-09** — Zentraler Namespace für Feature-Flags. Bisher gab es
// keinen Flag-Mechanismus in der App (Audit bestätigt). Erster Eintrag:
// Léa-Chat, der wegen eines Backend-Connectivity-Bugs für die TestFlight-
// Demo deaktiviert werden soll, ohne bestehenden Chat-Code anzufassen.
//
// Bewusst simpel gehalten (Bool-Konstanten, kein Remote-Config, kein
// Store) — Verdrahtung an den einzelnen Call-Sites passiert in separaten
// Prompts, diese Datei liefert nur die Single-Source-of-Truth.

import Foundation

enum FeatureFlags {
    /// Léa-Chat wegen Backend-Bug deaktiviert. Nach Fix: auf true zurückstellen.
    static let leaChatEnabled = false

    /// **2026-06-09** — Willkommens-Screen bei JEDEM App-Start zeigen.
    /// Für die Testphase gewollt, damit der Screen ohne Deinstallation
    /// immer wieder prüfbar ist.
    ///
    /// Vor Release auf `false` stellen: dann erscheint der Screen nur
    /// beim allerersten Start (persistiert über `HintStore`, gleiche
    /// Mechanik wie die Erstnutzer-Hints).
    static let alwaysShowWelcomeScreen = true

    /// **2026-08-05** — Ziel-Onboarding bei JEDEM App-Start zurücksetzen.
    /// Rein fürs Testen des neuen Ziel-Systems: ohne diesen Flag müsste
    /// man vor jedem Durchlauf manuell in die Dev-Card und "Ziel
    /// löschen" tippen. Mit `true` ist beim Start jedes Mal der
    /// Zustand eines frischen Testnutzers da — der gesamte
    /// Onboarding-Flow (inkl. Scan-Rückweg) lässt sich ohne
    /// Neuinstallation wiederholt durchklicken.
    ///
    /// Setzt NUR den Wochenfortschritt + Plan zurück
    /// (`LearningGoalStore.reset()`), rührt keine anderen Daten an.
    ///
    /// Vor Release auf `false` stellen — sonst verliert jeder Nutzer
    /// bei jedem App-Start sein gesetztes Lernziel.
    static let alwaysResetGoalOnboardingForTesting = true

    /// **2026-08-05** — Feature-Karten auf dem Willkommens-Screen
    /// ausblenden (Vokabelheft fotografieren / Üben / Jeden Tag /
    /// Spiele freischalten).
    ///
    /// Hintergrund: Der Screen erklärte vier Funktionen, bevor der
    /// Nutzer überhaupt weiß, ob ihn die App interessiert. Die
    /// NN/g-Teenager-Forschung ist da eindeutig — dichter Text ist ein
    /// Abbruch-Auslöser, und Jugendliche haben sehr wenig Geduld.
    /// Erklärt wird jetzt am ENDE des Onboardings (Modul-Screen), wenn
    /// der Nutzer bereits investiert hat und die Info tatsächlich
    /// brauchen kann.
    ///
    /// Nebeneffekt, der den Ausschlag gab: Elumi stellte sich zweimal
    /// vor — einmal hier, einmal im Ziel-Onboarding. Ohne die Karten
    /// ist dieser Screen ein reiner Türöffner, die Vorstellung passiert
    /// nur noch an einer Stelle.
    ///
    /// Der Code bleibt vollständig erhalten: `false` setzen bringt die
    /// Karten unverändert zurück.
    static let welcomeScreenFeatureCardsEnabled = false

    /// **2026-06-09** — Lernjahr-Auswahl für die Demo ausgeblendet.
    /// Der Grundwortschatz A1 ist damit nur noch als Ganzes an- und
    /// abwählbar; die „LJ 1-3"-Pills verschwinden app-weit.
    ///
    /// Der Mechanismus dahinter bleibt vollständig erhalten — es ist
    /// ein reines UI-Gate:
    ///   • `VocabularyListSelectionResolver.currentLernjahrMax()` gibt
    ///     `nil` zurück → `effectiveItems` liefert den vollen Parent.
    ///     Der gespeicherte Wert in UserDefaults bleibt unangetastet.
    ///   • `lernjahrRangeLabel()` gibt `nil` → alle Pills verschwinden.
    ///   • Die aufklappbaren Lernjahr-Rows in den beiden Listen-Pickern
    ///     rendern als einfache Zeile.
    ///
    /// Auf `true` zurückstellen reaktiviert alles, inklusive der zuvor
    /// gespeicherten Lernjahr-Wahl.
    static let learningYearSelectionEnabled = false

    /// **2026-06-09** — Maximale Anzahl Seiten pro Scan-Durchgang.
    /// Für die Demo auf 1 begrenzt: weniger Anthropic-Vision-Kosten
    /// pro Scan und ein einfacherer, geradliniger Flow (fotografieren →
    /// direkt zur Analyse, kein „weitere Seite hinzufügen").
    ///
    /// Der Produktionswert ist 10 (Kamera-Multi-Shot) bzw. 20
    /// (Album-Mehrfachauswahl). Beide Consumer lesen diesen Flag als
    /// Obergrenze via `min(nativerWert, maxScanPagesPerRun)` — steht der
    /// Flag also auf einen Wert ≥ dem nativen Limit (z. B. 20 oder
    /// `Int.max`), greift wieder exakt das alte Verhalten. Die
    /// Mehrseiten-Logik selbst bleibt vollständig im Code.
    static let maxScanPagesPerRun = 1
}
