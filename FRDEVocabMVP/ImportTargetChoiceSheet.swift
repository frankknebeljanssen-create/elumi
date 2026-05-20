import SwiftUI

/// **Erster Sheet im neuen Import-Flow** (User-Spec 2026-04-22 Abend V):
/// Bevor die bisherige „neue Liste"-Namensvergabe startet, fragt diese
/// Sheet nach dem Ziel.
///
/// Zwei klare große Tap-Targets:
///   1. Neue Liste — bisheriger Flow läuft unverändert weiter
///   2. Bestehende Liste — eigene Picker-Sheet öffnet sich
///
/// Visuell bewusst minimalistisch (keine Farb-Spielereien) damit die
/// Entscheidung selbsterklärend bleibt.
struct ImportTargetChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let importableCount: Int
    let onChooseNewList: () -> Void
    let onChooseExistingList: () -> Void
    // **Phase B (2026-05-20)** — dritter Pfad: Scan als Entwurf sichern.
    // **Phase D v2 (2026-05-20)** — optional: im Draft-Detail entfällt der
    // Pfad (man ist schon im Entwurf) → dritte Card wird ausgeblendet.
    var onSaveAsDraft: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                summary
                    .padding(.top, 8)

                choiceCard(
                    icon: "square.and.pencil",
                    title: "In neue Liste importieren",
                    subtitle: "Eine frische Liste mit eigenem Namen anlegen.",
                    action: {
                        dismiss()
                        // Defer: damit Sheet-Dismiss-Animation nicht mit
                        // dem nächsten UI-Trigger kollidiert.
                        DispatchQueue.main.async { onChooseNewList() }
                    }
                )

                choiceCard(
                    icon: "tray.and.arrow.down",
                    title: "Zu bestehender Liste hinzufügen",
                    subtitle: "Auswahl aus deinen vorhandenen Listen — Duplikate werden übersprungen.",
                    action: {
                        dismiss()
                        DispatchQueue.main.async { onChooseExistingList() }
                    }
                )

                // **Phase B (2026-05-20)** — dritter Pfad: als Entwurf sichern
                // (nur wenn `onSaveAsDraft` gesetzt — Phase D v2).
                if let onSaveAsDraft {
                    choiceCard(
                        icon: "tray.full",
                        title: "Als Entwurf speichern",
                        subtitle: "Scan sichern und später fertig bearbeiten",
                        action: {
                            dismiss()
                            DispatchQueue.main.async { onSaveAsDraft() }
                        }
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle("Wohin importieren?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        Text("\(importableCount) \(importableCount == 1 ? "Eintrag" : "Einträge") aus dem Scan bereit zum Import.")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func choiceCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.cta)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(AppTapButtonStyle())
    }
}
