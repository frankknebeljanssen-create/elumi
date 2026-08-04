import SwiftUI

/// Ergebnis-Screen für „Freier Text".
///
/// Zeigt Originaltext, Übersetzung und kuratierte Wortklassen-Listen.
/// Nomen und Verben sind offen, sekundäre Wortarten eingeklappt.
/// Über den „Speichern"-Button im Header kann der Nutzer die Analyse
/// als neue Vokabelliste im bestehenden Listensystem ablegen.
struct FreierTextResultView: View {
    let result: FreeTextResult
    let onDone: () -> Void

    var listStore: VocabularyListStore? = nil
    var onImportComplete: ((ImportCompletionContext) -> Void)? = nil

    private let sectionStyle: AppSectionStyle = .scan

    // MARK: - Save-Sheet State

    @State private var showingSaveSheet = false
    @State private var hasSaved = false
    @State private var pendingImportContext: ImportCompletionContext?

    // MARK: - Toast State

    @State private var toastMessage = ""
    @State private var isShowingToast = false
    @State private var toastDismissWorkItem: DispatchWorkItem?

    // MARK: - Collapsible State

    /// Nomen + Verben standardmäßig offen, Rest eingeklappt.
    /// User kann jede Sektion per Tap auf den Header auf-/zuklappen.
    @State private var expandedSections: Set<String> = ["nomen", "verben"]

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if result.hasAnyEntries || result.hasAnyTextBlock {
                    scrollContent
                } else {
                    emptyState
                }

