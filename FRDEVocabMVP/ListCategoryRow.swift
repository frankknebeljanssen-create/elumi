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
    /// **2026-08-05** — Markiert die Kategorie, in der gerade die aktive
    /// Liste liegt (User-Spec: „dass man schon in diesem Obermenü sieht,
    /// da sind Listen ausgewählt" — ohne diesen Hinweis musste man erst
    /// jede Kategorie einzeln aufklappen, um die angehakte Liste
    /// wiederzufinden). Default `false` — bestehende Call-Sites ohne
    /// aktive Auswahl (z. B. `UnifiedListCategoryPicker`) bleiben
    /// unverändert.
    var isActive: Bool = false

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

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                        .accessibilityLabel("Aktuelle Auswahl liegt hier")
                }

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
            .modifier(ListRowChrome(accent: accent, isActive: isActive))
        }
        .buttonStyle(.plain)
    }
}

/// **2026-08-05** — Geteilte Card-Chrome (Fill + Border) für alle Zeilen
/// im Lernlisten-Screen. Extrahiert, damit „Alle Lernlisten" und „+ Neue
/// Lernliste anlegen" optisch **identisch** zu den drei Kategorie-Zeilen
/// werden (User-Spec: „Alle Lernlisten" wirkte doppelt so groß wie die
/// anderen, die Seite sollte konsistenter/ausgeglichener aussehen) statt
/// die Farben/Radien an vier Stellen einzeln zu pflegen.
struct ListRowChrome: ViewModifier {
    let accent: Color
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent.opacity(isActive ? AppTheme.CardIntensity.selected : AppTheme.CardIntensity.whisper))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.6) : AppTheme.Colors.border, lineWidth: isActive ? 1.5 : 1)
            )
    }
}
