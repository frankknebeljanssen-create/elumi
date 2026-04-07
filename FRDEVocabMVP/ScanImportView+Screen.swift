import SwiftUI

extension ScanImportView {
    @ViewBuilder
    var scanStatusMessageView: some View {
        if !isRecognizingImage {
            Text(importMessage)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func scanRootContent(proxy: ScrollViewProxy) -> some View {
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
                        Label("Zurück zur Auswahl", systemImage: "arrow.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))
                    .disabled(isRecognizingImage)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ScanModeSelectionCardView(
                            activeMode: activeScanMode,
                            sectionStyle: sectionStyle,
                            onSelect: selectScanMode
                        )

                        ScanInputMethodOptionsCardView(
                            isRecognizingImage: isRecognizingImage,
                            isCameraAvailable: isCameraCaptureAvailable,
                            selectedMethod: selectedScanInputMethod,
                            sectionStyle: sectionStyle,
                            onCamera: {
                                guard !isRecognizingImage else { return }
                                guard isCameraCaptureAvailable else { return }
                                shouldAppendNextScan = false
                                selectedScanInputMethod = .camera
                                openCameraScanner()
                            },
                            onLibrary: {
                                guard !isRecognizingImage else { return }
                                shouldAppendNextScan = false
                                selectedScanInputMethod = .library
                                showingPhotoLibrary = true
                            }
                        )

                        if !previewPairs.isEmpty {
                            previewCard
                                .id(Self.reviewAnchorID)
                            ScanImportDetailsCardView(
                                sectionStyle: sectionStyle,
                                selectedCollectionPreset: selectedCollectionPresetBinding,
                                listName: listNameBinding,
                                isListNameFocused: $isListNameFocused,
                                isListNamePulseActive: isListNamePulseActive,
                                listNameFieldBackground: listNameFieldBackground,
                                listNameFieldBorder: listNameFieldBorder,
                                listNameFieldIcon: listNameFieldIcon,
                                onSubmitListName: confirmListNameEntry
                            )

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
                            ScanSelectedImageCardView(
                                image: selectedImage,
                                isRecognizingImage: isRecognizingImage,
                                progressText: scanProgressText,
                                runtimeLabel: scanProgressRuntimeLabel,
                                runtimeTint: scanProgressRuntimeTint,
                                runtimeIcon: scanProgressRuntimeIcon,
                                sectionStyle: sectionStyle,
                                onTap: {
                                    showingImagePreview = true
                                }
                            )
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

                        scanStatusMessageView
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

    var body: some View {
        applyingScanPresentationModifiers(
            to: applyingScanRootModifiers(
                to: ScrollViewReader { proxy in
                    scanRootContent(proxy: proxy)
                }
            )
        )
    }
}
