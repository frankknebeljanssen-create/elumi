import SwiftUI

/// Kompakter, runder Profil-Badge — Initialen-Variante, wenn ein Name
/// gesetzt ist, sonst neutrales Personen-Icon.
///
/// Designsprache: matcht die Top-Bar-Optik (secondarySurface + Border)
/// und trägt einen dezenten CTA-Amber-Accent als Aktivitäts-Highlight.
/// So wirkt der Badge als „zugehörig" zum App-Chrome, nicht als Fremdkörper.
///
/// Wiederverwendung:
/// • **AppTopBar** — 30pt, verdrängt den alten `person.crop.circle.fill`
/// • **Profilansicht-Hero** — größere Version (64–80pt)
/// • **Onboarding Abschluss-Teaser** — optional
struct ProfileAvatarBadge: View {
    let initials: String
    var size: CGFloat = 30
    var showsAccentRing: Bool = true

    /// Direkter Initializer — für Call-Sites, die die Initialen bereits haben.
    init(initials: String, size: CGFloat = 30, showsAccentRing: Bool = true) {
        self.initials = initials
        self.size = size
        self.showsAccentRing = showsAccentRing
    }

    /// Bequem-Initializer direkt aus dem ProfileStore. Vermeidet
    /// Call-Site-Boilerplate (`store.initials`).
    init(store: ProfileStore, size: CGFloat = 30, showsAccentRing: Bool = true) {
        self.initials = store.initials
        self.size = size
        self.showsAccentRing = showsAccentRing
    }

    private var isPlaceholder: Bool { initials == "?" }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.secondarySurface)

            if showsAccentRing {
                Circle()
                    .stroke(
                        AppTheme.Colors.cta.opacity(isPlaceholder ? 0.18 : 0.35),
                        lineWidth: 1
                    )
            }

            if isPlaceholder {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isPlaceholder ? "Profil öffnen" : "Profil: \(initials)"))
        .accessibilityAddTraits(.isButton)
    }
}
