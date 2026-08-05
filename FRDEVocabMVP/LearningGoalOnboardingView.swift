import SwiftUI

// LearningGoalOnboardingView.swift
// **Ziel-Onboarding (2026-08-05)** — zweiter Onboarding-Schritt NACH
// der Account-Anlage (Name + Emoji). Läuft als Vollbild-Overlay über
// Home, technisch analog zu `WelcomeScreen`: liegt im äußeren `ZStack`
// von `RootContentView`, erscheint erst NACHDEM ein Account existiert.
//
// **Warum erst nach Account-Anlage statt davor** — der Scan-Schritt
// weiter unten im Flow braucht die echte `AppRuntimeContainer`/
// `AppNavigationCoordinator`-Infrastruktur (Listen-Store, Navigation),
// die es vor Account-Anlage noch nicht gibt. Statt den Scan-Flow ein
// zweites Mal vereinfacht nachzubauen, läuft dieses Onboarding NACH
// der Account-Anlage, wenn diese Infrastruktur längst existiert — der
// "Jetzt scannen"-Weg ruft exakt denselben `ScanImportView`-Flow auf
// wie der Rest der App (Rückweg siehe `OnboardingScanCompletionView`
// in `ScanImportSupportViews.swift`).
//
// **Dramaturgie** (User-Spec, angelehnt an YAZIO-Referenz-Screens,
// NICHT kopiert — Elumi-Maskottchen statt Diagramm, Elumi-Wortwahl):
// eine Frage pro Screen, Maskottchen an den emotionalen Ankerpunkten,
// kein technischer "Fertig"-Screen.
//
//   1. Übergang       Maskottchen stellt sich als Begleiter vor
//   2. Anlass         "Was steht bei dir an?" — 5 Karten
//   3. Termin          nur bei Anlass = Schulaufgabe
//   4. Rhythmus        2/3/5/7 Tage/Woche, Wort+Emoji-Skala
//      → Plan wird HIER gespeichert (siehe Timing-Hinweis unten)
//   5. Vorschau        Maskottchen zeigt eine motivierende Kurzaussage
//   6. Vokabeln-Frage  nur wenn Anlass einen Bestand braucht — reine
//                      Ja/Nein-Frage "Hast du die Vokabeln schon?"
//   7a. Listen wählen  bei "Ja" — eigene Listen, Mehrfachauswahl
//   7b. Scan-Einstieg  bei "Nein" — führt in den echten Scan-Flow
//   8. Feier           Maskottchen feiert, "Los geht's, {Name}!"
//
// **Timing-Falle, gelöst über den Latch in `RootContentView`**: Der
// Plan wird schon in Schritt 4 persistiert (nötig, damit Schritt 7b
// den echten Scan-Flow nutzen kann — der Scan-Rückweg prüft
// `LearningGoalStore.plan`). Würde die Sichtbarkeit dieses Overlays
// direkt an `plan == nil` hängen, verschwände es in dem Moment, in dem
// der Plan gespeichert wird. Der Latch (`isGoalOnboardingLatched` in
// `RootContentView`) hält das Overlay deshalb explizit offen, bis der
// Flow selbst `completeOnboarding()`/`handOffToScan()` ruft.
struct LearningGoalOnboardingView: View {
    /// Anzeigename für die Begrüßung/Feier — kommt vom frisch
    /// angelegten Account, nicht aus `ProfileStore` (Timing: dieser
    /// Screen erscheint direkt nach Account-Anlage, bevor irgendein
    /// anderer Screen den Namen gebraucht hätte).
    let displayName: String

    /// Pusht auf den echten Navigation-Pfad — dieselbe Closure, die
    /// auch `AppDestinationHost` bekommt. Ermöglicht "Jetzt scannen"
    /// ohne Sonderweg.
    let navigate: (AppScreen) -> Void

