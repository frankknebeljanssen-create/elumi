import SwiftUI

struct IdentifiableUUID: Identifiable {
    let id: UUID
    init(_ uuid: UUID) { self.id = uuid }
}

struct ReviewPairEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var french: String
    @State var german: String
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Französisch")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    TextField("Französisch", text: $french)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deutsch")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    TextField("Deutsch", text: $german)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textFieldStyle(.roundedBorder)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Eintrag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        onSave(french, german)
                    }
                    .bold()
                    .disabled(french.trimmingCharacters(in: .whitespaces).isEmpty || german.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

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
                        HStack(spacing: 6) {
                            // Warning badge for unsure entries
                            if !pair.isImportable {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(AppTheme.Colors.warning)
                                    .frame(width: 24)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(pair.french)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(2)
                                Text(pair.german)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(pair.isImportable ? AppTheme.Colors.textSecondary : AppTheme.Colors.warning)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)

                            // OK button — confirms unsure entry as importable
                            if !pair.isImportable {
                                Button {
                                    if let idx = previewPairs.firstIndex(where: { $0.id == pair.id }) {
                                        previewPairs[idx] = ImportPreviewPair(
                                            id: pair.id,
                                            french: pair.french,
                                            german: pair.german,
                                            cardType: pair.cardType,
                                            learningCategory: pair.learningCategory,
                                            note: pair.note,
                                            isImportable: true,
                                            isReviewed: true
                                        )
                                    }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(AppTheme.Colors.success)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                reviewEditingPairID = IdentifiableUUID(pair.id)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(sectionStyle.accent)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            Button {
                                previewPairs.removeAll { $0.id == pair.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(AppTheme.Colors.error.opacity(0.7))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(pair.isImportable ? AppTheme.Colors.surface : AppTheme.Colors.warning.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(pair.isImportable ? AppTheme.Colors.border : AppTheme.Colors.warning.opacity(0.5), lineWidth: pair.isImportable ? 1 : 2)
                        )
                    }
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.vertical, 12)
            }

            Divider().opacity(0.3)

            // Fixed footer — Import button only
            VStack(spacing: 0) {
                Button {
                    isShowingFullscreenReview = false
                    session.batchCompleted = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        importScannedText()
                    }
                } label: {
                    Label("Jetzt importieren", systemImage: "square.and.arrow.down.fill")
                        .font(AppTheme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .disabled(completePreviewPairCount == 0)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 16)
            }
            .background(AppTheme.Colors.surface)
        }
        .toolbar(.hidden, for: .navigationBar)
        .appScreenBackground(sectionStyle)
        .sheet(item: $reviewEditingPairID) { wrapper in
            if let index = previewPairs.firstIndex(where: { $0.id == wrapper.id }) {
                ReviewPairEditSheet(
                    french: previewPairs[index].french,
                    german: previewPairs[index].german
                ) { newFrench, newGerman in
                    previewPairs[index] = ImportPreviewPair(
                        id: previewPairs[index].id,
                        french: newFrench,
                        german: newGerman,
                        cardType: previewPairs[index].cardType,
                        learningCategory: previewPairs[index].learningCategory,
                        note: previewPairs[index].note,
                        isImportable: true,
                        isReviewed: true
                    )
                    reviewEditingPairID = nil
                }
            }
        }
    }

    var scanResultUnsureCount: Int {
        previewPairs.filter { !$0.isImportable }.count
    }

    var batchCompleteSummary: some View {
        let pageCount = max(session.batchTotalCount, 1)
        let totalPairs = previewPairs.count
        let unsureCount = scanResultUnsureCount

        return VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Analyse abgeschlossen")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            VStack(spacing: 5) {
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

                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.primary)
                    Text("\(completePreviewPairCount) Einträge bereit zum Import")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: unsureCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(unsureCount > 0 ? AppTheme.Colors.warning : AppTheme.Colors.success)
                    Text(unsureCount > 0 ? "\(unsureCount) unsichere Einträge" : "Keine unsicheren Einträge")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(unsureCount > 0 ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary)
                    Spacer()
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
            .padding(.top, 2)
        }
        .padding(16)
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
        if !isRecognizingImage, !session.batchCompleted {
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
                        Label("Zurück", systemImage: "arrow.left")
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
                                feedbackPlayer.playTabSwitch()
                                shouldAppendNextScan = false
                                selectedScanInputMethod = .camera
                                openCameraScanner()
                            },
                            onLibrary: {
                                guard !isRecognizingImage else { return }
                                feedbackPlayer.playTabSwitch()
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

                        if !session.batchCompleted {
                            if session.batchThumbnails.count > 1 {
                                // Multi-page: thumbnail strip
                                ScanBatchThumbnailCardView(
                                    thumbnails: session.batchThumbnails,
                                    currentIndex: session.batchCurrentIndex,
                                    isRecognizing: isRecognizingImage,
                                    progressText: scanProgressText,
                                    runtimeLabel: scanProgressRuntimeLabel,
                                    runtimeTint: scanProgressRuntimeTint,
                                    runtimeIcon: scanProgressRuntimeIcon,
                                    sectionStyle: sectionStyle
                                )
                            } else if let selectedImage {
                                // Single page
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
        Group {
            if isShowingImportCompletion, let ctx = importCompletionContext {
                importCompletionScreen(context: ctx)
            } else {
                applyingScanPresentationModifiers(
                    to: applyingScanRootModifiers(
                        to: ScrollViewReader { proxy in
                            scanRootContent(proxy: proxy)
                        }
                    )
                )
            }
        }
    }

    private func importCompletionScreen(context: ImportCompletionContext) -> some View {
        ImportCompletionView(
            context: context,
            onTrain: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .vocabulary,
                    shouldAutoStart: true
                )))
            },
            onArticles: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .articles,
                    shouldAutoStart: true
                )))
            },
            onVerbs: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .verbs,
                    shouldAutoStart: true
                )))
            },
            onFlashcards: {
                handleCompletionSelection(.flashcards(context.flashcardLaunchContext))
            },
            onQuiz: {
                handleCompletionSelection(.quiz(context.quizLaunchContext))
            },
            onViewList: {
                handleCompletionSelection(.lists(context.listLaunchContext))
            },
            onLater: {
                handleCompletionSelection(nil)
            }
        )
    }
}
