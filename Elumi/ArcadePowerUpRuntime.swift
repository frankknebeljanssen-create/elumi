import Foundation
import SwiftUI
import Combine

// MARK: - Lifecycle-State-Machine

/// **Formale State-Machine** pro Power-Up. Löst die vorher losen
/// Booleans (`isActive`, `isVisible`, `isCollected`) durch **einen**
/// klar definierten Zustand ab. Ein Power-Up ist zu jedem Zeitpunkt
/// in **genau einem** dieser Zustände.
///
/// Legale Transitionen:
/// ```
///   spawning ──────▶ idle
///       idle ──────▶ pickedUp        (User sammelt das Drop ein)
///       idle ──────▶ consumed        (Drop verschwunden ohne Pickup)
///   pickedUp ──────▶ active
///     active ──────▶ ending          (Timer abgelaufen)
///     ending ──────▶ consumed        (End-Animation fertig)
///  consumed ── terminal
/// ```
///
/// Wichtig:
///   • Während `active` greifen Gameplay-Effekte (z. B. Schutz-Logik)
///   • Im `ending` läuft nur noch die Ausblend-Animation — keine
///     neuen Effekte werden ausgelöst
///   • `consumed` ist der Endzustand — Instanz wird aus der Runtime
///     entfernt, nichts läuft mehr
enum PowerUpLifecycleState: String, Equatable {
    case spawning
    case idle
    case pickedUp
    case active
    case ending
    case consumed
}

// MARK: - Power-Up-Instanz

/// Laufzeit-Repräsentation eines Power-Ups, das gerade in irgendeiner
/// Form im System lebt (sei es als Drop auf dem Screen, im Pickup-
/// Übergang oder als aktiver Effekt um den Spieler).
///
/// Identifiziert via `type + instanceID` — so kann mehrfach dasselbe
/// Power-Up in der Runtime getrackt werden (z. B. theoretisch eine
/// Shield-Bubble aktiv + eine zweite im Drop), auch wenn das aktuelle
/// Spawn-Gate das verhindert.
struct ArcadePowerUpInstance: Identifiable, Equatable {
    let id: UUID
    let type: ArcadePowerUpType
    var state: PowerUpLifecycleState
    let spawnedAt: Date
    /// End-Zeitpunkt des `.active`-Zustands. Wird bei `activate(...)`
    /// gesetzt. Im `.active`-Zustand prüft die Runtime jeden Tick,
    /// ob `activeEndsAt < now` → dann Transition zu `.ending`.
    var activeEndsAt: Date?
    /// End-Zeitpunkt des `.ending`-Zustands (letzte Animations-ms).
    /// Wenn überschritten → Transition zu `.consumed`.
    var endingEndsAt: Date?
}

// MARK: - Ambient-Event-Typ

/// Rein visuelle Events, bewusst **getrennt** von Power-Ups verwaltet.
/// Haben eigene Spawn-Regeln (pro Runde max. 1), keine Kollisions-
/// Relevanz, keine Effekt-Logik auf den Spieler.
enum ArcadeAmbientEventType: String, Equatable {
    case fish
    case shark
}

// MARK: - Kollisions-Priorität

