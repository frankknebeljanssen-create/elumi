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

                // Wortarten-Verteilung — 2-zeilig, „X Verben" tappable → Verb-Lemma-Sheet
                POSBreakdownLine(
                    stats: FrenchListStatisticsAggregator.cachedStatistics(for: list.items),
                    font: .system(size: 12, weight: .semibold, design: .rounded),
                    layout: .twoLines
                )
                .padding(.top, 2)
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
                            // 3-zeiliges Layout:
                            //   Zeile 1: Original FR (volle Breite, für lange Phrasen)
                            //   Zeile 2: Übersetzung DE (volle Breite)
                            //   Zeile 3: Infinitiv links (falls Verb) · Wortart + Icons rechts
                            VStack(alignment: .leading, spacing: 4) {
                                // ─── Zeile 1: Französisch ─────────────────────────
                                // displayFrench ergänzt bei Nomen den Artikel (le/la/l') falls fehlend.
                                Text(FrenchLemmaFormatter.displayFrench(for: item))
                                    .font(AppTheme.Typography.cardTitle)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                // ─── Zeile 2: Deutsch ────────────────────────────
                                // displayGerman schreibt den ersten Buchstaben bei Nomen gross (hund → Hund).
                                Text(FrenchLemmaFormatter.displayGerman(for: item))
                                    .font(AppTheme.Typography.body)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                // ─── Zeile 3: Infinitiv (links) + Wortart + Icons (rechts) ───
                                let isVerbItem = itemIsVerb(item)
                                let labelColor: Color = isVerbItem
                                    ? Color(hex: "#C4B5FD")
                                    : AppTheme.Colors.textSecondary

                                HStack(spacing: 10) {
                                    // Links: „Infinitif: savoir" (nur bei Verben / Verb-Phrasen,
                                    // und nur wenn das Lemma vom Eintrag abweicht).
                                    // Gleicher Font wie die Übersetzungszeile darüber.
                                    if let hint = lemmaHint(for: item) {
                                        Text(hint)
                                            .font(AppTheme.Typography.body)
                                            .foregroundStyle(Color(hex: "#C4B5FD"))
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    // Rechts: Wortart-Pill (analog Lexikon-Badge — konsistent app-weit)
                                    Text(displayWordClass(for: item))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(labelColor)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(labelColor.opacity(0.14))
                                        .clipShape(Capsule())

                                    // Rechts: Edit + Trash (nur für eigene Listen) — mit klarem Abstand
                                    if !list.isBuiltIn {
                                        HStack(spacing: 14) {
                                            Button {
                                                onEdit(item)
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                                    .frame(width: 28, height: 28)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                itemPendingDeletion = item
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                                    .frame(width: 28, height: 28)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.leading, 4)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(AppTheme.Spacing.sm)
                            .appChipBackground(style, intensity: 0.08, cornerRadius: 14)
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

    // (wordClassBreakdownLines entfernt — `POSBreakdownLine` rendert direkt)

    /// Zentrale App-Bezeichnung (FrenchLemmaFormatter.wordClassLabel).
    /// Single Source of Truth — gleiche Logik überall, inkl. Pronomen/Präposition/Interjektion.
    private func displayWordClass(for item: VocabularyItem) -> String {
        FrenchLemmaFormatter.wordClassLabel(for: item)
    }

    /// Optionaler Lemma-Hinweis in Klammern hinter dem französischen Text.
    private func lemmaHint(for item: VocabularyItem) -> String? {
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        return FrenchLemmaFormatter.makeLemmaHint(from: result)
    }

    /// Ist dieser Eintrag ein ECHTES Verb (Einzelwort-Verb)?
    /// NUR dann wird das rechte Label „Verb" violett eingefärbt.
    /// Phrasen bleiben auch mit Verb-Lemma im Label neutral — nur der
    /// Infinitiv in Klammern (links neben dem FR-Text) wird violett.
    private func itemIsVerb(_ item: VocabularyItem) -> Bool {
        if let stored = item.wordClass?.lowercased(), !stored.isEmpty {
            return stored == "verb"
        }
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        if result.specialCategory != nil { return false }
        return result.primaryPos == .verb
    }
}

