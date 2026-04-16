import SwiftUI

/// Daten-Modell für das Home Progress Board.
///
/// Phase-Home-Redesign: Struktur **final** — die `HomeView` baut dieses
/// Modell aus den existierenden Stores (ProgressStore, @AppStorage, Elumi-
/// Level-Tiers). Der nächste Schritt („Content-Logik" direkt im Anschluss)
/// kann dieses Modell aus einem dedizierten ViewModel / Service befüllen,
/// ohne die View anzufassen.
struct HomeProgressBoardData: Equatable {
    let streakDays: Int
    let level: Int
    /// 0…1 — Anteil bis zum nächsten Level-Up.
    let levelProgress: Double
    let totalXP: Int
    let credits: Int
    /// Optionaler Status-Text unter der Werteleiste („Noch 37 XP bis
    /// Champion"). `nil` → die untere Zeile wird ausgeblendet, die Card
    /// wird kompakter.
    let goalHint: String?
}

/// Horizontale, **eine** kompakte Card — ersetzt die frühere Kombination
/// aus Gamification-Bar + separatem Tagesbonus-Chip.
///
/// Layout (Spec):
///   • obere Zeile: Streak · Level+Progress · XP · Credits
///   • Hairline-Divider
///   • untere Zeile: Goal-Hint („Noch X XP bis …") + Chevron
///
/// Tap → `onTap` (üblich: Navigation in den Progress Hub).
struct HomeProgressBoardCard: View {
    let data: HomeProgressBoardData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    streakSegment
                    segmentDivider
                    levelSegment
                    segmentDivider
                    xpSegment
                    segmentDivider
                    creditsSegment
                }

                if let goalHint = data.goalHint, !goalHint.isEmpty {
                    Rectangle()
                        .fill(AppTheme.Colors.textSecondary.opacity(0.14))
                        .frame(height: 1)

                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.cta)
                            .frame(width: 18)

                        Text(goalHint)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(0.55),
                radius: 8,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Öffnet den vollständigen Fortschrittsbereich.")
    }

    // MARK: - Segments

    private var streakSegment: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "#FF9F40"))
            Text("\(data.streakDays)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(minWidth: 44, alignment: .leading)
    }

    private var levelSegment: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Lv")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .tracking(0.8)
                Text("\(data.level)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
            }
            progressBar(progress: data.levelProgress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.cta,
                                AppTheme.Colors.cta.opacity(0.82)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * progress.clamped01))
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private var xpSegment: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("XP")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("\(data.totalXP)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(minWidth: 40, alignment: .trailing)
    }

    private var creditsSegment: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.Colors.elumiBlue)
            Text("\(data.credits)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(minWidth: 40, alignment: .trailing)
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    // MARK: - Chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.cta.opacity(0.22), lineWidth: 1)
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        var parts: [String] = [
            "Streak \(data.streakDays) Tage",
            "Level \(data.level)",
            "\(data.totalXP) XP",
            "\(data.credits) Credits"
        ]
        if let hint = data.goalHint, !hint.isEmpty {
            parts.append(hint)
        }
        return parts.joined(separator: ", ")
    }
}

private extension Double {
    /// Klammert auf [0, 1] — Schutz vor NaN/Over-/Undershoot aus Config-Werten.
    var clamped01: Double {
        guard isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, self))
    }
}
