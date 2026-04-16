import SwiftUI

// MARK: - Progress Hub Section Header
//
// Kleine typografische Überschrift für Sektionen im Progress Hub. Ersetzt
// das bisherige „jede Gruppe bekommt eine eigene Card"-Muster: die
// Gruppierung passiert über Typografie + Abstand, nicht über verschachtelte
// Card-Chromes. Wiederverwendbar für spätere Home/Session-End-Screens.

/// Ruhige Sektions-Überschrift: Haupttitel + optionaler Sub-Text.
/// Bewusst kein starker Akzent — der Titel soll strukturieren, nicht
/// visuell konkurrieren mit den Werten darunter.
struct ProgressSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .tracking(0.4)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - Progress Hero Card
//
// **Die** visuell dominante Karte des Progress Hub. Konsolidiert Level,
// XP-Stand, Progress-Bar und den Meilenstein-Hinweis („Noch X XP bis …")
// in einem einzigen Block — so erzeugt der Screen oben eine klare
// Dominanz statt mehrerer konkurrierender Karten.
//
// Für spätere Home-Wiederverwendung: dieselbe Datenlogik kann in einer
// kompakten Variante (ohne großen Avatar, kleinere Typo) auf dem Home
// erscheinen — über einen eigenen Initializer oder Wrapper-View.
struct ProgressHeroCard: View {
    let levelTitle: String
    let levelNumber: Int
    let xp: Int
    let progress: Double
    let milestoneTagline: String?
    let snackKind: ElumiSnackKind
    let sectionStyle: AppSectionStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top: Level-Identität + Avatar-Kreis
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aktuelles Level")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .tracking(0.8)

                    Text(levelTitle)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text("Level \(levelNumber)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(sectionStyle.accent)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(sectionStyle.accent.opacity(0.16))
                    ElumiSnackIcon(snackKind, size: 46)
                }
                .frame(width: 72, height: 72)
            }

            // Mitte: XP groß + Progress-Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(xp)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("XP")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                progressBar

                // Footer: Meilenstein-Tagline (merged aus ehemaliger Milestone-Card).
                // Fallback: Max-Level-Aussage statt leere Zeile — Layout bleibt stabil.
                if let milestoneTagline {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text(milestoneTagline)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(sectionStyle.accent)
                        Text("Höchstes Level erreicht — stark!")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(sectionStyle.accent)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: 0.14, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    /// Deutliche Progress-Bar — 12pt hoch, 2-Stopp-Gradient, Capsule-geclipped.
    /// Bewusst ohne Shine-Animation — wir wollen wertige Ruhe.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.secondarySurface)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                sectionStyle.accent.opacity(0.9),
                                AppTheme.Colors.warning.opacity(0.95)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, geo.size.width * max(0, min(1, progress))))
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
    }
}
