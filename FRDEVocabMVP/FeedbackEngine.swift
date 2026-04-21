import Foundation
import SwiftUI
import Combine

/// Zentraler Router für alle UI-Feedback-Events in Elumi.
///
/// **Zweck** (aus dem Auftrag):
/// • Einheitliche Entscheidung, **wann** Feedback ausgelöst wird, **welche
///   Stärke** es hat und **welchen Sound** es spielt.
/// • Kein Duplizieren der Combo-/Streak-Logik in jedem Modul — die Call-
///   Sites rufen nur `record(event:)` mit einer klaren Intent-Struktur.
/// • Cooldown gegen Event-Spam bei schneller Antwort-Kadenz.
/// • Singleton (`shared`), weil ein App-globaler UI-Bus reicht — die
///   SessionStreak-Instanzen in den Controllern publishen hierher.
///
/// **Verhältnis zu `GamificationFeedbackPresenter`**:
/// Der Presenter bleibt die View-Anbindung (Toast-Rendering, Overlay).
/// Der `FeedbackEngine` sitzt eine Ebene darüber und entscheidet, **ob
/// und welcher** Toast angezeigt wird. So ist die Dramaturgie zentral,
/// das View-Rendering bleibt schlank.
@MainActor
final class FeedbackEngine: ObservableObject {
    static let shared = FeedbackEngine()

    private init() {}

    // MARK: - Player-Attachment

    /// Globaler FeedbackPlayer. Wird einmal beim App-Start per
    /// `attach(feedbackPlayer:)` gesetzt — danach können alle Call-Sites
    /// `record(.correctAnswer …)` aufrufen, ohne den Player lokal
    /// durchzureichen. Ohne Attach laufen die Events stumm durch (kein
    /// Crash, nur keine Sounds — sinnvoll für Unit-Tests oder Previews).
    private weak var attachedFeedbackPlayer: FeedbackPlayer?

    func attach(feedbackPlayer: FeedbackPlayer) {
        self.attachedFeedbackPlayer = feedbackPlayer
    }

    // MARK: - Event-Modell

    /// Intent-Schicht: ein Event beschreibt, **was** passiert ist
    /// (richtige Antwort, falsche Antwort, Session abgeschlossen,
    /// Wort auf „stark" gewechselt). Der Engine entscheidet daraus,
    /// **welche** UI-Stimmung dazu passt.
    enum Event {
        /// Eine richtige Antwort mit der **neuen laufenden Serie** als
        /// Parameter. Der Engine prüft, ob die Serie eine Schwelle
        /// erreicht hat, und löst ggf. einen Streak-Moment aus.
        case correctAnswer(currentStreak: Int)

        /// Eine falsche Antwort. Keine Serie → kein Streak-Event.
        /// Der Engine spielt einen leisen, neutralen „wrong"-Sound.
        case wrongAnswer

        /// Eine Session ist sauber abgeschlossen (mind. Minimum-
        /// Schwelle erreicht). Löst einen Milestone-Moment aus.
        case sessionCompleted(correctCount: Int, total: Int)

        /// Ein Wort ist gerade auf `.strong` gewechselt — „jetzt sitzt
        /// es". Optional vom Lernstatus-Store aufzurufen. Im MVP noch
        /// nicht verdrahtet, aber die API steht schon bereit.
        case wordMasteredNow(display: String)
    }

    // MARK: - Cooldown-State

    /// Zeitstempel des letzten großen Events (Streak Medium/Large/
    /// Milestone). Kleine Events ignorieren den Cooldown.
    private var lastLargeEventAt: Date = .distantPast

    /// Gibt `true` zurück, wenn gerade **jetzt** ein großes Event
    /// erlaubt ist (Cooldown abgelaufen). Kleine Events rufen diese
    /// Methode nicht — sie feuern immer.
    private func isLargeEventAllowed() -> Bool {
        Date().timeIntervalSince(lastLargeEventAt) >= FeedbackConfig.largeFeedbackCooldown
    }

    private func markLargeEventFired() {
        lastLargeEventAt = Date()
    }

    // MARK: - Public API

    /// Einziger Einstiegspunkt. Alle Controller rufen hier rein, der
    /// Engine erledigt den Rest (Sound + Toast + Haptik + Cooldown).
    /// Die konkreten UI-Artefakte entstehen über
    /// `GamificationFeedbackPresenter.shared` — er ist das View-Target.
    ///
    /// Der optionale `feedbackPlayer`-Parameter überschreibt den per
    /// `attach(feedbackPlayer:)` gesetzten Global-Player, falls der
    /// Caller gezielt einen anderen nutzen will (z. B. in speziellen
    /// Test-Flows). Normal-Fall: leer lassen, Engine nutzt den Global.
    func record(_ event: Event, feedbackPlayer: FeedbackPlayer? = nil) {
        let resolvedPlayer = feedbackPlayer ?? attachedFeedbackPlayer
        switch event {
        case .correctAnswer(let streak):
            handleCorrect(streak: streak, feedbackPlayer: resolvedPlayer)

        case .wrongAnswer:
            handleWrong(feedbackPlayer: resolvedPlayer)

        case .sessionCompleted(let correct, let total):
            handleSessionCompleted(correct: correct, total: total, feedbackPlayer: resolvedPlayer)

        case .wordMasteredNow(let display):
            handleWordMastered(display: display, feedbackPlayer: resolvedPlayer)
        }
    }

