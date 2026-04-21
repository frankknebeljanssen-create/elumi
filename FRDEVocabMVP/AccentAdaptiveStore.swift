import Foundation
import Combine

/// Persistenter Speicher für adaptive Akzent-Gewichtung.
///
/// Merkt sich pro Akzenttyp einen `confidence`-Wert in `[0, 1]`:
///   • 1.0 = der Nutzer beantwortet diesen Typ zuverlässig richtig
///   • 0.0 = häufige Fehler, braucht mehr Wiederholung
///
/// Nach jeder Session wird der Wert per **Exponential Moving Average**
/// aktualisiert (α = 0.35). Frische Daten ziehen den Wert stark, aber
/// nicht so stark, dass ein einzelner Ausrutscher die Historie kippt.
///
/// Der `ContentBuilder` fragt vor jeder Session den Store ab und
/// gewichtet die Seed-Auswahl **gegenläufig** zur Confidence: niedrige
/// Werte → mehr Aufgaben dieses Typs in der nächsten Runde. Bewusst
/// leichtgewichtig, kein ML-System — klare Regeln + Persistenz reicht
/// für ein spürbar kluges Nachschärfen.
@MainActor
final class AccentAdaptiveStore: ObservableObject {

    /// Shared Instance — der Store lebt app-weit, sodass Session-zu-
    /// Session-Lerneffekte erhalten bleiben. Kein DI-Graph nötig.
    static let shared = AccentAdaptiveStore()

    // MARK: - Persistenz

    /// Alle Default-Werte 0.6 — neutraler Startwert, sodass Neuanfänger
    /// eine gleichmäßige Verteilung bekommen, aber schon leicht
    /// unterbewertet sind (→ nach wenigen falschen Antworten greift die
    /// adaptive Logik schnell).
    private static let defaultConfidence: Double = 0.6

    /// α-Wert fürs Exponential Moving Average.
    private static let updateAlpha: Double = 0.35

    private let defaults: UserDefaults
    private let storageKey = "accents.confidenceByType.v1"

    /// Confidence-Map — sichtbar für Observer, wird bei Änderungen
    /// automatisch persistiert.
    @Published private(set) var confidenceByType: [AccentType: Double] = [:]

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Public API

    /// Liefert den aktuellen Confidence-Wert für einen Typ. Defaultet
    /// auf 0.6, wenn für diesen Typ noch nichts gespeichert ist.
    func confidence(for type: AccentType) -> Double {
        confidenceByType[type] ?? Self.defaultConfidence
    }

    /// Aktualisiert die Confidence pro Akzenttyp **aus einer abge-
    /// schlossenen Session**. Pro Typ wird die Trefferquote dieser
    /// Session berechnet und per EMA in die historische Confidence
    /// eingemischt.
    ///
    /// - Parameter breakdown: (type, correct, total) pro Akzenttyp aus
    ///   `AccentSessionEngine.breakdownByType()`.
    func updateFromSession(breakdown: [(type: AccentType, correct: Int, total: Int)]) {
        for entry in breakdown where entry.total > 0 {
            let ratio = Double(entry.correct) / Double(entry.total)
            let current = confidence(for: entry.type)
            let updated = current * (1 - Self.updateAlpha) + ratio * Self.updateAlpha
            confidenceByType[entry.type] = clamp(updated)
        }
        persist()
    }

    /// Liefert die Akzenttypen in **aufsteigender** Confidence-Reihenfolge
    /// — der schwächste zuerst. Nützlich für das Result-Screen-Ranking
    /// und den ContentBuilder.
    func weakestTypesFirst() -> [AccentType] {
        let known = AccentType.mvpActive
        return known.sorted { confidence(for: $0) < confidence(for: $1) }
    }

    /// Setzt den gesamten Store zurück. Fürs Debug / Tests / „Fortschritt
    /// zurücksetzen"-Option im Settings-Screen (falls später gewünscht).
    func reset() {
        confidenceByType = [:]
        persist()
    }

    // MARK: - Persistenz (intern)

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        var mapped: [AccentType: Double] = [:]
        for (key, value) in decoded {
            if let type = AccentType(rawValue: key) {
                mapped[type] = clamp(value)
            }
        }
        confidenceByType = mapped
    }

    private func persist() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: confidenceByType.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func clamp(_ v: Double) -> Double {
        min(1, max(0, v))
    }
}
