// AppLernjahrPill.swift
// **2026-05-06** — neuer Component im Zuge des „Lernjahr-Pill"-Sweeps
// (B2). Vorher war der Lernjahr-Range an 4 Call-Sites in der „Ausgewählte
// Listen"-Card als Plain-Text-Subtitle eingebettet:
//
//   „X Listen · LJ 1-3 · Y Einträge"
//
// Damit war der Filter zwar sichtbar, aber nicht greifbar — ein 13-Jähriger
// musste über Settings → Lernjahr-Auswahl gehen, um den Range zu ändern.
// Mit der Pill ist der „LJ 1-N"-Teil ein eigenständiger, getappter
// Button geworden, der einen Mini-Picker (5 Single-Select-Chips für
// 1, 2, 3, 4, 5) öffnet. Persistenz schreibt direkt auf
// `appLernjahrMaxKey` — derselbe Key, den der Resolver liest.
//
// Render-Eligibility: dieselbe Logik wie der bisherige Plain-Text-Pfad
// (`VocabularyListSelectionResolver.lernjahrRangeLabel(...)` !=  nil) —
// also nur sichtbar, wenn (a) mindestens eine selektierte Liste hierar-
// chisch ist (cumulativeChildren) UND (b) `lernjahrMax` einen Filter
// signalisiert (1...4). Bei `lernjahrMax == 5` ist der Filter „Alle
// Lernjahre" → Pill verschwindet konsistent zum aktuellen UX-Verhalten.
// Recovery „Alle → Filter" geht weiterhin über Settings (kein Mini-
// Picker-Eintrag „kein Filter", weil Pill dann unsichtbar wäre — kein
// sinnvoller Re-Entry-Pfad innerhalb des Setup-Screens).
//
// Verschachtelte Buttons: drei der vier Call-Sites rendern die Subtitle-
// Zeile innerhalb eines äußeren Tap-Buttons (List-Picker-Open). Die Pill
// als innerer Button funktioniert in SwiftUI seit iOS 14 problemlos
// (innerer Button gewinnt Hit-Test-Priorität auf seinem Frame).

import SwiftUI

/// Tappbarer Pill/Chip in einer Subtitle-Zeile, der den aktuellen
/// `lernjahrMax`-Range darstellt. Tap öffnet ein kompaktes Sheet mit
/// 5 Single-Select-Chips (1, 2, 3, 4, 5). Auswahl persistiert sofort
/// auf `appLernjahrMaxKey`; Sheet schließt automatisch nach Tap.
///
/// **Render-Voraussetzung** — Caller-Verantwortung: die Pill nur dann
/// instanziieren, wenn `VocabularyListSelectionResolver.lernjahrRangeLabel(
/// forSelectedLists:)` einen non-nil Wert zurückliefert. Wir wiederholen
/// diese Eligibility-Logik nicht intern — der Caller hat den Listen-
/// Kontext sowieso schon, und der Render-Aufruf läuft im Subtitle-
/// Layout-Pfad der jeweiligen Listen-Card.
///
/// Tinting: Caller übergibt einen Akzent (`tint`), den die Pill für
/// Background-Fill (.opacity 0.18) und Stroke (.opacity 0.55) nutzt.
/// Vorder-Text bleibt `AppTheme.Colors.textPrimary`, damit der Filter-
/// Hint trotz farbigem Hintergrund klar lesbar ist.
struct AppLernjahrPill: View {
    /// Aktueller Range-Text — das, was vorher als Plain-Text gerendert
    /// wurde (Format: „LJ 1-N"). Caller liefert ihn als String, weil er
    /// schon den Resolver-Call durchgeführt hat — wir vermeiden den
    /// doppelten Lookup.
    let label: String

    /// Akzent-Farbe für Background + Stroke. Pro-Modul abgestimmt
    /// (z. B. Quiz-Pink, Karteikarten-Blue, Training-Vokabeln-DarkBlue).
    let tint: Color

