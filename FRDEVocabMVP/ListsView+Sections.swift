import SwiftUI

extension ListsView {
    var toastView: some View {
        HStack(spacing: 10) {
            Image(systemName: toastIsSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(toastIsSuccess ? AppTheme.Colors.success : AppTheme.Colors.warning)

            Text(toastMessage)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke((toastIsSuccess ? AppTheme.Colors.success : AppTheme.Colors.warning).opacity(0.25), lineWidth: 1)
        )
        .shadow(color: AppTheme.Shadow.card.color, radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    func collectionPresetPicker(
        selectedPreset: Binding<ListCollectionPreset>,
        includeHeading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if includeHeading {
                Text("Sammlung")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ListCollectionPreset.allCases) { preset in
                    Button {
                        selectedPreset.wrappedValue = preset
                    } label: {
                        HStack {
                            Text(preset.rawValue)
                                .font(AppTheme.Typography.body)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(selectedPreset.wrappedValue == preset ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                        .foregroundStyle(selectedPreset.wrappedValue == preset ? .white : AppTheme.Colors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    selectedPreset.wrappedValue = .other
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(AppTheme.Colors.secondarySurface)
                        .foregroundStyle(sectionStyle.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