                footer
            }

            // Toast-Overlay
            if isShowingToast {
                VStack {
                    toastView
                        .padding(.horizontal, AppTheme.Layout.screenPadding)
                        .padding(.top, AppTheme.Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(100)
            }
        }
        .sheet(isPresented: $showingSaveSheet, onDismiss: {
            if let ctx = pendingImportContext {
                pendingImportContext = nil
                if let onImportComplete {
                    onImportComplete(ctx)
                } else {
                    let label = ctx.importedCount == 1
                        ? "1 Wort gespeichert"
                        : "\(ctx.importedCount) Wörter gespeichert"
                    showToast(label)
                }
            }
        }) {
            if let store = listStore {
                SaveNewListSheet(
                    result: result,
                    listStore: store,
                    onSaved: { context in
                        hasSaved = true
                        pendingImportContext = context
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            // Top-Row: Label + Speichern + X
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("Erkannte Sprache")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
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

            // Sprache + Wortzahl
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(result.language)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                if result.totalEntryCount > 0 {
                    Text(wordCountLabel)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(sectionStyle.accent.opacity(AppTheme.CardIntensity.gentle))
                        )
                }
            }

            // Kategorie-Breakdown: "Nomen 12 · Verben 5 · Adjektive 3"
            if result.totalEntryCount > 0 {
                categorySummary
                    .padding(.top, AppTheme.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Layout.screenPadding)
        .padding(.top, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    private var wordCountLabel: String {
        let count = result.totalEntryCount
        return count == 1 ? "1 Wort" : "\(count) Wörter"
    }

    /// Kompakte Zusammenfassung der belegten Kategorien.
    /// Nur Kategorien mit Einträgen werden gezeigt.
    private var categorySummary: some View {
        let segments: [(String, Int)] = [
            ("Nomen", result.nomen.count),
            ("Verben", result.verben.count),
            ("Adj.", result.adjektive.count),
            ("Adv.", result.adverbien.count),
            ("Pron.", result.pronomen.count),
            ("Präp.", result.praepositionen.count),
            ("Konj.", result.konjunktionen.count),
            ("Sonst.", result.sonstige.count)
        ].filter { $0.1 > 0 }

        return HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                if idx > 0 {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
                }
                Text("\(segment.0) \(segment.1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Toast

    private var toastView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.Colors.success)
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
                .stroke(AppTheme.Colors.success.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
    }

    private func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.22)) { isShowingToast = true }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.22)) { isShowingToast = false }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    // MARK: - Scroll-Content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                // Originaltext + Übersetzung — immer offen, immer oben
                if !trimmedOriginalText.isEmpty {
                    textBlockSection(
                        title: "Originaltext",
                        body: trimmedOriginalText,
                        isTranslation: false
                    )
                }
                if !trimmedTranslation.isEmpty {
                    textBlockSection(
                        title: "Übersetzung",
                        body: trimmedTranslation,
                        isTranslation: true
                    )
                }

                // === Primäre Wortarten (prominent) ===
                if !result.nomen.isEmpty {
                    collapsibleNounSection(
                        key: "nomen",
                        title: "Nomen",
                        entries: result.nomen,
                        isProminent: true
                    )
                }
                if !result.verben.isEmpty {
                    collapsibleVerbSection(
                        key: "verben",
                        title: "Verben",
                        entries: result.verben,
                        isProminent: true
                    )
                }
                if !result.adjektive.isEmpty {
                    collapsibleGenericSection(
                        key: "adjektive",
                        title: "Adjektive",
                        entries: result.adjektive,
                        isProminent: false
                    )
                }

                // === Sekundäre Wortarten (kompakt) ===
                if !result.adverbien.isEmpty {
                    collapsibleGenericSection(
                        key: "adverbien",
                        title: "Adverbien",
                        entries: result.adverbien,
                        isProminent: false
                    )
                }
                if !result.pronomen.isEmpty {
                    collapsibleGenericSection(
                        key: "pronomen",
                        title: "Pronomen",
                        entries: result.pronomen,
                        isProminent: false
                    )
                }
                if !result.praepositionen.isEmpty {
                    collapsibleGenericSection(
                        key: "praepositionen",
                        title: "Präpositionen",
                        entries: result.praepositionen,
                        isProminent: false
                    )
                }
                if !result.konjunktionen.isEmpty {
                    collapsibleGenericSection(
                        key: "konjunktionen",
                        title: "Konjunktionen",
                        entries: result.konjunktionen,
                        isProminent: false
                    )
                }
                if !result.sonstige.isEmpty {
                    collapsibleGenericSection(
                        key: "sonstige",
                        title: "Sonstige",
                        entries: result.sonstige,
                        isProminent: false
                    )
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }

    // MARK: - Text-Block-Sektion

    private var trimmedOriginalText: String {
        result.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTranslation: String {
        result.translation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func textBlockSection(title: String, body: String, isTranslation: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(body)
                .font(AppTheme.Typography.body)
                .foregroundStyle(isTranslation ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(sectionStyle.accent.opacity(AppTheme.CardIntensity.subtle), lineWidth: 1)
        )
    }

    // MARK: - Collapsible Wortart-Sektionen

    /// Collapsible Header mit Titel, Count-Badge und Chevron.
    /// Tap togglet die Sektion.
    private func sectionHeader(key: String, title: String, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedSections.contains(key) {
                    expandedSections.remove(key)
                } else {
                    expandedSections.insert(key)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(sectionStyle.accent.opacity(AppTheme.CardIntensity.gentle))
                    )
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .rotationEffect(expandedSections.contains(key) ? .degrees(90) : .zero)
            }
        }
        .buttonStyle(.plain)
    }

    /// Nomen-Sektion mit Artikel-Merge. Prominent = mehr Padding, größere Rows.
    private func collapsibleNounSection(
        key: String,
        title: String,
        entries: [NounEntry],
        isProminent: Bool
    ) -> some View {
        let isExpanded = expandedSections.contains(key)
        return VStack(alignment: .leading, spacing: isExpanded ? AppTheme.Spacing.sm : 0) {
            sectionHeader(key: key, title: title, count: entries.count)
            if isExpanded {
                VStack(spacing: isProminent ? AppTheme.Spacing.sm : AppTheme.Spacing.xs) {
                    ForEach(entries) { entry in
                        entryRow(
                            primary: entry.displayLabel,
                            translation: entry.translation,
                            isForeign: entry.isForeign,
                            isProminent: isProminent
                        )
                    }
                }
            }
        }
        .padding(isProminent ? AppTheme.Layout.cardPadding : AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(sectionStyle.accent.opacity(AppTheme.CardIntensity.subtle), lineWidth: 1)
        )
    }

    /// Verb-Sektion.
    private func collapsibleVerbSection(
        key: String,
        title: String,
        entries: [VerbEntry],
        isProminent: Bool
    ) -> some View {
        let isExpanded = expandedSections.contains(key)
        return VStack(alignment: .leading, spacing: isExpanded ? AppTheme.Spacing.sm : 0) {
            sectionHeader(key: key, title: title, count: entries.count)
            if isExpanded {
                VStack(spacing: isProminent ? AppTheme.Spacing.sm : AppTheme.Spacing.xs) {
                    ForEach(entries) { entry in
                        entryRow(
                            primary: entry.word,
                            translation: entry.translation,
                            isForeign: entry.isForeign,
                            isProminent: isProminent
                        )
                    }
                }
            }
        }
        .padding(isProminent ? AppTheme.Layout.cardPadding : AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(sectionStyle.accent.opacity(AppTheme.CardIntensity.subtle), lineWidth: 1)
        )
    }

    /// Generische Sektion (Adjektive, Adverbien, Pronomen, …).
    private func collapsibleGenericSection(
        key: String,
        title: String,
        entries: [GenericEntry],
        isProminent: Bool
    ) -> some View {
        let isExpanded = expandedSections.contains(key)
        return VStack(alignment: .leading, spacing: isExpanded ? AppTheme.Spacing.sm : 0) {
            sectionHeader(key: key, title: title, count: entries.count)
            if isExpanded {
                VStack(spacing: isProminent ? AppTheme.Spacing.sm : AppTheme.Spacing.xs) {
                    ForEach(entries) { entry in
                        entryRow(
                            primary: entry.word,
                            translation: entry.translation,
                            isForeign: entry.isForeign,
                            isProminent: isProminent
                        )
                    }
                }
            }
        }
        .padding(isProminent ? AppTheme.Layout.cardPadding : AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(sectionStyle.accent.opacity(AppTheme.CardIntensity.subtle), lineWidth: 1)
        )
    }

    // MARK: - Entry Row

    /// Einzelner Eintrag — `isProminent` steuert Schriftgröße und Spacing.
    /// Nomen/Verben bekommen mehr Luft und etwas größere Schrift.
    private func entryRow(
        primary: String,
        translation: String,
        isForeign: Bool,
        isProminent: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(isProminent ? AppTheme.Typography.body : .system(size: 14))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if isForeign {
                    Text("Fremdwort")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.warning)
                }
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(translation)
                .font(isProminent ? AppTheme.Typography.body : .system(size: 14))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, isProminent ? AppTheme.Spacing.xxs : 1)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Kein Text erkannt.")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Versuch es mit einem schärferen Foto.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Layout.screenPadding)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Primärer CTA: Speichern (wenn listStore vorhanden und Einträge da)
            if listStore != nil, result.totalEntryCount > 0, !hasSaved {
                Button(action: { showingSaveSheet = true }) {
                    Text("Als Lernliste speichern")
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.Layout.buttonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(AppTheme.Colors.cta)
                        )
                }
                .buttonStyle(.plain)
            }

            // Sekundär: Schließen (nur Text-Link, wenn Speichern sichtbar)
            Button(action: onDone) {
                if listStore != nil, result.totalEntryCount > 0, !hasSaved {
                    Text("Ohne Speichern schließen")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    Text("Fertig")
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.Layout.buttonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(AppTheme.Colors.cta)
                        )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Layout.screenPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}
