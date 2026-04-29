import SwiftUI

// **Stufe 6 Schritt 4 (2026-04-29)**: Die historische Icon-Set-A/B-
// Switch-Maschinerie (`AppIconSet`-Enum, `AppIconRegistry` mit
// `storageKey`/`current`/`setCurrent`/`resolved`, `Image(appIcon:)`-
// Init) ist entfernt. Set A wurde aus dem Asset-Catalog gelöscht
// (Schritt 2), die Set-B-Imagesets wurden zu den Basis-Namen
// umbenannt (Schritt 3), und die Settings-UI plus alle toten
// `@AppStorage(appIconSet)`-Observer sind in diesem Schritt weg.
//
// Der Filename `AppIconRegistry.swift` ist jetzt irreführend — der
// Inhalt ist nur noch eine UUID-Convenience-Extension, die unab-
// hängig vom Icon-System ist und in mehreren Scanner-Stellen für
// kompakte Log-Ausgaben verwendet wird (`📋 [Capture-Identity abc123]`).
// Backlog-Item: File-Rename `AppIconRegistry.swift`
// → `UUIDExtensions.swift` o.ä. (separater Cleanup-Branch wegen
// pbxproj-Änderung).
//
// Verwaister `UserDefaults["appIconSet"]`-Eintrag bleibt auf
// existierenden Geräten liegen — harmlos, kein Migration-Pfad
// jetzt. Bei nächstem ohnehin notwendigen Migration-Pfad mit-
// aufräumen.

// MARK: - UUID Convenience

extension UUID {
    /// Erste 6 Zeichen der UUID für kompakte Logs
    /// (z. B. `📋 [Capture-Identity abc123]`).
    var shortID: String { String(uuidString.prefix(6)) }
}
