import SwiftUI
import UIKit

enum AppLayout {
    static let screenPadding: CGFloat = AppTheme.Layout.screenPadding
    // Card-Radien reduziert: ruhigeres Erscheinungsbild systemweit.
    // Cards = 14pt, kleine Elemente = 10pt (siehe AppTheme.Radius).
    static let cardCornerRadius: CGFloat = AppTheme.Radius.md
    static let largeCardCornerRadius: CGFloat = AppTheme.Radius.md
    static let largeSelectionHeight: CGFloat = AppTheme.Layout.selectionHeight
    static let homeCardHeight: CGFloat = AppTheme.Layout.homeCardHeight
    static let homeWideCardHeight: CGFloat = AppTheme.Layout.wideCardHeight
    static let primaryButtonHeight: CGFloat = AppTheme.Layout.buttonHeight
    static let headerHeight: CGFloat = AppTheme.Layout.headerHeight
    static let topBarHeight: CGFloat = AppTheme.Layout.chromeBarHeight
    static let ctaMaxWidth: CGFloat = 320
    static let topBarInsetTop: CGFloat = AppTheme.Spacing.sm
    static let bottomBarInsetBottom: CGFloat = AppTheme.Spacing.xs
    static let contentTopPadding: CGFloat = AppTheme.Spacing.xl

    /// **Systemweites Bottom-Padding** unter jedem Screen-Header
    /// (AppTopBar, ScreenHeaderCard, SessionSetupHeader, Training-Header).
    /// Garantiert, dass der erste Content-Block in **jedem** Screen im
    /// gleichen Abstand unterhalb der Header-Zeile beginnt.
    ///
    /// Ändern → alle Header springen gemeinsam. Keine Local-Overrides.
    static let screenHeaderBottomPadding: CGFloat = 16

    /// **Systemweites Top-Padding** vor dem Header-Block eines Screens.
    /// Referenz ist die Quiz-/Session-Setup-Position: der Header sitzt
    /// direkt am Screen-Top und hat intern nur 4 pt Atemraum zum Safe-
    /// Area-Rand. Diese Konstante ersetzt `contentTopPadding` als
    /// Top-Padding für Screens, die mit einem ScreenHeader-Block
    /// beginnen — dadurch sitzen Header auf **jedem** Screen auf der
    /// gleichen vertikalen Position.
    static let screenHeaderTopPadding: CGFloat = 4

    /// **Systemweites Top-Padding für die Chevron-Row** (Push-Screen-
    /// Header). Referenz ist `TrainingHubView`: dort sitzt die Back-
    /// Chevron-HStack direkt am Safe-Area-Top, ohne eigenes Top-Padding.
    /// Alle anderen Push-Screens (Setup-Screens, Lexicon, Trophy,
    /// GameHub, Settings, Lists) richten sich daran aus — Chevron sitzt
    /// auf systemweit identischer y-Position.
    ///
    /// Bewusst **getrennt** von `screenHeaderTopPadding`: letzteres
    /// regelt den Abstand zwischen Chevron-Row und dem Content darunter
    /// (bzw. ScrollView-Innenabstand), ist also ein Content-Spacing-
    /// Token. `headerChevronTopPadding` ist dagegen die y-Position des
    /// Chevron-Frames selbst.
    static let headerChevronTopPadding: CGFloat = 0

    /// **Systemweite Corner-Radius für Primary-CTAs und die Gamification-
    /// Bar** darüber — beide sollen identisch aussehen und dieselbe
    /// Rundung wie die anderen Home-/Setup-Cards (Progress-Board,
    /// Fokus-Card …) haben.
    static let sessionCTARadius: CGFloat = 16

    /// **Systemweites Bottom-Padding** unter dem Primary-CTA bis zum
    /// Footer. Vorlage: Karteikarten-Setup. Wird in
    /// `SessionSetupScreen` (Karteikarten, Quiz, Training-Setup) und
    /// in Session-eigenen CTAs (Flashcards-Setup-CTA etc.) genutzt —
    /// damit der Abstand zwischen CTA und Footer auf **jedem** Screen
    /// exakt identisch ist.
    ///
    /// **2026-05-08** — Wert von `footerHeight + bottomBarInsetBottom + 14`
    /// auf `14` reduziert. Nach der Footer-Migration zu
    /// `.safeAreaInset(.bottom)` (Commit c941ef9) reserviert die
    /// systemweite Safe-Area die Footer-Höhe automatisch; das alte
    /// Manual-Footer-Reservierungs-Pattern verdoppelte das Padding
    /// und schob den CTA visuell deutlich nach oben (User-Befund:
    /// „Setup-Screens sehen nach unten gerutscht aus"). Der verbleibende
    /// 14-pt-Wert ist reiner CTA→Footer-Atemraum.
    static let sessionCTABottomClearance: CGFloat = 14

    /// **Systemweites Horizontal-Padding** für CTA + Gamification-Bar.
    /// Garantiert, dass die Bar exakt dieselbe Breite wie der CTA
    /// darunter hat.
    static let sessionCTAHorizontalPadding: CGFloat = 16

