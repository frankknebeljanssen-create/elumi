import SwiftUI
import Foundation

// MARK: - Power-Up-Typ-Enum
//
// Einheitliches System für alle Arcade-Power-Ups. Vorher waren Sauger,
// Bonus-Blase und Slow-Motion-Trank als drei separate `@State Date?`-
// Variablen plus Helper-Funktionen hart in `ElumiArcadeGameView`
// verdrahtet. Das Schutz-Bubble-Power-Up ist die Gelegenheit, das
// auf ein zentrales Typ-/Konfig-Modell umzubauen, das für künftige
// Power-Ups (Slow-Motion, Bonus-Punkte, Extra-Leben) offen ist.
//
// Ein aktiver Power-Up-Status lebt weiterhin in `@State`-Variablen
// der `ElumiArcadeGameView` (`suctionEndsAt`, `bonusPointsEndsAt` etc.) —
// diese Datei definiert primär **Farben**, **Dauern**, **Spawn-
// Kontrolle** und das **Drop-Kind-Mapping**. Ziel ist Polish und
// Wiederverwendbarkeit, nicht ein kompletter Rewrite des bestehenden
// Active-State-Handlings.

enum ArcadePowerUpType: String, CaseIterable, Identifiable {
    case shieldBubble
    case vacuum
    case slowMotion
    case bonusPoints
    case extraLife

    var id: String { rawValue }
}

// MARK: - Visuelle & Gameplay-Konfiguration

/// Zentrale Konfiguration pro Power-Up-Typ. `color`-Werte kommen aus
/// der User-Spec (funktionale Farblogik: Farbe kommuniziert Wirkung).
struct ArcadePowerUpConfig {

    /// Primärfarbe (Fill, Core).
    let primaryColor: Color
    /// Sekundärfarbe (heller Fill-Layer, Glanzpunkte).
    let secondaryColor: Color
    /// Akzentfarbe (Kontur, Mid-Layer-Details).
    let accentColor: Color

    /// Dauer des Aktiv-Zustands in Sekunden. Nil für Typen, die sofort
    /// wirken (z. B. extra life = Leben +1, ohne Aktiv-Phase).
    let activeDuration: TimeInterval?

    /// Wie oft im Verhältnis zu anderen Power-Ups gespawnt werden soll
    /// (pro Spawn-Roll). Wird im zentralen Spawn-Gate berücksichtigt.
    let spawnWeight: Double

    /// Mindest-Intervall zwischen zwei Spawns desselben Typs
    /// (Sekunden). Verhindert Spam.
    let minIntervalSameType: TimeInterval

    /// Lesbares Label für Debug/Logs.
    let debugLabel: String
}

// MARK: - Farb-Registry

/// Globale Farb- und Konfig-Tabelle. Single-Source-of-Truth für alle
/// Power-Up-Typen. Wenn ein neuer Typ dazukommt: hier eintragen und
/// fertig — UI, Spawn-Logik und Gameplay ziehen aus dem gleichen
/// Eintrag.
enum ArcadePowerUps {

    /// Farbpaletten aus der User-Spec — funktional-semantisch zugewiesen.
    static let configs: [ArcadePowerUpType: ArcadePowerUpConfig] = [
        .shieldBubble: ArcadePowerUpConfig(
            primaryColor:   Color(hex: "#8FD3FF"),
            secondaryColor: Color(hex: "#D9F4FF"),
            accentColor:    Color(hex: "#BDEBFF"),
            activeDuration: 4.6,            // Dauer ≈ Sauger — „Hilfsmoment"-Parität
            spawnWeight:    0.12,           // Selten — 10–15 %
            minIntervalSameType: 11.0,      // 10–15 s Fenster
            debugLabel: "shieldBubble"
        ),
        .vacuum: ArcadePowerUpConfig(
            primaryColor:   Color(hex: "#A78BFA"),
            secondaryColor: Color(hex: "#E9D5FF"),
            accentColor:    Color(hex: "#C4B5FD"),
            activeDuration: 4.6,
            spawnWeight:    0.17,           // 15–20 %
            minIntervalSameType: 9.0,       // 8–12 s Fenster
            debugLabel: "vacuum"
        ),
        .slowMotion: ArcadePowerUpConfig(
            primaryColor:   Color(hex: "#60A5FA"),
            secondaryColor: Color(hex: "#DBEAFE"),
            accentColor:    Color(hex: "#93C5FD"),
            activeDuration: 5.0,
            spawnWeight:    0.07,           // 5–10 %
            minIntervalSameType: 14.0,
            debugLabel: "slowMotion"
        ),
        .bonusPoints: ArcadePowerUpConfig(
            primaryColor:   Color(hex: "#FBBF24"),
            secondaryColor: Color(hex: "#FEF3C7"),
            accentColor:    Color(hex: "#FCD34D"),
            activeDuration: 5.0,
            spawnWeight:    0.12,           // 10–15 %
            minIntervalSameType: 11.0,
            debugLabel: "bonusPoints"
        ),
        .extraLife: ArcadePowerUpConfig(
            primaryColor:   Color(hex: "#34D399"),
            secondaryColor: Color(hex: "#D1FAE5"),
            accentColor:    Color(hex: "#6EE7B7"),
            activeDuration: nil,            // Instant-Effekt (+1 Leben)
            spawnWeight:    0.05,
            minIntervalSameType: 22.0,
            debugLabel: "extraLife"
        )
    ]

