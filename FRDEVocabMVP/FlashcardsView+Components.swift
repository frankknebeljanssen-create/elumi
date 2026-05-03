import SwiftUI
import UIKit

extension FlashcardsView {
    /// **Karteikarten-Design Phase 8** (User-Spec 2026-04-22):
    /// Fixed-size Karte 260×168 pt, cornerRadius 6, farblich klar
    /// differenzierte Front/Back-Seiten mit pink/teal-Stripe und
    /// Streak-Row rechts oben (5 Dots, Amber-Filling aus
    /// `consecutiveCorrect` im SM-2-Datenmodell).
    ///
    /// Bei Streak ≥ 5 wird die Karte „mastered" → Stripe wechselt auf
    /// beiden Seiten auf Amber (#FFD166). Streak > 5 wird auf 5
    /// geclampt (Render-Only-Cap; das Datenmodell kann weiter zählen).
    func flashcardFace(
        text: String,
        isAnswerSide: Bool,
        languageCode: String,
        wordClassLabel: String? = nil,
        cardIndex: Int,
        totalCount: Int,
        streak: Int,
        streakTarget: Int,
        hidesCardCounter: Bool = false
    ) -> some View {
        // **User-Revision 2026-04-22**: Streak-Dots richten sich nach der
        // Mastery-Threshold („Karte fällt raus nach N richtigen Antworten").
        // Threshold 1 → 1 Dot, 2 → 2 Dots, 3 → 3 Dots, 4 → 4 Dots. Das
        // Spielgefühl bleibt stimmig: man sieht die „Lebens"-Leiste genau
        // so lang wie sie auch tatsächlich ist.
        let clampedTarget = max(1, min(4, streakTarget))
        let clampedStreak = max(0, min(clampedTarget, streak))
        let isMastered = clampedStreak >= clampedTarget

        // User-Spec-Palette (exakt aus dem Briefing)
        let borderColor = Color(hex: "#1E4060")
        let bgFront = Color(hex: "#0F2D48")
        let bgBack = Color(hex: "#0A2035")
        let stripePink = Color(hex: "#FF4D80")
        let stripeTeal = Color(hex: "#2EC4A9")
        let stripeAmber = Color(hex: "#FFD166")
        let dotFilled = Color(hex: "#FFD166")
        let dotEmpty = Color.white.opacity(0.12)

        let bg = isAnswerSide ? bgBack : bgFront
        // Stripe: im Mastered-Zustand auf beiden Seiten Amber, sonst
        // Front = Pink, Back = Teal.
        let stripeColor = isMastered ? stripeAmber : (isAnswerSide ? stripeTeal : stripePink)
        // Tag-Farbe spiegelt die Seiten-Identität, auch im Mastered-
        // Zustand (damit FR/DE optisch unterscheidbar bleibt).
        let tagColor = isAnswerSide ? stripeTeal : stripePink

        // Sprach-Label aus languageCode ableiten — „Français" bei fr*,
        // „Deutsch" bei de*, sonst Uppercase-Code.
        let languageLabel: String = {
            let code = languageCode.lowercased()
            if code.hasPrefix("fr") { return "Français" }
            if code.hasPrefix("de") { return "Deutsch" }
            if code.hasPrefix("en") { return "English" }
            return code.uppercased()
        }()
        // **Block 3.7.3 (2026-05-03)** — Im Chain-Modus
        // (`hidesCardCounter = true`) entfällt der „Karte X / Y"-Suffix
        // auf der Front-Seite. Chain-Header zeigt eh „ÜBUNG X VON Y"
        // — der Per-Card-Counter ist redundant und nimmt visuelles
        // Gewicht im Tag-Slot ein.
        let frontTagText: String = hidesCardCounter
            ? languageLabel
            : "\(languageLabel) · Karte \(cardIndex) / \(totalCount)"
        let tagText: String = isAnswerSide
            ? "\(languageLabel) · Antwort"
            : frontTagText

        return ZStack(alignment: .topLeading) {
            // Hintergrund + Border
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor, lineWidth: 1.5)
                )

