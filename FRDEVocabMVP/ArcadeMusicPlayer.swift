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

    // Audio-Balance-Pass (Phase 7.6 — User-Report „Musik zu laut"):
    // weitere Reduktion ~25 % gegenüber vorigem Pass. Musik sitzt
    // jetzt bewusst leise unter den SFX; Player können sich im
    // Menü die System-Lautstärke hochregeln, ohne dass die SFX
    // schreien.
    private let arcadeVolume: Float = 0.30
    private let fishVolume: Float = 0.32

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

    /// **Preload** (Phase 7.6) — bereitet den nächsten Arcade-Track
    /// vor, damit `startNewRun()` ohne Decoder-Anlauf spielt. Wird
    /// vom `ElumiArcadeGameView.onAppear` beim Start-Screen-Aufruf
    /// gecalled.
    ///
    /// Achtung: verändert `nextTrackIndex` **nicht** — das passiert
    /// weiterhin erst in `startNewRun`, damit die Rotation stabil
    /// bleibt auch bei mehrfachem Preload.
    func preloadNextTrack() {
        let idx = nextTrackIndex % arcadeTracks.count
        let track = arcadeTracks[idx]
        SoundPlayer.shared.preloadMusic(resource: track, ext: trackExtension)
    }

    /// Startet einen neuen Arcade-Run. Rotiert auf den nächsten
    /// Track aus `arcadeTracks`, stoppt hart alle ggf. laufenden
    /// Spuren (keine Phantom-Player) und loopt den neuen Track.
    func startNewRun() {
        let idx = nextTrackIndex % arcadeTracks.count
        let track = arcadeTracks[idx]
        nextTrackIndex = (idx + 1) % arcadeTracks.count
        // Phase 7.6 — bulletproof `stopAllMusic`, erhält Preload für
        // die Ziel-Resource, damit Musik sofort startet.
        SoundPlayer.shared.stopAllMusic(keepPreloadFor: track)
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

    /// Wechselt auf den Fish-Theme-Track. **Phase 7.6 Bug-Fix**: früher
    /// fadeten wir den Arcade-Track über 0.6 s weich aus, bevor das
    /// Fish-Theme startete. Das führte dazu, dass beide Tracks
    /// gleichzeitig liefen (User-Report „alte Musik läuft mit der
    /// neuen zusammen").
    ///
    /// Jetzt: **harter Cut** — alle anderen Music-Resources werden
    /// sofort gestoppt, dann das Fish-Theme gestartet. Kein Overlap,
    /// keine Race-Condition mit pending Fade-Timern.
    ///
    /// Idempotent: erneuter Call während `.fishEvent` ist no-op.
    func enterFishEvent() {
        guard state != .fishEvent else { return }
        interruptedTrackName = currentTrack
        state = .fishEvent

        // **Phase 7.6 Bug-2 Final-Fix**: `stopAllMusic` iteriert
        // **jeden** Player im Dict (unabhängig von MusicCatalog-
        // Listen), zwingt Volume auf 0 und ruft `.stop()`. Falls ein
        // Zombie-Player unter einem exotischen Key hängt, wird er
        // hier garantiert gekillt. Der vorige `stopAllTracks(except:)`-
        // Ansatz hat sich verlassen, dass der Arcade-Player unter
        // einem bekannten Key steht — Zombie-Szenario griff nicht.
        SoundPlayer.shared.stopAllMusic(keepPreloadFor: fishTrack)
        SoundPlayer.shared.playMusic(
            resource: fishTrack,
            ext: trackExtension,
            volume: fishVolume
        )
        currentTrack = fishTrack
        #if DEBUG
        print("🎵 [ArcadeMusic] fish event active (exclusive)")
        #endif
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

        // **Phase 7.6 Bug 2 Final-Fix (exit-seitig)** — harter Cut.
        // `stopAllMusic` killt den Fish-Track + alle Zombies, dann
        // startet resume-Track exklusiv.
        SoundPlayer.shared.stopAllMusic(keepPreloadFor: resumeTrack)
        SoundPlayer.shared.playMusic(
            resource: resumeTrack,
            ext: trackExtension,
            volume: arcadeVolume
        )
        currentTrack = resumeTrack
        interruptedTrackName = nil
        #if DEBUG
        print("🎵 [ArcadeMusic] fish event ended → \(resumeTrack) (exclusive)")
        #endif
    }

    // MARK: - Intern

    /// **Exklusiv-Ownership-Garantie** (Audio-Integration-Fix):
    /// Nukt nicht nur die eigenen Arcade-Tracks, sondern **alle**
    /// in `MusicCatalog.allMusicResources` gelisteten Tracks — inkl.
    /// Word-Runner. So wird sicher verhindert, dass beim schnellen
    /// Modus-Wechsel zwei Musik-Quellen parallel spielen.
    ///
    /// **Phase 7.6** — `except`-Parameter sorgt dafür, dass der
    /// preloaded-silent Player der Ziel-Resource **nicht** mit-
    /// zerstört wird. Ohne das würde ein `stopAllTracks()` direkt
    /// vor `playMusic(target)` den Preload zerstören und `playMusic`
    /// müsste einen frischen Player erstellen → Musik startet spät.
    private func stopAllTracks(exceptPreloadFor target: String? = nil) {
        for track in MusicCatalog.allMusicResources {
            SoundPlayer.shared.stopMusic(resource: track)
            // Preload für andere Tracks sauber wegräumen — verhindert
            // stummes Hintergrund-Streamen konkurrierender Resources
            // (Fish-Event-Bug: alter Track silent, neuer laut → User
            // hört nur den neuen, aber zwei Player laufen).
            if target == nil || track != target! {
                SoundPlayer.shared.dropPreload(resource: track)
            }
        }
    }
}
