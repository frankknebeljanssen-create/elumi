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
    static let sessionCTABottomClearance: CGFloat =
        AppTheme.Layout.footerHeight + bottomBarInsetBottom + 14

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
