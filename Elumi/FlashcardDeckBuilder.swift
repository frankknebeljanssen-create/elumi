import Foundation

enum FlashcardDeckBuilder {
    static func buildDeck(
        from list: VocabularyList?,
        preferredCardType: CardType?
    ) -> FlashcardDeck? {
        guard let list else { return nil }

        let filteredItems = list.items.filter { item in
            guard let preferredCardType else { return true }
            return item.cardType == preferredCardType
        }

        let sourceLanguage = filteredItems.first?.sourceLanguage ?? list.items.first?.sourceLanguage ?? .french
        return FlashcardDeck(
            id: "custom-\(list.id.uuidString)",
            name: list.name,
            sourceLanguage: sourceLanguage,
            cards: filteredItems.map { item in
                FlashcardDeckCard(
                    id: item.id.uuidString,
                    french: item.french,
                    german: item.german,
                    sourceLanguage: item.sourceLanguage,
                    cardType: item.cardType
                )
            }
        )
    }

    /// **2026-08-05** — `urgency` priorisiert die Teilmenge, wenn nicht
    /// der ganze Stapel geübt wird (User-Report: „zwei Wörter aus der
    /// Lernliste wurden bei Karteikarten gar nicht abgefragt").
    ///
    /// Vorher zog `sampledVocabularyItems` per Reservoir-Sampling rein
    /// zufällig — keine Vokabel war dauerhaft gesperrt, aber es gab auch
    /// keinerlei Abdeckungs-Garantie: Bei 20 von 35 Karten lag die
    /// Chance pro Wort und Runde bei ~57 %, reiner Zufall. Wörter, die
    /// nie gezogen wurden, tauchten folglich auch nie im Lernstatus auf
    /// und fielen still aus dem Lernkreislauf.
    ///
    /// Jetzt entscheidet der Aufrufer per Closure, wie dringend ein Item
    /// ist (kleinerer Wert = dringender, typischerweise abgeleitet aus
    /// `ItemLearningStatusStore`: noch nie geübt vor wackelnd vor sitzt).
    /// Innerhalb derselben Dringlichkeitsstufe wird weiterhin gemischt,
    /// damit sich Runden nicht identisch wiederholen. Ohne Closure
    /// bleibt es beim bisherigen Zufalls-Sampling.
    static func buildDeck(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?,
        maxCardCount: Int? = nil,
        urgency: ((VocabularyItem) -> Int)? = nil
    ) -> FlashcardDeck? {
        let selectedItems: [VocabularyItem]
        if let maxCardCount, maxCardCount > 0 {
            selectedItems = sampledVocabularyItems(
                from: lists,
                language: language,
                preferredCardType: preferredCardType,
                maxCardCount: maxCardCount,
                urgency: urgency
            )
        } else {
            selectedItems = filteredVocabularyItems(
                from: lists,
                language: language,
                preferredCardType: preferredCardType
            )
        }

        guard !selectedItems.isEmpty else { return nil }

        let limitedCards = selectedItems.map { item in
            FlashcardDeckCard(
                id: item.id.uuidString,
                french: item.french,
                german: item.german,
                sourceLanguage: item.sourceLanguage,
                cardType: item.cardType
            )
        }

        let deckName = lists.count == 1 ? lists[0].name : "Mein Stapel"
        let typeSuffix = preferredCardType?.rawValue ?? "mixed"
        let countSuffix = maxCardCount.map(String.init) ?? "all"
        let deckID = "custom-stack-\(language.shortCode.lowercased())-\(typeSuffix)-\(countSuffix)-" + lists.map { $0.id.uuidString }.sorted().joined(separator: "-")

        return FlashcardDeck(
            id: deckID,
            name: deckName,
            sourceLanguage: language,
            cards: limitedCards
        )
    }

    private static func matchingVocabularyItem(
        _ item: VocabularyItem,
        language: StudyLanguage,
        preferredCardType: CardType?
    ) -> VocabularyItem? {
        guard item.sourceLanguage == language else { return nil }
        if let preferredCardType, item.cardType != preferredCardType {
            return nil
        }
        return item
    }

    private static func filteredVocabularyItems(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?
    ) -> [VocabularyItem] {
        lists.flatMap { list in
            list.items.compactMap { item in
                matchingVocabularyItem(item, language: language, preferredCardType: preferredCardType)
            }
        }
    }

    private static func sampledVocabularyItems(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?,
        maxCardCount: Int,
        urgency: ((VocabularyItem) -> Int)? = nil
    ) -> [VocabularyItem] {
        guard maxCardCount > 0 else { return [] }

        let candidates = lists
            .flatMap(\.items)
            .compactMap {
                matchingVocabularyItem(
                    $0,
                    language: language,
                    preferredCardType: preferredCardType
                )
            }
        guard candidates.count > maxCardCount else { return candidates }

        guard let urgency else {
            // Kein Lernstatus-Kontext → wie bisher zufällig ziehen.
            return Array(candidates.shuffled().prefix(maxCardCount))
        }

        // Erst mischen, dann **stabil** nach Dringlichkeit sortieren:
        // Die dringendsten Items stehen vorn, innerhalb einer Stufe
        // bleibt die zufällige Reihenfolge aus dem Shuffle erhalten.
        return Array(
            candidates
                .shuffled()
                .enumerated()
                .sorted { lhs, rhs in
                    let lhsUrgency = urgency(lhs.element)
                    let rhsUrgency = urgency(rhs.element)
                    if lhsUrgency != rhsUrgency { return lhsUrgency < rhsUrgency }
                    return lhs.offset < rhs.offset
                }
                .prefix(maxCardCount)
                .map(\.element)
        )
    }
}
