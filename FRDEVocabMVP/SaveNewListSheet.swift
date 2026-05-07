import SwiftUI

/// Bottom-Sheet zum Speichern eines „Freier Text"-Analyse-Ergebnisses
/// als neue Vokabelliste.
///
/// Flow: Nutzer tippt auf „Speichern" in der Result-View → Sheet öffnet
/// mit vorgefülltem Listennamen („Scan DD.MM.YYYY HH:MM") und offener
/// Tastatur. Ein Tap auf „Speichern" im Sheet erzeugt die Liste sofort
/// im bestehenden `VocabularyListStore`-System und ruft `onSaved` zurück,
/// damit die Result-View einen Toast zeigen kann.
///
/// Die Zuordnung `french` / `german` hängt von der erkannten Sprache ab:
/// - Deutsch → `word` = german, `translation` = french
/// - Alles andere → `word` = french, `translation` = german
struct SaveNewListSheet: View {
    let result: FreeTextResult
    let listStore: VocabularyListStore
    /// Callback nach erfolgreichem Speichern — liefert den vollständigen
    /// `ImportCompletionContext`, damit der Parent den identischen Post-
    /// Import-Flow (Lernmodus-Auswahl) wie beim Vokabel-Scan zeigen kann.
    let onSaved: (ImportCompletionContext) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var listName: String
    @FocusState private var isNameFocused: Bool

    // MARK: - Init

    init(
        result: FreeTextResult,
        listStore: VocabularyListStore,
        onSaved: @escaping (ImportCompletionContext) -> Void
    ) {
        self.result = result
        self.listStore = listStore
        self.onSaved = onSaved

        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        _listName = State(initialValue: "Scan \(formatter.string(from: Date()))")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Drag-Indicator
            Capsule()
                .fill(AppTheme.Colors.textSecondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.md)

            // Titel
            Text("Neue Liste speichern")
                .font(AppTheme.Typography.screenTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.bottom, AppTheme.Spacing.lg)

            // Eingabefeld
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text("Listenname")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                TextField("Listenname", text: $listName)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .fill(AppTheme.Colors.secondarySurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .stroke(AppTheme.Colors.textSecondary.opacity(0.25), lineWidth: 1)
                    )
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { saveIfValid() }
            }
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.bottom, AppTheme.Spacing.lg)

            // Vorschau-Info
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(previewLabel)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.bottom, AppTheme.Spacing.lg)

            // Speichern-Button
            Button(action: saveIfValid) {
                Text("Speichern")
                    .font(AppTheme.Typography.button)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Layout.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .fill(isSaveDisabled ? AppTheme.Colors.cta.opacity(0.4) : AppTheme.Colors.cta)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSaveDisabled)
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.bottom, AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.background)
        .onAppear {
            // Keyboard sofort öffnen; kurze Verzögerung, damit das Sheet
            // komplett aufgebaut ist (sonst ignoriert iOS den Focus).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isNameFocused = true
            }
        }
    }

    // MARK: - Computed

    private var trimmedName: String {
        listName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        trimmedName.isEmpty
    }

    private var previewLabel: String {
        let count = result.totalEntryCount
        return count == 1 ? "1 Wort wird gespeichert" : "\(count) Wörter werden gespeichert"
    }

    // MARK: - Save

    private func saveIfValid() {
        guard !isSaveDisabled else { return }

        let items = Self.mapToVocabularyItems(from: result)
        guard !items.isEmpty else { return }

        let listID = listStore.createList(
            named: trimmedName,
            collectionPreset: .vocabularyNotebook
        )
        let importedCount = listStore.importItems(
            items,
            preferredListID: listID,
            suggestedListName: trimmedName,
            collectionPreset: .vocabularyNotebook
        )

        let context = ImportCompletionContext(
            importedCount: importedCount,
            targetListID: listID,
            targetListName: trimmedName,
            language: .french,
            preferredDirection: nil,
            cardType: .words,
            importedItemIDs: items.map(\.id)
        )

        appDebugLog("📄 [FreierText] ✅ Liste \"\(trimmedName)\" gespeichert: \(importedCount) Einträge")
        onSaved(context)
        dismiss()
    }

    // MARK: - Mapping FreeTextResult → [VocabularyItem]

    /// Konvertiert alle Wortklassen-Einträge in `VocabularyItem`s.
    ///
    /// Richtung:
    /// - Erkannter Text ist Deutsch → `word` landet in `german`,
    ///   `translation` in `french`.
    /// - Alles andere (Französisch, Englisch, …) → `word` landet
    ///   in `french`, `translation` in `german`.
    ///
    /// Dedup: Gleiche Kombination `word.lowercased() + type` wird
    /// nur einmal aufgenommen — Claude liefert zwar schon deduplizierte
    /// Lemmata, aber verschiedene Wortklassen-Sektionen könnten
    /// theoretisch Überschneidungen haben.
    static func mapToVocabularyItems(from result: FreeTextResult) -> [VocabularyItem] {
        let isGerman = result.language.lowercased().hasPrefix("deutsch")

        var seen = Set<String>()
        var items: [VocabularyItem] = []

        func addEntries<E: WordEntryProtocol>(
            _ entries: [E],
            type: String,
            genderKeyPath: KeyPath<E, String?>? = nil
        ) {
            for entry in entries {
                let dedupeKey = "\(entry.entryWord.lowercased())|\(type)"
                guard seen.insert(dedupeKey).inserted else { continue }

                let french: String
                let german: String

                if isGerman {
                    german = entry.entryWord
                    french = entry.entryTranslation
                } else {
                    french = entry.entryWord
                    german = entry.entryTranslation
                }

                guard !french.isEmpty, !german.isEmpty else { continue }

                items.append(VocabularyItem(
                    rawFrench: french,
                    rawGerman: german,
                    cardType: .words,
                    sourceLanguage: .french,
                    wordClass: type
                ))
            }
        }

        addEntries(result.nomen, type: "nomen")
        addEntries(result.verben, type: "verb")
        addEntries(result.adjektive, type: "adjektiv")
        addEntries(result.adverbien, type: "adverb")
        addEntries(result.pronomen, type: "pronomen")
        addEntries(result.praepositionen, type: "präposition")
        addEntries(result.konjunktionen, type: "konjunktion")
        addEntries(result.sonstige, type: "sonstige")

        return items
    }
}

// MARK: - Protocol für einheitlichen Zugriff auf Entry-Felder

/// Kleines Hilfs-Protokoll, damit `addEntries` generisch über
/// `NounEntry`, `VerbEntry` und `GenericEntry` iterieren kann,
/// ohne drei separate Schleifen zu schreiben.
protocol WordEntryProtocol {
    var entryWord: String { get }
    var entryTranslation: String { get }
}

extension NounEntry: WordEntryProtocol {
    var entryWord: String { word }
    var entryTranslation: String { translation }
}

extension VerbEntry: WordEntryProtocol {
    var entryWord: String { word }
    var entryTranslation: String { translation }
}

extension GenericEntry: WordEntryProtocol {
    var entryWord: String { word }
    var entryTranslation: String { translation }
}
