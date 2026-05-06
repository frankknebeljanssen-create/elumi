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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

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
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0

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
    @StateObject private var dropRate = ElumiDropRateControllerStore()
    @StateObject private var budget = SlotMachineSpinBudgetStore()
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
    private var selectedDuration: Int = ElumiTabView.durationDefault

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
    @State private var modalDurationSelection: Int? = nil
    /// Slot-Phase — externe Sicht der State-Maschine in `SlotMachineView`.
    @State private var slotPhase: SlotPhase = .idle
    /// Trigger-Token — Setzen auf `true` startet einen Spin.
    @State private var slotStartToken: Bool = false
    /// Ziel-Symbole pro Reel — vor dem Spin gefüllt.
    @State private var spinTargets: [ReelSymbol?] = [nil, nil, nil]
    /// Letztes Spin-Ergebnis — Quelle für die Ergebnis-Sektion.
    @State private var lastSpinResult: SlotSpinResult?

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
    @State private var creditGrantConsumed: Bool = false

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
    @State private var showJackpotCelebration: Bool = false
    @State private var jackpotConfettiStartDate: Date = .distantPast
    @State private var jackpotTicketsBefore: Int = 0
    @State private var jackpotTicketsGranted: Int = 0

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
    private let maxSpins: Int = 3

    /// Anzahl bereits abgeschlossener Spins (0…maxSpins).
    @State private var currentSpinNumber: Int = 0

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
    @State private var showSetupModal: Bool = false

    /// **2026-05-06** — Aktuell sichtbarer Header-Hint. Wird beim
    /// Tab-Mount und bei jedem Tab-Re-Visit (`.onAppear` im
    /// `mainContent`) zufällig aus `ElumiHints.pool` gezogen.
    /// Initial-Value ist ein Random-Pick, damit beim allerersten
    /// View-Build schon ein Hint da ist (statt eines leeren Strings,
    /// der erst durch onAppear gefüllt würde).
    @State private var currentHint: String = ElumiHints.random()

    // MARK: - Listen-Auswahl-Card (Stufe 1c, 2026-04-30)

    /// Sheet-Trigger für den `ChainListSelectionSheet` (Multi-Select
    /// der globalen Listen-Auswahl). Tap auf die Listen-Card im Setup-
    /// Modal setzt diesen auf `true`; das Sheet persistiert beim
    /// „Fertig"-Tap und schreibt zurück in `globalSelectedListIDs`.
    @State private var showListPicker: Bool = false

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
    @State private var globalSelectedListIDs: Set<UUID> = []

    /// Können noch Spins getriggert werden?
    private var hasRemainingSpins: Bool { currentSpinNumber < maxSpins }

    /// Anzeige-String für den Versuchszähler („Versuch 1/3", usw.).
    /// Zeigt den GERADE zu startenden Versuch — also +1 gegenüber
    /// abgeschlossenen.
    private var currentAttemptDisplay: String {
        "Versuch \(min(currentSpinNumber + 1, maxSpins))/\(maxSpins)"
    }

    /// **CTA-Label-Dynamik** (UX Stufe 3, 2026-04-29):
    ///   • 0 Spins → ein Button „Los geht's!" (erster Versuch, full-width)
    ///   • 1–2 Spins → zwei Buttons nebeneinander („Nochmal drehen" links,
    ///     „Jetzt üben" rechts) + Caption „Versuch X von 3" darüber
    ///   • 3 Spins → ein Button „Jetzt üben" (Spin-Phase vorbei)
    /// Das Label „Jetzt üben" bleibt identisch zwischen 2-Button-State
    /// und post-Spin-3-State — Konsistenz für den User.
    private var spinPrimaryLabel: String {
        // Erster Spin: „Maschine jetzt starten!" — direkter, energischer
        // Imperativ + Ausrufungszeichen markieren den Spin-Moment als
        // bewusste Aktion (User-Spec 2026-05-06 „Sprach-Polish"). Vorher
        // „Maschine starten" — neutral, unter den anderen CTAs nicht
        // prominent genug. Nach erstem Spin: „Nochmal drehen" für die
        // Re-Spin-Variante (unverändert; ist bereits klar, weil neben
        // dem „Jetzt üben"-Button positioniert).
        currentSpinNumber == 0 ? "Maschine jetzt starten!" : "Nochmal drehen"
    }

    private let sectionStyle: AppSectionStyle = .elumi

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
    private let ctaYellow: Color = Color(hex: "#FFD54F")
    /// Glow-Farbe für das hervorgehobene Ergebnis — warmer Gelb-Ton,
    /// kein Pink mehr.
    private let resultGlowColor: Color = Color(hex: "#FFE08A")

    // MARK: - Result-Highlight-State (2026-04-25 User-Spec)

    /// Initial-Burst-Skalierung nach `.revealed` — kurz >1.0, dann
    /// zurück auf 1.0.
    @State private var resultHighlightScale: CGFloat = 1.0
    /// Glow-Intensität auf der Result-Card. Wird nach dem Reveal erst
    /// stark aktiviert (Initial-Burst), dann sanft pulsierend.
    @State private var resultHighlightGlow: Double = 0.0

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
    /// einmalig auf `durationDefault` (= 12) gesetzt. Idempotent: der
    /// Korrekturpfad wird beim ersten Open ausgeführt und bei allen
    /// Folge-Opens als no-op übersprungen.
    // TODO: 3 ist temporär für Smoke-Test (Stufe 4b-Chain-Tests),
    // später wieder zurück zu 6 — Backlog: TODO_post_v1b.md.
    private static let durationOptions: [Int] = [3, 12, 18]

    /// **Slot-Spin Credit-Mapping** (Pool-Vereinheitlichung 2026-04-30,
    /// Stufe 1b). Aus dem ehemaligen `ElumiCreditsStore.GrantTable`
    /// in den Tab gezogen, weil der Store entfernt wurde. Mapping
    /// unverändert: 1× Game → +1 Credit, 2× → +3, 3× → +6. Wird in
    /// `handleSlotLanded` konsumiert.
    private static let slotCreditGrantTable: [Int: Int] = [1: 1, 2: 3, 3: 6]

    /// **Single Source für die Default-Trainingsdauer** (Sache B Stufe 1,
    /// 2026-04-29). Wird sowohl als `@AppStorage`-Initialwert für
    /// `selectedDuration` verwendet als auch — ab Stufe 2 — als Modal-
    /// Preselect beim allerersten Open. Keine Duplikation an anderen
    /// Stellen: alle „falls nichts gewählt"-Pfade lesen diesen Wert.
    static let durationDefault: Int = 12

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
                print("🕒 [DurationMigration] selectedDuration=\(selectedDuration) ∉ \(Self.durationOptions) → reset to \(Self.durationDefault)")
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
            // **2026-05-06** — Header-Hint pro Tab-Visit neu würfeln.
            // `.onAppear` feuert beim ersten Mount und bei jedem
            // Tab-Re-Visit, sodass der Pool sich lebendig anfühlt
            // ohne dass der User eine fixe Reihenfolge merkt.
            currentHint = ElumiHints.random()
            checkSetupModalState()
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
    private func checkSetupModalState() {
        // **2026-05-06 Refactor (Pop-up-Only)** — Pop-up zeigt sich nur
        // wenn der User in dieser Session noch keine Zeit aktiv gewählt
        // hat (`modalDurationSelection == nil`). Vorher öffnete das
        // Modal bei jedem Tab-Open neu mit Zeit-Reset — das war zu
        // aggressiv, sobald die Listen-Card weg ist und die Zeit-
        // Auswahl die einzige Wahl bleibt. Beim Skip-X bleibt
        // `modalDurationSelection` nil → CTA bleibt disabled, Pop-up
        // zeigt sich beim nächsten Tab-Open wieder.
        guard modalDurationSelection == nil else { return }
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
    private func dismissSetupModal() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showSetupModal = false
        }
    }

    // MARK: - Setup-Modal (Sache B Stufe 2)

    /// Modal-Layer mit Dimm-Backdrop + Card. **Backdrop-Tap dismisst**
    /// (Sache B Stufe 2): da das Modal mit einem sinnvollen Default-
    /// Preselect (`Self.durationDefault` = 10) öffnet, kann der User
    /// keinen „undefined state" produzieren. Backdrop-Tap übernimmt den
    /// aktuellen Preselect — `selectedDuration` ist schon via
    /// `@AppStorage` persistiert, der Dismiss-Pfad braucht nichts
    /// zusätzlich zu schreiben (siehe `dismissSetupModal()`-Doc).
    ///
    /// Begründung der Dismissable-Decision: konsistente Modal-Semantik
    /// über Erstöffnung und Re-Edit (Stufe 3) — Forcing-Function bei
    /// einer Low-Stakes-10/15/20-Wahl wäre unnötige Reibung.
    private var setupModalOverlay: some View {
        // **2026-05-06 Refactor (Pop-up-Only)** — vorher zeigte das
        // Modal Listen-Card + Zeit-Cards + „Los geht's"-CTA. Mit dem
        // Refactor:
        //   • Listen-Card raus — globale Auswahl wird transparent aus
        //     `globalSelectedListIDs` gezogen (Default: A1 Grundwortschatz
        //     via Resolver-Fallback `effectiveSelectedListIDs`).
        //   • CTA raus — Tap auf Time-Card schließt direkt (Auto-Close).
        //   • Sparkles + Subline raus — Pop-up wirkt minimaler, klar als
        //     Single-Question „Wie lange?".
        //   • Skip-X oben rechts — User kann Pop-up schließen ohne Wahl;
        //     Slot-CTA bleibt dann disabled (`canTriggerSpin`).
        ZStack(alignment: .top) {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSetupModal()
                }

            // **2026-05-06 Layout-Tweak** — Modal-Karte sitzt jetzt im
            // oberen Drittel (Top-Alignment + Top-Padding), nicht mehr
            // dead-center. User-Spec: „Pop-up etwas höher im Screen".
            // Hintergrund: zentrierter Modal-Block überlappte mit der
            // Slot-Machine, die unmittelbar nach Auto-Close erscheint —
            // visuell wie ein Sprung von Mitte → Mitte. Mit dem Top-
            // Anchor ist der vertikale Fokus klar oben, während das
            // Slot-Layout darunter „atmen" kann.
            VStack(spacing: 18) {
                // Skip-X oben rechts — schließt Pop-up ohne Zeit zu
                // setzen. `modalDurationSelection` bleibt `nil`, Slot-
                // CTA disabled (siehe `canTriggerSpin`).
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        dismissSetupModal()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Schließen"))
                }

                Text("Wie lange möchtest du üben?")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // Time-Cards — Tap löst auto-close aus (siehe
                // `durationChip` Tap-Handler).
                HStack(spacing: 12) {
                    ForEach(Self.durationOptions, id: \.self) { minutes in
                        durationChip(minutes: minutes)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 340)
            // **Layout-Fix** (Sache B Stufe 2): `.fixedSize(vertical:
            // true)` zwingt die Modal-VStack zur intrinsischen
            // Vertikal-Höhe. Sonst proposed der äußere ZStack (mit
            // dem screen-füllenden Backdrop) volle Screen-Höhe an
            // die VStack, die diese auf flexible Kinder (HStack der
            // Chips mit `minHeight: 44` und ohne `maxHeight`)
            // verteilt — Chips würden mehrere hundert Punkte hoch
            // gerendert. `.fixedSize` koppelt die VStack-Höhe an
            // die Summe der intrinsischen Kind-Höhen (~218pt) und
            // hält die Modal-Card kompakt.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#101522"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(sectionStyle.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
            // Top-Offset: ~120pt unter der Status-Bar — Modal-Card sitzt
            // im oberen Drittel statt dead-center. Wert empirisch (sieht
            // auf iPhone 17 / Air / SE gut aus, lässt genug Luft zum
            // Backdrop-Tap unten).
            .padding(.top, 120)
        }
        .sheet(isPresented: $showListPicker) {
            // **Stufe 1c (2026-04-30)** — Multi-Select-Sheet für die
            // globale Listen-Auswahl. Schreibt direkt via
            // `setGlobalSelectedListIDs(...)` (R11: Toggle-State wird
            // ignoriert) und gibt die neue Selection per `onCommit`
            // zurück, damit die Card im Setup-Modal sofort aktualisiert.
            GlobalListPickerSheet(
                allLists: listStore.allLists,
                initialSelection: globalSelectedListIDs,
                onCommit: { newSelection in
                    globalSelectedListIDs = newSelection
                },
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() }
            )
        }
    }

    /// **Listen-Auswahl-Card im Setup-Modal** (Stufe 1c, 2026-04-30 /
    /// Block 4 Restyle 2026-05-03).
    ///
    /// Zeigt die aktuelle globale Listen-Auswahl (gemeinsam genutzt mit
    /// Karteikarten/Quiz/Word Runner/Training). Tap auf die Card öffnet
    /// den `ChainListSelectionSheet` für Multi-Select-Editing.
    ///
    /// **Block 4 (2026-05-03) Restyle**: Card-Stil von der eigenen
    /// kompakten Layout-Variante (cornerRadius 12, Pencil-Pill, kleine
    /// Icon-Plate) auf das Time-Card-Pattern (cornerRadius 14,
    /// minHeight 88, Selected-State mit Modul-Akzent-Tönung) angeglichen
    /// — User-Spec „selbe Höhe, Padding, Border, Background wie
    /// Zeit-Cards". Pulsations-Hint solange noch keine Liste gewählt;
    /// stoppt bei erster Auswahl, übergibt parallel an den Zeit-Cards-
    /// und CTA-Pulse-Pfad.
    ///
    /// **Anzeige-Logik:**
    ///   • Empty → „Listen wählen" als Hinweis-Text (User muss tippen)
    ///   • 1 Liste  → Listen-Name als zentrale Zeile
    ///   • 2 Listen → beide Namen untereinander
    ///   • 3+ Listen → erste 2 Namen + „+N weitere"-Hinweis
    private var listSelectionCard: some View {
        let isEmpty = globalSelectedListIDs.isEmpty
        let isSelected = !isEmpty
        let moduleColor = sectionStyle.accent

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? moduleColor.opacity(0.25)
                        : AppTheme.Colors.secondarySurface
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? moduleColor : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(moduleColor)
                    .frame(width: 32, height: 32)

                if isEmpty {
                    Text("Listen wählen")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    listSummaryView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .opacity(isSelected ? 1.0 : 0.85)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            showListPicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        // **Block 4 (2026-05-03)** — Pulsations-Hint solange keine
        // Liste gewählt. Stoppt bei erster Auswahl. Glow in Modul-
        // Akzent-Farbe analog zu den Zeit-Cards.
        .pulsing(active: isEmpty, glowColor: moduleColor)
    }

    /// Sub-View für die nicht-leere Anzeige in `listSelectionCard`.
    /// Resolved die UUIDs auf Display-Namen via `listStore.allLists`
    /// und zeigt bis zu 2 Namen + Restzähler.
    /// **Block 4 (2026-05-03)** — User-Spec-konformes Format:
    ///   • 1-3 Listen → Namen kommagetrennt + Total-Einträge-Count
    ///   • 4+ Listen  → „X Listen ausgewählt" + Total-Einträge-Count
    /// Total-Count via `VocabularyListSelectionResolver.effectiveItems`
    /// pro Liste, summiert. Lernjahr-Max wird respektiert (gleicher
    /// Resolver wie Quiz/Karteikarten/Train).
    @ViewBuilder
    private var listSummaryView: some View {
        let resolvedLists: [VocabularyList] = globalSelectedListIDs
            .compactMap { id in listStore.allLists.first(where: { $0.id == id }) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let totalEntries = resolvedLists.reduce(0) { acc, list in
            acc + VocabularyListSelectionResolver.effectiveItems(
                for: list,
                lernjahrMax: lernjahrMax
            ).count
        }

        let listLine: String = {
            if resolvedLists.count >= 4 {
                return "\(resolvedLists.count) Listen ausgewählt"
            }
            return resolvedLists.map(\.name).joined(separator: ", ")
        }()

        // **Phase 5 (2026-05-04)** — optionales LJ-Range vor dem Total.
        let summaryText: String = {
            let totalText = "\(totalEntries) Einträge"
            if let range = VocabularyListSelectionResolver.lernjahrRangeLabel(forSelectedLists: resolvedLists) {
                return "\(range) · \(totalText)"
            }
            return totalText
        }()

        VStack(alignment: .leading, spacing: 3) {
            Text(listLine)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)

            Text(summaryText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // **2026-04-24 Layout-Finaler-Pass** (User-Spec):
            //   • VStack-Spacing 8pt (weiter kompakt).
            //   • Credits-Card entfernt — Credits werden im Arcade-
            //     Spiel HUD angezeigt, keine doppelte Fläche hier.
            //   • Reihenfolge: Header → Zeit → Slot → Ergebnis → CTA.
            //     Der CTA steht jetzt IMMER als letztes inhaltliches
            //     Element direkt über dem Footer (User-Spec „CTA
            //     gehört unters Ergebnis").
            VStack(alignment: .leading, spacing: 8) {
                ModuleHeaderCard(
                    systemImage: "sparkles",
                    title: currentHint,
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )

                // 1) Trainingszeit-Anzeige (Sache B Stufe 3): XXL-Zahl
                //    + Pencil-Pill für Re-Edit. Statt der alten
                //    `durationCard` mit drei Chips. Die Chips leben
                //    jetzt im Setup-Modal (`setupModalOverlay`).
                timeDisplayCard

                // 2) Slot Machine.
                slotMachineArea

                // 3) Ergebnisbereich — Placeholder vor Spin,
                //    gezogene Module nach Reveal.
                trainingResultCard

                // 4) CTA als LETZTES inhaltliches Element. Zeigt
                //    „Los geht's! (Versuch X/3)" oder transformiert
                //    nach dem 3. Spin zu „Training starten". Kein
                //    Overlay, kein safeAreaInset — im normalen
                //    VStack-Flow.
                spinCTA

                Spacer(minLength: 0)
            }
            .animation(.easeInOut(duration: 0.28), value: slotPhase)
            .animation(.easeInOut(duration: 0.22), value: lastSpinResult)
            .animation(.easeInOut(duration: 0.25), value: currentSpinNumber)
            .onChange(of: slotPhase) { _, newPhase in
                // **Result-Highlight-Trigger** (2026-04-25): sobald
                // die Slot-Machine in `.revealed` wechselt, bekommt
                // die Ergebnis-Card einen initialen Glow-Burst +
                // anschließend sanftes Pulsieren. Bei einem neuen
                // Spin (`.spinning` / `.stopping`) reset.
                switch newPhase {
                case .revealed:
                    triggerResultHighlight()
                    // **Block 5 (2026-05-03)** — Jackpot-Feier-Trigger.
                    // Wenn alle drei Reels Game-Symbole zeigen, fahren
                    // wir das Overlay direkt hier hoch (statt den User
                    // den „Jetzt üben"-CTA tappen zu lassen, der dann
                    // den Pre-Screen mit „Jackpot — kein Training!"
                    // gerendert hätte).
                    triggerJackpotIfApplicable()
                case .spinning, .stopping:
                    resultHighlightScale = 1.0
                    resultHighlightGlow = 0.0
                case .idle, .landed:
                    break
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
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
                onSettings: openSettings
            )
        }
    }

    // MARK: - Header-Hint

    // **2026-05-06 Refactor** — `headerTitle` (statisch „Salut Frank!")
    // entfernt. Stattdessen rotiert ein Hint-Pool aus `ElumiHints`
    // pro Tab-Visit (`@State` + `.onAppear`-Reroll im mainContent).
    // User-Spec: „Salut Frank!" macht im Maschine-Tab keinen Sinn —
    // es ist keine Begrüßung, der User ist schon mehrere Tabs tief.
    // Hint-Pool wirkt lebendig und stimmt auf den Spin-Moment ein.

    // MARK: - Slot-Machine-Bereich

    private var slotMachineArea: some View {
        // **V4.4 Sound-Pass (2026-04-24)**: differenzierte SFX für
        // jeden Slot-Event-Typ — keine einheitlichen `playTabSwitch`
        // mehr für alle drei Callbacks.
        //   • onSpinStart → `playLaunch()` (kraftvoller Start-Sound).
        //   • onReelSettled → `playTabSwitch()` (klares Tick pro Reel).
        //   • onLanded → wird in `handleSlotLanded` separat behandelt
        //     (Achievement bei Elumi-Treffer, neutraler Success-Ton
        //     ohne Treffer).
        // Dazu unterschiedlich starke Haptik-Impulse, damit der
        // User auch mit Ton aus Feedback spürt.
        SlotMachineView(
            reelPools: ReelSymbol.standardReelPools,
            accent: sectionStyle.accent,
            spinTargets: $spinTargets,
            spinStartToken: $slotStartToken,
            phase: $slotPhase,
            onLanded: handleSlotLanded,
            onReelSettled: { reelIndex in
                // **2026-04-25 Sound-Pass V2** (User-Report „Klicks nicht
                // hörbar"): dedizierte `playSlotReelClick` / `playSlotFinalReelClick`
                // Methoden mit markanteren Assets (`toggle` + `listaction`)
                // statt der generischen `playTabSwitch`. Jeder Stop hat so
                // ein deutlich wahrnehmbares Klack.
                let isFinalReel = (reelIndex == 2)
                UIImpactFeedbackGenerator(
                    style: isFinalReel ? .heavy : .medium
                ).impactOccurred()
                if isFinalReel {
                    feedbackPlayer.playSlotFinalReelClick()
                } else {
                    feedbackPlayer.playSlotReelClick()
                }
                #if DEBUG
                print("🔊 [Slot] Reel \(reelIndex) Click (final=\(isFinalReel))")
                #endif
            },
            onSpinStart: {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                // **Audio-Session-Priming** (2026-04-25): sorgt dafür,
                // dass die Click-Sounds nicht durch eine schlafende oder
                // konkurrierende Audio-Session gedämpft werden. Der
                // Session-Warm-Up bleibt für die ganze Spin-Sequenz
                // aktiv — nachfolgende Reel-Stops klingen dann sofort
                // ohne Anlauf-Delay.
                feedbackPlayer.sp.ensureAudioSession()
                // **Start-Sound entfernt** (Branch
                // `feature/slot-machine-sounds`, 2026-04-30) — der frühere
                // `playLaunch()` (kraftvoller Start-Sound) war ein
                // hörbarer Cue *vor* dem neuen Click-Stream und wirkte
                // gegenüber dem realistischen Reel-Click redundant /
                // konkurrierend. User-Spec: „start sound muss weg
                // (der vor dem neuen click sound kommt)". Haptik und
                // Session-Priming bleiben — beides ist nicht hörbar.
                #if DEBUG
                print("🔊 [Slot] Spin gestartet (session primed, kein Launch-Sound mehr)")
                #endif
            }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trainingszeit-Anzeige (Sache B Stufe 3) — IMMER sichtbar

    /// XXL-Anzeige der gewählten Trainingsdauer + Pencil-Pill für
    /// Re-Edit. Ersetzt die ehemalige `durationCard` mit drei Chips
    /// (User-Spec Sache B 2026-04-29): nach dem Setup-Modal-Refactor
    /// (Stufe 2) ist die Chip-Wahl ins Modal gewandert; hier zeigt die
    /// Card jetzt nur noch die persistierte Wahl groß.
    ///
    /// Komponenten:
    ///   • Section-Label „TRAININGSZEIT" via `setupCardLabel(...)`-Helper
    ///   • XXL-Zahl in 56pt black rounded, accent-Color, mit
    ///     `.contentTransition(.numericText())` für smoothes Update
    ///     beim Re-Edit
    ///   • „min"-Suffix in 16pt semibold, dezent in `textSecondary`
    ///   • Pencil-Pill (40×40 Circle, accent.opacity(0.14)) rechts
    ///     bündig — Pattern analog zu `SessionContextCard`
    ///   • Pencil ist `disabled(!isSpinAllowed)` — kein Re-Edit
    ///     während die Slot-Machine rollt (Edge-Case E2)
    private var timeDisplayCard: some View {
        // **Setup-Modal-Tweaks 3/3 (2026-04-30) + v2 — C3**: Card
        // kompakter gemacht (Vertical-Padding 10 → 6, VStack-Spacing
        // 8 → 4, XXL-Zahl 56 → 46pt) und Inhalt **horizontal
        // zentriert**. Das Section-Label „TRAININGSZEIT" bleibt
        // linksbündig oben (Section-Header-Konvention), aber die
        // Wert-Zeile (Zahl + „min") ist via Spacer-Spacer-Pattern
        // ehrlich mittig — links 40pt-Reserve-Slot (gleicher Width
        // wie der Pencil-Pill rechts), Wert in der Mitte mit
        // Spacern auf beiden Seiten, Pencil rechts unverändert.
        VStack(spacing: 4) {
            // **Setup-Tweaks v2 — C3 (User-Spec 2026-04-30)**: Label
            // ist hier zentriert (nicht der Standard-`setupCardLabel(...)`-
            // Helper, der `.alignment: .leading` hartkodiert). Inline-
            // Definition mit identischen Styles aus dem Helper, nur
            // mit `.center`-Frame-Alignment + `multilineTextAlignment`.
            // Ergebnis: Section-Header und Wert-Zeile sind beide
            // ehrlich zentriert.
            Text("TRAININGSZEIT")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.Colors.cardLabel)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Reserve-Slot links — gleich breit wie der Pencil
                // rechts, damit die Wert-VStack in der echten
                // Mitte sitzt (nicht links-versetzt durch den
                // Pencil-Asymmetrie-Effekt).
                // **UX-Polish 2026-05-02 Iter 2**: Pencil 40 → 32pt
                // (siehe unten), Reserve mitgezogen.
                Color.clear.frame(width: 32, height: 32)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(selectedDuration)")
                        // **UX-Polish 2026-05-02 Iter 2 (User „zeitcard
                        // oben etwas flacher machen, Slot-CTAs sind
                        // teilweise vom Footer verdeckt")**: Number
                        // 46 → 28 pt. Spart ~18 pt Card-Höhe und schiebt
                        // den gesamten Slot-Screen-Content nach oben,
                        // damit die Twin-CTAs („Nochmal drehen" /
                        // „Jetzt üben") wieder klar über der Footer-
                        // Linie sitzen.
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(sectionStyle.accent)
                        // **Spec-1 (2026-04-30)** — `.identity` statt
                        // `.numericText()`. Begründung: mit den neuen
                        // Optionen 6/12/18 wechselt die Anzeige zwischen
                        // 1- und 2-stelligen Werten (6 ↔ 12). Die
                        // numericText-Animation ist dafür nicht ausgelegt
                        // (sie morpht digit-für-digit gleicher Stelle) und
                        // erzeugt einen unsauberen Sprung. `.identity` ist
                        // ein harter Crossfade ohne Glyph-Morphing.
                        .contentTransition(.identity)

                    Text("min")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    openSetupModalForReEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                        // **UX-Polish 2026-05-02 Iter 2** — Pencil-
                        // Frame 40×40 → 32×32, damit die HStack-Höhe
                        // mit dem kleineren Number-Glyph mitschrumpft.
                        // Tap-Target bleibt mit 32 pt Apple-HIG-konform.
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(sectionStyle.accent.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isSpinAllowed)
                .opacity(isSpinAllowed ? 1.0 : 0.45)
                .accessibilityLabel(Text("Trainingsdauer ändern"))
                .accessibilityHint(Text("Öffnet den Setup-Dialog mit der aktuellen Wahl preselected"))
            }
        }
        .padding(.horizontal, 14)
        // **2026-04-30 Fine-Tuning**: vertikales Padding 6 → 2pt
        // (User-Spec „10 % weniger Höhe"). Spart 8pt Card-Höhe (~9,6 %),
        // alle anderen Werte (Zahl-Größe, Pencil-Frame, VStack-Spacing,
        // Section-Label) unverändert.
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
        .animation(.easeInOut(duration: 0.20), value: selectedDuration)
        .animation(.easeInOut(duration: 0.20), value: isSpinAllowed)
    }

    /// Re-Edit-Pfad — Pencil-Tap im Setup-Screen öffnet das Setup-Modal
    /// mit der persistierten Wahl preselected. Animation-Strategie ist
    /// Single-Source: `withAnimation` um den State-Toggle gewrappt,
    /// die View-Transition läuft über `.animation(value: showSetupModal)`
    /// am ZStack-Wrapper + `.transition(...)` am Mount-Site (Stufe 2).
    /// Erstmaliges Modal-Erscheinen und Re-Edit nutzen denselben Pfad —
    /// keine duplizierte Animation, keine getrennten States.
    private func openSetupModalForReEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // **2026-05-06 Refactor (Pop-up-Only)** — Re-Edit zeigt die
        // aktuelle Wahl als preselected an. Vorher wurde
        // `modalDurationSelection` nilliert, um dem User eine bewusste
        // Re-Wahl abzunötigen — mit dem neuen `canTriggerSpin`-Gate
        // (`modalDurationSelection != nil`) würde das aber den Slot-CTA
        // disablen, sobald der User das Pop-up via Skip-X / Backdrop
        // schließt ohne neue Card zu tappen. Stattdessen: Re-Edit
        // preselected die persistierte `selectedDuration`. Dismiss
        // ohne Änderung → CTA bleibt aktiv (kein Regression). Tap auf
        // andere Card → Auto-Close mit neuem Wert.
        modalDurationSelection = selectedDuration
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showSetupModal = true
        }
    }

    /// Pro-Chip-Renderer für das Setup-Modal (Sache B Stufe 2). Vor
    /// Stufe 3 wurde dieser Helper auch von der ehemaligen
    /// `durationCard` im Setup-Screen genutzt; mit dem Wechsel zur
    /// `timeDisplayCard` (XXL + Pencil) ist das Modal jetzt der einzige
    /// Call-Site.
    private func durationChip(minutes: Int) -> some View {
        // **2026-04-24 Tap-Reliability-Fix** (User-Report: „1–2 Taps
        // gehen, dann nicht mehr"). Frühere Varianten mit `Button {}
        // label:` in einer ScrollView haben nach State-Changes
        // intermittent Taps verloren. Der robusteste Pattern für
        // ScrollView-Inhalte ist ein pures `ZStack + onTapGesture`
        // mit:
        //
        //   1. ZStack mit Background + Stroke + Label — alles EINE
        //      zusammenhängende View (kein Button-Wrapper, der seine
        //      eigene Hit-Area ableitet).
        //   2. `.frame(maxWidth: .infinity, minHeight: 44)` — Apple-
        //      HIG-kompatible Tap-Area, expliziter Full-Width-Stretch,
        //      damit der ganze 1/3-Slot tappbar ist.
        //   3. `.contentShape(Rectangle())` NACH dem Background — setzt
        //      die Hit-Area auf das volle Rechteck.
        //   4. `.onTapGesture { ... }` — schneller, reliabler Tap-
        //      Handler ohne Button-Wrapper-Overhead.
        //   5. Farb-Transition kommt über `.animation(_, value:)` auf
        //      der Chip-Ebene — nur auf Color-Änderung.
        //
        // **Sache B Stufe 1 (2026-04-29)**: Pulse-Animation entfernt.
        // Vorher pulsierten alle drei Chips so lange `selectedDuration
        // == nil`, um zur Wahl einzuladen. Mit der `@AppStorage`-Migration
        // ist `selectedDuration` immer gesetzt (Default = `durationDefault`),
        // ergo kein nil-State mehr → der Pulse wäre tot. Die TimelineView
        // + wave/stagger/glow-Mechanik ist daher entfallen; der Chip ist
        // jetzt rein state-driven.
        // **UX-Polish 2026-05-02** — Modal-Selektion ist jetzt
        // optional (`modalDurationSelection`); bei Modal-Open kein
        // Preselect. Selected-State liest den Modal-State, nicht
        // `selectedDuration`. Tap setzt beide Werte (View-State +
        // persistent storage).
        let moduleColor = sectionStyle.accent
        let isSelected = modalDurationSelection == minutes
        let shouldPulse = modalDurationSelection == nil
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? moduleColor.opacity(0.25)
                        : AppTheme.Colors.secondarySurface
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? moduleColor : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )
            // **UX-Polish 2026-05-02** — Number-Font 16 → 32 pt,
            // Card-Höhe 44 → 88. Cards prominent als „bewusste Wahl"-
            // Element, statt als Kleingedrucktes neben anderen Modal-
            // Elementen.
            VStack(alignment: .center, spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("min")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .opacity(isSelected ? 1.0 : 0.85)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            #if DEBUG
            print("🕒 [DurationChip] tap on \(minutes) (prev=\(String(describing: modalDurationSelection)))")
            #endif
            modalDurationSelection = minutes
            selectedDuration = minutes
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #if DEBUG
            print("🕒 [DurationChip] modalDurationSelection → \(minutes) ✓")
            #endif
            // **2026-05-06 Refactor (Pop-up-Only)** — Auto-Close direkt
            // nach Time-Tap. User-Spec: „User tippt Zeit-Card → Pop-up
            // schließt automatisch → Slot-Screen erscheint mit
            // blinkendem CTA". Kein zusätzlicher „Los geht's"-CTA mehr
            // im Pop-up, der Tap auf die Zeit-Card IST die Bestätigung.
            dismissSetupModal()
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        // **UX-Polish 2026-05-02** — Pulsations-Hint solange noch
        // keine Card gewählt. Bei erstem Tap stoppt die Pulse-
        // Schleife (`shouldPulse = false`); Pulse springt auf den
        // CTA „Los geht's" über.
        .pulsing(active: shouldPulse, glowColor: moduleColor)
    }

    // MARK: - Unified CTA „Los geht's" / „Nochmal drehen + Jetzt üben" / „Jetzt üben"

    /// **UX Stufe 3 (2026-04-29)** — drei States, klar getrennt:
    ///
    ///   1. `currentSpinNumber == 0` → ein Full-Width-Button „Los geht's!"
    ///      (erster Versuch, kein Versuchszähler).
    ///   2. `currentSpinNumber > 0 && hasRemainingSpins` → zwei
    ///      gleichwertige Buttons nebeneinander („Nochmal drehen" links,
    ///      „Jetzt üben" rechts), beide gelb gefüllt
    ///      (`AppPrimaryButtonStyle(color: ctaYellow)`). Versuchszähler
    ///      „Versuch X von 3" als separate Caption darüber — nicht im
    ///      Button-Sublabel, weil zwei Buttons mit unterschiedlichen
    ///      Sublabel-Strukturen das equal-weight-Prinzip optisch brechen
    ///      würden.
    ///   3. `!hasRemainingSpins` → ein Full-Width-Button „Jetzt üben"
    ///      (Single-CTA, ehrliche Kommunikation: Spin-Phase vorbei,
    ///      jetzt wird trainiert). Label bleibt „Jetzt üben" identisch
    ///      zum 2-Button-State — Konsistenz für den User.
    @ViewBuilder
    private var spinCTA: some View {
        // **Setup-Tweaks v2 — C4 (2026-04-30)**: die separate
        // „Versuch X von 3"-Caption-Zeile oberhalb der Twin-CTAs ist
        // entfernt. Der Counter lebt jetzt als Sub-Label im
        // „Nochmal drehen"-Button (siehe `twinCTAs`). Damit verschwindet
        // der vertikale Layout-Sprung beim Phase-Übergang
        // (revealed → spinning) — der Button-Block hat jetzt eine
        // konstante Höhe über alle Slot-Phasen.
        if currentSpinNumber == 0 {
            singleSpinButton
        } else if hasRemainingSpins {
            twinCTAs
        } else {
            singleTrainingButton
        }
    }

    /// State 1: erster Versuch — ein Full-Width-Button „Maschine starten".
    private var singleSpinButton: some View {
        // **UX-Polish 2026-05-02 (Stufe 7)** — pulsiert wenn der
        // Slot ruht und noch nichts gedreht wurde (`slotPhase == .idle &&
        // currentSpinNumber == 0`). User-Spec: nur dieser CTA + die
        // Pre-Screen-„Bereit?"-Headline pulsieren auf dem Slot/Pre-
        // Screen-Pfad — der „Nochmal drehen"/„Jetzt üben"-Twin-State
        // bleibt ruhig.
        let shouldPulse = slotPhase == .idle && currentSpinNumber == 0 && canTriggerSpin
        return Button {
            triggerSpin()
        } label: {
            Text(spinPrimaryLabel)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: ctaYellow))
        .disabled(!canTriggerSpin)
        .opacity(canTriggerSpin ? 1.0 : 0.45)
        .pulsing(active: shouldPulse, glowColor: ctaYellow)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityLabel(Text("Los geht's"))
        .accessibilityHint(Text("Startet den ersten Slot-Spin"))
    }

    /// State 2: 2-Button-State nach erstem Spin, solange Versuche übrig.
    /// Beide Buttons gelb gefüllt, gleiche Höhe, gleiche Schriftgröße,
    /// `frame(maxWidth: .infinity)` → 50/50-Aufteilung.
    ///
    /// **Setup-Tweaks v2 — C4 (2026-04-30)**: Versuch-Counter
    /// (`currentAttemptDisplay`) ist jetzt **Sub-Label im Re-Spin-
    /// Button**, nicht mehr eine separate Caption-Zeile oberhalb. Der
    /// „Jetzt üben"-Button bekommt eine unsichtbare Reserve-Slot-Zeile
    /// (`Text(" ")` mit identischer Schrift), damit beide Buttons
    /// dieselbe Höhe halten und es keine vertikalen Layout-Sprünge
    /// beim Phase-Wechsel mehr gibt.
    private var twinCTAs: some View {
        HStack(spacing: 12) {
            Button {
                triggerSpin()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                        Text(spinPrimaryLabel)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(currentAttemptDisplay)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
            }
            // **CTA-Differenzierung (2026-05-02)** — „Nochmal drehen"
            // wird optisch vom „Jetzt üben"-CTA abgesetzt: Warning-Amber
            // signalisiert „Retry-Aktion mit Verlust einer Spin-Chance",
            // im Gegensatz zum Success-Grün der Confirmation-CTA daneben.
            // Pre-Spin-CTA „Los geht's" (`singleSpinButton`) bleibt
            // bewusst auf `ctaYellow` — dort gibt es noch keinen
            // Differenzierungs-Bedarf.
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.warning))
            .disabled(!canTriggerSpin)
            .opacity(canTriggerSpin ? 1.0 : 0.45)
            .accessibilityLabel(Text(spinPrimaryLabel))
            .accessibilityHint(Text("\(currentAttemptDisplay). Erzeugt eine andere zufällige Trainings-Zusammenstellung."))

            Button {
                startTraining()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Jetzt üben")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // Sub-Label: gewählte Trainings-Dauer in Klammern.
                    // Identische Schrift wie der Versuch-Counter im
                    // Re-Spin-Button (User-Spec 2026-04-30) — damit
                    // beide Buttons visuell symmetrisch zweizeilig
                    // wirken und gleich hoch bleiben.
                    Text("(\(selectedDuration) min)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
            }
            // **CTA-Differenzierung (2026-05-02)** — „Jetzt üben"
            // ist der Confirmation-CTA → Success-Grün, klar abgesetzt
            // vom Warning-Amber des „Nochmal drehen"-Retry-CTA daneben.
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.success))
            .accessibilityLabel(Text("Jetzt \u{00FC}ben \(selectedDuration) Minuten"))
            .accessibilityHint(Text("Startet die generierte Trainingseinheit sofort"))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    /// State 3: alle Versuche aufgebraucht — ein Full-Width-Button
    /// „Jetzt üben". Label-Konsistenz zur 2-Button-Phase.
    private var singleTrainingButton: some View {
        Button {
            startTraining()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Jetzt üben")
                    .font(.system(size: 19, weight: .black, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        // **CTA-Differenzierung (2026-05-02)** — Single-CTA-Final-State
        // (3/3, keine Retries mehr) hält Label-Konsistenz zur 2-Button-
        // Phase und erbt deshalb auch die Success-Grün-Farbe vom
        // „Jetzt üben"-Twin.
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.success))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityLabel(Text("Jetzt üben"))
        .accessibilityHint(Text("Startet die generierte Trainingseinheit"))
    }

    /// **Spin-Gate** — Sache B Stufe 1 (2026-04-29): vereinfacht auf
    /// (a) Phase-Erlaubnis und (b) verbleibende Versuche. Die ehemalige
    /// `selectedDuration != nil`-Bedingung ist entfallen, weil
    /// `selectedDuration` jetzt non-optional persistiert ist und stets
    /// einen sinnvollen Default (`Self.durationDefault` = 10) hält.
    ///
    /// **2026-05-06 Refactor (Pop-up-Only)** — zusätzliche Bedingung
    /// `modalDurationSelection != nil`. Im neuen Flow ist die Zeit-Wahl
    /// pro Session ein bewusster Akt: der User muss im Pop-up eine
    /// Time-Card tappen, bevor der Slot-CTA aktiv wird. Vorher konnte
    /// der User dank `selectedDuration`-Default sofort spinnen, jetzt
    /// gate-t der Slot-CTA bis die Pop-up-Wahl getroffen wurde
    /// (User-Spec: „Falls keine Zeit gewählt: Slot-Screen-CTA bleibt
    /// gegraut/disabled bis Zeit gesetzt ist").
    private var canTriggerSpin: Bool {
        isSpinAllowed && hasRemainingSpins && modalDurationSelection != nil
    }

    /// Spin ist nur in `.idle` und `.revealed` erlaubt — während
    /// `.spinning` / `.stopping` / `.landed` muss der Button deaktiviert
    /// sein, damit kein zweiter Spin in einen laufenden Spin reinhackt.
    private var isSpinAllowed: Bool {
        slotPhase == .idle || slotPhase == .revealed
    }

    // MARK: - „Dein Ergebnis"-Card — IMMER sichtbar

    /// Flache Card unter der Slot Machine. Zeigt vor dem Spin einen
    /// ruhigen Placeholder (drei Geist-Slots + Hinweis), nach dem Spin
    /// die drei tatsächlich gezogenen Symbole.
    /// Per User-Spec 2026-04-24: kompakt, weniger vertikales Padding,
    /// damit die Card nicht wie ein großer Content-Block wirkt.
    private var trainingResultCard: some View {
        // **2026-04-25 Dauerhaft-Pulse-Fix** (User-Spec „muss dauerhaft
        // blinken, nicht stoppen, bis Nochmal oder Training starten
        // gedrückt wird").
        //
        // Vorher: `.repeatForever(autoreverses: true)` auf @State-
        // basierten Glow/Scale — SwiftUI konnte die Animation unter
        // bestimmten Re-Render-Pfaden abbrechen.
        // Jetzt: `TimelineView(.animation)` treibt Glow + Scale direkt
        // aus einer Sinuswelle basierend auf der System-Uhr. Diese
        // Schleife läuft GARANTIERT so lange die View sichtbar ist —
        // kein SwiftUI-Animation-State kann sie abbrechen.
        //
        // Gated by `slotPhase == .revealed`: nur während der Reveal-
        // Phase sind Glow und Scale aktiv. In allen anderen Phasen
        // (`.spinning`, `.stopping`, `.idle`, `.landed`) wird der
        // Multiplikator 0 → kein Glow, Scale 1.0.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let isRevealed = slotPhase == .revealed
            let t = context.date.timeIntervalSinceReferenceDate
            // **2026-04-25 V3 (User „stärker + schneller blinken")**:
            // Cycle 1.4s → 0.75s (fast 2× schneller). Glow-Amplitude
            // 0.55…1.0 → 0.2…1.0 (deutlich breiterer Swing). Scale
            // 0.018 → 0.025 (intensiver Pop). Shadow-Radius 16 → 22
            // (mehr sichtbare „Strahlung"). Fühlt sich klar als
            // Blinken/Pulsieren an, nicht mehr wie ruhiges Atmen.
            let cycle: Double = 0.75
            let phase = t.truncatingRemainder(dividingBy: cycle) / cycle
            let wave = (sin(phase * 2 * .pi) + 1) / 2  // 0…1
            let pulseGlow: Double = isRevealed ? (0.2 + 0.8 * wave) : 0.0
            let pulseScale: CGFloat = isRevealed
                ? CGFloat(1.0 + 0.025 * wave)
                : 1.0

            return trainingResultCardContent
                .scaleEffect(pulseScale * resultHighlightScale)
                .shadow(
                    color: resultGlowColor.opacity(pulseGlow),
                    radius: 22,
                    x: 0,
                    y: 0
                )
        }
    }

    /// Reiner Card-Inhalt ohne Pulse-Effekte. Wird von der TimelineView
    /// in `trainingResultCard` umschlossen; so bleibt der Content stabil
    /// und nur die Pulse-Werte re-rendern pro Frame.
    private var trainingResultCardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dein Ergebnis")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            if let result = lastSpinResult, slotPhase == .revealed {
                filledModulesRow(for: result)
            } else {
                placeholderModulesRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .appSetupCardBackground()
    }

    private func filledModulesRow(for result: SlotSpinResult) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(result.centerSymbols.enumerated()), id: \.offset) { _, symbol in
                moduleResultCard(for: symbol)
            }
        }
    }

    private var placeholderModulesRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                placeholderModuleSlot
            }
        }
    }

    private var placeholderModuleSlot: some View {
        // **Setup-Tweaks v2 — C5 (User-Spec 2026-04-30)**: kleine
        // Circle-Sparkle + „—"-Label ersetzt durch **großes zentriertes
        // Fragezeichen** in der Card-Akzent-Farbe. Card-Dimensions
        // unverändert — das Q wirkt dominant „hier kommt was rein".
        //
        // Vorgeschichte (2026-04-25 Visibility-Pass): die kleinen
        // Sparkle-Circles hatten den Slot zu zaghaft markiert. Das
        // dominante Q ist die nächste Iteration und kommuniziert
        // klarer „Slot ist noch leer, Spin füllt ihn".
        //
        // **UX-Polish 2026-05-02 (Stufe 7)** — Layout-Shift-Fix.
        // Vorher: Placeholder ~44 pt vs Filled (`moduleResultCard`)
        // ~92 pt → Card wechselt Höhe beim Spin-Reveal, CTA-Position
        // wandert vertikal. Jetzt: fixe `frame(height: Self.resultSlotHeight)`
        // an beiden Pfaden — CTA-Position konstant über alle Slot-
        // Phasen.
        VStack(spacing: 0) {
            Image(systemName: "questionmark")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(sectionStyle.accent.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.resultSlotHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    AppTheme.Colors.border.opacity(0.75),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
        )
    }

    /// **UX-Polish 2026-05-02** — fixe Höhe für Result-Slots
    /// (Placeholder + Filled). Wert ist gewählt nach gemessener
    /// Filled-Card-Höhe: 52 pt Icon + 5 pt Spacing + 12 pt Label +
    /// 12 pt Vertical-Padding (6 pt × 2) = ~92 pt. Etwas Reserve
    /// für Font-Metrics auf großen Dynamic-Type-Settings.
    private static let resultSlotHeight: CGFloat = 92

    /// Result-Modul-Card — zeigt das gezogene Modul mit demselben
    /// Home-Icon wie im Home-Screen.
    ///
    /// **V4.8 Icon-Migration (2026-04-25)**: direkt `HomeModuleIconView`
    /// für Trainingsmodule, `ElumiWasserfloh`-Asset für Elumi. Kein
    /// SF-Symbol-Pfad mehr — identische Icon-Quelle wie in der
    /// Slot-Machine + Home-Cards.
    private func moduleResultCard(for symbol: ReelSymbol) -> some View {
        // **2026-04-25 (User „keine Pills, Icons größer")**: Der
        // Circle-Pill um das Icon ist entfernt. Das Icon steht jetzt
        // direkt im Card-Rahmen — klarer Fokus, weniger Layer-Rauschen.
        //
        // **Setup-Tweaks v2 — C6 (User-Spec 2026-04-30)**: Icon-Größen
        // nochmal hoch — Card-Dimensions sind unverändert geblieben,
        // Platz war da. Iteration:
        //   • HomeModuleIconView 32 → 40 (+25%, 2026-04-25)
        //   • HomeModuleIconView 40 → 52 (+30%, 2026-04-30)
        //   • Elumi-Asset 30 → 38 (+27%, 2026-04-25)
        //   • Elumi-Asset 38 → 50 (+32%, 2026-04-30)
        VStack(spacing: 5) {
            if let module = symbol.homeModule {
                HomeModuleIconView(icon: module.icon, size: 52)
            } else if let assetName = symbol.assetImage {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
            }
            Text(symbol.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        // **UX-Polish 2026-05-02** — fixe Höhe wie placeholder, damit
        // `trainingResultCard` zwischen Pre-Spin/Post-Spin nicht
        // mehr wächst. Siehe Doc bei `resultSlotHeight`.
        .frame(height: Self.resultSlotHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
    }

    // **2026-04-24 Versuchslogik**: Der separate `startTrainingCTA`
    // ist entfallen. Die Training-Starten-Funktion wohnt jetzt im
    // `trainingModeButton` (Teil von `spinCTA`), der nach dem 3. Spin
    // automatisch erscheint.

    // MARK: - Aktionen

    /// Wird vom Spin-CTA aufgerufen — startet einen frischen Spin
    /// und versteckt das alte Ergebnis (Reset-Verhalten per Spec).
    /// **2026-04-24 Gate**: läuft nur wenn die Phase es erlaubt und
    /// noch Versuche übrig sind (siehe `canTriggerSpin`).
    private func triggerSpin() {
        guard canTriggerSpin else { return }
        // **Sache B Stufe 2 Future-Insurance** (2026-04-29): zusätzlicher
        // Guard gegen den Fall, dass ein zukünftiger Auto-Spin / Push-
        // Trigger / Background-Notification den Spin programmatisch
        // anstoßen will, während das Setup-Modal offen ist. Aktuell
        // unmöglich, weil der Modal-Backdrop alle UI-Tap-Pfade blockiert
        // und es keinen externen Trigger-Pfad gibt — billige Versicherung
        // gegen Race-Conditions in V2/V3, falls jemand einen
        // programmatischen Spin-Pfad einführt.
        guard !showSetupModal else { return }
        feedbackPlayer.playTabSwitch()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Altes Ergebnis verwerfen, damit der Bereich beim erneuten
        // Drehen sauber verschwindet (User-Spec: „Reset-Verhalten").
        lastSpinResult = null_lastSpin()
        // Pre-computed Targets via DropRate-Pipeline (gewichtete
        // Elumi-Wahrscheinlichkeit pro Reel).
        spinTargets = computeSpinTargets()
        // Trigger an die SlotMachineView. Sie setzt das Token nach
        // dem vollständigen Spin-Sequenz-Durchlauf selbst auf false.
        slotStartToken = true
    }

    /// Helfer, der `lastSpinResult` defensiv auf nil setzt — als
    /// Funktion ausgelagert, damit Type-Checker happy bleibt mit dem
    /// `Optional<SlotSpinResult>` literal.
    private func null_lastSpin() -> SlotSpinResult? { nil }

    /// Pro-Reel Ziel-Symbol berechnen mit aktueller Elumi-Chance.
    ///
    /// **Regel (2026-04-25 User-Spec)**: Es dürfen NIE zweimal
    /// dasselbe Trainingsmodul im selben Spin vorkommen. Elumi
    /// (Bonus-Symbol) darf mehrfach erscheinen (2× oder 3× Elumi
    /// sind ausdrücklich erlaubt — das ist der „Jackpot"-Effekt).
    ///
    /// Algorithmus:
    ///   1. Pro Reel Elumi-Roll (unabhängig wie vorher).
    ///   2. Für Nicht-Elumi-Reels aus dem jeweiligen Pool wählen,
    ///      aber nur aus den Modulen, die in diesem Spin **noch
    ///      nicht** verwendet wurden.
    ///   3. Wenn alle Pool-Module schon belegt sind (Edge-Case bei
    ///      stark überlappenden Pools), fallen wir auf den vollen
    ///      Pool zurück — dann kann es theoretisch Doubletten geben.
    ///      Mit den aktuellen Pools (Reel 1/2/3 haben je 4 Module
    ///      aus einem Satz von 8 und überlappen nur partiell) tritt
    ///      das in der Praxis nie auf.
    private func computeSpinTargets() -> [ReelSymbol?] {
        let chance = dropRate.currentElumiChance()
        let pools = ReelSymbol.standardReelPools
        var targets: [ReelSymbol?] = [nil, nil, nil]
        var usedModules: Set<HomeHeroModule> = []

        for reelIndex in 0..<3 {
            if dropRate.drawIsElumi(chance: chance) {
                // Elumi — darf mehrfach. Kein Set-Eintrag.
                targets[reelIndex] = ReelSymbol.elumi
                continue
            }
            let pool = pools[reelIndex]
            // Kandidaten = Pool-Einträge, deren Modul noch nicht
            // belegt ist.
            let candidates = pool.filter { symbol in
                guard let module = symbol.homeModule else { return false }
                return !usedModules.contains(module)
            }
            let chosen = candidates.randomElement() ?? pool.randomElement()
            if let module = chosen?.homeModule {
                usedModules.insert(module)
            }
            targets[reelIndex] = chosen
        }
        return targets
    }

    /// Wird von `SlotMachineView` aufgerufen, sobald die komplette
    /// Spin-Sequenz (inkl. Reveal) durch ist.
    ///
    /// **2026-04-30 Credit-Grant-Verlagerung (Stufe 1b, Patch)**: die
    /// Credit-Vergabe wandert vom Slot-Stop **zum „Jetzt üben"-Tap** —
    /// siehe `startTraining()`. Begründung: bisher gutgeschriebene
    /// Tickets pro Drehung erlaubten Re-Roll-Farming (User dreht 3×,
    /// kassiert Tickets aus allen drei Drehungen, drückt nicht „Jetzt
    /// üben"). Neue Regel: nur die EINE Drehung, mit der der User in
    /// die Übung geht, zählt. Dieser Callback inkrementiert daher nur
    /// noch Spin-Budget-Bonus (intern für mehr Spins) und Drop-Rate-
    /// Statistik — keine `arcadeCredits`-Änderung.
    ///
    /// **Versuchslogik**: Hier — und NUR hier — wird
    /// `currentSpinNumber` inkrementiert. Bei bloßem Button-Tap oder
    /// während einer abgebrochenen Animation wird dieser Pfad NICHT
    /// erreicht, Versuche gehen nicht verloren.
    private func handleSlotLanded(_ result: SlotSpinResult) {
        lastSpinResult = result
        // **Stufe 2 (2026-04-30)** — neuer Spin = neuer Grant erlaubt.
        // Erst beim „Jetzt üben"-Tap wird der Flag auf `true` gesetzt.
        // Solange der User dreht (Re-Roll), bleibt der nächste Grant
        // wieder offen.
        creditGrantConsumed = false
        currentSpinNumber = min(currentSpinNumber + 1, maxSpins)
        dropRate.registerSpinResult(elumiCount: result.elumiCount)
        budget.awardBonusCredits(for: result.elumiCount)
        #if DEBUG
        print("🎰 [ElumiTab] Spin abgeschlossen — currentSpinNumber=\(currentSpinNumber)/\(maxSpins), Elumis=\(result.elumiCount) (Credit-Grant erfolgt erst beim 'Jetzt üben'-Tap)")
        #endif
        // **V4.4 Final-Result-Sound**:
        //   • Elumi-Treffer (1+) → Achievement-Sound (bonusbubble)
        //     + heavy Haptic → spürbarer Gewinn-Moment.
        //   • Kein Treffer → neutrales Round-Clear (leichter Abschluss-
        //     Ton) + success-Notification-Haptik. Vorher lief hier
        //     nur eine Haptik ohne Sound — der User erlebte das als
        //     „Stille nach dem Spin".
        if result.elumiCount > 0 {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            feedbackPlayer.playAchievement()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            feedbackPlayer.playRoundClear()
        }
    }

    // **2026-04-24 User-Spec + Pool-Vereinheitlichung 2026-04-30**: Der
    // separate `playCreditsChip` ist entfallen — Credits werden im
    // Arcade-Spiel-HUD und im Footer-Badge angezeigt. Mit dem Pool-
    // Merge in Stufe 1b sind Footer-Badge und In-Game-Anzeige derselbe
    // `arcadeCredits`-Wert.

    /// Baut aus dem Slot-Ergebnis eine `TrainingChainContext` und
    /// navigiert zum ersten Modul-Step.
    ///
    /// **Stufe 1 (2026-04-30, Branch `feature/training-session-flow`)**:
    /// Der frühere Pfad über `TrainingGenerator.generate(...)` ist
    /// abgelöst — der Slot-Spin selbst diktiert jetzt die Modul-
    /// Reihenfolge. Game-Slots sind in `TrainingChainContext.make(...)`
    /// bereits gefiltert; bei reinem Game-Jackpot (3× Game) ist das
    /// Builder-Result `nil`, und wir fallen still zurück (Stufe 5
    /// führt das Jackpot-UI ein).
    ///
    /// **Versuchslogik-Reset**: Vor der Navigation setzen wir
    /// `currentSpinNumber` auf 0 + räumen das lastSpinResult auf.
    /// Damit hat der Nutzer bei Rückkehr zum Tab frische 3 Versuche.
    ///
    /// **Stufe 2 (2026-04-30)** — Pre-Screen-Verkettung. Statt direkt
    /// aufs erste Modul zu pushen, navigieren wir auf
    /// `.trainingChainOverview(chain)`. Der Pre-Screen rendert den Plan
    /// und pusht beim CTA-Tap selbst auf das erste Modul (über
    /// `HomeHeroModule.chainScreen(...)` im `AppDestinationHost`).
    ///
    /// **Slot-State bleibt sichtbar (R12)**: die früheren Resets
    /// (`currentSpinNumber = 0`, `lastSpinResult = nil`,
    /// `slotPhase = .idle`, `resultHighlight*`) sind entfernt. Wenn der
    /// User auf dem Pre-Screen den Back-Chevron tappt, soll er sein
    /// Spin-Ergebnis im Tab unverändert wiedersehen — sonst wirkt der
    /// Chevron wie ein Hard-Reset. Der Chain-Reset selbst läuft via
    /// `TrainingChainStore.shared.clear()` aus dem Pre-Screen.
    ///
    /// **Idempotenz (creditGrantConsumed)**: verhindert die
    /// Re-Roll-Cheat-Variante 2, in der der User „Jetzt üben → Back →
    /// Jetzt üben" mit demselben `lastSpinResult` mehrfach durchläuft.
    /// Tickets gibt's nur beim ersten Tap; jeder weitere Tap mit
    /// demselben Ergebnis baut zwar die Chain neu (Pre-Screen erscheint
    /// erneut), gibt aber keine Tickets mehr. Spin/Re-Roll setzt das
    /// Flag in `handleSlotLanded` zurück.
    ///
    /// **Jackpot-Pfad (3× Game)**: `TrainingChainContext.make(...)`
    /// liefert seit Stufe 2 auch hier einen gültigen Context (mit
    /// leerem `plannedSteps`). Pre-Screen rendert nur Game-Cards und
    /// ein disabled-CTA. Credits werden trotzdem gutgeschrieben (+6).
    private func startTraining() {
        feedbackPlayer.playTabSwitch()

        guard let pendingResult = lastSpinResult else { return }

        // **Credit-Grant beim 'Jetzt üben'-Tap** (Stufe 1b Patch,
        // 2026-04-30): nur die Drehung, mit der der User tatsächlich
        // ins Training geht, gibt Tickets — verhindert Re-Roll-Farming.
        // Mapping aus `slotCreditGrantTable` (1×→+1, 2×→+3, 3×→+6).
        //
        // **Block 5 (2026-05-03)**: Grant-Logik extrahiert nach
        // `grantSpinTicketsIfNeeded(_:)` — wird auch vom Jackpot-Pfad
        // (`triggerJackpotIfApplicable`) genutzt. Idempotenz via
        // `creditGrantConsumed` bleibt unverändert.
        _ = grantSpinTicketsIfNeeded(for: pendingResult)

        // Chain-Build aus Slot-Result. Game-Slots sind in `make(...)`
        // bereits aus `plannedSteps` gefiltert (sourceCenterSymbolKinds
        // bewahrt sie für End-Summary in Stufe 4). Bei Jackpot (3× Game)
        // ist `plannedSteps` leer — Pre-Screen rendert dann nur die
        // Game-Cards und disabled-CTA mit Hint „Drehe noch mal für
        // Übungen" (siehe `TrainingChainContext.isJackpot`).
        let chain = TrainingChainContext.make(
            from: pendingResult,
            totalDuration: selectedDuration
        )

        // Chain-Start: Resume-Stores werden im Store geleert (R5).
        // **Performance-Fix 2026-05-01**: direkter Singleton-Call
        // statt observed-store, siehe Doc beim `@StateObject dropRate`-
        // Block oben. Verhalten unverändert — nur die Re-Render-
        // Cascade ist weg.
        TrainingChainStore.shared.start(chain)

        // **Stufe 2 Navigation**: Pre-Screen statt direktes Modul-Push.
        // Der Pre-Screen pusht beim „Übung starten"-CTA selbst auf den
        // ersten Chain-Step (Logik im `AppDestinationHost`-Wiring).
        navigate(.trainingChainOverview(chain))
    }

    // MARK: - Tickets-Grant (extrahiert für Block 5, 2026-05-03)

    /// Schreibt die Tickets-Belohnung für ein abgeschlossenes Spin-
    /// Ergebnis ins `ProgressStore`. Idempotent über
    /// `creditGrantConsumed` — ein und dieselbe Drehung kann nicht
    /// doppelt gegrantet werden (Re-Roll-Cheat-Variante 2 wird hier
    /// abgewehrt).
    ///
    /// Returns: Anzahl tatsächlich vergebener Tickets (`0` wenn schon
    /// gegrantet oder kein Mapping-Eintrag).
    ///
    /// **Block 5**: aus `startTraining()` herausgezogen. Wird vom
    /// Jackpot-Pfad (`triggerJackpotIfApplicable`) zur Reveal-Zeit
    /// gerufen, damit der Counter im Overlay sofort den neuen Wert
    /// im Footer-Badge widerspiegelt — und vom regulären
    /// „Jetzt üben"-Pfad in `startTraining()` zur Tap-Zeit, wie bisher.
    @discardableResult
    private func grantSpinTicketsIfNeeded(for result: SlotSpinResult) -> Int {
        guard !creditGrantConsumed else { return 0 }
        let granted = Self.slotCreditGrantTable[result.elumiCount] ?? 0
        if granted > 0 {
            ProgressStore.shared.mutate { progress in
                progress.arcadeCredits += granted
            }
            // Mirror auf bare `@AppStorage`-Key — siehe Pattern aus
            // FlashcardsView+SessionComponents:42, damit Footer-Badge
            // den neuen Wert sofort sieht.
            arcadeCredits = ProgressStore.shared.progress.arcadeCredits
        }
        creditGrantConsumed = true
        return granted
    }

    // MARK: - Jackpot-Feier-Trigger (Block 5, 2026-05-03)

    /// Prüft das aktuelle `lastSpinResult` auf Jackpot-Konfiguration
    /// (alle drei Reels = Game-Symbol) und löst gegebenenfalls die
    /// In-Place-Feier aus.
    ///
    /// Wird aus `.onChange(of: slotPhase) → .revealed` gerufen, also
    /// genau in dem Moment, in dem die Reels stillstehen. Tickets
    /// werden hier — nicht erst beim Tap auf einen Folge-CTA —
    /// gutgeschrieben, damit der Footer-Badge synchron mit dem
    /// Counter-Animation im Overlay hochzählt.
    ///
    /// Bei Nicht-Jackpot-Spins ist diese Funktion ein No-Op.
    private func triggerJackpotIfApplicable() {
        guard let result = lastSpinResult else { return }
        guard result.elumiCount == 3 else { return }
        // Tickets-Counter-Werte VOR dem Grant einfangen, damit der
        // Counter im Overlay sauber von alt → neu animiert.
        let beforeBalance = ProgressStore.shared.progress.arcadeCredits
        let granted = grantSpinTicketsIfNeeded(for: result)
        // Falls schon gegrantet (defensiv — würde theoretisch nur bei
        // Re-Render-Race auftreten): Counter trotzdem zeigen, aber mit
        // Granted = 0. Praktisch: erste Reveal triggert hier, Folge-
        // Renders sehen `creditGrantConsumed == true`.
        jackpotTicketsBefore = beforeBalance
        jackpotTicketsGranted = granted
        jackpotConfettiStartDate = Date()

        // Erfolgs-Haptik — additive Wuchtigkeit zum bestehenden
        // `playJackpot()`-Sound aus `SlotMachineView.runSpinSequence`.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // Layered Sound: zusätzlich Level-Up-Sound für tiefe Pointe
        // (Jackpot-System-Sound 1306 läuft schon parallel aus dem
        // Reel-Settle-Pfad; das Level-Up bringt einen warmen Layer
        // dazu, der auch bei stummgeschalteten System-Sounds noch
        // Punch hat).
        feedbackPlayer.playLevelUp()

        showJackpotCelebration = true
    }

    /// CTA-Closure aus `JackpotCelebrationView` — Primary „Nochmal
    /// drehen!". Schließt das Overlay und triggert einen frischen Spin
    /// (gleicher Code-Pfad wie der reguläre `triggerSpin`-CTA).
    ///
    /// Wir respektieren `canTriggerSpin` — wenn der User schon alle
    /// drei Versuche durch hat (`!hasRemainingSpins`), darf hier
    /// trotzdem nichts passieren. In der Praxis aber: Jackpot kann nur
    /// nach einem Spin auftreten, also ist `currentSpinNumber >= 1`
    /// und höchstens `== maxSpins`. Bei `currentSpinNumber == maxSpins`
    /// hat der User keinen Re-Spin mehr — Button bleibt clickable, aber
    /// der `triggerSpin()`-Guard verhindert den Spin und das Overlay
    /// dismisst trotzdem (User-Feedback: Tap reagiert).
    private func handleJackpotSpinAgain() {
        showJackpotCelebration = false
        triggerSpin()
    }

    /// CTA-Closure aus `JackpotCelebrationView` — Secondary „Zur
    /// Startseite". Schließt das Overlay und navigiert zum Home-Tab.
    /// Slot-State wird dabei *nicht* zurückgesetzt — der Slot-Tab
    /// bleibt mit dem Jackpot-Result sichtbar, falls der User später
    /// zurückkommt.
    private func handleJackpotGoHome() {
        showJackpotCelebration = false
        goHome()
    }

    /// Mappt einen Chain-Step (HomeHeroModule) auf den passenden
    /// `AppScreen` mit injiziertem `chainContext` und
    /// `shouldAutoStart=true` (Setup-Screen überspringen).
    ///
    /// **R3 (Audit-Spec)**: Akzente nutzt `.uben` als Chain-Default —
    /// Speed-Round bleibt manueller Pfad und kommt nicht aus dem Slot.
    /// **R4**: Vokabeln/Nomen/Artikel/Verben/Verbformen laufen alle
    /// über `.train(TrainingLaunchContext)`, der `preferredMode` schaltet
    /// die TrainingView intern auf den richtigen Modus.
    ///
    /// **Stufe 2 (2026-04-30)**: Wrapper um `HomeHeroModule.chainScreen(...)`
    /// — die Logik ist nach `AppNavigationModels.swift` umgezogen, weil
    /// auch `AppDestinationHost` (Pre-Screen-CTA-Closure) den Mapping
    /// braucht. Hier bleibt nur der Wrapper damit existing Call-Sites
    /// unverändert bleiben.
    private func screenForChainStep(
        _ step: HomeHeroModule,
        chainContext: TrainingChainContext
    ) -> AppScreen {
        step.chainScreen(chainContext: chainContext)
    }

    // MARK: - Result-Highlight (2026-04-25 User-Spec)

    /// **V3 (2026-04-25)**: Nur noch Initial-Burst-Scale via @State.
    /// Der kontinuierliche Pulse läuft jetzt aus der `TimelineView`
    /// in `trainingResultCard` — robust gegen SwiftUI-Animation-Stops.
    /// Diese Methode ist daher schlanker: einmal kurz „Pop" auf 1.03,
    /// zurück auf 1.0. Das TimelineView-Pulse überlagert sich dann
    /// multiplikativ.
    private func triggerResultHighlight() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.52)) {
            resultHighlightScale = 1.03
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard slotPhase == .revealed else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                resultHighlightScale = 1.0
            }
        }
    }

    // **Stufe 1 (2026-04-30)**: `routeForBlock(_:)` entfernt — der
    // `TrainingExerciseType`→`AppScreen`-Mapper war auf den alten
    // `TrainingGenerator`-Pfad gemünzt. Chain-Routing geht jetzt über
    // `screenForChainStep(_:chainContext:)` direkt aus
    // `HomeHeroModule`-Slots (siehe oben).

    // **2026-04-24 Vereinfachung**: statusCard + statusMetric +
    // statusDivider entfernt. Sie waren am Footer gepinnt und
    // verursachten den „halb sichtbar unter Footer"-Bug. Streak/Level
    // bleiben im Trophy-Tab sichtbar — der Elumi-Tab fokussiert sich
    // jetzt nur auf die Slot-Machine.
}

