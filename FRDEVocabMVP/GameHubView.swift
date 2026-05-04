import SwiftUI

/// Game Hub — Phase 4 der Gamification-Architektur.
///
/// Rolle im System (bewusste Trennung zu Home und Progress Hub):
///   • Home        → „Wie läuft's?"  (kompakter Überblick + Motivation)
///   • Progress    → „Wo stehe ich?" (vollständiger Fortschritt)
///   • **Game Hub** → „Was bekomme ich dafür?"  (**Reward nutzen + Spiel starten**)
///
/// Der Screen zeigt in genau drei Zonen:
///   1) Hero — Credits als visuell dominante Zahl + Kontext-Zeile
///   2) CTA — *einer* großer Button „Spiel starten" (bzw. Empty-State-CTA)
///   3) Lern→Reward-Hinweis — wie Credits entstehen
///
/// Bewusst *nicht* enthalten:
///   • ausführliche Fortschrittsinfos (die leben im Progress Hub)
///   • mehrere Startbuttons / konkurrierende Aktionen
///   • Bonus-Runden-Mechanik, Highscore-Listen, Daily-Reward-UI — sind
///     als leere Slots mental vorbereitet, aber hier **noch nicht** gebaut.
struct GameHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @Environment(\.appOpenArcadeAction) private var openArcade
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0
    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    /// Optional — wird vom AppDestinationHost durchgereicht. Nur
    /// nötig für den Word-Runner-DEBUG-Eintrag (Live-Tasks aus
    /// echter Liste); GameHub selbst zeigt keine Listen-Daten.
    var listStore: VocabularyListStore? = nil
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    /// Navigations-Router, vom AppDestinationHost durchgereicht.
    /// Aktuell nur genutzt, um aus dem Word-Runner-Empty-State direkt
    /// auf die Listen-Auswahl zu springen (Cover schließen + push).
    var navigate: ((AppScreen) -> Void)? = nil

    // MARK: - Word-Runner-Entry (Phase 7.5)
    //
    // Word Runner wird jetzt als **echte Nav-Destination** gepusht —
    // analog zur Arcade. Kein FullScreenCover mehr, damit der globale
    // Footer während des Start-Screens sichtbar bleibt (User-Wunsch:
    // „footer im start screen von wordrunner muss sichtbar sein").

    private let sectionStyle: AppSectionStyle = .hearts
    private let livesPerCredit = 4   // sichtbare Credit → Leben Zuordnung
    private let xpPerCredit = ArcadeCreditSystem.xpPerCredit  // 20 XP = 1 Credit (Live-Wert)

    /// **Quick-Fix 2026-04-30 (`v2-unify-game-tile-disabled`)** — wenn der
    /// User auf eine disabled Game-Tile tippt, erscheint dieser Alert mit
    /// Single-OK-CTA. Vorher: Elumi-Tile war disabled (Tap = no-op),
    /// Word-Runner-Tile war fälschlich antippbar (kostet aber 1 Credit
    /// beim Spielstart → User wurde überrascht). Mit dem Fix: beide
    /// Tiles disabled bei 0 Credits, Tap zeigt expliziten Hinweis.
    @State private var showNoTicketsAlert: Bool = false

    // MARK: - Derived

    private var hasCredits: Bool {
        arcadeCredits >= ArcadeCreditSystem.gamesCost
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Spacing `.md` statt `.lg` → insgesamt kompakter, damit
            // Hero + beide Start-Buttons + Reward-Explainer ohne
            // Scrollen auf den Screen passen (User-Spec).
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                // **Einheitlicher Modul-Header** (User-Spec): Back-
                // Chevron oben + farbige `ModuleHeaderCard` mit Game-
                // Controller-Icon und Titel „Spielen" — analog zu
                // allen anderen Modulen (Karteikarten, Quiz …). Das
                // alte schlichte `hubHeader` (nur Text) ist entfallen.
                ModuleHeaderCard(
                    systemImage: "gamecontroller.fill",
                    title: "Spielen",
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )
                heroBlock
                // Zwei gleichwertige Start-Buttons (Elumi + Word Runner)
                // direkt unter dem Hero — oben Auswahl, dann Start.
                // Die frühere separate Word-Runner-Dev-Shortcut-Card
                // ganz unten ist damit entfallen.
                gameStartButtons
                rewardExplainerBlock
                    // **2026-05-04 Polish-Follow-up** — Reward-Explainer
                    // mit zusätzlichem Top-Padding etwas weiter runter
                    // gerückt. Trennt visuell Game-Aktion oben von
                    // „so verdienst du Spiele"-Erklärung darunter.
                    .padding(.top, AppTheme.Spacing.lg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            // Top-Padding angeglichen an alle anderen Module
            // (Wörterbuch, Nomen, Training …): `screenHeaderTopPadding`
            // (= 4 pt) statt `contentTopPadding` (= Spacing.xl). Vorher
            // saß der Spielen-Header sichtbar tiefer als die anderen
            // Screens — jetzt auf gleicher Linie.
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        // **Quick-Fix 2026-04-30 (`v2-unify-game-tile-disabled`)** —
        // Acknowledge-Alert für disabled Game-Tile-Tap. Single-OK-CTA,
        // kein Cancel: User soll nur informiert werden, dass er Tickets
        // verdienen muss. Wording konsistent zum Empty-State-Text unter
        // den Tiles („Trainingsgenerator" als App-eigene Bezeichnung
        // statt „Slot drehen").
        .alert("Keine Tickets", isPresented: $showNoTicketsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Du hast aktuell keine Tickets. Verdiene welche durchs Lernen oder durch den Trainingsgenerator.")
        }
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() },
                isHeartsActive: true
            )
        }
    }

    // Alter `hubHeader` (nur „Spielen"-Text) raus — die farbige
    // `ModuleHeaderCard` oben trägt jetzt Back-Chevron + Icon + Titel
    // im systemweit einheitlichen Stil.

    // MARK: - Hero Block

    /// Großer Spiele-Stand als visueller Anker. Keine Navigation, keine
    /// sekundären Aktionen in diesem Block — er ist die **Identität**
    /// des Screens: „Du hast X Spiele verdient."
    ///
    /// Wortschatz-Harmonisierung (User-Request „Footer-Icon-Semantik"):
    /// Footer-Badge, Hero-Label und Session-End nennen alle dasselbe
    /// „Spiele"-Konzept — `arcadeCredits` ist technisch weiterhin
    /// „Credits" (DB-Key), für den User aber durchgängig „Spiele".
    /// `gamesCost == 1` → Credits = Spiele, daher direkt übertragbar.
    private var heroBlock: some View {
        // **2026-05-04 Polish** — Card aufgeräumt:
        //   • Wasserfloh-Asset → `SplashCharacter` (Elumi-Maskottchen
        //     wie es im Arcade-Spiel für die 4-Leben-Row verwendet wird,
        //     siehe `ElumiArcadeGameView+Overlays.swift:336`).
        //   • Sparkles-Row „Verdient durch Lernen" entfernt — redundant
        //     zum `rewardExplainerBlock` weiter unten, der das im Detail
        //     erklärt.
        //   • Eine zentrale Meta-Row reicht jetzt; Layout wirkt ruhiger.
        VStack(spacing: 10) {
            // **2026-05-04 Polish-Follow-up** — Beide Zeilen horizontal
            // zentriert (User-Spec). Spacer am Ende entfernt, Card-Frame
            // auf `.center`-Alignment.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Deine Credits:")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("\(arcadeCredits)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(arcadeCredits == 1 ? "Spiel" : "Spiele")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            heroMetaRowAsset(
                assetName: "SplashCharacter",
                text: "1 Spiel = \(livesPerCredit) Leben"
            )
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .center)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.strong, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    @ViewBuilder
    private func heroMetaRow(systemImage: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
    }

    /// Asset-Variante von `heroMetaRow` — rendert ein Image aus dem
    /// Asset-Catalog statt eines SF-Symbols. Genutzt für das Elumi-Icon
    /// im „1 Spiel = X Leben"-Hinweis (markennäher als Herz-SF-Symbol).
    ///
    /// **2026-05-04 Polish-Follow-up** — kein trailing Spacer mehr;
    /// die Row wird vom Caller horizontal zentriert.
    @ViewBuilder
    private func heroMetaRowAsset(assetName: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    // MARK: - Game-Start-Buttons (Phase 7.6+)
    //
    // Zwei gleichgroße Primary-CTAs, einer pro Spiel. Visuell
    // identisches Design — gleicher Button-Style, gleiche Höhe, gleiche
    // Icon-Größe —, nur Label + Icon differenzieren die Spiele.
    //
    // Elumi (Arcade) braucht Credits; ohne Credits wird der Button
    // deaktiviert + eine Hinweiszeile unter dem Block zeigt, wie der
    // User an Spiele kommt. Word Runner läuft ohne Credit-Verbrauch
    // (Dev-/Prototyp-Stand) und ist daher immer verfügbar.

    private var gameStartButtons: some View {
        // **2026-05-04 Polish-Follow-up** — Cards minimal schmaler durch
        // 12 pt Horizontal-Inset. Hero und Reward-Block oben/unten
        // bleiben full-width, die Game-Start-Buttons rücken visuell
        // dezent zurück.
        VStack(spacing: 10) {
            // Asset-Zuordnung (korrigiert nach Asset-Prüfung):
            //   • `ElumiWasserfloh` = die eigentliche Elumi-Spielfigur
            //     (Wasserfloh-Maskottchen) → Button „Elumi starten".
            //   • `IconElumiSpiel`   = das U-Boot-Icon
            //     (Submarine-Silhouette mit Bullaugen) → Button „Word
            //     Runner starten" (User-Spec „Elumi im U-Boot").
            // Vorher waren beide vertauscht — der Dateiname
            // `IconElumiSpiel` klang nach Elumi, zeigt aber ein U-Boot.
            //
            // **Quick-Fix 2026-04-30 (`v2-unify-game-tile-disabled`)**:
            // beide Tiles werden jetzt einheitlich auf `hasCredits`
            // gegated, weil beide Spiele beim Start 1 Ticket
            // verbrauchen (siehe `WordRunnerGameView.swift:2943` und
            // `ElumiArcadeGameView+Overlays.swift:243`). Vorher war
            // Word Runner fälschlich antippbar trotz Verbrauch — User
            // wurde nach dem Tap überrascht. Jetzt: Tile zeigt den
            // 0-Tickets-State explizit, Tap auf disabled-Tile öffnet
            // Acknowledge-Alert.
            // **2026-05-04 Polish** — Algenkugel raus (Reduktion von 3
            // auf 2 Snack-Icons), Title in CAPS ohne „starten"-Suffix,
            // Pfeil-Icon rechts statt Text-CTA.
            gameStartButton(
                title: "ELUMI GAME",
                assetNames: ["ElumiWuermchen", "ElumiWasserfloh"],
                enabled: hasCredits,
                action: startGameTapped,
                onDisabledTap: { showNoTicketsAlert = true }
            )

            gameStartButton(
                title: "WORDRUNNER",
                assetNames: ["IconElumiSpiel"],
                enabled: hasCredits,
                action: { navigate?(.wordRunner) },
                onDisabledTap: { showNoTicketsAlert = true }
            )

            // Hinweis-Zeile **nur** im Empty-State. Wording bewusst mit
            // dem App-internen Begriff „Trainingsgenerator" — analog
            // zur App-eigenen Bezeichnung der Slot-Machine im
            // Elumi-Tab. Vorher hieß die Zeile „Keine Spiele für
            // Elumi — Word Runner kannst du trotzdem starten" und war
            // unhonest, weil WR auch 1 Credit kostet.
            if !hasCredits {
                Text("Du hast keine Tickets mehr. Verdiene welche durch Lernen oder durch den Trainingsgenerator.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    /// Gemeinsamer Start-Button-Stil — beide Spiele nutzen identisches
    /// Layout, damit die beiden Cards visuell homogen
    /// nebeneinander stehen.
    ///
    /// **2026-05-04 Polish** — Layout-Refresh:
    ///   • Icon-Spalte LINKS, fix breit (`Self.iconColumnWidth` pt) —
    ///     egal ob 1 oder 2 Symbole, der Spalten-Footprint ist
    ///     identisch. Asset-Größen sind so kalibriert, dass der
    ///     visuelle „Fülle"-Eindruck pro Card ähnlich wirkt.
    ///   • Title CENTER (CAPS, ohne „starten"-Suffix).
    ///   • Pfeil-Icon rechts (`arrow.right.circle.fill`) statt Text-CTA.
    ///   • Pulsation aktiv, solange enabled — User-Tap-Hint.
    ///   • Disabled-State: Lock-Icon + „0 🎫"-Pill rechts statt Pfeil.
    private static let iconColumnWidth: CGFloat = 92

    @ViewBuilder
    private func gameStartButton(
        title: String,
        assetNames: [String],
        enabled: Bool,
        action: @escaping () -> Void,
        onDisabledTap: (() -> Void)? = nil
    ) -> some View {
        Button {
            if enabled {
                action()
            } else {
                onDisabledTap?()
            }
        } label: {
            HStack(spacing: 0) {
                // Icon-Spalte links — fix breit, leading alignment.
                HStack(spacing: 4) {
                    if enabled {
                        ForEach(assetNames, id: \.self) { name in
                            Image(name)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: assetNames.count > 1 ? 40 : 56,
                                    height: assetNames.count > 1 ? 40 : 56
                                )
                        }
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: 56, height: 56)
                    }
                }
                .frame(width: Self.iconColumnWidth, alignment: .leading)

                // Title CENTER — beide Cards nutzen `.frame(maxWidth: .infinity)`
                // für die Title-Spalte, damit der Text geometrisch
                // mittig sitzt zwischen Icon-Spalte und Trailing-Indikator.
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Trailing-Indikator: Pfeil im Enabled-State, „0 🎫"-Pill
                // im Disabled-State. Trailing-Spalte ebenfalls fix breit
                // (44 pt), damit Title-Center auf beiden Cards an
                // derselben x-Position liegt.
                Group {
                    if enabled {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.black.opacity(0.65))
                    } else {
                        Text("0 🎫")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(AppTheme.Colors.textSecondary.opacity(0.20))
                            )
                    }
                }
                .frame(width: 44, alignment: .center)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .opacity(enabled ? 1.0 : 0.50)
        // **2026-05-04 Polish** — Pulsation, solange das Spiel
        // anwählbar ist. Pattern aus `PulsingModifier`. Bei disabled
        // (keine Tickets) statisch — sonst suggeriert die Pulsation
        // einen tappable Pfad zum Spiel, der nicht funktioniert.
        .pulsing(active: enabled, glowColor: AppTheme.Colors.cta)
    }

    private func startGameTapped() {
        guard hasCredits else { return }
        // Start-Sound hier NICHT — er kommt einmal beim
        // **Erscheinen des Start-Screens** (ElumiArcadeGameView.
        // onAppear). Beim tatsächlichen Run-Start (CTA im Overlay)
        // startet sofort die Musik statt erneutem SFX — User-Spec
        // „start sound nur beim aufruf des start screens".
        openArcade?(false)
    }

    // MARK: - Reward Explainer
    //
    // Kurze, überschaubare Vier-Punkt-Liste: „So verdienst du Spiele."
    // Wortschatz appweit konsistent („Spiele" statt „Credits" — siehe
    // Footer-Badge, Hero-Label, Session-End-Chips). Zahlen gespiegelt
    // aus den zentralen Konstanten (`GamificationConfig`).

    private var rewardExplainerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressSectionHeader(
                title: "So verdienst du Spiele",
                subtitle: nil
            )

            VStack(spacing: 0) {
                // Tagesaufgabe zuerst — direktester Weg zu einem Spiel,
                // passt zur „Retention-Engine".
                rewardExplainerRow(
                    systemImage: "sparkles",
                    tint: AppTheme.Colors.cta,
                    title: "Tagesaufgabe erledigen",
                    subtitle: "täglich +1 Spiel + XP"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "text.bubble.fill",
                    tint: AppTheme.Colors.elumiBlue,
                    title: "Lernen",
                    subtitle: "\(xpPerCredit) XP = 1 Spiel"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "flame.fill",
                    tint: Color(hex: "#FF9F40"),
                    title: "Streak halten",
                    subtitle: "Tage in Folge bringen Bonus-Spiele"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "star.fill",
                    tint: sectionStyle.accent,
                    title: "Level aufsteigen",
                    subtitle: GamificationConfig.creditsPerLevelUp == 1
                        ? "+1 Spiel pro neuem Level"
                        : "+\(GamificationConfig.creditsPerLevelUp) Spiele pro neuem Level"
                )
            }
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle)
        }
    }

    @ViewBuilder
    private func rewardExplainerRow(systemImage: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        // Vertikal-Padding 11 → 8 pro Row → 4 Reihen sparen 12 pt.
        .padding(.vertical, 8)
    }

    private var rewardExplainerDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.border.opacity(0.4))
            .frame(height: 1)
            .padding(.leading, 58)
    }

}
