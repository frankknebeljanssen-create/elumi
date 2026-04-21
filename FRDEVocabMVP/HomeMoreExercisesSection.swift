import SwiftUI

/// **Weitere Übungen** — kleinere, sekundäre Modul-Reihe (Home-Rebuild).
///
/// Liegt unter der Hero-Sektion. Horizontale Scroll-Reihe mit den
/// initialen vier Karten (Karteikarten · Nomen · Quiz · Akzente).
/// Spec: „deutlich kleiner als die Hero Karten / gleiche Größe innerhalb
/// der Reihe / kein ‚Mehr anzeigen' / horizontal scrollbar / Dot-
/// Navigation darunter".
///
/// Die Liste teilt sich `HomeHeroModule` (selbes Routing/Icon/Color) —
/// hier aber sichtbar **kompakter gerendert** (90×90) und horizontal,
/// nicht im Hero-Format (158-pt-Höhe).
struct HomeMoreExercisesSection: View {
    let onSelect: (HomeHeroModule) -> Void
    /// 0 = Anfang sichtbar, 1 = User hat zur Mitte/Ende gescrollt.
    /// Wird über `onScrollGeometryChange` (iOS 17+) live aktualisiert.
    @State private var scrollProgress: CGFloat = 0

    /// Module, die **nicht** schon in den 4 Hero-Karten oben gezeigt
    /// werden — keine Doppelungen. Quelle ist `HomeHeroLearningSection
    /// .heroModules`; sobald sich die Hero-Liste ändert, passt sich der
    /// Filter automatisch an.
    private var modules: [HomeHeroModule] {
        let heroIDs = Set(HomeHeroLearningSection.heroModules.map { $0.id })
        return HomeHeroModule.allCases.filter { !heroIDs.contains($0.id) }
    }

    // 90 → 78 (−12 pt): Weitere-Übungen-Cards etwas kleiner, damit der
    // sekundäre Charakter gegenüber dem Hero-Grid deutlicher bleibt.
    private let cardSize: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Bewusst kleiner + leichter gesetzt als die Hero-Headline
            // (21 pt / .black) — die Hero-Sektion ist die Hauptentscheidung,
            // „Weitere Übungen" ist klar sekundär. 15 → 16 (+1 pt).
            Text("Weitere Übungen")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            let visibleModules = modules
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(visibleModules) { module in
                        MoreExerciseCard(
                            module: module,
                            size: cardSize,
                            onTap: { onSelect(module) }
                        )
                    }
                }
                .padding(.horizontal, 2)
                // **Dot-Tracking** (iOS 17 kompatibel): GeometryReader
                // im Content liefert per PreferenceKey den minX im
                // Coordinate-Space „moreScroll". Bei Scroll nach
                // rechts wird minX negativ — Schwelle −50 pt
                // schaltet auf Dot 2 um.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HomeMoreScrollOffsetKey.self,
                            value: geo.frame(in: .named("moreScroll")).minX
                        )
                    }
                )
            }
            .coordinateSpace(name: "moreScroll")
            .frame(height: cardSize + 8)
            .onPreferenceChange(HomeMoreScrollOffsetKey.self) { minX in
                // minX = 0 am Anfang, sinkt ins Negative beim Scrollen
                // nach rechts. Schwelle pragmatisch bei −50 pt.
                scrollProgress = minX < -50 ? 1 : 0
            }

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { idx in
                    let isActive = (idx == 0 && scrollProgress < 0.5) ||
                                   (idx == 1 && scrollProgress >= 0.5)
                    Circle()
                        .fill(isActive
                              ? AppTheme.Colors.elumiBlue
                              : AppTheme.Colors.textSecondary.opacity(0.30))
                        .frame(width: isActive ? 7 : 5,
                               height: isActive ? 7 : 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .animation(.easeInOut(duration: 0.18), value: scrollProgress < 0.5)
        }
    }
}

/// PreferenceKey für das Dot-Tracking — bubbelt den minX-Offset des
/// LazyHStacks aus dem ScrollView nach oben.
private struct HomeMoreScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MoreExerciseCard: View {
    let module: HomeHeroModule
    let size: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                HomeModuleIconView(
                    icon: module.icon,
                    // Vorher 0.55 → 0.68 (User-Wunsch: Icons hier
                    // etwas größer). Bei size=90 ergibt das ~61 pt
                    // Icon, der Text rückt entsprechend dichter ran.
                    size: size * 0.68,
                    glyphTint: module.accent
                )
                Text(module.title)
                    // +1pt überall AUSSER Karteikarten (User-Wunsch).
                    .font(.system(
                        size: module == .karteikarten ? 11 : 12,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(module.accent.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
