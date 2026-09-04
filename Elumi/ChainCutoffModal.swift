import SwiftUI

/// **Trainings-Chain Soft-Cutoff-Modal** (Stufe 4b-Modal-Refactor,
/// 2026-05-02, Branch `feature/training-session-flow`).
///
/// Ersetzt den vorherigen `ChainCutoffToast` (Stufe 4a-Fix). Statt eines
/// flüchtigen Auto-Fade-Toasts ohne Interaktion ist das Modal jetzt ein
/// **persistenter, blockierender Backdrop-Overlay** mit zwei klaren
/// Action-Buttons:
///
///   • **Secondary** „Aufgabe fertigmachen" (outline-grau) — schließt
///     das Modal, lässt `timerExpired = true` für den Modul-Submit-
///     Hook (4b-1 KK / 4b-2 Akzente / 4b-3 Quiz / 4b-4 Training)
///     stehen. Der nächste User-Submit triggert den vorhandenen
///     Force-Done-Pfad — gleiche Auto-Advance-Mechanik wie ohne
///     Modal-Refactor, nur mit explizitem User-Choice davor.
///
///   • **Primary** „Jetzt weiter" (Success-Grün) — sofortiger Force-
///     Done über die Modul-spezifische Closure aus dem
///     `appChainForceAdvanceAction`-Environment. Wird vom Modul-View
///     gesetzt (mit Zugriff auf den eigenen Session-Store / Engine);
///     wenn nil (Modul hat noch keinen Force-Done-Helper), wird der
///     Primary-Button **versteckt** und nur Secondary bleibt sichtbar.
///     Graceful Rollout für 4b-3/4/5.
///
/// **Backdrop**: halb-transparenter schwarzer Layer (~40 % Opacity)
/// blockiert jegliche Modul-Interaktion, bis der User eine der zwei
/// CTAs tappt. Kein Tap-Outside-Dismiss — User MUSS bewusst
/// entscheiden. Das ist der bewusste UX-Switch gegenüber dem 4a-
/// Toast: Cutoff ist ein wichtiger Übergangs-Punkt, kein bloßer Hint.
struct ChainCutoffModal: View {
    /// Modul-Name für die Sub-Headline („deinen aktuellen Schritt
    /// abschließen") — optional, wenn nil fällt der Sub-Text auf eine
    /// neutrale Variante zurück.
    let moduleName: String?

    /// Tap-Handler für „Aufgabe fertigmachen". Schließt das Modal.
    let onFinishTask: () -> Void

    /// Tap-Handler für „Jetzt weiter". Schließt das Modal **und**
    /// triggert den Modul-spezifischen Force-Done. Wenn nil, wird
    /// der Primary-CTA komplett ausgeblendet — Modal hat dann nur
    /// noch den Secondary-CTA.
    let onAdvanceNow: (() -> Void)?

    var body: some View {
        ZStack {
            // **Backdrop** — blockiert Modul-Interaktion bis Tap auf
            // einen der beiden CTAs. `contentShape(Rectangle())` +
            // leerer onTapGesture absorbiert Touches, damit nichts
            // dahinter klickbar bleibt. **Kein** Tap-Outside-Dismiss
            // (Spec 2026-05-02): User soll bewusst eine der zwei
            // Optionen wählen.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* swallow */ }

            // **Modal-Card** — zentriert, max-Breite damit's auf
            // großen Geräten nicht über die ganze Breite zerläuft.
            VStack(spacing: 18) {
                Image(systemName: "hourglass")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    Text("Trainingszeit abgelaufen")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 10) {
                    // Primary („Jetzt weiter") nur rendern, wenn das
                    // Modul einen Force-Done-Helper über die
                    // `appChainForceAdvanceAction`-Environment-Closure
                    // bereitstellt. Stand 2026-05-02 sind das
                    // Karteikarten (4b-1) und Akzente (4b-2) — Quiz
                    // (4b-3), Training (4b-4) und Verbformen (4b-5)
                    // adoptieren das Pattern in den Folge-Commits.
                    if let onAdvanceNow {
                        Button {
                            onAdvanceNow()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Jetzt weiter")
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.success))
                        .accessibilityLabel(Text("Jetzt weiter"))
                        .accessibilityHint(Text("Beendet den aktuellen Schritt sofort und springt zum nächsten Modul."))
                    }

                    // Secondary („Aufgabe fertigmachen") immer
                    // sichtbar — auch ohne Force-Done-Helper kann
                    // der User den Cutoff-Hint quittieren und im
                    // Modul weiterarbeiten.
                    Button {
                        onFinishTask()
                    } label: {
                        Text("Aufgabe fertigmachen")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .accessibilityLabel(Text("Aufgabe fertigmachen"))
                    .accessibilityHint(Text("Schließt diesen Hinweis. Du kannst die aktuelle Aufgabe noch zu Ende beantworten — danach geht es automatisch weiter."))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.Colors.warning.opacity(0.40), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }

    /// Sub-Text-Variante. Wenn ein Modul-Name vorhanden ist, wird er
    /// für eine konkretere Formulierung benutzt; sonst neutral.
    private var subText: String {
        if let moduleName, !moduleName.isEmpty {
            return "Du kannst \(moduleName) noch fertigmachen oder direkt zum nächsten Schritt springen."
        }
        return "Du kannst die aktuelle Aufgabe noch fertigmachen oder direkt zum nächsten Schritt springen."
    }
}