    /// Wird gerufen, sobald der Flow das Overlay verlassen soll —
    /// sowohl beim regulären Abschluss (Feier-CTA) als auch beim
    /// Handoff in den Scan-Flow.
    let onDismissOverlay: () -> Void

    // Nicht `private`: `+Steps.swift` liegt in derselben Extension-
    // Familie, aber in einer eigenen Datei — Swifts `private` ist
    // datei-scoped, würde den Zugriff von dort aus sperren.
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var goalStore = LearningGoalStore.shared

    /// **2026-08-05, Ring-Schließen-Fix** — Einstiegsschritt bei
    /// Neu-Erscheinen des Overlays. Normalerweise `.transition` (erster
    /// Durchlauf). Kommt der Nutzer aus dem Scan-Rückweg zurück,
    /// springt das Overlay direkt zum Feier-Screen — Plan und Liste
    /// stehen dann schon, alle vorherigen Fragen wären redundant.
    init(
        displayName: String,
        listStore: VocabularyListStore,
        initialStep: Step = .transition,
        navigate: @escaping (AppScreen) -> Void,
        onDismissOverlay: @escaping () -> Void
    ) {
        self.displayName = displayName
        self.navigate = navigate
        self.onDismissOverlay = onDismissOverlay
        self._listStore = ObservedObject(wrappedValue: listStore)
        self._currentStep = State(initialValue: initialStep)
    }

    /// **2026-08-05, Zwei-Wege-Split** — der frühere Einzelschritt
    /// "Vokabeln zuordnen" (Listen wählen ODER scannen ODER später,
    /// alles auf einem Screen) wurde durch User-Feedback in drei
    /// eigene Schritte aufgeteilt: erst eine reine Ja/Nein-Frage
    /// ("Hast du die Vokabeln schon in der App?"), danach je nach
    /// Antwort entweder der Listen-Picker oder ein eigener,
    /// dedizierter Scan-Einstiegs-Screen. Klarer als ein Screen mit
    /// drei gleichzeitigen Optionen.
    enum Step: Equatable {
        case transition, occasion, deadline, rhythm, preview
        case hasVocabQuestion, selectLists, scanPrompt
        case modules, celebration
    }

    @State var currentStep: Step
    @State var occasion: LearningOccasion?
    @State var deadline: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State var weeklyTarget: Int = LearningGoalPlan.defaultWeeklyTargetDays
    @State var hasVocabAlready: Bool?
    @State var selectedListIDs: Set<UUID> = []

    /// Zähler für das Auswahl-Blinken (siehe
    /// `OnboardingSelectionFlashModifier`). Steigt bei jedem Tap; die
    /// Karten vergleichen ihn gegen ihre eigene Auswahl.
    @State var selectionTick: Int = 0

