import SwiftUI
import UIKit

extension ScanImportView {
    func showScanToast(
        _ message: String,
        isWarning: Bool = false,
        delay: TimeInterval = 0
    ) {
        session.showToast(message, isWarning: isWarning, delay: delay)
    }

    func presentScanAIInfo(_ message: String) {
        session.presentScanAIInfo(message)
    }

    var scanToastView: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    (scanToastIsWarning ? AppTheme.Colors.warning : AppTheme.Colors.success).opacity(0.25),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    func scanAIFallbackPopupMessage(
        for result: ScanProviderResult,
        aiConfigured: Bool
    ) -> String? {
        let aiWarnings = result.warnings.filter { $0.hasPrefix("ai_") }
        let mentionsOCRFallback = result.importMessage.localizedCaseInsensitiveContains("OCR")
        guard !aiWarnings.isEmpty || mentionsOCRFallback else { return nil }

        let headline: String
        if aiWarnings.contains("ai_provider_unavailable") {
            headline = aiConfigured
                ? "GPT war diesmal nicht verfügbar. Bitte nochmal versuchen."
                : "GPT ist in diesem Build nicht konfiguriert. Bitte API-Key prüfen."
        } else if aiWarnings.contains("ai_http_401") {
            headline = "GPT konnte nicht genutzt werden. Bitte den API-Key prüfen."
        } else if aiWarnings.contains("ai_http_429") {
            headline = "GPT-Limit erreicht. Bitte später nochmal versuchen."
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

    func startScanProgressFeedback() {
        session.startProgressFeedback()
    }

    func stopScanProgressFeedback() {
        session.stopProgressFeedback()
    }

    @ViewBuilder
    func imagePreviewSheet(for image: UIImage) -> some View {
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
