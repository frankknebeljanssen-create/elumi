import Foundation

/// **Stufe 1 (2026-04-28)** — zentrale Auflösung der „effektiven"
/// Item-Liste für eine ausgewählte VocabularyList unter
/// Berücksichtigung optionaler hierarchischer Filter (Lernjahr-
/// Children mit cumulativeChildren).
///
/// Single Source of Truth: jeder Consumer ruft hier hinein, statt
/// `list.items` direkt zu lesen. Damit ist die Filter-Logik an EINER
/// Stelle und Erweiterungen (Confidence-Filter, Topic-Filter etc.)
/// kommen automatisch durch alle Consumer durch.
///
/// **V1a-Scope**: Word Runner (`LiveListRunnerTaskProvider`) ruft
/// hier hinein. Quiz/Flashcards/Training-Generator folgen in V1b.
///
/// Die Funktion ist `pure` — kein Side-Effect, kein Logging,
/// deterministisch. Persistente State-Variablen (UserDefaults-Lookup)
/// macht der Caller, nicht der Resolver.
enum VocabularyListSelectionResolver {

    /// Liefert die effektive Item-Liste für eine ausgewählte Liste.
    ///
    /// Verhalten:
    ///   • Liste ohne `children` ODER ohne `cumulativeChildren=true`
    ///     → returns `list.items` unverändert.
    ///   • Liste mit cumulative-Children UND `lernjahrMax == nil`
    ///     → returns `list.items` (Parent voll = alle Lernjahre).
    ///   • Liste mit cumulative-Children UND `lernjahrMax = n` (1..5)
    ///     → returns `children.prefix(n).flatMap(\.items)`.
    ///
    /// Die letzte Variante slicet die Children-Items bis Index n
    /// (1-basiert; prefix(n) nimmt die ersten n Children = Y_1…Y_n).
    static func effectiveItems(
        for list: VocabularyList,
        lernjahrMax: Int?
    ) -> [VocabularyItem] {
        guard let children = list.children,
              list.cumulativeChildren,
              let max = lernjahrMax,
              max >= 1
        else {
            // Fallback: Parent-Items (alle Lernjahre, oder klassische
            // flache Liste ohne Hierarchie).
            return list.items
        }
        // Cumulative-Slice: Y_1...Y_max. Cap auf children.count, damit
        // ein out-of-range max-Wert (z. B. 99 aus alten UserDefaults)
        // nicht crasht.
        let cap = Swift.min(max, children.count)
        return children.prefix(cap).flatMap(\.items)
    }
}