/// **Kollisions-Reihenfolge** pro Frame. Die Game-Loop-Update-Logik
/// evaluiert Kollisionen streng in dieser Reihenfolge. Der erste
/// Match entscheidet — kein Event wird mehrfach verarbeitet.
///
/// Prioritäten (niedrig = höher gepriorisiert):
///   1. `runTerminated` → Session/Game-Over: keine Kollision mehr
///   2. `shieldBubble`  → aktiver Schild blockt Schaden, leitet
///                        Abprall-Impuls aus
///   3. `powerUpPickup` → Power-Up-Drops werden eingesammelt
///   4. `snackCollect`  → normale Snacks + Punkte
///   5. `ambient`       → Fisch/Hai etc. — ignorieren
enum ArcadeCollisionPriority: Int, Comparable {
    case runTerminated = 1
    case shieldBubble  = 2
    case powerUpPickup = 3
    case snackCollect  = 4
    case ambient       = 5

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Arcade-Power-Up-Runtime

/// **Zentrale Power-Up-Verwaltung** — Single Source of Truth für:
///   • alle aktiven/sichtbaren Power-Ups mit ihrem Lifecycle-State
///   • Spawn-Cooldowns (global + per-Typ)
///   • Ambient-Event-Lock pro Runde
///   • Restdauern (computed aus Timestamps)
///   • Debug-Hooks für schnelles Testen
///
/// **Thread-Modell**: `@MainActor` — alle Mutationen kommen von der
/// Game-Loop auf MainActor (weil UI-State getrieben). Kein Cross-
/// Thread-Zugriff nötig.
///
/// **Update-Pfad**: Ein einziger `tick(at:)`-Call pro Frame schreibt
/// ALLE Zustandsübergänge fort. Keine parallelen DispatchQueue-
/// asyncAfter-Ketten. Das verhindert doppelte Updates und hängen-
/// bleibende Effekte.
///
/// **Migrations-Hinweis**: Aktuell ist **Shield-Bubble** voll durch
/// die Runtime verwaltet. Sauger, Bonus-Points, Slow-Motion nutzen
/// noch ihre Legacy-Timestamp-Variablen (`suctionEndsAt` etc.) —
/// funktional korrekt, werden in einem Folge-Slice migriert. Die
/// Runtime verträgt den Mischbetrieb problemlos.
@MainActor
final class ArcadePowerUpRuntime: ObservableObject {

    // MARK: - State

    /// Alle gerade aktiven Instanzen (spawning → … → ending).
    /// `.consumed`-Instanzen werden sofort aus dem Array entfernt.
    @Published private(set) var instances: [ArcadePowerUpInstance] = []

    /// Globaler Spawn-Cooldown — nach dem letzten Power-Up-Spawn
    /// mindestens `globalCooldown` Sekunden warten, bevor ein neuer
    /// Power-Up erscheinen darf. Schutz gegen Spam.
    @Published private(set) var lastAnyPowerUpSpawnAt: Date?

    /// Per-Typ-Cooldown — zusätzlich zum globalen Cooldown hat jeder
    /// Typ sein eigenes Mindest-Intervall (siehe
    /// `ArcadePowerUps.config(for:).minIntervalSameType`).
    @Published private(set) var lastSpawnByType: [ArcadePowerUpType: Date] = [:]

    /// Ambient-Event-Lock: sobald ein Fisch/Hai in der Runde gelaufen
    /// ist, bleibt das Lock bis zum nächsten Runden-Reset aktiv.
    @Published private(set) var ambientEventFiredThisRound: Bool = false

    /// Aktiv laufendes Ambient-Event (Fisch/Hai). Nil, wenn keines
    /// aktiv. Max. 1 gleichzeitig (pro Runde nur eins).
    @Published private(set) var activeAmbientEvent: (type: ArcadeAmbientEventType, endsAt: Date)?

    // MARK: - Konfiguration

    /// Mindest-Abstand zwischen zwei beliebigen Power-Up-Spawns.
    /// Matcht den Wert aus dem bisherigen `ArcadePowerUpSpawnGate`.
    static let globalPowerUpCooldown: TimeInterval = 6.0

    /// Dauer der End-Animation (visuelles Ausblenden) nach Active-Ende.
    /// Während dieser Phase gelten keine Effekte mehr, nur Fade/Scale.
    static let endingAnimationDuration: TimeInterval = 0.4

    // MARK: - Spawn-Gates

    /// Darf **irgendein** Power-Up gerade neu gespawnt werden?
    /// Prüft:
    ///   • globaler Cooldown eingehalten
    ///   • kein anderes Power-Up gerade als Drop sichtbar
    ///     (`.spawning`/`.idle`)
    ///   • kein Power-Up gerade `.active` oder `.ending`
    ///
    /// Das ist die „only one at a time"-Regel aus der User-Spec.
    func mayConsiderSpawn(now: Date) -> Bool {
        if let last = lastAnyPowerUpSpawnAt,
           now.timeIntervalSince(last) < Self.globalPowerUpCooldown {
            return false
        }
        let dropOrActive = instances.contains { inst in
            [.spawning, .idle, .pickedUp, .active, .ending].contains(inst.state)
        }
        return !dropOrActive
    }

