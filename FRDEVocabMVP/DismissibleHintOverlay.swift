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

/// Sprechblase mit Maskottchen-Avatar (oben/links) + Text + Dismiss-
/// Button (oben rechts). Style: `leaChatGlass`-Gradient als Background
/// (bestehender Glas-Look), `elumiBlue` als Info-Akzent (bewusst nicht
/// Warning-Farbe — der Hint ist eine freundliche Erklärung, keine
/// Warnung).
private struct DismissibleHintBubble: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)

            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(AppTheme.Colors.secondarySurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tipp schließen")
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppTheme.Gradients.leaChatGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Colors.elumiBlue.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: AppTheme.Colors.shadow, radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ViewModifier + API

private struct HintBubbleModifier: ViewModifier {
    let id: String
    let text: String
    let alignment: Alignment

    @ObservedObject private var store = HintStore.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if !store.hasSeen(id) {
                DismissibleHintBubble(text: text) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.markSeen(id)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                .padding(.horizontal, AppTheme.Spacing.sm)
            }
        }
    }
}

extension View {
    /// Hängt eine dismissible Sprechblase als Overlay an — erscheint
    /// nur, solange `id` noch nicht in `HintStore` als gesehen markiert
    /// ist. Persistiert über App-Neustarts hinweg.
    func hintBubble(id: String, text: String, alignment: Alignment = .top) -> some View {
        modifier(HintBubbleModifier(id: id, text: text, alignment: alignment))
    }
}
