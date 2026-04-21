import SwiftUI

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
    }
}
