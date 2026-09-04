import Foundation
import SwiftUI

/// App-weiter Settings-Namespace für den Scan-Stack.
///
/// Ziel: ein einziger Ort, an dem Toggles/Defaults für Scan-Verhalten
/// definiert sind. Parallele Struktur zu `SpeedRoundSettings` — die
/// Persistenz läuft über `@AppStorage`, Controller-Logik liest über die
/// statischen Helfer hier, SettingsView bindet direkt via `@AppStorage`.
enum ScanSettings {

    // MARK: - Smart-Region-Crop (FreeText-Power-User)

    /// Aktueller Wert des Smart-Region-Crop-Toggles — direkt aus
    /// UserDefaults. Liest `false`, wenn der Key noch nie gesetzt wurde
    /// (Erstinstall oder Bestandsnutzer vor Slice-11).
    ///
    /// Semantik: wenn aktiv UND Profil `.freeText`, läuft
    /// `SmartTextRegionDetector` als zusätzlicher Post-Capture-Schritt
    /// auf dem korrigierten Bild. Bei erfolgreicher Erkennung wird das
    /// Ergebnis **zusätzlich** durch den Text-Region-Crop ersetzt —
    /// sonst bleibt das Bild unverändert.
    ///
    /// Default aus: die meisten User wollen das gesamte Foto behalten
    /// (weniger Überraschung, besser für die KI-Analyse bei zentriertem
    /// Text). Power-User, die tight gecroppte Text-Ausschnitte bevorzugen
    /// (z. B. für OCR-Weiterverarbeitung), schalten den Toggle in den
    /// Einstellungen ein.
    static var smartRegionCropEnabled: Bool {
        UserDefaults.standard.bool(forKey: appScanSmartRegionCropKey)
    }
}

// MARK: - @AppStorage Keys

/// Persistenz-Key für das Smart-Region-Crop-Opt-in. Bool — default
/// `false` (siehe `ScanSettings.smartRegionCropEnabled`).
let appScanSmartRegionCropKey = "elumi.scan.smartRegionCrop.enabled.v1"
