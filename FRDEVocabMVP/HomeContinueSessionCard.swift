import SwiftUI

/// Datenmodell für die Weiterlern-Card.
///
/// Wird von der späteren Content-Logik (z. B. `LastSessionStore`) gefüllt —
/// die View bleibt davon unberührt. `moduleIcon` ist optional: wenn
/// gesetzt, nutzt die Card das bestehende SVG-Asset. Ohne Icon wird der
/// Akzent allein aus `accent` gezeichnet, damit ein Fallback existiert.
struct HomeContinueSessionData: Equatable {
    let moduleTitle: String
    /// Unterzeile z. B. „Vokabeln · 15 Min." — die konkrete Formatierung
    /// liegt beim Aufrufer, die View zeigt den String 1:1.
    let subtitle: String
    /// CTA-Label (Default „Weiter"). Override erlaubt, falls der Kontext
    /// ein anderes Verb verlangt („Nochmal", „Fortsetzen" …).
    var ctaLabel: String = "Weiter"
    let moduleIcon: HomeModuleIcon?
    let accent: Color
}

/// Home-Card „Letzte Session fortsetzen". Struktur + alle Zustände final
/// gebaut, damit die Logik-Runde danach nur noch das Datenmodell erzeugen
/// muss.
///
/// Zustände:
///   • `data != nil` → aktive Card mit Modul-Icon, Titel, Subtext, CTA
///   • `data == nil` → dezenter Empty-State („Noch keine Session zum
///     Fortsetzen"), damit der Home-Flow nicht „reißt", wenn wirklich nichts
///     da ist. Die HomeView kann optional entscheiden, den Empty-State
///     ganz wegzulassen, indem sie die Card nicht rendert.
struct HomeContinueSessionCard: View {
    let data: HomeContinueSessionData?
    let onContinue: () -> Void

    var body: some View {
        if let data {
            activeCard(data: data)
        } else {
            emptyCard
        }
    }

    // MARK: - Active

    private func activeCard(data: HomeContinueSessionData) -> some View {
        Button(action: onContinue) {
            HStack(spacing: 14) {
                iconBadge(data: data)

                VStack(alignment: .leading, spacing: 3) {
                    Text("LETZTE SESSION")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))

                    Text(data.moduleTitle)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(data.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Text(data.ctaLabel)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(data.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(data.accent.opacity(0.15))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(accent: data.accent))
            .overlay(cardBorder(accent: data.accent))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color.opacity(0.4), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Letzte Session fortsetzen: \(data.moduleTitle), \(data.subtitle)")
    }

    @ViewBuilder
    private func iconBadge(data: HomeContinueSessionData) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(data.accent.opacity(0.14))
                .frame(width: 46, height: 46)
            if let icon = data.moduleIcon {
                HomeModuleIconView(icon: icon, size: 36)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(data.accent)
            }
        }
    }

    // MARK: - Empty

    private var emptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                .frame(width: 36, height: 36)
                .background(AppTheme.Colors.textSecondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Noch keine Session")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Starte ein Modul und wir merken uns, wo du warst.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Colors.surface.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.Colors.border.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Noch keine Session zum Fortsetzen vorhanden.")
    }

    // MARK: - Chrome

    private func cardBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.05))
            )
    }

    private func cardBorder(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(accent.opacity(0.22), lineWidth: 1)
    }
}