    // MARK: - Handlers

    private func handleCorrect(streak: Int, feedbackPlayer: FeedbackPlayer?) {
        // **Kein** Standard-Success-Sound hier — den spielen die
        // Controller (Training/Quiz/Flashcards/Akzente) weiterhin selbst
        // in ihren Handlern. Der Engine ist nur für Tiered-Events
        // (Streak-Moments + Milestones) zuständig, damit kein Sound
        // doppelt spielt. Der `Pulse`-Trigger ist orthogonal: er feuert
        // bei jeder richtigen Antwort, damit Views einen Scale-Up-Puls
        // auf der geklickten Card zeigen können.
        GamificationFeedbackPresenter.shared.noteSuccessPulse()

        // Streak-Moment? Höchste gerade erreichte Schwelle ermitteln.
        guard let tier = FeedbackConfig.tier(forCurrentStreak: streak) else { return }

        // Große Events unterliegen dem Cooldown (nicht zwei dicke Toasts
        // direkt hintereinander bei super-schnellem Flow).
        if tier.isLargeEvent, !isLargeEventAllowed() { return }
        if tier.isLargeEvent { markLargeEventFired() }

        // **Zusätzlicher** Streak-Sound (oberhalb des Controller-Success).
        // Kleine Events (Tier .small) bekommen `playToggle()` als subtile
        // Ergänzung, Medium/Large bekommen `playStreak()`. Der Controller-
        // Standard-Sound läuft parallel; zusammen entsteht der „reiche"
        // Moment-Klang ohne zusätzlichen Sound-Import.
        playSound(forTier: tier, feedbackPlayer: feedbackPlayer)

        // Toast/Overlay auslösen — Rendering-Details hängen im Presenter.
        GamificationFeedbackPresenter.shared.showStreakMoment(tier: tier, combo: streak)
    }

    private func handleWrong(feedbackPlayer: FeedbackPlayer?) {
        // **Kein** Sound hier — der Controller spielt weiterhin
        // `playStudyError()`, die jetzt zentral leise (`negativeSoundVolume`)
        // arbeitet. Engine triggert nur den sanften Wrong-Pulse für eine
        // dezente UI-Reaktion.
        GamificationFeedbackPresenter.shared.noteWrongPulse()
    }

    private func handleSessionCompleted(correct: Int, total: Int, feedbackPlayer: FeedbackPlayer?) {
        guard isLargeEventAllowed() else { return }
        markLargeEventFired()

        feedbackPlayer?.playStudyAchievement()

        // Session-Completion ist ein echter Milestone.
        let label: String
        if correct == total, total > 0 {
            label = "Fehlerfrei!"
        } else if correct >= (total * 3 / 4) {
            label = "Geschafft"
        } else {
            label = "Stark durchgezogen"
        }
        GamificationFeedbackPresenter.shared.showMilestone(label: label)
    }

    private func handleWordMastered(display: String, feedbackPlayer: FeedbackPlayer?) {
        guard isLargeEventAllowed() else { return }
        markLargeEventFired()

        feedbackPlayer?.playStudyAchievement()
        // Deutsche typografische Anführungszeichen um das Wort —
        // Swift-sicher via Unicode-Escape, damit der String-Parser
        // nicht am oberen Anführungszeichen-Ende stolpert.
        GamificationFeedbackPresenter.shared.showMilestone(
            label: "Jetzt sitzt \u{201E}\(display)\u{201C}"
        )
    }

    // MARK: - Sound-Mapping

    private func playSound(forTier tier: FeedbackConfig.StreakTier, feedbackPlayer: FeedbackPlayer?) {
        guard let feedbackPlayer else { return }
        switch tier {
        case .small:
            // Kleiner zusätzlicher Bonus-Ton oberhalb des Standard-
            // Success, damit der erste Streak-Moment spürbar wird,
            // ohne die Großen zu überlagern.
            feedbackPlayer.playToggle()
        case .medium:
            feedbackPlayer.playStreak()
        case .large:
            // Großer Moment: Streak-Sound + leichter Level-Up-Sound
            // kombiniert als „reicher" Klang.
            feedbackPlayer.playStreak()
        case .milestone:
            feedbackPlayer.playAchievement()
        }
    }
}
