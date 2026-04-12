import SwiftUI
import UIKit

extension FlashcardsView {
    func flashcardFace(text: String, isAnswerSide: Bool, languageCode: String, wordClassLabel: String? = nil) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(isAnswerSide ? AppTheme.Colors.secondarySurface : AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isAnswerSide ? AppTheme.Colors.success.opacity(0.15) : sectionStyle.accent.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isAnswerSide ? AppTheme.Colors.success.opacity(0.5) : sectionStyle.accent.opacity(0.3),
                        lineWidth: isAnswerSide ? 1.5 : 1.5
                    )
            )
            .overlay(alignment: .center) {
                VStack(spacing: 6) {
                    Text(text)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(4)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)

                    if let wordClassLabel, !wordClassLabel.isEmpty {
                        Text("(\(wordClassLabel))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, isAnswerSide ? 14 : 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: flashcardFaceHeight)
            .shadow(color: sectionStyle.accent.opacity(isAnswerSide ? 0 : 0.18), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(isAnswerSide ? 0.06 : 0.12), radius: 16, x: 0, y: 8)
    }

    func selectionChip(title: String, value: String) -> some View {
        CompactSelectionChip(style: sectionStyle, title: title, value: value)
    }
}
