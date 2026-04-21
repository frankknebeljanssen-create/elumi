import SwiftUI

extension ScanImportView {
    @ViewBuilder
    func scanPreparationSheet(previewImage: UIImage) -> some View {
        // **Vereinheitlichter Review-Workflow** (Camera + Galerie):
        // bisher hatte der Galerie-Pfad nur „Abbrechen" + „Übernehmen
        // und analysieren". Jetzt: dieselben drei Aktionen wie der
        // Camera-Preview-Stage — Zuschneiden, Verwenden, Neu wählen.
        // Damit fühlt sich Galerie identisch an wie Camera.
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
    }
}
