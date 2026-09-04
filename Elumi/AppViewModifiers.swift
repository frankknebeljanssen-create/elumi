import SwiftUI

struct AppTopBarSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.chromeBarHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.surface.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    )
            }
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y
            )
    }
}

struct AppBottomBarSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.top, AppTheme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.footerHeight, alignment: .top)
            .safeAreaPadding(.bottom, AppTheme.Spacing.xs)
            .background {
                AppTheme.Colors.background.opacity(0.98)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 1)
            }
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: 10,
                x: 0,
                y: -2
            )
    }
}

/// **2026-06-09** — „Ich höre zu"-Zustand für Aufnahme-Buttons.
///
/// Der Screen wirkte während der Spracheingabe statisch: ein rotes
/// Stop-Quadrat und ein kaum sichtbarer Rahmen-Puls (Weiß bei 28 %
/// Deckkraft). Man sah nicht, dass die App gerade auf eine Antwort
/// wartet (User-Report).
///
/// Der Puls läuft hier selbstständig als Dauer-Animation — er hängt
/// nicht mehr an einem extern getakteten Flag, das nur den
/// Aufnahmezustand spiegelte und deshalb gar nicht blinkte. Sichtbar
/// über drei Kanäle gleichzeitig, damit es auch im Augenwinkel auffällt:
/// atmende Skalierung, wandernde Rahmenstärke und ein farbiger Schein.
private struct ListeningPulseModifier: ViewModifier {
    let isActive: Bool
    let tint: Color
    let cornerRadius: CGFloat

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && isPulsing ? 1.035 : 1.0)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(tint.opacity(isPulsing ? 0.95 : 0.35),
                                lineWidth: isPulsing ? 4 : 2)
                }
            }
            .shadow(color: isActive ? tint.opacity(isPulsing ? 0.7 : 0.2) : .clear,
                    radius: isPulsing ? 16 : 6)
            // **2026-08-05 Bugfix** — `.animation(.repeatForever(...), value:)`
            // bindet dieselbe nie-endende Kurve an BEIDE Richtungen des
            // Übergangs, auch ans Ausschalten. Nach mindestens einem
            // Start/Stopp-Zyklus (ab der 2. Karte im Sprachmodus, wenn der
            // Auto-Zuhören-Zyklus erstmals durchläuft) blieb dadurch eine
            // verwaiste, sich selbst fortsetzende Animation auf der
            // Mikro-Karte hängen — sichtbar als endloses Wackeln, das mit
            // dem „Falsch"-Text alterniert, obwohl `isActive`/`isRecording`
            // längst korrekt `false` war (User-Report). Fix: kein
            // implizites `.animation(value:)` mehr; Start und Stopp laufen
            // jetzt als zwei explizite `withAnimation`-Transaktionen mit
            // unterschiedlichen Kurven — die kurze, nicht-wiederholende
            // Stopp-Kurve löst die laufende Dauerschleife sauber ab, statt
            // sie unbeendet weiterlaufen zu lassen.
            .onAppear { if isActive { startPulsing() } }
            .onChange(of: isActive) { _, active in
                if active {
                    startPulsing()
                } else {
                    stopPulsing()
                }
            }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private func stopPulsing() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPulsing = false
        }
    }
}

extension View {
    /// Markiert einen Button sichtbar als „wartet auf Spracheingabe".
    func appListeningPulse(
        isActive: Bool,
        tint: Color = AppTheme.Colors.elumiMint,
        cornerRadius: CGFloat = AppTheme.Radius.md
    ) -> some View {
        modifier(ListeningPulseModifier(isActive: isActive, tint: tint, cornerRadius: cornerRadius))
    }

    func appScreenBackground(_ style: AppSectionStyle) -> some View {
        // System-Pattern: Screen-Hintergrund ist der **dunklere** Ton
        // (`background` = elumiMidnight), Cards darauf nutzen `surface`
        // (= elumiNavy) und heben sich minimal heller ab — identisch zum
        // Home-Screen. Frühere Variante (surface als Screen-Fill) ließ
        // Cards in der gleichen Farbe wie der Screen liegen, dadurch
        // verschwanden sie optisch.
        background(AppTheme.Colors.background.ignoresSafeArea())
    }

    func appCardBackground(_ style: AppSectionStyle, intensity: Double = AppTheme.CardIntensity.soft, cornerRadius: CGFloat = AppTheme.Radius.lg) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(style.accent.opacity(intensity))
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }

    /// Farb-Overload von `appCardBackground` für Stellen, die keinen
    /// `AppSectionStyle` haben, sondern direkt einen Akzent-`Color`
    /// wollen — z. B. die Developer-Section (`AppTheme.Colors.
    /// developerAccent`), die bewusst außerhalb der Modul-Farbfamilie
    /// liegt. Identisches Rendering wie die `AppSectionStyle`-Variante.
    func appCardBackground(tint: Color, intensity: Double = AppTheme.CardIntensity.soft, cornerRadius: CGFloat = AppTheme.Radius.lg) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(intensity))
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }

    func appChipBackground(_ style: AppSectionStyle, intensity: Double = AppTheme.CardIntensity.medium, cornerRadius: CGFloat = AppTheme.Radius.md) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(style.accent.opacity(intensity), lineWidth: 1)
                )
        }
    }

    /// Kompletter Standard-Chip-Look für modul-assoziierte Pills
    /// (Filter-Chips, Status-Badges, Kategorie-Tags). Fasst
    /// Foreground-Color + Padding + Capsule-Background + Border in einem
    /// Modifier zusammen — spart pro Chip ~5 Zeilen ad-hoc-Styling.
    ///
    /// Unterscheidet sich bewusst von `appChipBackground`:
    /// - `appChipBackground` = **nur** Background + Border, Caller setzt
    ///   Padding und Text-Color. Für Custom-Layouts.
    /// - `moduleChipStyle` = **komplettes** Standard-Paket inkl.
    ///   Capsule-Geometrie, Horizontal/Vertical-Padding und Text-Color.
    ///   Für den typischen Modul-Tag-Use-Case.
    ///
    /// Font setzt der Caller selbst (Typographie liegt außerhalb dieser
    /// Verantwortung).
    func moduleChipStyle(_ section: AppSectionStyle) -> some View {
        let style = section.style
        return self
            .foregroundStyle(style.chipText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(style.chipBackground)
            )
            .overlay(
                Capsule().stroke(AppTheme.Colors.border, lineWidth: 1)
            )
    }

    /// Setup-Card-Hintergrund (Karteikarten-Auswahl-Screen und analoge Setups).
    /// Nutzt die zentralen Farb-Tokens `setupCardBackground` (#0F2D48) +
    /// `setupCardBorder` (#1A3A55) — Single Source of Truth, sodass alle
    /// Setup-Cards einheitlich aussehen, unabhängig vom Modul-Akzent.
    func appSetupCardBackground(cornerRadius: CGFloat = AppTheme.Radius.lg) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.setupCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }
}

/// Globaler Section-Header-Label für Setup-Cards (z. B. „AUSGEWÄHLTE LISTEN",
/// „ANZAHL DER KARTEN"). Single Source of Truth für app-weite Konsistenz.
/// Spec: 10pt, weight 600, tracking 1.5, uppercase, linksbündig,
/// Farbe `cardLabel` (= elumiAmber #FFD166).
@ViewBuilder
func setupCardLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .tracking(1.5)
        .foregroundStyle(AppTheme.Colors.cardLabel)
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, alignment: .leading)
}
