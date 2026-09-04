import SwiftUI

/// **App-weites Micro-Interaction-System** (Phase 7.6).
///
/// Zentrale Definition aller App-Timings, Animations-Kurven,
/// Button-Styles und Entry-Modifier. **Keine** lokalen
/// Animations-Durations mehr — neue Interactions holen sich ihre
/// Werte aus `AppMotion.Timing` / `AppMotion.Scale` / den
/// Preset-`Animation`s und verwenden die bereitgestellten
/// `ButtonStyle`s bzw. `.appEntryTransition(delay:)`-Modifier.
///
/// Leitprinzipien (User-Spec):
///   • Sofortiges Feedback bei Interaktion (kein Delay).
///   • Kurz, präzise, **keine** Bounces / Spring-Overshoots auf
///     großen Elementen.
///   • Konsistente Geschwindigkeit und Bewegungsmuster appweit.
///   • Weniger ist mehr: max. 1–2 parallele Animationen pro
///     Aktion; keine simultanen Stagger-Orgien.
///
/// Zukünftige Anpassungen nur hier — jeder Subscreen liest die
/// Konstanten, sodass ein einzelner Tuning-Pass die ganze App
/// ausrichtet.
enum AppMotion {

    // MARK: - Timings

    /// Standard-Dauern nach User-Spec „Micro Interaction System".
    enum Timing {
        /// **Tap-Feedback** (Button/Card-Scale-Down). 80–120 ms.
        static let tapFeedback: Double = 0.1

        /// **State-Change** (Highlight-Wechsel, Farb-Fade,
        /// Value-Swap, Selection-Marker). 120–200 ms.
        static let stateChange: Double = 0.18

        /// **Screen-Transition** (Overlay-Swap, Start→Gameplay,
        /// Game-Over→Summary). 180–250 ms.
        static let screenTransition: Double = 0.22

        /// **Entry-Animation** (Fade + leichter Slide beim Öffnen
        /// eines Screens). Identisch zu `screenTransition` — bewusst
        /// eine Größe weniger zum Pflegen.
        static let entry: Double = 0.22
    }

    // MARK: - Scale-Werte

    enum Scale {
        /// **Phase 7.6 Debug-Visibility-Pass** — User-Report „null
        /// Effekt auf dem Gerät sichtbar". Werte temporär drastisch
        /// deutlicher, damit wir auf dem Gerät sicher sehen, dass
        /// das Feedback greift. Nach Verifizierung zentral leise
        /// zurückdrehen (0.95/0.97 reichten visuell eigentlich aus).
        static let buttonPress: CGFloat = 0.92
        static let cardPress: CGFloat = 0.92
    }

    // MARK: - Entry-Offset

    enum Offset {
        /// Slide-Up beim Screen-Open. 8 pt = Mitte des Spec-
        /// Korridors 6–10 pt.
        static let entry: CGFloat = 8
    }

    // MARK: - Vorgefertigte `Animation`-Presets

    /// Für Button-/Card-Press-Feedback.
    static let tap: Animation = .easeOut(duration: Timing.tapFeedback)

    /// Für State-Changes (Highlight-Fade, Badge-Einblendung,
    /// Value-Swap, Dropdown-Auswahl).
    static let state: Animation = .easeOut(duration: Timing.stateChange)

    /// Für Overlay-/Screen-Transitions.
    static let transition: Animation = .easeOut(duration: Timing.screenTransition)

    /// Für Entry-Animation (mit optionalem Stagger-Delay außen
    /// aufgesetzt via `.delay(_:)`).
    static let entry: Animation = .easeOut(duration: Timing.entry)

    // MARK: - Haptic (Phase 7.6 Debug-Pass)

