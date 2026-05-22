import SwiftUI

/// Wiederverwendbare Kategorie-Zeile für Listen-Picker.
///
/// **Extrahiert (2026-05-22)** 1:1 aus `ListsView.listsCategoryRow`. Die
/// „Meine Listen"-Optik (Catalog-Icon 46pt + Titel 18pt-bold + Count +
/// Chevron) ist ab jetzt die kanonische Kategorie-Card und wird in der
/// Listenpicker-Vereinheitlichung über alle Übungsmodi geteilt.
///
/// `accent` wird hereingereicht (statt `sectionStyle.accent`), damit die
/// Komponente in jedem Modul mit dessen Sektionsfarbe arbeitet.
struct ListCategoryRow: View {
    let title: String
    let iconAsset: String
    let count: Int
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Eigenständige SVG-Icons aus dem Catalog (nicht SF-Symbols).
                // Bounding-Box 46pt — etwas größer als vorher (40), damit die
                // Kategorie-Illustrationen auch in der Row sichtbar „atmen".
                // Stufe 6 Schritt 3 (2026-04-29): nach Set-A-Removal +
                // Imageset-Rename ist der Catalog flach; Asset-Name wird
                // 1:1 verwendet, kein Resolver, kein Suffix.
                Image(iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)

                // Titel +1pt (17 → 18) — besser lesbar auf der gewachsenen
                // Card, bleibt aber klar unterhalb des Alle-Listen-Titels.
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                // Count ebenfalls +1pt (16 → 17) — skaliert mit dem Titel.
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 18)
            // **Polish 2026-05-10** — Cards flacher (~10%): vertical
            // padding 20 → 14, minHeight 78 → 70. Kategorie-Cards
            // sitzen kompakter, der Listen-Screen wirkt insgesamt
            // ruhiger und schneller scannbar.
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent.opacity(AppTheme.CardIntensity.whisper))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
