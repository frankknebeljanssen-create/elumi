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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Deine Tools")
                // 17 → 16 (−1 pt): dezenter gegenüber dem Hero-Grid.
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

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
                    // Scannen +1pt (User-Wunsch) — auf 18, Listen
                    // bleibt 17 als Vergleichsanker.
                    .font(.system(
                        size: title == "Scannen" ? 18 : 17,
                        weight: .black,
                        design: .rounded
                    ))
                    // Weiß mit Drop-Shadow → Lesbarkeit auf Accent-BG.
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            // Vertical-Padding 12 → 10, minHeight 68 → 58: Tools-Cards
            // noch etwas niedriger.
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            // Identischer 3-Lagen-Pop-Look wie Hero-Cards. Kein
            // farbiger Außen-Glow — Tiefe nur innerhalb der Card.
            .background(PopCardBackground(accent: accent, cornerRadius: 18))
            .overlay(PopCardBevel(cornerRadius: 18))
            .shadow(color: .black.opacity(0.32), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
