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
}
