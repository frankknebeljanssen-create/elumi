import Foundation

/// Zentrale Konfiguration für das **Feedback-System** — getrennt vom
/// `GamificationConfig` (XP/Level/Credits), weil Feedback-Dramaturgie
/// eine andere Achse ist als Reward-Balancing. Ein Combo-Bonus für XP
/// darf bei 5 bleiben, selbst wenn wir parallel drei Streak-Stufen
/// (3/5/10) für die UI-Feedback-Effekte definieren wollen.
///
/// Designprinzipien (aus dem Auftrag):
/// • **Qualität vor Quantität** — lieber wenige starke Signale als viele
///   kleine. Die drei Schwellen 3/5/10 sind bewusst grob, keine Fein-
///   Abstufung alle 1–2 Treffer.
/// • **Cooldown** gegen Spam — ein großes Event darf nicht unmittelbar
///   auf ein anderes folgen. Bei sehr schnellem Spielfluss würde sonst
///   ein Toast den anderen überlagern.
/// • **Release-sichtbare Konstanten** — alles hier einstellbar, keine
///   verteilten Magic-Numbers in den Controllern.
enum FeedbackConfig {

    // MARK: - Streak-Schwellen

    /// Erster Streak-Moment — „3 in Folge". Ein leicht erkennbares Erfolgs-
    /// Signal, das den User bestärkt, weiter zu machen, aber noch ruhig
    /// bleibt (kein Feuerwerk).
    static let streakThresholdSmall: Int = 3

    /// Bekannter Combo-Moment — „5 richtig in Folge". Deutlich präsenter;
    /// entspricht gleichzeitig `GamificationConfig.xpComboThreshold`,
    /// damit XP-Bonus und visuelles Feedback auf derselben Linie laufen.
    static let streakThresholdMedium: Int = 5

    /// Großer Moment — „10 richtig in Folge". Selten, spürbar, Bounce-
    /// Animation + eigener Sound. Passiert nicht in jeder Session.
    static let streakThresholdLarge: Int = 10

    // MARK: - Cooldowns

    /// Mindest-Pause zwischen **großen** Feedback-Events (Streak Medium
    /// oder höher + Milestone). Verhindert, dass bei schneller Antwort-
    /// Kadenz zwei Toasts direkt hintereinander stapeln. Kleine Events
    /// (Standard-Success + Streak-Small) dürfen weiter in jeder Antwort
    /// feuern, weil sie klein genug sind, um nicht zu stören.
    static let largeFeedbackCooldown: TimeInterval = 1.5

    // MARK: - Sichtzeiten

    /// Wie lange ein Streak-Toast sichtbar bleibt, bevor er fade-out
    /// geht. Klein-bis-groß gestaffelt, damit größere Events mehr Raum
    /// zum Wirken bekommen.
    static func toastVisibleDuration(for tier: StreakTier) -> TimeInterval {
        switch tier {
        case .small:     return 1.2
        case .medium:    return 1.8
        case .large:     return 2.2
        case .milestone: return 2.6
        }
    }

    // MARK: - Sound

    /// Globaler An/Aus-Schalter für Feedback-Sounds. Bindet sich an
    /// `@AppStorage(feedbackSoundEnabledKey)` und ist der einzige Kanal,
    /// über den die UI Sounds global abschaltet — der `FeedbackPlayer`
    /// hat zwar sein eigenes `areSoundsEnabled`, der neue Key hier ist
    /// die **feature-spezifische** Tonspur (wurde bislang implizit am
    /// Player gehängt). MVP-Default: ON.
    ///
    /// Separat vom FeedbackPlayer-Schalter, damit User später nur die
    /// Gamification-Sounds abschalten könnte, ohne System-Sounds (Tap-
    /// Geräusche, TTS) mit zu deaktivieren.
    static let defaultSoundEnabled: Bool = true

    // MARK: - Negatives Feedback

    /// Volume für den „wrong"-Sound bei falschen Antworten. Sehr leise,
    /// fast nur haptischer Hinweis. User-Prinzip: Fehler nicht bestrafen,
    /// nur sanft lenken. Wenn `negativeSoundEnabled == false`, wird gar
    /// kein Sound gespielt.
    static let negativeSoundVolume: Float = 0.35

    /// Ob bei falschen Antworten überhaupt ein Sound gespielt wird.
    /// Default: an, aber **leise**. Kann später pro-User umgeschaltet
    /// werden.
    static let negativeSoundEnabled: Bool = true

    // MARK: - Tier-Definition

    /// Die Abstufung der Feedback-Events. Benutzt vom `FeedbackEngine`
    /// und `GamificationFeedbackPresenter`, damit beide dieselbe Sprache
    /// sprechen — keine ad-hoc-if-else-Kaskaden in der View.
    enum StreakTier: Int, Comparable, CaseIterable {
        case small = 0      // 3 in Folge
        case medium = 1     // 5 in Folge
        case large = 2      // 10 in Folge
        case milestone = 3  // Besonderer Moment (z. B. Session-Ende, Wort jetzt „stark")

        static func < (lhs: StreakTier, rhs: StreakTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Gehört das Event in die „große" Kategorie, die dem Cooldown
        /// unterliegt? Medium und höher — damit Small-Moments (3 in Folge)
        /// auch bei schnellem Flow durchkommen.
        var isLargeEvent: Bool { self >= .medium }
    }

    /// Bildet eine laufende Streak auf den passenden Tier ab. `nil` heißt
    /// „kein spezielles Event" — der Aufrufer zeigt dann nur das
    /// Standard-Success-Feedback (Micro-Pulse + Click), kein Toast.
    ///
    /// Regel: es wird **exakt** die höchste gerade erreichte Schwelle
    /// getriggert — nicht alle darunterliegenden. Bei Combo = 10 feuert
    /// also nur `.large`, nicht zusätzlich `.medium` und `.small`.
    static func tier(forCurrentStreak combo: Int) -> StreakTier? {
        if combo == streakThresholdLarge { return .large }
        if combo == streakThresholdMedium { return .medium }
        if combo == streakThresholdSmall { return .small }
        // Mehrfache von Medium jenseits von 10 (15, 20, 25, …) lösen
        // weiter `.medium`-Events aus — damit lange Serien sichtbar
        // bleiben, aber ohne dass `.large` inflationär auftritt.
        if combo > streakThresholdLarge,
           combo % streakThresholdMedium == 0 {
            return .medium
        }
        return nil
    }
}

// MARK: - @AppStorage Keys

/// Zentraler Key für die Feedback-Sound-Einstellung. Getrennt vom
/// FeedbackPlayer-Master-Switch, damit ein späteres Settings-Panel die
/// Gamification-Sounds separat steuern kann.
let feedbackSoundEnabledKey = "elumi.feedback.sound.enabled.v1"
