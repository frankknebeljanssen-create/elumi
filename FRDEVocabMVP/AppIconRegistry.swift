import SwiftUI

/// **Icon-Set-Schalter (Übergangs-Zustand, Stufe 6 Schritt 1, 2026-04-29)**.
///
/// Historisch lieferte die App zwei parallele Icon-Sets aus (Set A — flache
/// 2D-Cartoon-Icons; Set B — 3D-Style aus `elumi-icon-set-B_0419`). Stufe 6
/// dropt Set A und macht Set B zum Standard. In **diesem Schritt** sind:
///   • der `resolved(...)`-Resolver und der `Image(appIcon:)`-Init entfernt
///   • `assetName` in den Enums liefert den B-Suffix-Namen direkt (hartkodiert)
///   • Die Set-Switch-Settings-UI (in `SettingsView`) und die
///     `@AppStorage`-Observer in mehreren Views **bleiben temporär bestehen** —
///     sie schreiben in einen Slot, der nichts mehr beeinflusst. Schritt 4
///     räumt das vollständig auf.
///
/// `AppIconSet`/`storageKey`/`current`/`setCurrent` bleiben für die
/// Settings-UI-Konsistenz, bis Schritt 4 sie zusammen mit dem Switch
/// entfernt. Der UUID-Helper unten ist unabhängig und bleibt dauerhaft.
enum AppIconSet: String, CaseIterable, Codable {
    case a, b

    var displayName: String {
        switch self {
        case .a: return "Set A"
        case .b: return "Set B"
        }
    }
}

/// Single Source of Truth für die aktive Icon-Set-Wahl.
enum AppIconRegistry {
    /// `UserDefaults`-Key. Identisch zur `@AppStorage`-Wrapper-Definition
    /// in der Settings-View — beide schreiben in denselben Slot.
    static let storageKey = "appIconSet"

    /// Liefert das aktive Set. Default `.a` (bestehendes UI-Verhalten
    /// bleibt unverändert, solange der User nicht aktiv umschaltet).
    static var current: AppIconSet {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let set = AppIconSet(rawValue: raw) else { return .a }
        return set
    }

    /// Setzt das aktive Set.
    static func setCurrent(_ set: AppIconSet) {
        UserDefaults.standard.set(set.rawValue, forKey: storageKey)
    }
}

// MARK: - UUID Convenience

extension UUID {
    /// Erste 6 Zeichen der UUID für kompakte Logs
    /// (z. B. `📋 [Capture-Identity abc123]`).
    var shortID: String { String(uuidString.prefix(6)) }
}
