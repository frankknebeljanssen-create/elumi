import Foundation

extension ClaudeHaikuScanAIClient {
    /// Konstruiert den Scan-Client für den Backend-Proxy. Kein lokaler
    /// Schlüssel mehr nötig — die Auth läuft serverseitig. Das Modell
    /// kann optional via Env-Var `ANTHROPIC_SCAN_MODEL` überschrieben
    /// werden (leerer Wert = ignoriert); Default ist Haiku. Liefert nie
    /// `nil` (Optional-Signatur bleibt nur für Aufruf-Kompatibilität).
    ///
    /// **Phase 1.6** — die frühere mehrstufige Auflösung (Env →
    /// Info.plist → gebundelte Config-Plist) über die geteilten Config-
    /// Helfer ist entfernt; die Plist hielt nie einen
    /// `ANTHROPIC_SCAN_MODEL`-Eintrag, daher ist die reine Env-Auflösung
    /// verhaltens-äquivalent.
    static func fromEnvironment() -> ClaudeHaikuScanAIClient? {
        let model = ProcessInfo.processInfo.environment["ANTHROPIC_SCAN_MODEL"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "claude-haiku-4-5-20251001"
        return ClaudeHaikuScanAIClient(model: model)
    }
}
