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

/// **Footer-Credit-Badge** mit Increment-Animation.
///
/// **Stufe 1b (2026-04-30, Branch `feature/training-session-flow`)**:
/// erweitert um Pulse + „+N"-Pop bei Credit-Increment. Trigger:
/// `.onChange(of: text)` parst alten und neuen Text als Int und
/// berechnet das Delta. Animation läuft nur bei **positivem Delta**
/// (= echtem Reward, z.B. Slot-Spin-Grant) — Decrements wie
/// Spielstart-Verbrauch (-1) bleiben stumm. Begründung: ein „+(−1)"-
/// Pop wäre semantisch komisch und visuell distracting; der Drop des
/// Badge-Counters ist ohnehin ein neutraler Buchhaltungs-Vorgang, kein
/// Reward-Moment.
///
/// **Animation-Sequenz** (~2.0s gesamt):
///   • t=0      Pulse-Scale 1.0 → 1.25 (Spring response 0.35, damping 0.55)
///   • t=0      „+N"-Tag erscheint (Fade-in + Pop-Scale 0.6 → 1.0)
///   • t=0.3s   Pulse-Scale zurück auf 1.0 (ease-out)
///   • t=1.3s   „+N"-Tag fade-out + slide-up
///   • t=1.6s   `+N`-State auf nil → kein Re-Render
///
/// **Pulse-Pattern wiederverwendet** aus `ElumiTabView.resultHighlightScale`
/// (Z. 181-183, 944-967) — dort `TimelineView`-getrieben für
/// kontinuierlichen Glow; hier kompakte one-shot-Animation reicht.
private struct AppBottomBarBadge: View {
    let text: String

    /// Pulse-Skalierung bei Increment. 1.0 = idle, 1.25 = peak.
    @State private var pulseScale: CGFloat = 1.0

    /// Aktuell sichtbarer „+N"-Pop-Wert. Nil = unsichtbar.
    /// Erzeugt aus dem Delta zwischen altem und neuem `text`.
    @State private var popValue: Int? = nil

    /// Letzter geparster Wert — Referenz für Delta-Berechnung beim
    /// nächsten Update. Default 0 → Initial-Render zeigt keinen Pop
    /// (auch wenn der Initial-Wert > 0 ist; das ist gewollt, weil der
    /// User den Wert nicht in dieser Sitzung verdient hat).
    @State private var lastParsedValue: Int = 0

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(AppTheme.Colors.error)
            .clipShape(Capsule())
            .scaleEffect(pulseScale)
            .overlay(alignment: .top) {
                if let n = popValue {
                    BadgePopTag(amount: n)
                        .offset(y: -16)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.6).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .offset(x: 9, y: -4)
            .onChange(of: text) { oldText, newText in
                animateIfIncrement(oldText: oldText, newText: newText)
            }
            .onAppear {
                lastParsedValue = Int(text) ?? 0
            }
    }

    /// Parst alten und neuen Text als Int und triggert Pulse + „+N"-Pop
    /// nur bei **positivem Delta**. Negative Deltas (z.B. Spielstart
    /// verbraucht 1 Credit) bleiben animations-frei.
    private func animateIfIncrement(oldText: String, newText: String) {
        guard let newValue = Int(newText) else { return }
        let oldValue = Int(oldText) ?? lastParsedValue
        lastParsedValue = newValue
        let delta = newValue - oldValue
        guard delta > 0 else { return }

        // Pulse-Scale: schneller Up-Bounce, dann sanft zurück.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            pulseScale = 1.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeOut(duration: 0.20)) {
                pulseScale = 1.0
            }
        }

        // „+N"-Tag: Pop ein, kurz halten, slide-up + Fade aus.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
            popValue = delta
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
            withAnimation(.easeIn(duration: 0.30)) {
                popValue = nil
            }
        }
    }
}

/// **„+N"-Pop-Tag**, der über dem Footer-Badge bei Credit-Increment
/// kurz aufploppt. Stufe 1b. Eigene Capsule mit Akzent-Farbe (Warning,
/// Gelb-Ton) — visuell unterscheidbar vom roten Counter-Badge, damit
/// der Pop als positiver Reward-Moment gelesen wird.
private struct BadgePopTag: View {
    let amount: Int

    var body: some View {
        Text("+\(amount)")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppTheme.Colors.warning)
            .clipShape(Capsule())
            .shadow(color: AppTheme.Colors.warning.opacity(0.55), radius: 6, x: 0, y: 1)
    }
}
