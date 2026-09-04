import SwiftUI

struct ListDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let list: VocabularyList
    let onClose: () -> Void
    let onEdit: (VocabularyItem) -> Void
    let onDelete: (VocabularyItem) -> Void
    /// Optionales Rename-Callback. Wenn gesetzt und die Liste nicht
    /// gebuilt-in ist, erscheint neben dem Listennamen im Header ein
    /// Stift-Button. Tap feuert den Callback — der Caller (`ListsView`)
    /// schließt das Detail-Sheet und öffnet das Rename-Sheet.
    var onRename: (() -> Void)? = nil

    // **Editor-über-Detail (2026-05-22)** — der Vokabel-Editor wird jetzt
    // INNERHALB dieser Sheet präsentiert (eigener Presenter-Kontext) → das
    // Detail bleibt gemountet (kein Flackern zur Übersicht, Scroll bleibt
    // automatisch erhalten). Der Editor-State lebt weiter in ListsView und
    // wird als Bindings durchgereicht (Delete-Flows referenzieren ihn dort).
    @Binding var showingEntryEditor: Bool
    @Binding var editFrench: String
    @Binding var editGerman: String
    @Binding var editCardType: CardType
    let editorTitle: String
    let sourceFieldLabel: String
    let onEditorSave: () -> Void
    let onEditorCancel: () -> Void

    @State private var itemPendingDeletion: VocabularyItem?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Lernliste",
                leadingTint: style.accent,
                onLeading: {
                    onClose()
                    dismiss()
                }
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                // **Name + Rename-Stift** (User-Spec): Pencil sitzt
                // rechts neben dem Listen-Namen, nur für eigene
                // (nicht-built-in) Listen sichtbar. Tap ruft
                // `onRename` — der Parent (`ListsView`) schließt das
                // Detail-Sheet und öffnet die `RenameListSheet`.
                HStack(alignment: .center, spacing: 10) {
                    Text(list.name)
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Wackelkandidaten ausgenommen — automatisch generiert,
                    // Umbenennen ergibt hier keinen Sinn (siehe
                    // `ListPickerSheet.isWackelkandidatenList`).
                    if !list.isBuiltIn, list.id != VocabularyListStore.wackelkandidatenListID, let onRename {
                        Button(action: onRename) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(style.accent)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(style.accent.opacity(0.18))
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Lernliste umbenennen")
                    }
                }

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
            .appCardBackground(style, intensity: AppTheme.CardIntensity.soft)

            if list.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch keine Einträge in dieser Lernliste.")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.md)
                .appCardBackground(style, intensity: AppTheme.CardIntensity.soft)
            } else {
                ScrollView {
                    // **Codeaudit 2026-09-03, Stufe 3 (Punkt 21)** — vorher
                    // `VStack`: SwiftUI baut damit ALLE Zeilen sofort, auch
                    // die weit unterhalb des Bildschirms. Jede Zeile macht
                    // bis zu drei Genus-Lookups; bei der XP-Liste mit 8030
                    // Einträgen sind das bis zu 24.090 Lookups in einer
                    // einzigen Body-Auswertung. Das Wörterbuch nutzt an
                    // vergleichbarer Stelle längst `LazyVStack`.
                    LazyVStack(spacing: 10) {
                        ForEach(list.items) { item in
                            // 3-zeiliges Layout:
                            //   Zeile 1: Original FR (volle Breite, für lange Phrasen)
                            //   Zeile 2: Übersetzung DE (volle Breite)
                            //   Zeile 3: Infinitiv links (falls Verb) · Wortart + Icons rechts
                            VStack(alignment: .leading, spacing: 4) {
                                // ─── Zeile 1: Französisch ─────────────────────────
                                // **Anzeige-Bug-Fix (2026-05-22)** — `displayFrench`
                                // statt `displayFrenchWithGender`. Letzteres leitete
                                // die Anzeige-Base aus `strippingLeadingFrenchArticle`
                                // ab, das intern `normalizedLookupText` (DB-Matching:
                                // Diakritik-Folding + Bindestrich→Leerzeichen) nutzt →
                                // „la belle-mère" wurde als „le belle mere" gezeigt.
                                // `displayFrench` zeigt den GESPEICHERTEN Text 1:1
                                // (kein Folding, Artikel nur wenn keiner da ist, keine
                                // Singular-Rekonstruktion). Das Genus liefert die Pill
                                // rechts (genusLabel) — kein Info-Verlust.
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

                                    // Genus-Pill direkt rechts daneben — nur für Nomen
                                    // und nur wenn wir ein Gender auflösen konnten
                                    // (User-Wunsch „dahinter müsste Genus-Pill kommen").
                                    // Farbe rezykliert die Home-Akzentfarbe, damit sich
                                    // die beiden Pills klar voneinander abheben, ohne
                                    // visuell aufdringlich zu wirken.
                                    if let genus = genusLabel(for: item) {
                                        Text(genus)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppSectionStyle.home.accent)
                                            .lineLimit(1)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(AppSectionStyle.home.accent.opacity(0.14))
                                            .clipShape(Capsule())
                                    }

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
                            .appChipBackground(style, intensity: AppTheme.CardIntensity.gentle, cornerRadius: 14)
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
        // **Editor ÜBER dem Detail (2026-05-22)** — eigener Presenter →
        // Detail bleibt gemountet (kein Flackern, Scroll-Erhalt).
        .sheet(isPresented: $showingEntryEditor) {
            VocabularyEntryEditorSheet(
                style: style,
                title: editorTitle,
                sourceFieldLabel: sourceFieldLabel,
                frenchText: $editFrench,
                germanText: $editGerman,
                cardType: $editCardType,
                onCancel: onEditorCancel,
                onSave: onEditorSave
            )
        }
    }

    // (wordClassBreakdownLines entfernt — `POSBreakdownLine` rendert direkt)

    /// Zentrale App-Bezeichnung (FrenchLemmaFormatter.wordClassLabel).
    /// Single Source of Truth — gleiche Logik überall, inkl. Pronomen/Präposition/Interjektion.
    ///
    /// **Kontext-Refinement** (TODO 3): für ambigue französische
    /// Kurz-Tokens (`le`, `la`, `les`, `l'`) entscheidet der
    /// `VocabContextClassifier` anhand der deutschen Übersetzung, ob
    /// das Wort hier als Artikel (DE: „der/die/das/…") oder Pronomen
    /// (DE: „ihn/sie/es/…") auftritt. Nur wenn sich das Ergebnis von
    /// der gespeicherten `wordClass` unterscheidet, überschreiben wir
    /// das Label — sonst bleibt die Analyzer-Kaskade unverändert.
    ///
    /// Typischer Anwendungsfall: Altdaten aus früheren Prompt-
    /// Versionen, bei denen das LLM „le" fälschlich immer als „Artikel"
    /// gekennzeichnet hat, auch wo die DE-Übersetzung eindeutig
    /// Pronomen ist („le" → „ihn").
    private func displayWordClass(for item: VocabularyItem) -> String {
        let storedLower = item.wordClass?.lowercased() ?? ""
        if let refined = VocabContextClassifier.refinedWordClass(
            french: item.french,
            german: item.german,
            storedWordClass: item.wordClass
        ), refined.rawValue != storedLower {
            return FrenchLemmaFormatter.germanWordClassName(refined.rawValue)
        }
        return FrenchLemmaFormatter.wordClassLabel(for: item)
    }

    /// Optionaler Lemma-Hinweis in Klammern hinter dem französischen Text.
    private func lemmaHint(for item: VocabularyItem) -> String? {
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        return FrenchLemmaFormatter.makeLemmaHint(from: result)
    }

    /// Kurzer Genus-Text für die Pill neben der Wortart-Pill. Nil für
    /// Nicht-Nomen oder wenn **definitiv kein** Gender auflösbar ist.
    ///
    /// Variants-aware: wenn das Item `variants` hat (Gender-Paar oder
    /// Singular/Plural), liefern wir ein kombiniertes Label wie
    /// „m/f" oder „sg/pl". So bleibt die Pill für die gemergten
    /// Einträge aussagekräftig.
    ///
    /// Resolver-Kaskade (User-Feedback: „Prüfung muss exakter sein —
    /// ich sehe Genus-Angaben aber nicht bei allen Nomen"):
    ///   1. DB-Lookup auf originalen Eintrag
    ///   2. DB-Lookup auf bare (ohne Artikel)
    ///   3. DB-Lookup auf rekonstruierte Singular-Form (wenn Plural)
    ///   4. Heuristik via `frenchGenderInfo` (Suffix-Regeln, Head-Override)
    ///   5. **Fallback** über die deutsche Übersetzung: „der X" → m,
    ///      „die X" → f. „das X" wird bewusst nicht auf Französisch
    ///      gemappt (FR hat kein Neutrum, die Zuordnung wäre Rate-
    ///      spiel).
    ///
    /// Diese Kaskade deckt deutlich mehr Custom-List-Einträge ab,
    /// ohne die Zuverlässigkeit zu opfern.
    private func genusLabel(for item: VocabularyItem) -> String? {
        // 0) Variants-Shortcut — wenn der Merger Varianten gesetzt hat,
        //    lesen wir das Label direkt aus den Tags. Spart alle Lookups.
        if let variants = item.variants, !variants.isEmpty {
            let tags = variants.map(\.tag)
            // Gender-Paar (m/f)
            if Set(tags) == Set(["m", "f"]) { return "m/f" }
            // Singular/Plural
            if Set(tags) == Set(["sg", "pl"]) { return "sg/pl" }
            // Fallback: erste beide Tags
            if tags.count >= 2 { return "\(tags[0])/\(tags[1])" }
            return tags[0]
        }

        // Nur bei Nomen — Verben/Adjektive/Adverbien haben kein Genus.
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        let storedIsNoun = (item.wordClass?.lowercased() == "noun")
        let resolvedIsNoun = (result.primaryPos == .noun)
        guard storedIsNoun || resolvedIsNoun else { return nil }

        // 1) DB-Lookup auf originalen Eintrag (zuverlässig).
        if let direct = SupplementalFreeDictLexicon.sourceOnlyGender(for: item.french) {
            return genderPillText(from: direct)
        }

        // 2) Bare (ohne Artikel) versuchen — falls der Eintrag einen
        //    Artikel enthält, den die DB-Variante nicht findet.
        let base = strippingLeadingFrenchArticle(from: item.french)
        let probe = base.isEmpty ? item.french : base
        if !base.isEmpty,
           let bareDirect = SupplementalFreeDictLexicon.sourceOnlyGender(for: base) {
            return genderPillText(from: bareDirect)
        }

        // 3) Wenn der Eintrag Plural ist: Singular-Form rekonstruieren,
        //    daran erneut DB-Lookup probieren.
        if let singularCandidate = FrenchLemmaFormatter.naiveSingularizeFrenchNoun(probe),
           let singularGender = SupplementalFreeDictLexicon.sourceOnlyGender(for: singularCandidate) {
            return genderPillText(from: singularGender)
        }

        // 4) Heuristik via `frenchGenderInfo`.
        if let info = frenchGenderInfo(for: probe, cardType: .words) {
            switch info.gender {
            case .masculine: return "m"
            case .feminine:  return "f"
            case .neuter:    return "n"
            case .plural:    return "pl"
            }
        }

        // 5) Fallback: deutsche Übersetzung anschauen. Artikel-
        //    Prefix → Gender ableiten. `das X` wird nicht gemappt,
        //    weil Neutrum im Französischen nicht existiert.
        let germanLower = item.german.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if germanLower.hasPrefix("der ") || germanLower.hasPrefix("ein ") {
            return "m"
        }
        if germanLower.hasPrefix("die ") || germanLower.hasPrefix("eine ") {
            // „die X" ist im Deutschen auch Plural-Form — wenn die
            // französische Seite offensichtlich Singular ist, mappen
            // wir nach feminin. Bei „les X"/Plural bewusst nicht
            // überschreiben (wäre falsch).
            let frLower = item.french.lowercased()
            if !frLower.hasPrefix("les ") && !frLower.hasPrefix("des ") {
                return "f"
            }
        }

        // 6) Echte Heuristik übers `germanGenderInfo` — nutzt die
        //    selbe Logik, die auch die App-internen Lexikon-Einträge
        //    anreichert. Wenn das eine Feminine/Masculine-Zuordnung
        //    liefert, übernehmen wir es als letzten Versuch.
        if !item.german.isEmpty,
           let germanInfo = germanGenderInfo(for: item.german, cardType: .words) {
            switch germanInfo.gender {
            case .masculine: return "m"
            case .feminine:  return "f"
            case .neuter:    break  // keine verlässliche FR-Zuordnung
            case .plural:    break
            }
        }

        return nil
    }

    private func genderPillText(from dbLetter: String) -> String? {
        switch dbLetter {
        case "m":  return "m"
        case "f":  return "f"
        case "n":  return "n"
        case "pl": return "pl"
        default:    return nil
        }
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

