import SwiftUI

/// Datenmodell für die Weiterlern-Card.
///
/// Wird von der späteren Content-Logik (z. B. `LastSessionStore`) gefüllt —
/// die View bleibt davon unberührt. `moduleIcon` ist optional: wenn
/// gesetzt, nutzt die Card das bestehende SVG-Asset als Fallback. Ohne
/// Icon zeigt die Card das Raketen-Emoji als visuelles „Weiter-Lernen"-
/// Leitbild.
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
/// Layout:
///   • Icon-Badge links — Raketen-Emoji (SPEC) über einem dunklen Kreis
///   • Text-Block — kleine Mint-Überschrift „Weiter lernen" + großer Titel
///     + dezenter Subtitle
///   • CTA rechts — Pill in Mint („Weiter ›")
///
/// Zustände:
///   • `data != nil` → aktive Card
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
            HStack(spacing: 12) {
                iconBadge(data: data)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Weiter lernen")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.elumiMint)

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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.Colors.elumiMint)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color.opacity(0.4), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weiter lernen: \(data.moduleTitle), \(data.subtitle)")
    }

    @ViewBuilder
    private func iconBadge(data: HomeContinueSessionData) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.elumiMint.opacity(0.18))
                .frame(width: 44, height: 44)
            Text("🚀")
                .font(.system(size: 24))
        }
    }

    // MARK: - Empty

    private var emptyCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Text("🚀")
                    .font(.system(size: 20))
                    .opacity(0.45)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Weiter lernen")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.65))

                Text("Noch keine Session")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Starte ein Modul und wir merken uns, wo du warst.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Colors.surface.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Noch keine Session zum Fortsetzen vorhanden.")
    }

    // MARK: - Chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
    }
}
