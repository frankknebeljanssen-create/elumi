import SwiftUI

@main
struct FRDEVocabMVPApp: App {
    init() {
        #if DEBUG
        _ = TextNormalizationEngineSelfTest.didRun
        _ = FrenchLinguisticAnalysisSelfTest.didRun
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
