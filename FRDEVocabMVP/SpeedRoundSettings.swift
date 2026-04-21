import Foundation
import SwiftUI

/// Erlaubte Dauern für den Speed-Round-Timer in Sekunden. Feste Enum-Cases
/// (statt eines freien Int-Werts) halten die Auswahl verständlich und
/// konsistent — UI, Persistenz und Default-Logik arbeiten alle auf
/// demselben Typ.
///
/// Neue Werte können jederzeit ergänzt werden (z. B. `.seconds90` für
/// ein späteres „Zen"-Profil); die einzige Stelle, die dafür angepasst
/// werden muss, ist diese Datei und der Picker im `SettingsView`.
enum SpeedRoundDuration: Int, CaseIterable, Codable, Hashable {
    case seconds20 = 20
    case seconds30 = 30
    case seconds45 = 45
    case seconds60 = 60

    /// App-weiter Default — bislang war 45s der Hardcoded-Standard
    /// überall (siehe Git-Blame zu `speedRoundTimeRemaining = 45`).
    /// Bestandsnutzer:innen bleiben damit bei unverändertem Verhalten,
    /// solange sie die neue Einstellung nicht anfassen.
    static let defaultDuration: SpeedRoundDuration = .seconds45

    /// Anzahl Sekunden als Int — für Timer-Logik und LearningSession-
    /// Headline. Spiegelt den Enum-Rohwert.
    var seconds: Int { rawValue }

    /// UI-Label — einheitliche Schreibweise appweit. Wir nutzen überall
    /// „N Sekunden" und nicht „N s" / „0:NN", damit die Darstellung
    /// konsistent bleibt (siehe Setup-Card, Info-View, Summary).
    var label: String { "\(rawValue) Sekunden" }

    /// Kurzlabel für kompakte Anzeigen (Timer-Overlay etc.) — „30s".
    var compactLabel: String { "\(rawValue)s" }
}

/// Zentraler Resolver: liefert die aktuell aktive Speed-Round-Dauer.
/// Alle Module (Training, Verbformen, Akzente, zukünftige) lesen
/// ausschließlich über diesen Weg — so existiert genau **ein**
/// Wahrheitszustand, und ein Settings-Change wirkt sofort überall.
///
/// Der Typ ist bewusst ein simpler Namespace ohne gespeicherten State
/// (kein ObservableObject) — die Persistenz läuft über `@AppStorage`
/// auf dem gemeinsamen Key (`appSpeedRoundDurationKey`). SwiftUI-
/// Reader binden sich direkt via `@AppStorage(appSpeedRoundDurationKey)`,
/// Controller-Logik greift über die statischen Helfer hier.
enum SpeedRoundSettings {
    /// Aktuell konfigurierte Dauer — aus UserDefaults, mit Fallback auf
    /// `SpeedRoundDuration.defaultDuration`. Ungültige persistierte Werte
    /// (z. B. aus einer zukünftigen Version mit mehr Optionen) werden auf
    /// den Default gekippt, statt die App crashen zu lassen.
    static var currentDuration: SpeedRoundDuration {
        let raw = UserDefaults.standard.integer(forKey: appSpeedRoundDurationKey)
        if raw <= 0 { return SpeedRoundDuration.defaultDuration }
        return SpeedRoundDuration(rawValue: raw) ?? SpeedRoundDuration.defaultDuration
    }

    /// Shortcut für Timer-Initialisierungen — `speedRoundTimeRemaining =
    /// SpeedRoundSettings.currentSeconds`.
    static var currentSeconds: Int { currentDuration.seconds }

    /// Shortcut für UI-Texte — „45 Sekunden", folgt der App-weiten
    /// Schreibweise.
    static var currentLabel: String { currentDuration.label }
}

/// Zentraler Terminologie-Namespace für die „Kurz-Session". Aktuell
/// appweit „Speed Round". Falls später auf „Challenge" (oder einen
/// anderen Begriff) umgestellt wird, ist nur diese Datei zu ändern —
/// alle Views und Texte lesen darüber.
enum SpeedRoundTerminology {
    /// Titel-Label in Setup-Cards und Headern.
    static var name: String { "Speed Round" }

    /// Untertitel-Vorschlag für die Modus-Card — Module dürfen einen
    /// eigenen Subtitle setzen, sollten aber denselben **Stil** nutzen
    /// (kurze, ruhige Umschreibung).
    static func subtitle(forSeconds seconds: Int) -> String {
        "\(seconds) Sekunden Tempo"
    }
}

// MARK: - @AppStorage Key

/// Persistenz-Key für die globale Speed-Round-Dauer. Ein **einziger**
/// Key appweit — keine modulspezifischen Overrides. Value ist der
/// Roh-Int aus `SpeedRoundDuration.rawValue`.
let appSpeedRoundDurationKey = "elumi.speedround.duration.seconds.v1"
