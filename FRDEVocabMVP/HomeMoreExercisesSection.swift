import SwiftUI

/// **Weitere Übungen** — sekundäre Modul-Reihe unter dem Hero-Grid.
///
/// Vier gleich-breite, quadratische Cards nebeneinander, **links und
/// rechts bündig** mit dem Hero-Grid darüber. Kein Scroll, keine
/// Pagination, keine Dots — die vier übrig gebliebenen Module
/// (Hero-Filter) passen auf eine Zeile.
///
/// Die Liste teilt sich `HomeHeroModule` (selbes Routing/Icon/Color).
struct HomeMoreExercisesSection: View {
    let onSelect: (HomeHeroModule) -> Void

    /// Feste Display-Reihenfolge für „Weitere Übungen". Alle
    /// Module, die nicht schon in den Hero-Cards oben stehen, werden
    /// aus dieser Liste gezogen — d.\u{00A0}h. die Reihenfolge hier
    /// ist die einzige Quelle der Wahrheit, unabhängig von der
    /// enum-Deklarations-Reihenfolge.
    private static let orderedModules: [HomeHeroModule] = [
        .artikel, .verbformen, .akzente, .vokabeln
    ]

    /// Module, die **nicht** schon in den Hero-Karten oben gezeigt
    /// werden. Quelle ist `HomeHeroLearningSection.heroModules`.
    private var modules: [HomeHeroModule] {
        let heroIDs = Set(HomeHeroLearningSection.heroModules.map { $0.id })
        return Self.orderedModules.filter { !heroIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section-Headline klar sekundär: 16 pt / .medium /
            // textSecondary. Damit hebt sich die Hero-Headline
            // (22 pt / .black / textPrimary) deutlich ab.
            Text("Weitere Übungen")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            // HStack mit `.frame(maxWidth: .infinity)` pro Card verteilt
            // die verfügbare Breite gleichmäßig auf alle Einträge. Bei
            // vier Modulen ergibt das links/rechts bündige, quadratische
            // Tiles in einer Zeile — ohne Scroll, ohne Dots.
            HStack(spacing: 10) {
                ForEach(modules) { module in
                    MoreExerciseCard(
                        module: module,
                        onTap: { onSelect(module) }
                    )
                }
            }
        }
    }
}

private struct MoreExerciseCard: View {
    let module: HomeHeroModule
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Quadratisches Sizing via `Color.clear` + aspectRatio —
            // dasselbe Pattern wie bei der Hero-Card. Die HStack
            // außen vergibt jeder Card gleiche Breite; aspectRatio
            // macht sie dann echt quadratisch.
            // Aspect 1.0 → 1.2: Cards ca. 15 % flacher (weniger Höhe
            // bei gleicher Breite), klar untergeordnet zu den Hero-
            // Cards. Icon von 48 → 40 pt (−17 %) und Spacing 2 → 1
            // halten den kompakten Inhalt proportional.
            Color.clear
                .aspectRatio(1.2, contentMode: .fit)
                .overlay {
                    VStack(spacing: 1) {
                        HomeModuleIconView(
                            icon: module.icon,
                            size: 40,
                            // Glyph weiß auf farbiger Card, identisch
                            // zum Hero-Grid — liest sich klar gegen
                            // den Modul-Tint.
                            glyphTint: .white
                        )
                        Text(module.title)
                            .font(.system(
                                size: module == .karteikarten ? 11 : 12,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                // Farbiger Gradient-Background in der Modulfarbe —
                // identisches Pattern wie Hero, nur etwas sanfter
                // (0.88 → 0.68 statt 0.95 → 0.75), damit die Cards
                // klar untergeordnet zu Hero wirken, aber die
                // Modul-Farb-Identität konsistent weitertragen.
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    module.accent.opacity(0.88),
                                    module.accent.opacity(0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(AppCardPressStyle())
    }
}
