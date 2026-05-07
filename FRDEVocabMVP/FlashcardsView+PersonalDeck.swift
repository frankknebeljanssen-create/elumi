import SwiftUI

/// **Persönlicher Trainingsmodus — Integration in FlashcardsView** (Phase 8).
///
/// Bündelt die drei Aufgaben, die das bestehende Karteikarten-Modul NICHT
/// schon hat:
///   1. „MEINE STAPEL"-Setup-Block + Sheets (Create / Rename)
///   2. Launch-Flow: Personal-Deck → Session konfigurieren
///   3. Session-End-Sync: Fortschritt (`currentIndex`, `masteredCardIDs`)
///      in den `PersonalDeckStore` zurückspiegeln
///
/// Architektur-Entscheidung: KEINE neue Session-View, keine Änderungen am
/// regulären FlashcardSessionStore-Flow. Wir bauen eine synthetische
/// `VocabularyList` aus dem Personal-Deck-Kartenorder und geben die an
/// `configureCustomDeck(from:…)`. So teilt sich der persönliche Modus
/// vollständig alle bestehenden Render-/Swipe-/Mastery-Pfade mit dem
/// normalen Setup — lediglich die Kartenreihenfolge kommt aus dem Deck,
/// statt zufällig gemischt zu sein.
extension FlashcardsView {

    // MARK: - „MEINE STAPEL"-Setup-Block

