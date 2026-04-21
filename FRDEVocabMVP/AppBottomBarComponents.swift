import SwiftUI

struct AppBottomBarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: (() -> Void)?
    var isActive: Bool = false
    var foregroundColor: Color? = nil
    var badgeText: String? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle((foregroundColor ?? AppTheme.Colors.textPrimary).opacity(isActive ? 1 : 0.92))
                    .accessibilityLabel(Text(accessibilityLabel))

                if let badgeText {
                    AppBottomBarBadge(text: badgeText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil && badgeText == nil)
        .opacity(action == nil && badgeText == nil && !isActive ? 0.45 : (isActive ? 1 : 0.92))
    }
}

/// Footer-Button für den **Game Hub**. Der Name „SnackButton" ist
/// historisch (früher Sammlung/Herzchen-Snacks); semantisch zeigt dieser
/// Button jetzt **verfügbare Spiele** und führt in den Game Hub.
///
/// Icon-Wechsel `trophy.fill` → `gamecontroller.fill` (User-Request):
/// Pokal signalisiert Auszeichnung/Sammlung, aber der Button öffnet
/// spielbare Sessions. Der Controller ist das klare, etablierte Symbol
/// für „Spielen" — keine Verwechslungsgefahr mehr mit Progress/Streak-
/// Rewards, die auf dem Home-Progress-Board sitzen.
///
/// Der `kind`-Parameter bleibt erhalten (wird von Call-Sites noch
/// übergeben), ist aber ohne visuellen Effekt — kein Snack-Asset mehr
/// sichtbar. Entfernen würde Call-Sites brechen, also weiches Deprecate.
struct AppBottomBarSnackButton: View {
    let accessibilityLabel: String
    let action: (() -> Void)?
    let isActive: Bool
    let kind: ElumiSnackKind
    var badgeText: String? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(width: 38, height: 38)
                    .scaleEffect(isActive ? 1.06 : 1)
                    .opacity(isActive ? 1 : 0.95)
                    .accessibilityLabel(Text(accessibilityLabel))

                if let badgeText {
                    AppBottomBarBadge(text: badgeText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil && badgeText == nil)
        .opacity(action == nil && badgeText == nil && !isActive ? 0.45 : (isActive ? 1 : 0.92))
    }
}

struct AppBottomBarSoundToastView: View {
    let toast: SoundToggleToast
    let areSoundsEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(areSoundsEnabled ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary)

            Text(toast.message)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke((areSoundsEnabled ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary).opacity(0.24), lineWidth: 1)
        )
        .shadow(color: AppTheme.Shadow.card.color, radius: 10, x: 0, y: 4)
    }
}

private struct AppBottomBarBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(AppTheme.Colors.error)
            .clipShape(Capsule())
            .offset(x: 9, y: -4)
    }
}
