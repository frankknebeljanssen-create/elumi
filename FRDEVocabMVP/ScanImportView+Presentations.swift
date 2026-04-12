import SwiftUI
import Vision
import VisionKit
import UIKit

extension ScanImportView {
    func applyingScanRootModifiers<Content: View>(to content: Content) -> some View {
        content
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigate(pendingCompletionDestination)
                }
            }
    }

    func applyingScanPresentationModifiers<Content: View>(to content: Content) -> some View {
        content
            .navigationDestination(isPresented: $isShowingFullscreenReview) {
                scanFullscreenReview
            }
            .navigationDestination(isPresented: $isShowingImportCompletion) {
                if let importCompletionContext {
                    ImportCompletionView(
                        context: importCompletionContext,
                        onTrain: {
                            handleCompletionSelection(.train(TrainingLaunchContext(
                                preferredListID: importCompletionContext.targetListID,
                                preferredMode: .vocabulary,
                                shouldAutoStart: true
                            )))
                        },
                        onArticles: {
                            handleCompletionSelection(.train(TrainingLaunchContext(
                                preferredListID: importCompletionContext.targetListID,
                                preferredMode: .articles,
                                shouldAutoStart: true
                            )))
                        },
                        onVerbs: {
                            handleCompletionSelection(.train(TrainingLaunchContext(
                                preferredListID: importCompletionContext.targetListID,
                                preferredMode: .verbs,
                                shouldAutoStart: true
                            )))
                        },
                        onFlashcards: {
                            handleCompletionSelection(.flashcards(importCompletionContext.flashcardLaunchContext))
                        },
                        onQuiz: {
                            handleCompletionSelection(.quiz)
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
                PhotoLibraryPicker { images in
                    handleSelectedImages(images)
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
}
