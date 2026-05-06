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
    /// kompakte Sub-Section-Trenner-Variante (TrainingHubView's
    /// „ALLGEMEIN"/„SPEZIAL"). Caller kann auf 13 pt hochstellen
    /// für prominenteren Look (Home-Section „DEINE TOOLS" nach
    /// dem Spacing-Polish 2026-05-06).
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.bottom, 4)
    }
}
