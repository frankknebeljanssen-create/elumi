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

    private func resolvedWordClass(for pair: ImportPreviewPair) -> String? {
        if let wc = pair.wordClass, !wc.isEmpty { return wc }
        // Try full text first
        if let wc = StandardVocabularyLoader.wordClass(for: pair.french) { return wc }
        // For phrases: check individual words
        let words = pair.french.split(separator: " ").map(String.init)
        if words.count > 1 {
            for word in words {
                if let wc = StandardVocabularyLoader.wordClass(for: word) { return wc }
            }
        }
        return nil
    }

    var batchCompleteSummary: some View {
        let pageCount = max(session.batchTotalCount, 1)
        let totalPairs = previewPairs.count
        let unsureCount = scanResultUnsureCount

        // Word class counts — check wordClass, then individual words via inflection DB
        var nounCount = 0
        var verbCount = 0
        var adjCount = 0
        for pair in previewPairs {
            let wc = resolvedWordClass(for: pair)
            if wc == "noun" { nounCount += 1 }
            else if wc == "verb" { verbCount += 1 }
            else if wc == "adjective" { adjCount += 1 }
            else {
                // Fallback: check if any word in the french text is a known verb/noun/adj
                let words = pair.french.lowercased()
                    .replacingOccurrences(of: "'", with: " ")
                    .replacingOccurrences(of: "\u{2019}", with: " ")
                    .split(separator: " ").map(String.init)
                let detectedWC = words.compactMap { StandardVocabularyLoader.wordClass(for: $0) }.first
                if detectedWC == "verb" { verbCount += 1 }
                else if detectedWC == "noun" { nounCount += 1 }
                else if detectedWC == "adjective" { adjCount += 1 }
            }
        }
        let otherCount = totalPairs - nounCount - verbCount - adjCount

        return VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Analyse abgeschlossen")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(pageCount == 1 ? "1 Seite analysiert" : "\(pageCount) Seiten analysiert")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            // Total count big
            Text("\(totalPairs) Vokabeln erkannt")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            // Word class breakdown — 2-zeilig pills
            HStack(spacing: 10) {
                if nounCount > 0 {
                    wordClassBadge(count: nounCount, label: "Nomen", color: AppTheme.Colors.moduleNomen)
                }
                if verbCount > 0 {
                    wordClassBadge(count: verbCount, label: "Verben", color: AppTheme.Colors.moduleVerbs)
                }
                if adjCount > 0 {
                    wordClassBadge(count: adjCount, label: "Adjektive", color: AppTheme.Colors.moduleQuiz)
                }
                if otherCount > 0 {
                    wordClassBadge(count: otherCount, label: "Andere", color: AppTheme.Colors.textSecondary)
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.primary)
                    Text("\(completePreviewPairCount) Eintr\u{00E4}ge bereit zum Import")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                }

                if unsureCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.warning)
                        Text("\(unsureCount) unsichere Eintr\u{00E4}ge")
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

    private func wordClassBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 20, weight: .black, design: .rounded))
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .frame(minWidth: 60)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

                if session.batchCompleted && !previewPairs.isEmpty {
                    // Summary: nur Summary zentriert, keine Auswahl-Buttons
                    Spacer(minLength: 8)
                    batchCompleteSummary
                    Spacer(minLength: 8)
                } else {
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
            } // else (nicht batchCompleted)
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
            onNomen: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .nouns,
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
            onVerbforms: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .verbforms,
                    shouldAutoStart: false
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
