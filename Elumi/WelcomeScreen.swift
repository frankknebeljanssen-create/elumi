// WelcomeScreen.swift
// **2026-06-09** — Vollbild-Willkommensscreen, der direkt nach dem
// Splash erscheint und per CTA weggeklickt wird.
//
// Reihenfolge: Splash → Welcome → (beim ersten Start) Account-
// Onboarding → Home. Der Screen läuft bewusst VOR der Namenseingabe:
// Erstnutzer sehen erst, worum es geht, und tragen sich danach ein.
//
// Sichtbarkeit: gesteuert über `FeatureFlags.alwaysShowWelcomeScreen`.
//   • `true`  (Testphase): erscheint bei JEDEM App-Start. Der Screen
//     merkt sich nichts — das Gate ist reiner Launch-State in
//     `RootContentView`.
//   • `false` (Release):   erscheint nur beim allerersten Start; danach
//     ist die ID im `HintStore` als gesehen markiert — dieselbe
//     Persistenz wie bei den Erstnutzer-Hints, kein zweiter Mechanismus.
//
// Ton: Elumi spricht in Ich-Form, konsistent zu den Hint-Bubbles
// (`DismissibleHintOverlay`). Zielgruppe sind Kinder/Jugendliche —
// kurze Sätze, ein Gedanke pro Zeile, keine Textwände.

import SwiftUI

struct WelcomeScreen: View {
    /// Wird vom CTA aufgerufen — der Aufrufer blendet den Screen aus.
    let onStart: () -> Void

    /// **Intro-Skip (Testphase, 2026-09-03)** — ein Tipp auf das
    /// Maskottchen springt am gesamten Intro vorbei direkt auf Home.
    /// Bewusst ohne sichtbaren Button: Der reguläre Weg über „Los
    /// geht's!" soll der offensichtliche bleiben, damit der Screen im
    /// Test genau so wirkt wie später im Release. Ist der Callback
    /// `nil` (Release-Pfad), verhält sich das Maskottchen wie vorher.
    var onSkipIntro: (() -> Void)? = nil

    /// Hint-ID für den Release-Pfad (`alwaysShowWelcomeScreen == false`).
    /// In der Testphase ungenutzt, aber hier definiert, damit Gate und
    /// Screen dieselbe Konstante teilen.
    static let hintID = "welcome_screen"

    /// Maskottchen-Auftritt: leichtes Einschweben beim Erscheinen.
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            AppTheme.Colors.background
                .ignoresSafeArea()

            // **2026-08-05** — Unterwasser-Stimmung nur auf diesem
            // Screen (User-Spec: "du kannst da auch 'n bisschen mit den
            // Farben spielen, dass der erste und zweite Screen nicht
            // komplett gleich aussehen"). Weicher Mint-Schein von unten
            // plus aufsteigende Blasen. Der zweite Onboarding-Screen
            // bleibt bewusst nüchtern — dort wird gefragt, hier wird
            // begrüßt.
            if !FeatureFlags.welcomeScreenFeatureCardsEnabled {
                RadialGradient(
                    colors: [
                        AppTheme.Colors.elumiMint.opacity(0.20),
                        AppTheme.Colors.background.opacity(0)
                    ],
                    center: .bottom,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()

                WelcomeBubbleField()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // **2026-06-09** — Kein ScrollView mehr: der Screen muss
            // komplett auf eine iPhone-Höhe passen (User-Spec). Dafür
            // Maskottchen verkleinert, Abstände enger und der frühere
            // Abschluss-Block „Keine Angst vor Fehlern" entfernt.
            // **2026-08-05** — Feature-Karten hinter
            // `FeatureFlags.welcomeScreenFeatureCardsEnabled`. Ohne sie
            // ist der Screen ein reiner Türöffner: Maskottchen,
            // Begrüßung, weiter. Erklärt wird am Ende des
            // Ziel-Onboardings (Modul-Screen) — begründet am Flag.
            //
            // Ohne Karten bekommt die Begrüßung Luft nach oben und
            // unten (`Spacer` davor), damit sie mittig steht statt
            // oben zu kleben.
            VStack(spacing: AppTheme.Spacing.md) {
                if FeatureFlags.welcomeScreenFeatureCardsEnabled {
                    mascot
                    greeting
                    featureList
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    mascot
                    greeting
                    snackRow
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppTheme.Spacing.sm)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth)
            .frame(maxWidth: .infinity)

            // CTA fix am unteren Rand — der Screen darf scrollen, der
            // Weiter-Weg bleibt immer sichtbar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startButton
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Maskottchen

    /// **2026-08-05** — ohne Feature-Karten ist auf dem Screen viel
    /// Platz frei, den das Maskottchen füllen darf (User-Spec: "du
    /// kannst den Platz auch weiterhin gerne nutzen").
    private var mascotSize: CGFloat {
        FeatureFlags.welcomeScreenFeatureCardsEnabled ? 92 : 150
    }

    private var mascot: some View {
        ZStack {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: mascotSize, height: mascotSize)
            SplashCharacterBlinkOverlay(size: mascotSize, startDate: .now)
                .frame(width: mascotSize, height: mascotSize)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .scaleEffect(hasAppeared ? 1 : 0.88)
        .opacity(hasAppeared ? 1 : 0)
        // **Intro-Skip (Testphase)** — siehe `onSkipIntro`. Der
        // `contentShape` macht auch die transparenten Ecken des
        // Maskottchens tippbar, sonst trifft man nur die Pixel der
        // Figur selbst.
        .contentShape(Rectangle())
        .onTapGesture {
            onSkipIntro?()
        }
    }

    /// **2026-08-05** — Würmchen, Wasserfloh und Algenkugel als
    /// Vorgeschmack (User-Spec: "mach ruhig auch son Würmchen rein und
    /// auch die Kugel, die können auch als Symbole mit erscheinen").
    /// Dieselben Assets wie im Game-Hub und in der Session-Summary —
    /// der Nutzer erkennt sie später wieder, wenn er sie sammelt.
    private var snackRow: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            snackIcon("ElumiWuermchen")
            snackIcon("ElumiWasserfloh")
            snackIcon("ElumiAlgenkugel")
        }
        .padding(.top, AppTheme.Spacing.sm)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
    }

