import SwiftUI

/// Daten-Modell für das Home Progress Board.
///
/// Phase-Home-Redesign: Struktur **final** — die `HomeView` baut dieses
/// Modell aus den existierenden Stores (ProgressStore, @AppStorage, Elumi-
/// Level-Tiers). Der nächste Schritt („Content-Logik" direkt im Anschluss)
/// kann dieses Modell aus einem dedizierten ViewModel / Service befüllen,
/// ohne die View anzufassen.
///
/// **Credits** bleiben weiterhin Teil des Modells (weil sie in anderen
/// Kontexten, z. B. Progress-Hub, genutzt werden), werden aber im
/// Home-Board bewusst nicht mehr gezeigt — Streak/Level/XP bekommen so
/// mehr Platz.
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
///
/// Credits sind aus dieser Card entfernt — sie sind im Progress-Hub
/// weiterhin sichtbar. Dadurch bekommen die drei verbleibenden Segmente
/// deutlich mehr Raum und die Card wirkt weniger gestapelt.
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // +10 pt höher als die natürliche Content-Höhe (~61pt) — gibt
            // dem Progress-Board oben mehr Gewicht, ohne das Padding zu
            // ändern. Padding-Werte (horizontal 12 / vertical 10) bleiben
            // unangetastet; die Card wächst nur über den minHeight-Frame.
            .frame(maxWidth: .infinity, minHeight: 71)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(0.55),
                radius: 7,
                x: 0,
                y: 2
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
            // „Streak"-Label jetzt **mittig unter der Tageszahl** statt
            // links-bündig — dadurch wirkt der Block als kompakter Tages-
            // Wert (Zahl dominant, Label als zentrierte Caption darunter).
            // Label zusätzlich 3 pt größer (10 → 13), damit die Hierarchie
            // Zahl/Label weniger extrem gestaffelt ist.
            VStack(alignment: .center, spacing: 1) {
                Text("\(data.streakDays) \(data.streakDays == 1 ? "Tag" : "Tage")")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Streak")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                // „Noch xxx XP bis …"-Hint 1 pt größer (10 → 11), damit die
                // Zeile nicht unter der Progress-Bar verschwindet.
                Text(hint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
        // „Gesamt"-Label jetzt **mittig unter der XP-Zahl** statt trailing-
        // bündig — spiegelt das neue Streak-Layout links und macht den
        // rechten Block symmetrisch. Label zusätzlich 2 pt größer (10 →
        // 12), damit „Gesamt" nicht zu fein unter der dominanten Zahl
        // sitzt.
        VStack(alignment: .center, spacing: 1) {
            Text("\(data.totalXP) XP")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("Gesamt")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiPink)
                .tracking(0.4)
        }
        .fixedSize()
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
            .frame(width: 1, height: 28)
    }

    // MARK: - Chrome

    private var cardBackground: some View {
        // Home-Modul-Akzent additiv auf den Surface-Fill — Card liest sich
        // jetzt als Teil des Home-Farbsystems, ohne dass Border/Shadow der
        // Card ihre bewusst weiche Home-Optik verlieren.
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppSectionStyle.home.accent.opacity(AppTheme.CardIntensity.soft))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        var parts: [String] = [
            "Streak \(data.streakDays) \(data.streakDays == 1 ? "Tag" : "Tage")",
            "Level \(data.level)",
            "\(data.totalXP) XP"
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