    /// Sheet-Open-State — lokal, weil der Caller keine Sheet-Verwaltung
    /// für eine Mini-Auswahl braucht. Picker-Schluss persistiert direkt.
    @State private var showPicker: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPicker = true
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            LernjahrMiniPickerSheet(tint: tint)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .accessibilityLabel(Text("Lernjahr-Filter \(label)"))
        .accessibilityHint(Text("Tippen, um den Lernjahr-Bereich zu ändern."))
    }
}

/// Kompaktes Sheet mit 5 Chips (1, 2, 3, 4, 5) für die Lernjahr-Wahl.
/// Single-Select; Tap auf einen Chip persistiert direkt nach
/// `UserDefaults` (Key: `appLernjahrMaxKey`) und schließt das Sheet.
///
/// Ein Tap auf „5" entspricht „kein Filter" (Resolver liefert dann
/// `nil` für `lernjahrRangeLabel`) — die Pill im Caller verschwindet
/// dadurch. Recovery-Pfad ist dann Settings (analog zum bisherigen
/// Verhalten — siehe Doc-Block oben in `AppLernjahrPill`).
///
/// Dimensionen klein (Sheet-Detent 220pt), damit das Sheet nicht den
/// halben Screen frisst — der Picker ist eine sub-modale Mini-Wahl,
/// kein Setup-Screen.
struct LernjahrMiniPickerSheet: View {
    let tint: Color

    /// Lokaler Mirror für die `@AppStorage`-Wahl, damit der Tap auf
    /// einen Chip eine sichtbare Selected-Animation triggert, bevor das
    /// Sheet schließt.
    @AppStorage(appLernjahrMaxKey) private var lernjahrMax: Int = 0

    @Environment(\.dismiss) private var dismiss

    /// Verfügbare Lernjahre. Spec literal: 5 Chips. „5" ist der Off-
    /// State (= kein Filter), die ersten vier sind echte kumulative
    /// Filter (LJ 1-1, 1-2, 1-3, 1-4).
    private static let years: [Int] = [1, 2, 3, 4, 5]

    var body: some View {
        VStack(spacing: 16) {
            Text("Lernjahr-Bereich")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.top, 4)

            // 5 Chips horizontal — Tap setzt den Wert und schließt.
            // **Layout-Hinweis**: gleichmäßig verteilt, damit auch auf
            // schmalen Geräten (iPhone SE) jeder Chip mindestens
            // 44pt Tap-Target erreicht.
            HStack(spacing: 8) {
                ForEach(Self.years, id: \.self) { year in
                    yearChip(year)
                }
            }
            .padding(.horizontal, 16)

            Text("LJ 1-1 = nur Lernjahr 1, LJ 1-4 = Lernjahre 1 bis 4. Bei 5 ist kein Filter aktiv.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }

    /// Ein einzelner Chip. Selected-State liest `lernjahrMax`:
    ///   • 0 oder nil-äquivalent → Chip „5" gilt als selected
    ///     (= kein Filter)
    ///   • 1...4 → der entsprechende Chip ist selected
    ///   • 5     → Chip „5" ist selected (kein Filter, explizit)
    private func yearChip(_ year: Int) -> some View {
        // **Selected-Logik**: `lernjahrMax == 0` (App-Default = nie
        // gewählt) wird hier wie 5 behandelt — der „5"-Chip leuchtet,
        // damit der User sieht „aktuell kein Filter aktiv".
        let effectiveCurrent = (lernjahrMax == 0) ? 5 : lernjahrMax
        let isSelected = (effectiveCurrent == year)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // **Persist via @AppStorage**: Setter triggert UserDefaults-
            // Write + benachrichtigt alle @AppStorage-Reader sofort
            // (inkl. der Pill-Beschriftung, die nach Re-Open des
            // Setup-Screens aktualisiert ist).
            lernjahrMax = year
            // Kurze Verzögerung, damit der Selected-Highlight kurz
            // sichtbar ist, bevor das Sheet schließt — sonst „blinkt"
            // der Tap weg, ohne Bestätigungsfeedback.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                dismiss()
            }
        } label: {
            Text("\(year)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(
                    isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary
                )
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.25) : AppTheme.Colors.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? tint : Color.clear, lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(year == 5 ? "Alle Lernjahre" : "Lernjahre 1 bis \(year)"))
    }
}
