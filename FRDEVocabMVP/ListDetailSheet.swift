import SwiftUI

struct ListDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let list: VocabularyList
    let onClose: () -> Void
    let onEdit: (VocabularyItem) -> Void
    let onDelete: (VocabularyItem) -> Void
    @State private var itemPendingDeletion: VocabularyItem?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Liste",
                leadingTint: style.accent,
                onLeading: {
                    onClose()
                    dismiss()
                }
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(list.name)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)

                Text("\(list.items.count) Einträge")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .appCardBackground(style, intensity: 0.09)

            if list.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch keine Einträge in dieser Liste.")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.md)
                .appCardBackground(style, intensity: 0.09)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(list.items) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.french)
                                        .font(AppTheme.Typography.cardTitle)
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .lineLimit(2)
                                    Text(item.german)
                                        .font(AppTheme.Typography.body)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Text(item.cardType == .words ? "Wort" : "Phrase")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                if !list.isBuiltIn {
                                    Button {
                                        onEdit(item)
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        itemPendingDeletion = item
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(AppTheme.Spacing.sm)
                            .appChipBackground(style, intensity: 0.08, cornerRadius: 18)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(style.accent)
        .appScreenBackground(style)
        .alert("Wirklich löschen?", isPresented: Binding(
            get: { itemPendingDeletion != nil },
            set: { if !$0 { itemPendingDeletion = nil } }
        )) {
            Button("Nein", role: .cancel) {
                itemPendingDeletion = nil
            }
            Button("Ja", role: .destructive) {
                if let itemPendingDeletion {
                    onDelete(itemPendingDeletion)
                    self.itemPendingDeletion = nil
                }
            }
        } message: {
            Text(itemPendingDeletion.map { "„\($0.french)“ wird gelöscht." } ?? "")
        }
    }
}

