// DailyDropStackedCardsIcon.swift
// **2026-05-07** — Programmatische SwiftUI-Illustration für die
// Daily-Drop-Card auf Home. Ersetzt das bisherige `sparkles`-SF-
// Symbol durch einen 3-Karten-Stapel, der visuell den Slot-/Karten-
// Charakter des Daily-Drop-Modus signalisiert.
//
// **Layout** (von hinten nach vorne):
//   1. Karte 1 (hinten):  -8° rotiert, Akzent Amber/Quiz-Yellow
//   2. Karte 2 (mitte):    0° gerade,  Akzent Mint
//   3. Karte 3 (vorne):   +8° rotiert, Akzent Lavender/Verbforms
//
// Subtle Drop-Shadow unter dem Stack für eine leicht 3D-Anmutung.
// Keine Animation am Icon selbst — die Card hat bereits Border-Glow
// + Shimmer + Badge, das Icon bleibt ruhig im Zentrum.
//
// **Backlog**: Ersatz durch externes 3D-Asset (Konzept C —
// fallende Karten mit echter Tiefe wie das Karteikarten-Asset)
// kann später ohne API-Änderung erfolgen.

import SwiftUI

/// Stacked-Cards-Illustration für die Daily-Drop-Card. Container ist
/// quadratisch (Default 40 pt); die drei Karten skalieren proportional.
struct DailyDropStackedCardsIcon: View {
    /// Außen-Container-Größe. Default 40 pt — passt visuell in den
    /// 52pt-Icon-Frame der WideMethodCard.
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // Karte 1 — hinten, leicht nach links rotiert.
            singleCard(color: AppTheme.Colors.moduleQuiz)
                .rotationEffect(.degrees(-8))
                .offset(x: -3, y: 1)

            // Karte 2 — mitte, gerade. Etwas kleinerer Drop-Shadow,
            // damit sie als „Stapel-Anker" zwischen den beiden
            // gekippten Nachbarn fungiert.
            singleCard(color: AppTheme.Colors.elumiMint)

            // Karte 3 — vorne, leicht nach rechts rotiert.
            singleCard(color: AppTheme.Colors.moduleVerbforms)
                .rotationEffect(.degrees(8))
                .offset(x: 3, y: -1)
        }
        .frame(width: size, height: size)
        // Subtiler Stack-Shadow — gibt dem ganzen Icon-Block eine
        // leichte 3D-Höhe ohne dass jede Karte einzeln einen Shadow
        // bekommt (würde die Karten-Kanten zu hart machen).
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    /// Einzelne Karte: Rounded-Rect mit Akzent-Fill, weißem Border
    /// für Pop-Effekt auf farbigem Card-Background.
    @ViewBuilder
    private func singleCard(color: Color) -> some View {
        // Karte ist 70 % der Icon-Größe breit, 95 % hoch — klassisches
        // Spielkarten-Aspect-Ratio (~3:4).
        let cardWidth = size * 0.62
        let cardHeight = size * 0.88
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .frame(width: cardWidth, height: cardHeight)
    }
}