    /// Skalierung des Vorschau-Titels — treibt den WOW-Auftritt.
    @State var previewHeadlineScale: CGFloat = 1.0

    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppTheme.Spacing.sm)

                ScrollView(showsIndicators: false) {
                    stepContent
                        .padding(.horizontal, AppLayout.screenPadding)
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xxl)
                        .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.22), value: currentStep)
    }

    // MARK: - Fortschritt

    /// **Vollständige** Schritt-Reihenfolge des aktuellen Pfads —
    /// inklusive der Maskottchen-Momente (Übergang, Vorschau, Module,
    /// Feier).
    ///
    /// **2026-08-05, Bug-Fix:** Vorher zählte der Balken nur die
    /// „Frage"-Schritte. Bei einem reinen Rhythmusziel („Einfach
    /// dranbleiben") gab es davon nur zwei — der Balken stand also
    /// schon bei „Wie oft schaffst du das?" auf voll, obwohl noch drei
    /// Screens folgten (User-Report). Jetzt läuft er über den ganzen
    /// Weg und ist exakt beim Plan-Screen am Ende voll.
    ///
    /// Dynamisch, weil Termin- und Vokabel-Schritte je nach Anlass
    /// entfallen.
    private var allSteps: [Step] {
        var steps: [Step] = [.transition, .occasion]
        if occasion?.requiresDeadline == true { steps.append(.deadline) }
        steps.append(.rhythm)
        steps.append(.preview)
        if occasion?.requiresListSelection == true {
            steps.append(.hasVocabQuestion)
            // Genau EINER der beiden Zweige wird gezeigt — welcher,
            // entscheidet die Ja/Nein-Antwort. Der Platz ist immer
            // reserviert, damit der Balken beim Antworten nicht
            // springt (die Gesamtzahl bleibt gleich, nur der Inhalt
            // des Slots wechselt).
            steps.append(hasVocabAlready == true ? .selectLists : .scanPrompt)
        }
        steps.append(.modules)
        steps.append(.celebration)
        return steps
    }

    /// 0 beim Übergangs-Screen, exakt 1.0 beim Plan-Screen.
    private var progressFraction: Double {
        guard let index = allSteps.firstIndex(of: currentStep) else { return 0 }
        return Double(index) / Double(max(1, allSteps.count - 1))
    }

    private var progressHeader: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if canGoBack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppTheme.Colors.secondarySurface))
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(stepAccentColor)
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.25), value: stepAccentColor)
        }
        .frame(height: 34)
    }

    private var canGoBack: Bool {
        currentStep != .transition && currentStep != .celebration
    }

    // MARK: - Schritt-Inhalt

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .transition:
            transitionStep
        case .occasion:
            occasionStep
        case .deadline:
            deadlineStep
        case .rhythm:
            rhythmStep
        case .preview:
            previewStep
        case .hasVocabQuestion:
            hasVocabQuestionStep
        case .selectLists:
            selectListsStep
        case .scanPrompt:
            scanPromptStep
        case .modules:
            modulesStep
        case .celebration:
            celebrationStep
        }
    }

    // MARK: - 1. Übergang

    /// **2026-08-05** — Elumi stellt sich jetzt explizit als Begleiter
    /// vor (User-Spec: "Elumi muss sich vorstellen... wirst dich jetzt
    /// hier in der App die ganze Zeit begleiten"), nicht nur eine
    /// neutrale Begrüßung. Später (nicht Teil dieses Passes) kann hier
    /// noch erwähnt werden, dass Elumi auch bei Hilfe/Fragen zur Seite
    /// steht — bewusst für jetzt ausgespart, um den Screen kurz zu halten.
    private var transitionStep: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer(minLength: AppTheme.Spacing.xxl)

            mascot

            // **2026-08-05, Umbau nach Gerätetest** — dieser Screen hat
            // vorher begrüßt ("Schön, dass du da bist" + "Ich bin
            // Elumi"). Damit stand er fast wortgleich hinter dem
            // Willkommens-Screen, der genau dasselbe sagt (User-Report:
            // "die ersten zwei Screens sind sehr ähnlich").
            //
            // Jetzt macht er das, wofür er da ist: **ankündigen und
            // begründen**. Der Nutzer soll wissen, was jetzt kommt und
            // warum es sich lohnt — statt ein zweites Mal begrüßt zu
            // werden. Begrüßt wird genau einmal, im Welcome-Screen.
            VStack(spacing: 14) {
                Text("Fangen wir mit deinem Ziel an, \(displayName).")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Darauf bau ich alles andere auf.")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.md)

                Text("Was du übst und wie oft, richtet sich danach. Dauert nur eine Minute.")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }

            Spacer(minLength: AppTheme.Spacing.xxl)
            Spacer(minLength: AppTheme.Spacing.xl)

            // **2026-08-05** — "Los geht's" → "Bin dabei!" (User-Spec:
            // "wir haben beim Onboarding zweimal Los geht's als CTA").
            // Der Willkommensscreen direkt davor sagt schon "Los geht's!",
            // und der Abschluss-Screen sagt "Jetzt geht's los" — dreimal
            // dieselbe Formel in einem Durchlauf.
            //
            // Geändert wird bewusst DIESER, nicht der Abschluss: dort
            // zahlt der Satz tatsächlich ein, weil es danach wirklich
            // losgeht. Hier ist es nur die Zustimmung zu Elumis "Fangen
            // wir mit deinem Ziel an" — eine Antwort passt besser als
            // ein Startruf. Nicht wörtlich "Ich bin bereit" (User-
            // Vorschlag), weil das zwei Schritte später schon der
            // CTA des Plan-Screens ist; dann stünde die Dopplung nur an
            // anderer Stelle.
            primaryButton("Bin dabei!") { advance() }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 500)
    }

    // MARK: - 8. Feier

    /// **2026-08-05, Umbau** — vorher sah dieser Screen dem
    /// "Du bist startbereit"-Screen aus dem Scan-Rückweg fast identisch
    /// (Maskottchen mittig, Titel, Untertitel, CTA) — User-Report: "das
    /// sieht alles sehr gleich aus".
    ///
    /// Jetzt trägt er echten, anderen Inhalt: eine kompakte
    /// Zusammenfassung dessen, worauf sich der Nutzer gerade festgelegt
    /// hat. Das ist gleichzeitig didaktisch besser — das Ziel wird
    /// einmal schwarz auf weiß gespiegelt, statt nur gefeiert zu werden.
    private var celebrationStep: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer(minLength: AppTheme.Spacing.md)

            HStack(spacing: AppTheme.Spacing.md) {
                compactMascot()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alles steht, \(displayName)!")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.elumiPink)
                        .fixedSize(horizontal: false, vertical: true)
                    // **2026-08-05** — größer (User-Spec: "Mach 'das ist
                    // dein Plan' noch größer").
                    Text("Das ist dein Plan:")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Spacer(minLength: 0)
            }

            // **2026-08-05** — Plan-Karte und alles darunter tiefer
            // gesetzt (User-Spec: "da machst du die Card mit dein Ziel
            // und Rhythmus etwas weiter runter und auch was darunter
            // kommt"). Gibt der Überschrift Luft und lässt den Plan als
            // eigenen Block wirken statt direkt anzuschließen.
            Spacer(minLength: AppTheme.Spacing.lg)

            goalSummaryCard

            Text("Keine Sorge, du kannst dein Ziel jederzeit ändern!")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.sm)

            Spacer(minLength: AppTheme.Spacing.lg)

            // **2026-08-05** — pulsierender Abschluss-CTA (User-Spec:
            // "den lässt du blinken, so wie wir's schon 'n paarmal in
            // der App drin haben"). Nutzt denselben `PulsingModifier`
            // wie Slot-Maschine, Pre-Screen-CTA und Chain-Weiter-Button.
            primaryButton("Jetzt geht's los") { completeOnboarding() }
                .pulsing(active: true, glowColor: AppTheme.Colors.cta)
        }
        .frame(maxWidth: .infinity)
    }

    /// Kompakte Ziel-Zusammenfassung: Anlass, Rhythmus, Bestand.
    /// Nutzt dieselben Card-Bausteine wie der Rest des Onboardings.
    private var goalSummaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                emoji: occasion?.emoji ?? "🙂",
                label: "Dein Ziel",
                value: occasion?.title ?? "Einfach dranbleiben"
            )
            summaryDivider
            summaryRow(
                emoji: "📅",
                label: "Dein Rhythmus",
                value: "\(weeklyTarget) Tage die Woche"
            )
            if occasion?.requiresListSelection == true {
                summaryDivider
                summaryRow(
                    emoji: "📚",
                    label: "Deine Vokabeln",
                    value: vocabSummaryValue
                )
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
    }

    private var vocabSummaryValue: String {
        let assignedCount = goalStore.plan?.content?.listIDs.count ?? 0
        let total = max(selectedListIDs.count, assignedCount)
        if total == 0 { return "Holen wir später" }
        return total == 1 ? "1 Liste" : "\(total) Listen"
    }

    /// **2026-08-05** — Werte deutlich größer (User-Spec: "mach den Plan
    /// in die Mitte mit 'dein Ziel' größer, 'deinen Rhythmus' auch
    /// größer"). Der Plan ist der inhaltliche Kern dieses Screens und
    /// war vorher kleiner gesetzt als die Überschrift darüber.
    private func summaryRow(emoji: String, label: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(emoji)
                .font(.system(size: 32))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.Colors.cardLabel)
                Text(value)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 15)
    }

    private var summaryDivider: some View {
        Divider()
            .background(AppTheme.Colors.border.opacity(0.4))
            .padding(.horizontal, AppTheme.Spacing.md)
    }

    // MARK: - Gemeinsame Bausteine

    /// Große, zeremonielle Fassung — Übergang, Vorschau, Feier.
    var mascot: some View {
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

    /// Kleinere Fassung für die reinen Frage-Screens (Anlass/Rhythmus/
    /// Vokabeln-Frage): Elumi bleibt als Begleiter sichtbar, damit
    /// nicht jeder Screen nur aus Text und Karten besteht.
    func compactMascot() -> some View {
        ZStack {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
            SplashCharacterBlinkOverlay(size: 52, startDate: .now)
                .frame(width: 52, height: 52)
        }
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
    }

    /// **2026-08-05** — eigener CTA-Stil statt `AppPrimaryButtonStyle`
    /// direkt: größere Schrift (User-Spec) plus ein verspielter
    /// Feder-Bounce beim Tippen ("kurz ausblinken... größer wird,
    /// kleiner wird") — bewusst NUR für dieses Onboarding, der Rest der
    /// App bleibt beim gewohnten, dezenteren Press-Feedback.
    func primaryButton(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
        }
        .buttonStyle(OnboardingCTAButtonStyle(color: AppTheme.Colors.cta))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    // 24 → 28 pt (User-Spec: Schriften größer, näher an der
    // YAZIO-Referenz statt App-üblicher Screen-Titel-Größe).
    func questionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var sectionAccent: AppSectionStyle { sectionStyle }

    /// **2026-08-05** — Akzentfarbe pro Schritt (User-Spec: "lass uns
    /// doch bei 'Wie oft schaffst du das' eine grüne Umrandung machen,
    /// das hebt sich ein bisschen ab").
    ///
    /// Die Anlass-Frage bleibt beim Home-Akzent (Pink), der
    /// Rhythmus-Schritt bekommt Emerald. Beides sind bestehende
    /// App-Farben, keine neuen erfunden. Der Wechsel macht nebenbei
    /// klar, dass hier eine andere Art von Frage kommt.
    var stepAccentColor: Color {
        switch currentStep {
        case .rhythm:
            return AppTheme.Colors.moduleNomen
        default:
            return sectionStyle.accent
        }
    }

    // MARK: - Schritt-Logik

    func advance() {
        switch currentStep {
        case .transition:
            currentStep = .occasion
        case .occasion:
            currentStep = (occasion?.requiresDeadline == true) ? .deadline : .rhythm
        case .deadline:
            currentStep = .rhythm
        case .rhythm:
            persistPlan()
            currentStep = .preview
        case .preview:
            currentStep = (occasion?.requiresListSelection == true) ? .hasVocabQuestion : .modules
        case .hasVocabQuestion:
            currentStep = (hasVocabAlready == true) ? .selectLists : .scanPrompt
        case .selectLists:
            currentStep = .modules
        case .scanPrompt:
            // Erreicht über den "Später"-Ausweg auf dem Scan-Screen —
            // der reguläre Weg von dort ist `handOffToScan()`, nicht
            // `advance()`.
            currentStep = .modules
        case .modules:
            currentStep = .celebration
        case .celebration:
            completeOnboarding()
        }
    }

    private func goBack() {
        switch currentStep {
        case .transition, .celebration:
            break
        case .occasion:
            currentStep = .transition
        case .deadline:
            currentStep = .occasion
        case .rhythm:
            currentStep = (occasion?.requiresDeadline == true) ? .deadline : .occasion
        case .preview:
            currentStep = .rhythm
        case .hasVocabQuestion:
            currentStep = .preview
        case .selectLists, .scanPrompt:
            currentStep = .hasVocabQuestion
        case .modules:
            if occasion?.requiresListSelection == true {
                currentStep = (hasVocabAlready == true) ? .selectLists : .scanPrompt
            } else {
                currentStep = .preview
            }
        }
    }

    /// Schreibt den Plan in `LearningGoalStore` — schon hier, nicht erst
    /// am Flow-Ende, damit der Scan-Einstieg sofort mit einem gültigen,
    /// wartenden Ziel arbeiten kann (`isAwaitingListAssignment`).
    private func persistPlan() {
        let content: LearningGoalContent?
        if let occasion, occasion != .stayOnTrack {
            content = LearningGoalContent(
                occasion: occasion,
                listIDs: [],
                deadline: occasion.requiresDeadline ? deadline : nil
            )
        } else {
            content = nil
        }
        goalStore.setPlan(LearningGoalPlan(weeklyTargetDays: weeklyTarget, content: content))
    }

    /// Regulärer Abschluss über den Feier-Screen: übernimmt eine im
    /// Listen-Schritt getroffene Auswahl (falls vorhanden) und gibt den
    /// Blick auf Home frei.
    func completeOnboarding() {
        if !selectedListIDs.isEmpty {
            goalStore.setLists(Array(selectedListIDs))
        }
        onDismissOverlay()
    }

    /// Handoff in den echten Scan-Flow: Plan steht bereits (persistiert
    /// in Schritt 4), das Overlay gibt sofort den Blick auf den
    /// gepushten Scan-Screen frei.
    ///
    /// **Der Ring schließt sich NICHT hier** — er läuft über
    /// `LearningGoalStore.pendingCelebrationRequested`: Der
    /// Import-Abschluss zeigt bei wartendem Ziel automatisch
    /// `OnboardingScanCompletionView` statt der normalen
    /// Modul-Auswahl (User-Feedback: acht Übungs-Kacheln direkt nach
    /// dem Onboarding-Scan waren die falsche nächste Aktion) und setzt
    /// beim "Let's go"-CTA dieses Signal. `RootContentView` beobachtet
    /// es und öffnet dieses Overlay erneut — direkt beim Feier-Screen.
    func handOffToScan() {
        navigate(.scan)
        onDismissOverlay()
    }
}

