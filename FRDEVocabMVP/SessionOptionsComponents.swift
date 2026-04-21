import SwiftUI

// MARK: - Session Options Components
//
// Wiederverwendbare Bausteine für den modul-spezifischen Options-Bereich
// des Session-Setup. Ziel: selbe visuelle Sprache über alle Module —
// die Buttons/Slider/Toggles sind überall gleich geformt und lassen nur
// die Inhalte pro Modul variieren.
//
// Komponenten:
//   • `SessionOptionGroupCard<Content>` — Titel-Card mit Inhalt
//   • `OptionChipGrid<Option>` — 2-Spalten-Grid aus Auswahl-Chips
//   • `SingleToggleOptionRow` — Row mit Switch (z. B. Speed Round)
//   • `CountSliderCard` — großes Zähler-Display + Slider

// MARK: - OptionGroupCard

/// Container für eine Options-Gruppe. Kleines Header-Label oben,
/// frei gestaltbarer Inhalt darunter. Liegt in einer `SessionCardBackground`.
struct SessionOptionGroupCard<Content: View>: View {
    let title: String
    var iconName: String? = nil
    @ViewBuilder let content: () -> Content

    init(title: String, iconName: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.iconName = iconName
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.cardLabel)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.Colors.cardLabel)
            }

            content()
        }
        // Vertikal etwas enger (18 → 10) — zieht den Chip-Inhalt um
        // ~10 pt nach oben. Gilt aktuell ausschließlich für die
        // Quiz-„Anzahl Fragen"-Card, die als einziger Call-Site diese
        // Komponente verwendet.
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SessionCardBackground())
    }
}

// MARK: - OptionChipGrid

/// 2-spaltiges Grid aus gleich-großen Auswahl-Buttons. Generisch über
/// jede `Hashable` Option — zeigt Titel + optionales Subtitle pro Chip.
///
/// Einheitliche Optik über alle Module:
///   • Radius 20, Höhe 76
///   • Inaktiv: weißer 4%-Fill + 6%-Border
///   • Aktiv: Accent-Tint 20%-Fill + Accent-Border
struct OptionChipGrid<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let subtitle: ((Option) -> String?)?
    let selected: Option
    var accent: Color = AppTheme.Colors.cta
    let onSelect: (Option) -> Void

    init(
        options: [Option],
        title: @escaping (Option) -> String,
        subtitle: ((Option) -> String?)? = nil,
        selected: Option,
        accent: Color = AppTheme.Colors.cta,
        onSelect: @escaping (Option) -> Void
    ) {
        self.options = options
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.accent = accent
        self.onSelect = onSelect
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selected
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        onSelect(option)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(title(option))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .monospacedDigit()
                        if let subtitle, let subText = subtitle(option), !subText.isEmpty {
                            Text(subText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // Nochmals flacher (56 → 48) — Quiz-Fragen-Chips
                    // wirken als reine Auswahl-Buttons, nicht als
                    // dominante Cards. Text bleibt lesbar, Subtitle
                    // rutscht dichter heran.
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected
                                  ? accent.opacity(0.20)
                                  : Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected
                                    ? accent
                                    : Color.white.opacity(0.06),
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - SingleToggleOptionRow

/// Eine einzeilige Option mit Switch, Icon und Beschreibungstext.
/// Nutzung: Speed Round an/aus, Sound an/aus, etc.
struct SingleToggleOptionRow: View {
    let title: String
    let subtitle: String
    let iconName: String
    var accent: Color = AppTheme.Colors.cta
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(accent)
        }
    }
}

// MARK: - CountSliderCard

/// Großer Zähler + Slider. Spec-Variante für „Anzahl der Karten/Fragen".
/// Zählt die aktuelle Zahl in großem Bold, Slider daneben bzw. darunter.
/// Das Card-Chrome liegt außen, ähnlich dem `SessionOptionGroupCard`.
struct CountSliderCard: View {
    let title: String
    @Binding var value: Double
    let minValue: Double
    let maxValue: Double
    let displayValue: String
    var accent: Color = AppTheme.Colors.cta
    var iconName: String? = nil

    var body: some View {
        SessionOptionGroupCard(title: title, iconName: iconName) {
            HStack(alignment: .center, spacing: 18) {
                Text(displayValue)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 72, alignment: .leading)

                Slider(value: $value, in: minValue...maxValue, step: 1)
                    .tint(accent)
            }
        }
    }
}
