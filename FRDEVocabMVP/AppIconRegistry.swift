import SwiftUI
import UIKit

/// **Globaler Icon-Set-Schalter**.
///
/// Die App liefert zwei vollständige, parallele Icon-Sets aus:
///   • **Set A** — die ursprünglichen Cartoon-Icons (Asset-Namen ohne Suffix).
///   • **Set B** — der alternative Stil aus `elumi-icon-set-B_0419` (Asset-
///     Namen mit `B`-Suffix; identische Asset-Geometrie und Bounding-Boxes,
///     damit der Wechsel keine Tile-Sprünge erzeugt).
///
/// **Garantie**: Es gibt nur **einen** globalen Schalter (`UserDefaults`-
/// Key `appIconSet`), und alle Icon-Lookups in der App gehen entweder über
/// `Image(appIcon:)` (für direkte Aufrufstellen) oder über die zentralen
/// Wrapper `HomeModuleIcon.assetName` / `ElumiIcon.assetName` (die intern
/// denselben Resolver nutzen). Damit ist Misch-Zustand technisch
/// ausgeschlossen — nach Set-Wechsel + App-Neustart erscheint überall nur
/// das gewählte Set.
///
/// **Live-Wechsel**: SwiftUI-Views, die Icons direkt rendern, werden bei
/// einem Set-Wechsel **nicht** automatisch invalidiert (statische Resolver).
/// Der User-Vertrag (Settings-Card-Hint): „Neustart empfohlen". Das
/// vermeidet teure Environment-Propagation und garantiert, dass nach dem
/// nächsten Cold-Start jedes Asset frisch geladen wird.
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

    /// Löst einen Asset-Basisnamen auf das Asset des aktiven Sets auf.
    /// Wenn das Set-B-Asset (Suffix „B") existiert, wird es zurückgegeben;
    /// sonst Fallback auf den Basisnamen (Set A bzw. Set ohne B-Pendant).
    static func resolved(_ baseName: String) -> String {
        switch current {
        case .a:
            return baseName
        case .b:
            let candidate = baseName + "B"
            // `UIImage(named:)` fragt den Asset-Catalog ab. Bei nicht
            // existierendem B-Pendant fällt der Lookup auf das A-Asset
            // zurück — sicherer Fallback, kein leeres Image.
            if UIImage(named: candidate) != nil {
                return candidate
            }
            return baseName
        }
    }
}

// MARK: - Image-Convenience

// MARK: - UUID Convenience

extension UUID {
    /// Erste 6 Zeichen der UUID für kompakte Logs
    /// (z. B. `📋 [Capture-Identity abc123]`).
    var shortID: String { String(uuidString.prefix(6)) }
}

extension Image {
    /// Asset-Lookup, der **immer** das aktive Icon-Set respektiert.
    /// Nutze diesen Init überall, wo direkt eine Asset-Konstante gerendert
    /// wird (statt `Image("HomeIconNomen")` → `Image(appIcon: "HomeIconNomen")`).
    ///
    /// Kein Live-Wechsel: bei einem Set-Switch in den Settings sieht der
    /// User die neue Auswahl nach **App-Neustart**. Dieser Trade-off ist
    /// bewusst — siehe `AppIconRegistry`-Doc.
    init(appIcon baseName: String) {
        self.init(AppIconRegistry.resolved(baseName))
    }
}
