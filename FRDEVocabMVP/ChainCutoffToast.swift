import SwiftUI

/// **Trainings-Chain Soft-Cutoff-Toast** (Stufe 4a-Fix, 2026-05-01,
/// Branch `feature/training-session-flow`).
///
/// Mittig-erscheinende Toast-Card, die einmalig pro Chain-Step
/// eingeblendet wird, sobald der Step-Timer abläuft (`timerExpired`
/// im `TrainingChainStore` wechselt von `false` → `true`). Vorher war
/// der Hinweis ein **dauerhaftes Banner** unter der Timer-Bar — das
/// nahm zu viel vertikalen Platz und kollidierte mit dem Modul-Content.
/// Jetzt ist es ein **flüchtiger Toast**: Scale-In, kurz Stehen,
/// Fade-Out.
///
/// **Wording-Note (Stufe 4a)**: bewusst neutral formuliert
/// („du kannst manuell weiter, wenn du möchtest") — KEIN
/// Force-Done-Versprechen. Wording-Update auf
/// „beende deine letzte Aufgabe" kommt erst in Stufe 4b-6, nachdem
/// die Force-Done-Hooks pro Modul gelandet sind.
///
/// **Verhalten**: keine User-Interaktion nötig. Kein OK-Button. Toast
/// verschwindet automatisch nach ~3.5 s + 0.5 s Fade-Out. Show-Once-
/// pro-Step ist im `TrainingChainStore.hasShownExpirationToast`-Flag
/// und im `ChainTimerOverlayModifier`-Hook geregelt.
struct ChainCutoffToast: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Trainingszeit für diese Übung ist abgelaufen")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Du kannst manuell weiter, wenn du möchtest.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.warning.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 4)
        // Begrenzte Breite, damit der Toast auf großen Geräten nicht
        // bis ans äußere Padding läuft — wirkt wie eine Card, nicht
        // wie ein Banner.
        .frame(maxWidth: 320)
    }
}