// MARK: - Onboarding-eigener Button-Stil

/// **2026-08-05** — verspielter Feder-Bounce für den primären CTA
/// dieses Onboardings (User-Spec: "muss 'n bisschen verspielt sein...
/// größer wird, kleiner wird"). Repliziert bewusst die Chrome-Logik
/// von `AppPrimaryButtonStyle` (Kontrast, Radius, Schatten), NICHT
/// diesen Stil selbst geändert — der ist app-weit im Einsatz und soll
/// sein gewohntes, dezenteres Verhalten behalten.
///
/// Nicht `private`, aus demselben Grund wie `listStore` oben: wird
/// auch aus `+Steps.swift` für die Karten-Auswahl gebraucht (dort ohne
/// eigene Chrome, siehe `OnboardingCardBounceStyle` unten).
struct OnboardingCTAButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color.isLightBackground ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.82 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(
                color: AppTheme.Shadow.button.color,
                radius: configuration.isPressed ? 3 : AppTheme.Shadow.button.radius,
                x: AppTheme.Shadow.button.x,
                y: configuration.isPressed ? 1 : AppTheme.Shadow.button.y
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.42), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { AppMotion.triggerSelectionHaptic() }
            }
    }
}

/// **2026-08-05** — leichte Variante für Karten mit eigener Chrome
/// (Anlass/Rhythmus/Ja-Nein/Listen-Zeilen): nur der Bounce, kein
/// Hintergrund/Schatten-Nachbau, weil die Card ihr Aussehen selbst
/// mitbringt.
struct OnboardingCardBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Auswahl-Blinken

