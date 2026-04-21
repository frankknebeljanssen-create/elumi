import Foundation

/// Eingebauter Katalog französischer Wörter mit Akzenten — MVP-Seed.
///
/// Dient als **Fallback**, wenn die Nutzer-Liste zu wenig geeignete Wörter
/// enthält. Wird auch im Lernen-Modus für die Beispiel-Karten genutzt.
///
/// Struktur bewusst simpel gehalten: ein Array von `SeedEntry`-Records.
/// Später kann das durch eine größere Datenquelle (TSV, DB) ersetzt werden.
/// Nur Wörter mit eindeutig trainierbarem Akzent — keine Zweifelsfälle.
enum AccentWordCatalog {

    struct SeedEntry {
        let correctWord: String        // Schreibweise MIT Akzent
        let accentType: AccentType
        /// Index des betroffenen Zeichens (0-basiert). Verwendet für
        /// Variante B (Buchstabe antippen).
        let targetIndex: Int
        /// Optional — für Speed-Round-Modus genutzt (bevorzugt `medium`/
        /// `hard`-Seeds, siehe `AccentContentBuilder.prepareSeeds`).
        let difficulty: AccentDifficulty
    }

    /// Alle verfügbaren Akzent-Seeds. Reihenfolge spielt keine Rolle —
    /// der ContentBuilder wählt je nach Modus + Round-Robin-Balance aus.
    ///
    /// Kuration: Fokus auf häufige, schulnahe Wörter. Exotische oder
    /// unnötig lange Formen (z. B. „remplaçant", „soupçon", „cérémonie")
    /// wurden ersetzt durch Alltagswörter, die Lernende sofort kennen.
    /// Pro Akzenttyp ca. 14 Einträge — Cédille bewusst auf Augenhöhe
    /// mit é/è/ê, damit die Gewichtung im Round-Robin fair ausfällt.
    static let all: [SeedEntry] = [
        // MARK: - é (accent aigu) — häufigster Akzent
        // Alle targetIndex-Werte wurden Buchstabe für Buchstabe verifiziert.
        // Sie zeigen auf das **akzentuierte Zeichen** im `correctWord`.
        SeedEntry(correctWord: "école",      accentType: .aigu, targetIndex: 0, difficulty: .easy),
        SeedEntry(correctWord: "étudiant",   accentType: .aigu, targetIndex: 0, difficulty: .easy),
        SeedEntry(correctWord: "été",        accentType: .aigu, targetIndex: 0, difficulty: .easy),
        SeedEntry(correctWord: "café",       accentType: .aigu, targetIndex: 3, difficulty: .easy),
        SeedEntry(correctWord: "bébé",       accentType: .aigu, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "télé",       accentType: .aigu, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "santé",      accentType: .aigu, targetIndex: 4, difficulty: .easy),
        SeedEntry(correctWord: "musée",      accentType: .aigu, targetIndex: 3, difficulty: .easy),   // FIX: war 4 (zeigte auf „e" statt „é")
        SeedEntry(correctWord: "clé",        accentType: .aigu, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "écrire",     accentType: .aigu, targetIndex: 0, difficulty: .medium),
        SeedEntry(correctWord: "idée",       accentType: .aigu, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "déjeuner",   accentType: .aigu, targetIndex: 1, difficulty: .medium),
        SeedEntry(correctWord: "réponse",    accentType: .aigu, targetIndex: 1, difficulty: .medium),
        SeedEntry(correctWord: "médecin",    accentType: .aigu, targetIndex: 1, difficulty: .medium),

        // MARK: - è (accent grave)
        SeedEntry(correctWord: "père",       accentType: .grave, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "mère",       accentType: .grave, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "frère",      accentType: .grave, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "très",       accentType: .grave, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "après",      accentType: .grave, targetIndex: 3, difficulty: .easy),   // FIX: war 2 (zeigte auf „r" statt „è")
        SeedEntry(correctWord: "élève",      accentType: .grave, targetIndex: 2, difficulty: .medium), // FIX: war 3 (zeigte auf „v" statt „è")
        SeedEntry(correctWord: "problème",   accentType: .grave, targetIndex: 5, difficulty: .medium),
        SeedEntry(correctWord: "collège",    accentType: .grave, targetIndex: 4, difficulty: .medium), // FIX: war 5 (zeigte auf „g" statt „è")
        SeedEntry(correctWord: "pièce",      accentType: .grave, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "règle",      accentType: .grave, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "lèvre",      accentType: .grave, targetIndex: 1, difficulty: .medium),
        SeedEntry(correctWord: "sève",       accentType: .grave, targetIndex: 1, difficulty: .medium),
        SeedEntry(correctWord: "bibliothèque", accentType: .grave, targetIndex: 8, difficulty: .hard),
        SeedEntry(correctWord: "liège",      accentType: .grave, targetIndex: 2, difficulty: .medium),

        // MARK: - ê (accent circonflexe)
        SeedEntry(correctWord: "forêt",      accentType: .circonflexe, targetIndex: 3, difficulty: .easy),
        SeedEntry(correctWord: "fenêtre",    accentType: .circonflexe, targetIndex: 3, difficulty: .medium),
        SeedEntry(correctWord: "tête",       accentType: .circonflexe, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "être",       accentType: .circonflexe, targetIndex: 0, difficulty: .easy),  // FIX: war 1 (zeigte auf „t" statt „ê")
        SeedEntry(correctWord: "même",       accentType: .circonflexe, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "rêve",       accentType: .circonflexe, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "prêt",       accentType: .circonflexe, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "bête",       accentType: .circonflexe, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "arrêt",      accentType: .circonflexe, targetIndex: 3, difficulty: .medium),
        SeedEntry(correctWord: "fête",       accentType: .circonflexe, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "crêpe",      accentType: .circonflexe, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "hôtel",      accentType: .circonflexe, targetIndex: 1, difficulty: .easy),
        SeedEntry(correctWord: "hôpital",    accentType: .circonflexe, targetIndex: 1, difficulty: .medium),
        SeedEntry(correctWord: "gâteau",     accentType: .circonflexe, targetIndex: 1, difficulty: .medium),

        // MARK: - ç (cédille) — parité mit den anderen Akzenttypen
        SeedEntry(correctWord: "garçon",     accentType: .cedille, targetIndex: 3, difficulty: .easy),
        SeedEntry(correctWord: "français",   accentType: .cedille, targetIndex: 4, difficulty: .easy),
        SeedEntry(correctWord: "ça",         accentType: .cedille, targetIndex: 0, difficulty: .easy),
        SeedEntry(correctWord: "leçon",      accentType: .cedille, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "façon",      accentType: .cedille, targetIndex: 2, difficulty: .easy),
        SeedEntry(correctWord: "glaçon",     accentType: .cedille, targetIndex: 3, difficulty: .easy),
        SeedEntry(correctWord: "hameçon",    accentType: .cedille, targetIndex: 4, difficulty: .medium), // FIX: war 3
        SeedEntry(correctWord: "reçu",       accentType: .cedille, targetIndex: 2, difficulty: .medium),
        SeedEntry(correctWord: "déçu",       accentType: .cedille, targetIndex: 2, difficulty: .medium),
        SeedEntry(correctWord: "maçon",      accentType: .cedille, targetIndex: 2, difficulty: .medium),
        SeedEntry(correctWord: "balançoire", accentType: .cedille, targetIndex: 5, difficulty: .medium), // FIX: war 4
        SeedEntry(correctWord: "provençal",  accentType: .cedille, targetIndex: 6, difficulty: .medium), // FIX: war 4
        SeedEntry(correctWord: "aperçu",     accentType: .cedille, targetIndex: 4, difficulty: .hard)    // FIX: war 3
        // „ça va" entfernt — enthält Space, würde den chooseAccent-Highlight
        // (HStack-per-char-Rendering) uneinheitlich darstellen.
    ]

    /// Alle Wörter für einen bestimmten Akzenttyp.
    static func entries(for type: AccentType) -> [SeedEntry] {
        all.filter { $0.accentType == type }
    }

    /// Alle Wörter der MVP-Akzenttypen — Convenience.
    static var mvpActive: [SeedEntry] {
        let types = Set(AccentType.mvpActive)
        return all.filter { types.contains($0.accentType) }
    }
}
