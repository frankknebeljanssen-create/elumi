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
}
