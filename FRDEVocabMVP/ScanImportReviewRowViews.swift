import SwiftUI

struct ScanEditablePreviewRowView: View {
    let pair: ImportPreviewPair
    let assessment: ImportPreviewAssessment
    let sourceLanguageLabel: String
    let cardTypeTint: Color
    let category: ScanLearningCategory?
    let categoryTint: Color?
    let sourceText: Binding<String>
    let targetText: Binding<String>
    @FocusState.Binding var focusedReviewField: ScanReviewFieldFocus?
    let sourceFieldID: String
    let targetFieldID: String
    let onMarkReviewed: () -> Void
    let onDelete: () -> Void
    let note: String?
    /// Optionales Wortarten-Label inkl. Verb-Infinitiv ("Verb (être)") —
    /// wird über dem Source-Feld als kleiner Badge angezeigt. Wenn nil,
    /// erscheint kein Badge (z. B. für ungeklärte Wortarten).
    var wordClassLabel: String? = nil
    var wordClassColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(sourceLanguageLabel)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        // Wortart-Badge mit Verb-Infinitiv (z. B. „Verb (être)")
                        if let wordClassLabel, !wordClassLabel.isEmpty {
                            Text(wordClassLabel)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(wordClassColor ?? AppTheme.Colors.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (wordClassColor ?? AppTheme.Colors.textSecondary).opacity(0.15)
                                )
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 0)
                    }

                    TextField(sourceLanguageLabel, text: sourceText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...2)
                        .font(.system(size: 14, design: .rounded))
                        .id(sourceFieldID)
                        .focused($focusedReviewField, equals: .source(pair.id))

                    Text("Deutsch")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    TextField("Deutsch", text: targetText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...2)
                        .font(.system(size: 14, design: .rounded))
                        .id(targetFieldID)
                        .focused($focusedReviewField, equals: .target(pair.id))
                }

                HStack(spacing: 8) {
                    if assessment == .suspicious {
                        Button(action: onMarkReviewed) {
                            Text("OK")
                                .font(AppTheme.Typography.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.success)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.Colors.success.opacity(0.16))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            if assessment == .suspicious {
                Text("Unsicher, bitte prüfen.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.warning)
            } else if assessment == .incomplete {
                Text("Unvollständig.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .id(pair.id)
        .padding(10)
        .background(previewAssessmentBackground(assessment))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(previewAssessmentBorder(assessment), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func previewAssessmentBackground(_ assessment: ImportPreviewAssessment) -> Color {
        switch assessment {
        case .complete:
            return AppTheme.Colors.success.opacity(0.12)
        case .suspicious:
            return AppTheme.Colors.warning.opacity(0.12)
        case .incomplete:
            return AppTheme.Colors.secondarySurface.opacity(0.62)
        }
    }

    private func previewAssessmentBorder(_ assessment: ImportPreviewAssessment) -> Color {
        switch assessment {
        case .complete:
            return AppTheme.Colors.success.opacity(0.32)
        case .suspicious:
            return AppTheme.Colors.warning.opacity(0.34)
        case .incomplete:
            return AppTheme.Colors.border
        }
    }
}

struct ScanRecognizedTextPreviewRowView: View {
    let pair: ImportPreviewPair
    let categoryTitle: String
    let categoryTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ScanModeBadgeView(title: categoryTitle, tint: categoryTint)
                Spacer()
            }

            Text(pair.french)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !pair.german.isEmpty {
                Text(pair.german)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Nur Kontext, wird nicht importiert.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(10)
        .background(AppTheme.Colors.secondarySurface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
