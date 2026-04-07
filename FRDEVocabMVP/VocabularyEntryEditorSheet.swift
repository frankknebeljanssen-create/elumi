import SwiftUI

struct VocabularyEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let title: String
    let sourceFieldLabel: String
    @Binding var frenchText: String
    @Binding var germanText: String
    @Binding var cardType: CardType
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        !frenchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !germanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: title,
                leadingTitle: "Abbrechen",
                trailingTitle: "Speichern",
                leadingTint: style.accent,
                trailingTint: canSave ? style.accent : AppTheme.Colors.textDisabled,
                onLeading: {
                    onCancel()
                    dismiss()
                },
                onTrailing: {
                    onSave()
                    dismiss()
                }
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                TextField(sourceFieldLabel, text: $frenchText)
                    .textFieldStyle(.roundedBorder)

                TextField("Deutsch", text: $germanText)
                    .textFieldStyle(.roundedBorder)

                Picker("Typ", selection: $cardType) {
                    ForEach(CardType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(AppTheme.Spacing.md)
            .appCardBackground(style, intensity: 0.09)

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(style.accent)
        .appScreenBackground(style)
        .dismissKeyboardOnTap()
    }
}

