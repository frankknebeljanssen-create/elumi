import SwiftUI

struct ScanImportDetailsCardView: View {
    let sectionStyle: AppSectionStyle
    @Binding var selectedCollectionPreset: ListCollectionPreset
    @Binding var listName: String
    @FocusState.Binding var isListNameFocused: Bool
    let isListNamePulseActive: Bool
    let listNameFieldBackground: Color
    let listNameFieldBorder: Color
    let listNameFieldIcon: String
    let onSubmitListName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name der Liste")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 10) {
                    Image(systemName: listNameFieldIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isListNameFocused ? AppTheme.Colors.warning : AppTheme.Colors.success)

                    TextField("Zum Beispiel: Unit 3", text: $listName)
                        .font(AppTheme.Typography.body)
                        .textFieldStyle(.plain)
                        .focused($isListNameFocused)
                        .submitLabel(.done)
                        .onSubmit(onSubmitListName)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(listNameFieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(listNameFieldBorder, lineWidth: isListNamePulseActive ? 2.5 : 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(isListNamePulseActive ? 1.015 : 1)
                .animation(.easeInOut(duration: 0.18), value: isListNameFocused)
                .animation(.easeInOut(duration: 0.16), value: isListNamePulseActive)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Ordner")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ListCollectionPreset.allCases) { preset in
                        Button {
                            selectedCollectionPreset = preset
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
                            .background(selectedCollectionPreset == preset ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .foregroundStyle(selectedCollectionPreset == preset ? .white : AppTheme.Colors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        selectedCollectionPreset = .other
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
        .padding(16)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}
