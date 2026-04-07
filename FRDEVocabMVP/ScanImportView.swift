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
    @State var pendingCompletionDestination: AppScreen?
    @State var scanKeyboardInset: CGFloat = 0
    @State var previewEditSyncWorkItem: DispatchWorkItem?
    @State var manualCropSession: ManualCropSession?
    @FocusState var isListNameFocused: Bool
    @FocusState var focusedReviewField: ScanReviewFieldFocus?
    @State var isListNamePulseActive = false
}
