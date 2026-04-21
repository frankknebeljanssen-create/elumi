import SwiftUI
import Vision
import VisionKit
import UIKit

struct ScanImportView: View {
    static let reviewAnchorID = "scan-review-anchor"
    static let maxOCRLongEdge: CGFloat = 900
    static let maxFallbackOCRLongEdge: CGFloat = 720
    static let maxPreviewLongEdge: CGFloat = 560

    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let listStore: VocabularyListStore?
    let ensureListStoreReady: () -> VocabularyListStore
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void
    let sectionStyle: AppSectionStyle = .scan

    @StateObject var session = ScanSessionController()
    @State var importCompletionContext: ImportCompletionContext?
    @State var isShowingImportCompletion = false
    @State var isShowingFullscreenReview = false
    @State var reviewEditingPairID: IdentifiableUUID?
    @State var pendingCompletionDestination: AppScreen?
    @State var scanKeyboardInset: CGFloat = 0
    @State var previewEditSyncWorkItem: DispatchWorkItem?
    @State var manualCropSession: ManualCropSession?
    @FocusState var isListNameFocused: Bool
    @FocusState var focusedReviewField: ScanReviewFieldFocus?
    @State var isListNamePulseActive = false
    /// Identifiable-Wrapper um das zur Analyse anstehende Bild. Wird in
    /// `recognizeText(from:)` gesetzt, wenn `activeScanMode == .text` —
    /// der Nutzer hat dann bereits denselben Pick-Weg wie bei Vokabel-
    /// Scan durchlaufen (Mode-Card → Kamera/Foto-Album → Preparation-
    /// Sheet inkl. Crop).
    ///
    /// Die Präsentation läuft über `.fullScreenCover(item:)` in
    /// `ScanImportView+Presentations.swift` — **nicht** über einen
    /// separaten Bool-Flag. Grund: SwiftUI remountet die Cover-View bei
    /// jedem Parent-Re-Render, wenn die Content-Closure `if let …`
    /// verwendet; der laufende Claude-Request wird dabei durch den
    /// `.task`-Cleanup gecancelled (Symptom: „network error: cancelled"
    /// im Log, Alert „Analyse fehlgeschlagen"). Mit dem Identifiable-
    /// Wrapper hält `.fullScreenCover(item:)` genau EINE stabile
    /// Präsentation, bis das Item auf `nil` gesetzt wird.
    @State var freierTextPendingImage: FreierTextPendingImage?
    /// Zwischenspeicher für den Import-Completion-Context, den der
    /// „Freier Text"-Save-Flow produziert. Wird in der
    /// `.fullScreenCover(onDismiss:)` ausgelesen — erst wenn das Cover
    /// komplett weg ist, schaltet `isShowingImportCompletion` um, damit
    /// die Completion-View den selben Platz einnimmt wie beim Vokabel-Scan.
    @State var pendingFreierTextCompletion: ImportCompletionContext?

    // MARK: - Preparation-Sheet Quality & Auto-Optimize State
    //
    // Diese drei @State sind bewusst **in der View** (nicht im Session-
    // Controller), weil sie nur existieren, solange das Preparation-
    // Sheet sichtbar ist — beim Dismiss verschwinden sie automatisch
    // mit dem View-Lifecycle.
    //
    // Flow (siehe `ScanImportView+PreparationSheet.swift`):
    //
    //   1. Sheet erscheint → `.task` lädt den Preview-Image-Report
    //      (`ImageQualityAnalyzer.analyzeAsync`). Bis dahin bleibt
    //      `scanPreparationQualityReport = nil` → kein Banner sichtbar.
    //
    //   2. Report kommt rein → Banner rendert (Score + kombinierter
    //      Hint + Level-Icon), falls `report.level != .good`. Zusätzlich
    //      taucht der „Auto optimieren"-Button auf, wenn
    //      `report.hasAutoFixableIssue == true`.
    //
    //   3. User tippt „Auto optimieren" → `scanPreparationIsOptimizing`
    //      wird `true` (Spinner im Button), `ImageEnhancer.optimizeAsync`
    //      läuft, Resultat landet in `scanPreparationPreviewImage`
    //      (überschreibt das Bild, das in `recognizeText(from:)` geht)
    //      und der Re-Analyse-Report ersetzt den alten. Der Button
    //      ändert sich zu „Optimiert" (Aktiv-Status).
    //
    // Wird beim Neu-Öffnen des Sheets (neues Bild) automatisch in
    // `onPreparationSheetAppear(...)` via `resetPreparationQualityState()`
    // auf nil gesetzt.

    /// Qualitäts-Report des aktuell im Preparation-Sheet gezeigten
    /// Bildes. `nil` = noch nicht analysiert oder kein Bild sichtbar.
    /// Treiber für Quality-Banner + „Auto optimieren"-Button-Sichtbarkeit.
    @State var scanPreparationQualityReport: ImageQualityAnalyzer.Report?

    /// `true` während eines laufenden Auto-Optimize-Passes — der Button
    /// zeigt dann einen Spinner statt „Auto optimieren". Wird am Ende
    /// immer zurückgesetzt (auch bei Fehler), damit der User ggf. noch-
    /// mal tippen kann.
    @State var scanPreparationIsOptimizing = false

    /// `true`, sobald `scanPreparationPreviewImage` einmal durch einen
    /// Auto-Optimize-Pass ersetzt wurde. Steuert die Darstellung des
    /// Buttons (inaktiv/aktiv) und verhindert, dass der User denselben
    /// Pass mehrfach anstößt — ein erneuter Tap würde nur erneut
    /// dieselben Enhancement-Parameter anwenden.
    @State var scanPreparationWasOptimized = false
}
