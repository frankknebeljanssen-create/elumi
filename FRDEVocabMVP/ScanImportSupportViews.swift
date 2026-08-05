import SwiftUI

// Phase 7.6 Cleanup: lokaler `HomeCardPressStyle` entfernt — der
// systemweite `AppCardPressStyle` (siehe `AppButtonStyles.swift`)
// übernimmt diese Rolle. Der Scan-Import-Flow nutzt bereits die
// zentrale Variante (siehe Button-Aufrufe weiter unten).

struct ImportCompletionView: View {
    let context: ImportCompletionContext
    let onTrain: () -> Void
    let onNomen: () -> Void
    let onArticles: () -> Void
    let onVerbs: () -> Void
    let onVerbforms: () -> Void
    let onFlashcards: () -> Void
    let onQuiz: () -> Void
    let onAccents: () -> Void
    let onViewList: () -> Void
    let onLater: () -> Void
    private let sectionStyle: AppSectionStyle = .scan
    @State private var isNavigationLocked = false

    /// Feste Modul-Reihenfolge — identisch zur Home-Identität (User-
    /// Spec: „Reihenfolge wie im Home: kartei, quiz, nomen, artikel,
    /// verben, verbformen, akzente, vokabeln"). Einzige Quelle der
    /// Wahrheit für den 4×2-Grid darunter.
    private static let moduleOrder: [HomeHeroModule] = [
        .karteikarten, .quiz, .nomen, .artikel,
        .verben, .verbformen, .akzente, .vokabeln
    ]

