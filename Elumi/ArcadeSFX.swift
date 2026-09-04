import Foundation
import UIKit

/// **Zentrales Sound-Hook-System** für Arcade-Power-Ups.
///
/// Ziel: **eine** Stelle im Code, an der die akustische Sprache des
/// Power-Up-Systems definiert ist. Gameplay-Code ruft ausschließlich
/// über diesen Typ auf — keine `feedbackPlayer.playXYZ()`-Direktaufrufe
/// mehr quer durchs Projekt. Wenn später echte Sound-Assets kommen,
/// werden sie **hier** eingehängt, und alle Call-Sites ziehen automatisch
/// nach.
///
/// **Fünf Lebenszyklus-Events pro Power-Up** (aus User-Spec):
///   1. **Spawn** — Drop erscheint
///   2. **Pickup** — User sammelt das Power-Up ein
///   3. **Activate** — Aktiv-Zustand beginnt
///   4. **Collision** — Kollision an aktiver Hülle / Feedback-Ereignis
///      im Aktiv-Zustand (z. B. Snack prallt an der Schutz-Bubble ab)
///   5. **End** — Aktiv-Zustand endet, Effekt fadet aus
///
/// **Spam-Schutz**: `.collision`-Events bekommen ein zentrales
/// Debouncing (siehe `lastCollisionTriggerByType`), damit schnelle
/// Kollisions-Salven (z. B. mehrere Snacks in einem Frame gegen die
/// Bubble) den Sound nicht zerreißen. Andere Events (Spawn/Pickup/
/// Activate/End) sind einmalig pro Lebenszyklus und brauchen kein
/// Debouncing.
///
/// **Austauschbarkeit**: Jedes Event delegiert an den `FeedbackPlayer`
/// über klar benannte Hook-Methoden. Die Methoden sind heute auf
/// bestehende Sounds gemappt (z. B. `playPowerUpSpawn`), mit `// TODO:
/// final asset`-Kommentaren an den Stellen, wo der finale Sound noch
/// nicht geliefert wurde. Asset-Swap = Ein-Zeilen-Tausch in dieser
/// Datei.
@MainActor
final class ArcadeSFX {

    // MARK: - Event-Typ

    enum Event {
        case spawn
        case pickup
        case activate
        case collision
        case end
    }

    // MARK: - State

    /// Zuletzt gefeuertes Collision-Event pro Power-Up-Typ — Basis für
    /// Debouncing. Andere Events haben keine State-Track-Anforderung.
    private var lastCollisionTriggerByType: [ArcadePowerUpType: Date] = [:]

    /// Mindest-Abstand zwischen zwei Collision-Sounds desselben Typs
    /// in Sekunden. 0.15 s ist fein genug, um einzelne Treffer noch
    /// individuell hörbar zu machen, und grob genug, um bei einer
    /// 10er-Snack-Salve nicht 10× zu feuern.
    private let collisionDebounce: TimeInterval = 0.15

    /// Referenz auf den App-weiten `FeedbackPlayer`. Haltung via
    /// `weak` nicht nötig, weil `ArcadeSFX` view-lokal lebt und der
    /// Player eine höhere Lebensdauer hat.
    private let feedbackPlayer: FeedbackPlayer

    init(feedbackPlayer: FeedbackPlayer) {
        self.feedbackPlayer = feedbackPlayer
    }

    // MARK: - Public API

    /// Zentrale Einsprung-Methode. Gameplay-Code ruft hier, nicht
    /// direkt auf dem `FeedbackPlayer`.
    ///
    /// - Parameters:
    ///   - event: Welches Lebenszyklus-Event (spawn/pickup/…)
    ///   - type: Welches Power-Up löst aus
    ///   - date: Event-Zeitpunkt (meist `gameClock`) — genutzt fürs
    ///     Debouncing der Kollisions-Sounds.
    func fire(_ event: Event, for type: ArcadePowerUpType, at date: Date = Date()) {
        switch event {
        case .spawn:
            handleSpawn(for: type)
        case .pickup:
            handlePickup(for: type)
        case .activate:
            handleActivate(for: type)
        case .collision:
            guard debouncePassCollision(for: type, at: date) else { return }
            handleCollision(for: type)
        case .end:
            handleEnd(for: type)
        }
    }

