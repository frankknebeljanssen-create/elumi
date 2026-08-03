// DismissibleHintOverlay.swift
// **2026-06-09** — Wiederverwendbarer Dismissible-Hint-Baustein für
// Erstnutzer, die die App ohne begleiteten Onboarding-Flow allein
// durchklicken (TestFlight-Vorbereitung). Additive Sprechblasen-Overlays
// auf bestehenden Screens — kein Onboarding-Flow, keine Screen-Logik
// wird angefasst.
//
// Audit-Befund: kein bestehender Tooltip-/Coachmark-Mechanismus in der
// App (nur `ElumiHints` = Zufalls-Textpool ohne Dismiss-Persistenz,
// `ChatNewWordTooltipView` = Léa-Chat-spezifisch). Dieser Baustein ist
// komplett neu.
//
// Persistenz: `HintStore` hält gesehene Hint-IDs in UserDefaults (Set,
// als Array serialisiert — `@AppStorage` unterstützt `Set<String>` nicht
// direkt als RawRepresentable). Ein Hint mit gegebener ID erscheint nur,
// solange seine ID noch nicht im Set ist.
//
// Verwendung:
//   SomeView(...)
//       .hintBubble(id: "home_intro", text: "...", alignment: .top)

import SwiftUI

// MARK: - HintStore

/// Zentraler Speicher für gesehene Hint-IDs. Singleton, analog zu
/// `ProgressStore.shared` / `PersonalDeckStore.shared` — ein Store pro
/// App-Lifetime, kein Dependency-Injection-Aufwand für einen so kleinen
/// State.
@MainActor
final class HintStore: ObservableObject {
    static let shared = HintStore()

    private static let storageKey = "com.frank.FRDEVocabMVP.seenHintIDs"

    @Published private(set) var seenHintIDs: Set<String>

    private init() {
        seenHintIDs = Set(UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? [])
    }

    func hasSeen(_ id: String) -> Bool {
        seenHintIDs.contains(id)
    }

    func markSeen(_ id: String) {
        guard seenHintIDs.insert(id).inserted else { return }
        persist()
    }

    /// Setzt alle Hints zurück — genutzt vom Settings-„Tipps erneut
    /// anzeigen"-Reset zum wiederholten Testen.
    func resetAll() {
        guard !seenHintIDs.isEmpty else { return }
        seenHintIDs.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(seenHintIDs), forKey: Self.storageKey)
    }
}

// MARK: - Bubble-View

/// Sprechblase mit Maskottchen-Avatar (links) + Text + Dismiss-Button
/// (oben rechts). Style: solider, bläulich getönter Hintergrund
/// (`secondarySurface` + `elumiBlue`-Tint — bewusst deutlich anders als
/// der flache Screen-Hintergrund, damit die Box klar als eigenes
/// Element „aufpoppt"), `elumiBlue` als Info-Akzent (bewusst nicht
/// Warning-Farbe — der Hint ist eine freundliche Erklärung).
///
/// **2026-06-09** — Box vergrößert (mehr vertikaler Innenraum + Min-
/// Höhe), Hintergrund vom flachen `secondarySurface` auf einen
/// blau-getönten Ton gebracht (User-Spec „andere Farbe, nicht wie der
/// Screen").
private struct DismissibleHintBubble: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)

            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppTheme.Colors.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tipp schließen")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 132)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(AppTheme.Colors.elumiBlue.opacity(0.16))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Colors.elumiBlue.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: AppTheme.Colors.shadow, radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ViewModifier + API

private struct HintBubbleModifier: ViewModifier {
    let id: String
    let text: String

    @ObservedObject private var store = HintStore.shared

    func body(content: Content) -> some View {
        // **2026-06-09** — Der Hint wird als Screen-Root-Overlay
        // eingehängt (siehe Aufruf-Seite), damit der Dim-Scrim den
        // GESAMTEN Bildschirm abdeckt. Während ein Hint sichtbar ist,
        // wird alles dahinter abgedunkelt; die Box sitzt zentriert
        // darauf. Tap auf den Scrim schließt den Hint ebenfalls.
        content.overlay {
            if !store.hasSeen(id) {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss() }

                    DismissibleHintBubble(text: text, onDismiss: dismiss)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                }
                .transition(.opacity)
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            store.markSeen(id)
        }
    }
}

extension View {
    /// Hängt einen dismissiblen Hint als Screen-Root-Overlay an —
    /// erscheint nur, solange `id` noch nicht in `HintStore` als gesehen
    /// markiert ist, dunkelt den Screen dahinter ab und zeigt die
    /// zentrierte Sprechblase. Persistiert über App-Neustarts hinweg.
    ///
    /// **Wichtig:** Am Screen-Root einhängen (nicht an einer inneren
    /// Anker-View), damit der Dim-Scrim den ganzen Bildschirm abdeckt.
    func hintBubble(id: String, text: String) -> some View {
        modifier(HintBubbleModifier(id: id, text: text))
    }
}
