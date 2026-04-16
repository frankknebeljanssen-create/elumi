import SwiftUI

extension ScanImportView {
    @ViewBuilder
    func scanPreparationSheet(previewImage: UIImage) -> some View {
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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(
                hasAlternatePreparedImage
                ? "Prüfe kurz, ob der Zuschnitt stimmt. Danach startet die Analyse."
                : "Prüfe das Bild kurz. Danach startet die Analyse."
            )
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
}
