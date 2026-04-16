import SwiftUI

/// Zustände der Tages-Fokus-Card — treibt Icon, Akzentfarbe und CTA-Label.
///
/// **Wichtig:** Card zeigt immer **nur eine** Aufgabe; mehrere Tagesziele
/// parallel sind explizit nicht vorgesehen. Die Logik, welche Aufgabe das
/// ist, liefert die nachfolgende Runde (Daily-Challenge-System, Streak-
/// Status, Modul-Hint). Die View selbst ist agnostisch.
enum HomeDailyFocusState: Equatable {
    case open          // Noch kein Fortschritt — frisches Tagesziel
    case inProgress    // Teilweise erfüllt
    case done          // Vollständig erfüllt — stolzer Ruhe-Zustand
}

/// Fokus-Datenmodell. Die View kennt nur dieses Modell — so lässt sich die
/// spätere Content-Logik (Auswahl der Aufgabe, Progress-Werte) ohne
/// View-Bruch austauschen.
struct HomeDailyFocusData: Equatable {
    let title: String
    /// Optionaler Subtext („Halte deinen Streak am Leben"). Bei `nil` wird
    /// die Zeile ausgeblendet.
    let subtitle: String?
    /// Optionaler Fortschritts-Chip („7/20" o. ä.). `nil` → kein Chip.
    let progressText: String?
    /// SF-Symbol für den Icon-Badge links — bewusst nicht aus
    /// `HomeModuleIcon` (der Fokus ist kein Modul). Default `target`
    /// (Zielscheibe), passend zur Home-Spec.
    let iconSystemName: String
    let accent: Color
    let state: HomeDailyFocusState
}

/// Home-Fokus-Card — einziger prominenter „heute wichtig"-Impuls oben im
/// Home-Screen. Tap öffnet die Aufgabe (Modul-Start, Progress-Hub,
/// spezifischer Screen — die View weiß es nicht, sie reicht nur `onTap`
/// weiter).
///
/// Label „Dein Fokus heute" wird in `elumiPink` gesetzt — konsistent zur
/// Begrüßung im Header.
struct HomeDailyFocusCard: View {
    let data: HomeDailyFocusData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 11) {
                iconBadge

                VStack(alignment: .leading, spacing: 1) {
                    Text(sectionLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(sectionLabelColor)

                    Text(data.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)

                    if let subtitle = data.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 6)

                trailingAccessory
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            // +10 pt höher als der natürliche Inhalt (~56 pt) — synchron
            // zum Progress-Board, damit die beiden oberen Status-Cards
            // als ein Paar wirken. Padding (h 12 / v 9) bleibt identisch.
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color.opacity(0.5), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }

    // MARK: - Pieces

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(data.accent.opacity(data.state == .done ? 0.22 : 0.16))
            Image(systemName: data.state == .done ? "checkmark" : data.iconSystemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(data.state == .done ? AppTheme.Colors.success : data.accent)
        }
        .frame(width: 38, height: 38)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch data.state {
        case .done:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Geschafft")
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.success)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AppTheme.Colors.success.opacity(0.14))
            .clipShape(Capsule())

        case .inProgress:
            if let progressText = data.progressText, !progressText.isEmpty {
                Text(progressText)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(data.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(data.accent.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                chevronChip
            }

        case .open:
            chevronChip
        }
    }

    private var chevronChip: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
            .padding(8)
            .background(AppTheme.Colors.textSecondary.opacity(0.12))
            .clipShape(Circle())
    }

    private var sectionLabel: String {
        switch data.state {
        case .open, .inProgress: return "Dein Fokus heute"
        case .done:              return "Heute erledigt"
        }
    }

    private var sectionLabelColor: Color {
        data.state == .done ? AppTheme.Colors.success : AppTheme.Colors.elumiPink
    }

    // MARK: - Chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
    }

    // MARK: - Accessibility

    private var accessibilityLabelText: String {
        var parts: [String] = ["Dein Fokus heute", data.title]
        if let subtitle = data.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if let progressText = data.progressText, !progressText.isEmpty { parts.append(progressText) }
        if data.state == .done { parts.append("Erledigt") }
        return parts.joined(separator: ", ")
    }
}
