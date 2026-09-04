import Foundation
import UIKit

/// **Stabiler Datenträger** für eine im Auto-Modus aufgenommene
/// Scan-Capture (User-Spec 2026-04-22 Abend VI).
///
/// Vorher lief der Multi-Capture-Flow nur über lose `[UIImage]`-Arrays
/// in `ScanSessionController`. Das hatte zwei Folgen:
///   • UI hatte keine stabile Identität pro Aufnahme — Selection
///     konnte nicht zugeordnet werden, Thumbnails wirkten „eingefroren"
///   • Beim Tap auf „Zurück" gingen Captures unkontrolliert verloren,
///     weil keine Quelle der Wahrheit existierte
///
/// `CapturedScanItem` löst beides durch eine Identifiable-Struktur mit
/// `UUID`. Die Sammlung lebt im Session-Controller (`capturedItems`),
/// die Auswahl in `selectedCapturedItemID`. Damit kann die UI
/// stabil rendern und persistent sein, bis der User die Captures
/// **bewusst** verwirft.
///
/// Status-Tracking:
///   • `.pending` — Capture liegt vor, aber wurde noch nicht zur
///                  Analyse geschickt
///   • `.analyzed` — der User hat „Überprüfen" auf diese Capture
///                   gedrückt und die Pipeline ist durchgelaufen
///   • `.failed` — die Analyse ist fehlgeschlagen, das Bild bleibt
///                 aber in der Sammlung erhalten (User-Spec:
///                 „Wenn ein Bild nicht verarbeitet werden kann,
///                 trotzdem Session und restliche Bilder behalten")
struct CapturedScanItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case analyzed
        case failed
    }

    let id: UUID
    let originalImage: UIImage
    let createdAt: Date
    var status: Status

    init(
        id: UUID = UUID(),
        originalImage: UIImage,
        createdAt: Date = Date(),
        status: Status = .pending
    ) {
        self.id = id
        self.originalImage = originalImage
        self.createdAt = createdAt
        self.status = status
    }

    static func == (lhs: CapturedScanItem, rhs: CapturedScanItem) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.createdAt == rhs.createdAt
    }
}
