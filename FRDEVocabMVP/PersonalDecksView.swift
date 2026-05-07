import SwiftUI

/// **Meine Stapel — Subscreen** (Phase 8.2). Dedizierter Navigation-
/// Destination-Screen für persönliche Trainings-Stapel. Wird vom
/// Karteikarten-Setup über einen kompakten Entry-Button gepusht.
///
/// Struktur:
///   • Navigation-Titel „Meine Stapel", „+ Neu"-Button oben rechts
///     (ausgeblendet, sobald der 2-Slot-Cap erreicht ist)
///   • ScrollView mit `PersonalDeckDetailCard` pro Stapel
///   • Max-Slots-Hinweis unter den Karten, wenn das Limit erreicht ist
///
/// Alle Session-Start- und Storage-Pfade laufen weiterhin über das
/// bestehende Parent-Setup (via Callback `onStartDeck`); die View
/// selbst kennt keine Session-Logik.
struct PersonalDecksView: View {
    @ObservedObject var personalDeckStore: PersonalDeckStore
    /// **Bug-Fix Phase 8.2**: ObservedObject-Referenz auf den globalen
    /// Listen-Store — frische Lookups für Card-Stats und Edit-Apply.
    /// Vorher: gefilterte `allLists` als snapshot — Listen, die
    /// nicht zur aktuellen Sprachrichtung gehörten, wurden im Edit-
    /// Flow nicht erkannt → cardOrder konnte leer werden.
    @ObservedObject var listStore: VocabularyListStore
    let sectionStyle: AppSectionStyle
    let language: StudyLanguage
    let cardTypeFilter: CardType?
    /// Parent-Callback. Triggert Pop + Session-Start atomar im Parent.
    let onStartDeck: (PersonalDeck) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Frische Listen-Snapshot für Resolver-Logik. Computed, damit
    /// neu erstellte/gelöschte Listen sofort sichtbar werden.
    private var allLists: [VocabularyList] {
        listStore.allLists
    }

