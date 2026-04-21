import SwiftUI

/// **Deine Tools** — zwei Karten nebeneinander am Home-Screen-Ende
/// (Home-Rebuild). Spec: „größer als Karten in ‚Weitere Übungen' /
/// kleiner oder ruhiger als Hero / nebeneinander / sauberer Abstand
/// zum Footer".
///
/// Inhalt: Scannen + Listen. Beide sind „Werkzeuge" (Aktion-Tools),
/// keine Lernmodule — daher die eigene Sektion separat von Hero und
/// Weitere-Übungen.
struct HomeToolsSection: View {
    let onSelectScan: () -> Void
    let onSelectLists: () -> Void

    var body: some View {
        // Spacing 4 pt — **exakt identisch** zum Headline-Cards-Abstand
        // in `HomeMoreExercisesSection`, damit beide Sektionen visuell
        // gleich atmen.
        VStack(alignment: .leading, spacing: 4) {
            Text("Deine Tools")
                // Section-Headline-Hierarchie: 16 pt / .medium /
                // textSecondary — identisch zu „Weitere Übungen".
                // Hebt sich klar von der Hero-Headline ab
                // (22 pt / .black / textPrimary).
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ToolCard(
                    icon: .scan,
                    title: "Scannen",
                    accent: AppTheme.Colors.moduleScan,
                    onTap: onSelectScan
                )

                ToolCard(
                    icon: .listen,
                    title: "Listen",
                    accent: AppTheme.Colors.moduleLists,
                    onTap: onSelectLists
                )
            }
        }
    }
}

private struct ToolCard: View {
    let icon: HomeModuleIcon
    let title: String
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                HomeModuleIconView(
                    icon: icon,
                    size: 58,
                    // Glyph-Tint behält die Original-Modul-Farbe —
                    // das Tool-Icon ist mehrfarbig (Pink/Rosa-Inhalt
                    // im Scan-Rahmen, Foto-Apparat in Cyan-Rosa für
                    // Listen) und liest sich auf dem farbigen BG
                    // weiterhin als wiedererkennbares Symbol.
                    glyphTint: accent
                )
                Text(title)
                    // Beide Tool-Labels gleich groß (Scannen 18 → 17,
                    // Listen bleibt 17). Vereinheitlicht den
                    // Typografie-Rhythmus der Tools-Sektion.
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    // Weiß mit Drop-Shadow → Lesbarkeit auf Accent-BG.
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            // Gradient-Background statt 3-Lagen-Pop-Look (User-Spec):
            // subtiler Verlauf 0.95 → 0.75 vom topLeading nach
            // bottomTrailing, keine harten Flächen-Trennungen mehr.
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.95),
                                accent.opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