    /// Darf der **spezifische Typ** gespawnt werden? Prüft den pro-
    /// Typ-Mindestabstand aus `ArcadePowerUps.config`.
    func mayConsiderSpawn(type: ArcadePowerUpType, now: Date) -> Bool {
        guard mayConsiderSpawn(now: now) else { return false }
        if let lastSame = lastSpawnByType[type] {
            let interval = ArcadePowerUps.config(for: type).minIntervalSameType
            return now.timeIntervalSince(lastSame) >= interval
        }
        return true
    }

    // MARK: - Lifecycle-Transitionen

    /// Registriert einen **neuen Drop**. Zustand beginnt bei `.spawning`.
    /// Caller ist typischerweise die Spawn-Logik in `spawnSnack()`.
    @discardableResult
    func registerSpawn(type: ArcadePowerUpType, at date: Date) -> UUID {
        let instance = ArcadePowerUpInstance(
            id: UUID(),
            type: type,
            state: .spawning,
            spawnedAt: date,
            activeEndsAt: nil,
            endingEndsAt: nil
        )
        instances.append(instance)
        lastAnyPowerUpSpawnAt = date
        lastSpawnByType[type] = date
        #if DEBUG
        appDebugLog("🎁 [Runtime] spawn \(type.rawValue) (id=\(instance.id.uuidString.prefix(8))) state=spawning")
        #endif
        return instance.id
    }

    /// Übergang `.spawning` → `.idle` — Drop ist vollständig aufgepoppt
    /// und jetzt regulär catchable.
    func markIdle(id: UUID) {
        updateState(id: id, from: [.spawning], to: .idle)
    }

    /// Übergang `.idle` → `.pickedUp` — User hat das Drop eingesammelt,
    /// Pickup-Animation läuft (Snap zum Spieler).
    func markPickedUp(id: UUID) {
        updateState(id: id, from: [.idle, .spawning], to: .pickedUp)
    }

    /// Übergang `.pickedUp` → `.active` mit Active-Dauer. Die Dauer
    /// kommt aus `ArcadePowerUps.config(for:).activeDuration` falls
    /// nicht explizit überschrieben.
    func markActive(id: UUID, at date: Date, durationOverride: TimeInterval? = nil) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        let type = instances[index].type
        let duration = durationOverride
            ?? ArcadePowerUps.config(for: type).activeDuration
            ?? 0
        guard duration > 0 else {
            // Instant-Effekte (z. B. extra life) direkt consumen.
            updateState(id: id, from: [.pickedUp, .idle], to: .consumed)
            return
        }
        instances[index].state = .active
        instances[index].activeEndsAt = date.addingTimeInterval(duration)
        #if DEBUG
        appDebugLog("🎁 [Runtime] \(type.rawValue) → active (ends \(duration)s)")
        #endif
    }

    /// Forciere `.consumed` — bei Runden-/Session-Ende oder via Debug.
    func markConsumed(id: UUID) {
        updateState(id: id, from: nil, to: .consumed)
        instances.removeAll { $0.id == id }
    }

    // MARK: - Convenience: Find-by-Type-Transitionen
    //
    // Callsites arbeiten typischerweise mit dem Power-Up-Typ, nicht
    // mit einer konkreten Instance-ID. Weil nur **ein** Power-Up eines
    // Typs gleichzeitig existiert (Spawn-Gate), ist es sicher, die
    // erste passende Instanz zu finden und den State-Übergang dort
    // auszulösen.

    /// Findet das aktuell „droppable" Power-Up des Typs und markiert
    /// es als eingesammelt (`pickedUp`). Optional: direkt weiter in
    /// `active` transitionieren.
    @discardableResult
    func pickUp(type: ArcadePowerUpType, at date: Date, andActivate: Bool = false, durationOverride: TimeInterval? = nil) -> UUID? {
        guard let inst = instances.first(where: {
            $0.type == type && ($0.state == .idle || $0.state == .spawning)
        }) else { return nil }
        markPickedUp(id: inst.id)
        if andActivate {
            markActive(id: inst.id, at: date, durationOverride: durationOverride)
        }
        return inst.id
    }