    // Sheet-/Alert-State — lebt im Subscreen, nicht mehr im Parent.
    @State private var showingCreateSheet: Bool = false
    @State private var deckBeingEdited: PersonalDeck? = nil
    @State private var deckPendingAction: PersonalDeck? = nil
    /// **Stufe 5 Polish (2026-04-30)**: dedicated Delete-Confirmation-
    /// Pfad. Vom neuen Context-Menu-Long-Press getriggert. Separat von
    /// `deckPendingAction` (= Rename/Delete-Combo-Alert), damit der
    /// Long-Press-Pfad direkt zu einer Destructive-only-Bestätigung
    /// führt, statt zur Combo-UI mit TextField.
    @State private var deckPendingDelete: PersonalDeck? = nil
    @State private var renameText: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // **User-Revision (final)**: standard ModuleHeaderCard
            // (gleiches Pattern wie alle Module-Screens) — Karteikarten-
            // Icon, Title „Meine Stapel", Back-Chevron oberhalb.
            // KEIN doppelter Titel mehr in der Navigation-Bar.
            ModuleHeaderCard(
                icon: .karteikarten,
                title: "Meine Stapel",
                accent: AppTheme.Colors.moduleFlashcards,
                onBack: { dismiss() }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("AKTIVE STAPEL")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(Color(hex: "#FFD166"))
                        Spacer(minLength: 0)
                        if personalDeckStore.decks.count < PersonalDeckStore.maxDeckCount {
                            Button {
                                showingCreateSheet = true
                            } label: {
                                Label("Neu", systemImage: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(sectionStyle.accent)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.top, 12)

                    ForEach(personalDeckStore.decks) { deck in
                        PersonalDeckDetailCard(
                            deck: deck,
                            cardStats: cardStats(for: deck),
                            onStart: {
                                // **Bug-Fix Phase 8.2 (v4)**: Parent
                                // (FlashcardsView) übernimmt sowohl Pop
                                // als auch Session-Start in EINEM Closure-
                                // Body. Das vermeidet die Race zwischen
                                // dismiss() und setup.isShowingSetup-Flip,
                                // die den User zurück in den Setup-Screen
                                // beförderte.
                                onStartDeck(deck)
                            },
                            onEditList: {
                                deckBeingEdited = deck
                            },
                            onRenameOrDelete: {
                                renameText = deck.name
                                deckPendingAction = deck
                            },
                            onDelete: {
                                deckPendingDelete = deck
                            }
                        )
                    }

                    if personalDeckStore.decks.count >= PersonalDeckStore.maxDeckCount {
                        maxSlotsHint
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "#0A1628").ignoresSafeArea())
        // **User-Revision**: Navigation-Bar komplett ausgeblendet —
        // der `ModuleHeaderCard` oben übernimmt Title + Back. Identisch
        // zu allen anderen Modul-Screens (Karteikarten-Setup, Quiz,
        // Training, Akzente).
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Create-Sheet (Standard-Listen-Picker mit leerer Vorauswahl).
        .sheet(isPresented: $showingCreateSheet) {
            FlashcardStackComposerSheet(
                style: sectionStyle,
                lists: allLists,
                selectedListIDs: [],
                language: language,
                cardTypeFilter: cardTypeFilter,
                // Empty-Pool-Hint (2026-04-29): Pre-Save-Check, ob aus
                // der aktuellen Selection unter dem aktiven Lernjahr-
                // Filter überhaupt Karten resultieren würden. Wenn
                // nein, gibt der Closure den Fehler-String zurück und
                // das Sheet bleibt offen statt silent zu schließen.
                // Selection-leer fällt durch: dann hat der User nichts
                // ausgewählt und der bestehende `selectedIDs.isEmpty`-
                // Guard in `createDeck` macht weiterhin no-op.
                validate: { selectedIDs in
                    // **Personal-Deck-Polish 2/3 (2026-04-30)**:
                    // 0-Selection-Fall fängt jetzt einen eigenen Inline-
                    // Fehler ab. Vorher ging die Closure mit `return nil`
                    // durch und das Sheet schloss sich trotzdem ohne
                    // Effekt (der createDeck/updateDeck-`isEmpty`-Guard
                    // war silent). Jetzt: User sieht direkt was zu tun
                    // ist, ohne dass das Sheet wegklappt.
                    if selectedIDs.isEmpty {
                        return "W\u{00E4}hle mindestens eine Liste, aus der dein Stapel bestehen soll."
                    }
                    let selectedLists = allLists.filter { selectedIDs.contains($0.id) }
                    let cardIDs = PersonalDeck.buildCardOrderSnapshot(from: selectedLists)
                    if cardIDs.isEmpty {
                        return "In deinem aktuellen Lernjahr-Range ergeben diese Listen keine Karten — w\u{00E4}hle andere Listen oder erweitere den Range."
                    }
                    return nil
                }
            ) { selectedIDs in
                createDeck(fromSelectedListIDs: selectedIDs)
                showingCreateSheet = false
            }
        }
        // Edit-Sheet (derselbe Picker, vorgefüllt, Update-Semantik).
        .sheet(item: $deckBeingEdited) { editing in
            FlashcardStackComposerSheet(
                style: sectionStyle,
                lists: allLists,
                selectedListIDs: Set(editing.sourceListIDs),
                language: language,
                cardTypeFilter: cardTypeFilter,
                // Empty-Pool-Hint (2026-04-29): symmetrisch zur Create-
                // Sheet — verhindert, dass der User die Listen so
                // tauscht, dass keine Karten mehr resultieren. Im Edit-
                // Pfad würde sonst die alte `cardOrder` als „Notfall-
                // Inhalt" stehen bleiben (siehe `updateDeck`-Else-
                // Branch), während die neuen `sourceListIDs` schon
                // gespeichert wären — inkonsistenter Zwischenstand.
                // Der Hint zwingt zur sinnvollen Auswahl.
                validate: { selectedIDs in
                    // **Personal-Deck-Polish 2/3 (2026-04-30)**:
                    // 0-Selection-Fall fängt jetzt einen eigenen Inline-
                    // Fehler ab. Vorher ging die Closure mit `return nil`
                    // durch und das Sheet schloss sich trotzdem ohne
                    // Effekt (der createDeck/updateDeck-`isEmpty`-Guard
                    // war silent). Jetzt: User sieht direkt was zu tun
                    // ist, ohne dass das Sheet wegklappt.
                    if selectedIDs.isEmpty {
                        return "W\u{00E4}hle mindestens eine Liste, aus der dein Stapel bestehen soll."
                    }
                    let selectedLists = allLists.filter { selectedIDs.contains($0.id) }
                    let cardIDs = PersonalDeck.buildCardOrderSnapshot(from: selectedLists)
                    if cardIDs.isEmpty {
                        return "In deinem aktuellen Lernjahr-Range ergeben diese Listen keine Karten — w\u{00E4}hle andere Listen oder erweitere den Range."
                    }
                    return nil
                }
            ) { selectedIDs in
                updateDeck(editing, withSelectedListIDs: selectedIDs)
                deckBeingEdited = nil
            }
        }
        // Bearbeiten-Alert: TextField zum Umbenennen + Löschen-Option.
        .alert(
            "Stapel bearbeiten",
            isPresented: Binding(
                get: { deckPendingAction != nil },
                set: { if !$0 { deckPendingAction = nil } }
            ),
            presenting: deckPendingAction
        ) { deck in
            TextField("Name", text: $renameText)
            Button("Speichern") {
                personalDeckStore.rename(id: deck.id, to: renameText)
                deckPendingAction = nil
            }
            Button("Löschen", role: .destructive) {
                personalDeckStore.remove(id: deck.id)
                deckPendingAction = nil
            }
            Button("Abbrechen", role: .cancel) {
                deckPendingAction = nil
            }
        } message: { _ in
            Text("Gib einen neuen Namen ein oder lösche den Stapel.")
        }
        // **Stufe 5 Polish (2026-04-30)** — Destructive-Bestätigung
        // für den Long-Press-Delete-Pfad. Separat vom Rename-Alert
        // oben, damit der User beim Long-Press direkt zur Lösch-
        // Bestätigung kommt (ohne Umweg über TextField).
        //
        // **Sim-Smoke-Test-Iteration (2026-04-30)**: erste Variante
        // nutzte `.confirmationDialog` — auf iOS 26 wurde der als
        // kompakter Popover gerendert mit hellem Hintergrund und
        // verschlucktem Cancel-Button (User sah keinen Abbrechen-
        // Pfad). Umgestellt auf `.alert`, das einen klassischen
        // zwei-Button-Layout mit Modal-Background liefert — beide
        // Buttons garantiert sichtbar, rote Destructive-Schrift
        // sauber lesbar gegen System-Background.
        .alert(
            "Stapel löschen?",
            isPresented: Binding(
                get: { deckPendingDelete != nil },
                set: { if !$0 { deckPendingDelete = nil } }
            ),
            presenting: deckPendingDelete
        ) { deck in
            Button("Abbrechen", role: .cancel) {
                deckPendingDelete = nil
            }
            Button("L\u{00F6}schen", role: .destructive) {
                personalDeckStore.remove(id: deck.id)
                deckPendingDelete = nil
            }
        } message: { deck in
            // **Wichtig**: explizit klarstellen, dass NUR der Stapel
            // (User-Curation + Mastery-Daten) gelöscht wird — nicht die
            // zugrunde liegenden Quelllisten. Der `deck.name`-Auto-Wert
            // (z. B. „Buch Unite 1 · A1 Grundwortschatz") sieht aus wie
            // eine Listen-Bezeichnung; ohne den Reassurance-Satz könnte
            // der User denken, er löscht den Grundwortschatz selbst.
            Text("Der Stapel \u{201E}\(deck.name)\u{201C} und dein Lernfortschritt werden gel\u{00F6}scht. Die Quelllisten bleiben erhalten.")
        }
    }

    // MARK: - Header-Banner

    /// Gradient-Banner analog zu anderen Modul-Screens. Icon = das
    /// bestehende Karteikarten-Home-Icon (keine neue Grafik).
    private var headerBanner: some View {
        HStack(spacing: 14) {
            HomeModuleIconView(icon: .karteikarten, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meine Stapel")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                Text("Persönliche Trainingslisten")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1a4a7a"), Color(hex: "#0f3560")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Helpers

    private func cardStats(for deck: PersonalDeck) -> (totalCards: Int, listCount: Int) {
        let lists = allLists.filter { deck.sourceListIDs.contains($0.id) }
        return (totalCards: deck.cardOrder.count, listCount: lists.count)
    }

    private func createDeck(fromSelectedListIDs selectedIDs: Set<UUID>) {
        guard !selectedIDs.isEmpty else { return }
        let selectedLists = allLists.filter { selectedIDs.contains($0.id) }
        // **V1b Snapshot (2026-04-28)** — cardOrder wird mit dem
        // aktuellen lernjahrMax gefiltert (Snapshot-Semantik).
        let cardIDs = PersonalDeck.buildCardOrderSnapshot(from: selectedLists)
        guard !cardIDs.isEmpty else { return }
        let deck = PersonalDeck(
            name: autoName(fromLists: selectedLists),
            colorIndex: personalDeckStore.nextColorIndex,
            sourceListIDs: Array(selectedIDs),
            cardOrder: cardIDs.shuffled()
        )
        personalDeckStore.add(deck)
    }

    private func updateDeck(_ deck: PersonalDeck, withSelectedListIDs selectedIDs: Set<UUID>) {
        print("🔧 updateDeck called: deckID=\(deck.id) oldLists=\(deck.sourceListIDs.count) newLists=\(selectedIDs.count) allListsAvailable=\(allLists.count)")
        guard !selectedIDs.isEmpty else {
            print("⚠️ updateDeck: selectedIDs leer — abort")
            return
        }
        let listsChanged = Set(deck.sourceListIDs) != selectedIDs
        var updated = deck
        updated.sourceListIDs = Array(selectedIDs)
        if listsChanged {
            let matchedLists = allLists.filter { selectedIDs.contains($0.id) }
            // **V1b Re-Snapshot (2026-04-28)** — Listen-Wechsel
            // erzwingt neuen Snapshot mit aktuellem lernjahrMax.
            let freshCardIDs = PersonalDeck.buildCardOrderSnapshot(from: matchedLists)
            print("🔧 updateDeck: lists changed → matched=\(matchedLists.count) freshCards=\(freshCardIDs.count)")

            // Defensive: wenn KEIN Item gematched wurde (Listen wurden
            // zwischenzeitlich gelöscht?), nicht den alten cardOrder
            // wegwerfen — der Stapel bliebe sonst spielunfähig.
            if !freshCardIDs.isEmpty {
                updated.cardOrder = freshCardIDs.shuffled()
                updated.currentIndex = 0
                updated.masteredCardIDs = []
            } else {
                print("⚠️ updateDeck: keine Karten in den neuen Listen — cardOrder bleibt unverändert")
            }

            // **User-Revision**: Name automatisch an neue Listen angleichen,
            // damit der Stapel-Header sichtbar reflektiert, was drin ist.
            // Manuell vergebene Namen lassen sich anschließend immer noch
            // über „Bearbeiten" überschreiben.
            updated.name = autoName(fromLists: matchedLists)
        }
        updated.lastAccessedAt = Date()
        personalDeckStore.replace(updated)
    }

    private func autoName(fromLists lists: [VocabularyList]) -> String {
        guard !lists.isEmpty else { return "Mein Stapel" }
        let prefix = lists.prefix(3).map(\.name).joined(separator: " · ")
        return lists.count > 3 ? "\(prefix) +…" : prefix
    }

    private var maxSlotsHint: some View {
        Text("Max. 2 Stapel · einen löschen um neu anzulegen")
            .font(.system(size: 7, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.20))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            )
    }
}

// MARK: - PersonalDeckDetailCard

/// Detail-Card pro Stapel auf dem „Meine Stapel"-Subscreen.
///
/// Aufbau:
///   • Top-Row: Farb-Dot + Name + „Bearbeiten"-Link (→ Rename/Delete-Alert)
///   • Stats-Row: 4 Chip-Karten (Position · Gesamt · Gemeistert · Zuletzt)
///   • Progress-Bar: 2 pt Balken in Deck-Farbe
///   • „Weiter lernen"-Button mit Deck-farblich variierender Optik
///     (Slot 0 = solid pink, Slot 1 = outline blue)
struct PersonalDeckDetailCard: View {
    let deck: PersonalDeck
    let cardStats: (totalCards: Int, listCount: Int)
    let onStart: () -> Void
    let onEditList: () -> Void
    let onRenameOrDelete: () -> Void
    /// **Stufe 5 Polish (2026-04-30)**: dedicated destructive-Delete-
    /// Pfad. Wird vom neuen Context-Menu-Long-Press getriggert; der
    /// Caller zeigt eine `.confirmationDialog` mit „{Name} löschen"
    /// als einzelner Destructive-Button. Vorher ging Delete nur via
    /// „Bearbeiten"-Text-Button → kombinierter Rename/Delete-Alert,
    /// der für viele User unentdeckbar war.
    let onDelete: () -> Void

    private var dotColor: Color { PersonalDeck.color(for: deck.colorIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // **User-Revision (final-2)**: alle Fonts in der Card jetzt
            // nochmal +1 pt — bessere Lesbarkeit, ohne dass der Header
            // angetastet wird.
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                Text(deck.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    onRenameOrDelete()
                } label: {
                    Text("Bearbeiten")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.borderless)
                Button {
                    onEditList()
                } label: {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.borderless)
            }

            // Stats-Row (vergrößert)
            HStack(spacing: 6) {
                statChip(value: "\(min(deck.currentIndex, deck.cardOrder.count))", label: "POSITION")
                statChip(value: "\(deck.cardOrder.count)", label: "GESAMT")
                statChip(value: "\(deck.masteredCardIDs.count)", label: "GEMEISTERT")
                statChip(value: deck.lastAccessedAt.relativeLabel, label: "ZULETZT")
            }

            // Progress-Bar (3 pt statt 2 pt)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(dotColor)
                        .frame(width: max(0, geo.size.width * deck.progressFraction))
                }
            }
            .frame(height: 3)

            // **User-Revision 2026-04-22 (final)**: Beide Stapel-CTAs
            // einheitlich — solide Dot-Color als Background, weißer
            // Text, weißer Outline-Border (opacity 0.45) für Kontrast
            // gegen die jetzt eingefärbte Card. Optisch konsistent
            // zwischen Slot 0 (pink) und Slot 1 (blau).
            Button(action: onStart) {
                Text("Weiter lernen")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(dotColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // **User-Revision (final)**: leichte Dot-Color-Tint auf der
        // gesamten Card, damit Stapel 0 (Pink) und Stapel 1 (Blau) auf
        // einen Blick auseinanderzuhalten sind. Opacity bewusst klein
        // (0.10) — Card bleibt insgesamt dunkel, nur ein Hauch Farbe.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dotColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(dotColor.opacity(0.35), lineWidth: 1)
        )
        // **Stufe 5 Polish (2026-04-30)** — iOS-natives Long-Press-
        // Pattern: Context-Menu mit allen drei Bearbeitungs-Aktionen.
        // Vorher war nur ein subtiler „Bearbeiten"-Text-Button im
        // Card-Header der Trigger; User-Report 2026-04-29: „löschen
        // option fehlt". Diagnose: Trigger zwar funktional, aber
        // unentdeckbar. Fix: Long-Press auf die Card surface alle
        // Aktionen — natürlich für iOS-User, ohne Card-Layout zu
        // brechen. Der existierende Text-Button-Pfad bleibt parallel
        // erhalten, kein Regress.
        .contextMenu {
            Button {
                onRenameOrDelete()
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            Button {
                onEditList()
            } label: {
                Label("Listen ändern", systemImage: "list.bullet.rectangle")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // **User-Revision (final-2)**: Label nochmal +1 pt → 11.
            // Opacity bleibt 0.55 für klaren Kontrast.
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(hex: "#1A3050"), lineWidth: 1)
        )
    }

    // Deck-farblich variierende CTA-Optik:
    //   • Slot 0 (Pink) → solid pink mit weißer Schrift
    //   • Slot 1 (Blue) → transparenter Hintergrund, blauer Border + Text
    private var weiterLernenForeground: Color {
        deck.colorIndex == 1 ? Color(hex: "#5B9CF5") : Color.white
    }
    private var weiterLernenBackground: Color {
        if deck.colorIndex == 1 {
            return Color(hex: "#5B9CF5").opacity(0.15)
        }
        return Color(hex: "#FF4D80")
    }
    private var weiterLernenBorder: Color {
        Color(hex: "#5B9CF5")
    }
}

// MARK: - Date.relativeLabel

extension Date {
    /// User-freundliches Label für „zuletzt" auf deutsch — „heute",
    /// „gestern", sonst „vor N Tagen". Kalendervergleich auf Tag-Ebene,
    /// Zeitzone = aktuelle Device-Zeit.
    var relativeLabel: String {
        let days = Calendar.current.dateComponents([.day], from: self, to: .now).day ?? 0
        switch days {
        case 0:   return "heute"
        case 1:   return "gestern"
        default:  return "vor \(days) Tagen"
        }
    }
}
