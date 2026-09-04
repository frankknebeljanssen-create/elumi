import SwiftUI

/// **2026-05-04 Footer-Action-Bridge im Sheet-Kontext.**
///
/// Hintergrund: Picker-Sheets (`ListPickerSheet`,
/// `ChainListSelectionSheet`) rendern
/// einen eigenen `AppBottomBar` über `appLocalChrome`, damit der User
/// nicht das Gefühl hat „Tab-Bar weg" (siehe Punkt 1, 2026-05-04).
/// Aber die Footer-Buttons mit Environment-basierten Actions —
/// `ElumiFooterFeastButton` (Axolotl) liest `appOpenElumiAction`,
/// `AppBottomBar.resolvedScanAction` fällt auf `appOpenLexiconAction`
/// zurück — würden beim Tap auf der **parent**-Navigation laufen, die
/// hinter dem Sheet liegt. Folge: User tippt Elumi/Wörterbuch im Sheet,
/// nichts passiert sichtbar, weil das Push hinter dem Sheet unsichtbar
/// stattfindet.
///
/// Dieser Modifier wraps die Environment-Actions: vor jedem Original-
/// Aufruf wird `dismiss()` ausgelöst → Sheet schließt → Original-
/// Action navigiert sichtbar im parent-Stack.
///
/// Anwendung: auf den `AppBottomBar` im Sheet, mit dem `dismiss`-
/// Handle des Sheets als Param. Beispiel:
///
/// ```swift
/// @Environment(\.dismiss) private var dismiss
///
/// AppBottomBar(...)
///     .dismissingFooterActions(dismiss)
/// ```
///
/// Pure-Pass-Through für Actions die nil sind — verändert nichts an
/// nicht-gesetzten Footer-Pfaden.
struct DismissingFooterActionsModifier: ViewModifier {
    let dismiss: DismissAction

    @Environment(\.appOpenElumiAction) private var parentOpenElumi
    @Environment(\.appOpenLexiconAction) private var parentOpenLexicon
    @Environment(\.appOpenScanAction) private var parentOpenScan
    @Environment(\.appOpenArcadeAction) private var parentOpenArcade
    @Environment(\.appOpenGameHubAction) private var parentOpenGameHub
    @Environment(\.appOpenTrophyAction) private var parentOpenTrophy

    func body(content: Content) -> some View {
        content
            .environment(\.appOpenElumiAction, wrap(parentOpenElumi))
            .environment(\.appOpenLexiconAction, wrap(parentOpenLexicon))
            .environment(\.appOpenScanAction, wrap(parentOpenScan))
            .environment(\.appOpenArcadeAction, wrapBool(parentOpenArcade))
            .environment(\.appOpenGameHubAction, wrap(parentOpenGameHub))
            .environment(\.appOpenTrophyAction, wrap(parentOpenTrophy))
    }

    private func wrap(_ action: (() -> Void)?) -> (() -> Void)? {
        guard let action else { return nil }
        let dismissAction = dismiss
        return {
            dismissAction()
            action()
        }
    }

    private func wrapBool(_ action: ((Bool) -> Void)?) -> ((Bool) -> Void)? {
        guard let action else { return nil }
        let dismissAction = dismiss
        return { flag in
            dismissAction()
            action(flag)
        }
    }
}

extension View {
    /// Wrappt die globalen Footer-Action-Environments
    /// (`appOpenElumiAction`, `appOpenLexiconAction`, `appOpenScanAction`,
    /// `appOpenArcadeAction`) so dass jeder Tap zuerst `dismiss()`
    /// auslöst. Anzuwenden auf den `AppBottomBar` in Sheets, damit
    /// Footer-Buttons im Sheet-Kontext die parent-Navigation sichtbar
    /// triggern.
    func dismissingFooterActions(_ dismiss: DismissAction) -> some View {
        modifier(DismissingFooterActionsModifier(dismiss: dismiss))
    }
}
