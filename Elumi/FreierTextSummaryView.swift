import SwiftUI

/// Summary-Screen nach „Freier Text"-Analyse.
///
/// Designmäßig 1:1 an der Vokabel-Scan-Completion-Card orientiert:
/// Checkmark, „Analyse abgeschlossen", Wortzahl, Word-Class-Badges
/// und ein CTA-Button „Jetzt ansehen".
struct FreierTextSummaryView: View {
    let result: FreeTextResult
    let onViewResults: () -> Void
    let onDone: () -> Void

    private let sectionStyle: AppSectionStyle = .scan

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // X-Close oben rechts
                HStack {
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(AppTheme.Colors.secondarySurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, AppTheme.Spacing.lg)

                Spacer()

                // Hero-Card
                summaryCard
                    .padding(.horizontal, AppTheme.Layout.screenPadding)

                Spacer()
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Analyse abgeschlossen")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("1 Seite analysiert")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            // Total count
            Text(totalLabel)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            // Word class badges
            wordClassBadges

            // CTA
            Button(action: onViewResults) {
                Label("Jetzt ansehen", systemImage: "list.bullet.rectangle")
                    .font(AppTheme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: sectionStyle.accent))
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(sectionStyle.accent.opacity(AppTheme.CardIntensity.medium))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.Colors.success.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Word Class Badges

    private var wordClassBadges: some View {
        let badges: [(String, Int, Color)] = [
            ("Nomen", result.nomen.count, AppTheme.Colors.moduleNomen),
            // **2026-06-09** — Singular/Plural-Fix: bei genau 1 Verb
            // muss es „Verb" heißen, nicht „Verben".
            (result.verben.count == 1 ? "Verb" : "Verben", result.verben.count, AppTheme.Colors.moduleVerbs),
            ("Adj.", result.adjektive.count, AppTheme.Colors.moduleQuiz),
            ("Adv.", result.adverbien.count, AppTheme.Colors.modulePractice),
            ("Pron.", result.pronomen.count, AppTheme.Colors.textSecondary),
            ("Präp.", result.praepositionen.count, AppTheme.Colors.moduleScan),
            ("Konj.", result.konjunktionen.count, AppTheme.Colors.moduleScan),
            ("Sonst.", result.sonstige.count, AppTheme.Colors.textSecondary)
        ].filter { $0.1 > 0 }

        // Maximal 2 Zeilen à 4 Badges — bei vielen Kategorien
        // umbrechen, damit nichts abgeschnitten wird.
        return FlowLayout(spacing: 8) {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                wordClassBadge(count: badge.1, label: badge.0, color: badge.2)
            }
        }
    }

    private func wordClassBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 20, weight: .black, design: .rounded))
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .frame(minWidth: 60)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Helpers

    private var totalLabel: String {
        let count = result.totalEntryCount
        return count == 1 ? "1 Wort erkannt" : "\(count) Wörter erkannt"
    }
}

// MARK: - FlowLayout

/// Einfaches Flow-Layout: ordnet Kinder horizontal an und bricht
/// in die nächste Zeile um, wenn der Platz nicht reicht.
/// Genutzt für die Word-Class-Badges im Summary-Screen.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }

        let height = rows.enumerated().reduce(CGFloat.zero) { acc, pair in
            let rowHeight = pair.element.map { $0.size.height }.max() ?? 0
            return acc + rowHeight + (pair.offset > 0 ? spacing : 0)
        }
        let width = proposal.width ?? .infinity
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.size.height }.max() ?? 0
            // Zentriert in der Zeile
            let totalWidth = row.reduce(CGFloat.zero) { $0 + $1.size.width } + CGFloat(max(0, row.count - 1)) * spacing
            var x = bounds.minX + (bounds.width - totalWidth) / 2

            for item in row {
                item.subview.place(at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private struct LayoutItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutItem]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutItem]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = currentRowWidth > 0 ? size.width + spacing : size.width

            if currentRowWidth + neededWidth > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }

            rows[rows.count - 1].append(LayoutItem(subview: subview, size: size))
            currentRowWidth += (currentRowWidth > 0 ? spacing : 0) + size.width
        }

        return rows
    }
}
