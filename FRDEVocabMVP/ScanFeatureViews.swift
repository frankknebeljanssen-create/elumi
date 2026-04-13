import SwiftUI
import Vision
import VisionKit
import UIKit

struct ScanImportView: View {
    private enum ReviewFieldFocus: Hashable {
        case source(UUID)
        case target(UUID)
    }

    private static let reviewAnchorID = "scan-review-anchor"
    private static let maxOCRLongEdge: CGFloat = 900
    private static let maxFallbackOCRLongEdge: CGFloat = 720
    private static let maxPreviewLongEdge: CGFloat = 560

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appDirectionKey) private var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let listStore: VocabularyListStore?
    let ensureListStoreReady: () -> VocabularyListStore
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void
    private let sectionStyle: AppSectionStyle = .scan

    @StateObject private var session = ScanSessionController()
    @State private var importCompletionContext: ImportCompletionContext?
    @State private var isShowingImportCompletion = false
    @State private var pendingCompletionDestination: AppScreen?
    @State private var scanKeyboardInset: CGFloat = 0
    @State private var previewEditSyncWorkItem: DispatchWorkItem?
    @State private var manualCropSession: ManualCropSession?
    @FocusState private var isListNameFocused: Bool
    @FocusState private var focusedReviewField: ReviewFieldFocus?
    @State private var isListNamePulseActive = false

    private var importText: String {
        get { session.importText }
        nonmutating set { session.importText = newValue }
    }

    private var scanSourceLanguage: StudyLanguage {
        get { session.scanSourceLanguage }
        nonmutating set { session.scanSourceLanguage = newValue }
    }

    private var importType: CardType {
        get { session.importType }
        nonmutating set { session.importType = newValue }
    }

    private var selectedCollectionPreset: ListCollectionPreset {
        get { session.selectedCollectionPreset }
        nonmutating set { session.selectedCollectionPreset = newValue }
    }

    private var listName: String {
        get { session.listName }
        nonmutating set { session.listName = newValue }
    }

    private var importMessage: String {
        get { session.importMessage }
        nonmutating set { session.importMessage = newValue }
    }

    private var previewPairs: [ImportPreviewPair] {
        get { session.previewPairs }
        nonmutating set { session.previewPairs = newValue }
    }

    private var selectedImage: UIImage? {
        get { session.selectedImage }
        nonmutating set { session.selectedImage = newValue }
    }

    private var showingCamera: Bool {
        get { session.showingCamera }
        nonmutating set { session.showingCamera = newValue }
    }

    private var showingPhotoLibrary: Bool {
        get { session.showingPhotoLibrary }
        nonmutating set { session.showingPhotoLibrary = newValue }
    }

    private var selectedScanInputMethod: ScanInputMethod? {
        get { session.selectedScanInputMethod }
        nonmutating set { session.selectedScanInputMethod = newValue }
    }

    private var isRecognizingImage: Bool {
        get { session.isRecognizingImage }
        nonmutating set { session.isRecognizingImage = newValue }
    }

    private var isSyncingPreviewToText: Bool {
        get { session.isSyncingPreviewToText }
        nonmutating set { session.isSyncingPreviewToText = newValue }
    }

    private var showingImagePreview: Bool {
        get { session.showingImagePreview }
        nonmutating set { session.showingImagePreview = newValue }
    }

    private var showingScanPreparation: Bool {
        get { session.showingScanPreparation }
        nonmutating set { session.showingScanPreparation = newValue }
    }

    private var showingAdditionalScanOptions: Bool {
        get { session.showingAdditionalScanOptions }
        nonmutating set { session.showingAdditionalScanOptions = newValue }
    }

    private var scanToastMessage: String {
        get { session.scanToastMessage }
        nonmutating set { session.scanToastMessage = newValue }
    }

    private var isShowingScanToast: Bool {
        get { session.isShowingScanToast }
        nonmutating set { session.isShowingScanToast = newValue }
    }

    private var scanToastIsWarning: Bool {
        get { session.scanToastIsWarning }
        nonmutating set { session.scanToastIsWarning = newValue }
    }

    private var scanAIInfoMessage: String {
        get { session.scanAIInfoMessage }
        nonmutating set { session.scanAIInfoMessage = newValue }
    }

    private var isShowingScanAIInfoAlert: Bool {
        get { session.isShowingScanAIInfoAlert }
        nonmutating set { session.isShowingScanAIInfoAlert = newValue }
    }

    private var scanProgressStep: Int {
        get { session.scanProgressStep }
        nonmutating set { session.scanProgressStep = newValue }
    }

    private var scanRuntimeStage: ScanRuntimeStage {
        get { session.scanRuntimeStage }
        nonmutating set { session.scanRuntimeStage = newValue }
    }

    private var shouldAppendNextScan: Bool {
        get { session.shouldAppendNextScan }
        nonmutating set { session.shouldAppendNextScan = newValue }
    }

    private var originalScanImage: UIImage? {
        get { session.originalScanImage }
        nonmutating set { session.originalScanImage = newValue }
    }

    private var preparedScanImage: UIImage? {
        get { session.preparedScanImage }
        nonmutating set { session.preparedScanImage = newValue }
    }

    private var usePreparedScanImage: Bool {
        get { session.usePreparedScanImage }
        nonmutating set { session.usePreparedScanImage = newValue }
    }

    private var selectedImageSourcePath: String? {
        get { session.selectedImageSourcePath }
        nonmutating set { session.selectedImageSourcePath = newValue }
    }

    private var previewPairPendingDeletion: ImportPreviewPair? {
        get { session.previewPairPendingDeletion }
        nonmutating set { session.previewPairPendingDeletion = newValue }
    }

    private var detectedScanMode: ScanMode {
        get { session.detectedScanMode }
        nonmutating set { session.detectedScanMode = newValue }
    }

    private var scanModeOverride: ScanMode? {
        get { session.scanModeOverride }
        nonmutating set { session.scanModeOverride = newValue }
    }

    private var lastRecognizedBoxes: [OCRLineBox] {
        get { session.lastRecognizedBoxes }
        nonmutating set { session.lastRecognizedBoxes = newValue }
    }

    private var lastAnalysisPath: ScanAnalysisPath {
        get { session.lastAnalysisPath }
        nonmutating set { session.lastAnalysisPath = newValue }
    }

    private var lastScanWarnings: [String] {
        get { session.lastScanWarnings }
        nonmutating set { session.lastScanWarnings = newValue }
    }

    private var lastScanDurationMS: Int? {
        get { session.lastScanDurationMS }
        nonmutating set { session.lastScanDurationMS = newValue }
    }

    private var lastScanAIConfigured: Bool {
        get { session.lastScanAIConfigured }
        nonmutating set { session.lastScanAIConfigured = newValue }
    }

    private var lastScanImportDebugMessage: String {
        get { session.lastScanImportDebugMessage }
        nonmutating set { session.lastScanImportDebugMessage = newValue }
    }

    private var scanEvalSuiteReport: ScanEvalSuiteReport? {
        get { session.scanEvalSuiteReport }
        nonmutating set { session.scanEvalSuiteReport = newValue }
    }

    private var reviewSummary: String {
        get { session.reviewSummary }
        nonmutating set { session.reviewSummary = newValue }
    }

    private var reviewScrollTrigger: Int {
        get { session.reviewScrollTrigger }
        nonmutating set { session.reviewScrollTrigger = newValue }
    }

    private var hasPendingPreviewEdits: Bool {
        get { session.hasPendingPreviewEdits }
        nonmutating set { session.hasPendingPreviewEdits = newValue }
    }

    private var listNameBinding: Binding<String> {
        Binding(
            get: { listName },
            set: { listName = $0 }
        )
    }

    private var showingCameraBinding: Binding<Bool> {
        Binding(
            get: { showingCamera },
            set: { showingCamera = $0 }
        )
    }

    private var showingPhotoLibraryBinding: Binding<Bool> {
        Binding(
            get: { showingPhotoLibrary },
            set: { showingPhotoLibrary = $0 }
        )
    }

    private var showingImagePreviewBinding: Binding<Bool> {
        Binding(
            get: { showingImagePreview },
            set: { showingImagePreview = $0 }
        )
    }

    private var showingScanPreparationBinding: Binding<Bool> {
        Binding(
            get: { showingScanPreparation },
            set: { showingScanPreparation = $0 }
        )
    }

    private var showingAdditionalScanOptionsBinding: Binding<Bool> {
        Binding(
            get: { showingAdditionalScanOptions },
            set: { showingAdditionalScanOptions = $0 }
        )
    }

    private var isShowingScanAIInfoAlertBinding: Binding<Bool> {
        Binding(
            get: { isShowingScanAIInfoAlert },
            set: { isShowingScanAIInfoAlert = $0 }
        )
    }

    private var listNameFieldBackground: Color {
        if isListNameFocused {
            return AppTheme.Colors.primary.opacity(0.16)
        }

        return AppTheme.Colors.success.opacity(isListNamePulseActive ? 0.28 : 0.18)
    }

    private var listNameFieldBorder: Color {
        if isListNameFocused {
            return AppTheme.Colors.primary.opacity(0.72)
        }

        return AppTheme.Colors.success.opacity(isListNamePulseActive ? 0.88 : 0.56)
    }

    private var listNameFieldIcon: String {
        isListNameFocused ? "pencil.circle.fill" : "checkmark.circle.fill"
    }

    private var scanProgressText: String {
        "Analysiere" + String(repeating: ".", count: scanProgressStep + 1)
    }

    private var scanProgressRuntimeLabel: String {
        switch scanRuntimeStage {
        case .idle, .ocrPreflight:
            return "OCR lokal"
        case .aiConnecting:
            return "KI wird kontaktiert"
        case .aiPrimary:
            return "KI analysiert"
        case .ocrFallback:
            return "OCR-Fallback"
        }
    }

    private var scanProgressRuntimeTint: Color {
        switch scanRuntimeStage {
        case .idle, .ocrPreflight:
            return AppTheme.Colors.textSecondary
        case .aiConnecting:
            return AppTheme.Colors.warning
        case .aiPrimary:
            return AppTheme.Colors.primary
        case .ocrFallback:
            return AppTheme.Colors.warning
        }
    }

    private var scanProgressRuntimeIcon: String {
        switch scanRuntimeStage {
        case .idle, .ocrPreflight:
            return "doc.text.viewfinder"
        case .aiConnecting:
            return "antenna.radiowaves.left.and.right"
        case .aiPrimary:
            return "sparkles"
        case .ocrFallback:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var hasAlternatePreparedImage: Bool {
        guard let originalScanImage, let preparedScanImage else { return false }
        return ScanImageLifecycle.fingerprint(for: originalScanImage) !=
            ScanImageLifecycle.fingerprint(for: preparedScanImage)
    }

    private var selectedAppDirection: Direction {
        Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman
    }

    private var activeScanMode: ScanMode {
        scanModeOverride ?? detectedScanMode
    }

    private var hasRecognizedContent: Bool {
        !previewPairs.isEmpty
    }

    private var hasActiveScanDraft: Bool {
        selectedImage != nil ||
        !lastRecognizedBoxes.isEmpty ||
        !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !previewPairs.isEmpty
    }

    private var analysisPathDebugLabel: String {
        switch lastAnalysisPath {
        case .ocrOnly:
            return "OCR"
        case .aiAssisted:
            return "KI"
        case .hybrid:
            return "OCR + KI"
        }
    }

    private var analysisPathDebugTint: Color {
        switch lastAnalysisPath {
        case .ocrOnly:
            return AppTheme.Colors.textSecondary
        case .aiAssisted:
            return AppTheme.Colors.primary
        case .hybrid:
            return AppTheme.Colors.success
        }
    }

    private var hasScanDevDebugInfo: Bool {
        #if DEBUG
        return lastScanDurationMS != nil || !lastScanWarnings.isEmpty || !lastScanImportDebugMessage.isEmpty
        #else
        return false
        #endif
    }

    private var scanDurationDebugLabel: String? {
        guard let lastScanDurationMS else { return nil }
        if lastScanDurationMS >= 1000 {
            return String(format: "%.1fs", Double(lastScanDurationMS) / 1000)
        }
        return "\(lastScanDurationMS)ms"
    }

    private var completePreviewPairCount: Int {
        importablePreviewPairs.filter {
            !sanitizedLine($0.french).isEmpty && !sanitizedLine($0.german).isEmpty
        }.count
    }

    private var incompletePreviewPairCount: Int {
        max(importablePreviewPairs.count - completePreviewPairCount, 0)
    }

    private var importablePreviewPairs: [ImportPreviewPair] {
        previewPairs.filter(\.isImportable)
    }

    private var recognizedContextPreviewCount: Int {
        previewPairs.filter { $0.learningCategory == .recognizedText }.count
    }

    private var previewCounterLabel: String {
        if activeScanMode == .text {
            if recognizedContextPreviewCount > 0 {
                return "\(completePreviewPairCount) Lernkarten · \(recognizedContextPreviewCount) Text"
            }
            return "\(completePreviewPairCount) Lernkarten"
        }

        return "\(completePreviewPairCount)/\(previewPairs.count) Einträge"
    }

    private var freeTextCategoryCounts: [(ScanLearningCategory, Int)] {
        ScanLearningCategory.allCases.compactMap { category in
            let count = previewPairs.filter { $0.learningCategory == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    private var hasScanEvalDebugReport: Bool {
        #if DEBUG
        guard let scanEvalSuiteReport else { return false }
        return !scanEvalSuiteReport.reports.isEmpty
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ScreenHeaderCard(
                        style: sectionStyle,
                        title: "Scan",
                        subtitle: "",
                        systemImage: "camera.viewfinder"
                    )

                    if hasActiveScanDraft {
                        Button {
                            returnToScanSetup()
                        } label: {
                            Label("Zurück", systemImage: "arrow.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))
                        .disabled(isRecognizingImage)
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            scanModeSelectionCard

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                HStack(spacing: 10) {
                                    Button {
                                        guard !isRecognizingImage else { return }
                                        guard UIImagePickerController.isSourceTypeAvailable(.camera) || VNDocumentCameraViewController.isSupported else { return }
                                        shouldAppendNextScan = false
                                        selectedScanInputMethod = .camera
                                        openCameraScanner()
                                    } label: {
                                        scanSymbolButtonCard(
                                            systemImage: "camera.fill",
                                            title: "Foto",
                                            isSelected: selectedScanInputMethod == .camera
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .allowsHitTesting(!isRecognizingImage && (UIImagePickerController.isSourceTypeAvailable(.camera) || VNDocumentCameraViewController.isSupported))
                                    .opacity((UIImagePickerController.isSourceTypeAvailable(.camera) || VNDocumentCameraViewController.isSupported) ? 1 : 0.5)

                                    Button {
                                        guard !isRecognizingImage else { return }
                                        shouldAppendNextScan = false
                                        selectedScanInputMethod = .library
                                        showingPhotoLibrary = true
                                    } label: {
                                        scanSymbolButtonCard(
                                            systemImage: "photo.on.rectangle.fill",
                                            title: "Aufnahme",
                                            isSelected: selectedScanInputMethod == .library
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .allowsHitTesting(!isRecognizingImage)
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .appCardBackground(sectionStyle, intensity: 0.09)

                            if !previewPairs.isEmpty {
                                previewCard
                                    .id(Self.reviewAnchorID)
                                scanImportDetailsCard

                                Button {
                                    importScannedText()
                                } label: {
                                    Label("Importieren", systemImage: "square.and.arrow.down.fill")
                                        .font(AppTheme.Typography.button)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                }
                                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                                .disabled(completePreviewPairCount == 0)
                            }

                            if let selectedImage {
                                Button {
                                    showingImagePreview = true
                                } label: {
                                    ZStack {
                                        Image(uiImage: selectedImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: 220, maxHeight: 320)

                                        if isRecognizingImage {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(Color.black.opacity(0.12))

                                            scanProgressPopupView
                                                .padding(.horizontal, 18)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .appCardBackground(sectionStyle, intensity: 0.09)
                            }

                            if !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    showingAdditionalScanOptions = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "plus.viewfinder")
                                            .font(.system(size: 20, weight: .bold))
                                        Text("Noch mehr einlesen")
                                            .font(AppTheme.Typography.button)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                }
                                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                            }

                            if !isRecognizingImage {
                                Text(importMessage)
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.bottom, 8 + scanKeyboardBottomPadding)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }

                if isShowingScanToast {
                    scanToastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, AppLayout.screenPadding)
                        .padding(.bottom, 74)
                }

            }
            .onChange(of: reviewScrollTrigger) { _, _ in
                guard !previewPairs.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(Self.reviewAnchorID, anchor: .top)
                }
            }
            .onChange(of: focusedReviewField) { _, focus in
                guard let focus else {
                    commitPreviewEditsAndSyncImportText()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(
                            reviewFieldScrollID(for: focus),
                            anchor: reviewFieldScrollAnchor(for: focus)
                        )
                    }
                }
            }
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.22), value: isShowingScanToast)
        .animation(.easeInOut(duration: 0.18), value: isRecognizingImage)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() },
                isScanActive: true
            )
        }
        .onAppear {
            scanSourceLanguage = .french
            ensureSuggestedListName()
            refreshPreviewPairsFromImportText()
        }
        .onDisappear {
            stopScanProgressFeedback()
            scanKeyboardInset = 0
            previewEditSyncWorkItem?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateScanKeyboardInset(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                scanKeyboardInset = 0
            }
        }
        .onChange(of: importText) { _, newValue in
            if isSyncingPreviewToText {
                isSyncingPreviewToText = false
                return
            }

            previewPairs = parsePreviewPairs(from: newValue)
        }
        .onChange(of: scanSourceLanguage) { _, _ in
            refreshPreviewPairsFromImportText()
        }
        .onChange(of: selectedAppDirectionRaw) { _, _ in
            scanSourceLanguage = .french
            refreshPreviewPairsFromImportText()
        }
        .onChange(of: isShowingImportCompletion) { _, isPresented in
            guard !isPresented, let pendingCompletionDestination else { return }
            self.pendingCompletionDestination = nil
            DispatchQueue.main.async {
                navigate(pendingCompletionDestination)
            }
        }
        .navigationDestination(isPresented: $isShowingImportCompletion) {
            if let importCompletionContext {
                ImportCompletionView(
                    context: importCompletionContext,
                    onTrain: {
                        handleCompletionSelection(.train(importCompletionContext.trainingLaunchContext))
                    },
                    onFlashcards: {
                        handleCompletionSelection(.flashcards(importCompletionContext.flashcardLaunchContext))
                    },
                    onLists: {
                        handleCompletionSelection(.lists(importCompletionContext.listLaunchContext))
                    },
                    onLater: {
                        handleCompletionSelection(nil)
                    }
                )
            }
        }
        .sheet(isPresented: showingCameraBinding) {
            if VNDocumentCameraViewController.isSupported {
                DocumentScanner { image, sourcePath in
                    handleSelectedImage(image, sourcePath: sourcePath)
                }
            } else {
                ImagePicker(sourceType: .camera) { image, sourcePath in
                    handleSelectedImage(image, sourcePath: sourcePath)
                }
            }
        }
        .sheet(isPresented: showingPhotoLibraryBinding) {
            ImagePicker(sourceType: .photoLibrary) { image, sourcePath in
                handleSelectedImage(image, sourcePath: sourcePath)
            }
        }
        .sheet(isPresented: showingImagePreviewBinding) {
            if let selectedImage {
                imagePreviewSheet(for: selectedImage)
            }
        }
        .fullScreenCover(item: $manualCropSession) { session in
            ManualCropSheet(
                image: session.image,
                accent: sectionStyle.accent,
                onCancel: {
                    handleManualCropCancel()
                },
                onApply: { croppedImage, shouldAnalyzeImmediately in
                    applyManualCrop(croppedImage, shouldAnalyzeImmediately: shouldAnalyzeImmediately)
                }
            )
        }
        .sheet(isPresented: showingScanPreparationBinding) {
            if let previewImage = scanPreparationPreviewImage {
                scanPreparationSheet(previewImage: previewImage)
            }
        }
        .confirmationDialog("Noch mehr einlesen", isPresented: showingAdditionalScanOptionsBinding, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Foto machen") {
                    shouldAppendNextScan = true
                    openCameraScanner()
                }
            }

            Button("Bild wählen") {
                shouldAppendNextScan = true
                showingPhotoLibrary = true
            }

            Button("Abbrechen", role: .cancel) {
                shouldAppendNextScan = false
            }
        } message: {
            Text("Der nächste Scan wird an die aktuelle Liste angehängt.")
        }
        .alert("Wirklich löschen?", isPresented: Binding(
            get: { previewPairPendingDeletion != nil },
            set: { if !$0 { previewPairPendingDeletion = nil } }
        )) {
            Button("Nein", role: .cancel) {
                previewPairPendingDeletion = nil
            }
            Button("Ja", role: .destructive) {
                if let previewPairPendingDeletion {
                    previewPairs.removeAll { $0.id == previewPairPendingDeletion.id }
                    syncImportTextFromPreview()
                    self.previewPairPendingDeletion = nil
                }
            }
        } message: {
            Text(previewPairPendingDeletion.map { "„\($0.french)“ wird entfernt." } ?? "")
        }
        .alert("Hinweis", isPresented: isShowingScanAIInfoAlertBinding) {
            if canRetryCurrentScanAfterAIAlert {
                Button("Nochmal versuchen") {
                    retryCurrentScanAfterAIAlert()
                }
            }
            Button("OK", role: .cancel) {
                scanAIInfoMessage = ""
            }
        } message: {
            Text(scanAIInfoMessage)
        }
    }

    private var scanCollectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ordner")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ListCollectionPreset.allCases) { preset in
                    Button {
                        selectedCollectionPreset = preset
                    } label: {
                        HStack {
                            Text(preset.rawValue)
                                .font(AppTheme.Typography.body)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(selectedCollectionPreset == preset ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                        .foregroundStyle(selectedCollectionPreset == preset ? .white : AppTheme.Colors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    selectedCollectionPreset = .other
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(AppTheme.Colors.secondarySurface)
                        .foregroundStyle(sectionStyle.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var listNameInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name der Liste")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                Image(systemName: listNameFieldIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isListNameFocused ? AppTheme.Colors.warning : AppTheme.Colors.success)

                TextField("Zum Beispiel: Unit 3", text: listNameBinding)
                    .font(AppTheme.Typography.body)
                    .textFieldStyle(.plain)
                    .focused($isListNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        confirmListNameEntry()
                    }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(listNameFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(listNameFieldBorder, lineWidth: isListNamePulseActive ? 2.5 : 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isListNamePulseActive ? 1.015 : 1)
            .animation(.easeInOut(duration: 0.18), value: isListNameFocused)
            .animation(.easeInOut(duration: 0.16), value: isListNamePulseActive)
        }
    }

    private var scanImportDetailsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            listNameInputCard
            scanCollectionCard
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    private func confirmListNameEntry() {
        listName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        isListNameFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        withAnimation(.easeInOut(duration: 0.12)) {
            isListNamePulseActive = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.16)) {
                isListNamePulseActive = false
            }
        }
    }

    private func openCameraScanner() {
        guard !isRecognizingImage else { return }
        showingAdditionalScanOptions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingCamera = true
        }
    }

    private func restartCurrentScan() {
        guard !isRecognizingImage else { return }
        guard let imageToAnalyze = scanPreparationPreviewImage ?? selectedImage else { return }
        shouldAppendNextScan = false
        prepareForRescanDisplay()
        recognizeText(from: imageToAnalyze)
    }

    private func retryCurrentScanAfterAIAlert() {
        isShowingScanAIInfoAlert = false
        scanAIInfoMessage = ""
        restartCurrentScan()
    }

    private func prepareForRescanDisplay() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        focusedReviewField = nil
        previewEditSyncWorkItem?.cancel()
        previewEditSyncWorkItem = nil
        hasPendingPreviewEdits = false
        session.prepareForRescanDisplay()
    }

    private var scanPreparationPreviewImage: UIImage? {
        if usePreparedScanImage {
            return preparedScanImage ?? originalScanImage
        }
        return originalScanImage ?? preparedScanImage
    }

    @ViewBuilder
    private func scanPreparationSheet(previewImage: UIImage) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Bild prüfen",
                leadingTitle: "Abbrechen",
                leadingTint: AppTheme.Colors.textSecondary,
                onLeading: {
                    showingScanPreparation = false
                    shouldAppendNextScan = false
                }
            )

            Button {
                presentManualCrop(from: previewImage, target: ManualCropTarget.scanPreparation)
            } label: {
                Label("Zuschneiden", systemImage: "crop")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 42)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))
            .padding(.top, 6)

            if hasAlternatePreparedImage {
                HStack(spacing: 10) {
                    Button {
                        usePreparedScanImage = true
                    } label: {
                        Text("Zugeschnitten")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 42)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(usePreparedScanImage ? .white : AppTheme.Colors.textPrimary)
                            .background(usePreparedScanImage ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        usePreparedScanImage = false
                    } label: {
                        Text("Original")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 42)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(!usePreparedScanImage ? .white : AppTheme.Colors.textPrimary)
                            .background(!usePreparedScanImage ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                let imageToAnalyze = scanPreparationPreviewImage ?? previewImage
                showingScanPreparation = false
                recognizeText(from: imageToAnalyze)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Analysieren")
                        .font(AppTheme.Typography.button)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(hasAlternatePreparedImage ? "Prüfe kurz, ob der Zuschnitt stimmt. Danach startet die Analyse." : "Prüfe das Bild kurz. Danach startet die Analyse.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
    }

    private func presentManualCrop(from image: UIImage, target: ManualCropTarget) {
        showingScanPreparation = false
        showingImagePreview = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            manualCropSession = ManualCropSession(image: image, target: target)
        }
    }

    private func handleManualCropCancel() {
        let target = manualCropSession?.target
        manualCropSession = nil
        guard let target else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch target {
            case .scanPreparation:
                showingScanPreparation = true
            case .imagePreview:
                showingImagePreview = true
            }
        }
    }

    private func applyManualCrop(_ croppedImage: UIImage, shouldAnalyzeImmediately: Bool) {
        let target = manualCropSession?.target
        manualCropSession = nil
        let ocrReadyCrop = normalizedImageForProcessing(
            croppedImage,
            maxLongEdge: Self.maxOCRLongEdge
        )
        selectedImage = downscaledImageForDisplay(
            ocrReadyCrop,
            maxLongEdge: Self.maxPreviewLongEdge
        ) ?? ocrReadyCrop
        guard let target else { return }

        switch target {
        case .scanPreparation:
            preparedScanImage = ocrReadyCrop
            usePreparedScanImage = true
            if shouldAnalyzeImmediately {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    recognizeText(from: ocrReadyCrop)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingScanPreparation = true
                }
            }
        case .imagePreview:
            preparedScanImage = ocrReadyCrop
            usePreparedScanImage = true
            if shouldAnalyzeImmediately {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    recognizeText(from: ocrReadyCrop)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingImagePreview = true
                }
            }
        }
    }

    private func scanSymbolButtonCard(systemImage: String, title: String, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : sectionStyle.accent)

            Text(title)
                .font(AppTheme.Typography.body)
                .foregroundStyle(isSelected ? Color.white : AppTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 50, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? sectionStyle.accent : AppTheme.Colors.secondarySurface)

                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(0.24) : AppTheme.Colors.border,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(isSelected ? 1.015 : 1)
        .shadow(
            color: isSelected ? sectionStyle.accent.opacity(0.34) : .clear,
            radius: isSelected ? 16 : 0,
            x: 0,
            y: isSelected ? 8 : 0
        )
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var scanModeSelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was möchtest du scannen?")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            HStack(spacing: 10) {
                ForEach(ScanMode.allCases) { mode in
                    Button {
                        selectScanMode(mode)
                    } label: {
                        scanSymbolButtonCard(
                            systemImage: mode.systemImage,
                            title: mode.title,
                            isSelected: activeScanMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    private var scanTypeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typ")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(CardType.allCases) { item in
                    Button {
                        importType = item
                    } label: {
                        Text(item.rawValue)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 40)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(importType == item ? .white : AppTheme.Colors.textPrimary)
                            .background(importType == item ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Review")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if canRescanCurrentSelection {
                    Button {
                        restartCurrentScan()
                    } label: {
                        Label("Erneut scannen", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .foregroundStyle(sectionStyle.accent)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(sectionStyle.accent.opacity(0.10))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(sectionStyle.accent.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRecognizingImage)
                    .opacity(isRecognizingImage ? 0.55 : 1)
                }

                Spacer()

                Text(previewCounterLabel)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Text(reviewSummary)
                .font(isCompactReviewSummary ? .system(size: 11, weight: .medium, design: .rounded) : AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(isCompactReviewSummary ? 1 : nil)
                .minimumScaleFactor(isCompactReviewSummary ? 0.68 : 1)
                .fixedSize(horizontal: false, vertical: !isCompactReviewSummary)

            HStack(spacing: 8) {
                if !previewPairs.isEmpty {
                    modeBadge(analysisPathDebugLabel, tint: analysisPathDebugTint)
                }
                if incompletePreviewPairCount > 0 {
                    modeBadge("\(incompletePreviewPairCount) offen", tint: AppTheme.Colors.warning)
                }
                Spacer(minLength: 0)
            }

            if activeScanMode == .text && !freeTextCategoryCounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(freeTextCategoryCounts, id: \.0) { category, count in
                            modeBadge("\(category.title) \(count)", tint: learningCategoryTint(category))
                        }
                    }
                }
            }

            if hasScanDevDebugInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        modeBadge("DEV DEBUG", tint: AppTheme.Colors.warning)
                        modeBadge(analysisPathDebugLabel, tint: analysisPathDebugTint)
                        if let scanDurationDebugLabel {
                            modeBadge(scanDurationDebugLabel, tint: AppTheme.Colors.primary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI konfiguriert: \(lastScanAIConfigured ? "ja" : "nein")")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        if !lastScanWarnings.isEmpty {
                            Text("Warnings: \(lastScanWarnings.joined(separator: ", "))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !lastScanImportDebugMessage.isEmpty {
                            Text(lastScanImportDebugMessage)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(AppTheme.Colors.secondarySurface.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if hasScanEvalDebugReport, let scanEvalSuiteReport {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        modeBadge(
                            scanEvalSuiteReport.passed ? "DEV EVAL PASS" : "DEV EVAL FAIL",
                            tint: scanEvalSuiteReport.passed ? AppTheme.Colors.success : AppTheme.Colors.warning
                        )

                        if let fixtureImagePath = scanEvalSuiteReport.fixtureImagePath {
                            Text((fixtureImagePath as NSString).lastPathComponent)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    ForEach(scanEvalSuiteReport.reports, id: \.fixtureID) { report in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.title)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text(report.summary)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(report.passed ? AppTheme.Colors.success : AppTheme.Colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(AppTheme.Colors.secondarySurface.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if isEditingReviewField {
                previewListContent
            } else {
                ScrollView {
                    previewListContent
                }
                .frame(maxHeight: 320)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    private var canRescanCurrentSelection: Bool {
        scanPreparationPreviewImage != nil || selectedImage != nil
    }

    private var canRetryCurrentScanAfterAIAlert: Bool {
        canRescanCurrentSelection && !isRecognizingImage
    }

    private var isCompactReviewSummary: Bool {
        reviewSummary.hasPrefix("Die Vorlage wurde")
    }

    private var scanProgressPopupView: some View {
        scanProgressView
            .frame(maxWidth: 280)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    @ViewBuilder
    private var previewListContent: some View {
        if activeScanMode == .text {
            freeTextPreviewList
        } else {
            standardPreviewList
        }
    }

    private var standardPreviewList: some View {
        VStack(spacing: 8) {
            ForEach(visiblePreviewPairs) { pair in
                editablePreviewRow(for: pair)
            }
        }
    }

    private var freeTextPreviewList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ScanLearningCategory.allCases, id: \.self) { category in
                let categoryPairs = visiblePreviewPairs.filter { $0.learningCategory == category }
                if !categoryPairs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(category.title)
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            modeBadge("\(categoryPairs.count)", tint: learningCategoryTint(category))
                        }

                        VStack(spacing: 8) {
                            ForEach(categoryPairs) { pair in
                                if pair.isImportable {
                                    editablePreviewRow(for: pair, category: category)
                                } else {
                                    recognizedTextPreviewRow(for: pair, category: category)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editablePreviewRow(
        for pair: ImportPreviewPair,
        category: ScanLearningCategory? = nil
    ) -> some View {
        let assessment = previewAssessment(for: pair)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(scanSourceLanguage.rawValue)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        modeBadge(
                            pair.cardType.rawValue,
                            tint: pair.cardType == .phrases ? AppTheme.Colors.moduleQuiz : sectionStyle.accent
                        )

                        if let category {
                            modeBadge(category.title, tint: learningCategoryTint(category))
                        }
                    }

                    TextField(scanSourceLanguage.rawValue, text: Binding(
                        get: { bindingValue(for: pair.id)?.french ?? "" },
                        set: { newValue in
                            updatePreviewPairForEditing(pair.id) {
                                $0.french = extractedDisplayTerm(from: newValue)
                                $0.isReviewed = false
                            }
                            schedulePreviewEditCommit()
                        }
                    ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .id(reviewFieldScrollID(for: .source(pair.id)))
                    .focused($focusedReviewField, equals: .source(pair.id))

                    Text("Deutsch")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    TextField("Deutsch", text: Binding(
                        get: { bindingValue(for: pair.id)?.german ?? "" },
                        set: { newValue in
                            updatePreviewPairForEditing(pair.id) {
                                $0.german = extractedDisplayTerm(from: newValue)
                                $0.isReviewed = false
                            }
                            schedulePreviewEditCommit()
                        }
                    ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .id(reviewFieldScrollID(for: .target(pair.id)))
                    .focused($focusedReviewField, equals: .target(pair.id))
                }

                HStack(spacing: 8) {
                    if assessment == .suspicious {
                        Button {
                            updatePreviewPair(pair.id) { $0.isReviewed = true }
                            focusedReviewField = nil
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                        } label: {
                            Text("OK")
                                .font(AppTheme.Typography.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.success)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.Colors.success.opacity(0.16))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        previewPairPendingDeletion = pair
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            if let note = pair.note, !note.isEmpty {
                Text(note)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            if assessment == .suspicious {
                Text("Unsicher, bitte prüfen.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.warning)
            } else if assessment == .incomplete {
                Text("Unvollständig.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .id(pair.id)
        .padding(10)
        .background(previewAssessmentBackground(for: assessment))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(previewAssessmentBorder(for: assessment), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func recognizedTextPreviewRow(
        for pair: ImportPreviewPair,
        category: ScanLearningCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                modeBadge(category.title, tint: learningCategoryTint(category))
                Spacer()
            }

            Text(pair.french)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !pair.german.isEmpty {
                Text(pair.german)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Nur Kontext, wird nicht importiert.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(10)
        .background(AppTheme.Colors.secondarySurface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modeBadge(_ title: String, tint: Color = AppTheme.Colors.primary) -> some View {
        Text(title)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

    private func learningCategoryTint(_ category: ScanLearningCategory) -> Color {
        switch category {
        case .recognizedText:
            return AppTheme.Colors.primary
        case .verbs:
            return AppTheme.Colors.success
        case .phrases:
            return AppTheme.Colors.moduleQuiz
        case .grammar:
            return AppTheme.Colors.warning
        }
    }

    private func importScannedText() {
        commitPreviewEditsAndSyncImportText()
        let activeListStore = listStore ?? ensureListStoreReady()
        let items = previewPairs
            .filter(\.isImportable)
            .compactMap { pair in
            scanVocabularyItemFactory.makeVocabularyItem(
                french: pair.french,
                german: pair.german,
                cardType: pair.cardType,
                sourceLanguage: scanSourceLanguage
            )
            }
        let importedItemIDs = items.map(\.id)
        let trimmedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetListID = activeListStore.ensureCustomList(
            named: trimmedListName.isEmpty ? activeListStore.suggestedListName(from: "Scan") : trimmedListName,
            collectionPreset: selectedCollectionPreset
        )
        let importedCount = activeListStore.importItems(
            items,
            preferredListID: targetListID,
            suggestedListName: trimmedListName.isEmpty ? "Scan" : trimmedListName,
            collectionPreset: selectedCollectionPreset
        )

        if importedCount == 0 {
            importMessage = "Keine Paare erkannt. Nutze pro Zeile ein Trennzeichen wie `=` oder `→`."
            return
        }

        let targetListName = activeListStore.selectedList.name
        importMessage = "\(importedCount) Einträge in „\(targetListName)“ importiert."
        importCompletionContext = ImportCompletionContext(
            importedCount: importedCount,
            targetListID: targetListID,
            targetListName: targetListName,
            language: scanSourceLanguage,
            preferredDirection: scanSourceLanguage.defaultDirectionToGerman,
            cardType: dominantImportedCardType(in: items),
            importedItemIDs: importedItemIDs
        )
        resetScanInputAfterSuccessfulImport(keepingListName: false)
        isShowingImportCompletion = true
    }

    private func dominantImportedCardType(in items: [VocabularyItem]) -> CardType {
        let phraseCount = items.filter { $0.cardType == .phrases }.count
        let wordCount = items.count - phraseCount
        return phraseCount > wordCount ? .phrases : .words
    }

    private var visiblePreviewPairs: [ImportPreviewPair] {
        scanPreviewAssessor.visiblePreviewPairs(
            from: previewPairs,
            sourceLanguage: scanSourceLanguage
        )
    }

    private var isEditingReviewField: Bool {
        focusedReviewField != nil
    }

    private func reviewFieldScrollID(for focus: ReviewFieldFocus) -> String {
        switch focus {
        case .source(let id):
            return "scan-review-source-\(id.uuidString)"
        case .target(let id):
            return "scan-review-target-\(id.uuidString)"
        }
    }

    private func reviewFieldScrollAnchor(for focus: ReviewFieldFocus) -> UnitPoint {
        switch focus {
        case .source:
            return .top
        case .target:
            return scanKeyboardInset > 0 ? .center : .top
        }
    }

    private var scanKeyboardBottomPadding: CGFloat {
        guard scanKeyboardInset > 0 else { return 0 }
        return scanKeyboardInset + AppTheme.Spacing.md
    }

    private func updateScanKeyboardInset(from notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - frame.minY - windowSafeAreaBottomInset)
        withAnimation(.easeInOut(duration: 0.22)) {
            scanKeyboardInset = overlap
        }
    }

    private var windowSafeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    private func analyzeRecognizedScan(
        from lineBoxes: [OCRLineBox],
        preferredMode: ScanMode?
    ) -> ScanAnalysisResult {
        scanOCRAnalyzer.analyze(from: lineBoxes, preferredMode: preferredMode)
    }

    private func applyRecognizedScanAnalysis(_ analysis: ScanAnalysisResult, appending: Bool) {
        let applicationState = ScanStateCoordinator.makeAnalysisApplicationState(
            from: analysis,
            existingPreviewPairs: previewPairs,
            appending: appending,
            currentImportText: importText,
            deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) },
            prepareFreeTextPreviewPairs: { previewPairs, recognizedLines, sourceLanguage in
                freeTextPostProcessor.prepare(
                    seedEntries: previewPairs,
                    recognizedLines: recognizedLines,
                    sourceLanguage: sourceLanguage
                )
            },
            freeTextReviewSummary: { previewPairs, fallback in
                freeTextPostProcessor.reviewSummary(from: previewPairs, fallback: fallback)
            },
            importTextFromPreviewPairs: { previewPairs in
                scanPreviewTextBridge.importText(from: previewPairs)
            }
        )
        session.applyAnalysisApplicationState(applicationState)
    }

    private var freeTextPostProcessor: ScanFreeTextPostProcessor {
        ScanFreeTextPostProcessor(
            dependencies: ScanFreeTextPostProcessorDependencies(
                extractDisplayTerm: { extractedDisplayTerm(from: $0) },
                normalizedWords: { normalizedWords(in: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) },
                lexiconPreviewPairs: { text, sourceLanguage in
                    scanPreviewBuilder.lexiconPreviewPairs(from: text, sourceLanguage: sourceLanguage)
                },
                canonicalizeSourceTerm: { text, sourceLanguage in
                    canonicalizedSourceTermIfNeeded(text, sourceLanguage: sourceLanguage)
                },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) }
            )
        )
    }

    private var scanOCRNoiseFilter: ScanOCRNoiseFilter {
        ScanOCRNoiseFilter(
            dependencies: ScanOCRNoiseFilterDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isStandalonePedagogicalMarker: { isStandalonePedagogicalMarker($0) },
                normalizedWords: { normalizedWords(in: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                sourceLexiconCoverageScore: {
                    sourceLexiconCoverageScore(for: $0, language: scanSourceLanguage)
                },
                isLikelyMarkerNoise: { isLikelyMarkerNoise($0) },
                sourceLanguageScore: { sourceLanguageScore(for: $0, language: scanSourceLanguage) },
                germanScore: { germanScore(for: $0) }
            )
        )
    }

    private var scanVocabularyPairRepair: ScanVocabularyPairRepair {
        ScanVocabularyPairRepair(
            dependencies: ScanVocabularyPairRepairDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) },
                sourceLanguageScore: { text, language in
                    sourceLanguageScore(for: text, language: language)
                },
                germanScore: { germanScore(for: $0) },
                dictionaryCoverageScore: { text, language in
                    dictionaryCoverageScore(for: text, language: language)
                },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                sourceLexiconCoverageScore: { text, language in
                    sourceLexiconCoverageScore(for: text, language: language)
                },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedWords: { normalizedWords(in: $0) },
                inferredCardType: { source, target in
                    inferredCardType(forSource: source, target: target)
                },
                canonicalizedGermanTargetIfNeeded: { target, source, cardType, sourceLanguage in
                    canonicalizedGermanTargetIfNeeded(
                        target,
                        source: source,
                        cardType: cardType,
                        sourceLanguage: sourceLanguage
                    )
                },
                germanDisplayText: { text, cardType, sourceHint in
                    germanDisplayText(text, cardType: cardType, sourceHint: sourceHint)
                },
                normalizedEnglishVerbMarker: { normalizedEnglishVerbMarker(in: $0) },
                scanStopWords: { scanStopWords(for: $0) },
                detectedTerminalSentencePunctuation: { detectedTerminalSentencePunctuation(from: $0) },
                inferredGermanTerminalSentencePunctuation: { text, cardType in
                    inferredGermanTerminalSentencePunctuation(text, cardType: cardType)
                }
            )
        )
    }

    private var scanColumnPairMatcher: ScanColumnPairMatcher {
        ScanColumnPairMatcher(
            dependencies: ScanColumnPairMatcherDependencies(
                bestVocabularyPairScore: { source, target, preferredLanguage in
                    bestVocabularyPairScore(
                        source: source,
                        target: target,
                        preferredLanguage: preferredLanguage
                    )
                },
                vocabularyPairPenalty: { semanticScore, pairTolerance in
                    vocabularyPairPenalty(for: semanticScore, pairTolerance: pairTolerance)
                },
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedWords: { normalizedWords(in: $0) },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) }
            )
        )
    }

    private var scanPreviewBuilder: ScanPreviewBuilder {
        ScanPreviewBuilder(
            dependencies: ScanPreviewBuilderDependencies(
                filteredVocabularyBoxes: { filteredVocabularyBoxes(from: $0) },
                makeColumnPairs: { boxes, preferredLanguage in
                    makeColumnPairs(from: boxes, preferredLanguage: preferredLanguage)
                },
                repairedVocabularyPairs: { pairs, sourceLanguage in
                    repairedVocabularyPairs(pairs, sourceLanguage: sourceLanguage)
                },
                makePreviewPair: { first, second in
                    makePreviewPair(first: first, second: second)
                },
                deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) },
                parsePreviewPairs: { parsePreviewPairs(from: $0) },
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedPreviewPair: { normalizedPreviewPair($0) },
                canonicalizedSourceTermIfNeeded: { text, sourceLanguage in
                    canonicalizedSourceTermIfNeeded(text, sourceLanguage: sourceLanguage)
                },
                looksLikeEnglishInfinitiveMarker: { looksLikeEnglishInfinitiveMarker($0) },
                normalizedEnglishVerbMarker: { normalizedEnglishVerbMarker(in: $0) },
                bestVocabularyPairScore: { source, target, preferredLanguage in
                    bestVocabularyPairScore(
                        source: source,
                        target: target,
                        preferredLanguage: preferredLanguage
                    )
                },
                sanitizedLine: { sanitizedLine($0) },
                stopWords: { scanStopWords(for: $0) },
                bestLexiconTranslation: { text, sourceLanguage in
                    DataStore.bestLexiconTranslation(for: text, sourceLanguage: sourceLanguage)
                }
            )
        )
    }

    private var scanPreviewPairParser: ScanPreviewPairParser {
        ScanPreviewPairParser(
            dependencies: ScanPreviewPairParserDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isStandalonePedagogicalMarker: { isStandalonePedagogicalMarker($0) },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) },
                inferredCardType: { source, target in
                    inferredCardType(forSource: source, target: target)
                },
                isSourceColumnFirst: { first, second in
                    isSourceColumnFirst(first: first, second: second)
                },
                isLikelyOrphanTargetPreviewLine: { line, sourceLanguage in
                    isLikelyOrphanTargetPreviewLine(line, sourceLanguage: sourceLanguage)
                },
                sanitizedLine: { sanitizedLine($0) },
                normalizedSourceImportTerm: { text, sourceLanguage in
                    normalizedSourceImportTerm(text, sourceLanguage: sourceLanguage)
                },
                canonicalizedGermanTargetIfNeeded: { target, source, cardType, sourceLanguage in
                    canonicalizedGermanTargetIfNeeded(
                        target,
                        source: source,
                        cardType: cardType,
                        sourceLanguage: sourceLanguage
                    )
                },
                synchronizedPairTerminalSentencePunctuation: { source, target, sourceLanguage, cardType in
                    synchronizedPairTerminalSentencePunctuation(
                        source: source,
                        target: target,
                        sourceLanguage: sourceLanguage,
                        cardType: cardType
                    )
                }
            )
        )
    }

    private var scanOCRAnalyzer: ScanOCRAnalyzer {
        ScanOCRAnalyzer(
            dependencies: ScanOCRAnalyzerDependencies(
                sourceLanguage: scanSourceLanguage,
                filteredVocabularyBoxes: { filteredVocabularyBoxes(from: $0) },
                makeColumnPairs: { boxes, preferredLanguage in
                    makeColumnPairs(from: boxes, preferredLanguage: preferredLanguage)
                },
                pairCandidateSelectionScore: { pairs, preferredLanguage in
                    scanPreviewBuilder.pairCandidateSelectionScore(
                        pairs,
                        preferredLanguage: preferredLanguage
                    )
                },
                listModePreviewPairs: { boxes, sourceLanguage in
                    scanPreviewBuilder.listModePreviewPairs(
                        from: boxes,
                        sourceLanguage: sourceLanguage
                    )
                },
                textModePreviewPairs: { lines, sourceLanguage in
                    scanPreviewBuilder.textModePreviewPairs(
                        from: lines,
                        sourceLanguage: sourceLanguage
                    )
                },
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) }
            )
        )
    }

    private func releaseScanWorkingImages() {
        session.releaseWorkingImages()
    }

    private func selectScanMode(_ mode: ScanMode) {
        guard activeScanMode != mode else { return }

        scanModeOverride = mode

        if lastRecognizedBoxes.isEmpty {
            importMessage = mode.introMessage
            reviewSummary = "Der Scan ist jetzt auf \(mode.title.lowercased()) eingestellt."
            return
        }

        reprocessLastRecognizedScan()
    }

    private func reprocessLastRecognizedScan() {
        guard !lastRecognizedBoxes.isEmpty else { return }
        let analysis = analyzeRecognizedScan(
            from: lastRecognizedBoxes,
            preferredMode: scanModeOverride
        )
        applyRecognizedScanAnalysis(analysis, appending: false)
    }

    private func scanStopWords(for language: StudyLanguage) -> Set<String> {
        switch language {
        case .french:
            return [
                "je", "tu", "il", "elle", "nous", "vous", "ils", "elles", "le", "la",
                "les", "un", "une", "des", "de", "du", "et", "ou", "à", "au", "aux",
                "dans", "sur", "avec", "pour", "mais", "ne", "pas", "que", "qui"
            ]
        case .english:
            return [
                "i", "you", "he", "she", "we", "they", "the", "a", "an", "and", "or",
                "to", "of", "in", "on", "at", "with", "for", "from", "is", "are"
            ]
        }
    }

    private func deduplicatedPreviewPairs(_ pairs: [ImportPreviewPair]) -> [ImportPreviewPair] {
        ScanReviewMapper.deduplicatedPreviewPairs(
            pairs,
            normalizedPreviewPair: { normalizedPreviewPair($0) },
            normalizedLookupText: { normalizedLookupText($0) },
            extractedDisplayTerm: { extractedDisplayTerm(from: $0) }
        )
    }

    private func parsePreviewPairs(from rawText: String) -> [ImportPreviewPair] {
        scanPreviewPairParser.parsePreviewPairs(
            from: rawText,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func splitLine(_ line: String) -> (String, String)? {
        scanPreviewPairParser.splitLine(line)
    }

    private func handleSelectedImage(_ image: UIImage?, sourcePath: String? = nil) {
        guard let image else {
            shouldAppendNextScan = false
            return
        }

        if !shouldAppendNextScan {
            session.discardDraftForReplacement(
                activeScanMode: activeScanMode,
                currentListName: listName,
                fallbackListName: listStore?.suggestedListName(from: "Scan") ?? "Scan"
            )
        }

        let selectionState = ScanImageLifecycle.makeSelectedImageState(
            from: image,
            sourcePath: sourcePath,
            maxAnalysisLongEdge: Self.maxOCRLongEdge,
            maxPreviewLongEdge: Self.maxPreviewLongEdge,
            normalizeForProcessing: { image, maxLongEdge in
                normalizedImageForProcessing(image, maxLongEdge: maxLongEdge)
            },
            downscaledForDisplay: { image, maxLongEdge in
                downscaledImageForDisplay(image, maxLongEdge: maxLongEdge)
            }
        )
        ensureSuggestedListName()
        session.applySelectedImageState(selectionState)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard manualCropSession == nil else { return }
            showingScanPreparation = true
        }
    }

    private func recognizeText(from image: UIImage) {
        isRecognizingImage = true
        startScanProgressFeedback()
        scanRuntimeStage = .ocrPreflight
        importMessage = "Text wird erkannt..."
        let appendToExistingPreview = shouldAppendNextScan
        let aiConfiguredForScan = OpenAIResponsesScanAIClient.fromEnvironment() != nil
        let scanStart = CFAbsoluteTimeGetCurrent()
        releaseScanWorkingImages()

        Task(priority: .userInitiated) {
            let analysisImage = await preparedImageForAnalysis(from: image)
            let request = ScanRequest(
                image: analysisImage,
                preparedImage: nil,
                preferredMode: scanModeOverride,
                sourceLanguage: scanSourceLanguage
            )

            let providerResult = await makeScanAnalysisEngine().analyze(request) { stage in
                await MainActor.run {
                    scanRuntimeStage = stage
                }
            }

            await MainActor.run {
                isRecognizingImage = false
                session.stopProgressFeedback()
                session.updateEvalReport(for: providerResult)
                session.updateProviderDebugInfo(
                    result: providerResult,
                    aiConfigured: aiConfiguredForScan,
                    durationMS: Int(((CFAbsoluteTimeGetCurrent() - scanStart) * 1000).rounded())
                )
                let gptFallbackInfoMessage = scanAIFallbackPopupMessage(
                    for: providerResult,
                    aiConfigured: aiConfiguredForScan
                )

                guard !providerResult.isEmpty else {
                    importMessage = providerResult.importMessage.isEmpty
                        ? "Der Text konnte aus dem Foto nicht erkannt werden."
                        : providerResult.importMessage
                    lastRecognizedBoxes = []
                    shouldAppendNextScan = false
                    if let gptFallbackInfoMessage {
                        session.presentScanAIInfo(gptFallbackInfoMessage)
                    }
                    return
                }

                lastRecognizedBoxes = providerResult.recognizedBoxes
                applyRecognizedScanAnalysis(
                    ScanReviewMapper.makeAnalysisResult(from: providerResult),
                    appending: appendToExistingPreview
                )
                shouldAppendNextScan = false
                if let gptFallbackInfoMessage {
                    session.presentScanAIInfo(gptFallbackInfoMessage)
                }
            }
        }
    }

    private func makeScanAnalysisEngine() -> ScanAnalysisEngine {
        ScanAnalysisFactory().makeEngine(
            analyzeRecognizedScan: { lineBoxes, preferredMode in
                analyzeRecognizedScan(from: lineBoxes, preferredMode: preferredMode)
            },
            extractLineBoxes: { image, sourceLanguage, includeGermanTargetLanguage, recognitionLevel, usesLanguageCorrection, customWordsLimit in
                extractOCRLineBoxes(
                    from: image,
                    sourceLanguage: sourceLanguage,
                    includeGermanTargetLanguage: includeGermanTargetLanguage,
                    recognitionLevel: recognitionLevel,
                    usesLanguageCorrection: usesLanguageCorrection,
                    customWordsLimit: customWordsLimit
                )
            },
            prepareFallbackImage: { image, maxLongEdge in
                fallbackPreparedImageForOCR(from: image, maxLongEdge: maxLongEdge)
            },
            downscaleImageForOCR: { image, maxLongEdge in
                downscaledImageForOCR(image, maxLongEdge: maxLongEdge)
            },
            maxFallbackLongEdge: Self.maxFallbackOCRLongEdge
        )
    }

    private var scanOCRLineExtractor: ScanOCRLineExtractor {
        ScanOCRLineExtractor(
            dependencies: ScanOCRLineExtractorDependencies(
                sanitizedLine: { sanitizedLine($0) }
            )
        )
    }

    private var scanOCRImagePreprocessor: ScanOCRImagePreprocessor {
        ScanOCRImagePreprocessor()
    }

    private var scanOCRTextSanitizer: ScanOCRTextSanitizer {
        ScanOCRTextSanitizer()
    }

    private var scanOCRTermExtractor: ScanOCRTermExtractor {
        ScanOCRTermExtractor(
            dependencies: ScanOCRTermExtractorDependencies(
                sanitizedLine: { sanitizedLine($0) },
                cleanedQuizDisplayText: { cleanedQuizDisplayText($0) },
                normalizedLookupWords: { normalizedLookupWords($0) },
                preservingTerminalSentencePunctuation: { original, text, cardType in
                    preservingTerminalSentencePunctuation(
                        from: original,
                        in: text,
                        style: .neutral,
                        cardType: cardType
                    )
                },
                sourceLexiconCoverageScore: { text, language in
                    sourceLexiconCoverageScore(for: text, language: language)
                },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedWords: { normalizedWords(in: $0) }
            )
        )
    }

    private var scanImportNormalizer: ScanImportNormalizer {
        ScanImportNormalizer(
            dependencies: ScanImportNormalizerDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                preservingTerminalSentencePunctuation: { original, candidate, cardType in
                    preservingTerminalSentencePunctuation(
                        from: original,
                        in: candidate,
                        style: .neutral,
                        cardType: cardType
                    )
                },
                canonicalizedSourceTermIfNeeded: { text, sourceLanguage in
                    canonicalizedSourceTermIfNeeded(text, sourceLanguage: sourceLanguage)
                },
                germanDisplayText: { text, cardType, sourceHint in
                    germanDisplayText(text, cardType: cardType, sourceHint: sourceHint)
                },
                bestLocalTranslationMatch: { source, sourceLanguage in
                    bestLocalTranslationMatch(for: source, sourceLanguage: sourceLanguage)
                },
                shouldPreserveScannedGermanTargetText: { original, canonical in
                    shouldPreserveScannedGermanTargetText(original, insteadOf: canonical)
                },
                normalizedLookupText: { normalizedLookupText($0) },
                compactLookupKey: { compactLookupKey($0) },
                isLikelyOCRCorruptedWordToken: { isLikelyOCRCorruptedWordToken($0) },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                ocrConfusableSimilarityScore: { lhs, rhs in
                    ocrConfusableSimilarityScore(lhs, rhs)
                },
                vocabularyPairScore: { source, target, sourceLanguage in
                    vocabularyPairScore(
                        source: source,
                        target: target,
                        sourceLanguage: sourceLanguage
                    )
                },
                sourceLanguageScore: { text, sourceLanguage in
                    sourceLanguageScore(for: text, language: sourceLanguage)
                },
                germanScore: { germanScore(for: $0) },
                isLikelyMarkerNoise: { isLikelyMarkerNoise($0) },
                sourceLexiconCoverageScore: { text, sourceLanguage in
                    sourceLexiconCoverageScore(for: text, language: sourceLanguage)
                },
                looksLikeEnglishInfinitiveMarker: { looksLikeEnglishInfinitiveMarker($0) },
                normalizedEnglishVerbMarker: { normalizedEnglishVerbMarker(in: $0) },
                sourceDisplayText: { text, sourceLanguage in
                    sourceDisplayText(text, sourceLanguage: sourceLanguage)
                },
                detectedTerminalSentencePunctuation: { detectedTerminalSentencePunctuation(from: $0) },
                applyingTerminalSentencePunctuation: { punctuation, text, style in
                    applyingTerminalSentencePunctuation(punctuation, to: text, style: style)
                },
                inferredGermanTerminalSentencePunctuation: { text, cardType in
                    inferredGermanTerminalSentencePunctuation(text, cardType: cardType)
                }
            )
        )
    }

    private var scanVocabularyItemFactory: ScanVocabularyItemFactory {
        ScanVocabularyItemFactory(
            dependencies: ScanVocabularyItemFactoryDependencies(
                extractedTermComponents: { extractedTermComponents(from: $0) },
                normalizedSourceImportTerm: { normalizedSourceImportTerm($0) },
                canonicalizedGermanTargetIfNeeded: { target, source, cardType, sourceLanguage in
                    canonicalizedGermanTargetIfNeeded(
                        target,
                        source: source,
                        cardType: cardType,
                        sourceLanguage: sourceLanguage
                    )
                },
                synchronizedPairTerminalSentencePunctuation: { source, target, sourceLanguage, cardType in
                    synchronizedPairTerminalSentencePunctuation(
                        source: source,
                        target: target,
                        sourceLanguage: sourceLanguage,
                        cardType: cardType
                    )
                }
            )
        )
    }

    private var scanPreviewTextBridge: ScanPreviewTextBridge {
        ScanPreviewTextBridge(
            dependencies: ScanPreviewTextBridgeDependencies(
                parsePreviewPairs: { parsePreviewPairs(from: $0) },
                normalizedPreviewPair: { normalizedPreviewPair($0) }
            )
        )
    }

    private var scanPreviewAssessor: ScanPreviewAssessor {
        ScanPreviewAssessor(
            extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
            bestVocabularyPairScore: { source, target, sourceLanguage in
                bestVocabularyPairScore(
                    source: source,
                    target: target,
                    preferredLanguage: sourceLanguage
                )
            },
            sourceLanguageScore: { text, sourceLanguage in
                sourceLanguageScore(for: text, language: sourceLanguage)
            },
            germanScore: { germanScore(for: $0) },
            normalizedWords: { normalizedWords(in: $0) }
        )
    }

    private var scanLanguageScorer: ScanLanguageScorer {
        ScanLanguageScorer()
    }

    private func extractOCRLineBoxes(
        from image: UIImage,
        sourceLanguage: StudyLanguage,
        includeGermanTargetLanguage: Bool,
        recognitionLevel: VNRequestTextRecognitionLevel,
        usesLanguageCorrection: Bool,
        customWordsLimit: Int
    ) -> [OCRLineBox] {
        scanOCRLineExtractor.extractLineBoxes(
            from: image,
            sourceLanguage: sourceLanguage,
            includeGermanTargetLanguage: includeGermanTargetLanguage,
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: usesLanguageCorrection,
            customWordsLimit: customWordsLimit
        )
    }

    private func prepareImageForOCR(from image: UIImage, completion: @escaping (UIImage) -> Void) {
        scanOCRImagePreprocessor.prepareImageForOCR(
            from: image,
            maxLongEdge: Self.maxOCRLongEdge,
            completion: completion
        )
    }

    private func preparedImageForAnalysis(from image: UIImage) async -> UIImage {
        await ScanImageLifecycle.preparedAnalysisImage(
            from: image,
            cachedPreparedImage: preparedScanImage,
            prepareImage: prepareImageForOCR(from:completion:)
        )
    }

    private func normalizedImageForProcessing(
        _ image: UIImage,
        maxLongEdge: CGFloat = 1800
    ) -> UIImage {
        scanOCRImagePreprocessor.normalizedImageForProcessing(
            image,
            maxLongEdge: maxLongEdge
        )
    }

    private func downscaledImageForOCR(_ image: UIImage, maxLongEdge: CGFloat = 2200) -> UIImage? {
        scanOCRImagePreprocessor.downscaledImage(
            image,
            maxLongEdge: maxLongEdge
        )
    }

    private func downscaledImageForDisplay(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        downscaledImageForOCR(image, maxLongEdge: maxLongEdge)
    }

    private func softlyEnhancedOCRImage(from image: UIImage) -> UIImage? {
        scanOCRImagePreprocessor.softlyEnhancedOCRImage(from: image)
    }

    private func fallbackPreparedImageForOCR(from image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        scanOCRImagePreprocessor.fallbackPreparedImageForOCR(
            from: image,
            maxLongEdge: maxLongEdge
        )
    }

    private func sanitizedLine(_ line: String) -> String {
        scanOCRTextSanitizer.sanitizedLine(line)
    }

    private func extractedDisplayTerm(from text: String) -> String {
        scanOCRTermExtractor.extractedDisplayTerm(
            from: text,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func extractedTermComponents(from text: String) -> (display: String, phonetic: String?) {
        let components = scanOCRTermExtractor.extractedTermComponents(
            from: text,
            sourceLanguage: scanSourceLanguage
        )
        return (components.display, components.phonetic)
    }

    private func isLikelyPhoneticSegment(_ segment: String) -> Bool {
        scanOCRTermExtractor.isLikelyPhoneticSegment(
            segment,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func isStandalonePedagogicalMarker(_ text: String) -> Bool {
        scanOCRTermExtractor.isStandalonePedagogicalMarker(text)
    }

    private func strippingPedagogicalUsageNotes(from text: String) -> String {
        scanOCRTermExtractor.strippingPedagogicalUsageNotes(from: text)
    }

    private func filteredVocabularyBoxes(from boxes: [OCRLineBox]) -> [OCRLineBox] {
        scanOCRNoiseFilter.filteredVocabularyBoxes(from: boxes)
    }

    private func makeColumnPairs(
        from boxes: [OCRLineBox],
        preferredLanguage: StudyLanguage? = nil
    ) -> [(String, String)] {
        scanColumnPairMatcher.makeColumnPairs(
            from: boxes,
            preferredLanguage: preferredLanguage
        )
    }

    private func makePreviewPair(first: String, second: String) -> ImportPreviewPair? {
        scanPreviewPairParser.makePreviewPair(
            first: first,
            second: second,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func makeIncompletePreviewPair(from line: String) -> ImportPreviewPair? {
        scanPreviewPairParser.makeIncompletePreviewPair(
            from: line,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func inferredCardType(forSource source: String, target: String) -> CardType {
        let sourceWordCount = normalizedWords(in: source).count
        let targetWordCount = normalizedWords(in: target).count
        let maxWordCount = max(sourceWordCount, targetWordCount)

        if maxWordCount <= 1 {
            return .words
        }

        if maxWordCount >= 3 {
            return .phrases
        }

        let sentencePunctuationPattern = #"[.!?]"#
        if maxWordCount >= 2 &&
            (source.range(of: sentencePunctuationPattern, options: .regularExpression) != nil ||
             target.range(of: sentencePunctuationPattern, options: .regularExpression) != nil) {
            return .phrases
        }

        return .words
    }

    private func isLikelyOrphanTargetPreviewLine(
        _ line: String,
        sourceLanguage: StudyLanguage? = nil
    ) -> Bool {
        let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedLine.isEmpty else { return true }

        let germanStrength = germanScore(for: cleanedLine)
        let resolvedSourceLanguage = sourceLanguage ?? scanSourceLanguage
        let sourceStrength = sourceLanguageScore(for: cleanedLine, language: resolvedSourceLanguage)
        let wordCount = normalizedWords(in: cleanedLine).count
        let hasKnownGermanCoverage = germanDictionaryCoverageScore(for: cleanedLine) >= 0.45
        let isSingleWord = wordCount == 1

        return germanStrength > sourceStrength + 0.22 &&
            isSingleWord &&
            hasKnownGermanCoverage
    }

    private func normalizedPreviewPair(_ pair: ImportPreviewPair) -> ImportPreviewPair {
        scanPreviewPairParser.normalizedPreviewPair(
            pair,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func canonicalizedGermanTargetIfNeeded(
        _ target: String,
        source: String,
        cardType: CardType,
        sourceLanguage: StudyLanguage
    ) -> String {
        scanImportNormalizer.canonicalizedGermanTargetIfNeeded(
            target,
            source: source,
            cardType: cardType,
            sourceLanguage: sourceLanguage
        )
    }

    private func normalizedSourceImportTerm(_ text: String) -> String {
        normalizedSourceImportTerm(text, sourceLanguage: scanSourceLanguage)
    }

    private func normalizedSourceImportTerm(
        _ text: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        scanImportNormalizer.normalizedSourceImportTerm(
            text,
            sourceLanguage: sourceLanguage
        )
    }

    private func normalizedEnglishVerbMarker(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalizedPrefix = trimmed
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\s*$"#, with: "(to)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*to\)\s*$"#, with: "(to)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*to\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(to\s*"#, with: "(to) ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = normalizedPrefix.range(
            of: #"(?i)^\s*\(?\s*to\)?\s*(.+)$"#,
            options: .regularExpression
        ) {
            let remainder = String(normalizedPrefix[range])
            let cleanedRemainder = remainder
                .replacingOccurrences(of: #"(?i)^\s*\(?\s*to\)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\)+\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanedRemainder.isEmpty else { return "(to)" }
            return "(to) \(cleanedRemainder)"
        }

        return normalizedPrefix
    }

    private func looksLikeEnglishInfinitiveMarker(_ text: String) -> Bool {
        text.range(
            of: #"(?i)^\s*(\(?\s*to\)?)(\s|$)"#,
            options: .regularExpression
        ) != nil
    }

    private func isSourceColumnFirst(first: String, second: String) -> Bool {
        scanLanguageScorer.isSourceColumnFirst(
            first: first,
            second: second,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func sourceLanguageScore(for text: String) -> Double {
        scanLanguageScorer.sourceLanguageScore(
            for: text,
            language: scanSourceLanguage
        )
    }

    private func sourceLanguageScore(for text: String, language: StudyLanguage) -> Double {
        scanLanguageScorer.sourceLanguageScore(for: text, language: language)
    }

    private func germanScore(for text: String) -> Double {
        scanLanguageScorer.germanScore(for: text)
    }

    private func normalizedWords(in text: String) -> [String] {
        scanLanguageScorer.normalizedWords(in: text)
    }

    private func isLikelyHeadingOrMetaLine(_ text: String) -> Bool {
        scanOCRNoiseFilter.isLikelyHeadingOrMetaLine(text)
    }

    private func repairedVocabularyPairs(
        _ pairs: [(String, String)],
        sourceLanguage: StudyLanguage
    ) -> [(String, String)] {
        scanVocabularyPairRepair.repairedVocabularyPairs(
            pairs,
            sourceLanguage: sourceLanguage
        )
    }

    private func vocabularyPairScore(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> Double {
        scanVocabularyPairRepair.vocabularyPairScore(
            source: source,
            target: target,
            sourceLanguage: sourceLanguage
        )
    }

    private func bestVocabularyPairScore(
        source: String,
        target: String,
        preferredLanguage: StudyLanguage?
    ) -> Double {
        scanVocabularyPairRepair.bestVocabularyPairScore(
            source: source,
            target: target,
            preferredLanguage: preferredLanguage
        )
    }

    private func vocabularyPairPenalty(for semanticScore: Double, pairTolerance: Double) -> Double {
        scanVocabularyPairRepair.vocabularyPairPenalty(
            for: semanticScore,
            pairTolerance: pairTolerance
        )
    }

    private func correctedPairIfNeeded(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> (String, String) {
        scanVocabularyPairRepair.correctedPairIfNeeded(
            source: source,
            target: target,
            sourceLanguage: sourceLanguage
        )
    }

    private func bestLocalTranslationMatch(
        for source: String,
        sourceLanguage: StudyLanguage
    ) -> (sourceTerm: String, suggestions: [String], matchDistance: Double)? {
        scanVocabularyPairRepair.bestLocalTranslationMatch(
            for: source,
            sourceLanguage: sourceLanguage
        )
    }

    private func shouldPreserveScannedSourceText(
        _ original: String,
        insteadOf canonical: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        scanVocabularyPairRepair.shouldPreserveScannedSourceText(
            original,
            insteadOf: canonical,
            sourceLanguage: sourceLanguage
        )
    }

    private func shouldPreserveScannedGermanTargetText(
        _ original: String,
        insteadOf canonical: String
    ) -> Bool {
        scanVocabularyPairRepair.shouldPreserveScannedGermanTargetText(
            original,
            insteadOf: canonical
        )
    }

    private func canonicalizedSourceTermIfNeeded(
        _ source: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        scanVocabularyPairRepair.canonicalizedSourceTermIfNeeded(
            source,
            sourceLanguage: sourceLanguage
        )
    }

    private func isLikelyMarkerNoise(_ text: String) -> Bool {
        scanVocabularyPairRepair.isLikelyMarkerNoise(text)
    }

    private func isLikelyOCRCorruptedWordToken(_ text: String) -> Bool {
        scanVocabularyPairRepair.isLikelyOCRCorruptedWordToken(text)
    }

    private func ocrConfusableSimilarityScore(_ lhs: String, _ rhs: String) -> Double {
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0 }

        let distance = ocrConfusableDistance(lhs, rhs)
        return max(0, 1.0 - (distance / Double(maxLength)))
    }

    private func ocrConfusableDistance(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        var dist = Array(
            repeating: Array(repeating: 0.0, count: right.count + 1),
            count: left.count + 1
        )

        for i in 0...left.count { dist[i][0] = Double(i) }
        for j in 0...right.count { dist[0][j] = Double(j) }

        guard !left.isEmpty, !right.isEmpty else {
            return Double(max(left.count, right.count))
        }

        for i in 1...left.count {
            for j in 1...right.count {
                let substitutionCost: Double
                if left[i - 1] == right[j - 1] {
                    substitutionCost = 0
                } else if areOCRConfusable(left[i - 1], right[j - 1]) {
                    substitutionCost = 0.22
                } else {
                    substitutionCost = 1
                }

                dist[i][j] = min(
                    dist[i - 1][j] + 1,
                    dist[i][j - 1] + 1,
                    dist[i - 1][j - 1] + substitutionCost
                )
            }
        }

        return dist[left.count][right.count]
    }

    private func areOCRConfusable(_ lhs: Character, _ rhs: Character) -> Bool {
        lhs == rhs ||
        ocrConfusableAlternatives[lhs]?.contains(rhs) == true ||
        ocrConfusableAlternatives[rhs]?.contains(lhs) == true
    }

    private var ocrConfusableAlternatives: [Character: Set<Character>] {
        [
            "0": ["o", "d"],
            "1": ["l", "i"],
            "2": ["z"],
            "3": ["a", "e"],
            "4": ["a"],
            "5": ["s"],
            "6": ["g"],
            "7": ["t"],
            "8": ["b"],
            "9": ["g", "q"],
            "o": ["0"],
            "d": ["0"],
            "l": ["1", "i"],
            "i": ["1", "l"],
            "z": ["2"],
            "a": ["3", "4"],
            "e": ["3"],
            "s": ["5"],
            "g": ["6", "9"],
            "t": ["7"],
            "b": ["8"],
            "q": ["9"]
        ]
    }

    private func dictionaryCoverageScore(for text: String, language: StudyLanguage) -> Double {
        scanLanguageScorer.dictionaryCoverageScore(
            for: text,
            language: language
        )
    }

    private func germanDictionaryCoverageScore(for text: String) -> Double {
        scanLanguageScorer.germanDictionaryCoverageScore(for: text)
    }

    private func sourceLexiconCoverageScore(for text: String, language: StudyLanguage) -> Double {
        scanLanguageScorer.sourceLexiconCoverageScore(
            for: text,
            language: language
        )
    }

    private func ensureSuggestedListName() {
        session.ensureSuggestedListName(
            fallbackListName: listStore?.suggestedListName(from: "Scan") ?? "Scan"
        )
    }

    private func refreshPreviewPairsFromImportText() {
        previewPairs = scanPreviewTextBridge.previewPairs(from: importText)
    }

    private func bindingValue(for id: UUID) -> ImportPreviewPair? {
        previewPairs.first(where: { $0.id == id })
    }

    private func previewAssessment(for pair: ImportPreviewPair) -> ImportPreviewAssessment {
        scanPreviewAssessor.assessment(
            for: pair,
            sourceLanguage: scanSourceLanguage
        )
    }

    private func previewAssessmentBackground(for assessment: ImportPreviewAssessment) -> Color {
        switch assessment {
        case .complete:
            return Color.clear
        case .incomplete:
            return Color.secondary.opacity(0.06)
        case .suspicious:
            return AppTheme.Colors.warning.opacity(0.12)
        }
    }

    private func previewAssessmentBorder(for assessment: ImportPreviewAssessment) -> Color {
        switch assessment {
        case .complete:
            return Color.clear
        case .incomplete:
            return Color.secondary.opacity(0.22)
        case .suspicious:
            return AppTheme.Colors.warning.opacity(0.52)
        }
    }

    private func updatePreviewPair(_ id: UUID, update: (inout ImportPreviewPair) -> Void) {
        guard let index = previewPairs.firstIndex(where: { $0.id == id }) else { return }
        update(&previewPairs[index])
        previewPairs[index] = normalizedPreviewPair(previewPairs[index])
    }

    private func updatePreviewPairForEditing(_ id: UUID, update: (inout ImportPreviewPair) -> Void) {
        guard let index = previewPairs.firstIndex(where: { $0.id == id }) else { return }
        update(&previewPairs[index])
        hasPendingPreviewEdits = true
    }

    private func schedulePreviewEditCommit(delay: TimeInterval = 0.18) {
        previewEditSyncWorkItem?.cancel()
        hasPendingPreviewEdits = true

        let workItem = DispatchWorkItem {
            commitPreviewEditsAndSyncImportText()
        }

        previewEditSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func commitPreviewEditsAndSyncImportText() {
        previewEditSyncWorkItem?.cancel()
        previewEditSyncWorkItem = nil
        guard hasPendingPreviewEdits else { return }
        previewPairs = previewPairs.map { normalizedPreviewPair($0) }
        syncImportTextFromPreview()
        hasPendingPreviewEdits = false
    }

    private func syncImportTextFromPreview() {
        isSyncingPreviewToText = true
        importText = scanPreviewTextBridge.importText(from: previewPairs)
    }

    private func updateScanEvalReport(for result: ScanProviderResult) {
        session.updateEvalReport(for: result)
    }

    private func resetScanInputAfterSuccessfulImport(keepingListName: Bool) {
        session.resetInputAfterSuccessfulImport(
            keepingListName: keepingListName,
            fallbackListName: listStore?.suggestedListName(from: "Scan") ?? "Scan"
        )
    }

    private func returnToScanSetup() {
        guard !isRecognizingImage else { return }

        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        session.returnToSetup()
    }

    private func handleCompletionSelection(_ destination: AppScreen?) {
        pendingCompletionDestination = destination
        isShowingImportCompletion = false
    }

    private func showScanToast(
        _ message: String,
        isWarning: Bool = false,
        delay: TimeInterval = 0
    ) {
        session.showToast(message, isWarning: isWarning, delay: delay)
    }

    private func presentScanAIInfo(_ message: String) {
        session.presentScanAIInfo(message)
    }

    private var scanToastView: some View {
        HStack(spacing: 10) {
            Image(systemName: scanToastIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(scanToastIsWarning ? AppTheme.Colors.warning : AppTheme.Colors.success)

            Text(scanToastMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    (scanToastIsWarning ? AppTheme.Colors.warning : AppTheme.Colors.success).opacity(0.25),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private func scanAIFallbackPopupMessage(
        for result: ScanProviderResult,
        aiConfigured: Bool
    ) -> String? {
        let aiWarnings = result.warnings.filter { $0.hasPrefix("ai_") }
        let mentionsOCRFallback = result.importMessage.localizedCaseInsensitiveContains("OCR")
        guard !aiWarnings.isEmpty || mentionsOCRFallback else { return nil }

        let headline: String
        if aiWarnings.contains("ai_provider_unavailable") {
            headline = aiConfigured
                ? "Die KI war diesmal nicht verfügbar. Bitte nochmal versuchen."
                : "Die KI ist nicht konfiguriert. Bitte API-Key prüfen."
        } else if aiWarnings.contains("ai_http_401") {
            headline = "Ungültiger API-Key. Bitte den Key prüfen."
        } else if aiWarnings.contains("ai_http_429") {
            headline = "API-Limit erreicht. Bitte später nochmal versuchen."
        } else if aiWarnings.contains("ai_timeout") {
            headline = "Die Analyse hat zu lange gedauert. Bitte nochmal versuchen."
        } else if aiWarnings.contains("ai_invalid_response") || aiWarnings.contains("ai_analysis_failed") {
            headline = "Die KI-Analyse war diesmal nicht erfolgreich. Bitte nochmal versuchen."
        } else {
            headline = "Die KI-Analyse konnte nicht gestartet werden. Bitte nochmal versuchen."
        }

        var detailLines: [String] = []
        detailLines.append("AI konfiguriert: \(aiConfigured ? "ja" : "nein")")
        if !aiWarnings.isEmpty {
            detailLines.append("Warnung: \(aiWarnings.joined(separator: ", "))")
        }
        let trimmedImportMessage = result.importMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedImportMessage.isEmpty {
            detailLines.append(trimmedImportMessage)
        }

        return ([headline] + detailLines).joined(separator: "\n\n")
    }

    private var scanProgressView: some View {
        ZStack {
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.Colors.textPrimary.opacity(0.92))

                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                Text(scanProgressText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .center)

                Label(scanProgressRuntimeLabel, systemImage: scanProgressRuntimeIcon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(scanProgressRuntimeTint)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private func startScanProgressFeedback() {
        session.startProgressFeedback()
    }

    private func stopScanProgressFeedback() {
        session.stopProgressFeedback()
    }

    @ViewBuilder
    private func imagePreviewSheet(for image: UIImage) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Bild",
                leadingTitle: "Zuschneiden",
                trailingTitle: "Fertig",
                leadingTint: sectionStyle.accent,
                trailingTint: sectionStyle.accent,
                onLeading: {
                    presentManualCrop(from: image, target: ManualCropTarget.imagePreview)
                },
                onTrailing: {
                    showingImagePreview = false
                }
            )

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
    }
}

private struct HomeCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ImportCompletionView: View {
    let context: ImportCompletionContext
    let onTrain: () -> Void
    let onFlashcards: () -> Void
    let onLists: () -> Void
    let onLater: () -> Void
    private let sectionStyle: AppSectionStyle = .scan
    @State private var isNavigationLocked = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Import fertig")
                        .font(AppTheme.Typography.largeTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(context.summaryText)
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Liste: \(context.targetListName)")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                Text("Du kannst jetzt direkt üben oder später weitermachen.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onTrain()
                } label: {
                    completionActionCard(
                        title: "Jetzt trainieren",
                        systemImage: "mic.fill",
                        isPrimary: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNavigationLocked)

                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onFlashcards()
                } label: {
                    completionActionCard(
                        title: "Karteikarten üben",
                        systemImage: "rectangle.stack.fill",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNavigationLocked)

                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onLists()
                } label: {
                    completionActionCard(
                        title: "Zur Liste",
                        systemImage: "list.bullet.rectangle.fill",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNavigationLocked)
            }

            Button("Später") {
                guard !isNavigationLocked else { return }
                isNavigationLocked = true
                onLater()
            }
            .buttonStyle(.plain)
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: 0)
        }
        .safeAreaPadding(.top, AppTheme.Spacing.xs)
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isNavigationLocked = false
        }
    }

    private func completionActionCard(title: String, systemImage: String, isPrimary: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 42, height: 42)
                .background((isPrimary ? Color.white.opacity(0.22) : AppTheme.Colors.cta.opacity(0.14)))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(isPrimary ? .white : AppTheme.Colors.cta)

            Text(title)
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(isPrimary ? .white : AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isPrimary ? Color.white.opacity(0.82) : AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(isPrimary ? AppTheme.Colors.cta : AppTheme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isPrimary ? AppTheme.Colors.cta.opacity(0.18) : AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage?, String?) -> Void

        init(onImagePicked: @escaping (UIImage?, String?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            let imagePath = (info[.imageURL] as? URL)?.path
            picker.dismiss(animated: true)
            onImagePicked(image, imagePath)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImagePicked(nil, nil)
        }
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onImagePicked: (UIImage?, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onImagePicked: (UIImage?, String?) -> Void

        init(onImagePicked: @escaping (UIImage?, String?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onImagePicked(nil, nil)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            onImagePicked(nil, nil)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            controller.dismiss(animated: true)
            onImagePicked(image, nil)
        }
    }
}

struct ManualCropSheet: View {
    let image: UIImage
    let accent: Color
    let onCancel: () -> Void
    let onApply: (UIImage, Bool) -> Void

    @State private var cropRect: CGRect = .zero
    @State private var dragStartRect: CGRect?
    @State private var lastImageFrame: CGRect = .zero

    private let minimumCropSize: CGFloat = 80

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text("Zuschneiden")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)

            GeometryReader { geometry in
                let imageFrame = fittedImageFrame(for: image.size, in: geometry.size)

                ZStack {
                    Color.clear

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            initializeCropRectIfNeeded(imageFrame: imageFrame)
                        }
                        .onChange(of: geometry.size) { _, _ in
                            initializeCropRectIfNeeded(imageFrame: imageFrame, force: true)
                        }

                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .mask(
                            Rectangle()
                                .overlay(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .frame(width: cropRect.width, height: cropRect.height)
                                        .offset(x: cropRect.minX, y: cropRect.minY)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                                .luminanceToAlpha()
                        )
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent, lineWidth: 3)
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartRect == nil { dragStartRect = cropRect }
                                    guard let startRect = dragStartRect else { return }
                                    cropRect = movedCropRect(
                                        startRect,
                                        translation: value.translation,
                                        within: imageFrame
                                    )
                                    lastImageFrame = imageFrame
                                }
                                .onEnded { _ in
                                    dragStartRect = nil
                                }
                        )

                    ForEach(CropHandle.allCases, id: \.self) { handle in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(accent, lineWidth: 3)
                            )
                            .position(position(for: handle, in: cropRect))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if dragStartRect == nil { dragStartRect = cropRect }
                                        guard let startRect = dragStartRect else { return }
                                        cropRect = resizedCropRect(
                                            startRect,
                                            handle: handle,
                                            translation: value.translation,
                                            within: imageFrame
                                        )
                                        lastImageFrame = imageFrame
                                    }
                                    .onEnded { _ in
                                        dragStartRect = nil
                                    }
                            )
                    }
                }
            }

            Text("Zieh den Rahmen oder die Ecken, damit nur die Buchseite übrig bleibt.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appScreenBackground(.scan)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Button("Abbrechen") {
                    onCancel()
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textPrimary))

                HStack(spacing: 12) {
                    Button("Übernehmen") {
                        if let cropped = croppedImage(from: image, imageFrame: lastImageFrame, cropRect: cropRect) {
                            onApply(cropped, false)
                        } else {
                            onCancel()
                        }
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textPrimary))

                    Button("Übernehmen + Analysieren") {
                        if let cropped = croppedImage(from: image, imageFrame: lastImageFrame, cropRect: cropRect) {
                            onApply(cropped, true)
                        } else {
                            onCancel()
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.surface.opacity(0.98))
        }
    }

    private func initializeCropRectIfNeeded(imageFrame: CGRect, force: Bool = false) {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
        if force || cropRect == .zero || lastImageFrame != imageFrame {
            cropRect = imageFrame.insetBy(dx: imageFrame.width * 0.08, dy: imageFrame.height * 0.08)
            lastImageFrame = imageFrame
        }
    }

    private func fittedImageFrame(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageRatio = imageSize.width / imageSize.height
        let containerRatio = containerSize.width / max(containerSize.height, 1)

        if imageRatio > containerRatio {
            let width = containerSize.width
            let height = width / imageRatio
            return CGRect(x: 0, y: (containerSize.height - height) / 2, width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageRatio
            return CGRect(x: (containerSize.width - width) / 2, y: 0, width: width, height: height)
        }
    }

    private func movedCropRect(_ rect: CGRect, translation: CGSize, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: translation.width, dy: translation.height)

        if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
        if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
        if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
        if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }

        return moved
    }

    private func resizedCropRect(
        _ rect: CGRect,
        handle: CropHandle,
        translation: CGSize,
        within bounds: CGRect
    ) -> CGRect {
        var updated = rect

        switch handle {
        case .topLeft:
            updated.origin.x += translation.width
            updated.origin.y += translation.height
            updated.size.width -= translation.width
            updated.size.height -= translation.height
        case .topRight:
            updated.origin.y += translation.height
            updated.size.width += translation.width
            updated.size.height -= translation.height
        case .bottomLeft:
            updated.origin.x += translation.width
            updated.size.width -= translation.width
            updated.size.height += translation.height
        case .bottomRight:
            updated.size.width += translation.width
            updated.size.height += translation.height
        }

        if updated.width < minimumCropSize {
            switch handle {
            case .topLeft, .bottomLeft:
                updated.origin.x = rect.maxX - minimumCropSize
            default:
                break
            }
            updated.size.width = minimumCropSize
        }

        if updated.height < minimumCropSize {
            switch handle {
            case .topLeft, .topRight:
                updated.origin.y = rect.maxY - minimumCropSize
            default:
                break
            }
            updated.size.height = minimumCropSize
        }

        if updated.minX < bounds.minX {
            let delta = bounds.minX - updated.minX
            updated.origin.x += delta
            updated.size.width -= delta
        }

        if updated.minY < bounds.minY {
            let delta = bounds.minY - updated.minY
            updated.origin.y += delta
            updated.size.height -= delta
        }

        if updated.maxX > bounds.maxX {
            updated.size.width = bounds.maxX - updated.minX
        }

        if updated.maxY > bounds.maxY {
            updated.size.height = bounds.maxY - updated.minY
        }

        updated.size.width = max(updated.width, minimumCropSize)
        updated.size.height = max(updated.height, minimumCropSize)

        return updated
    }

    private func position(for handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func croppedImage(from image: UIImage, imageFrame: CGRect, cropRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage, imageFrame.width > 0, imageFrame.height > 0 else { return nil }

        let scaleX = CGFloat(cgImage.width) / imageFrame.width
        let scaleY = CGFloat(cgImage.height) / imageFrame.height

        let crop = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral

        guard crop.width > 10, crop.height > 10,
              let cropped = cgImage.cropping(to: crop) else { return nil }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}

private enum CropHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
