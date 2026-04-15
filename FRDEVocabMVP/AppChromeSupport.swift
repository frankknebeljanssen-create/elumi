import SwiftUI
import UIKit

enum AppLayout {
    static let screenPadding: CGFloat = AppTheme.Layout.screenPadding
    static let cardCornerRadius: CGFloat = AppTheme.Radius.lg
    static let largeCardCornerRadius: CGFloat = AppTheme.Radius.xl
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

    /// App-weite Obergrenze für Mehrfachauswahl von Vokabel-Listen
    /// (Training, Flashcards, Verbformen). Mehr als 5 würden in den Card-Layouts
    /// (Listen-Übersicht in der Setup-Card) den Bildschirm sprengen.
    /// Hinweis: Limit auf 6 statt 5 gesetzt, damit auch nach internen Aggregate-
    /// Removal-Schritten garantiert 5 Listen wählbar sind.
    static let maxSelectableLists: Int = 6
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
