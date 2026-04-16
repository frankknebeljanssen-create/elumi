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
    /// SF-Symbol für den Icon-Badge links. Bewusst nicht aus
    /// `HomeModuleIcon` — der Fokus ist kein Modul, sondern eine Aufgabe.
    let iconSystemName: String
    let accent: Color
    let state: HomeDailyFocusState
}

/// Home-Fokus-Card — einziger prominenter „heute wichtig"-Impuls oben im
/// Home-Screen. Tap öffnet die Aufgabe (Modul-Start, Progress-Hub,
/// spezifischer Screen — die View weiß es nicht, sie reicht nur `onTap`
/// weiter).
struct HomeDailyFocusCard: View {
    let data: HomeDailyFocusData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                iconBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(sectionLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(data.accent.opacity(0.9))

                    Text(data.title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)

                    if let subtitle = data.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                trailingAccessory
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color.opacity(0.5), radius: 8, x: 0, y: 3)
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(data.state == .done ? AppTheme.Colors.success : data.accent)
        }
        .frame(width: 48, height: 48)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch data.state {
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Geschafft")
                    .font(.system(size: 12, weight: .black, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.Colors.success.opacity(0.14))
            .clipShape(Capsule())

        case .inProgress:
            if let progressText = data.progressText, !progressText.isEmpty {
                Text(progressText)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(data.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(data.accent.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
            }

        case .open:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
        }
    }

    private var sectionLabel: String {
        switch data.state {
        case .open:       return "DEIN FOKUS HEUTE"
        case .inProgress: return "DEIN FOKUS HEUTE"
        case .done:       return "HEUTE ERLEDIGT"
        }
    }

    // MARK: - Chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(data.accent.opacity(data.state == .done ? 0.04 : 0.06))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                data.state == .done
                    ? AppTheme.Colors.success.opacity(0.28)
                    : data.accent.opacity(0.22),
                lineWidth: 1
            )
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
