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
///
/// **2026-06-09 Lesbarkeits-Pass** — Kinder als Hauptzielgruppe:
/// Box nochmal vertikal vergrößert, und der Text wird pro Satz in
/// einen eigenen Block gerendert (die Aufrufer setzen `\n` zwischen
/// den Sätzen). Der Abstand zwischen den Sätzen ist dabei größer als
/// der innerhalb eines Satzes, sodass die Struktur auch bei langen,
/// selbst umbrechenden Sätzen erkennbar bleibt.
///
/// **2026-06-09 CI-Angleichung** — Die Bubble sah neben dem
/// `WelcomeScreen` nach Fremdkörper aus. Jetzt dieselbe Bildsprache:
/// Maskottchen groß und oben mittig (statt klein links), gleiche
/// Card-Geometrie und Border wie die Feature-Cards im Welcome, und
/// ein echter CTA-Button unten statt des X-Kreuzes oben rechts.
///
/// Bewusst KEIN Vollbild: drei der Hints verweisen wörtlich auf
/// Elemente, die auf dem Screen sichtbar sind („unter Basics…",
/// „Schau kurz drüber"). Ein Vollbild-Screen würde genau das
/// verdecken, worauf der Text zeigt.
private struct DismissibleHintBubble: View {
    let text: String
    let onDismiss: () -> Void

    /// Der übergebene Text, aufgeteilt in seine Sätze — die Aufrufer
    /// setzen pro Satz einen Zeilenumbruch. Leerzeilen werden
    /// verworfen, damit ein versehentlicher Doppel-Umbruch keine
    /// Lücke erzeugt.
    private var sentences: [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Maskottchen groß + mittig — identische Behandlung wie im
            // WelcomeScreen (Blink-Overlay, gleicher Shadow), nur
            // kleiner skaliert.
            ZStack {
                Image("SplashCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                SplashCharacterBlinkOverlay(size: 88, startDate: .now)
                    .frame(width: 88, height: 88)
            }
            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)

            // Jeder Satz (= eine Zeile im übergebenen Text) wird als
            // eigener Block gerendert. Der Abstand ZWISCHEN den Sätzen
            // (VStack-spacing) ist größer als der Zeilenabstand
            // INNERHALB eines Satzes (`lineSpacing`) — dadurch bleibt
            // die Satz-Struktur auch dann sichtbar, wenn ein langer
            // Satz selbst über mehrere Zeilen umbricht.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                    Text(sentence)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Echter CTA statt X-Kreuz — gleiche Geste wie „Los geht's!"
            // im WelcomeScreen, nur in Info-Blau statt CTA-Amber, damit
            // der Hint nicht wie eine Hauptaktion wirkt.
            Button(action: onDismiss) {
                Text("Alles klar!")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.elumiBlue))
            .accessibilityLabel("Tipp schließen")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
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
    /// **2026-06-09** — Optionaler Callback, der NACH dem Markieren als
    /// „gesehen" feuert. Aufrufer nutzen das, um etwas, das sonst
    /// gleichzeitig mit dem Hint erscheinen würde (z. B. ein Setup-
    /// Modal), erst danach zu zeigen — sonst überlappen sich Hint und
    /// Folge-UI beim allerersten Öffnen.
    var onDismiss: (() -> Void)? = nil

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
                    // **2026-06-09** — 0.55 → 0.78. Bei 55 % blieb der
                    // Screen dahinter so präsent, dass die Bubble nicht
                    // klar als eigene Ebene las. Dunkler heißt: der
                    // Kontext bleibt erahnbar (deshalb kein Vollbild),
                    // aber der Fokus liegt eindeutig auf dem Hint.
                    Color.black.opacity(0.78)
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
        onDismiss?()
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
    ///
    /// `onDismiss` (optional) feuert, sobald der Hint geschlossen wird
    /// (Tap auf CTA oder Backdrop) — für Aufrufer, die eine Folge-UI
    /// erst NACH dem Hint zeigen wollen, statt beide gleichzeitig.
    func hintBubble(id: String, text: String, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(HintBubbleModifier(id: id, text: text, onDismiss: onDismiss))
    }
}
