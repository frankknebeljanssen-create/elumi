import SwiftUI

/// **Elumi-Tab — Single-Screen-Konzept** (User-Spec 2026-04-23 nacht).
///
/// Komplett umgebaut von „Persönlicher Begleiter mit Empfehlungs- und
/// Status-Cards" zu **einem** zusammenhängenden Trainingsgenerator-
/// Screen mit integrierter Slot Machine.
///
/// **Wichtig**: kein Screenwechsel mehr. Die alte separate
/// `TrainingGeneratorView` wird nicht mehr aufgerufen — der gesamte
/// Spin-/Result-Flow lebt jetzt direkt hier auf dem Tab.
///
/// **Layout-Update 2026-04-24 abend** (User-Spec):
/// ```
///   ModuleHeaderCard("Salut {name}!")
///   Card: „Wie lange willst du üben?" (10/15/20 Chips)  ← IMMER sichtbar
///   Slot Machine (immer sichtbar)
///   CTA „Los geht's!" — disabled bis Zeit gewählt
///   Card: „Dein Ergebnis" (flach)                       ← IMMER sichtbar
///       • vor Spin: Placeholder-Slots + „Deine Übungsmodule erscheinen hier"
///       • nach Reveal: 3 gezogene Symbole
///   CTA „Training starten" (nur nach Reveal)
/// ```
///
/// State-Maschine:
///   • idle      — Slot wartet, „Los geht's" aktiv (wenn Zeit gewählt)
///   • spinning  — Reels laufen, „Los geht's" deaktiviert
///   • stopping  — Stagger-Stops, „Los geht's" deaktiviert
///   • landed    — alle Reels stehen, „Los geht's" noch deaktiviert
///   • revealed  — Ergebnis sichtbar, „Los geht's" wieder aktiv (= Re-Spin),
///                 zusätzlich „Training starten" sichtbar
struct ElumiTabView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void

    /// **Stufe 1c (2026-04-30)** — VocabularyListStore wird vom
    /// AppDestinationHost durchgereicht, damit das Setup-Modal die
    /// Listen-Auswahl-Card mit echten Listen-Namen befüllen und der
    /// `ChainListSelectionSheet` `allLists` rendern kann.
    @ObservedObject var listStore: VocabularyListStore

    @ObservedObject private var profileStore = ProfileStore.shared
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    /// **Pool-Vereinheitlichung 2026-04-30 (Stufe 1b)** — `@AppStorage`-
    /// Mirror auf den bare `appArcadeCreditsKey`. Wird nach Slot-Spin-
    /// Increment aus `ProgressStore.shared.progress.arcadeCredits`
    /// gespiegelt, damit der Footer-Badge (`AppBottomBarView`) und
    /// andere bare-Key-Reader sofort den neuen Wert sehen. Pattern
    /// identisch zu FlashcardsView+SessionComponents:42,
    /// TrainingView+SessionFlow:61/89, QuizView+Flow:262.
    ///
    /// **Hintergrund:** ProgressStore namespaces den Key per Account,
    /// `@AppStorage` liest aber den bare-Key. Die Bestand-App lebt mit
    /// dem Dual-Write-Pattern; wir folgen ihm hier statt eine
    /// Architektur-Sanierung als Side-Quest aufzumachen.
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0

    // MARK: - Slot-Machine + Trainingsgenerator-State (vorher in TrainingGeneratorView)

    /// **Trainings-Chain-Store** (Stufe 1, 2026-04-30, Branch
    /// `feature/training-session-flow`). In-Memory-State für die
    /// auto-verkettete Übungs-Sequenz aus dem Slot-Ergebnis. Wird beim
    /// `startTraining()`-Tap befüllt; Stufe 2 verbindet die Modul-Done-
    /// CTAs daran. Persistiert nicht — Chain überlebt App-Restart nicht.
    ///
    /// Der frühere `@StateObject generatorStore = TrainingGeneratorStore`
    /// ist mit Stufe 1 obsolet (Audit-Verifikation 2026-04-30: einzige
    /// Live-Call-Site war `startTraining()`, jetzt durch Chain-Builder
    /// ersetzt). Die 3 Generator-Files
    /// (`TrainingGenerator.swift`, `TrainingGeneratorStore.swift`,
    /// `TrainingGeneratorModels.swift`) sind als Dead-Code markiert,
    /// Removal als Backlog-Item in TODO_post_v1b.md.
    ///
    /// **Stufe 2 (2026-04-30)**: aus `@StateObject` auf
    /// `@ObservedObject … .shared` umgestellt. Der Chain-Store wird ab
    /// Stufe 2 von zwei Stellen referenziert (hier zum Befüllen, plus
    /// `TrainingChainOverviewView` für Back-Chevron-Clear via Closure).
    /// Singleton-Pattern matcht `ProgressStore.shared`/`AccountStore.shared`.
    ///
    /// **Performance-Fix 2026-05-01 (Hypothese A)**: `@ObservedObject`
    /// entfernt zugunsten eines direkten Singleton-Aufrufs in
    /// `startTraining()`. Hintergrund: ab Stufe 4a hat der Store einen
    /// 1-Hz-Timer mit vier zusätzlichen `@Published`-Properties
    /// (`stepRemainingSeconds`, `stepTotalSeconds`, `timerExpired`,
    /// `hasShownExpirationToast`). Während eine Chain läuft (z.B.
    /// nachdem User aus Modul ohne `clear()` zurück zum Tab kommt) feuert
    /// der Store jede Sekunde `objectWillChange` → ElumiTabView
    /// re-renderte mit. Der 60fps-Slot-Spin-Loop hatte dadurch
    /// sichtbare Hakler. Da ElumiTabView den Store ausschließlich
    /// schreibend nutzt (nur `chainStore.start(chain)` in
    /// `startTraining()`, keine reactive Reads im Body), war der
    /// `@ObservedObject`-Wrapper überflüssig — der Direkt-Singleton-
    /// Call entkoppelt das Re-Render-Verhalten komplett. Andere
    /// Konsumenten der Timer-State (`ChainTimerOverlayModifier`)
    /// observieren weiter, wie es by design sein soll, weil sie die
    /// Timer-Bar live aktualisieren.
    @StateObject var dropRate = ElumiDropRateControllerStore()
    @StateObject var budget = SlotMachineSpinBudgetStore()
    // **Pool-Vereinheitlichung 2026-04-30 (Stufe 1b)**: der frühere
    // `@ObservedObject playCredits = ElumiCreditsStore.shared` ist
    // entfernt. Der Slot-Spin schreibt jetzt direkt auf
    // `appArcadeCreditsKey` via `ProgressStore.shared.mutate` (siehe
    // `handleSlotLanded`). Rescue/Skip im Arcade-Spiel verbrauchen
    // ebenfalls aus dem `arcadeCredits`-Pool. Single-Source-of-Truth
    // ist `ProgressStore.shared.progress.arcadeCredits` (mit
    // `@AppStorage`-Mirror in den Modul-Views).

    /// **User-gewählte Trainingsdauer in Minuten — Sache B Stufe 1
    /// (2026-04-29).** Persistiert via `@AppStorage` (Account-namespaced
    /// über `AccountScopedKeys.userDefaultsKeys`). Default-Wert kommt
    /// aus `Self.durationDefault` (= 10) — der `@AppStorage`-Init liefert
    /// 10 zurück, solange kein Wert persistiert ist. Nach dem ersten
    /// Modal-Close (Stufe 2) wird der aktuelle Wert idempotent in
    /// UserDefaults geschrieben.
    ///
    /// **Vorgängerstand:** `@State Int? = nil` — Forcing-Function für
    /// bewusste Wahl. Mit Sache B aufgegeben zugunsten konsistenter
    /// Modal-Dismiss-Semantik (immer Backdrop-tappable, immer Preselect).
    @AppStorage(appTrainingGeneratorDurationKey)
    var selectedDuration: Int = ElumiTabView.durationDefault

    /// **UX-Polish 2026-05-02 (Stufe 7)** — pure View-State für die
    /// Setup-Modal-Selektion. `selectedDuration` (oben) bleibt als
    /// persistierter Slot-Screen-Anzeigewert. Im Modal verwenden wir
    /// dagegen einen Optional-State, der bei jedem Modal-Open
    /// **explizit auf `nil` zurückgesetzt** wird (siehe
    /// `openSetupModalForReEdit`/`triggerStartTraining` Pfade) — User-
    /// Spec: kein Default-Preselect, der User soll bewusst eine
    /// Zeit wählen, bevor der „Los geht's"-CTA aktiv wird. Bei Tap
    /// auf einen Chip wird sowohl `modalDurationSelection` als auch
    /// `selectedDuration` gesetzt; CTA-Tap dismisst das Modal mit dem
    /// (jetzt gültig persistierten) Wert.
    @State var modalDurationSelection: Int? = nil
    /// **Daily Drop Modul 3 (2026-05-23)** — Anzahl-Picker (ersetzt die
    /// „Wie lange?"-Zeitwahl). Gewählte Gesamt-Übungszahl (10/20/30 =
    /// Kurz/Mittel/Lang). Optional → kein Default-Preselect, bewusste Wahl;
    /// dient zugleich als Gate für `canTriggerSpin`. Die Duration-States
    /// oben (`selectedDuration`/`modalDurationSelection`) sind damit toter
    /// Code (separater Cleanup, User-Spec).
    @State var modalExerciseSelection: Int? = nil
    /// **Daily Drop Modul 3 (2026-05-23)** — gecachte Material-Basis
    /// (`min(quizUsable, vokabelUsable)` der globalen Auswahl). Bestimmt,
    /// welche Längen anbietbar sind. Wird bei Modal-Open + Selection-Change
    /// neu berechnet (`recomputeDailyDropMaterial`), NICHT pro Render.
    @State var cachedDailyDropMaterial: Int = 0
    /// Slot-Phase — externe Sicht der State-Maschine in `SlotMachineView`.
    @State var slotPhase: SlotPhase = .idle
    /// Trigger-Token — Setzen auf `true` startet einen Spin.
    @State var slotStartToken: Bool = false
    /// Ziel-Symbole pro Reel — vor dem Spin gefüllt.
    @State var spinTargets: [ReelSymbol?] = [nil, nil, nil]
    /// Letztes Spin-Ergebnis — Quelle für die Ergebnis-Sektion.
    @State var lastSpinResult: SlotSpinResult?

    /// **Stufe 2 (2026-04-30, Branch `feature/training-session-flow`)** —
    /// Idempotenz-Flag für den Credit-Grant in `startTraining()`. Wird
    /// in `handleSlotLanded` für jeden neuen Spin auf `false` zurück­
    /// gesetzt, in `startTraining()` nach erfolgreichem Grant auf `true`
    /// gesetzt. Verhindert die „Re-Roll-Cheat-Variante 2": User tappt
    /// „Jetzt üben" → kassiert Tickets → Back-Chevron auf dem Pre-
    /// Screen → tappt erneut „Jetzt üben" → würde sonst nochmal Tickets
    /// kassieren (selber Spin-Ergebnis). Mit dem Flag ist der zweite
    /// Tap idempotent: Chain wird neu gebaut, Pre-Screen wieder
    /// gepusht, aber **keine** Tickets gutgeschrieben.
    ///
    /// Variante 1 (mehrere Drehungen ohne „Jetzt üben") ist davon
    /// unabhängig — die ist über die `pendingResult`-Konstante in
    /// `startTraining` schon abgedeckt: nur das **letzte**
    /// `lastSpinResult` wird verwertet.
    @State var creditGrantConsumed: Bool = false

    // MARK: - Jackpot-Feier (Block 5, 2026-05-03)
    //
    // Wird ausgelöst, sobald die Slot-Machine in `.revealed` wechselt
    // und alle drei Reels ein Game-Symbol (`elumiCount == 3`) zeigen.
    // Statt User auf den `TrainingChainOverviewView`-Pre-Screen mit
    // „Jackpot — kein Training!" zu pushen, feiern wir an Ort und
    // Stelle (siehe `JackpotCelebrationView`). Tickets-Grant findet
    // bei der Reveal-Detection direkt statt (analog zur
    // `startTraining`-Logik), damit der Counter im Overlay sofort
    // hochzählen kann und der Footer-Badge synchron mitzieht.
    @State var showJackpotCelebration: Bool = false
    @State var jackpotConfettiStartDate: Date = .distantPast
    @State var jackpotTicketsBefore: Int = 0
    @State var jackpotTicketsGranted: Int = 0

    // MARK: - Versuchslogik (2026-04-24 User-Spec)
    //
    // Genau **drei** Versuche pro Trainings-Setup. Counter erhöht sich
    // NUR nach einem tatsächlich abgeschlossenen Spin (in
    // `handleSlotLanded`) — nicht beim Button-Tap, nicht bei
    // abgebrochener Animation. Nach dem 3. Spin transformiert die
    // „Los geht's"-Card in eine „Training starten"-Card. Reset erfolgt
    // bei Start des Trainings (sodass der User bei Rückkehr frische
    // Versuche hat).

    /// Max. Anzahl Spin-Versuche pro Trainings-Setup.
    let maxSpins: Int = 3

    /// Anzahl bereits abgeschlossener Spins (0…maxSpins).
    @State var currentSpinNumber: Int = 0

    // MARK: - Setup-Modal (Sache B Stufe 2, 2026-04-29)
    //
    // Erstmaliges Öffnen des Trainings-Generators auf dem Elumi-Tab
    // zeigt ein Setup-Modal mit Zeit-Chips (10/15/20) + „Los geht's"-
    // CTA. Default-Preselect ist `Self.durationDefault` (= 10), Backdrop-
    // Tap ist erlaubt (übernimmt aktuellen Preselect). Persistenz des
    // Seen-Flags per-Account namespaced (siehe
    // `appTrainingGeneratorOnboardingSeenKey` — Key-Name unverändert
    // zur ursprünglichen Onboarding-Stufe, weil's konzeptionell derselbe
    // „erstmaliger Öffnungs-Hint"-Slot ist; nur das Modal ist umgewidmet
    // von Steps-Erklärung zu funktionaler Zeit-Wahl).
    //
    // Read aus dem account-namespaced Slot via
    // `AccountStore.shared.namespacedKey(...)` — dieselbe Strategie
    // wie `appOnboardingCompletedKey` in `ProfileStore`.
    @State var showSetupModal: Bool = false

    // MARK: - Listen-Auswahl-Card (Stufe 1c, 2026-04-30)

    /// Sheet-Trigger für den `ChainListSelectionSheet` (Multi-Select
    /// der globalen Listen-Auswahl). Tap auf die Listen-Card im Setup-
    /// Modal setzt diesen auf `true`; das Sheet persistiert beim
    /// „Fertig"-Tap und schreibt zurück in `globalSelectedListIDs`.
    @State var showListPicker: Bool = false

    /// Lokaler Mirror der globalen Listen-Auswahl. Initialisiert in
    /// `mainContent.onAppear` aus
    /// `VocabularyListSelectionResolver.currentGlobalSelectedListIDs()`,
    /// nach Sheet-Close via `onCommit`-Callback aktualisiert. Wird in
    /// der Listen-Card im Setup-Modal als Source angezeigt und treibt
    /// die `Los geht's`-CTA-Disable-Logik (leer → CTA disabled).
    ///
    /// **Empty-State-Note (Spec)**: Wenn der Resolver `nil` zurückgibt
    /// (User hat noch nie etwas Globales gewählt), bleibt dieses Set
    /// leer — Card zeigt „Keine Liste gewählt", CTA ist disabled. Der
    /// User MUSS aktiv mindestens eine Liste wählen, bevor er ins
    /// Training geht. (Settings-Toggle-Initial-Default
    /// `Grundwortschatz A1` greift nur, wenn der Toggle erstmals
    /// aktiviert wird — der Chain-Pfad ist davon unabhängig.)
    @State var globalSelectedListIDs: Set<UUID> = []

    /// Können noch Spins getriggert werden?
    var hasRemainingSpins: Bool { currentSpinNumber < maxSpins }

    /// Anzeige-String für den Versuchszähler („Versuch 1/3", usw.).
    /// Zeigt den GERADE zu startenden Versuch — also +1 gegenüber
    /// abgeschlossenen.
    var currentAttemptDisplay: String {
        "Versuch \(min(currentSpinNumber + 1, maxSpins))/\(maxSpins)"
    }

    /// **CTA-Label-Dynamik** (UX Stufe 3, 2026-04-29):
    ///   • 0 Spins → ein Button „Los geht's!" (erster Versuch, full-width)
    ///   • 1–2 Spins → zwei Buttons nebeneinander („Nochmal drehen" links,
    ///     „Jetzt üben" rechts) + Caption „Versuch X von 3" darüber
    ///   • 3 Spins → ein Button „Jetzt üben" (Spin-Phase vorbei)
    /// Das Label „Jetzt üben" bleibt identisch zwischen 2-Button-State
    /// und post-Spin-3-State — Konsistenz für den User.
    var spinPrimaryLabel: String {
        // **2026-05-23 (User-Spec)** — „Drop starten" → „Maschine starten".
        // Benennt die Slot-Mechanik direkt. Nach erstem Spin bleibt
        // „Nochmal drehen" — Re-Spin-Variante kommuniziert weiterhin die
        // Slot-Mechanik.
        currentSpinNumber == 0 ? "Maschine starten" : "Nochmal drehen"
    }

    let sectionStyle: AppSectionStyle = .elumi

    // MARK: - Palette (2026-04-25 User-Spec „Pink reduzieren")
    //
    // Exakte Hex-Werte aus dem User-Spec — Single Source of Truth,
    // damit die Farben screen-übergreifend konsistent bleiben.
    //
    // **Sache B Stufe 3 (2026-04-29) Cleanup**: die Tokens
    // `durationCardBackground` (#E8F7F4) und `durationCardBorder`
    // (#CFEDE7) sind entfernt. Sie waren ein legacy Mint-Hintergrund-
    // Versuch der ehemaligen `durationCard`, der bereits 2026-04-25
    // zugunsten von `appSetupCardBackground()` rückgängig gemacht
    // wurde. Mit dem Wegfall der `durationCard` (jetzt `timeDisplayCard`)
    // sind die Tokens auch konzeptionell tot.
    //
    // **2026-04-25 Kontrast-Pass**: Chip-Farben aus den App-Standard-
    // Tokens — hell-auf-hell (mint-auf-mint) war nicht ausreichend
    // lesbar. Unselected = `secondarySurface` (app-weit für
    // Auswahl-Elemente), Selected = `textPrimary` (dunkel) + weiße
    // Schrift für maximalen Kontrast. Keine neuen Farben erfunden.

    /// Primärer CTA-Gelbton — derselbe Yellow für alle Primary-Buttons
    /// im Trainingsgenerator. Dunkle Schrift für maximalen Kontrast.
    let ctaYellow: Color = Color(hex: "#FFD54F")
    /// Glow-Farbe für das hervorgehobene Ergebnis — warmer Gelb-Ton,
    /// kein Pink mehr.
    let resultGlowColor: Color = Color(hex: "#FFE08A")

    // MARK: - Result-Highlight-State (2026-04-25 User-Spec)

    /// Initial-Burst-Skalierung nach `.revealed` — kurz >1.0, dann
    /// zurück auf 1.0.
    @State var resultHighlightScale: CGFloat = 1.0
    /// Glow-Intensität auf der Result-Card. Wird nach dem Reveal erst
    /// stark aktiviert (Initial-Burst), dann sanft pulsierend.
    @State var resultHighlightGlow: Double = 0.0

    /// **Setup-Tweaks v2 — C2 (2026-04-30)**: Erweitert auf 4 Optionen
    /// inkl. neuer 5min-Variante (kürzeste Übungseinheit). 5min wird
    /// vom `TrainingGenerator` via `buildFiveMinute(focus:)` korrekt
    /// in 2 Blöcke (Warmup 2 + Kern 3min) aufgeteilt — verifiziert
    /// vor dem Branch-Start. Default bleibt 10min (`durationDefault`).
    /// **Spec-1 (2026-04-30, Branch `feature/training-session-flow`)** — die
    /// Trainingsdauer-Optionen sind von [5, 10, 15, 20] auf [6, 12, 18]
    /// umgestellt. Begründung: 6/12/18 sind sauber durch 2 und 3 teilbar
    /// und passen damit zur 3-Reel-Chain (Modul-Slots können gleichmäßig
    /// die Gesamtdauer aufteilen, ohne Restzeit-Kosmetik). Default ist
    /// 12 min (mittlere Option, ein Stufe drüber dem alten 10er-Default).
    ///
    /// **Migration für existierende User**: defensive-on-Launch in
    /// `mainContent.onAppear` — wenn `selectedDuration` nicht in
    /// `durationOptions` ist (z.B. User hatte 10/15/20 gespeichert), wird
    /// einmalig auf `durationDefault` (= 10) gesetzt. Idempotent: der
    /// Korrekturpfad wird beim ersten Open ausgeführt und bei allen
    /// Folge-Opens als no-op übersprungen.
    //
    // **Naming-Sweep 2026-05-06** — Optionen 3/12/18 → 5/10/15.
    // Standard-Zeiten, intuitiv, alle in 5er-Schritten. Default
    // (`durationDefault`) ist die mittlere Option (10 min) — beim
    // Daily-Drop-Modus passt eine kurze Standard-Session besser
    // als die alten 12 min.
    private static let durationOptions: [Int] = [5, 10, 15]

    /// **Daily Drop Modul 3 (2026-05-23)** — Anzahl-Optionen (Übungen
    /// gesamt): Kurz/Mittel/Lang. Ersetzt `durationOptions` (Minuten, tot).
    static let exerciseCountOptions: [Int] = [10, 20, 30]
    /// Default-Übungszahl (Mittel) — Anzeige-Fallback, falls noch keine
    /// Wahl getroffen wurde (der Slot ist bis zur Wahl ohnehin gegated).
    static let exerciseCountDefault: Int = 20

    /// **Slot-Spin Credit-Mapping** (Pool-Vereinheitlichung 2026-04-30,
    /// Stufe 1b). Aus dem ehemaligen `ElumiCreditsStore.GrantTable`
    /// in den Tab gezogen, weil der Store entfernt wurde. Mapping
    /// unverändert: 1× Game → +1 Credit, 2× → +3, 3× → +6. Wird in
    /// `handleSlotLanded` konsumiert.
    static let slotCreditGrantTable: [Int: Int] = [1: 1, 2: 3, 3: 6]

    /// **Single Source für die Default-Trainingsdauer** (Sache B Stufe 1,
    /// 2026-04-29). Wird sowohl als `@AppStorage`-Initialwert für
    /// `selectedDuration` verwendet als auch — ab Stufe 2 — als Modal-
    /// Preselect beim allerersten Open. Keine Duplikation an anderen
    /// Stellen: alle „falls nichts gewählt"-Pfade lesen diesen Wert.
    static let durationDefault: Int = 10

    // MARK: - Body

    var body: some View {
        // **2026-04-24 Vereinfachung**: Status-Card am Footer komplett
        // entfernt — sie war die „halb sichtbar unter Footer"-Card.
        // Kein `.safeAreaInset(.bottom)` mehr → bottom-padding deutlich
        // reduziert, damit nichts mehr unter dem AppBottomBar hängt.
        ZStack {
            mainContent
            // **Sache B Stufe 2 (2026-04-29)** — Setup-Modal über dem
            // gesamten Tab-Inhalt. Vor Sache B war das ein Onboarding-
            // Hint mit 3 Schritten und nicht-tappable Backdrop. Jetzt:
            // funktionales Setup-Modal mit Zeit-Chips, Backdrop-Tap
            // dismisst (übernimmt aktuellen Preselect — kein „undefined
            // state" möglich, weil `selectedDuration` immer einen
            // sinnvollen Wert hält).
            if showSetupModal {
                setupModalOverlay
                    .zIndex(20)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            // **Jackpot-Feier-Overlay** (Block 5, 2026-05-03). Liegt
            // über dem Setup-Modal-Layer, weil ein Jackpot logisch nach
            // dem Setup kommt — ein gleichzeitiges Setup-Modal sollte
            // ohnehin nie gleichzeitig sichtbar sein, aber höhere
            // zIndex schützt gegen Race-Conditions.
            if showJackpotCelebration {
                JackpotCelebrationView(
                    startDate: jackpotConfettiStartDate,
                    ticketsBefore: jackpotTicketsBefore,
                    ticketsGranted: jackpotTicketsGranted,
                    onSpinAgain: handleJackpotSpinAgain,
                    onGoHome: handleJackpotGoHome
                )
                .zIndex(30)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showSetupModal)
        .animation(.easeInOut(duration: 0.3), value: showJackpotCelebration)
        .onAppear {
            // **Spec-1 Migration (2026-04-30)**: Defensive-on-Launch.
            // User mit altem `selectedDuration` (5/10/15/20) → einmal
            // auf neuen Default (12) korrigieren. Idempotent — bei allen
            // Folge-Opens, sobald der Wert in `durationOptions` liegt,
            // ist der Korrekturpfad ein no-op. Schreibung erfolgt nur
            // wenn der gespeicherte Wert ungültig ist (kein Schema-Bump,
            // kein Migration-Flag, multi-device-safe).
            if !Self.durationOptions.contains(selectedDuration) {
                #if DEBUG
                appDebugLog("🕒 [DurationMigration] selectedDuration=\(selectedDuration) ∉ \(Self.durationOptions) → reset to \(Self.durationDefault)")
                #endif
                selectedDuration = Self.durationDefault
            }
            // **Stufe 1c (2026-04-30)**: Initial-Load der globalen
            // Listen-Auswahl in den lokalen `@State`-Mirror. Wenn der
            // Resolver `nil` zurückgibt (User hat noch nie etwas global
            // gewählt), bleibt das Set leer — Card zeigt Empty-State,
            // CTA wird disabled. Read passiert auf jedem Tab-Open, damit
            // externe Änderungen (z.B. via Settings) reflektiert werden.
            globalSelectedListIDs = VocabularyListSelectionResolver.currentGlobalSelectedListIDs() ?? []
            // **2026-06-09** — Beim allerersten Öffnen (Erstnutzer-Hint
            // „daily_drop_intro" noch ungesehen) NICHT sofort das Setup-
            // Modal zeigen — sonst poppen Hint und „Wie viele Übungen?"-
            // Picker gleichzeitig auf. Der Hint triggert das Modal selbst
            // via `onDismiss` unten, sobald er weggetippt wurde.
            if HintStore.shared.hasSeen("daily_drop_intro") {
                checkSetupModalState()
            }
        }
        // **Daily Drop Modul 3 (2026-05-23)** — Material-Gating neu zählen,
        // wenn der User die globale Listen-Auswahl ändert (z. B. via
        // GlobalListPickerSheet). Hält die Längen-Verfügbarkeit aktuell,
        // ohne pro Render zu rechnen.
        .onChange(of: globalSelectedListIDs) { _, _ in
            recomputeDailyDropMaterial()
        }
    }

    /// Zeigt das Setup-Modal beim Tab-Mount **immer** (Spec-Update
    /// 2026-04-30): das Modal ist jetzt der primäre Setup-Touchpoint
    /// vor jeder Trainings-Session, nicht mehr ein einmaliger
    /// Onboarding-Hint. Der bisherige `appTrainingGeneratorOnboarding-
    /// SeenKey`-Lesepfad ist hier weg; die persistierte
    /// `selectedDuration` (Sache-B-Stufe-1-`@AppStorage`) sorgt
    /// automatisch für den richtigen Preselect — User sieht beim
    /// nächsten Tab-Open seine zuletzt gewählte Zeit (z. B. 15 min),
    /// nicht den Default 10.
    ///
    /// Der Seen-Marker bleibt auf existierenden Geräten als toter
    /// Wert in UserDefaults — siehe Doc in `AppStorageKeys.swift`.
    /// Der State-Toggle ist in `withAnimation` gewrappt, damit die
    /// `.transition(...)` am Card-View garantiert anspringt (implicit
    /// `.animation(value:)` reicht hier nicht zuverlässig, weil der
    /// State-Change in einer Funktion außerhalb des View-Bodys passiert).
    func checkSetupModalState() {
        // **2026-05-06 Refactor (Pop-up-Only)** — Pop-up zeigt sich nur
        // wenn der User in dieser Session noch keine Zeit aktiv gewählt
        // hat (`modalDurationSelection == nil`). Vorher öffnete das
        // Modal bei jedem Tab-Open neu mit Zeit-Reset — das war zu
        // aggressiv, sobald die Listen-Card weg ist und die Zeit-
        // Auswahl die einzige Wahl bleibt. Beim Skip-X bleibt
        // `modalDurationSelection` nil → CTA bleibt disabled, Pop-up
        // zeigt sich beim nächsten Tab-Open wieder.
        guard modalExerciseSelection == nil else { return }
        // **Daily Drop Modul 3 (2026-05-23)** — Material frisch zählen,
        // bevor der Picker erscheint (gegated Längen).
        recomputeDailyDropMaterial()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showSetupModal = true
        }
    }

    /// Blendet das Setup-Modal aus.
    ///
    /// **Spec-Update 2026-04-30**: Modal erscheint jetzt bei jedem
    /// Tab-Open — der Seen-Marker-Write ist deshalb obsolet (wird
    /// nicht mehr gelesen) und entfernt. Auf existierenden Geräten
    /// bleibt der UserDefaults-Eintrag liegen; harmlos, kein Migration-
    /// Pfad nötig (analog zum verwaisten `appIconSet`-Key aus Stufe 6).
    ///
    /// **Idempotenz-Hinweis** (Sache B Stufe 2 — bleibt gültig): Diese
    /// Funktion schreibt NICHT den Duration-Key — `selectedDuration`
    /// ist via `@AppStorage` markiert und persistiert sich automatisch
    /// bei jeder Chip-Tap-Mutation. Das gilt für alle Pfade, über die
    /// das Modal geschlossen werden kann (CTA-Tap, Backdrop-Tap,
    /// Pencil-Re-Edit-Schließen). Der Backdrop-Tap nimmt also den
    /// aktuellen Preselect des Modals als Wahl mit, ohne dass diese
    /// Funktion etwas dafür tun muss.
    ///
    /// Spring-Wrapping wie in `checkSetupModalState()` — damit die Exit-
    /// Transition zuverlässig sichtbar ist.
    func dismissSetupModal() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showSetupModal = false
        }
    }

}
