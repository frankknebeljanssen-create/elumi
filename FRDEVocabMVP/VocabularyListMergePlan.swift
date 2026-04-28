import Foundation

/// **Zentraler Import-/Merge-Helper** für „Zu bestehender Liste hinzufügen".
///
/// Trennung von Plan und Apply, damit die UI vor dem Schreiben Konflikte
/// zur User-Entscheidung anzeigen kann (User-Spec 2026-04-22 Abend V).
///
/// Pipeline:
/// ```
///   incoming items + existing list
///         │
///         ▼
///   computePlan(...) → MergePlan {
///       safeAdds:               [VocabularyItem]   // nicht in Liste, kein Konflikt
///       exactDuplicatesToSkip:  [VocabularyItem]   // exakter Duplikat-Match
///       conflicts:              [ImportConflict]   // unklar — User entscheidet
///   }
///         │
///         ▼  (UI zeigt Conflict-Sheet, wenn conflicts.isEmpty == false)
///         │
///         ▼  pro Konflikt: keepExisting | replaceWithIncoming
///         │
///         ▼
///   applyPlan(...) → MergeResult {
///       added:    Int
///       skipped:  Int   // exakte Duplikate
///       replaced: Int   // Konflikte mit replace-Entscheidung
///   }
/// ```
///
/// **Definition** „exakter Duplikat":
///   Nach Normalisierung (case-insensitive, whitespace getrimmt + kollabiert)
///   sind sowohl `french` als auch `german` UND `cardType` gleich.
///
/// **Definition** „Konflikt":
///   Genau **eine** Seite (entweder `french` oder `german`) matcht
///   normalisiert. Die andere Seite weicht ab. Beispiele:
///     • bestehend: „bonjour|guten tag" — incoming: „bonjour|hallo"
///       → Konflikt (gleicher Source, anderer Target)
///     • bestehend: „bonjour|hallo" — incoming: „salut|hallo"
///       → Konflikt (gleicher Target, anderer Source)
///   Solche Fälle werden NIE automatisch dupliziert — der User
///   entscheidet pro Eintrag.

// MARK: - Normalisierung

enum VocabularyMergeNormalization {
    /// Für Vergleichszwecke: lowercased, getrimmt, mehrfacher Whitespace
    /// kollabiert auf ein Leerzeichen, alle Zeilenumbrüche zu Spaces.
    static func key(_ text: String) -> String {
        let lowered = text.lowercased()
        let unifiedWhitespace = lowered
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let collapsed = unifiedWhitespace
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Konflikt-Modell

/// Ein Item-Paar, das nicht eindeutig als Duplikat gilt — aber stark
/// genug überlappt, dass automatisches doppeltes Einfügen falsch wäre.
struct ImportConflict: Identifiable {
    enum Resolution: Equatable {
        case keepExisting        // Default
        case replaceWithIncoming
    }

    let id: UUID = UUID()
    /// Existing item in der Ziel-Liste (wird ggf. ersetzt).
    let existing: VocabularyItem
    /// Neuer Eintrag aus dem Scan-Review.
    let incoming: VocabularyItem
    /// User-Entscheidung. Default: existing behalten (sicherer Fallback,
    /// falls User den Sheet ohne Aktion schließt).
    var resolution: Resolution = .keepExisting

    /// Welche Seite matcht — für UI-Anzeige.
    enum MatchKind: Equatable {
        case sameSourceDifferentTarget
        case sameTargetDifferentSource
    }
    let matchKind: MatchKind
}

// MARK: - MergePlan

struct MergePlan {
    /// Items, die direkt eingefügt werden können (keine Überlappung).
    let safeAdds: [VocabularyItem]
    /// Items, die exakte Duplikate sind und übersprungen werden.
    let exactDuplicatesToSkip: [VocabularyItem]
    /// Konflikte mit User-Entscheidung.
    var conflicts: [ImportConflict]

    var hasConflicts: Bool { !conflicts.isEmpty }
    var requiresUserDecision: Bool { hasConflicts }
}

/// Resultat des Apply-Schrittes — für die Erfolgs-Anzeige.
struct MergeResult: Equatable {
    /// Zustand nach dem Apply.
    enum Status: Equatable {
        case success
        /// Ziel-Liste wurde nicht gefunden (z. B. zwischen Plan und Apply gelöscht).
        case targetListMissing
        /// Persistenz-Validierung ist gefehlschlagen — der After-Count
        /// in der Liste matcht nicht mit dem Plan-Erwartungswert.
        case persistenceMismatch(expected: Int, actual: Int)
    }

    let status: Status
    let added: Int        // safe-Adds + Konflikt-Replaces
    let skipped: Int      // exakte Duplikate
    let replaced: Int     // Konflikte mit `.replaceWithIncoming`

    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }

    /// Convenience: für Fehlerfälle ein Result mit 0/0/0 + Status-Info.
    static func failure(_ status: Status) -> MergeResult {
        MergeResult(status: status, added: 0, skipped: 0, replaced: 0)
    }
}

// MARK: - Planner

enum VocabularyListMergePlanner {

