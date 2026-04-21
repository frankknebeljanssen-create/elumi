import SwiftUI

extension ScanImportView {
    @ViewBuilder
    func scanPreparationSheet(previewImage: UIImage) -> some View {
        // **Vereinheitlichter Review-Workflow** (Camera + Galerie):
        // bisher hatte der Galerie-Pfad nur „Abbrechen" + „Übernehmen
        // und analysieren". Jetzt: dieselben drei Aktionen wie der
        // Camera-Preview-Stage — Zuschneiden, Verwenden, Neu wählen.
        // Damit fühlt sich Galerie identisch an wie Camera.
        //
        // **Quality-Banner + Auto-Optimize** (wieder eingebaut): unter
        // dem Bild, über den Aktionen. Analysiert das Bild beim Erscheinen
        // des Sheets via `ImageQualityAnalyzer.analyzeAsync` und zeigt:
        //   • Banner mit Score + priorisierten Hinweisen, wenn
        //     `report.level != .good`.
        //   • „Auto optimieren"-Button, wenn der Report ein auto-fixbares
        //     Issue (unscharf / wenig Kontrast / Schatten / zu dunkel)
        //     enthält. Tap ersetzt `session.preparedScanImage` durch die
        //     optimierte Variante und re-analysiert den neuen Report.
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

            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Quality-Banner + Auto-Optimize-Card (nur wenn Report vorliegt).
            preparationQualitySection(baseImage: previewImage)

            // **Drei-Button-Aktionen** (gleich für Camera + Galerie):
            //   • Zuschneiden — öffnet ManualCropSheet, Ergebnis ersetzt
            //     `scanPreparationPreviewImage`
            //   • Übernehmen und analysieren — Primary
            //   • Neu wählen — schließt Sheet + öffnet Galerie erneut
            VStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    let imageToCrop = scanPreparationPreviewImage ?? previewImage
                    presentManualCrop(from: imageToCrop, target: ManualCropTarget.scanPreparation)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crop")
                            .font(.system(size: 15, weight: .bold))
                        Text("Zuschneiden")
                            .font(AppTheme.Typography.button)
                    }
                    .foregroundStyle(sectionStyle.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Layout.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .fill(sectionStyle.accent.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(sectionStyle.accent.opacity(0.55), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    let imageToAnalyze = scanPreparationPreviewImage ?? previewImage
                    showingScanPreparation = false
                    recognizeText(from: imageToAnalyze)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Übernehmen und analysieren")
                            .font(AppTheme.Typography.button)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                Button {
                    showingScanPreparation = false
                    shouldAppendNextScan = false
                    // Galerie-Picker erneut öffnen (kleine Verzögerung,
                    // damit das Sheet erst sauber dismissen kann).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        showingPhotoLibrary = true
                    }
                } label: {
                    Text("Neu wählen")
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.Layout.buttonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(AppTheme.Colors.secondarySurface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .task(id: ObjectIdentifier(previewImage)) {
            // Quality-Analyse nur neu fahren, wenn das Bild wechselt
            // (neu ausgewählt, neu zugeschnitten, optimiert). Die
            // `task(id:)`-Variante nutzt die Image-Identity als Key,
            // sodass SwiftUI die Task bei Wechsel sauber cancelled und
            // eine neue startet.
            await analyzePreparationImageQuality(previewImage)
        }
    }

    // MARK: - Quality-Banner + Auto-Optimize (Preparation-Sheet)

    /// Rendert unter dem Bild einen kompakten Quality-Banner (wenn
    /// `level != .good`) und darunter den Auto-Optimize-Button (wenn
    /// ein auto-fixbares Issue vorliegt). Beide Teile sind optional —
    /// ein perfektes Bild zeigt **nichts** davon, damit die Sheet-
    /// Hierarchie nicht überladen wirkt.
    @ViewBuilder
    private func preparationQualitySection(baseImage: UIImage) -> some View {
        if let report = scanPreparationQualityReport {
            VStack(spacing: 10) {
                if report.level != .good {
                    preparationQualityBanner(report: report)
                }
                if report.hasAutoFixableIssue || scanPreparationWasOptimized {
                    preparationAutoOptimizeButton(
                        report: report,
                        baseImage: baseImage
                    )
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: report.level)
            .animation(.easeInOut(duration: 0.2), value: scanPreparationWasOptimized)
        }
    }

    /// Kompakter Hinweis-Block: Icon + Headline + Top-Hinweise +
    /// Score-Pill. Farbton richtet sich nach dem Qualitäts-Level
    /// (`medium` warm-gelb, `poor` kräftig-rot).
    private func preparationQualityBanner(
        report: ImageQualityAnalyzer.Report
    ) -> some View {
        let tint: Color = {
            switch report.level {
            case .good:   return AppTheme.Colors.success
            case .medium: return AppTheme.Colors.warning
            case .poor:   return AppTheme.Colors.error
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.level == .poor
                  ? "exclamationmark.triangle.fill"
                  : "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(report.headline)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text(report.scoreDisplay)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.15)))
                }
                if !report.combinedMessage.isEmpty {
                    Text(report.combinedMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    /// „Auto optimieren"-Button mit drei visuellen Zuständen:
    ///   • **Inaktiv** (Report liefert auto-fixbare Issues): blaue Soft-
    ///     Card mit Zauberstab-Icon + „Auto optimieren" — tap triggert
    ///     den Optimize-Pass.
    ///   • **Laufend**: Spinner + „Optimiere…", kein Tap möglich.
    ///   • **Angewandt**: grüne Pille „Optimiert — bereit zum Analysieren"
    ///     — zeigt dem User, dass die Verbesserung im Bild steckt, das
    ///     als nächstes an die OCR/KI-Pipeline geht.
    @ViewBuilder
    private func preparationAutoOptimizeButton(
        report: ImageQualityAnalyzer.Report,
        baseImage: UIImage
    ) -> some View {
        if scanPreparationWasOptimized {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Optimiert — bereit zum Analysieren")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.success)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.success.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(AppTheme.Colors.success.opacity(0.45), lineWidth: 1)
            )
        } else {
            Button {
                Task { await runPreparationAutoOptimize(baseReport: report) }
            } label: {
                HStack(spacing: 8) {
                    if scanPreparationIsOptimizing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppTheme.Colors.primary)
                            .scaleEffect(0.8)
                        Text("Optimiere…")
                            .font(AppTheme.Typography.button)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 15, weight: .bold))
                        Text("Auto optimieren")
                            .font(AppTheme.Typography.button)
                    }
                }
                .foregroundStyle(AppTheme.Colors.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.primary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.primary.opacity(0.55), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(scanPreparationIsOptimizing)
        }
    }

    /// Analysiert das aktuell angezeigte Preview-Bild und setzt den
    /// Qualitäts-Report. Resettet die „optimiert"-Flagge, wenn eine
    /// neue Bild-Identity reinkommt (Retake, Crop, Neuauswahl).
    @MainActor
    private func analyzePreparationImageQuality(_ image: UIImage) async {
        // Wenn das neue Bild **nicht** die aus einer früheren
        // Optimierung stammende `preparedScanImage` ist, setzen wir die
        // „wurde optimiert"-Flagge zurück — der User hat offensichtlich
        // neu gewählt, zugeschnitten oder einen frischen Scan gemacht.
        // Sonst bliebe der grüne „Optimiert"-Status hängen und der
        // Button käme nie zurück, obwohl das Bild inzwischen ein
        // anderes ist.
        if let optimized = session.preparedScanImage,
           optimized === image {
            // Wir schauen gerade auf die optimierte Version — Flag
            // belassen.
        } else {
            scanPreparationWasOptimized = false
        }

        let report = await ImageQualityAnalyzer.analyzeAsync(
            image: image,
            rectangleMetrics: nil,
            hints: .init(isTextDense: false)
        )
        scanPreparationQualityReport = report
        #if DEBUG
        print("🪄 [PrepSheet-Quality] \(report.debugSummary)")
        #endif
    }

    /// Auto-Optimize-Pass: wendet das aus den Issues empfohlene
    /// `EnhancementProfile` auf das Bild an, schreibt das Resultat in
    /// `session.preparedScanImage` (womit `scanPreparationPreviewImage`
    /// ab jetzt die optimierte Variante zurückgibt) und re-analysiert
    /// für den neuen Report.
    @MainActor
    private func runPreparationAutoOptimize(
        baseReport: ImageQualityAnalyzer.Report
    ) async {
        guard !scanPreparationIsOptimizing else { return }
        let base = scanPreparationPreviewImage ?? originalScanImage
        guard let base else { return }
        scanPreparationIsOptimizing = true
        defer { scanPreparationIsOptimizing = false }

        let profile = ImageQualityAnalyzer.EnhancementProfile.recommended(
            for: baseReport.issues
        )
        let optimized = await ImageEnhancer.optimizeAsync(base, profile: profile)
        session.preparedScanImage = optimized
        session.usePreparedScanImage = true
        scanPreparationWasOptimized = true

        let newReport = await ImageQualityAnalyzer.analyzeAsync(
            image: optimized,
            rectangleMetrics: nil,
            hints: .init(isTextDense: false)
        )
        scanPreparationQualityReport = newReport
        #if DEBUG
        let delta = newReport.overallScore - baseReport.overallScore
        print(String(
            format: "🪄 [PrepSheet-AutoOpt] profile=%@ Δ=%+.3f (base=%.2f → opt=%.2f)",
            profile.debugLabel, delta,
            baseReport.overallScore, newReport.overallScore
        ))
        #endif
    }
}
