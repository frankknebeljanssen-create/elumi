import Foundation

/// **Single Source of Truth** für alle Musik-Ressourcen der App.
///
/// Warum zentral?
///   • **Exklusiv-Ownership-Garantie**: ArcadeMusicPlayer und
///     WordRunnerMusicPlayer dürfen NIEMALS gleichzeitig aktiv sein.
///     Beim Start eines Runs nukt der jeweilige Player die
///     **fremden** Music-Tracks, nicht nur seine eigenen.
///     `MusicCatalog.allMusicResources` ist die Liste, die dafür
///     iteriert wird.
///   • **Erweiterbarkeit**: Wenn ein neues Modul Musik bekommt
///     (z. B. Boss-Theme, Level-Musik), wird der Resource-Name hier
///     eingetragen, und alle bestehenden Player exkludieren ihn
///     automatisch — ohne dass wir in jedem Player die Fremdlisten
///     pflegen müssten.
///   • **Keine doppelte Infrastruktur**: Wir nutzen weiterhin
///     `SoundPlayer.shared.playMusic/stopMusic/fadeStopMusic` als
///     physisches Audio-Interface. Der Katalog ist reine Metadata.
///
/// Die hier gelisteten Ressource-Namen (ohne `.mp3`-Extension)
/// müssen auch in der pbxproj als Resources registriert sein —
/// sonst findet `Bundle.main.url(forResource:…)` sie nicht.
enum MusicCatalog {

    /// Word-Runner-Tracks (WordRunnerMusicPlayer).
    static let runnerTracks: [String] = [
        "runner_theme_01",
        "runner_theme_02"
    ]

    /// Arcade-Tracks (ArcadeMusicPlayer).
    static let arcadeTracks: [String] = [
        "arcade_theme_01",
        "arcade_theme_02"
    ]

    /// Event-Spezial-Tracks (aktuell: Fish-Runde im Arcade).
    static let specialTracks: [String] = [
        "fish_theme_01"
    ]

    /// Alle Musik-Ressourcen zusammen. Wird von jedem Player genutzt,
    /// um **alle** anderen Music-Sounds zu nuken, bevor er selbst
    /// startet. Das ist unsere Audio-Mutex-Garantie.
    static var allMusicResources: [String] {
        runnerTracks + arcadeTracks + specialTracks
    }
}
