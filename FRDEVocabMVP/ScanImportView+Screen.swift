import SwiftUI

extension ScanImportView {
    // ── FULLSCREEN REVIEW SCREEN ──

    var scanFullscreenReview: some View {
        VStack(spacing: 0) {
            // Fixed header
            HStack {
                Button {
                    isShowingFullscreenReview = false
                } label: {
                    Label("Zurück", systemImage: "arrow.left")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(sectionStyle.accent)

                Spacer()

                Text("\(previewPairs.count) Einträge")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.vertical, 14)
            .background(AppTheme.Colors.surface.opacity(0.95))

            Divider().opacity(0.3)

            // Scrollable review list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(previewPairs) { pair in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pair.french)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(2)
                                Text(pair.german)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if !pair.isImportable {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.Colors.warning)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(pair.isImportable ? AppTheme.Colors.surface : AppTheme.Colors.warning.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(pair.isImportable ? AppTheme.Colors.border : AppTheme.Colors.warning.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.vertical, 12)
            }

            Divider().opacity(0.3)

            // Fixed footer — Import button
            VStack(spacing: 8) {
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
                    isShowingFullscreenReview = false
                    session.batchCompleted = false
                    importScannedText()
                } label: {
                    Label("Liste importieren", systemImage: "square.and.arrow.down.fill")
                        .font(AppTheme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .disabled(completePreviewPairCount == 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.vertical, 10)
            .background(AppTheme.Colors.surface.opacity(0.95))
        }
        .toolbar(.hidden, for: .navigationBar)
        .appScreenBackground(sectionStyle)
    }

    var scanResultUnsureCount: Int {
        previewPairs.filter { !$0.isImportable }.count
    }

    var batchCompleteSummary: some View {
        let pageCount = max(session.batchTotalCount, 1)
        let totalPairs = previewPairs.count
        let unsureCount = scanResultUnsureCount

        return VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Analyse abgeschlossen")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(pageCount == 1 ? "1 Seite analysiert" : "\(pageCount) Seiten analysiert")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.success)
                    Text("\(totalPairs) Vokabeln erkannt")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                }

                if unsureCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.warning)
                        Text("\(unsureCount) unsichere Einträge")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.warning)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 4)


            Button {
                isShowingFullscreenReview = true
            } label: {
                Label("Jetzt überprüfen", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: sectionStyle.accent))
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.Colors.success.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

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

                        // Summary screen (after analysis complete)
                        if session.batchCompleted && !previewPairs.isEmpty {
                            batchCompleteSummary
                        }

                        // Progress overlay during batch
                        // (handled below as overlay)

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

            // Batch analysis progress overlay
            if session.isBatchAnalysisInProgress {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(sectionStyle.accent)
                    Text(scanProgressText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("\(previewPairs.count) Vokabeln bisher erkannt")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
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