            // 4 pt Top-Stripe, durch denselben Corner-Radius geclippt,
            // damit er bündig in die runden Ecken läuft.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(stripeColor)
                    .frame(height: 4)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Content-Stack: Tag-Zeile oben, Vokabel zentriert,
            // Genus nur auf der Antwort-Seite.
            VStack(spacing: 0) {
                // Top row — Tag links, Streak-Block rechts
                HStack(alignment: .top, spacing: 8) {
                    Text(tagText.uppercased())
                        // **User-Revision**: Sprachart-Tag links +1 pt (8 → 9).
                        // Tracking proportional auf 9 × 0.12em ≈ 1.08 pt.
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.08)
                        .foregroundStyle(tagColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    // Streak-Block: „STREAK" Label + Dots
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("STREAK")
                            // **User-Revision 2026-04-22**: STREAK-Label
                            // +1 pt (9 → 10). Tracking 10 × 0.12em ≈ 1.2 pt.
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.5))
                        HStack(spacing: 4) {
                            ForEach(0..<clampedTarget, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(i < clampedStreak ? dotFilled : dotEmpty)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                // **User-Revision**: mehr Luft oben & unten auf der Karte
                // (12 → 16 pt). Bottom-Padding sitzt unten auf dem VStack,
                // damit Vokabel/Genus nicht zu nah an der Kartenunterkante
                // kleben.
                .padding(.top, 16)

                Spacer(minLength: 6)

                // Vokabel — zentriert, 26pt semibold rounded, white.
                VStack(spacing: 4) {
                    Text(text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.55)
                        .multilineTextAlignment(.center)

                    // Genus nur auf der Antwort-Seite.
                    if isAnswerSide, let wordClassLabel, !wordClassLabel.isEmpty {
                        Text(wordClassLabel)
                            .font(.system(size: 10, weight: .regular))
                            .italic()
                            .foregroundStyle(Color.white.opacity(0.30))
                    }
                }
                .padding(.horizontal, 14)

                Spacer(minLength: 0)
            }
            // **User-Revision**: expliziter Bottom-Inset auf dem
            // Content-VStack — hält Vokabel/Genus von der Kartenunter-
            // kante weg. Oben wird das Gegenstück via `.padding(.top, 16)`
            // auf der Tag-Zeile erreicht.
            .padding(.bottom, 14)
        }
        // **Design-Phase 8.1 → 8.4 (User-Revision „etwas größer")**:
        // Fix-Größe von 300×194 → 320×210 pt. Ratio bleibt nahe an
        // 1.524 (= ursprünglich 1.548) — eine 6,5 %-Steigerung sowohl
        // in Breite als auch Höhe. `flashcardFaceHeight` muss parallel
        // angepasst werden (FlashcardsView.swift).
        .frame(width: 320, height: 210)
        // Sanfter Schatten — Mastered-Karten kriegen einen leicht
        // wärmeren Ton, damit der Sieg auch unterbewusst ankommt.
        .shadow(
            color: isMastered ? stripeAmber.opacity(0.22) : .black.opacity(0.25),
            radius: 10,
            x: 0,
            y: 6
        )
    }

    func selectionChip(title: String, value: String) -> some View {
        CompactSelectionChip(style: sectionStyle, title: title, value: value)
    }

    /// Kompakter Header für Karteikarten-Screens (Session UND Setup):
    /// links der kleine „< Zurück"-Button, daneben „Karteikarten" als zentrierter
    /// Titel. Ersetzt die alte `ScreenHeaderCard` + den großen „Zurück"-Button.
    /// `onBack` ist die jeweilige Aktion (Session → Setup; Setup → Home).
    /// `showsModuleCard`: wenn `true`, rendert der Header zusätzlich eine
    /// farbige `ModuleHeaderCard` mit Icon — für Setup-Screens (visuelle
    /// Klammer Home → Modul). Während der aktiven Session bleibt der
    /// Header kompakt (Text-only), damit der Lerninhalt dominiert.
    func flashcardCompactHeader(
        onBack: @escaping () -> Void,
        showsModuleCard: Bool = false
    ) -> some View {
        Group {
            if showsModuleCard {
                // Setup-Screen: farbige ModuleHeaderCard mit integriertem
                // Back-Chevron + FR-DE-Toggle rechts oben — zentrales
                // Muster, identisch zu Quiz/Training/Vokabeln.
                ModuleHeaderCard(
                    icon: .karteikarten,
                    title: "Karteikarten",
                    accent: sectionStyle.accent,
                    onBack: onBack,
                    showsDirectionToggle: true
                )
            } else {
                // Session-Modus (aktives Lernen): kompakter Text-Header,
                // kein Card-Block — der Lerninhalt soll Fläche bekommen.
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
            }
        }
        // Horizontal-Padding 0 (vorher `flashcardSessionCardInset` = 8).
        // Der äußere Screen-Wrapper (`flashcardSetupScreen`) setzt bereits
        // `AppLayout.screenPadding` — wenn wir hier nochmal 8 pt pro Seite
        // draufsetzen, ist der Header 16 pt schmaler als der Content
        // darunter. Gleich breit wie alle Cards jetzt.
        .padding(.top, 4)
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }

    /// Header für die laufende Karteikarten-Übung — Zurück führt zur
    /// Listen-Auswahl-/Setup-Card (nicht ganz raus zu Home).
    /// Bleibt bewusst **ohne** ModuleHeaderCard: während aktiver Session
    /// soll der Lerninhalt maximal Platz haben. Horizontal-Inset gleich
    /// zu den Session-Cards (`flashcardSessionCardInset`).
    var flashcardSessionHeader: some View {
        flashcardCompactHeader(onBack: returnToFlashcardSetup, showsModuleCard: false)
            .padding(.horizontal, flashcardSessionCardInset)
    }

    /// Header für den Karteikarten-Setup-Screen — Zurück verlässt die
    /// Karteikarten-View komplett (zurück zur vorherigen Navigationsebene).
    /// Zeigt die farbige `ModuleHeaderCard` → visueller Wiedererkennungs-
    /// anker zum Home-Tap. **Kein** eigener Horizontal-Inset — der
    /// Setup-Wrapper setzt bereits `AppLayout.screenPadding`, damit
    /// der Header auf derselben Kante wie die Setup-Cards sitzt
    /// (vorher: zusätzliche 8 pt machten ihn 16 pt schmaler).
    var flashcardSetupHeader: some View {
        flashcardCompactHeader(onBack: handleBackNavigation, showsModuleCard: true)
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

            // User-Request: Labels „Kann ich / Offen / Nochmal" +2 pt
            // (11 → 13) — besser lesbar, ohne die Tile-Breite zu sprengen.
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