    static func config(for type: ArcadePowerUpType) -> ArcadePowerUpConfig {
        configs[type] ?? configs[.vacuum]!
    }

    // MARK: - Drop-Kind-Mapping (Brücke zur bestehenden Gameplay-Logik)

    /// Mapping von `ElumiArcadeDropKind` auf den Power-Up-Typ. Gibt nil
    /// zurück für nicht-PowerUp-Drops (Snacks, false-Elumi). Lässt die
    /// bestehende DropKind-Enum unverändert — diese Datei ergänzt nur.
    static func type(for kind: ElumiArcadeDropKind) -> ArcadePowerUpType? {
        switch kind {
        case .saugglocke:       return .vacuum
        case .slowMotionPotion: return .slowMotion
        case .bonusblase:       return .bonusPoints
        case .shieldBubble:     return .shieldBubble
        case .wuermchen, .wasserfloh, .algenkugel, .falseElumi:
            return nil
        }
    }

    /// Rückwärts: zu einem Power-Up-Typ den zugehörigen Drop-Kind.
    /// Nur Typen, die aktuell als Drop implementiert sind.
    static func dropKind(for type: ArcadePowerUpType) -> ElumiArcadeDropKind? {
        switch type {
        case .vacuum:       return .saugglocke
        case .slowMotion:   return .slowMotionPotion
        case .bonusPoints:  return .bonusblase
        case .shieldBubble: return .shieldBubble
        case .extraLife:    return nil        // noch nicht implementiert
        }
    }
}

// MARK: - Spawn-Gate (Dichte-Kontrolle)

/// **Globale Spawn-Kontrolle** — verhindert Power-Up-Spam.
///
/// Regel (aus User-Spec):
///   • maximal ein Power-Up pro 6–10 Sekunden
///   • Cooldown 5–8 s nach jedem Spawn
///   • nie mehr als ein Power-Up gleichzeitig auf dem Screen
///   • nie direkt beim Spieler spawnen
///
/// Die Gate-Logik wird vor dem probabilistischen Spawn-Roll in
/// `spawnSnack()` konsultiert. Wenn das Gate `false` sagt, fällt der
/// Spawn auf Regular-Snacks zurück — genau wie vorher, nur ohne das
/// Power-Up.
///
/// Die Gate-State (letzter Spawn-Zeitpunkt + pro-Typ-History) lebt
/// als `@State` in der View — dieser Typ selbst ist nur ein Wert-
/// Container mit Entscheidungslogik.
struct ArcadePowerUpSpawnGate {
    /// Letzter Spawn **irgendeines** Power-Ups — global.
    var lastAnySpawn: Date? = nil
    /// Letzter Spawn pro Typ — für pro-Typ-Mindestabstand.
    var lastSpawnByType: [ArcadePowerUpType: Date] = [:]

    /// Zentrale Cooldown-Schwelle — minimaler Abstand zwischen zwei
    /// **beliebigen** Power-Up-Spawns. Setzt den Grundrhythmus.
    static let globalCooldown: TimeInterval = 6.0

    /// Darf gerade generell ein Power-Up gespawnt werden? Prüft globalen
    /// Cooldown + Anzahl aktuell auf Screen.
    func mayConsiderPowerUp(now: Date, powerUpsOnScreen: Int) -> Bool {
        if powerUpsOnScreen > 0 { return false }
        if let last = lastAnySpawn {
            return now.timeIntervalSince(last) >= Self.globalCooldown
        }
        return true
    }

    /// Pro-Typ-Check: ist der Mindestabstand zum letzten Spawn dieses
    /// Typs eingehalten?
    func mayConsider(type: ArcadePowerUpType, now: Date) -> Bool {
        guard let last = lastSpawnByType[type] else { return true }
        return now.timeIntervalSince(last) >= ArcadePowerUps.config(for: type).minIntervalSameType
    }

    /// Bei erfolgreichem Spawn aufrufen — aktualisiert beide Timer.
    mutating func registerSpawn(type: ArcadePowerUpType, at date: Date) {
        lastAnySpawn = date
        lastSpawnByType[type] = date
    }

    /// Beim Runden-Reset / Game-Over komplett leeren, damit der nächste
    /// Run frisch startet.
    mutating func reset() {
        lastAnySpawn = nil
        lastSpawnByType.removeAll()
    }
}
