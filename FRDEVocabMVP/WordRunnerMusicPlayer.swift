import Foundation
import SwiftUI

/// **Zentrale Musikverwaltung für den Word Runner.**
///
/// Rolle: Orchestriert die Word-Runner-Musik (Track-Alternation,
/// Fade, Volume-Policy). Die eigentliche Audio-I/O — Bundle-Loading,
/// AVAudioSession, AVAudioPlayer-Setup, Fade-Timer — läuft durch
/// `SoundPlayer.shared` (siehe `FeedbackPlayer.swift`). Damit gibt es
/// **eine** Audio-Infrastruktur in der App, nicht zwei.
///
/// Warum trotzdem ein eigener Typ? Weil die Word-Runner-Musik
/// zusätzliche Logik braucht, die in `SoundPlayer` nichts zu suchen hat:
///   • Track-Rotation (pro Run zwischen zwei Tracks wechseln)
///   • Persistente Alternation über App-Restarts
///   • Fade-Dauer-Konvention (0.8 s bei Game-Over)
///
/// **Erweiterung auf weitere Tracks**: einfach einen weiteren
/// Resource-Namen in `tracks` anhängen. Die Alternation nutzt
/// `index % tracks.count` und passt sich automatisch an.
@MainActor
final class WordRunnerMusicPlayer: ObservableObject {

    // MARK: - Singleton

    static let shared = WordRunnerMusicPlayer()

    // MARK: - Tracks

    /// Bundle-Resource-Namen der Tracks (ohne Extension). Gespiegelt
    /// aus `MusicCatalog.runnerTracks` — einziger Ort, an dem Track-
    /// Listen gepflegt werden.
    private var tracks: [String] { MusicCatalog.runnerTracks }

    private let trackExtension = "mp3"

    // MARK: - Persistente Track-Alternation

    /// Schlüssel, unter dem der Index des **nächsten** zu spielenden
    /// Tracks persistiert wird. Überlebt App-Restarts — dadurch kriegt
    /// Run N+1 garantiert einen anderen Track als Run N, selbst wenn
    /// die App zwischendurch geschlossen wurde.
    private let nextTrackIndexKey = "wordRunner.nextTrackIndex"

    private var nextTrackIndex: Int {
        get { UserDefaults.standard.integer(forKey: nextTrackIndexKey) }
        set { UserDefaults.standard.set(newValue, forKey: nextTrackIndexKey) }
    }

    // MARK: - Published-State (für View-Observation)

    @Published private(set) var currentTrackName: String?

    /// Aktuell spielender Track? (Heuristisch — wir fragen nicht
    /// AVAudioPlayer.isPlaying durchgehend, sondern pflegen es selbst.)
    @Published private(set) var isPlaying: Bool = false

    // MARK: - Tuning

    // Audio-Balance-Pass (Phase 7.6): Musik insgesamt ~30 % leiser
    // (zwei −15 %-Stufen, 0.55 → 0.47 → 0.40), damit SFX klar über
    // den Mix kommen.
    private let defaultVolume: Float = 0.40
    private let defaultFadeDuration: TimeInterval = 0.8

    private init() {}

    // MARK: - Phase-2/3-API

    /// Startet die Musik für einen neuen Run.
    /// Rotiert auf den nächsten Track und loopt ihn.
    func startNewRun() {
        // Falls gerade ein Fade läuft: SoundPlayer bricht den beim
        // nächsten play-Aufruf implizit ab (neuer Loop = neuer State),
        // wir müssen hier nichts zusätzlich canceln.
        let index = nextTrackIndex % tracks.count
        let trackName = tracks[index]

        // Next-Index **vor** Playback persistieren. Falls Playback
        // fehlschlägt (z. B. Bundle-Resource fehlt), ist die Rotation
        // trotzdem fortgeschritten — beim nächsten Run landet der
        // andere Track dran, nicht zweimal derselbe.
        nextTrackIndex = (index + 1) % tracks.count

        // **Exklusiv-Ownership-Fix**: beim Run-Start nukt der Runner
        // **alle** bekannten Music-Tracks (auch die Arcade-Tracks)
        // — sonst spielen beide Player parallel, wenn der User
        // schnell zwischen Runner und Arcade wechselt.
        for resource in MusicCatalog.allMusicResources {
            SoundPlayer.shared.stopMusic(resource: resource)
        }

        SoundPlayer.shared.playMusic(
            resource: trackName,
            ext: trackExtension,
            volume: defaultVolume
        )
        currentTrackName = trackName
        isPlaying = true
    }

    /// Aliase, die der User-Spec entsprechen. Semantisch identisch zu
    /// `startNewRun()` — separate Namen existieren, weil die Spec sie
    /// als eigenständige API-Punkte verlangt hat.
    func playRunnerMusic() { startNewRun() }
    func nextRunnerTrack() { startNewRun() }

    /// Hartstopp der Musik ohne Fade. Für App-Hintergrund oder
    /// explizite Debug-Stop-Anforderungen. Nukt defensiv **alle**
    /// bekannten Music-Resources (siehe `startNewRun`-Kommentar).
    func stopRunnerMusic() {
        for resource in MusicCatalog.allMusicResources {
            SoundPlayer.shared.stopMusic(resource: resource)
        }
        currentTrackName = nil
        isPlaying = false
    }

    /// Sanftes Ausfaden über `defaultFadeDuration`. Shortcut für
    /// `fadeOut(over:)`.
    func fadeOutRunnerMusic() {
        fadeOut(over: defaultFadeDuration)
    }

    /// Fadet den aktiven Track über `duration` aus und stoppt ihn.
    /// Safe bei „kein Track läuft" (no-op).
    func fadeOut(over duration: TimeInterval) {
        guard let name = currentTrackName else { return }
        SoundPlayer.shared.fadeStopMusic(resource: name, over: duration) { [weak self] in
            guard let self else { return }
            if self.currentTrackName == name {
                self.currentTrackName = nil
                self.isPlaying = false
            }
        }
    }
}
