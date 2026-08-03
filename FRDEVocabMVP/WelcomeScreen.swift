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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.xl) {
                    mascot
                    greeting
                    featureList
                    reassurance
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.lg)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth)
                .frame(maxWidth: .infinity)
            }

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

    private var mascot: some View {
        ZStack {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
            SplashCharacterBlinkOverlay(size: 132, startDate: .now)
                .frame(width: 132, height: 132)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .scaleEffect(hasAppeared ? 1 : 0.88)
        .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - Begrüßung

    private var greeting: some View {
        VStack(spacing: 6) {
            Text("Salut! 👋")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text("Ich bin Elumi.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiPink)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("Schön, dass du da bist!")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Zusammen bringen wir dein Französisch zum Laufen.\nDas hier kannst du mit mir machen:")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, AppTheme.Spacing.xs)
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

    // MARK: - Abschluss

    private var reassurance: some View {
        VStack(spacing: 2) {
            Text("Keine Angst vor Fehlern.")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Genau davon lernst du am meisten.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - CTA

    private var startButton: some View {
        VStack(spacing: 0) {
            Button(action: onStart) {
                Text("Los geht's!")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.md)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.Colors.background)
    }
}
