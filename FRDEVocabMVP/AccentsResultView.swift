import SwiftUI

/// **DEPRECATED** (seit Akzente-Summary-Harmonisierung) — Akzente nutzt
/// jetzt die zentrale `SessionSummaryView` (siehe `AccentsEntryView`
/// Zeile ~165 im `.fullScreenCover(item: $showingResult)`-Branch).
/// Diese View ist im aktuellen Flow **nicht** mehr instanziiert und
/// bleibt nur als Referenz/Archiv bestehen — gleicher Summary-Stil wie
/// Training/Quiz/Flashcards/Verbformen läuft jetzt durch die geteilte
/// View. Kann bei nächster Cleanup-Runde entfernt werden.
///
/// Result-Screen nach einer abgeschlossenen Akzent-Session (Üben / Speed Round).
///
/// Zeigt die Gesamtleistung + einen kompakten Breakdown pro Akzenttyp.
/// MVP-Struktur: groß die Kennzahl oben, darunter Badges, unten Buttons.
struct AccentsResultView: View {
    let mode: AccentMode
    let correct: Int
    let total: Int
    let breakdown: [(type: AccentType, correct: Int, total: Int)]
    /// V3: Audio-vs-visuelle Trefferquote — wenn Audio-Aufgaben in der
    /// Session waren, zeigt der Result-Screen einen Split-Hinweis.
    let audioVisualSplit: (audioCorrect: Int, audioTotal: Int, visualCorrect: Int, visualTotal: Int)
    let accentColor: Color
    let onRetry: () -> Void
    let onClose: () -> Void
    /// System-Chrome-Requisiten: AppBottomBar wird in jedem Akzent-
    /// Screen gezeigt (keine Ausnahme).
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let onHome: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        summaryCard
                        if !breakdown.isEmpty {
                            strongestWeakestCard
                            breakdownCard
                        }
                        if shouldShowAudioSplit {
                            audioVisualSplitCard
                        }
                        if !problemAccents.isEmpty {
                            nextRoundHintCard
                        }
                        encouragementText
                    }
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }

                footer

                // Systemkonformer Bottom-Bar — immer sichtbar.
                AppBottomBar(
                    feedbackPlayer: feedbackPlayer,
                    onHome: onHome,
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: onSettings
                )
            }
        }
    }

    // MARK: - Header — systemkonform: Back-Chevron + „Akzente" mittig

    private var header: some View {
        AccentsSessionHeader(onBack: onClose)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Session abgeschlossen")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("\(correct) von \(total) richtig")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            // Prozent-Anzeige
            Text("\(percentage)%")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(accentColor.opacity(0.25), lineWidth: 1.5)
        )
    }

    private var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(correct) / Double(total) * 100).rounded())
    }

    // MARK: - Strongest / Weakest

    /// Ranking der Akzenttypen nach Trefferquote. Nur Typen mit ≥ 1 Aufgabe.
    private var rankedBreakdown: [(type: AccentType, ratio: Double, correct: Int, total: Int)] {
        breakdown
            .filter { $0.total > 0 }
            .map { (type: $0.type, ratio: Double($0.correct) / Double($0.total), correct: $0.correct, total: $0.total) }
            .sorted { $0.ratio > $1.ratio }
    }

    /// Nur sinnvoll, wenn mindestens 2 Typen mit Abweichung im Ergebnis —
    /// sonst sagt „stärkster" / „schwächster" nichts aus.
    /// „Stark bei" + „Noch üben" — **jede Zeile volle Breite**, damit die
    /// beiden Hinweise genauso breit wie alle anderen Cards im Screen
    /// wirken (Summary, Breakdown, Audio-Split …).
    @ViewBuilder
    private var strongestWeakestCard: some View {
        let ranked = rankedBreakdown
        if ranked.count >= 2, let best = ranked.first, let worst = ranked.last, best.ratio != worst.ratio {
            VStack(spacing: AppTheme.Spacing.sm) {
                strengthRow(label: "Stark bei", accent: best.type, tone: .success)
                strengthRow(label: "Noch üben", accent: worst.type, tone: .warning)
            }
        }
    }

    private enum Tone { case success, warning }

    /// Eine Hinweis-Zeile, die die **volle Breite** einnimmt — analog zu
    /// summaryCard / breakdownCard.
    private func strengthRow(label: String, accent: AccentType, tone: Tone) -> some View {
        let color: Color = tone == .success ? AppTheme.Colors.success : AppTheme.Colors.warning
        return HStack(spacing: 12) {
            Text(accent.representativeGlyph)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Text(accent.germanLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Breakdown

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Nach Akzenttyp")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(Array(breakdown.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.type.representativeGlyph)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(accentColor)
                            .frame(width: 30)

                        Text(entry.type.germanLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Spacer()

                        Text("\(entry.correct) / \(entry.total)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(entry.correct == entry.total ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
    }

    // MARK: - V3: Audio-vs-Visuell-Split

    /// Nur anzeigen, wenn mindestens eine Audio-**und** eine visuelle
    /// Aufgabe in der Session war — andernfalls sagt der Split nichts aus.
    private var shouldShowAudioSplit: Bool {
        audioVisualSplit.audioTotal > 0 && audioVisualSplit.visualTotal > 0
    }

    private var audioVisualSplitCard: some View {
        let aC = audioVisualSplit.audioCorrect
        let aT = audioVisualSplit.audioTotal
        let vC = audioVisualSplit.visualCorrect
        let vT = audioVisualSplit.visualTotal
        let aRatio = aT > 0 ? Double(aC) / Double(aT) : 0
        let vRatio = vT > 0 ? Double(vC) / Double(vT) : 0
        let hint: String = {
            let delta = vRatio - aRatio
            if delta > 0.2  { return "Visuell stark — Audio ruhig weiter üben." }
            if delta < -0.2 { return "Audio sitzt — visuelle Stellen noch schärfen." }
            return "Audio und visuell sind ausgewogen."
        }()

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Audio vs. Visuell")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .textCase(.uppercase)

            HStack {
                splitRow(icon: "speaker.wave.2.fill", label: "Audio", correct: aC, total: aT)
                splitRow(icon: "eye.fill", label: "Visuell", correct: vC, total: vT)
            }

            Text(hint)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .padding(.top, 4)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(.accents, intensity: AppTheme.CardIntensity.soft)
    }

    private func splitRow(icon: String, label: String, correct: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text("\(correct) / \(total)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - V3: Problem-Akzente für nächste Runde

    /// Alle Akzenttypen, bei denen die Trefferquote unter 60 % liegt —
    /// Kandidaten für den Next-Round-Fokus. Sortiert aufsteigend
    /// (schwächste zuerst).
    private var problemAccents: [(type: AccentType, ratio: Double)] {
        breakdown.compactMap { entry -> (AccentType, Double)? in
            guard entry.total > 0 else { return nil }
            let ratio = Double(entry.correct) / Double(entry.total)
            guard ratio < 0.6 else { return nil }
            return (entry.type, ratio)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(2)
        .map { ($0.0, $0.1) }
    }

    private var nextRoundHintCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accentColor)
                Text("Für die nächste Runde")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)
            }

            Text(nextRoundCopy)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Die nächste Session legt automatisch mehr Fokus auf diese Akzente.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(.accents, intensity: AppTheme.CardIntensity.soft)
    }

    /// „è und ê noch einmal üben" / „ç noch einmal üben" — adaptiv aus
    /// den schwächsten Typen der Session zusammengesetzt.
    private var nextRoundCopy: String {
        let glyphs = problemAccents.map { $0.type.representativeGlyph }
        guard !glyphs.isEmpty else { return "" }
        if glyphs.count == 1 {
            return "\(glyphs[0]) noch einmal üben."
        }
        return "\(glyphs.joined(separator: " und ")) noch einmal üben."
    }

    // MARK: - Encouragement

    /// Kleine motivierende Zeile — orientiert sich am Ergebnis.
    private var encouragementText: some View {
        Text(encouragementCopy)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var encouragementCopy: String {
        if total == 0 { return "" }
        let ratio = Double(correct) / Double(total)
        if ratio >= 0.9 { return "Stark! Die Akzente sitzen." }
        if ratio >= 0.7 { return "Solide Runde — dranbleiben!" }
        if ratio >= 0.5 { return "Guter Anfang. Noch eine Runde?" }
        return "Noch ein bisschen üben — jede Runde hilft."
    }

    // MARK: - Footer — System-CTAs

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button("Nochmal üben", action: onRetry)
                .buttonStyle(AppPrimaryButtonStyle())
            Button("Fertig", action: onClose)
                .buttonStyle(AppSecondaryButtonStyle(tint: accentColor))
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}
