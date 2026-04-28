import Foundation

/// **Persönlicher Trainingsmodus (Phase 8)** — ein vom User erstellter
/// Kartenstapel aus einer oder mehreren Vokabel-Listen, der einmalig
/// beim Erstellen gemischt wird und anschließend eine **fixe Reihenfolge**
/// behält. `currentIndex` markiert die zuletzt gespielte Position, damit
/// der User beim nächsten Mal genau dort weitermachen kann.
///
/// Abgrenzung zur regulären Flashcard-Session:
///   • Reguläre Session: zufälliger Draw, Karten fallen bei Mastery raus.
///   • Persönlicher Stapel: feste Reihenfolge, „gemeisterte" Karten
///     bleiben in `cardOrder` drin, werden aber bei Render/Index-
///     Berechnung via `masteredCardIDs` übersprungen. Bei End-of-List
///     → Wrap-around auf Index 0 (gemasterte Karten weiterhin skipped).
///
/// Persistiert als JSON in UserDefaults via `PersonalDeckStore`.
struct PersonalDeck: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// 0 = Pink (`#FF4D80`), 1 = Blau (`#5B9CF5`). Hartcodierter Index,
    /// weil User-Spec nur **zwei** Slots erlaubt — jeder Stapel hat seine
    /// feste Identitäts-Farbe. Keine eigene Color-Struct, damit die
    /// JSON-Persistenz ohne Custom-Encoder auskommt.
    var colorIndex: Int
    var sourceListIDs: [UUID]
    /// Einmalig gemischte Karten-ID-Reihenfolge. Wird nach dem Create
    /// **nicht mehr verändert**, damit der User eine konstante Stapel-
    /// Reihenfolge erlebt.
    var cardOrder: [UUID]
    var currentIndex: Int
    /// IDs der Karten, die den Mastery-Threshold erreicht haben. Werden
    /// beim nächsten Aufruf übersprungen.
    var masteredCardIDs: Set<UUID>
    var lastAccessedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int,
        sourceListIDs: [UUID],
        cardOrder: [UUID],
        currentIndex: Int = 0,
        masteredCardIDs: Set<UUID> = [],
        lastAccessedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.sourceListIDs = sourceListIDs
        self.cardOrder = cardOrder
        self.currentIndex = currentIndex
        self.masteredCardIDs = masteredCardIDs
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
    }

    // MARK: - Derived

    /// Anzahl Karten, die noch aktiv sind (nicht mastered). Für das
    /// „X aktiv verbleibend"-Label im Session-Badge.
    var activeRemainingCount: Int {
        cardOrder.count - masteredCardIDs.count
    }

    /// Fortschritts-Balken-Wert 0…1 basierend auf `currentIndex` relativ
    /// zur Gesamtlänge. Nutzt den rohen Index (nicht aktive Karten),
    /// weil das UI den Balken als lineare Stapel-Position meint.
    var progressFraction: Double {
        let total = max(1, cardOrder.count)
        return min(1.0, max(0.0, Double(currentIndex) / Double(total)))
    }

    // MARK: - Card-Order-Snapshot (V1b Lernjahr-Filter, 2026-04-28)

    /// **Snapshot-Semantik für `cardOrder`** — zentraler Helper für alle
    /// Pfade, die einen Personal-Deck-Karten-Pool aus Quell-Listen
    /// aufbauen (Create / Update-with-listsChanged / UUID-Stale-Recovery).
    ///
    /// **Verhalten:**
    /// Items werden zum Aufruf-Zeitpunkt mit dem **aktuellen**
    /// `lernjahrMax` aus `VocabularyListSelectionResolver.currentLernjahrMax()`
    /// gefiltert (Per-Liste-Slice via `effectiveItems`). Das Ergebnis ist
    /// eine flache Liste von Item-UUIDs — die Caller-Site kümmert sich
    /// selbst um `.shuffled()` falls gewünscht.
    ///
    /// **Snapshot-Garantie:**
    /// Spätere `lernjahrMax`-Änderungen wirken NICHT auf bereits
    /// existierende Decks. Der eingefrorene `cardOrder` bleibt stabil,
    /// bis der User explizit über den Edit-Mode mit
    /// `listsChanged = true` einen Re-Snapshot erzwingt — dann läuft
    /// dieser Helper erneut mit dem aktuellen `lernjahrMax`.
    ///
    /// **Recovery-Pfad:**
    /// Beim UUID-Stale-Recovery (DB-Reload erzeugt neue UUIDs, alter
    /// cardOrder findet keine Matches mehr) wird der Helper ebenfalls
    /// genutzt — die aktuellen Filter-Regeln gelten auch dort, weil
    /// Recovery den ursprünglichen Snapshot ohnehin zerstört (Mastery-
    /// Daten weg, neuer Shuffle).
    static func buildCardOrderSnapshot(from lists: [VocabularyList]) -> [UUID] {
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        return lists.flatMap { list in
            VocabularyListSelectionResolver.effectiveItems(
                for: list,
                lernjahrMax: lernjahrMax
            )
        }.map(\.id)
    }
}
