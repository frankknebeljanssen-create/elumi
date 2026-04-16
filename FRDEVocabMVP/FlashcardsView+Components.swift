import SwiftUI
import UIKit

extension FlashcardsView {
    func flashcardFace(text: String, isAnswerSide: Bool, languageCode: String, wordClassLabel: String? = nil) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isAnswerSide ? AppTheme.Colors.secondarySurface : AppTheme.Colors.surface)
            .overlay(
                // Promt-Seite deutlich farbig hinterlegen, damit die Karteikarte
                // gegenüber den darunter liegenden Action-Buttons dominiert.
                // Answer-Seite bleibt dezenter grün.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isAnswerSide ? AppTheme.Colors.success.opacity(0.18) : sectionStyle.accent.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isAnswerSide ? AppTheme.Colors.success.opacity(0.5) : sectionStyle.accent.opacity(0.55),
                        lineWidth: 1.5
                    )
            )
            .overlay(alignment: .center) {
                VStack(spacing: 6) {
                    Text(text)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(4)
                        .minimumScaleFactor(0.55)
                        .multilineTextAlignment(.center)

                    if let wordClassLabel, !wordClassLabel.isEmpty {
                        Text("(\(wordClassLabel))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, isAnswerSide ? 14 : 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: flashcardFaceHeight)
            .shadow(color: sectionStyle.accent.opacity(isAnswerSide ? 0 : 0.18), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(isAnswerSide ? 0.06 : 0.12), radius: 16, x: 0, y: 8)
    }

    func selectionChip(title: String, value: String) -> some View {
        CompactSelectionChip(style: sectionStyle, title: title, value: value)
    }

    /// Kompakter Header für Karteikarten-Screens (Session UND Setup):
    /// links der kleine „< Zurück"-Button, daneben „Karteikarten" als zentrierter
    /// Titel. Ersetzt die alte `ScreenHeaderCard` + den großen „Zurück"-Button.
    /// `onBack` ist die jeweilige Aktion (Session → Setup; Setup → Home).
    func flashcardCompactHeader(onBack: @escaping () -> Void) -> some View {
        ZStack {
            Text("Karteikarten")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                AppBackButton(action: onBack, tint: sectionStyle.accent)

                Spacer()
            }
        }
        .padding(.horizontal, flashcardSessionCardInset)
        .padding(.top, 4)
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }

    /// Header für die laufende Karteikarten-Übung — Zurück führt zur
    /// Listen-Auswahl-/Setup-Card (nicht ganz raus zu Home).
    var flashcardSessionHeader: some View {
        flashcardCompactHeader(onBack: returnToFlashcardSetup)
    }

    /// Header für den Karteikarten-Setup-Screen — Zurück verlässt die
    /// Karteikarten-View komplett (zurück zur vorherigen Navigationsebene).
    var flashcardSetupHeader: some View {
        flashcardCompactHeader(onBack: handleBackNavigation)
    }

    /// Drei-Spalten-Statistik oben im Session-Screen — ersetzt den alten
    /// progressText + Fortschrittsbalken. Jede Säule zeigt Mini-Stapel + Label
    /// + Zahl. Buckets sind disjunkt:
    /// • „Kann ich": gemasterte Karten (raus aus dem Stapel)
    /// • „Nochmal": Karten im Stapel, die mind. 1× falsch waren
    /// • „Offen": Karten im Stapel, die noch nie falsch waren (Rest)
    var flashcardStatsRow: some View {
        let mastered = sessionStore.masteredCount
        let nochmal = sessionStore.wrongAnsweredCardCount
        let total = sessionStore.totalCount
        let offen = max(0, total - mastered - nochmal)

        // 3-Spalten-Grid mit Mini-Card-Tiles (analog zum Stat-Trio im Setup).
        // Klare Farblogik: Grün = geschafft, Blau = offen, Rot = nochmal.
        return HStack(spacing: 8) {
            flashcardStatTile(count: mastered, label: "Kann ich", color: AppTheme.Colors.success)
            flashcardStatTile(count: offen, label: "Offen", color: sectionStyle.accent)
            flashcardStatTile(count: nochmal, label: "Nochmal", color: AppTheme.Colors.error)
        }
        .frame(maxWidth: .infinity)
    }

    private func flashcardStatTile(count: Int, label: String, color: Color) -> some View {
        // Stapel-Höhe wächst mit der Karten-Anzahl — wenig Karten = dünner
        // Stapel, viele Karten = dickerer Stapel. Quadratwurzel-Mapping
        // damit der Stapel bei großen Listen nicht „explodiert".
        let layerCount = Self.stackLayerCount(for: count)

        // Mini-Card-Tile im Setup-Trio-Look: BG #1A2A40, Border #243B55,
        // Radius 10. Mini-Stapel + Label (in Bucket-Farbe) + Zahl in weiß.
        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: Self.maxStackHeight)
                ForEach(0..<layerCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(0.45 + Double(i) * 0.08))
                        .frame(width: 38 - CGFloat(i) * 2, height: 5)
                        .offset(y: -CGFloat(i) * 3)
                }
            }

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#1A2A40"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: "#243B55"), lineWidth: 1)
        )
    }

    /// Mapping Karten-Anzahl → sichtbare Stapel-Schichten. Quadratwurzel-Skala
    /// sorgt dafür, dass kleine Unterschiede bei wenigen Karten gut sichtbar
    /// sind (4 vs. 10 Karten klar unterscheidbar) und große Stapel nicht
    /// unbegrenzt wachsen.
    private static func stackLayerCount(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        // sqrt(count) gerundet, mit Mindeststärke 1 und Maximum 8.
        let raw = Int((Double(count).squareRoot()).rounded())
        return max(1, min(8, raw))
    }

    /// Reservierte Höhe für den größten möglichen Stapel (8 Schichten à 3pt
    /// Offset + 5pt Capsule-Höhe). Wird als Spacer in jedem Tile gesetzt,
    /// damit Label und Zahl vertikal exakt auf einer Linie stehen.
    private static let maxStackHeight: CGFloat = 5 + (8 - 1) * 3
}
