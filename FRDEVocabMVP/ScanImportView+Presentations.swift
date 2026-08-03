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
            // **Erstnutzer-Hint (2026-06-09)** — Einstiegs-Screen des
            // Scans. Der zweite Scan-Hint (`scan_result`) sitzt auf dem
            // gepushten Review-Screen, kollidiert also nicht.
            .hintBubble(
                id: "scan_intro",
                text: """
                Hier machst du aus deinem Vokabelbuch Karteikarten.
                Wähl erst aus, was du scannst und woher das Bild kommt.
                Dann fotografier die Seite oder nimm ein Bild aus deinem Album.
                Ich lese die Wörter und mach dir Karten daraus.
                """
            )
            .onAppear {
                scanSourceLanguage = .french
                ensureSuggestedListName()
                refreshPreviewPairsFromImportText()
            }
            .onDisappear {
                stopScanProgressFeedback()
                feedbackPlayer.stopScanProcessLoop()
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
    }

    func applyingScanPresentationModifiers<Content: View>(to content: Content) -> some View {
        content
            .navigationDestination(isPresented: $isShowingFullscreenReview) {
                scanFullscreenReview
            }
            .fullScreenCover(isPresented: showingCameraBinding) {
                // SmartScannerView bringt die komplette Pipeline mit:
                // Live-Overlay-Guidance + Auto/Manual-Capture +
                // Perspektivkorrektur + Enhancement + Preview.
                // Fallback auf ImagePicker nur im Simulator (dort ist
                // keine echte Kamera verfügbar).
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    // Single-Source-of-Truth: `ScanCaptureProfile` trägt
                    // den Use-Case (vocabularyList / freeText). Die
                    // Processor-Config leitet sich daraus intern ab,
                    // gleichzeitig setzt das Profil Auto-Capture-Gate,
                    // Live-Quad-Overlay und (perspektivisch) die
                    // Tracker-Konfiguration.
                    SmartScannerView(
                        onUse: { correctedImage, qualityReport, captureID in
                            // Quality-Report + Capture-ID werden noch
                            // nicht in der Analyse-Pipeline genutzt —
                            // Übergabe ist die Voraussetzung für
                            // späteres Confidence-Tuning und Multi-
                            // Shot-Trace. Heute landen sie in den
                            // Debug-Logs, sodass wir nachvollziehen
                            // können, welche Capture-ID welcher Score
                            // hatte.
                            #if DEBUG
                            let scoreStr = qualityReport.map { String(format: "%.2f", $0.overallScore) } ?? "n/a"
                            let issuesStr = qualityReport?.issues.map(\.debugLabel).joined(separator: ",") ?? ""
                            let idStr = captureID?.shortID ?? "?"
                            appDebugLog("📤 [onUse \(idStr)] passed image to analysis pipeline — score=\(scoreStr) issues=[\(issuesStr)]")
                            #endif
                            _ = qualityReport
                            _ = captureID
                            handleSelectedImage(correctedImage, sourcePath: nil)
                        },
                        // **Multi-Shot Callback** (vocabularyList only):
                        // Camera-Multi-Capture sammelt Bilder, „Fertig"
                        // schickt sie als Batch raus. Single-Shot
                        // bleibt unverändert über `onUse`.
                        onUseBatch: { capturedImages in
                            #if DEBUG
                            appDebugLog("📤 [onUseBatch] received \(capturedImages.count) images from camera multi-shot")
                            #endif
                            handleSelectedImages(capturedImages)
                        },
                        onCancel: {
                            showingCameraBinding.wrappedValue = false
                        },
                        // Feature C — Swipe-Switching.
                        profile: Binding(
                            get: { activeScanMode == .text ? .freeText : .vocabularyList },
                            set: { newValue in
                                scanModeOverride = (newValue == .freeText) ? .text : .list
                            }
                        )
                    )
                } else {
                    ImagePicker(sourceType: .photoLibrary) { image, sourcePath in
                        handleSelectedImage(image, sourcePath: sourcePath)
                    }
                }
            }
            .sheet(isPresented: showingPhotoLibraryBinding) {
                PhotoLibraryPicker { images in
                    // **2026-04-23**: Galerie-Auswahl geht in den
                    // dedizierten per-image Review-Pfad. Camera-Multi-
                    // Shot bleibt am alten `handleSelectedImages`.
                    handleSelectedImagesFromGallery(images)
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
                Text(previewPairPendingDeletion.map { "\($0.french) wird entfernt." } ?? "")
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
            // Claude-Vision-basierter „Freier Text"-Flow. Fullscreen, weil
            // die Ergebnis-Anzeige als eigener Kontext läuft — kein
            // halbtransparentes Sheet über dem Scan-UI. Bildwahl erfolgt
            // über die bestehenden Scan-Cards (Kamera/Foto-Album) plus
            // Preparation-Sheet inkl. Crop; dieser Cover präsentiert den
            // Analyse-Flow (Processing → Result) auf dem bereits vor-
            // liegenden Bild.
            //
            // `item:`-Pattern statt `isPresented:` + `if let`: SwiftUI
            // remountet die Cover-View bei Re-Renders des Parents, wenn
            // die Content-Closure ein `if let pendingImage = …` enthält
            // — der laufende Claude-Request wird dann via `.task`-Cleanup
            // gecancelled (Bugreport vom 2026-04-16: „network error:
            // cancelled" × 2, Alert „Analyse fehlgeschlagen"). Mit
            // `.fullScreenCover(item:)` hält SwiftUI genau EINE stabile
            // Präsentation, bis das Item auf `nil` geht.
            // **2026-04-22 Abend V**: Drei neue Sheets für den
            // Import-Target-Choice-Flow.
            //
            //   1. ImportTargetChoiceSheet — neue/bestehende Liste fragen
            //   2. ExistingListPickerSheet — Single-Select wenn „bestehend"
            //   3. ScanImportConflictReviewSheet — bei Konflikten vor Apply
            .sheet(isPresented: $isShowingImportTargetChoice) {
                ImportTargetChoiceSheet(
                    importableCount: pendingImportItems.count,
                    onChooseNewList: {
                        // Pfad 1: bestehender Flow läuft unverändert.
                        proceedWithNewListImport()
                    },
                    onChooseExistingList: {
                        // Pfad 2: Picker öffnen.
                        showExistingListPicker()
                    },
                    onSaveAsDraft: {
                        // Pfad 3 (Phase B): Scan als Entwurf sichern.
                        saveAsDraft()
                    }
                )
                .presentationDetents([.medium])
            }
            // **2026-04-23**: Namensabfrage für „neue Liste".
            // Wird nach dem ImportTargetChoiceSheet präsentiert,
            // wenn der User „neue Liste" gewählt hat.
            .sheet(isPresented: $isShowingNewListNameSheet) {
                NewListNameSheet(
                    onCreate: { chosenName in
                        handleNewListNameChosen(chosenName)
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingExistingListPicker) {
                if let activeStore = listStore {
                    ExistingListPickerSheet(
                        store: activeStore,
                        importableCount: pendingImportItems.count,
                        onConfirm: { listID in
                            handleExistingListChosen(listID)
                        },
                        onFallbackToNewList: {
                            // User hat keine eigenen Listen — fällt
                            // zurück auf den neuen-Liste-Pfad.
                            proceedWithNewListImport()
                        }
                    )
                }
            }
            .sheet(isPresented: $isShowingConflictReview) {
                if let plan = pendingMergePlan,
                   let listID = pendingTargetListID,
                   let targetList = (listStore ?? ensureListStoreReady())
                       .customLists.first(where: { $0.id == listID }) {
                    ScanImportConflictReviewSheet(
                        workingConflicts: plan.conflicts,
                        safeAddCount: plan.safeAdds.count,
                        duplicateCount: plan.exactDuplicatesToSkip.count,
                        targetListName: targetList.name,
                        onConfirm: { resolved in
                            handleConflictReviewConfirmed(resolved)
                        }
                    )
                }
            }
            // **2026-04-22 Abend VI**: Multi-Capture-Review-Sheet.
            // Wird präsentiert, wenn der User im Auto-Modus mehrere
            // Bilder aufgenommen und „Fertig" getippt hat.
            // Die Captures leben in `session.capturedItems` und sind
            // dadurch stabil identifizierbar — kein UI-Deadlock-Pfad
            // wie im vorigen Auto-Sequenz-Verarbeitungs-Flow.
            // **2026-04-23 nachmittags**: Galerie-Mehrbild-Review.
            // Per-image Optimization-State; Caller bekommt am Ende
            // ALLE Bilder mit ihrem jeweils gewählten Final-State.
            .fullScreenCover(isPresented: $session.isShowingGalleryReview) {
                GalleryMultiImageReviewView(
                    items: $session.galleryReviewItems,
                    selectedItemID: $session.selectedGalleryItemID,
                    sectionStyle: sectionStyle,
                    onAnalyzeQuality: { item in
                        await analyzeGalleryItemQuality(item)
                    },
                    onOptimizeItem: { item in
                        await optimizeGalleryItem(item)
                    },
                    onSubmitAll: { submittedItems in
                        submitGalleryReviewToAnalysis(submittedItems)
                    }
                )
            }
            .fullScreenCover(isPresented: $session.isShowingMultiCaptureReview) {
                MultiCaptureReviewView(
                    items: $session.capturedItems,
                    selectedItemID: $session.selectedCapturedItemID,
                    sectionStyle: sectionStyle,
                    onReviewSelected: { item in
                        reviewSelectedCapturedItem(item)
                    },
                    onAddMoreCaptures: {
                        resumeScanningFromMultiReview()
                    },
                    onDiscardAll: {
                        discardAllMultiCaptures()
                    }
                )
            }
            .fullScreenCover(item: $freierTextPendingImage, onDismiss: {
                // Fires NACH der Cover-Dismiss-Animation. Wenn ein
                // pendingFreierTextCompletion vorliegt, wurde erfolgreich
                // gespeichert → Import-Completion-View zeigen (identisch
                // zum Vokabel-Scan-Post-Import).
                if let ctx = pendingFreierTextCompletion {
                    pendingFreierTextCompletion = nil
                    importCompletionContext = ctx
                    isShowingImportCompletion = true
                }
            }) { pending in
                FreierTextAnalysisFlowView(
                    image: pending.image,
                    inputMethod: pending.inputMethod,
                    onDismiss: {
                        freierTextPendingImage = nil
                    },
                    listStore: listStore,
                    onImportComplete: { context in
                        pendingFreierTextCompletion = context
                    }
                )
            }
    }
}
