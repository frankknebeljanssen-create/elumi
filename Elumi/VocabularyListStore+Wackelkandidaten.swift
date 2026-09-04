// VocabularyListStore+Wackelkandidaten.swift
// **Übungsliste aus Schwachstellen (2026-08-04)** — generierte
// Auto-Liste „Meine Wackelkandidaten".
//
// Idee (User-Spec): Der Lernstatus sammelt modulübergreifend, welche
// Vokabeln noch nicht sitzen. Statt diese Liste nur anzuschauen, will
// der User genau diesen Bestand als echte Liste zum Üben — einmal
// bauen, dann mit Karteikarten / Quiz / Training gezielt nur das
// Schwache pauken, ohne das schon Sitzende immer wieder mitzuschleppen.
//
// **Architektur** — dasselbe Muster wie `+ChatStapel.swift`:
//   • Eine ganz normale Custom-Liste (`isBuiltIn: false`), damit sie im
//     Picker auftaucht und jede Übung sie ohne Sonderfall nutzen kann.
//   • Stabile, hartcodierte UUID → die Liste ist wiederfindbar und wird
//     bei jedem Neu-Bauen **überschrieben** statt dupliziert. So wandert
//     alles, was inzwischen „Stark" ist, automatisch raus.
//   • NICHT das `PersonalDeck`-System (Snapshot-Semantik + 2er-Cap
//     würden den kontinuierlichen Charakter kaputtmachen).
//
// **Datengrenze** — der Lernstatus speichert pro Wort nur
// `displayFrench` + `displayGerman` + `cardType` (kein Genus-Variant,
// keine Beispiel-Metadaten). Für Karteikarten/Quiz/Training reicht das
// voll. Einträge ohne beide Seiten (z. B. Akzent-Training: nur
// Französisch, leeres Deutsch) werden übersprungen — eine halbe Karte
// wäre im Drill unbrauchbar.

import Foundation

extension VocabularyListStore {
    /// Stabile UUID der generierten Übungsliste. Pattern analog zu
    /// `chatStapelListID`.
    static let wackelkandidatenListID: UUID =
        UUID(uuidString: "F2AB1E00-1EA0-1EA0-1EA0-000000000002")!

    /// Display-Name — an einer Stelle gehalten, damit UI-Strings synchron
    /// bleiben.
    static let wackelkandidatenDisplayName = "Meine Wackelkandidaten"

    /// Baut die Übungsliste aus den übergebenen Lernstatus-Einträgen neu
    /// (bzw. überschreibt eine bereits existierende gleicher UUID).
    ///
    /// - Filtert Einträge ohne beide Seiten heraus (leeres FR oder DE).
    /// - Dedupliziert case-insensitive auf `(french, german, cardType)`.
    /// - Rebuild-Semantik: die Items der Liste werden **komplett ersetzt**,
    ///   nicht angehängt — der Bestand spiegelt immer den aktuellen
    ///   Lernstatus.
    ///
    /// Returns die stabile UUID **wenn mindestens ein brauchbares Item
    /// entstand**; sonst `nil` (dann wird keine leere Liste angelegt und
    /// eine evtl. vorhandene leergeräumte Liste bleibt unangetastet — der
    /// Aufrufer sollte den Button ohnehin nur bei vorhandenen
    /// Wackelkandidaten zeigen).
    /// **2026-08-04** — Reine Filter-/Dedupe-Logik, ausgelagert aus
    /// `rebuildWackelkandidatenList(from:)`, damit die Anzeige-Zahl auf
    /// dem CTA (`practiceListCTA` in `LernstatusView`) und die
    /// tatsächliche Item-Zahl der gebauten Liste garantiert
    /// übereinstimmen (User-Report: „Zum Üben 5 + Im Aufbau 63 = 68"
    /// stand auf dem Button, aber das Popup meldete „58 Wörtern" — die
    /// rohe Wackelkandidaten-Zahl zählt jeden Eintrag, unabhängig davon,
    /// ob er später durch den Filter fällt).
    static func usableWackelkandidatenItems(from statuses: [ItemLearningStatus]) -> [VocabularyItem] {
        var seen = Set<String>()
        var items: [VocabularyItem] = []

        for status in statuses {
            let french = status.displayFrench.trimmingCharacters(in: .whitespacesAndNewlines)
            let german = status.displayGerman.trimmingCharacters(in: .whitespacesAndNewlines)
            // Beide Seiten Pflicht — eine Karte ohne Frage oder Antwort
            // wäre im Drill sinnlos (betrifft v. a. Akzent-Einträge, die
            // nur die französische Seite tracken).
            guard !french.isEmpty, !german.isEmpty else { continue }

            let dedupeKey = "\(french.lowercased())|\(german.lowercased())|\(status.cardType.rawValue)"
            guard seen.insert(dedupeKey).inserted else { continue }

            // Raw-Init: displayFrench/displayGerman sind bereits die
            // anzeige-fertigen Strings (inkl. Artikel im Text). Der
            // Display-Init würde Genus/Kapitalisierung erneut anwenden.
            items.append(
                VocabularyItem(
                    rawFrench: french,
                    rawGerman: german,
                    cardType: status.cardType,
                    sourceLanguage: .french
                )
            )
        }

        return items
    }

    @discardableResult
    func rebuildWackelkandidatenList(from statuses: [ItemLearningStatus]) -> UUID? {
        let items = Self.usableWackelkandidatenItems(from: statuses)
        guard !items.isEmpty else { return nil }

        if let index = customLists.firstIndex(where: { $0.id == Self.wackelkandidatenListID }) {
            // Überschreiben — die didSet-Persistenz greift automatisch.
            customLists[index].items = items
            customLists[index].name = Self.wackelkandidatenDisplayName
        } else {
            let list = VocabularyList(
                id: Self.wackelkandidatenListID,
                name: Self.wackelkandidatenDisplayName,
                items: items,
                isBuiltIn: false,
                collectionPreset: .other
            )
            customLists.append(list)
        }

        return Self.wackelkandidatenListID
    }
}
