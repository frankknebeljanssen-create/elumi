import SwiftUI

extension ScanImportView {
    @ViewBuilder
    var previewListContent: some View {
        if activeScanMode == .text {
            freeTextPreviewList
        } else {
            standardPreviewList
        }
    }

    var standardPreviewList: some View {
        VStack(spacing: 8) {
            ForEach(visiblePreviewPairs) { pair in
                editablePreviewRow(for: pair)
            }
        }
    }

    var freeTextPreviewList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ScanLearningCategory.allCases, id: \.self) { category in
                let categoryPairs = visiblePreviewPairs.filter { $0.learningCategory == category }
                if !categoryPairs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(category.title)
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            ScanModeBadgeView(title: "\(categoryPairs.count)", tint: learningCategoryTint(category))
                        }

                        VStack(spacing: 8) {
                            ForEach(categoryPairs) { pair in
                                if pair.isImportable {
                                    editablePreviewRow(for: pair, category: category)
                                } else {
                                    recognizedTextPreviewRow(for: pair, category: category)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func learningCategoryTint(_ category: ScanLearningCategory) -> Color {
        switch category {
        case .recognizedText:
            return AppTheme.Colors.primary
        case .verbs:
            return AppTheme.Colors.success
        case .phrases:
            return AppTheme.Colors.moduleQuiz
        case .grammar:
            return AppTheme.Colors.warning
        }
    }
}
