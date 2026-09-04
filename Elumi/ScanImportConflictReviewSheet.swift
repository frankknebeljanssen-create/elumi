import SwiftUI

/// **Konflikt-Review** vor dem finalen Apply, falls der `MergePlan`
/// Items mit teil-überlappenden Einträgen in der Ziel-Liste enthält.
///
/// Pro Konflikt sieht der User:
///   • bestehender Eintrag (mit klarer Markierung)
///   • neuer Eintrag aus dem Scan
///   • Toggle-Pärchen: „Bestehenden behalten" (Default) vs.
///                     „Mit neuem überschreiben"
///
/// Erst nach „Import bestätigen" werden die Entscheidungen
/// auf den Plan zurück geschrieben und der Caller persistiert.
///
/// Wichtig: KEINE doppelten Einträge entstehen. Entweder existing
/// bleibt, oder existing wird durch incoming **ersetzt**. Niemals beide.
struct ScanImportConflictReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var workingConflicts: [ImportConflict]
    let safeAddCount: Int
    let duplicateCount: Int
    let targetListName: String
    let onConfirm: ([ImportConflict]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    summaryHeader
                    ForEach($workingConflicts) { $conflict in
                        conflictCard($conflict)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Konflikte prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                confirmFooter
            }
        }
    }

    // MARK: - Header

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bitte folgende Einträge überprüfen")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Lernliste \(targetListName) hat ähnliche Einträge. Wähle pro Konflikt, was passieren soll.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                summaryChip(label: "Sichere Adds", count: safeAddCount, color: AppTheme.Colors.cta)
                summaryChip(label: "Duplikate", count: duplicateCount, color: AppTheme.Colors.textSecondary)
                summaryChip(label: "Konflikte", count: workingConflicts.count, color: AppTheme.Colors.warning)
            }
            .padding(.top, 6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
    }

    private func summaryChip(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    // MARK: - Conflict-Card

    @ViewBuilder
    private func conflictCard(_ conflict: Binding<ImportConflict>) -> some View {
        let model = conflict.wrappedValue
        VStack(alignment: .leading, spacing: 10) {
            Text(matchKindLabel(model.matchKind))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.warning)
                .textCase(.uppercase)

            entryRow(label: "Bestehend", item: model.existing, isMuted: model.resolution == .replaceWithIncoming)
            entryRow(label: "Neu", item: model.incoming, isMuted: model.resolution == .keepExisting)

            HStack(spacing: 8) {
                resolutionButton(
                    title: "Bestehenden behalten",
                    icon: "checkmark.circle",
                    isActive: model.resolution == .keepExisting,
                    action: { conflict.wrappedValue.resolution = .keepExisting }
                )
                resolutionButton(
                    title: "Mit neuem überschreiben",
                    icon: "arrow.triangle.2.circlepath",
                    isActive: model.resolution == .replaceWithIncoming,
                    action: { conflict.wrappedValue.resolution = .replaceWithIncoming }
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
    }

    private func matchKindLabel(_ kind: ImportConflict.MatchKind) -> String {
        switch kind {
        case .sameSourceDifferentTarget: return "Gleiche Französisch-Form"
        case .sameTargetDifferentSource: return "Gleiche Deutsch-Übersetzung"
        }
    }

    private func entryRow(label: String, item: VocabularyItem, isMuted: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.french)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(item.german)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .opacity(isMuted ? 0.45 : 1.0)
    }

    private func resolutionButton(
        title: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isActive ? .white : AppTheme.Colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? AppTheme.Colors.cta : AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isActive ? Color.clear : AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var confirmFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            Button {
                dismiss()
                let resolved = workingConflicts
                DispatchQueue.main.async { onConfirm(resolved) }
            } label: {
                Text("Import bestätigen")
                    .font(AppTheme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(AppTheme.Colors.surface)
    }
}
