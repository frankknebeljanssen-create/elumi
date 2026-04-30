import SwiftUI

/// **Einheitlicher Start-Screen für alle Spiele** (Phase 7.5 —
/// Start-Flow-Vereinheitlichung).
///
/// Ziel: Jeder Einstieg in ein Spiel (Elumi-Arcade, Word Runner, …)
/// zeigt zuerst **denselben Startscreen**. Kein Spiel darf mehr direkt
/// loslegen — der Spieler sieht immer erst Titel/Info/CTA.
///
/// Aufbau (laut Spec):
///   1. **Header** — Zurück-Button oben links (klassische Chevron).
///   2. **Hero** — großes Icon + Titel + kurze Subline.
///   3. **Game-Info-Block** — „+225 XP · ~3 min" (optional).
///   4. **Extra-Content-Slot** — spielspezifische Zusatz-UI
///      (z. B. Word-Runner-Listen-Picker oder Elumi-Credit-Anzeige).
///   5. **Primär-CTA** — großer Button „Spiel starten" (oder
///      parametrisierter Label/Icon wie „Lernen starten", wenn das
///      Spiel aus Credit-/Listen-Gründen nicht startbar ist).
///   6. **Hint** — optionaler kleiner Text unter dem CTA (z. B.
///      „Liste hat zu wenige Nomen" oder „0 Credits — Lernen bringt
///      Credits").
///
/// Die Komponente ist **view-agnostisch** — kein Wissen über
/// Game-Logik, Credits, Listen etc. Alles, was spielspezifisch ist,
/// kommt über den `extraContent`-Slot.
///
/// Präsenter-Kontrakt: Back-Button ruft `onBack` auf, Primär-CTA
/// ruft `onPrimaryCTA` auf. Das Präsenter-View (z. B.
/// `WordRunnerGameView.idleStartScreen`) entscheidet dort, was
/// genau passiert (Run starten, Credit abziehen, etc.).
struct GameStartScreen<IconContent: View, ExtraContent: View>: View {

    // MARK: - Inhalt

    let title: String
    /// Kurze Subline unter dem Titel. `nil` → wird ausgeblendet
    /// (Layout-Variante ohne Subline, User-Spec Phase 7.5).
    let subline: String?
    /// Game-Info (z. B. „+225 XP · ~3 min"). `nil` → Info-Block
    /// wird ausgeblendet.
    let infoLine: String?
    /// Primär-CTA-Label (Default „Spiel starten").
    let primaryCTALabel: String
    /// SF-Symbol-Icon im Primär-CTA (Default „play.fill").
    let primaryCTAIcon: String
    /// Wenn `false`: Button ist disabled + ausgegraut. Der Hint
    /// darunter erklärt warum.
    let primaryCTAEnabled: Bool
    /// Optionaler Hinweis-Text unter dem CTA — z. B.
    /// „0 Credits — Lernen bringt Credits" oder „Liste hat keine
    /// Nomen".
    let hint: String?

    // MARK: - Callbacks

    let onPrimaryCTA: () -> Void
    let onBack: () -> Void

    // MARK: - Slots

    let iconContent: IconContent
    let extraContent: ExtraContent

