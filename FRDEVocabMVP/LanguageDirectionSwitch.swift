import SwiftUI
import UIKit

/// Globaler Language-Direction-Schalter.
///
/// Liest und schreibt den globalen Schlüssel `appDirectionKey` über
/// `@AppStorage` — das ist bereits der zentrale Wahrheitszustand in der
/// App, den alle Module (Quiz, Karteikarten, Training, Vokabeln …)
/// ohnehin beobachten. Mehrere Instanzen dieser Komponente an
/// unterschiedlichen Stellen (Home, Session-Setup) zeigen daher immer
/// denselben Zustand und halten sich gegenseitig synchron — es gibt
/// keinen parallelen Store und keine lokale Override-Logik.
///
/// Umfang des Toggles: `.frenchToGerman` ↔ `.germanToFrench`. Die beiden
/// englischen Varianten der `Direction`-Enum sind im V1-Umfang nicht Teil
/// des Home-Schalters — sie bleiben für Import-/Lexikon-Zwecke aber im
/// Datenmodell erhalten.
///
/// Varianten:
///   • `.regular` — Home-Screen, vollflächig, höherer Präsenz-Wert.
///   • `.compact` — Session-Setup-Zeile, kompakter, als Kontext-Element.
struct LanguageDirectionSwitch: View {
    enum Size {
        case regular
        case compact
    }

    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue

    /// Kompressions-Flag für die Tap-Animation (Scale-Down bei Tap,
    /// Snap-Back nach ~100 ms). Lebt pro Komponente — zwei Instanzen
    /// animieren unabhängig, der Datenzustand bleibt aber identisch.
    @State private var isPressed = false

    var size: Size = .regular
    /// Optionaler Callback nach dem Toggle (z. B. für Sound-Feedback).
    /// Der State-Wechsel selbst passiert bereits über `@AppStorage`.
    var onToggle: (() -> Void)? = nil

    var body: some View {
        let direction = Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman
        let isFrToDE = direction == .frenchToGerman
        let spec = spec(for: size)

        Button(action: toggle) {
            HStack(spacing: spec.flagSpacing) {
                flag(code: isFrToDE ? "FR" : "DE", spec: spec)

                Image(systemName: "arrow.right")
                    .font(.system(size: spec.arrowSize, weight: .black))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .scaleEffect(isPressed ? 0.9 : 1.0)

                flag(code: isFrToDE ? "DE" : "FR", spec: spec)
            }
            .padding(.horizontal, spec.horizontalPadding)
            .padding(.vertical, spec.verticalPadding)
            .frame(maxWidth: spec.expandsWidth ? .infinity : nil)
            .background(
                Capsule()
                    .fill(AppTheme.Colors.surface.opacity(0.55))
            )
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.Colors.border.opacity(0.55), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFrToDE
                ? "Lernrichtung Französisch nach Deutsch. Zum Umschalten tippen."
                : "Lernrichtung Deutsch nach Französisch. Zum Umschalten tippen."
        )
    }

    // MARK: - Sub-Views

    private func flag(code: String, spec: Spec) -> some View {
        StraightFlagBadge(
            countryCode: code,
            width: spec.flagWidth,
            height: spec.flagHeight,
            labelFontSize: spec.flagLabelSize
        )
        .scaleEffect(isPressed ? 0.88 : 1.0)
        // Symmetric id-Transition sorgt dafür, dass SwiftUI die Flaggen
        // beim Swap als „austauschend" behandelt — keine Text-/Farb-
        // Zwischenschritte.
        .id(code)
    }

    // MARK: - Toggle

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // 1) Kompression anziehen — kurzer „Druck"-Effekt auf Flaggen + Pfeil.
        withAnimation(.easeOut(duration: 0.08)) {
            isPressed = true
        }

        // 2) State flippen — geschieht in der Mitte der Animation, damit
        //    die Flaggen während des Skalen-Tiefpunkts wechseln und der
        //    visuelle „Swap" organisch wirkt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            selectedDirectionRaw = (selectedDirectionRaw == Direction.frenchToGerman.rawValue)
                ? Direction.germanToFrench.rawValue
                : Direction.frenchToGerman.rawValue
            withAnimation(.easeOut(duration: 0.10)) {
                isPressed = false
            }
            onToggle?()
        }
    }

    // MARK: - Spec

    private func spec(for size: Size) -> Spec {
        switch size {
        case .regular:
            return Spec(
                flagWidth: 40, flagHeight: 26, flagLabelSize: 10,
                arrowSize: 14,
                flagSpacing: 10,
                horizontalPadding: 16, verticalPadding: 10,
                expandsWidth: true
            )
        case .compact:
            return Spec(
                flagWidth: 30, flagHeight: 20, flagLabelSize: 9,
                arrowSize: 12,
                flagSpacing: 8,
                horizontalPadding: 12, verticalPadding: 6,
                expandsWidth: false
            )
        }
    }

    private struct Spec {
        let flagWidth: CGFloat
        let flagHeight: CGFloat
        let flagLabelSize: CGFloat
        let arrowSize: CGFloat
        let flagSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        /// `true` → die Komponente spannt auf die verfügbare Breite (Home).
        /// `false` → sie dimensioniert sich nach Inhalt (Session-Setup-Zeile).
        let expandsWidth: Bool
    }
}

/// Gemeinsame Zeile für das Session-Setup — Label „Richtung" links +
/// kompakter Switch rechts. Der Switch ist funktional identisch zur
/// Home-Instanz (derselbe globale State), nur kleiner gerendert.
///
/// Absichtlich **keine** eigene State-Logik: die Komponente ist reiner
/// Layout-Wrapper um den `LanguageDirectionSwitch`.
struct SessionDirectionRow: View {
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Richtung")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Gilt für diese und alle künftigen Sessions.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            LanguageDirectionSwitch(size: .compact, onToggle: onToggle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SessionCardBackground(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lernrichtung")
    }
}