/// **2026-08-05** — Quittungs-Blinken beim Auswählen einer Karte.
///
/// **Überarbeitet nach Gerätetest (User-Spec):** Vorher blinkte nur der
/// Rahmen, dreimal und sehr schnell. Rückmeldung: "das unruhige Blinken
/// des Randes ist eher nervös". Jetzt blinkt die **ganze Karte** heller
/// auf (Farbfläche über der Card), **fünfmal** und deutlich langsamer.
/// Die Größe bleibt bewusst unverändert — Skalieren wirkte zappelig.
///
/// **Bewusst mit expliziten, endlichen `withAnimation`-Aufrufen** statt
/// `.repeatCount` auf einer `.animation(value:)`-Kurve: Genau dieses
/// Muster hat heute früh den hängenden Mikrofon-Wackler verursacht
/// (siehe `ListeningPulseModifier`). Fest terminierte Ein-/Aus-Paare
/// können strukturell nicht hängenbleiben.
///
/// `trigger` ist ein Zähler, der bei jedem Tap hochzählt. Wert `0`
/// bedeutet "nicht ausgewählt" und löst nichts aus — dadurch blinkt
/// beim Umwählen nur die neu gewählte Karte, nicht die abgewählte.
struct OnboardingSelectionFlashModifier: ViewModifier {
    let trigger: Int
    let tint: Color
    let cornerRadius: CGFloat

