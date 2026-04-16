import SwiftUI

extension ScanImportView {
    var scanTypeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typ")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(CardType.allCases) { item in
                    Button {
                        importType = item
                    } label: {
                        Text(item.rawValue)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 40)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(importType == item ? .white : AppTheme.Colors.textPrimary)
                            .background(importType == item ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Review")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer()

                Text(previewCounterLabel)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            if canRescanCurrentSelection {
                Button {
                    restartCurrentScan()
                } label: {
                    Label("Erneut scannen", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))
                .disabled(isRecognizingImage)
                .opacity(isRecognizingImage ? 0.55 : 1)
            }

            HStack(spacing: 8) {
                if !previewPairs.isEmpty {
                    ScanModeBadgeView(title: analysisPathDebugLabel, tint: analysisPathDebugTint)
                }
                if incompletePreviewPairCount > 0 {
                    ScanModeBadgeView(title: "\(incompletePreviewPairCount) offen", tint: AppTheme.Colors.warning)
                }
                Spacer(minLength: 0)
            }

            if activeScanMode == .text && !freeTextCategoryCounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(freeTextCategoryCounts, id: \.0) { category, count in
                            ScanModeBadgeView(title: "\(category.title) \(count)", tint: learningCategoryTint(category))
                        }
                    }
                }
            }

            if hasScanDevDebugInfo {
                ScanReviewDebugInfoView(
                    analysisPathDebugLabel: analysisPathDebugLabel,
                    analysisPathDebugTint: analysisPathDebugTint,
                    scanDurationDebugLabel: scanDurationDebugLabel,
                    lastScanAIConfigured: lastScanAIConfigured,
                    lastScanWarnings: lastScanWarnings,
                    lastScanImportDebugMessage: lastScanImportDebugMessage
                )
            }

            if hasScanEvalDebugReport, let scanEvalSuiteReport {
                ScanEvalDebugReportView(scanEvalSuiteReport: scanEvalSuiteReport)
            }

            if isEditingReviewField {
                previewListContent
            } else {
                ScrollView {
                    previewListContent
                }
                .frame(maxHeight: 320)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    var canRescanCurrentSelection: Bool {
        scanPreparationPreviewImage != nil || selectedImage != nil
    }

    var canRetryCurrentScanAfterAIAlert: Bool {
        canRescanCurrentSelection && !isRecognizingImage
    }

    var isCompactReviewSummary: Bool {
        reviewSummary.hasPrefix("Die Vorlage wurde")
    }
}