    init(
        title: String,
        subline: String? = nil,
        infoLine: String? = nil,
        primaryCTALabel: String = "Spiel starten",
        primaryCTAIcon: String = "play.fill",
        primaryCTAEnabled: Bool = true,
        hint: String? = nil,
        onPrimaryCTA: @escaping () -> Void,
        onBack: @escaping () -> Void,
        @ViewBuilder icon: () -> IconContent,
        @ViewBuilder extraContent: () -> ExtraContent = { EmptyView() }
    ) {
        self.title = title
        self.subline = subline
        self.infoLine = infoLine
        self.primaryCTALabel = primaryCTALabel
        self.primaryCTAIcon = primaryCTAIcon
        self.primaryCTAEnabled = primaryCTAEnabled
        self.hint = hint
        self.onPrimaryCTA = onPrimaryCTA
        self.onBack = onBack
        self.iconContent = icon()
        self.extraContent = extraContent()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmer Backdrop — klassischer Game-Overlay-Look.
            Color.black.opacity(0.55).ignoresSafeArea()

            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    // **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)**:
                    // Die Spacer-content-Spacer-Centering basierte auf
                    // `geo.size.height`, das die volle Container-Höhe
                    // inkl. Footer-Bereich zurückgab. Dadurch landeten
                    // die Inhalte (Character + Title + Cards + CTA)
                    // visuell im unteren Drittel statt zentriert,
                    // weil der Footer ~110pt am unteren Bildrand
                    // belegt aber nicht aus dem Centering-Frame
                    // herausgerechnet wurde. Plus eine kleine Top-
                    // Reserve fürs Back-Chevron-Overlay (~60pt). User-
                    // Report: „Elumi Spiel start screen ist nicht
                    // zentriert, fixen; word runner auch nicht".
                    let footerOffset = AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom
                    let topReserve: CGFloat = 60
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content
                        Spacer(minLength: 0)
                    }
                    .frame(
                        minHeight: max(0, geo.size.height - footerOffset - topReserve),
                        alignment: .center
                    )
                    .padding(.top, topReserve)
                    .padding(.bottom, footerOffset)
                }
            }
        }
        .overlay(alignment: .topLeading) { backButton }
    }

    // MARK: - Teile

    private var content: some View {
        VStack(spacing: 16) {
            // **Staggered Entry** (Phase 7.6 Rollout) — jedes Element
            // bekommt eine kleine Delay-Stufe (je +50 ms), sodass der
            // Screen „von oben nach unten" aufbaut. User-Spec:
            // „Header → Cards → Aktionen gestaffelt".
            iconContent
                .frame(width: 78, height: 78)
                .appEntryTransition()

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let subline = subline {
                    Text(subline)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .appEntryTransition(delay: 0.05)

            if let info = infoLine {
                Text(info)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                            )
                    )
                    .appEntryTransition(delay: 0.08)
            }

            // Spielspezifische UI (List-Picker, Credit-Anzeige, …).
            // **WICHTIG**: KEINE `appEntryTransition` hier — der
            // `extraContent` enthält interaktive Cards (Dropdown-
            // Button für List-Picker). Die Entry-Animation nutzt
            // Opacity-Interpolation, die in SwiftUI auf manchen iOS-
            // Versionen während der Animation Taps schlucken kann.
            // Der globale Entry-Fade des Hosts (WR/Arcade-View)
            // animiert das Overlay als Ganzes — reicht.
            extraContent

            primaryCTA

            if let hint = hint {
                Text(hint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
    }

    private var primaryCTA: some View {
        Button(action: onPrimaryCTA) {
            HStack(spacing: 10) {
                Image(systemName: primaryCTAIcon)
                    .font(.system(size: 15, weight: .bold))
                Text(primaryCTALabel)
                    .font(.system(size: 17, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(
                    primaryCTAEnabled
                        ? AppTheme.Colors.elumiPink
                        : AppTheme.Colors.elumiPink.opacity(0.35)
                )
            )
            .shadow(
                color: AppTheme.Colors.elumiPink.opacity(primaryCTAEnabled ? 0.35 : 0),
                radius: 10, x: 0, y: 6
            )
        }
        // **Systemweiter CTA-Press-Feedback** — `AppTapButtonStyle`
        // aus `AppMotion.swift`. Scale 0.95 + Opacity-Drop +
        // Brightness-Dip + leichtes Tap-Haptic (Primär-CTA!) —
        // deutliches, multisensorisches Press-Feedback.
        .buttonStyle(AppTapButtonStyle(haptic: true))
        .disabled(!primaryCTAEnabled)
    }

    /// Systemweiter `AppBackButton` — identisch zu dem in GameHub
    /// / Trophy / Lists etc.: schlanker Chevron ohne Pill, 44 × 44
    /// Touch-Area, Primär-Tint. Auf unserem dunklen Overlay nutzen
    /// wir `.white` als Tint für ausreichenden Kontrast.
    ///
    /// Position 62 pt Top entspricht der visuellen Y-Höhe, die
    /// SwiftUI bei NavigationStack-Screens (Safe-Area 54 pt +
    /// Spacing.sm 8 pt) rendert — damit sitzt der Chevron hier an
    /// derselben Höhe wie bei SPIELEN und FORTSCHRITT.
    private var backButton: some View {
        AppBackButton(action: onBack, tint: .white)
            .padding(.leading, AppTheme.Spacing.xs)
            .padding(.top, 62)
    }
}

// `GameStartCTAButtonStyle` ist in das systemweite `AppTapButtonStyle`
// (siehe `AppMotion.swift`) gewandert. Dieser Shell-File enthält den
// Stil nicht mehr lokal — Single Source of Truth lebt zentral.