    /// Pure function: berechnet einen MergePlan aus eingehenden Items
    /// und einer bestehenden Item-Liste. Keine Side-Effects.
    static func computePlan(
        incoming: [VocabularyItem],
        existingItems: [VocabularyItem]
    ) -> MergePlan {
        // Vorab: Lookup-Index der bestehenden Items, damit wir nicht
        // O(n²) durch das Existing iterieren müssen.
        var bySource: [String: [VocabularyItem]] = [:]
        var byTarget: [String: [VocabularyItem]] = [:]
        for item in existingItems {
            bySource[VocabularyMergeNormalization.key(item.french), default: []].append(item)
            byTarget[VocabularyMergeNormalization.key(item.german), default: []].append(item)
        }

        var safeAdds: [VocabularyItem] = []
        var duplicates: [VocabularyItem] = []
        var conflicts: [ImportConflict] = []

        for incomingItem in incoming {
            let inFrenchKey = VocabularyMergeNormalization.key(incomingItem.french)
            let inGermanKey = VocabularyMergeNormalization.key(incomingItem.german)

            // Exakter Duplikat-Check: gleicher Source + Target + cardType.
            let exactMatch = bySource[inFrenchKey]?.first(where: { existing in
                VocabularyMergeNormalization.key(existing.german) == inGermanKey
                    && existing.cardType == incomingItem.cardType
            })

            if exactMatch != nil {
                duplicates.append(incomingItem)
                continue
            }

            // Konflikt-Check: source-only oder target-only Übereinstimmung.
            if let sameSource = bySource[inFrenchKey]?.first {
                conflicts.append(
                    ImportConflict(
                        existing: sameSource,
                        incoming: incomingItem,
                        matchKind: .sameSourceDifferentTarget
                    )
                )
                continue
            }
            if let sameTarget = byTarget[inGermanKey]?.first {
                conflicts.append(
                    ImportConflict(
                        existing: sameTarget,
                        incoming: incomingItem,
                        matchKind: .sameTargetDifferentSource
                    )
                )
                continue
            }

            // Keine Überschneidung — sicher einfügbar.
            safeAdds.append(incomingItem)
        }

        return MergePlan(
            safeAdds: safeAdds,
            exactDuplicatesToSkip: duplicates,
            conflicts: conflicts
        )
    }

    /// Wendet den Plan auf eine Item-Liste an und liefert die neue
    /// Item-Liste + ein Result-Objekt zurück. **Keine** direkten
    /// Store-Mutationen hier — der Store ruft das auf und persistiert
    /// das Ergebnis.
    static func apply(
        plan: MergePlan,
        to existingItems: [VocabularyItem]
    ) -> (newItems: [VocabularyItem], result: MergeResult) {
        var working = existingItems
        var addedCount = plan.safeAdds.count
        var replacedCount = 0

        // 1. Safe-Adds anhängen.
        working.append(contentsOf: plan.safeAdds)

        // 2. Konflikte auflösen.
        for conflict in plan.conflicts {
            switch conflict.resolution {
            case .keepExisting:
                // Nichts tun — bestehender Eintrag bleibt.
                break
            case .replaceWithIncoming:
                if let idx = working.firstIndex(where: { $0.id == conflict.existing.id }) {
                    // Wir behalten die ID des Existing, damit eventuelle
                    // Lern-Statistiken / Mastery weitergeführt werden.
                    var replaced = conflict.incoming
                    replaced.id = conflict.existing.id
                    working[idx] = replaced
                    replacedCount += 1
                    addedCount += 1   // im Sinne von „neuer Inhalt drin"
                }
            }
        }

        return (
            working,
            MergeResult(
                status: .success,
                added: addedCount,
                skipped: plan.exactDuplicatesToSkip.count,
                replaced: replacedCount
            )
        )
    }
}
