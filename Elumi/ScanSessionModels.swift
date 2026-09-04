import Foundation
import SwiftUI

enum ScanInputMethod {
    case camera
    case library
}

/// Live-Phase der Scan-/Analyse-Pipeline — wird vom `ScanSessionController`
/// (`@Published var scanRuntimeStage`) gehalten und **systemweit** als
/// einzige Wahrheit für die Status-Anzeige im Scan-UI benutzt.
///
/// Reihenfolge der Cases spiegelt den typischen Pipeline-Fluss wider:
///
///     .idle
///       → .preparingImage   (Bild wird skaliert/rotiert/vorbereitet)
///       → .ocrPreflight     (Vision-OCR lokal, schneller Pass)
///       → .aiConnecting     (Payload bauen + Verbindung zur KI)
///       → .aiPrimary        (KI analysiert das Bild)
///       → .aiReceiving      (KI-Antwort wird empfangen + entpackt)
///       → .parsingResults   (Vokabelpaare werden erkannt/zusammengeführt)
///       → .ocrFallback      (fallback: erweiterte OCR falls KI unsicher)
///       → .finalizing       (letzte Aufräumarbeiten vor Preview)
///       → .idle              (fertig)
///
/// Nicht jede Stage wird bei jedem Scan durchlaufen — z. B. läuft
/// `.ocrFallback` nur, wenn die KI unzureichende Ergebnisse liefert.
/// Die UI-Komponente (`ScanProgressOverlayCardView`) blendet den Text
/// passend zum aktuellen Case ein.
///
/// **Wichtig beim Erweitern**: pro neuer Stage auch die Display-Metadata
/// in der `ScanRuntimeStage` Extension weiter unten pflegen, sonst
/// fehlt der User-Text und die Stage läuft stumm durch.
enum ScanRuntimeStage: Equatable {
    case idle
    case preparingImage
    case ocrPreflight
    case aiConnecting
    case aiPrimary
    case aiReceiving
    case parsingResults
    case ocrFallback
    case finalizing
}

// MARK: - Display-Metadata
//
// Single Source of Truth für alles, was der User über die aktuelle
// Scan-Phase sieht. Zuvor lag das verstreut in
// `ScanImportView+ComputedState` (`scanProgressRuntimeLabel`,
// `scanProgressRuntimeIcon`, `scanProgressRuntimeTint`) — mit der
// neuen Struktur steht pro Stage **ein** Block hier, der alles
// (Titel, Sub-Info, Icon, Tint) zusammenhält. Neue Stages brauchen
// nur einen zusätzlichen `case`-Eintrag in jeder Property.

extension ScanRuntimeStage {
    /// Große Headline oben im Overlay — kurzer, aktivischer Satz („KI
    /// liest dein Bild", „Vokabelpaare werden erkannt"). Bewusst ohne
    /// Auslassungspunkte — der animierte Dot-Zähler (`scanProgressText`)
    /// signalisiert bereits, dass die Phase läuft.
    ///
    /// Default-Variante ohne Input-Method-Kontext — benutzt „Bild" als
    /// neutralen Begriff. Call-Sites mit bekanntem `ScanInputMethod`
    /// sollten stattdessen `displayTitle(for:)` aufrufen, damit das
    /// Wording an Kamera (→ „Foto") / Galerie (→ „Bild") angepasst wird.
    var displayTitle: String {
        displayTitle(for: nil)
    }

    /// Wording-Variante mit Input-Method-Kontext. Der einzige Case, der
    /// aktuell branched, ist `.aiPrimary`:
    ///
    ///   • Kamera  → „KI analysiert dein **Foto**"
    ///   • Galerie → „KI analysiert dein **Bild**"
    ///   • unknown → „KI analysiert dein Bild" (Default)
    ///
    /// Alle anderen Stages bleiben mode-neutral — das Wort „Bild" ist
    /// dort Sammelbegriff und muss nicht doppelt geführt werden.
    func displayTitle(for inputMethod: ScanInputMethod?) -> String {
        switch self {
        case .idle:
            return "Bereit"
        case .preparingImage:
            return "Bild wird vorbereitet"
        case .ocrPreflight:
            return "Text aus dem Bild lesen"
        case .aiConnecting:
            return "Verbinde mit KI"
        case .aiPrimary:
            switch inputMethod {
            case .camera:
                return "KI analysiert dein Foto"
            case .library, .none:
                return "KI analysiert dein Bild"
            }
        case .aiReceiving:
            return "Antwort wird empfangen"
        case .parsingResults:
            return "Vokabelpaare werden erkannt"
        case .ocrFallback:
            return "Genauer OCR-Durchgang"
        case .finalizing:
            return "Letzte Feinarbeit"
        }
    }

    /// Optionale Sub-Zeile — kurze, menschliche Erklärung, **was** die
    /// App gerade macht und warum. Wird unter dem Titel in kleinerer
    /// Schrift gerendert; `nil` bedeutet: keine Subzeile nötig (z. B.
    /// `.idle`).
    var displaySubtitle: String? {
        switch self {
        case .idle:
            return nil
        case .preparingImage:
            return "Größe, Drehung und Zuschnitt anpassen"
        case .ocrPreflight:
            return "Vision scannt die Zeilen lokal auf deinem Gerät"
        case .aiConnecting:
            return "Bild wird zur KI geschickt"
        case .aiPrimary:
            return "Die KI erkennt Sprache und Vokabelpaare"
        case .aiReceiving:
            return "Daten kommen zurück von der KI"
        case .parsingResults:
            return "Wörter und Übersetzungen werden zusammengeführt"
        case .ocrFallback:
            return "Fallback-Pass für bessere Zeichenerkennung"
        case .finalizing:
            return "Vorschau wird aufgebaut"
        }
    }

    /// SF-Symbol-Name für das Stage-Icon (Overlay + Status-Zeile).
    var systemImage: String {
        switch self {
        case .idle, .preparingImage:
            return "photo.on.rectangle.angled"
        case .ocrPreflight:
            return "doc.text.viewfinder"
        case .aiConnecting:
            return "antenna.radiowaves.left.and.right"
        case .aiPrimary:
            return "sparkles"
        case .aiReceiving:
            return "arrow.down.circle"
        case .parsingResults:
            return "list.bullet.rectangle.fill"
        case .ocrFallback:
            return "arrow.triangle.2.circlepath"
        case .finalizing:
            return "checkmark.seal.fill"
        }
    }

    /// Farbe des Stage-Icons + des Titels. Greift auf `AppTheme.Colors`
    /// zurück — damit Dark/Light-Switch + Theme-Changes automatisch
    /// mitziehen. Nicht-KI-Stages bleiben in Secondary, KI-Stages
    /// bekommen den Primary-Akzent (Signal „externer Service aktiv").
    var tintColor: Color {
        switch self {
        case .idle:
            return AppTheme.Colors.textSecondary
        case .preparingImage:
            return AppTheme.Colors.textSecondary
        case .ocrPreflight:
            return AppTheme.Colors.textSecondary
        case .aiConnecting:
            return AppTheme.Colors.warning
        case .aiPrimary, .aiReceiving:
            return AppTheme.Colors.primary
        case .parsingResults:
            return AppTheme.Colors.success
        case .ocrFallback:
            return AppTheme.Colors.warning
        case .finalizing:
            return AppTheme.Colors.success
        }
    }
}
