import SwiftUI

struct RenameListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    @Binding var listName: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isNameFocused: Bool
    @State private var isNameConfirmed = false

    private var trimmedName: String {
        listName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    private var fieldBackgroundColor: Color {
        if isNameConfirmed && canSave {
            return Color.green.opacity(0.20)
        }

        if isNameFocused {
            return Color.gray.opacity(0.16)
        }

        return Color.white.opacity(0.72)
    }

    private var fieldBorderColor: Color {
        if isNameConfirmed && canSave {
            return Color.green.opacity(0.55)
        }

        if isNameFocused {
            return Color.gray.opacity(0.45)
        }

        return style.accent.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Liste umbenennen",
                leadingTitle: "Abbrechen",
                trailingTitle: "Speichern",
                leadingTint: style.accent,
                trailingTint: canSave ? style.accent : AppTheme.Colors.textDisabled,
                onLeading: {
                    onCancel()
                    dismiss()
                },
                onTrailing: {
                    confirmName()
                    guard canSave else { return }
                    onSave()
                    dismiss()
                }
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Name der Liste")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                TextField("Name der Liste", text: $listName)
                    .font(AppTheme.Typography.body)
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .frame(minHeight: AppTheme.Layout.inputHeight)
                    .background(fieldBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(fieldBorderColor, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .onTapGesture {
                        isNameConfirmed = false
                    }
                    .onSubmit {
                        confirmName()
                    }

                Text(isNameConfirmed && canSave ? "Name bestätigt." : "Tippe den neuen Namen ein und drücke Return.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(isNameConfirmed && canSave ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.md)
            .appCardBackground(style, intensity: 0.09)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(style.accent)
        .appScreenBackground(style)
        .dismissKeyboardOnTap()
        .onAppear {
            isNameConfirmed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFocused = true
            }
        }
    }

    private func confirmName() {
        listName = trimmedName
        isNameConfirmed = canSave
        isNameFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