    // MARK: - Per-Type-Handler (Tausch-Stellen für finale Assets)

    private func handleSpawn(for type: ArcadePowerUpType) {
        // TODO: typspezifische Spawn-Sounds sobald Assets vorliegen.
        // Heute: gemeinsamer generischer Power-Up-Spawn-Shimmer.
        switch type {
        case .shieldBubble:
            // TODO final asset: feedbackPlayer.playShieldBubbleSpawn()
            feedbackPlayer.playPowerUpSpawn()
        case .vacuum:
            // TODO final asset: feedbackPlayer.playVacuumSpawn()
            feedbackPlayer.playPowerUpSpawn()
        case .slowMotion, .bonusPoints, .extraLife:
            feedbackPlayer.playPowerUpSpawn()
        }
    }

    private func handlePickup(for type: ArcadePowerUpType) {
        switch type {
        case .shieldBubble:
            // TODO final asset: feedbackPlayer.playShieldBubblePickup()
            feedbackPlayer.playAchievement()
        case .vacuum:
            // TODO final asset: feedbackPlayer.playVacuumPickup()
            feedbackPlayer.playSuctionWhir()
        case .slowMotion, .bonusPoints, .extraLife:
            feedbackPlayer.playAchievement()
        }
    }

    private func handleActivate(for type: ArcadePowerUpType) {
        switch type {
        case .shieldBubble:
            // TODO final asset: feedbackPlayer.playShieldBubbleActivate()
            // Aktuell keine dedizierte Hook — der Pickup-Sound wirkt
            // bereits als Aktivierungs-Signal.
            break
        case .vacuum:
            // Der Whir-to-Loop-Übergang ist heute direkt in
            // `activateSuction(at:)` verdrahtet — die Zentralisierung
            // lassen wir in Slice 2, damit wir den laufenden Saug-Loop
            // nicht fragmentieren. Dieser Hook bleibt als No-Op
            // stehen, bis der finale Activate-Einmal-Sound kommt.
            break
        case .slowMotion:
            feedbackPlayer.playSlowMotionActivate()
        case .bonusPoints, .extraLife:
            feedbackPlayer.playAchievement()
        }
    }

    private func handleCollision(for type: ArcadePowerUpType) {
        switch type {
        case .shieldBubble:
            // TODO final asset: feedbackPlayer.playShieldBubbleRipple()
            // Bis dahin: leichter Miss-Sound als akustischer „Bounce".
            feedbackPlayer.playSnackMiss()
        case .vacuum:
            // Sauger-Kollisionen brauchen keinen dedizierten Sound —
            // das Einsaugen läuft über den Loop, der bereits abspielt.
            break
        case .slowMotion, .bonusPoints, .extraLife:
            break
        }
    }

    private func handleEnd(for type: ArcadePowerUpType) {
        switch type {
        case .shieldBubble:
            // TODO final asset: feedbackPlayer.playShieldBubbleEnd()
            break
        case .vacuum:
            feedbackPlayer.stopSuctionLoop()
        case .slowMotion, .bonusPoints, .extraLife:
            break
        }
    }

    // MARK: - Debouncing

    private func debouncePassCollision(for type: ArcadePowerUpType, at date: Date) -> Bool {
        if let last = lastCollisionTriggerByType[type],
           date.timeIntervalSince(last) < collisionDebounce {
            return false
        }
        lastCollisionTriggerByType[type] = date
        return true
    }

    /// Reset beim Game-Over / Exit, damit beim nächsten Run die
    /// Debounce-History nicht spuckt.
    func reset() {
        lastCollisionTriggerByType.removeAll()
    }
}
