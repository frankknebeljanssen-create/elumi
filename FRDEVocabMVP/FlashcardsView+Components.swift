import SwiftUI
import UIKit

extension FlashcardsView {
    func flashcardFace(text: String, isAnswerSide: Bool, languageCode: String) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(isAnswerSide ? AppTheme.Colors.secondarySurface : AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isAnswerSide ? AppTheme.Colors.warning.opacity(0.14) : sectionStyle.accent.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isAnswerSide ? AppTheme.Colors.borderStrong : AppTheme.Colors.border, lineWidth: 1)
            )
            .overlay(alignment: .center) {
                Text(text)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isAnswerSide ? AppTheme.Colors.textPrimary : AppTheme.Colors.textPrimary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, isAnswerSide ? 14 : 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: flashcardFaceHeight)
    }

    func selectionChip(title: String, value: String) -> some View {
        CompactSelectionChip(style: sectionStyle, title: title, value: value)
    }
}
