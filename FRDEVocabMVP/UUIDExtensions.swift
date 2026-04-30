import Foundation

/// **UUID-Convenience-Extensions**.
///
/// Der ehemalige Filename `AppIconRegistry.swift` referenzierte die
/// Icon-Set-A/B-Switch-Maschinerie (entfernt in Stufe 6, Tag
/// `v2-icon-cleanup`, 2026-04-29). Mit dem Rename zu
/// `UUIDExtensions.swift` (Tag `v2-uuid-extensions-rename`,
/// 2026-04-30) entspricht der Dateiname jetzt dem Inhalt.
extension UUID {
    /// Erste 6 Zeichen der UUID für kompakte Logs
    /// (z. B. `📋 [Capture-Identity abc123]`).
    var shortID: String { String(uuidString.prefix(6)) }
}
