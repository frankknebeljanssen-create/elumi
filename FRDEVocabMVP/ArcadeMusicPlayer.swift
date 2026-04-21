import Foundation
import SwiftUI

/// **Zentrale Musikverwaltung für das Arcade-Spiel** (Elumi-Snackfang).
///
/// Analog zu `WordRunnerMusicPlayer`:
///   • Singleton, `@MainActor`.
///   • Delegiert Audio-I/O an `SoundPlayer.shared` (keine eigene
///     AVAudioPlayer-/Session-Bauerei — selbe Infrastruktur wie SFX
///     und Word-Runner-Musik).
///   • State-getrieben: `idle / running / fishEvent / gameOver`.
///     Die Arcade-View ruft die State-Übergänge an ihren Lifecycle-
///     Hooks (Start, Bonus-Round, Ende, Close).
///
/// **Track-Layout**:
///   • 2 Arcade-Tracks — alternierend pro Run, Rotation persistent
///     in `UserDefaults` (Key `arcade.nextTrackIndex`).
///   • 1 Fish-Theme — wechselt rein, solange das Fisch-Bonus-Event
///     läuft. Lautstärke minimal höher (+7 %), damit sich das Event
///     „besonders" anfühlt (per Spec).
///
/// **Fade-Modell**:
///   • Run-Start: hart-play (frischer Run-Beginn darf abrupt
///     wirken — der User hat gerade „Start" getippt).
///   • Fish-Event-Übergänge: **soft** (fade-out ~0.6 s → fade-in via
///     neuer Track-Start).
///   • Game-Over / Close: fade-out ~0.8 s.
///
/// **Resume-Verhalten nach Fish-Event**: bewusst restart des
/// unterbrochenen Arcade-Tracks (nicht Seek), weil SoundPlayer keine
/// Position persistiert. Der Fade-Wechsel ist weich genug, dass der
/// Loop-Neustart nicht als Bruch empfunden wird.
///
/// **Erweiterbar** (Spec „mehr Tracks / Boss-Musik / Level-Musik"):
///   • Neue Arcade-Tracks → in `arcadeTracks` Liste hinten anhängen,
///     Rotation passt automatisch.
///   • Neue Event-Musik (z. B. Boss) → analog zum Fish-Pfad
///     (`interruptedTrackName` + `playSpecial(_:)`-Helper).
@MainActor
final class ArcadeMusicPlayer: ObservableObject {

    // MARK: - Singleton

    static let shared = ArcadeMusicPlayer()

    // MARK: - States

    enum State: Equatable {
        case idle
        case running
        case fishEvent
        case gameOver
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentTrack: String?

    // MARK: - Tracks

    private var arcadeTracks: [String] { MusicCatalog.arcadeTracks }
    private var fishTrack: String { MusicCatalog.specialTracks.first ?? "fish_theme_01" }
    private let trackExtension = "mp3"

    // MARK: - Lautstärken

    // Audio-Balance-Pass (Phase 7.6): Musik ~15 % leiser, damit SFX
    // (v. a. Life-Loss) über dem Mix durchkommen. Fish-Event bleibt
    // proportional etwas lauter als Standard (atmosphärischer Moment).
    private let arcadeVolume: Float = 0.47
    private let fishVolume: Float = 0.53

    // MARK: - Fade-Dauern

    private let fadeOutNormal: TimeInterval = 0.6
    private let fadeOutGameOver: TimeInterval = 0.8

    // MARK: - Track-Rotation (persistent)

    private let nextTrackIndexKey = "arcade.nextTrackIndex"

    private var nextTrackIndex: Int {
        get { UserDefaults.standard.integer(forKey: nextTrackIndexKey) }
        set { UserDefaults.standard.set(newValue, forKey: nextTrackIndexKey) }
    }

    /// Merker, welcher Arcade-Track beim Eintritt ins Fish-Event lief
    /// — wird beim Verlassen des Events restartet. Falls das Event
    /// ohne laufenden Arcade-Track startete, bleibt nil und wir
    /// greifen auf die normale Rotation zurück.
    private var interruptedTrackName: String?

    private init() {}

    // MARK: - Öffentliche API (Phase-4-/Spec-API)

    /// Startet einen neuen Arcade-Run. Rotiert auf den nächsten
    /// Track aus `arcadeTracks`, stoppt hart alle ggf. laufenden
    /// Spuren (keine Phantom-Player) und loopt den neuen Track.
    func startNewRun() {
        stopAllTracks()
        let idx = nextTrackIndex % arcadeTracks.count
        let track = arcadeTracks[idx]
        // Rotation **vor** Playback inkrementieren — falls Playback
        // fehlschlägt, rotiert trotzdem (kein Loop-Lock auf Track 1).
        nextTrackIndex = (idx + 1) % arcadeTracks.count
        SoundPlayer.shared.playMusic(
            resource: track,
            ext: trackExtension,
            volume: arcadeVolume
        )
        currentTrack = track
        state = .running
        interruptedTrackName = nil
        #if DEBUG
        print("🎵 [ArcadeMusic] run start → \(track)")
        #endif
    }