    /// **Leichtes Tap-Haptic** für wichtige Buttons. Nutzen nur CTAs
    /// und zentrale Auswahlaktionen — nicht jede Kleinigkeit, sonst
    /// vibriert das Gerät unangenehm oft.
    ///
    /// Intern ein `UIImpactFeedbackGenerator(.light)`; auf Geräten
    /// ohne Haptic-Engine (iPad) ist der Call ein No-Op.
    @MainActor
    static func triggerSelectionHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Button-Styles (systemweit wiederverwendbar)

/// **Standard-Tap-Feedback** für alle primären und sekundären
/// Buttons (CTAs, „Spiel starten", „Fertig", kleinere Aktionen).
///
/// Phase 7.6 Debug-Pass (User-Report „auf Gerät kaum sichtbar"):
/// deutlich stärkeres Feedback — Scale 0.95, Opacity 0.88,
/// leichter Brightness-Lift. Haptisches Feedback optional via
/// `hapticFeedback` init-Parameter (nur für Primär-CTAs, damit
/// Trivialaktionen nicht vibrieren).
///
/// Verwendung:
/// ```swift
/// Button { … } label: { … }
///     .buttonStyle(AppTapButtonStyle())           // normal
///     .buttonStyle(AppTapButtonStyle(haptic: true)) // Primär-CTA
/// ```
struct AppTapButtonStyle: ButtonStyle {
    var haptic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AppMotion.Scale.buttonPress : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(AppMotion.tap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if haptic && isPressed {
                    AppMotion.triggerSelectionHaptic()
                }
            }
    }
}

// `AppCardButtonStyle` lebt bewusst NICHT hier — der existierende
// `AppCardPressStyle` in `AppButtonStyles.swift` übernimmt diese
// Rolle und liest seine Konstanten (Scale 0.98, 100 ms Ease-Out)
// aus `AppMotion.Scale.cardPress` + `AppMotion.Timing.tapFeedback`.
// Damit gibt es **einen** Card-Press-Stil app-weit — kein Parallel-
// System. Aufruf: `.buttonStyle(AppCardPressStyle())`.

// MARK: - Entry-Transition (Fade + Slide-Up)

/// `ViewModifier` für **Staggered-Entry** beim Screen-Open —
/// Fade-In + 8 pt Slide-Up, Standard-Dauer 220 ms.
///
/// `delay` staffelt mehrere Elemente; empfohlene Stufen:
/// `0.00` → `0.05` → `0.10` → `0.15`. Mehr als 4 Stufen wirkt
/// sequenziell statt „lebendig" (User-Spec „keine langen Sequenzen").
private struct AppEntryTransition: ViewModifier {
    let delay: Double
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : AppMotion.Offset.entry)
            .onAppear {
                withAnimation(AppMotion.entry.delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    /// Blendet die View beim ersten Erscheinen per Fade + 8 pt
    /// Slide-Up ein. Mit `delay` lassen sich mehrere Elemente
    /// leicht staffeln (Stufen 0 / 0.05 / 0.10 / 0.15).
    ///
    /// ```swift
    /// header.appEntryTransition()                // 0 s Delay
    /// cards.appEntryTransition(delay: 0.05)
    /// actions.appEntryTransition(delay: 0.10)
    /// ```
    func appEntryTransition(delay: Double = 0) -> some View {
        modifier(AppEntryTransition(delay: delay))
    }
}

// MARK: - Auswahl-Feedback (Selection-Highlight)

/// `ViewModifier` für die **Auswahl-Animation** in Listen, Dropdowns
/// und Option-Cards: Highlight-Fade (via `.animation(AppMotion.state,
/// value: isSelected)`) + optionaler Scale-Pulse auf Selection-
/// Wechsel.
///
/// Verwendung:
/// ```swift
/// Row(...)
///     .appSelectionHighlight(isSelected: list.id == current)
/// ```
private struct AppSelectionHighlight: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(AppMotion.state, value: isSelected)
    }
}

extension View {
    /// Selection-Feedback: sanfter Scale-Pulse + Highlight-Fade,
    /// User-Spec „alte Auswahl verliert Highlight (Fade ~120 ms),
    /// neue Auswahl bekommt Highlight (Fade + minimal Scale)".
    func appSelectionHighlight(isSelected: Bool) -> some View {
        modifier(AppSelectionHighlight(isSelected: isSelected))
    }
}
