import SwiftUI

enum ScanReviewFieldFocus: Hashable {
    case source(UUID)
    case target(UUID)
}

struct ScanModeBadgeView: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }
}

struct ScanReviewDebugInfoView: View {
    let analysisPathDebugLabel: String
    let analysisPathDebugTint: Color
    let scanDurationDebugLabel: String?
    let lastScanAIConfigured: Bool
    let lastScanWarnings: [String]
    let lastScanImportDebugMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ScanModeBadgeView(title: "DEV DEBUG", tint: AppTheme.Colors.warning)
                ScanModeBadgeView(title: analysisPathDebugLabel, tint: analysisPathDebugTint)
                if let scanDurationDebugLabel {
                    ScanModeBadgeView(title: scanDurationDebugLabel, tint: AppTheme.Colors.primary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI konfiguriert: \(lastScanAIConfigured ? "ja" : "nein")")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if !lastScanWarnings.isEmpty {
                    Text("Warnings: \(lastScanWarnings.joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !lastScanImportDebugMessage.isEmpty {
                    Text(lastScanImportDebugMessage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(AppTheme.Colors.secondarySurface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ScanEvalDebugReportView: View {
    let scanEvalSuiteReport: ScanEvalSuiteReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ScanModeBadgeView(
                    title: scanEvalSuiteReport.passed ? "DEV EVAL PASS" : "DEV EVAL FAIL",
                    tint: scanEvalSuiteReport.passed ? AppTheme.Colors.success : AppTheme.Colors.warning
                )

                if let fixtureImagePath = scanEvalSuiteReport.fixtureImagePath {
                    Text((fixtureImagePath as NSString).lastPathComponent)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            ForEach(scanEvalSuiteReport.reports, id: \.fixtureID) { report in
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(report.summary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(report.passed ? AppTheme.Colors.success : AppTheme.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(AppTheme.Colors.secondarySurface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