    /// **Systemweites vertikales Padding zwischen der „Ausgewählte Listen"-
    /// Card und der direkt darunter sitzenden Richtungs-Zeile** — in
    /// jedem Session-Setup-Screen (Karteikarten, Quiz, Nomen, Artikel,
    /// Verben, Verbformen, Vokabeln).
    ///
    /// Single Source of Truth: wird hier geändert, springt der Abstand
    /// **synchron** in allen Modulen. `SessionSetupScreen` nutzt den Wert
    /// als VStack-Spacing (gilt damit auch zwischen Richtung und Options-
    /// Slot), modul-eigene Setup-Screens (z. B. Karteikarten) wenden ihn
    /// explizit als Top-Padding auf `SessionDirectionRow` an.
    static let sessionContextToDirectionSpacing: CGFloat = 20

    /// App-weite Obergrenze für Mehrfachauswahl von Vokabel-Listen
    /// App-weites Limit für gleichzeitig ausgewählte Listen — gilt für Training,
    /// Karteikarten, Quiz und Verbformen. Mehr als 3 Listen verwirren in der
    /// Praxis das Lernen (zu großer Misch-Pool). Single Source of Truth: alle
    /// Picker prüfen gegen diesen Wert, alle Card-Übersichten verwenden ihn
    /// als `prefix`-Limit.
    static let maxSelectableLists: Int = 3

    // MARK: - Setup-Screen Vertical Rhythm
    //
    // Systemweite Spacing-Tokens für Modul-Setup-Screens (Karteikarten,
    // Quiz, Training, Akzente, Vokabeln, Verbformen). Alle Setup-Screens
    // nutzen dieselben Block-Abstände — Änderungen an einer Stelle
    // springen über alle Module synchron durch. Keine Local-Overrides.
    //
    // Rhythmus (von oben nach unten):
    //   Header → Ausgewählte Listen → Sprachrichtung → Hauptblock →
    //   Detail-Block → Gamification-Bar → CTA
    //
    // - `sessionContextToDirectionSpacing` existiert bereits oben
    //   (Listen ↔ Sprachrichtung, 20 pt).
    // - `setupMainSectionSpacing`: Abstand zwischen den Haupt-Blöcken
    //   (Sprachrichtung → Hauptblock → Detail → Gamification). Wert =
    //   `AppTheme.Spacing.md` (16 pt).
    // - `setupDetailBlockSpacing`: enger interner Abstand zwischen
    //   Detail-Unter-Sektionen (z. B. zwei Parameter-Cards untereinander).
    //   Wert = `AppTheme.Spacing.sm` (12 pt).
    // - `setupHeadlineToContentSpacing`: Abstand zwischen einer Section-
    //   Headline (z. B. „Was möchtest du machen?") und ihrem Content.
    //   Wert = 10 pt (der in den Drill-Modulen bereits in Benutzung ist).
    // - `gamificationBarToCTASpacing`: Abstand Gamification-Bar → CTA.
    //   Wird vom SessionSetupScreen gerendert; kompakt, damit die beiden
    //   als Card-Duo gelesen werden. Wert = 10 pt.

    static let setupMainSectionSpacing: CGFloat = AppTheme.Spacing.md
    static let setupDetailBlockSpacing: CGFloat = AppTheme.Spacing.sm
    static let setupHeadlineToContentSpacing: CGFloat = 10
    static let gamificationBarToCTASpacing: CGFloat = 10
}

// MARK: - Debug Logging
//
// **Sweep 2 — B3 (2026-05-07)**: Production-Print-Statements in
// DEBUG-only-Pfaden konsolidiert. Statt jeden `print(...)`-Call mit
// `#if DEBUG / #endif` zu umrahmen (75+ Stellen in 25+ Dateien),
// gibt es **eine** zentrale Helper-Funktion mit interner Compile-Time-
// Guard. Effekt ist identisch:
//   • Debug-Build: Helper ruft `Swift.print(...)` durch, Logs sichtbar
//   • Release-Build: Funktionsbody ist leer, der Compiler eliminiert
//     den Call komplett (`@inlinable` + leere Implementation)
//
// Aufrufe wurden via `print(` → `appDebugLog(` ersetzt. Die Signatur
// matched `Swift.print` 1:1, damit die Replace mechanisch ohne Argument-
// Anpassung funktionierte.
//
// **Wichtig**: Diese Helper-Definition selbst nutzt `Swift.print(...)`
// (qualifiziert), damit sie nicht versehentlich in Endlosrekursion
// mit sich selbst landet, wenn der Modul-Namespace anders aufgelöst
// wird.
@inlinable
func appDebugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(output, terminator: terminator)
    #endif
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissBackgroundView())
    }

    func appAmbientWormBackground(_ style: AppSectionStyle, enabled: Bool = true) -> some View {
        background {
            AppTheme.Colors.surface
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    func appLocalChrome<TopBar: View, BottomBar: View>(
        enabled: Bool,
        @ViewBuilder topBar: () -> TopBar,
        @ViewBuilder bottomBar: () -> BottomBar
    ) -> some View {
        if enabled {
            self
                .safeAreaInset(edge: .bottom) {
                    bottomBar()
                }
        } else {
            self
        }
    }
}

private struct KeyboardDismissBackgroundView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var currentView = touch.view
            while let view = currentView {
                if view is UITextField || view is UITextView {
                    return false
                }
                currentView = view.superview
            }
            return true
        }
    }
}
