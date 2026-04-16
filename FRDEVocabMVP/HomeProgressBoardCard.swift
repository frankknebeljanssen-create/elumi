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

/// Horizontale, **eine** kompakte Card.
///
/// Layout (Spec nach Iteration):
///   • Streak (Flamme + „3 Tage" + „Streak"-Label)
///   • Level (ausgeschrieben „Level 3") mit Progress-Bar darunter
///     → Goal-Hint („Noch 37 XP bis Champion") direkt unter der Bar
///   • XP-Block („663 XP" + „Gesamt"-Label)
///   • Credits-Block (Hexagon + „2" + „Credits"-Label)
///
/// Flacher als vorher — Inhalt steht klarer, Card braucht weniger Höhe.
/// Tap → `onTap` (üblich: Navigation in den Progress Hub).
struct HomeProgressBoardCard: View {
    let data: HomeProgressBoardData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                streakSegment
                segmentDivider
                levelSegment
                segmentDivider
                xpSegment
                segmentDivider
                creditsSegment
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: "#FF9F40"))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(data.streakDays) Tage")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Streak")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .tracking(0.4)
            }
        }
        .fixedSize()
    }

    private var levelSegment: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Level \(data.level)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            progressBar(progress: data.levelProgress)
            if let hint = data.goalHint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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
                                AppTheme.Colors.elumiPink,
                                AppTheme.Colors.elumiPinkDeep
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * progress.clamped01))
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
    }

    private var xpSegment: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(data.totalXP) XP")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("Gesamt")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiPink)
                .tracking(0.4)
        }
        .fixedSize()
    }

    private var creditsSegment: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.Colors.elumiBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(data.credits)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text("Credits")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .tracking(0.4)
            }
        }
        .fixedSize()
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
            .frame(width: 1, height: 34)
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
