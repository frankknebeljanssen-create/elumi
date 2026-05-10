// CorrectionCardView.swift
// **Léa-Chat MVP Schritt 2A (2026-05-10)** — Mint-Card, die zwischen
// User-Bubble und Léa-Antwort eingeblendet wird, wenn Léa einen
// Korrektur-Marker geliefert hat.
//
// **Visueller Anker (User-Spec)**:
//   • Look = iMessage-Quote-Bubble (eingerückt, leichter Akzent),
//     NICHT die Elumi-Setup-Card. Bewusst flach, zentriert, schmaler
//     als die Bubbles → wirkt wie ein Hinweis-Sticker, nicht wie
//     UI-Chrome.
//   • Linear-Gradient `#E8F9EE → #F0FBF4` (mint, sehr hell) damit
//     die Card sich vom weißen Chat-Background dezent abhebt ohne
//     den User-Flow zu unterbrechen.
//   • Foreground `#2D7A3E` (sattes Mint-Grün, lesbar auf hellem BG).
//   • 14 pt Schrift, 📗-Emoji als Anker statt Lehrer-Icon (Lernhinweis,
//     keine Korrektur-Strafe).
//
// **Animation**: Slide-In von oben + Fade-In, einmalig beim ersten
// Render via `transition(.move + .opacity)`. SwiftUI animiert das
// dann durch den `correctionCardId` als Identity-Anchor → keine
// Re-Animation bei jedem View-Update.
//
// **Layout**: Center-aligned, max-width ~85 % der ScrollView. Padding
// 14 pt horizontal × 12 pt vertical, corner radius 16 (etwas weniger
// als die 18-pt-Chat-Bubbles → bewusst andere Form, damit es als
// „nicht-Bubble" liest).

import SwiftUI

struct CorrectionCardView: View {
    /// Der deutsche Tipp-Text aus Léas Marker (`Kleiner Tipp: …`).
    let germanTip: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 📗-Emoji als Lernhinweis-Anker. Bewusst nicht 💡 (das
            // benutzt Léa selbst im Marker) und nicht ✏️ (Lehrer-
            // Vibe). Das grüne Buch fühlt sich nach „Vokabel-Heft an
            // dem du gerade was Neues lernst" an.
            Text("📗")
                .font(.system(size: 16))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                // Header — kurz, freundlich. Bewusst KEIN Bold, kein
                // Caps — sonst wirkt es wie Lehrer-Tafel-Hinweis.
                Text("Kleiner Tipp")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.176, green: 0.478, blue: 0.243)) // #2D7A3E

                // Tipp-Body — Léas deutsche Erklärung 1:1 wie aus dem
                // Marker geparst. Mehr-zeilig erlaubt (Léa schreibt
                // manchmal längere Tipps).
                Text(germanTip)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(red: 0.176, green: 0.478, blue: 0.243)) // #2D7A3E
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.910, green: 0.976, blue: 0.933), // #E8F9EE
                            Color(red: 0.941, green: 0.984, blue: 0.957)  // #F0FBF4
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.176, green: 0.478, blue: 0.243).opacity(0.18), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .center)
        // **Width-Constraint** — die Card soll schlanker als die
        // Bubbles wirken (Bubbles sind ~85 %). Wir wrappen nicht
        // hart auf 85 %, weil zu schmal bei langen Tipps unleserlich
        // wird. Stattdessen `padding(.horizontal, 36)` → die Card
        // ist auf beiden Seiten 36 pt von den Bubble-Edges eingerückt,
        // visualisiert „eingebettet zwischen den Bubbles".
        .padding(.horizontal, 36)
    }
}

#Preview {
    VStack(spacing: 12) {
        CorrectionCardView(germanTip: "Es heißt 'à l'école' — bei Schulen benutzt man à + l'!")
        CorrectionCardView(germanTip: "Bei Verben auf -er ist die je-Form ohne S: 'je mange', nicht 'je manges'.")
    }
    .padding(.vertical)
    .background(Color.white)
}