    /// Findet die Instanz eines Typs, die gerade `.pickedUp` oder
    /// `.idle` ist, und aktiviert sie. Legt sie im Notfall neu an
    /// (für Callsites, die ohne vorangegangenen Drop aktivieren
    /// wollen — z. B. Debug oder instant-grants).
    func activateOrCreate(
        type: ArcadePowerUpType,
        at date: Date,
        durationOverride: TimeInterval? = nil
    ) {
        if let inst = instances.first(where: {
            $0.type == type && [.pickedUp, .idle, .spawning].contains($0.state)
        }) {
            markActive(id: inst.id, at: date, durationOverride: durationOverride)
        } else {
            // Kein Drop vorhanden → virtueller Spawn direkt in `.active`.
            let instance = ArcadePowerUpInstance(
                id: UUID(),
                type: type,
                state: .active,
                spawnedAt: date,
                activeEndsAt: date.addingTimeInterval(
                    durationOverride
                        ?? ArcadePowerUps.config(for: type).activeDuration
                        ?? 0
                ),
                endingEndsAt: nil
            )
            instances.append(instance)
            lastAnyPowerUpSpawnAt = date
            lastSpawnByType[type] = date
        }
    }

    /// Beendet alle laufenden Effekte + Drops + Ambient — Cleanup-Pfad
    /// für Game-Over, Session-Ende, Arcade-Exit.
    func hardReset() {
        instances.removeAll()
        lastAnyPowerUpSpawnAt = nil
        lastSpawnByType.removeAll()
        ambientEventFiredThisRound = false
        activeAmbientEvent = nil
    }

    /// Reset nur für Runden-Wechsel: Ambient-Event-Lock wird frei,
    /// aber Power-Up-Cooldowns bleiben (Power-Ups sind rundenübergreifend).
    func resetForNewRound() {
        ambientEventFiredThisRound = false
        activeAmbientEvent = nil
    }

    // MARK: - Pro-Frame-Tick (ein einziger Update-Pfad)

    /// **Zentraler Frame-Tick** — prüft alle Instanzen auf State-
    /// Übergänge, entfernt `.consumed`-Einträge, verwaltet Ambient-
    /// Event-Ende.
    ///
    /// Muss einmal pro Frame aufgerufen werden (z. B. am Ende von
    /// `updateGame(now:)`).
    func tick(at date: Date) {
        var mutated = false

        // Active → Ending, Ending → Consumed.
        for index in instances.indices.reversed() {
            var instance = instances[index]
            switch instance.state {
            case .active:
                if let endsAt = instance.activeEndsAt, endsAt <= date {
                    instance.state = .ending
                    instance.endingEndsAt = date.addingTimeInterval(Self.endingAnimationDuration)
                    instances[index] = instance
                    mutated = true
                    #if DEBUG
                    appDebugLog("🎁 [Runtime] \(instance.type.rawValue) → ending")
                    #endif
                }
            case .ending:
                if let endsAt = instance.endingEndsAt, endsAt <= date {
                    instance.state = .consumed
                    instances[index] = instance
                    mutated = true
                    #if DEBUG
                    appDebugLog("🎁 [Runtime] \(instance.type.rawValue) → consumed (removed)")
                    #endif
                }
            case .spawning, .idle, .pickedUp, .consumed:
                break
            }
        }

        // Consumed Einträge entfernen
        instances.removeAll { $0.state == .consumed }

        // Ambient-Event ablaufen lassen
        if let event = activeAmbientEvent, event.endsAt <= date {
            activeAmbientEvent = nil
            mutated = true
            #if DEBUG
            appDebugLog("🐟 [Runtime] ambient event \(event.type.rawValue) ended")
            #endif
        }

        _ = mutated
    }

    // MARK: - Queries

    /// True, wenn ein aktiver Shield-Bubble-Effekt existiert. Wird von
    /// der Kollisions-Priorisierung (`ArcadeCollisionPriority.shieldBubble`)
    /// abgefragt.
    func hasActiveShield(at date: Date) -> Bool {
        instances.contains { inst in
            inst.type == .shieldBubble && inst.state == .active
        }
    }

