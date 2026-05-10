import SwiftUI
import SwiftData

@main
struct FRDEVocabMVPApp: App {
    init() {
        #if DEBUG
        _ = TextNormalizationEngineSelfTest.didRun
        _ = FrenchLinguisticAnalysisSelfTest.didRun
        // Artikel-Modus-Regressionstests — feuern einmal pro App-Start.
        // Verhindern still gebrochene Logik (falsche Gender-Auflösung,
        // Lernkern-Drift) ohne externes XCTest-Target. Release-Builds
        // sehen die Datei gar nicht.
        ArticleModeClassifierTests.runIfNeeded()

        // **Dev-Mode 2026-05-09** — bei jedem App-Start auf 10 Credits
        // setzen, damit Frank ohne ständige Reset-Klicks/Streak-Loops
        // testen kann. Bare-Key sofort schreiben (greift für alle
        // `@AppStorage(appArcadeCreditsKey)`-Reader); ProgressStore
        // wird via `Task` nach kurzem Delay synchronisiert (er ist
        // `@MainActor` und seine `shared`-Init triggert beim ersten
        // Zugriff — Task gibt der App-Init-Phase Zeit, durchzulaufen,
        // bevor wir den Store mutieren). Release-Builds sehen das
        // gesamte `#if DEBUG` nicht.
        UserDefaults.standard.set(10, forKey: appArcadeCreditsKey)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            ProgressStore.shared.mutate { $0.arcadeCredits = 10 }
        }
        #endif

        // Master-Lexikon im Hintergrund prewarmen — verhindert eine
        // spürbare Main-Thread-Blockade (SQLite-Load + Entry-Parsing,
        // ca. 100–500 ms) beim ersten Modul-Setup. Ohne Prewarm würde
        // die View, die zuerst `StandardVocabularyLoader.allEntries`
        // liest (z. B. Training-Setup mit Listen-Aggregation), den
        // Load synchron auslösen. Die Task läuft auf `.utility`, damit
        // sie keine UI-Frames konkurriert.
        //
        // `vocabularyItems` ist der Abkömmling, den der `ListStore`
        // als Lazy-Property lädt (siehe `VocabularyListStore.builtIn-
        // ListStorage`). Wir prewarmen ihn hier mit, damit die erste
        // Modul-Öffnung auf einen warm-gecachten `static let` trifft.
        Task.detached(priority: .utility) {
            _ = StandardVocabularyLoader.allEntries
            _ = StandardVocabularyLoader.vocabularyItems
            _ = StandardVocabularyLoader.verbEntries
            _ = StandardVocabularyLoader.nounEntries
            _ = StandardVocabularyLoader.frenchGenderMap
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // **SwiftData ModelContainer** (Léa-Chat MVP Schritt 1, 2026-05-10)
        // — erste Nutzung von SwiftData im Projekt. Aktuell nur die
        // `ChatMessage`-Tabelle für Chat-History-Persistenz; weitere
        // Models werden hier nachgezogen.
        .modelContainer(for: ChatMessage.self)
    }
}