    /// Der „MEINE STAPEL"-Abschnitt oben im Karteikarten-Setup. Label +
    /// zwei Slots. Render-Only — State-Mutationen laufen über die
    /// `@State`-Properties in `FlashcardsView` (sheet-Trigger, Rename-
    /// Target, Delete-Bestätigung).
    /// **Meine-Stapel-Entry-Button (Phase 8.2)** — ersetzt den Inline-
    /// Bereich mit 2 Slots. Tappt der User hier, wird via
    /// `.navigationDestination` der `PersonalDecksView`-Subscreen
    /// gepusht. Der Button zeigt kompakt, wie viele Stapel aktiv sind
    /// und welcher Stapel zuletzt genutzt wurde.
    /// **User-Revision (final)**: Layout-Parität mit der „Ausgewählte
    /// Listen"-Card — Karteikarten-Icon (36 pt) links, Text rechts in
    /// Weiß, Font wie Modul-Header (kleiner). +1 pt im letzten Pass.
    @ViewBuilder
    var personalDeckSection: some View {
        Button {
            isShowingPersonalDecksScreen = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                HomeModuleIconView(icon: .karteikarten, size: 36)

                Text("Meine Stapel")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // **User-Revision 2026-04-22**: Card etwas heller eingefärbt
            // (`#143a5d` mit dezentem Verlauf) — sticht aus dem
            // umgebenden Setup-Dunkel hervor, bleibt aber spürbar
            // dunkler als der Modul-Header (`#1a4a7a → #0f3560`).
            // Border in Akzent-Blau für klare Kante.
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#163d63"),
                                Color(hex: "#11304f")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(Color(hex: "#234e7a"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// **Personal-Deck-Indikator (User-Revision 2026-04-22)** —
    /// Computed lookup auf den aktiven Stapel. Nil = reguläre Session.
    /// Wird vom Session-Screen genutzt, um den Stapel-Hinweis unter
    /// dem Header anzuzeigen.
    var activePersonalDeckForSession: PersonalDeck? {
        guard let id = sessionStore.activePersonalDeckID else { return nil }
        return personalDeckStore.deck(withID: id)
    }

    /// Dot-Indicator für einen der zwei Slots. Wenn es an der Index-
    /// Position ein Deck gibt, nutzt der Dot dessen Farbe; sonst grau.
    @ViewBuilder
    private func dotIndicator(for index: Int) -> some View {
        if index < personalDeckStore.decks.count {
            Circle()
                .fill(PersonalDeck.color(for: personalDeckStore.decks[index].colorIndex))
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 7, height: 7)
        }
    }

    /// Zuletzt benutzter Stapel (für den „Zuletzt"-Hinweis). Nil, wenn
    /// noch keiner existiert.
    private var mostRecentDeck: PersonalDeck? {
        personalDeckStore.decks.sorted { $0.lastAccessedAt > $1.lastAccessedAt }.first
    }

    // MARK: - Card-Stats Provider

    /// Liefert `(totalCards, listCount)` für die Meta-Zeile des Slots.
    /// Summiert die Karten über alle referenzierten `sourceListIDs`.
    /// Wenn eine Liste zwischenzeitlich gelöscht wurde, bleibt ihre
    /// Zahl bei 0 — der Stapel hält dennoch alle `cardOrder`-IDs, die
    /// beim Play-Start gefiltert werden.
    func personalDeckCardStats(for deck: PersonalDeck) -> (totalCards: Int, listCount: Int) {
        let lists = listStore.allLists.filter { deck.sourceListIDs.contains($0.id) }
        return (totalCards: deck.cardOrder.count, listCount: lists.count)
    }

    // MARK: - Launch-Flow

    /// Baut eine synthetische `VocabularyList` aus dem Personal-Deck-
    /// Kartenorder (gestartet bei `currentIndex`, mit Wrap-Around,
    /// mastered-Karten übersprungen) und übergibt sie an den
    /// bestehenden Session-Flow via `configureCustomDeck(from:…)`.
    /// Kein neuer Session-Pfad, keine Sonderlogik in der Session-View.
    func startPersonalDeckSession(_ deck: PersonalDeck) {
        appDebugLog("🎯 startPersonalDeckSession: deckID=\(deck.id) sourceLists=\(deck.sourceListIDs.count) cardOrder=\(deck.cardOrder.count) mastered=\(deck.masteredCardIDs.count) currentIndex=\(deck.currentIndex)")

        // 1) Alle Items aus allen sourceListIDs als Lookup-Map aufbauen.
        let matchedLists = listStore.allLists.filter { deck.sourceListIDs.contains($0.id) }
        appDebugLog("🎯 matchedLists=\(matchedLists.count) (von \(listStore.allLists.count) globalen Listen)")
        var itemsByID: [UUID: VocabularyItem] = [:]
        for list in matchedLists {
            for item in list.items {
                itemsByID[item.id] = item
            }
        }
        appDebugLog("🎯 itemsByID hat \(itemsByID.count) Items aus den Source-Listen")

        // 2) Aus cardOrder die aktive Rotation ableiten — ab currentIndex
        //    bis Ende, dann wrap-around auf 0 bis currentIndex (nur einen
        //    Full-Loop — keine Endlos-Wiederholung). masteredCardIDs
        //    raus, fehlende IDs (z. B. gelöschte Listen) ebenso.
        let start = min(deck.currentIndex, max(0, deck.cardOrder.count - 1))
        let rotated = Array(deck.cardOrder[start...]) + Array(deck.cardOrder[..<start])
        let activeIDs = rotated.filter {
            !deck.masteredCardIDs.contains($0) && itemsByID[$0] != nil
        }
        var orderedItems: [VocabularyItem] = activeIDs.compactMap { itemsByID[$0] }
        appDebugLog("🎯 activeIDs=\(activeIDs.count) orderedItems=\(orderedItems.count)")

        // **Bug-Fix Phase 8.2 (UUID-Stale-Recovery)**: Standard-Listen
        // (StandardVocabularyLoader) erzeugen pro App-Launch neue
        // VocabularyItem-UUIDs aus der SQLite-DB — das war eine
        // Architektur-Annahme, die wir beim Personal-Deck nicht
        // berücksichtigt hatten. Folge: cardOrder eines Stapels enthält
        // UUIDs aus einem ALTEN Launch, itemsByID die UUIDs vom
        // aktuellen → ZERO Matches → orderedItems leer → User landet
        // wieder im Setup. Hier defensiv: wenn cardOrder zwar Inhalt
        // hat, die Resolver-Übersetzung aber komplett fehlschlägt,
        // bauen wir die cardOrder aus den AKTUELLEN Items neu auf.
        // Mastery-Daten gehen leider verloren (sie waren ans alte
        // UUID-Schema gebunden); cardOrder + currentIndex werden
        // resettet. Der User kann den Stapel ab jetzt wieder spielen.
        if orderedItems.isEmpty && !itemsByID.isEmpty && !deck.cardOrder.isEmpty {
            appDebugLog("♻️ UUID-Stale-Recovery: rebuilding cardOrder from current items")
            // **V1b Recovery (2026-04-28)** — Recovery-Pfad zerstört
            // Snapshot ohnehin (Mastery weg, neuer Shuffle), daher
            // gilt der **aktuelle** lernjahrMax. Konsistent zum
            // globalen Filter-Verhalten.
            let recoveredIDs = PersonalDeck.buildCardOrderSnapshot(from: matchedLists)
            let recoveredItems = recoveredIDs.compactMap { itemsByID[$0] }
            let shuffled = recoveredItems.shuffled()
            personalDeckStore.update(id: deck.id) { mutableDeck in
                mutableDeck.cardOrder = shuffled.map(\.id)
                mutableDeck.currentIndex = 0
                mutableDeck.masteredCardIDs = []
            }
            orderedItems = shuffled
        }

        guard !orderedItems.isEmpty else {
            appDebugLog("⚠️ startPersonalDeckSession: orderedItems LEER — abort, isShowingSetup bleibt true. itemsByID=\(itemsByID.count) cardOrderCount=\(deck.cardOrder.count) masteredCount=\(deck.masteredCardIDs.count)")
            return
        }

        // 3) Synthetische Liste bauen und an Session-Store reichen.
        //    `isBuiltIn = false`, damit sie in Listen-Queries als
        //    Custom-Entity behandelt wird. Sprache wird über das erste
        //    Item abgeleitet (fallback: Französisch).
        let syntheticList = VocabularyList(
            id: UUID(),
            name: deck.name,
            items: orderedItems,
            isBuiltIn: false
        )

        // **User-Revision 2026-04-22 (echter Bug-Fix)**: Wir nutzen jetzt
        // den `configureCustomDeck(from list:)`-Overload (Single-List,
        // ohne Sprach-Filter). Der `(from lists:, language:)`-Overload
        // hat die Items zusätzlich nach `item.sourceLanguage == language`
        // gefiltert — bei gemischten Personal-Decks oder leichter
        // Sprach-Drift fielen dadurch alle/zu viele Items raus,
        // `customDeck` blieb nil, `isShowingSetup` flippte nicht, und
        // der User landete nach „Weiter lernen" wieder im Setup-Screen.
        // Die Single-List-Variante akzeptiert alle Karten und ist für
        // Personal-Decks die richtige Wahl, weil unser `cardOrder` schon
        // die Wahrheitsquelle ist.
        sessionStore.configureCustomDeck(
            from: syntheticList,
            preferredCardType: nil
        )

        // 4) Active-Flag setzen, Session starten. Das Tag-Label + Badge
        //    im Session-View lesen die ID zur Discovery.
        sessionStore.activePersonalDeckID = deck.id
        if let customDeck = sessionStore.customDeck {
            sessionStore.selectedDeckID = customDeck.id
            sessionStore.selectedDirection = selectedAppDirection
            sessionStore.masteryThreshold = max(1, min(4, setup.masteryThreshold))
            sessionStore.startOrResumeSession()

            // **User-Revision 2026-04-22 (Stand-Sync)**: Die frische
            // Session hat KEINE cardMastery-Einträge — die "Kann ich"-
            // Statistik im Session-Header würde 0 zeigen, obwohl der
            // Stapel-Overview „GEMEISTERT: N" zeigt. Wir füllen die
            // session.cardMastery für die schon-gemasterten Karten
            // synthetisch auf, damit die UI-Counter zusammenpassen.
            // Die Karten selbst sind weiter aus den remainingCardIDs
            // gefiltert — sie tauchen also nicht erneut im Spielfluss
            // auf, nur in der Statistik.
            if var session = sessionStore.session {
                let threshold = sessionStore.masteryThreshold
                for masteredUUID in deck.masteredCardIDs {
                    let key = masteredUUID.uuidString
                    var mastery = session.cardMastery[key] ?? CardMastery()
                    if mastery.consecutiveCorrect < threshold {
                        mastery.consecutiveCorrect = threshold
                    }
                    session.cardMastery[key] = mastery
                }
                sessionStore.session = session
                appDebugLog("🔁 Stand-Sync: \(deck.masteredCardIDs.count) gemasterte Karten in session.cardMastery vor-gepopuliert (threshold=\(threshold))")
            }

            setup.isShowingSetup = false

            // **Bug-Fix 2026-04-22**: Auto-Speech-Kette aus dem Hot-Path
            // entfernt — sie hat in Kombination mit den Lifecycle-
            // OnChange-Sinks dazu geführt, dass sich der Setup-Body
            // nochmal zurück geflippt hat. Auto-Speech wird stattdessen
            // im Session-Screen-onAppear getriggert (siehe Lifecycle-
            // Folge-Pass).
        }
    }

    // MARK: - Session-End-Sync

    /// Schreibt den aktuellen Session-Fortschritt in den
    /// `PersonalDeckStore` zurück. Wird beim Verlassen der Session
    /// aufgerufen (Back-Button / Scene → Background). Bewusst auf
    /// Session-Ende beschränkt, damit das Hot-Path-Rendering nicht
    /// durch Persistenz-Arbeit gebremst wird.
    func syncPersonalDeckProgressIfNeeded() {
        guard let deckID = sessionStore.activePersonalDeckID,
              let deck = personalDeckStore.deck(withID: deckID),
              let session = sessionStore.session else { return }

        // Neu gemeisterte Karten einsammeln — consecutiveCorrect ≥ threshold.
        let threshold = sessionStore.masteryThreshold
        let newlyMastered: [UUID] = session.cardMastery.compactMap { pair in
            guard pair.value.level(threshold: threshold) == .mastered,
                  let uuid = UUID(uuidString: pair.key) else { return nil }
            return uuid
        }

        // currentIndex: nächste Karte, die als nächstes gespielt werden
        // würde, berechnet als Position der letzten nicht-gemeisterten
        // Karte +1 im deck.cardOrder. Fallback: +1 auf current, modulo
        // Länge.
        let updatedMasteredSet = deck.masteredCardIDs.union(newlyMastered)
        let nextIndex: Int = {
            let total = deck.cardOrder.count
            guard total > 0 else { return 0 }
            // Suche die nächste Position, die NOCH nicht mastered ist.
            for offset in 1...total {
                let idx = (deck.currentIndex + offset) % total
                let id = deck.cardOrder[idx]
                if !updatedMasteredSet.contains(id) {
                    return idx
                }
            }
            return deck.currentIndex // Alle mastered → Cursor bleibt.
        }()

        personalDeckStore.update(id: deckID) { mutableDeck in
            mutableDeck.masteredCardIDs = updatedMasteredSet
            mutableDeck.currentIndex = nextIndex
            mutableDeck.lastAccessedAt = Date()
        }

        sessionStore.activePersonalDeckID = nil
    }
}
