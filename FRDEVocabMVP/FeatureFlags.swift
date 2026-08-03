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
}
