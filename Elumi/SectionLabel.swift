// SectionLabel.swift
// **2026-05-06** — Sub-Section-Label-Component für den Home-Refactor
// (Hybrid γ v3). User-Spec: 11 pt / weight 500 / Grau / CAPS +
// Letter-Spacing 0.6. Konsistent zu Sub-Screen-Labels („ALLGEMEIN" /
// „SPEZIAL") im neuen Training-Hub.
//
// Abgrenzung zum bestehenden Section-Header-Stil (16 pt / .medium /
// textSecondary, sentence-case wie „Was möchtest du heute lernen?"):
// die großen Section-Headers bleiben unverändert. SectionLabel ist
// nur für die kleineren, unscheinbaren Sub-Section-Trenner (z. B.
// „DEINE TOOLS" zwischen Methoden- und Tools-Cards) gedacht.

import SwiftUI

/// Kleines, gemächliches Sub-Section-Label im CAPS-Stil. Caller
/// übergibt den Text (z. B. „DEINE TOOLS"); die View rendert ihn
/// uppercase, mit Letter-Spacing und in textSecondary.
///
/// **Style-Tokens**:
/// - 11 pt / weight `.medium` (= 500 im Apple-Mapping)
/// - `AppTheme.Colors.textSecondary` (grau, dezent)
/// - Letter-spacing 0.6 (UPPERCASE-Lesbarkeit)
/// - Trailing-Padding bottom 4 pt zum nächsten Content-Block
struct SectionLabel: View {
    let text: String
    /// Schriftgröße. Default 11 pt für die ursprünglich spec'te
    /// kompakte Sub-Section-Trenner-Variante. Caller kann auf
    /// 13 pt hochstellen (Home „DEINE TOOLS") oder 15 pt (Hub
    /// „ALLGEMEIN"/„SPEZIAL" nach Iteration 4 Polish — User-Spec
    /// 2026-05-06 „beides bold und 2pt größer").
    var size: CGFloat = 11
    /// Schriftgewicht. Default `.medium` (500) für die dezenteren
    /// Sub-Trenner; Caller kann auf `.bold` schalten, wenn der
    /// Label prominenter wirken soll.
    var weight: Font.Weight = .medium

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.bottom, 4)
    }
}