    /// Liefert die Restdauer des aktiven Shields (für Debug/UI).
    func shieldRemainingSeconds(at date: Date) -> TimeInterval {
        guard let shield = instances.first(where: {
            $0.type == .shieldBubble && $0.state == .active
        }), let endsAt = shield.activeEndsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(date))
    }

    /// Liefert die aktive Shield-Instanz (falls vorhanden). Wird vom
    /// Renderer genutzt, um Ending-Fade-Progress zu berechnen.
    func activeShieldInstance() -> ArcadePowerUpInstance? {
        instances.first { $0.type == .shieldBubble && [.active, .ending].contains($0.state) }
    }

    // MARK: - Ambient-Events

    /// Darf gerade ein Ambient-Event spawnen? Pro Runde genau einmal.
    func mayTriggerAmbientEvent() -> Bool {
        !ambientEventFiredThisRound && activeAmbientEvent == nil
    }

    /// Registriert ein neues Ambient-Event.
    func registerAmbientEvent(type: ArcadeAmbientEventType, durationSeconds: TimeInterval, at date: Date) {
        guard mayTriggerAmbientEvent() else { return }
        ambientEventFiredThisRound = true
        activeAmbientEvent = (type, date.addingTimeInterval(durationSeconds))
        #if DEBUG
        appDebugLog("🐟 [Runtime] ambient event \(type.rawValue) started (\(durationSeconds)s)")
        #endif
    }

    // MARK: - Debug-Hooks

    /// **Debug**: zwingt ein Power-Up sofort in den Drop-Zustand,
    /// unabhängig von Cooldowns. Für DEV-Tests in den Settings.
    func debugForceSpawn(type: ArcadePowerUpType, at date: Date) -> UUID {
        let id = UUID()
        let instance = ArcadePowerUpInstance(
            id: id,
            type: type,
            state: .spawning,
            spawnedAt: date,
            activeEndsAt: nil,
            endingEndsAt: nil
        )
        instances.append(instance)
        lastAnyPowerUpSpawnAt = date
        lastSpawnByType[type] = date
        #if DEBUG
        appDebugLog("🛠 [Runtime Debug] force-spawn \(type.rawValue)")
        #endif
        return id
    }

    /// **Debug**: zwingt alle aktiven Power-Ups sofort in `.consumed`.
    func debugEndAllActive() {
        let beforeCount = instances.count
        instances.removeAll()
        #if DEBUG
        appDebugLog("🛠 [Runtime Debug] ended \(beforeCount) active instance(s)")
        #endif
    }

    /// **Debug**: zwingt ein Ambient-Event unabhängig vom Round-Lock.
    /// Ignoriert den normalen `mayTriggerAmbientEvent()`-Guard.
    func debugForceAmbientEvent(type: ArcadeAmbientEventType, durationSeconds: TimeInterval, at date: Date) {
        activeAmbientEvent = (type, date.addingTimeInterval(durationSeconds))
        ambientEventFiredThisRound = true
        #if DEBUG
        appDebugLog("🛠 [Runtime Debug] force ambient event \(type.rawValue)")
        #endif
    }

    /// **Debug**: lesbarer Zustand aller Instanzen — für DEV-Card
    /// oder Konsolen-Dump.
    func debugStateSummary(at date: Date) -> String {
        let lines = instances.map { inst -> String in
            var base = "\(inst.type.rawValue) state=\(inst.state.rawValue)"
            if inst.state == .active, let endsAt = inst.activeEndsAt {
                let remaining = max(0, endsAt.timeIntervalSince(date))
                base += " remaining=\(String(format: "%.1f", remaining))s"
            }
            return "  " + base
        }
        let header = "Arcade-Runtime (\(instances.count) active)"
        return ([header] + lines).joined(separator: "\n")
    }

    // MARK: - Internal

    /// Validierte Transition mit optionaler „erlaubte Vorzustände"-
    /// Liste. `nil` für `allowedFrom` = Transition aus jedem Zustand
    /// möglich (für terminal-Reset). Illegale Transitionen werden
    /// im Debug geloggt und verworfen.
    private func updateState(
        id: UUID,
        from allowedFrom: Set<PowerUpLifecycleState>?,
        to newState: PowerUpLifecycleState
    ) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        let old = instances[index].state
        if let allowed = allowedFrom, !allowed.contains(old) {
            #if DEBUG
            appDebugLog("❌ [Runtime] illegal transition \(instances[index].type.rawValue): \(old.rawValue) → \(newState.rawValue)")
            #endif
            return
        }
        instances[index].state = newState
        #if DEBUG
        appDebugLog("🎁 [Runtime] \(instances[index].type.rawValue): \(old.rawValue) → \(newState.rawValue)")
        #endif
    }
}