    private func snackIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    // MARK: - Begrüßung

    /// **2026-06-09** — Kompakter als zuvor, damit der Screen ohne
    /// Scrollen passt: „Schön, dass du da bist!" ist in die Subline
    /// gewandert, Schriftgrößen leicht reduziert.
    /// **2026-08-05** — Schriftgrößen auf das Niveau der übrigen
    /// Onboarding-Screens gezogen (User-Spec: "die braucht auch noch
    /// den großen Schriftsatz wie die anderen Seiten, das wirkt son
    /// bisschen klein"). Ohne die Feature-Karten ist der Platz da.
    private var greeting: some View {
        // **2026-08-06** — User-Spec: mehr Luft zwischen den drei Zeilen
        // ("ein bisschen mehr Abstand zur nächsten Zeile", "das muss von
        // 'Ich bin Elumi' abgesetzt werden, mir ist das zu eng dran") und
        // die Subline zwei Punkt größer.
        VStack(spacing: 12) {
            Text("Salut! 👋")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text("Ich bin Elumi.")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiMint)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // **2026-08-05** — Der Satz kündigte die Feature-Karten an
            // ("Das hier kannst du mit mir machen:"). Sind die
            // ausgeblendet, zeigt er ins Leere — dann steht hier ein
            // eigenständiger Satz, der zum nächsten Schritt überleitet.
            Text(
                FeatureFlags.welcomeScreenFeatureCardsEnabled
                    ? "Schön, dass du da bist!\nDas hier kannst du mit mir machen:"
                    : "Schön, dass du da bist!\nIch helf dir beim Französischlernen."
            )
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Was die App kann

    private var featureList: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            featureCard(
                emoji: "📸",
                title: "Fotografier dein Vokabelheft",
                subtitle: "Ich lese die Wörter und mach dir Übungen draus.",
                tint: AppTheme.Colors.moduleScan
            )
            featureCard(
                emoji: "🎯",
                title: "Üben, wie du Lust hast",
                subtitle: "Karteikarten, Quiz, Nomen, Verben, Akzente.",
                tint: AppTheme.Colors.moduleVocabulary
            )
            featureCard(
                emoji: "🔥",
                title: "Jeden Tag ein bisschen",
                subtitle: "Damit wächst deine Serie — und ich krieg was zu futtern. 😋",
                tint: AppTheme.Colors.elumiPinkDeep
            )
            // Bewusst die kürzeste Card und bewusst am Ende: erst was
            // die App macht, dann die Belohnung. Formulierung folgt der
            // Spec in `ArcadeCreditSystem` — Spiele werden FREIGESCHALTET
            // (nicht jede Session gibt eines), deshalb kein Versprechen
            // wie „nach jeder Übung ein Spiel".
            featureCard(
                emoji: "🎮",
                title: "Spiele freischalten",
                subtitle: "Wer fleißig übt, darf zocken.",
                tint: AppTheme.Colors.moduleQuiz
            )
        }
    }

    /// Ein Feature-Block: Emoji links, Titel + Erklärung rechts.
    /// Solider Card-Hintergrund mit Akzent-Tint, damit die drei Punkte
    /// klar getrennt lesbar sind statt als Fließtext zu verschwimmen.
    private func featureCard(
        emoji: String,
        title: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    // **2026-06-09** — Der Abschluss-Block („Keine Angst vor Fehlern")
    // ist entfallen: der Screen soll ohne Scrollen auf eine
    // iPhone-Höhe passen (User-Spec).

    // MARK: - CTA

    /// **2026-08-05** — aufsteigende Luftblasen im Hintergrund
    /// (User-Spec: "vielleicht können auch Blubberblasen kurz
    /// hochsteigen durchs Bild"). Unterstreicht die Unterwasser-
    /// Identität und unterscheidet den Begrüßungs-Screen sichtbar vom
    /// nüchternen Frage-Screen danach.
    ///
    /// Läuft über `TimelineView` mit gedrosselter Rate, gleiche
    /// Bauart wie `PulsingModifier` — 20 Bilder/Sekunde reichen für
    /// langsam steigende Blasen und halten die Last niedrig. Die
    /// Positionen sind aus dem Index abgeleitet, nicht zufällig, damit
    /// keine `Math.random`-Neuberechnung bei jedem Frame passiert.
    private struct WelcomeBubbleField: View {
        private let bubbleCount = 14

        var body: some View {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<bubbleCount, id: \.self) { index in
                            bubble(index: index, size: geo.size, time: t)
                        }
                    }
                }
            }
        }

        private func bubble(index: Int, size: CGSize, time: TimeInterval) -> some View {
            // Deterministische Streuung aus dem Index: Position, Größe
            // und Tempo variieren, bleiben aber über Frames stabil.
            let seed = Double(index)
            let xFraction = (seed * 0.137).truncatingRemainder(dividingBy: 1.0)
            let diameter = 6 + (seed * 2.7).truncatingRemainder(dividingBy: 14)
            let speed = 26 + (seed * 5.3).truncatingRemainder(dividingBy: 22)
            let phase = (seed * 0.31).truncatingRemainder(dividingBy: 1.0)

            // Aufsteigen: von unterhalb des Bildschirms nach oben,
            // umlaufend über die Gesamthöhe plus Puffer.
            let travel = size.height + 120
            let progress = ((time * speed / travel) + phase).truncatingRemainder(dividingBy: 1.0)
            let y = size.height + 60 - progress * travel

            // Leichtes seitliches Pendeln, damit es nicht wie eine
            // gerade Linie wirkt.
            let sway = sin((time * 0.6) + seed) * 10

            return Circle()
                .stroke(AppTheme.Colors.elumiMint.opacity(0.35), lineWidth: 1.5)
                .background(Circle().fill(AppTheme.Colors.elumiMint.opacity(0.10)))
                .frame(width: diameter, height: diameter)
                .position(x: xFraction * size.width + sway, y: y)
                // Am oberen Rand ausblenden, damit Blasen nicht hart
                // abgeschnitten verschwinden.
                .opacity(progress > 0.85 ? (1 - progress) / 0.15 : 1)
        }
    }

    private var startButton: some View {
        VStack(spacing: 0) {
            Button(action: onStart) {
                Text("Los geht's!")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppTheme.Spacing.sm)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth)
            .frame(maxWidth: .infinity)

            // **Intro-Skip (Testphase, 2026-09-03)** — derselbe Skip
            // wie auf dem Splash, hier als zweite Gelegenheit. Der
            // Splash steht nur 2,8 Sekunden; wer den Button dort
            // verpasst, müsste sonst das ganze Intro durchklicken.
            // Bewusst dezent unter dem CTA: „Los geht's!" bleibt der
            // Weg, den ein echter Nutzer nimmt.
            if let onSkipIntro {
                Button(action: onSkipIntro) {
                    Text("Intro überspringen")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppLayout.screenPadding)
            }
        }
        .padding(.bottom, AppTheme.Spacing.md)
        .background(AppTheme.Colors.background)
    }
}