    /// **4 Spalten × 2 Reihen** (User-Spec): 8 Module in einem
    /// kompakten Grid, Kartengröße wie `HomeMoreExercisesSection.
    /// MoreExerciseCard` (klein, ≙ Home-„Weitere Übungen"-Reihe).
    /// Damit bleibt die Grid-Höhe flach genug, dass die Action-Row
    /// unten ohne Scrollen sichtbar bleibt.
    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        // **Scrollbar** (User-Bug: „unten steht noch was, kann nicht
        // scrollen"). ScrollView hüllt jetzt den kompletten Content —
        // bei vielen Kacheln + langer Summary + Footer-Buttons rutscht
        // sonst der letzte Block unter die Bottom-Bar.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Import fertig! — Häkchen **über** dem Titel
                // (User-Spec, Rollback auf das vorherige Layout). Icon
                // prominent in 48 pt, Titel darunter.
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.success)
                    Text("Import fertig!")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }

                // Summary card
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.summaryText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Lernliste: \(context.targetListName)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft, cornerRadius: 16)

                // **„Liste ansehen" — Primärer vollbreiter CTA**
                // (User-Spec 2026-04-23 abends): über „Was möchtest du
                // sofort üben" platziert, mit Eye-Icon und sichtbar
                // größerer Font für klare Hauptaktion-Anmutung.
                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onViewList()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Lernliste ansehen")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: .white))

                // Question — outside card
                Text("Was möchtest du sofort üben?")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                // **Module-Grid** — identisches Format wie `HomeHeroLearning
                // Section`: 2-Spalten-`LazyVGrid`, Cards mit 1.15-Aspect,
                // Gradient-Background in Modul-Accent, große Home-Icons
                // (kein SF-Symbol-Mix). 8 Kacheln in fester Home-Reihen-
                // folge.
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(Self.moduleOrder) { module in
                        completionHomeStyleCard(module: module)
                    }
                }

                // **„Ich übe später" — Sekundärer vollbreiter CTA**
                // (User-Spec 2026-04-23 abends): unter dem Module-Grid,
                // ebenfalls vollbreit und sichtbar größere Font.
                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onLater()
                } label: {
                    Text("Ich übe später")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: .white))
            }
            .padding(AppLayout.screenPadding)
            // **2026-05-08 Padding-Cleanup** — `footerHeight + insetBottom + lg`
            // → `Spacing.lg`. Footer per safeAreaInset reserviert.
            .padding(.bottom, AppTheme.Spacing.lg)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .safeAreaPadding(.top, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isNavigationLocked = false
        }
    }

    /// Home-Style-Card (kleine Variante für das 4×2 Import-Grid). Sehr
    /// eng an `HomeHeroLearningSection.HeroModuleCard` angelehnt —
    /// Gradient-Background, Home-Icon zentriert, weißer Titel. Eigener
    /// Wrapper (statt Private-Struct zu reusen), damit wir hier:
    ///   • den `isNavigationLocked`-Guard setzen (keine doppelten Taps
    ///     während der Navigation rausspringt),
    ///   • das Icon eine Stufe kleiner rendern (85 pt statt 95 pt —
    ///     das Grid hat 4 Reihen, die Home-Hero nur 2, also leicht
    ///     kompaktere Cards).
    @ViewBuilder
    private func completionHomeStyleCard(module: HomeHeroModule) -> some View {
        Button {
            guard !isNavigationLocked else { return }
            isNavigationLocked = true
            completionAction(for: module)()
        } label: {
            // **Größe wie Home-„Weitere Übungen"-Cards** (User-Spec):
            // aspectRatio 1.2, Icon 40 pt, Titel 12 pt (Karteikarten
            // 11 pt), cornerRadius 16, sanfterer Gradient (0.88→0.68).
            // 1:1 Match mit `HomeMoreExercisesSection.MoreExerciseCard`
            // — kompakt und klar untergeordnet zur Hero-Identität.
            Color.clear
                .aspectRatio(1.2, contentMode: .fit)
                .overlay {
                    VStack(spacing: 1) {
                        HomeModuleIconView(
                            icon: module.icon,
                            size: 40,
                            glyphTint: .white
                        )
                        Text(module.title)
                            .font(.system(
                                size: module == .karteikarten ? 11 : 12,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    module.accent.opacity(0.88),
                                    module.accent.opacity(0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(AppCardPressStyle())
        .disabled(isNavigationLocked)
    }

    /// Mapping Home-Modul → Import-Completion-Callback. Zentral hier,
    /// damit die Card-Rendering-Logik modul-agnostisch bleibt und
    /// später (z. B. „Freier Text"-Modus) einfach erweitert werden
    /// kann — neuer Case hier + neue Closure-Property oben reichen.
    private func completionAction(for module: HomeHeroModule) -> () -> Void {
        switch module {
        case .karteikarten: return onFlashcards
        case .quiz:         return onQuiz
        case .nomen:        return onNomen
        case .artikel:      return onArticles
        case .verben:       return onVerbs
        case .verbformen:   return onVerbforms
        case .akzente:      return onAccents
        case .vokabeln:     return onTrain
        }
    }
}

/// **Ziel-System-Rückweg (2026-08-05)** — dedizierter Abschluss-Screen
/// für Scans, die aus dem Ziel-Onboarding heraus gestartet wurden.
///
/// Ersetzt an dieser Stelle die normale `ImportCompletionView` (acht
/// Übungs-Kacheln + "Ich übe später"). User-Report nach Gerätetest:
/// direkt nach dem Onboarding-Scan mit acht gleichwertigen
/// Übungsoptionen konfrontiert zu werden war die falsche nächste
/// Aktion — "wir müssen wieder zurück ins Onboarding". Dieser Screen
/// hat genau EINE Aktion: die Liste dem wartenden Ziel zuordnen und
/// zurück zur Feier im Onboarding-Overlay (`RootContentView` fängt
/// `LearningGoalStore.pendingCelebrationRequested` ab).
///
/// Wird nur gezeigt, wenn `LearningGoalStore.isAwaitingListAssignment`
/// beim Erreichen des Import-Abschlusses noch `true` ist (siehe
/// Verzweigung in `ScanImportView+Screen.importCompletionScreen`) —
/// ganz normale Scans außerhalb des Onboardings sehen weiterhin die
/// gewohnte `ImportCompletionView`, unverändert.
struct OnboardingScanCompletionView: View {
    let context: ImportCompletionContext
    let onContinue: () -> Void

    private let sectionStyle: AppSectionStyle = .scan
    @State private var isNavigationLocked = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer(minLength: AppTheme.Spacing.xxl)

            mascot

            VStack(spacing: 12) {
                Text("Du bist startbereit! 🎉")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(context.summaryText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.md)

                // **2026-08-05** — sagt explizit, wohin es von hier
                // geht (User-Spec: "jetzt muss aber vielleicht noch 'n
                // Satz dazu kommen"). Ohne den Satz wirkte der Screen
                // wie eine Sackgasse, obwohl gleich das Onboarding
                // weiterläuft.
                Text("Deine Vokabeln sind bei deinem Ziel gelandet. Fehlt nur noch der letzte Schritt.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, 4)
            }

            Spacer(minLength: AppTheme.Spacing.xxl)
            Spacer(minLength: AppTheme.Spacing.xl)

            Button {
                guard !isNavigationLocked else { return }
                isNavigationLocked = true
                onContinue()
            } label: {
                Text("Let's go!")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
            }
            .buttonStyle(OnboardingCTAButtonStyle(color: AppTheme.Colors.cta))
            .padding(.horizontal, AppLayout.screenPadding)

            Spacer(minLength: AppTheme.Spacing.lg)
        }
        .frame(maxWidth: AppTheme.Layout.maxContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isNavigationLocked = false }
    }

    private var mascot: some View {
        ZStack {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
            SplashCharacterBlinkOverlay(size: 84, startDate: .now)
                .frame(width: 84, height: 84)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
    }
}
