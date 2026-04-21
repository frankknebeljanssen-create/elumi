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
            // −5 pt Höhe gegenüber vorher (User-Request): vertikales
            // Padding 10 → 8 und minHeight 76 → 71. Content (Streak-
            // Icon, Level-Wert, XP-Balken) bleibt; nur die Luft oben/
            // unten schrumpft. Synchron zur `HomeStatusCard`, damit
            // beide Cards weiterhin dieselbe Höhe haben.
            .padding(.vertical, 8)
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
        // Parität zum Icon-Layout der Status-Card darüber („Heute"):
        // Flame-Glyph auf 17 pt (= sparkles-Glyph-Größe), in einen 38×38-
        // Icon-Badge gesetzt und linksbündig mit der VStack nebenan —
        // dadurch landen „X Tage" / „Streak" auf **derselben X-Position**
        // wie „Heute" / „X Aktionen" in der Status-Card. Beide Cards
        // lesen sich jetzt als Paar mit konsistenter linker Kante.
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FF9F40").opacity(0.16))
                Image(systemName: "flame.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "#FF9F40"))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                // Zahl + „Tag/Tage" getrennt gerendert, damit die
                // Gewichtung feiner steuerbar ist (User-Wunsch Pokal-
                // Tab: Streak-Zahl +2 pt, Tag/Tage +1 pt gegenüber der
                // vorigen Baseline). Baseline-Alignment bindet beide
                // an derselben Grundlinie, damit die Zahl gut lesbar
                // dominieren darf, ohne dass „Tage" visuell abhängt.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(data.streakDays)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .monospacedDigit()
                    Text(data.streakDays == 1 ? "Tag" : "Tage")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
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
        // „Noch X XP bis …"-Hint entfernt — durch den linksbündigen Streak-
        // Block wird der verfügbare Platz ohnehin knapper, und der
        // Goal-Hint wiederholt sich mit dem Progress-Hub. „Level X" auf
        // 15 pt (+1 pt) angehoben, damit das verbleibende Label nicht
        // gegenüber „X Tage" (15 pt) und „X XP" (15 pt) zurückfällt.
        VStack(alignment: .leading, spacing: 5) {
            Text("Level \(data.level)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
        // User-Request: „Gesamt"-Label weg. Stattdessen XP-Zahl und „XP"-
        // Label auf **zwei Zeilen** stapeln, Font +2 pt — die XP-Zahl
        // wirkt dadurch prominenter, das Unit-Label „XP" ersetzt das
        // frühere „Gesamt" als zweite Zeile.
        VStack(alignment: .center, spacing: 1) {
            Text("\(data.totalXP)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("XP")
                .font(.system(size: 15, weight: .bold, design: .rounded))
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