    @State private var flashOn = false

    /// **2026-08-05, zweite Runde** — zurück auf zwei Blinks. Mit der
    /// flächigen Variante (statt Rahmen) und der langsameren Taktung
    /// reichen zwei aus; fünf wirkten dann wieder unruhig
    /// (User-Spec: "soll aber nur zweimal blinken, nicht öfter").
    private let flashCount = 2
    /// **2026-08-05, dritte Runde** — auf die Hälfte beschleunigt
    /// (User-Spec: "das Blinken der angetippten Cards doppelt so
    /// schnell"). Mit nur zwei Blinks wirkt das jetzt wie eine zügige
    /// Quittung statt wie Flackern — die frühere Unruhe kam aus der
    /// Kombination schnell UND oft, nicht aus dem Tempo allein.
    private let flashDuration: Double = 0.08
    private let flashInterval: Double = 0.17

    func body(content: Content) -> some View {
        content
            .overlay(
                // Flächiges Aufhellen statt Rahmen-Blitzen. `tint` ist
                // der Akzent des jeweiligen Schritts, dadurch bleibt das
                // Signal farblich im Kontext des Screens.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(flashOn ? 0.38 : 0))
                    .allowsHitTesting(false)
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue > 0 else { return }
                runFlash()
            }
    }

    private func runFlash() {
        for index in 0..<flashCount {
            let start = Double(index) * flashInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                withAnimation(.easeInOut(duration: flashDuration)) { flashOn = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + start + flashDuration + 0.02) {
                withAnimation(.easeInOut(duration: flashDuration)) { flashOn = false }
            }
        }
    }
}

extension View {
    /// Siehe `OnboardingSelectionFlashModifier`.
    func onboardingSelectionFlash(
        trigger: Int,
        tint: Color,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(
            OnboardingSelectionFlashModifier(
                trigger: trigger,
                tint: tint,
                cornerRadius: cornerRadius
            )
        )
    }
}