    /// Hartstopp — keine Fade. Für View-Close-Pfade, die sofort
    /// Ruhe brauchen.
    func stopArcadeMusic() {
        stopAllTracks()
        currentTrack = nil
        state = .idle
        interruptedTrackName = nil
    }

    /// Weiches Ausfaden; nach Abschluss ist `state = .idle`.
    /// Standard-Fade-Dauer (`fadeOutGameOver`), wenn kein Wert
    /// angegeben.
    func fadeOut(over duration: TimeInterval? = nil) {
        let d = duration ?? fadeOutGameOver
        guard let track = currentTrack else {
            state = .idle
            return
        }
        state = .gameOver
        SoundPlayer.shared.fadeStopMusic(resource: track, over: d) { [weak self] in
            guard let self else { return }
            // Nur resetten, wenn wir noch im gameOver-Zustand sind —
            // ein schneller Restart kann dazwischenfunken.
            if self.state == .gameOver {
                self.currentTrack = nil
                self.state = .idle
                self.interruptedTrackName = nil
            }
        }
    }

    // MARK: - Fish-Event

    /// Wechselt auf den Fish-Theme-Track. Fadet den laufenden
    /// Arcade-Track weich aus, startet dann das Fish-Theme.
    ///
    /// Idempotent: erneuter Call während `.fishEvent` ist no-op.
    func enterFishEvent() {
        guard state != .fishEvent else { return }
        interruptedTrackName = currentTrack
        state = .fishEvent

        let onDone: () -> Void = { [weak self] in
            guard let self else { return }
            // State-Guard: zwischen Fade-Start und Fade-Ende kann der
            // User den Run beendet oder neugestartet haben.
            guard self.state == .fishEvent else { return }
            SoundPlayer.shared.playMusic(
                resource: self.fishTrack,
                ext: self.trackExtension,
                volume: self.fishVolume
            )
            self.currentTrack = self.fishTrack
            #if DEBUG
            print("🎵 [ArcadeMusic] fish event active")
            #endif
        }

        if let track = currentTrack {
            SoundPlayer.shared.fadeStopMusic(resource: track, over: fadeOutNormal, onComplete: onDone)
        } else {
            onDone()
        }
    }

    /// Beendet das Fish-Event und kehrt zum vorherigen Arcade-Track
    /// zurück. Fish-Theme fadet aus, dann wird der unterbrochene
    /// Track neu gestartet (kein echtes Seek — SoundPlayer speichert
    /// keine Position; der Fade-Übergang kaschiert den Loop-
    /// Neustart).
    ///
    /// Falls kein Interruption-Track gemerkt ist (seltener Randfall,
    /// z. B. Fish direkt nach App-Start ohne vorherigen Run), wird
    /// auf die normale Rotation zurückgegriffen.
    func exitFishEvent() {
        guard state == .fishEvent else { return }
        state = .running

        let resumeTrack: String = interruptedTrackName ?? arcadeTracks[nextTrackIndex % arcadeTracks.count]
        let onDone: () -> Void = { [weak self] in
            guard let self else { return }
            guard self.state == .running else { return }
            SoundPlayer.shared.playMusic(
                resource: resumeTrack,
                ext: self.trackExtension,
                volume: self.arcadeVolume
            )
            self.currentTrack = resumeTrack
            self.interruptedTrackName = nil
            #if DEBUG
            print("🎵 [ArcadeMusic] fish event ended → back to \(resumeTrack)")
            #endif
        }

        SoundPlayer.shared.fadeStopMusic(resource: fishTrack, over: fadeOutNormal, onComplete: onDone)
    }

    // MARK: - Intern

    /// **Exklusiv-Ownership-Garantie** (Audio-Integration-Fix):
    /// Nukt nicht nur die eigenen Arcade-Tracks, sondern **alle**
    /// in `MusicCatalog.allMusicResources` gelisteten Tracks — inkl.
    /// Word-Runner. So wird sicher verhindert, dass beim schnellen
    /// Modus-Wechsel zwei Musik-Quellen parallel spielen.
    private func stopAllTracks() {
        for track in MusicCatalog.allMusicResources {
            SoundPlayer.shared.stopMusic(resource: track)
        }
    }
}
