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
        // Hero kompakter (User-Spec „weniger Platz verbrauchen"):
        // Hauptzahl 56→36, kein Gamepad-Icon mehr — stattdessen direkt
        // die prominente Textzeile „Deine Credits: X Spiele". Die
        // Meta-Row nutzt jetzt das Elumi-Icon (Wasserfloh) statt des
        // Herz-Symbols — enger an der Markenidentität des Spiels.
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Deine Credits:")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("\(arcadeCredits)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(arcadeCredits == 1 ? "Spiel" : "Spiele")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)
            }

            // Meta-Zeilen nebeneinander — spart eine komplette Zeile.
            // „Herz → Elumi-Icon": das Icon im Leben-Hinweis zieht den
            // Bezug zur Spielfigur, statt generisches Herz-Symbol.
            HStack(spacing: 14) {
                heroMetaRowAsset(
                    // Elumi-Maskottchen (Wasserfloh) — vorher hatte
                    // diese Zeile fälschlich `IconElumiSpiel` (das
                    // U-Boot-Icon). Im „1 Spiel = N Leben"-Hinweis
                    // gehört visuell das Spiel-Subjekt hin, nicht das
                    // Fahrzeug aus dem anderen Modus.
                    assetName: "ElumiWasserfloh",
                    text: "1 Spiel = \(livesPerCredit) Leben"
                )
                heroMetaRow(
                    systemImage: "sparkles",
                    tint: AppTheme.Colors.cta,
                    text: "Verdient durch Lernen"
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        // Vertical-Padding wieder auf `Spacing.md` gesetzt (User-
        // Rollback: „Credit-Card wieder etwas taller"). Davor war's
        // auf `xs` geschrumpft — zu wenig Luft, die Card wirkte
        // gedrückt.
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Spacer(minLength: 0)
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
        VStack(spacing: 10) {
            // Asset-Zuordnung (korrigiert nach Asset-Prüfung):
            //   • `ElumiWasserfloh` = die eigentliche Elumi-Spielfigur
            //     (Wasserfloh-Maskottchen) → Button „Elumi starten".
            //   • `IconElumiSpiel`   = das U-Boot-Icon
            //     (Submarine-Silhouette mit Bullaugen) → Button „Word
            //     Runner starten" (User-Spec „Elumi im U-Boot").
            // Vorher waren beide vertauscht — der Dateiname
            // `IconElumiSpiel` klang nach Elumi, zeigt aber ein U-Boot.
            gameStartButton(
                title: "Elumi starten",
                // Drei Snack-Icons nebeneinander (User-Spec) — zeigt
                // auf einen Blick, worum's im Arcade-Spiel geht:
                // Wurm, Wasserfloh, Algenkugel.
                assetNames: ["ElumiWuermchen", "ElumiWasserfloh", "ElumiAlgenkugel"],
                enabled: hasCredits,
                action: startGameTapped
            )

            gameStartButton(
                title: "Word Runner starten",
                assetNames: ["IconElumiSpiel"],
                enabled: true,
                action: { navigate?(.wordRunner) }
            )

            // Hinweis-Zeile **nur** im Empty-State — die generische
            // „X Spiele werden verwendet"-Zeile (User-Spec: raus) ist
            // entfallen, da sie keine neue Info über den bereits
            // sichtbaren Credits-Block liefert.
            if !hasCredits {
                Text("Keine Spiele für Elumi — spiel eine Runde Lernen, um welche zu verdienen. Word Runner kannst du trotzdem starten.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Gemeinsamer Start-Button-Stil — beide Spiele nutzen identisches
    /// Layout, damit die beiden Buttons visuell gleichwertig
    /// nebeneinander stehen.
    ///
    /// `assetNames` kann **ein oder mehrere** Asset-Namen enthalten:
    ///   • 1 Asset  → klassischer Button mit einem einzelnen Icon
    ///     (Word-Runner-U-Boot).
    ///   • 2–3 Assets → alle nebeneinander vor dem Label. Genutzt vom
    ///     Elumi-Start-Button, damit die drei Snacks (Wurm, Wasserfloh,
    ///     Algenkugel) sofort sichtbar sind und der Button erzählt,
    ///     worum es im Arcade-Spiel geht.
    @ViewBuilder
    private func gameStartButton(
        title: String,
        assetNames: [String],
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            action()
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(assetNames, id: \.self) { name in
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            // Bei einem Single-Asset bleibt es bei der
                            // großen 52-pt-Darstellung (User-Spec
                            // „doppelt so groß"). Bei mehreren Icons
                            // nebeneinander etwas kleiner (36 pt) —
                            // sonst sprengt die Icon-Reihe die Button-
                            // Breite und drückt das Label raus.
                            .frame(
                                width: assetNames.count > 1 ? 36 : 52,
                                height: assetNames.count > 1 ? 36 : 52
                            )
                    }
                }
                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            // minHeight wächst mit dem Icon-Set: Single-Icon 60 pt
            // (Icon 52 + Padding), Multi-Icon 52 pt (Icon 36 +
            // Padding).
            .frame(minHeight: assetNames.count > 1 ? 52 : 60)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.5)
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
