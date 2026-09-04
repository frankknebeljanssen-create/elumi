import Foundation
import Combine

/// **Store für persönliche Trainingsstapel** (Phase 8). Maximal **zwei**
/// Stapel können gleichzeitig existieren — das ist eine harte UI-Regel,
/// damit der Flashcard-Setup-Screen übersichtlich bleibt. Persistenz über
/// UserDefaults als JSON (kein CoreData, weil das Datenmodell einfach
/// und flach ist).
///
/// Alle Schreib-Operationen rufen `save()` sofort auf, damit App-Crash
/// oder Background-Wechsel keinen Fortschritt verschluckt.
@MainActor
final class PersonalDeckStore: ObservableObject {
    /// Singleton — es gibt nur eine Liste persönlicher Stapel pro
    /// Account; ein Shared-Store vermeidet Synchronisations-Probleme
    /// zwischen Setup-Screen, Session-View und Environment-Injection.
    static let shared = PersonalDeckStore()

    /// Hard-Cap der gleichzeitig erlaubten Stapel. Spec: zwei Slots.
    static let maxDeckCount = 2

    @Published private(set) var decks: [PersonalDeck] = []

    private init() {
        self.decks = Self.load()

        // **Codeaudit 2026-09-03, Stufe 3 (Punkt 18)** — der Store ist
        // ein Singleton und ueberlebt den Account-Wechsel. Ohne diesen
        // Reload behielte er die Stapel des vorigen Kindes im Speicher
        // und schriebe sie beim naechsten `save()` in dessen Slot.
        NotificationCenter.default.addObserver(
            forName: AccountStore.didSwitchAccount,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadForCurrentAccount()
            }
        }
    }

    /// Liest die Stapel des jetzt aktiven Accounts neu ein. Wird nach
    /// jedem Account-Wechsel gerufen; die Swap-Maschine im
    /// `AccountStore` hat den globalen Slot zu diesem Zeitpunkt bereits
    /// auf den neuen Account umgestellt.
    func reloadForCurrentAccount() {
        decks = Self.load()
    }

    // MARK: - Persistence

    private static let storageKey = appPersonalDecksKey

    private static func load() -> [PersonalDeck] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([PersonalDeck].self, from: data)
            return Array(decoded.prefix(maxDeckCount))
        } catch {
            // Korruption → leeren State zurückgeben, nicht crashen.
            // Der User verliert im schlimmsten Fall seine Stapel, die
            // App startet aber sauber.
            appDebugLog("⚠️ PersonalDeckStore decode failed: \(error)")
            return []
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(decks)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            appDebugLog("⚠️ PersonalDeckStore encode failed: \(error)")
        }
    }

    // MARK: - Public API

    /// Fügt einen neuen Stapel hinzu. Lehnt ab, wenn bereits
    /// `maxDeckCount` Stapel existieren. Gibt den erzeugten Stapel
    /// zurück, falls erfolgreich.
    @discardableResult
    func add(_ deck: PersonalDeck) -> PersonalDeck? {
        guard decks.count < Self.maxDeckCount else { return nil }
        decks.append(deck)
        save()
        return deck
    }

    /// Entfernt den Stapel anhand der ID. No-op, falls die ID
    /// nicht existiert (verhindert Crash bei doppelten Delete-Taps).
    func remove(id: UUID) {
        decks.removeAll { $0.id == id }
        save()
    }

    /// Benennt einen Stapel um. No-op, falls die ID nicht existiert.
    func rename(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        decks[index].name = trimmed
        save()
    }

    /// Aktualisiert den Fortschritt eines Stapels — wird nach jedem
    /// gespielten Kartenzyklus aus dem Session-Controller aufgerufen.
    /// Nimmt eine Mutator-Closure entgegen, damit mehrere Felder atomar
    /// aktualisiert werden können (z. B. Index + masteredCardIDs +
    /// lastAccessedAt in einem Save).
    func update(id: UUID, _ mutate: (inout PersonalDeck) -> Void) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&decks[index])
        save()
    }

    /// **User-Revision 2026-04-22**: Ersetzt ein existierendes Deck
    /// vollständig (Id-Match). Wird vom Edit-Flow genutzt: User
    /// bearbeitet Listen + Name, wir bekommen das komplett neu gebaute
    /// Deck-Objekt und schreiben es in-place.
    ///
    /// **Bug-Fix (Phase 8.2 v2)**: garantiert, dass das @Published-
    /// Update auch wirklich propagiert — Subscript-Mutation auf einem
    /// Published-Array konnte in einigen iOS-Versionen das
    /// objectWillChange ausschlafen. Jetzt wird das Array komplett neu
    /// aufgebaut + zurückgewiesen.
    func replace(_ updated: PersonalDeck) {
        guard let index = decks.firstIndex(where: { $0.id == updated.id }) else {
            appDebugLog("⚠️ PersonalDeckStore.replace: deck-id \(updated.id) nicht in store gefunden — no-op")
            return
        }
        var rebuilt = decks
        rebuilt[index] = updated
        decks = rebuilt   // Komplett-Reassign → garantiert objectWillChange
        save()
        appDebugLog("✅ PersonalDeckStore.replace: id=\(updated.id) sourceLists=\(updated.sourceListIDs.count) cardOrder=\(updated.cardOrder.count)")
    }

    /// Freie Slots (0…maxDeckCount). Wird vom Setup-Screen für die
    /// „Neuen Stapel anlegen"-Platzhalter verwendet.
    var freeSlotCount: Int {
        max(0, Self.maxDeckCount - decks.count)
    }

    /// Nächster freier `colorIndex` basierend auf den bereits vergebenen
    /// Farben. Spec: erster Stapel → 0 (Pink), zweiter → 1 (Blau).
    var nextColorIndex: Int {
        let usedColors = Set(decks.map { $0.colorIndex })
        for candidate in 0..<Self.maxDeckCount where !usedColors.contains(candidate) {
            return candidate
        }
        return 0
    }

    /// Der passende Stapel zur ID (oder nil).
    func deck(withID id: UUID) -> PersonalDeck? {
        decks.first(where: { $0.id == id })
    }
}
