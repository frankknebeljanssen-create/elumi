import SwiftUI
import Combine

/// **Word Runner — Phase 2 + 3 View**
///
/// Rendert den Zustand aus `WordRunnerGame` (VM). Die View selbst
/// hält **keinen** Gameplay-State mehr — alle Mutations fließen durch
/// das ViewModel. Das macht Kollisionserkennung, Spawn-Loop und
/// Restart-Pfade zentral testbar.
///
/// Layer-Reihenfolge (ZStack, hinten → vorn):
///   1. Basis-Gradient (statisch)
///   2. Scrollende Stripes (TimelineView + Canvas)
///   3. Lane-Guides (dezente Spur-Linien)
///   4. Obstacles (TimelineView + ForEach, positioniert in world-y)
///   5. Spieler-Puk (horizontal animiert auf Ziel-Spur)
///   6. Prompt-Banner oben (nur bei Task-Welle)
///   7. State-Overlay (Idle + Game-Over Karten)
///
/// TimelineView treibt den Clock. Kollisionen werden in
/// `.onChange(of: context.date)` auf dem VM aufgerufen — **nicht** im
/// Body, weil State-Mutation im Body ein SwiftUI-Antipattern wäre.
///
/// Phase 3: Wenn eine Welle einen `prompt` hat, erscheint er oben am
/// Screen. Optionen auf den Spuren tragen ihre Labels aus dem
/// zugehörigen `RunnerTask`. Die View kennt die Task-Struktur nicht
/// direkt — sie rendert nur `Obstacle.Kind.option(label:isCorrect:)`.
struct WordRunnerGameView: View {

    @StateObject private var game: WordRunnerGame
    @StateObject private var music = WordRunnerMusicPlayer.shared

    /// **Immersive-Toggle** (Phase 7.5). WR verwendet denselben
    /// Environment-Hook wie Elumi, um den globalen Footer während
    /// des tatsächlichen Gameplays auszublenden. Im Start-Screen und
    /// im Summary bleibt der Footer sichtbar.
    @Environment(\.appSetImmersiveArcadeAction) private var setImmersiveArcade
    @Environment(\.dismiss) private var dismissEnvironment

    /// **Lifetime-Stats** (Phase 7.5 Nachsatz — „Punkte, Leben,
    /// Trophies analog Elumi"). Werden nach jedem Run aktualisiert
    /// und im Start-Screen als Stats-Card angezeigt.
    @AppStorage(appWordRunnerBestScoreKey) private var wordRunnerBestScore = 0
    @AppStorage(appWordRunnerTotalTrophiesKey) private var wordRunnerTotalTrophies = 0

    /// **Spiele-Economy** (Phase 7.5 — Start-Flow-Final). WR zieht
    /// genau wie Elumi 1 Spiel pro Runde ab. Dieselbe UserDefaults-
    /// Quelle, sodass Credits zwischen den Spielen geteilt sind.
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0

    /// **Zuletzt gewählte Liste in WR** (Phase 7.6). Damit die
    /// Listen-Auswahl über mehrere WR-Runs hinweg persistiert, auch
    /// wenn andere Module zwischendurch die globale `selectedListID`
    /// verändert haben. `""` = noch keine WR-spezifische Auswahl.
    @AppStorage(appWordRunnerLastListIDKey) private var wordRunnerLastListIDRaw = ""

    /// Steuert das Ausklapp-Verhalten des Spielregeln-Blocks — analog
    /// zu `ElumiArcadeGameView.isShowingArcadeRules`.
    @State private var isShowingRules = false

    /// Präsentiert die „Liste wählen"-Sheet (User-Spec „Tap öffnet
    /// bekannte Liste-wählen-Ansicht mit Fertig-Button").
    @State private var isShowingListPicker = false

    /// **Observed** — der Spieler darf auf dem Start-Screen die
    /// Vokabelliste wechseln (User-Wunsch „liste muss als option
    /// vorher im startscreen wählbar sein"). Wenn nicht vorhanden
    /// (Preview o. Ä.), läuft der Runner ohne Live-Content und zeigt
    /// den Empty-State.
    @ObservedObject private var listStoreRef: VocabularyListStoreContainer

    /// Close-Handler vom Präsenter (z. B. GameHub). Default: nichts —
    /// die View bleibt in der Preview auch ohne Dismiss-Kette
    /// funktional.
    var onClose: () -> Void = {}

    /// Callback „Zu den Listen" — vom Empty-State-Overlay aufgerufen,
    /// wenn der User keine (oder eine unpassende) Liste gewählt hat.
    /// Präsenter kümmert sich um Dismiss+Navigation (Cover schließen
    /// und `.lists(nil)` pushen). Wenn nicht gesetzt, fällt das Overlay
    /// auf `onClose` zurück — immerhin keine Sackgasse.
    var onGoToLists: (() -> Void)? = nil

    /// **strict-Live**-Flag. Reaktiv — rechnet sich neu, wenn der
    /// User die Liste auf dem Start-Screen wechselt.
    @State private var hasUsableList: Bool = false

    /// **Phase 7.4+ strict-live mit Live-Swap**: Wenn eine gültige
    /// Liste anliegt, nutzen wir `LiveListRunnerTaskProvider`. Wenn
    /// der User die Liste auf dem Start-Screen wechselt, rufen wir
    /// `game.refreshLiveContent()` + neue `hasUsableList`-Berechnung
    /// auf — der VM selbst bleibt dieselbe Instanz.
    init(
        listStore: VocabularyListStore? = nil,
        onClose: @escaping () -> Void = {},
        onGoToLists: (() -> Void)? = nil
    ) {
        // **Stufe 1 (2026-04-28) — Fragen-Fallback-Chain**:
        // Wenn ein Store anliegt, wird Live-Provider primär verwendet.
        // Der Seed-Provider hängt als **sekundärer Fallback** dran,
        // damit auch bei leerer/fragmentierter Liste IMMER Tasks
        // erscheinen. Strict-Live bleibt das Default-Verhalten —
        // Seed greift nur, wenn Live nichts liefert.
        let provider: RunnerTaskProvider
        if let store = listStore {
            let live = LiveListRunnerTaskProvider(listStore: store)
            let seed = SeedRunnerTaskProvider()
            provider = FallbackRunnerTaskProvider(primary: live, fallback: seed)
        } else {
            // Ohne Store → reiner Seed-Provider; Empty-State-Overlay
            // gatet den Start zwar, aber wenn doch gestartet wird,
            // gibt es Tasks.
            provider = SeedRunnerTaskProvider()
        }
        _game = StateObject(wrappedValue: WordRunnerGame(taskProvider: provider))
        _listStoreRef = ObservedObject(wrappedValue: VocabularyListStoreContainer(store: listStore))
        self.onClose = onClose
        self.onGoToLists = onGoToLists
    }

    // MARK: - View-Tuning (nur Visuals, Gameplay-Tuning lebt im VM)

    private static let stripeSpacing: CGFloat = 80
    private static let stripeThickness: CGFloat = 2
    /// **Visual Tuning** — Spieler weiter verkleinert (60 → 50).
    /// Vehicle bei Ratio 1.6 also ~80 pt breit. Mit den breiten Lanes
    /// (lane-gap ~125 pt auf iPhone 15) bleibt deutlich Luft beim
    /// Spurwechsel.
    private static let playerSize: CGFloat = 50
    /// User-Feedback: STOP-Achteck zu schmal — „STOP"-Text wird
    /// abgeschnitten. Schild dezent vergrößert (56×45 → 70×52 → 80×60).
    /// Phase 7.6: weitere +14 % (Breite) / +15 % (Höhe), damit der STOP-
    /// Text sicher und großzügig reinpasst.
    private static let obstacleSize: CGSize = .init(width: 80, height: 60)
    /// Smooth-Settle-Animation für den Spieler **nach** Drag-End oder
    /// bei Tap-Sprüngen. `interactiveSpring` statt reiner `easeOut`,
    /// weil sie kurz mit-ziehen kann, wenn der Finger schnell weiter
    /// wandert. Kein Overshoot — User-Wunsch: „smooth, wie Arcade".
    private static let settleAnimation: Animation = .interactiveSpring(
        response: 0.28,
        dampingFraction: 0.86,
        blendDuration: 0.2
    )

    // MARK: - Drag-/Tap-State (Phase 3.5: Arcade-Stil)
    //
    // Das Arcade-Spiel benutzt `DragGesture(minimumDistance: 0)` mit
    // onChanged → Player folgt dem Finger in Echtzeit, kein Snap.
    // Für den 3-Lane-Runner machen wir eine Hybrid-Variante:
    //   • Während Drag: `displayX` = Finger-X (1:1, keine Animation) —
    //     der Spieler „klebt" am Finger. Parallel bestimmt die Finger-
    //     Position die logische Spur (`laneForX`), damit Kollision
    //     immer mit der nächstgelegenen Spur abgeglichen wird.
    //   • Auf Drag-End: `displayX` animiert zur Spur-X (smooth Spring).
    //   • Auf Tap: `setLane` absolute + displayX-Spring zur Ziel-Spur.
    //
    // Das liest sich analog zum Arcade-Gefühl, lässt aber die
    // Collision-Logik diskret auf Spuren laufen.

    /// Zuletzt angezeigte X-Position des Spielers. Startet `nil`, bis
    /// wir die Screen-Breite kennen — erster `onAppear` setzt sie auf
    /// die Mitte-Spur.
    @State private var displayX: CGFloat? = nil

    /// True, solange der Finger unten ist. Während Drag KEINE
    /// Animation auf `displayX` — sonst lagt der Sprite hinter dem
    /// Finger hinterher, das würde sich wieder „zäh" anfühlen.
    @State private var isDragging: Bool = false

    /// **Jump-vs-Drag-Klassifikation**: wurde der Finger während der
    /// aktuellen Geste über den `jumpVsDragThreshold` hinaus bewegt?
    /// Wenn ja → Geste ist ein Drag (Lane-Wechsel). Wenn nicht → bei
    /// `onEnded` als Tap interpretieren (Jump im Running-State, Start
    /// im Idle-State).
    ///
    /// Wird in `onChanged` auf `true` geflippt, sobald der Threshold
    /// überschritten ist, und in `onEnded` nach der Auswertung
    /// wieder zurückgesetzt.
    @State private var gestureMovedBeyondTapThreshold: Bool = false

    /// Leichter Tilt-Winkel (Grad) für den Sprite — wird kurz auf
    /// ±6° gekippt, wenn sich die logische Spur ändert, und federt
    /// zurück auf 0. Gibt dem Lane-Wechsel Body-Language ohne
    /// aufdringliches Overshoot im Positions-Spring.
    @State private var tilt: Double = 0

    /// **Combo-Badge** (Mini-Ziele): bei welchem Combo-Wert wurde
    /// zuletzt ein „X in Folge!"-Badge angezeigt? Verhindert
    /// Mehrfach-Trigger pro Combo-Stufe.
    @State private var comboBadgeMilestone: Int = 0
    /// Zeitstempel, ab dem der Badge sichtbar ist; `nil` = aktuell
    /// kein Badge. Lebensdauer ~1.5 s, dann faded es aus.
    @State private var comboBadgeShownAt: Date? = nil

    // MARK: - Runden-System (Phase 7.6 D)
    //
    // Runden gliedern den Run in 25-Sekunden-Abschnitte. Die
    // tatsächliche Difficulty steigt weiter über die bestehende
    // Speed-Ramp (`startScrollSpeed` → `peakScrollSpeed` über 35 s)
    // und Wave-Interval-Ramp (2.8 s → 2.1 s über 60 s) — das Runden-
    // System ist primär **visuelles Pacing**, nicht Difficulty-Spike.
    // Beim Übergang zur nächsten Runde wird ein zentriertes Badge
    // „Runde X" kurz eingeblendet (Fade + Scale).

    /// Runden-Dauer in Sekunden. Jede Runde: 25 s (User-Spec).
    private static let roundDuration: TimeInterval = 25.0
    /// Anzeigedauer des Runden-Badges.
    private static let roundBadgeDuration: TimeInterval = 1.8

    /// Zuletzt angezeigte Runde — verhindert Dauer-Trigger.
    @State private var displayedRound: Int = 1
    /// Zeitstempel, ab dem das „Runde X"-Badge sichtbar ist.
    @State private var roundBadgeShownAt: Date? = nil

    /// Aktuelle Runde (1-basiert) bei gegebener Welt-Zeit.
    private func currentRound(at date: Date) -> Int {
        let elapsed = game.effectiveElapsed(context: date)
        return max(1, Int(elapsed / Self.roundDuration) + 1)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // **Hintergrund (Phase 6 / Art-Direction)** — Unterwasser-
                // Farbverlauf + Lichtstrahl. Statisch (bis auf leichten
                // Drift).
                underwaterBackground(size: geo.size)
                    .allowsHitTesting(false)

                // **Mittelgrund (Phase 6c / Art-Direction Schicht 2)**.
                // Dunkle Korallen-/Pflanzen-Silhouetten links und
                // rechts des Spiel-Korridors. Parallax: sie scrollen
                // langsamer als die Obstacles (halber Speed), damit
                // sich Tiefe spürbar entfaltet.
                midgroundDecor(size: geo.size)
                    .allowsHitTesting(false)

                // **Vorderer Mittelgrund (Visual-Tuning)** —
                // kleine Steine/Korallen-Knubbel, schneller scrollend
                // als die Korallen-Silhouetten (0.7× statt 0.5×) →
                // dritte Tiefenebene zwischen Mittelgrund und
                // Spielfeld. Spec: „kleine Elemente / verschiedene
                // Tiefenebenen / keine großen zusätzlichen Objekte".
                smallForegroundDecor(size: geo.size)
                    .allowsHitTesting(false)

                // **Seegras-Cluster (Phase 7.4)** — kleine Pflanzen-
                // Tuffs außerhalb der Spielzone, in Gruppen gespawnt
                // (nicht gleichverteilt). Leicht wiegende Halme via
                // Sin-Wave. Parallax-Scroll langsamer als die Wellen,
                // damit echte Tiefe entsteht.
                seagrassClusters(size: geo.size)
                    .allowsHitTesting(false)

                // **Ambient-Fischschwarm (Phase 7.4)** — gelegentlicher
                // Schwarm von 3–4 kleinen Fisch-Silhouetten, der
                // horizontal durch den Mittelgrund zieht. Periodisch
                // (~jede 18 s), keine Kollision, nicht über der
                // Spielspur — liegt bei Y in der oberen Hälfte.
                ambientFishSchool(size: geo.size)
                    .allowsHitTesting(false)

                // **Ambient-Qualle (Phase 7.4)** — seltener, langsam
                // schwebender Schirm mit Tentakeln. Erscheint ~alle
                // 45 s, am äußeren Rand, driftet vertikal. Nie
                // mittig, nie über der Lese-Spur.
                ambientJellyfish(size: geo.size)
                    .allowsHitTesting(false)

                // **Blasen-Partikel (Phase 7.4)** — kleine aufsteigende
                // Luftblasen, verteilt über die Szene. Reiner Ambient-
                // Effekt: keine Kollision, keine Interaktion, liegt
                // noch hinter dem World-Layer, damit Blasen im
                // Spielfeld nicht die Lesbarkeit der Schilder stören.
                bubbleParticles(size: geo.size)
                    .allowsHitTesting(false)

                // **Game-Feel-Kamera** (folgt Spieler leicht verzögert +
                // Shake bei Fehler). Wird auf World-Layer **und** Player
                // angewandt, damit die Bewegung gekoppelt bleibt.
                TimelineView(.animation) { ctx in
                    let offset = cameraOffset(size: geo.size, now: ctx.date)
                    ZStack {
                        worldLayer(size: geo.size)
                            .allowsHitTesting(false)

                        // **Vordergrund-Vignette** (Visual-Quality):
                        // weicher Dunkel-Verlauf an Bottom + Seiten-
                        // rändern. Lenkt den Blick zur Mitte/oben
                        // (wo die Action passiert) und gibt der
                        // unteren Bildhälfte mehr Tiefe.
                        foregroundVignette(size: geo.size)

                        // **Spieler-Bodenglanz** (Visual-Quality):
                        // weicher pinker Schein knapp unter dem
                        // Vehicle, hebt es vom dunklen Boden ab.
                        // Liegt VOR dem Vignette-Layer aber HINTER
                        // dem Player.
                        playerGroundGlow(size: geo.size)

                        playerPuck(size: geo.size)
                            .allowsHitTesting(false)
                    }
                    .offset(x: offset.width, y: offset.height)
                }
                // **Game-Over-/Summary-Freeze** (Phase 7.6): der Welt-
                // Layer verschwindet im GameOver- UND Summary-State
                // fast vollständig — starker Blur + niedrige Opacity.
                // Zusammen mit dem dunklen Dim aus dem State-Overlay
                // bleibt vom Spielhintergrund nichts Lesbares übrig
                // (User-Spec: „muss alles weg").
                .blur(radius: (game.runState.isGameOver || game.runState.isSummary) ? 22 : 0)
                .opacity((game.runState.isGameOver || game.runState.isSummary) ? 0.08 : 1)
                .animation(.easeOut(duration: 0.4), value: game.runState.isGameOver)
                .animation(.easeOut(duration: 0.4), value: game.runState.isSummary)

                // **Dedicated Gesture-Layer** (Arcade-Pattern): eigener
                // transparenter Layer mit DragGesture(minimumDistance: 0)
                // → Finger-Tracking 1:1 in Echtzeit, wie im
                // Elumi-Arcade-Spiel. Die logische Spur wird aus der
                // Finger-X abgeleitet, Kollision läuft weiter diskret.
                //
                // **Phase 7.5 Bug-Fix** (User „Listen-Auswahl führt
                // nicht zur Ansicht"): während `.idle` und `.summary`
                // darf der Gesture-Layer NICHT die Touches abfangen —
                // sonst bekommt der List-Picker-Button im Start-
                // Overlay keine Taps mehr. Im Gameplay bleibt der
                // Layer voll aktiv wie bisher.
                if game.runState.isRunning {
                    gestureLayer(size: geo.size)
                }

                // Correct-Feedback: grüne Spur-Säule leuchtet kurz
                // auf, wenn eine korrekte Option unter den Spieler
                // passiert. Liegt ÜBER den Obstacles — bleibt aber
                // auch AUSSERHALB der Kamera-Transform, damit der
                // Leucht-Balken nicht wackelt, wenn der Kamera-Shake
                // feuert.
                correctLaneFlash(size: geo.size)
                    .allowsHitTesting(false)

                // **Fisch-Event** (Ambient): zieht max. einmal pro
                // Run mittig durch das Bild. Liegt über Welt-Schicht
                // aber unter Player + UI, damit der Fisch nicht den
                // Vehicle-Sprite verdeckt.
                if game.fishEventStartedAt != nil {
                    FishSwimAcrossView(
                        startedAt: game.fishEventStartedAt!,
                        screenSize: geo.size
                    )
                    .allowsHitTesting(false)
                }

                // PromptBanner nur im Running-State — während GameOver/
                // Summary darf **kein** Wort oder Vokabel mehr sichtbar
                // sein (User-Spec: „nur der Bubble-Background darf
                // weiterlaufen").
                if game.runState.isRunning {
                    promptBanner(size: geo.size)
                }

                // Wrong-Feedback: kurzer Screen-Flash über alles
                // gezogen (außer State-Overlay). Macht den Crash
                // spürbar ohne den Sprite zu verdecken.
                wrongScreenFlash()
                    .allowsHitTesting(false)

                stateOverlay(size: geo.size)
            }
            .animation(.easeInOut(duration: 0.22), value: game.runState.isSummary)
            // **Linker Top-Stack** (Phase 7.5 — unified HUD-Position):
            // Close-Button oben, darunter Listen-Chip + Collectibles-
            // Chip. Alles auf derselben Y-Höhe wie Elumis headerBar
            // (`.padding(.top, 58)`), damit die beiden Spiele ihre
            // Chrome auf **gleicher Höhe** präsentieren.
            //
            // **User-Fix**: X nur **während Gameplay / GameOver**
            // zeigen — auf dem Start-Screen übernimmt der Chevron aus
            // `GameStartScreen` die Zurück-Funktion, in der Summary
            // handhaben die CTAs den Ausgang. Doppelte Chrome raus.
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    if game.runState.isRunning || game.runState.isGameOver {
                        closeButton
                    }
                    if game.runState.isRunning {
                        selectedListChip
                        collectiblesChip
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, 58)
            }
            // HUD oben rechts: Leben **oben** + Score **darunter**.
            // Collectibles sind nach links gewandert (s. o.), damit
            // die rechte Seite klarer nur für die „Elumis"-Anzeige
            // reserviert bleibt. Nur sichtbar während `.running` oder
            // `.gameOver`.
            .overlay(alignment: .topTrailing) {
                if game.runState.isRunning || game.runState.isGameOver {
                    hudPanel
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, 58)
                }
            }
            // **Zentrale Popup-Stack** (User-Wunsch: „alle messages
            // müssen in der mitte vertikal aufpoppen").
            //
            // Statt die drei Badges an verschiedenen Top-Offsets zu
            // platzieren, sitzen sie jetzt alle **vertikal mittig**.
            // Ein VStack mit spacing 12 pt rendert sie untereinander,
            // falls gleichzeitig aktiv — das passiert selten, und wenn
            // doch, bleiben sie alle lesbar zentriert.
            //
            // Priorität (von oben nach unten):
            //   1. Life-Lost (kritischste Info)
            //   2. Combo (positive Bestätigung)
            //   3. Pickup (Sammelobjekt)
            .overlay(alignment: .center) {
                VStack(spacing: 12) {
                    lifeLostBadge
                    comboBadge
                    collectiblePickupBadge
                }
            }
            // **Speed-Burst- + Slow-Mo-Indicator**: Pillen unter
            // der HUD-Reihe rechts oben. Vertikal gestapelt, Slow-
            // Mo darüber (häufiger sichtbar) wenn beide aktiv.
            //
            // Top-Padding 160 pt — sitzt jetzt **unter** der neuen
            // tieferen HUD (58 pt Top + ~80 pt Höhe), damit keine
            // Überlappung entsteht.
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    slowMoIndicator
                    speedBurstIndicator
                }
                .padding(.trailing, AppTheme.Spacing.md)
                .padding(.top, 160)
            }
            // **Runden-Badge (Phase 7.6 D)**: zentriertes „Runde X"
            // beim Übergang zur nächsten Runde. Fade + Scale.
            .overlay(alignment: .center) {
                roundBadge
                    .offset(y: -80)  // leicht oberhalb der Bildmitte
            }
            // **Runden-Watcher**: periodisch prüfen, ob sich die
            // Runde hochgezählt hat; bei Sprung Badge triggern.
            .overlay {
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    let round = currentRound(at: ctx.date)
                    Color.clear
                        .onChange(of: round) { _, newRound in
                            guard game.runState.isRunning,
                                  newRound > displayedRound else { return }
                            displayedRound = newRound
                            roundBadgeShownAt = Date()
                        }
                }
                .allowsHitTesting(false)
            }
        }
        .background(AppTheme.Colors.elumiMidnight)
        .ignoresSafeArea()
        // Phase 7.5 — System-Nav-Back-Button ausblenden. Der
        // Start-Screen rendert einen eigenen Chevron, Gameplay/Summary
        // haben eigene Close-Wege. Ohne diesen Toolbar-Hide würde der
        // System-Chevron während des Spielens sichtbar bleiben (User-
        // Report „doppelter chevron" + „beim spielen muss chevron weg").
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            game.stop()
            music.fadeOut(over: 0.3)
            // Immersive sauber zurückräumen, damit der Footer in
            // nachfolgenden Screens wieder sichtbar ist.
            setImmersiveArcade?(false)
        }
        // **Listen-Picker-Sheet** (Phase 7.6 Bug-3 Fix):
        // `listStore.allLists` = Custom + Level + Topic — dieselbe
        // Liste, die `ListsView` an die ListPickerSheet gibt. Damit
        // sind wirklich ALLE Listen sichtbar (inkl. Niveau/Thema),
        // nicht nur Built-in + Custom (User-Report „nur das
        // Standardpaket sichtbar").
        .sheet(isPresented: $isShowingListPicker) {
            if let store = listStoreRef.backing {
                ListPickerSheet(
                    style: .home,
                    lists: store.allLists,
                    selectedListID: store.selectedListID,
                    onSelect: { newID in
                        store.selectedListID = newID
                    },
                    onDelete: { _ in
                        // Löschen vom Start-Screen aus ist nicht
                        // gewollt — die Löschen-Logik lebt in der
                        // Listen-Verwaltung.
                    }
                )
            }
        }
        .onChange(of: game.currentCombo) { _, newCombo in
            // Badge nur an Schwellen, nicht jedes Mal.
            if Self.comboMilestones.contains(newCombo), newCombo > comboBadgeMilestone {
                comboBadgeMilestone = newCombo
                comboBadgeShownAt = Date()
            } else if newCombo == 0 {
                comboBadgeMilestone = 0
            }
        }
        // **Audio-Hygiene (Nachsatz-Spec)**: Musik fadet beim
        // Game-Over State-Entry aus, nicht erst beim Close. 0.8 s
        // Fade-Dauer überlappt sauber mit dem Crash-Moment (0.6 s
        // VM-Delay bevor das Summary-Overlay erscheint), sodass
        // Summary in ruhiger Audio-Atmosphäre startet.
        //
        // `.onChange` statt direktem Hook im VM, damit die VM keine
        // direkte Abhängigkeit auf den Music-Player hat (bleibt
        // testbar).
        .onChange(of: game.runState) { _, newState in
            if case .gameOver = newState {
                music.fadeOut(over: 0.8)
                // Lifetime-Stats aktualisieren (Phase 7.5 Nachsatz):
                // Best-Score und Trophies werden persistiert, damit
                // der Start-Screen nach jedem Run aktuelle Werte
                // zeigt. Kein Netzwerk-Call, nur UserDefaults via
                // @AppStorage — sofort konsistent bei der nächsten
                // Start-Screen-Rendering.
                if game.score > wordRunnerBestScore {
                    wordRunnerBestScore = game.score
                }
                wordRunnerTotalTrophies += game.collectiblesGathered
            }
            // **Immersive-Toggle** (Phase 7.5): Footer bleibt sichtbar,
            // solange der User im Idle-Screen oder in der Summary
            // steht. Nur während des tatsächlichen Gameplays (running /
            // gameOver) blenden wir den globalen App-Footer aus.
            switch newState {
            case .running, .gameOver:
                setImmersiveArcade?(true)
            case .idle, .summary:
                setImmersiveArcade?(false)
            }
        }
    }

    // MARK: - Gesture Layer (Phase 3.5 — Arcade-Stil)

    /// Transparente, Screen-füllende Gesten-Oberfläche. Die Gesten
    /// sind bewusst **analog zum Arcade** aufgebaut:
    ///   • `DragGesture(minimumDistance: 0)` mit `onChanged` → der
    ///     Spieler folgt dem Finger in Echtzeit (kein Snap, kein
    ///     Threshold, kein „Schwelle überschritten"-Gefühl).
    ///   • `onEnded` → smooth Settle zur nächstgelegenen Spur.
    ///   • `onTapGesture` für User, die lieber tippen statt ziehen —
    ///     Tap auf linken/mittleren/rechten Drittel springt direkt
    ///     auf diese Spur (absolut, nicht ±1-inkrementell).
    @ViewBuilder
    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(dragGesture(width: size.width))
            // **Hit-Testing nur im Running-State.** Sonst fängt der
            // screen-füllende Layer im Idle/GameOver/Summary-State alle
            // Taps ab — inklusive Close-Button (X oben links) und der
            // dedizierten CTAs im State-Overlay. Der Idle-Tap-to-Start
            // ist redundant (der explizite „Spiel starten"-Button liegt
            // im idleStartScreen darüber), und GameOver/Summary haben
            // eigene Buttons. Außerhalb von `.running` hat der Gesture-
            // Layer also kein legitimes Ziel.
            .allowsHitTesting(game.runState.isRunning)
    }

    /// Eine einzige Geste übernimmt beides:
    ///
    /// 1. **Drag** (Finger bewegt sich > `jumpVsDragThreshold` pt
    ///    horizontal): Lane folgt dem Finger, wie bisher
    ///    (Arcade-Stil, Echtzeit-Tracking).
    /// 2. **Tap** (Finger lupft ohne Threshold zu überschreiten):
    ///    - Running → **Jump**
    ///    - Idle    → Run starten
    ///    - GameOver/Summary → ignoriert (eigene CTAs übernehmen)
    ///
    /// Ohne zweite `onTapGesture`, weil Swift-UI beim parallelen
    /// Tap-Gesture inkonsistent feuert, sobald der Drag
    /// `minimumDistance: 0` hat.
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = max(0, min(width, value.location.x))
                let deltaX = abs(value.translation.width)
                // Einmal gekippt, bleibt die Geste ein Drag — verhindert
                // dass ein leicht versetztes Release nachträglich als
                // Tap misinterpretiert wird.
                if deltaX > WordRunnerGame.Tuning.jumpVsDragThreshold {
                    gestureMovedBeyondTapThreshold = true
                }
                guard game.runState.isRunning else { return }
                // Nur während echter Drag den Player mitziehen — sonst
                // würde schon ein Mini-Wackeln die Lane ändern und der
                // Tap-als-Jump-Pfad wäre kaputt.
                guard gestureMovedBeyondTapThreshold else { return }
                if !isDragging { isDragging = true }
                displayX = x
                let lane = laneForX(x, width: width)
                if lane != game.currentLane {
                    game.setLane(lane)
                    nudgeTilt(for: lane)
                }

                // **Vertikal-Drag → Speed-Control** (User-Spec):
                // Zieht der Spieler nach oben (translation.height < 0),
                // beschleunigt sich die Welt; nach unten (> 0), wird
                // sie langsamer. Mapping: 140 pt Vertikal-Drag ergibt
                // voll ausgefahrenen Speed (`userSpeedMin`/`…Max`).
                // Linear interpoliert, geclampt, glatt animiert.
                let verticalTravel = value.translation.height
                let range: CGFloat = 140
                let normalized = max(-1, min(1, -verticalTravel / range))
                let target: CGFloat
                if normalized >= 0 {
                    target = 1.0 + normalized * (WordRunnerGame.userSpeedMax - 1.0)
                } else {
                    target = 1.0 + normalized * (1.0 - WordRunnerGame.userSpeedMin)
                }
                withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
                    game.userSpeedMultiplier = target
                }
            }
            .onEnded { _ in
                let wasTap = !gestureMovedBeyondTapThreshold
                gestureMovedBeyondTapThreshold = false

                // Tap-Pfad: Jump (running) oder Start (idle). In
                // gameOver/summary ignorieren — dort gibt es dedizierte
                // CTAs; ein Jump nach Crash würde sich falsch anfühlen.
                if wasTap {
                    switch game.runState {
                    case .idle:
                        startRun()
                    case .running:
                        game.jump()
                    case .gameOver, .summary:
                        break
                    }
                }

                // **Speed-Control loslassen** → sanft zurück auf 1.0.
                // Spring-Ease damit der Übergang nicht hart bricht.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    game.userSpeedMultiplier = 1.0
                }

                guard game.runState.isRunning else {
                    isDragging = false
                    return
                }
                // Drag-Ende: Settle-Animation nur, wenn tatsächlich
                // gezogen wurde. Nach einem Tap steht der Player
                // bereits auf seiner aktuellen Lane-X.
                if isDragging {
                    isDragging = false
                    let target = width * game.currentLane.xFraction
                    withAnimation(Self.settleAnimation) {
                        displayX = target
                    }
                }
            }
    }

    /// Welche Spur liegt horizontal unter X? Drittelt die Breite;
    /// Außenränder clampen auf links/rechts, Mitte bleibt symmetrisch.
    private func laneForX(_ x: CGFloat, width: CGFloat) -> WordRunnerLane {
        let fraction = x / max(1, width)
        if fraction < 1.0 / 3.0 { return .left }
        if fraction < 2.0 / 3.0 { return .center }
        return .right
    }

    /// Kurzer Tilt-Puls (±6°), federt zurück auf 0. Richtung kommt
    /// aus der Lane-Differenz (Ziel vs. aktuell). Phase 3.5 UX-Polish.
    private func nudgeTilt(for targetLane: WordRunnerLane) {
        let direction = targetLane.rawValue - game.currentLane.rawValue
        let angle: Double = direction > 0 ? 6 : (direction < 0 ? -6 : 0)
        withAnimation(.easeOut(duration: 0.08)) {
            tilt = angle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                tilt = 0
            }
        }
    }

    // MARK: - Camera (Game-Feel Final)

    /// Kamera-Offset — nur noch **Shake** + **Idle-Drift**.
    ///
    /// **Phase-6.3-Fix** (kritisch): der vorige Follow-X koppelte
    /// die Welt an die Spieler-X-Position → Obstacles schienen sich
    /// bei jedem Spurwechsel mitzubewegen. Spec sagt explizit:
    /// „Spieler bewegt sich zwischen Spuren / Objekte bleiben stabil
    /// auf ihren Spuren / KEINE Kopplung zwischen Player Input und
    /// Objektbewegung." → Follow entfernt.
    ///
    /// Shake + Drift bleiben — das sind **welt-bezogene** Effekte
    /// (Treffer-Reaktion und sanftes „Spiel lebt"-Gefühl), nicht
    /// spieler-input-abhängig. Beide wirken auf alle Welt-Schichten
    /// (Floor, Obstacles, Player), damit sie gemeinsam rütteln.
    private func cameraOffset(size: CGSize, now: Date) -> CGSize {
        var shakeX: CGFloat = 0
        var shakeY: CGFloat = 0
        if let ts = game.lastWrongFeedbackAt {
            let age = now.timeIntervalSince(ts)
            if age < 0.3 {
                let envelope = 1.0 - age / 0.3
                shakeX = CGFloat(sin(age * 52)) * 5 * envelope
                shakeY = CGFloat(cos(age * 64)) * 3 * envelope
            }
        }
        let t = now.timeIntervalSinceReferenceDate
        let driftY = CGFloat(sin(t * 0.8)) * 0.6
        return CGSize(width: shakeX, height: shakeY + driftY)
    }

    // MARK: - HUD (Leben + Score + Collectibles)

    /// Oben rechts: 3 Leben (als Elumi-Icons) in einer eigenen Reihe,
    /// darunter Score und Collectibles **nebeneinander** in einer
    /// Row — auf derselben Höhe, damit beide Zahlen gleichrangig
    /// lesbar sind (User-Wunsch).
    ///
    /// Die HUD als Ganzes sitzt via Body-Overlay-Padding niedriger
    /// am Screen — die Lives-Row klebte vorher am Screen-Rand, jetzt
    /// ist sie klar in der sichtbaren Zone.
    @ViewBuilder
    private var hudPanel: some View {
        // Phase 7.6+: Collectibles sind in den linken Stack gewandert.
        // Rechts nur noch Leben (oben) und Score (darunter) — klare
        // vertikale Ordnung, keine konkurrierenden HStack-Elemente mehr.
        VStack(alignment: .trailing, spacing: 8) {
            livesRow
            scoreChip
        }
    }

    /// **Listen-Chip** (Phase 7.6+): kleine Pill am oberen Rand mit
    /// Listen-Icon + Namen der aktuell gewählten Vokabelliste. Hilft
    /// dem Spieler beim langen Run die Orientierung zu behalten —
    /// besonders wenn Listen mitten im Spiel gewechselt wurden (auf
    /// dem Idle-Screen über den Picker). Schlanker dunkler Capsule-
    /// Look, damit er den Spielinhalt nicht überdeckt.
    @ViewBuilder
    private var selectedListChip: some View {
        if let store = listStoreRef.backing {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#BDEBFF"))
                Text(currentListName(store: store))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
            )
            .allowsHitTesting(false)
        }
    }

    /// Collectibles-HUD (Phase 7.6+): drei separate Chips pro Typ,
    /// vertikal gestapelt. Jeder Chip zeigt Icon + Count. Bei Count 0
    /// ist der Chip gedimmt, damit der Spieler weiß, dass es diesen
    /// Typ gibt — aber noch nichts gesammelt wurde.
    @ViewBuilder
    private var collectiblesChip: some View {
        TimelineView(.animation) { ctx in
            let pulse = pickupPulseScale(at: ctx.date)
            VStack(alignment: .trailing, spacing: 4) {
                // Emojis statt geometrischer Symbole — besser
                // wiedererkennbar als das Ingame-Äquivalent (bis
                // dedizierte Sprites fürs HUD verfügbar sind).
                collectibleTypeChip(
                    symbol: "⭐",
                    tint: Color(hex: "#FFC46C"),
                    count: game.collectedStarfish,
                    isRecent: game.lastCollectiblePickupKind == .starfish
                )
                collectibleTypeChip(
                    symbol: "🪱",
                    tint: Color(hex: "#EF6C50"),
                    count: game.collectedWorm,
                    isRecent: game.lastCollectiblePickupKind == .worm
                )
                collectibleTypeChip(
                    symbol: "🔮",
                    tint: Color(hex: "#C4B5FD"),
                    count: game.collectedPearl,
                    isRecent: game.lastCollectiblePickupKind == .pearl
                )
            }
            // Puls-Scale nur auf den zuletzt gesammelten Typ
            // anwenden — die anderen Chips ruhen.
            .scaleEffect(pulse, anchor: .trailing)
        }
    }

    /// Einzelner Typ-Chip. Bei `count == 0` gedimmt; `isRecent`
    /// hebt den zuletzt aufgenommenen Typ leicht hervor (via
    /// Border-Opacity).
    @ViewBuilder
    private func collectibleTypeChip(
        symbol: String,
        tint: Color,
        count: Int,
        isRecent: Bool
    ) -> some View {
        let active = count > 0
        HStack(spacing: 4) {
            Text(symbol)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(active ? tint : tint.opacity(0.35))
            Text("\(count)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(active ? .white : .white.opacity(0.4))
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(active ? 0.55 : 0.35))
                .overlay(
                    Capsule().stroke(
                        tint.opacity(isRecent ? 0.65 : (active ? 0.35 : 0.15)),
                        lineWidth: 0.8
                    )
                )
        )
    }

    /// Skalierung (1.0…1.18) für den Pickup-Pulse — läuft 0.5 s ab
    /// `lastCollectiblePickupAt` mit Ease-Out zurück auf 1.0.
    private func pickupPulseScale(at date: Date) -> CGFloat {
        guard let ts = game.lastCollectiblePickupAt else { return 1.0 }
        let age = date.timeIntervalSince(ts)
        let window: TimeInterval = 0.5
        guard age >= 0, age < window else { return 1.0 }
        let t = age / window
        // Ease-Out: 1.18 → 1.0
        let eased = 1 - pow(1 - t, 3)
        return 1.18 - 0.18 * CGFloat(eased)
    }

    @ViewBuilder
    private var livesRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<WordRunnerGame.startingLives, id: \.self) { index in
                // Leben werden von rechts nach links aufgebraucht:
                // der erste verlorene „schlägt" also den rechtesten
                // Slot. `slotFilled` kippt dann false.
                let slotFilled = index < game.lives
                Image("SplashCharacter")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .opacity(slotFilled ? 1.0 : 0.22)
                    .scaleEffect(slotFilled ? 1.0 : 0.85)
                    .animation(.spring(response: 0.32, dampingFraction: 0.68), value: slotFilled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    @ViewBuilder
    private var scoreChip: some View {
        Text("Score \(game.score)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .overlay(
                Capsule().stroke(AppTheme.Colors.elumiPink.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Life-Lost-Badge

    /// Kurzes Badge „−1 Leben" wenn ein Leben verloren ging, der
    /// Run aber noch läuft. Lebensdauer aus
    /// `Tuning.lifeLostBadgeDuration`, Opacity rampt linear aus.
    @ViewBuilder
    private var lifeLostBadge: some View {
        TimelineView(.animation) { context in
            let intensity = lifeLostIntensity(at: context.date)
            if intensity > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("−1 Leben")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(AppTheme.Colors.elumiErrorRed.opacity(0.88))
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
                .opacity(intensity)
                .scaleEffect(0.9 + 0.15 * intensity)
            }
        }
        .allowsHitTesting(false)
    }

    private func lifeLostIntensity(at date: Date) -> Double {
        guard let ts = game.lastLifeLostAt else { return 0 }
        let age = date.timeIntervalSince(ts)
        let duration = WordRunnerGame.Tuning.lifeLostBadgeDuration
        guard age >= 0, age < duration else { return 0 }
        // Ease-out: stark am Anfang, langsames Ausfaden.
        return max(0, pow(1 - age / duration, 1.3))
    }

    // MARK: - Runden-Badge (Phase 7.6 D)

    /// Zentrales „Runde X"-Badge, das bei Rundenübergang kurz
    /// einblendet (Fade + Scale) und wieder verschwindet. Positionierung
    /// via Overlay im Main-Body; hier nur die Badge-Grafik + Intensität.
    @ViewBuilder
    private var roundBadge: some View {
        TimelineView(.animation) { context in
            let intensity = roundBadgeIntensity(at: context.date)
            if intensity > 0 {
                Text("Runde \(displayedRound)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(2)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color.black.opacity(0.55))
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                    .opacity(intensity)
                    .scaleEffect(0.78 + 0.22 * intensity)
            }
        }
        .allowsHitTesting(false)
    }

    private func roundBadgeIntensity(at date: Date) -> Double {
        guard let ts = roundBadgeShownAt else { return 0 }
        let age = date.timeIntervalSince(ts)
        let duration = Self.roundBadgeDuration
        guard age >= 0, age < duration else { return 0 }
        // Ease-in + ease-out: glockenartig (stark in der Mitte,
        // fade an beiden Enden).
        let t = age / duration
        return sin(.pi * t)
    }

    // MARK: - Combo-Badge (Mini-Ziele)

    /// Combo-Schwellen, an denen ein Badge eingeblendet wird.
    /// Bewusst nicht jede einzelne Combo — sonst würde jedes Schild
    /// einen Banner triggern. Die Schwellen werden mit der Combo
    /// seltener (3, dann 5, dann 10er-Schritte) — fühlt sich wie
    /// ein eskalierendes Ziel an.
    static let comboMilestones: Set<Int> = [3, 5, 10, 15, 20, 30, 50]

    /// Lebensdauer des Combo-Badges in Sekunden. Etwas länger als
    /// das Life-Lost-Badge, damit der Spieler in Ruhe lesen kann.
    private static let comboBadgeDuration: TimeInterval = 1.6

    @ViewBuilder
    private var comboBadge: some View {
        TimelineView(.animation) { context in
            let intensity = comboBadgeIntensity(at: context.date)
            if intensity > 0, comboBadgeMilestone > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(comboBadgeMilestone) in Folge!")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(AppTheme.Colors.elumiMint.opacity(0.95))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: AppTheme.Colors.elumiMint.opacity(0.5), radius: 10, x: 0, y: 4)
                .opacity(intensity)
                .scaleEffect(0.85 + 0.20 * intensity)
            }
        }
        .allowsHitTesting(false)
    }

    private func comboBadgeIntensity(at date: Date) -> Double {
        guard let ts = comboBadgeShownAt else { return 0 }
        let age = date.timeIntervalSince(ts)
        let duration = Self.comboBadgeDuration
        guard age >= 0, age < duration else { return 0 }
        // Erst kurz wachsen, dann lange ausfaden.
        if age < 0.18 {
            return age / 0.18
        }
        return max(0, pow(1 - (age - 0.18) / (duration - 0.18), 1.5))
    }

    // MARK: - Pickup-Popup (Phase 7.4 Nachsatz)

    /// Lebensdauer des Collectible-Pickup-Popups. Kurz genug, um
    /// mehrere Pickups nacheinander nicht zu stapeln, lang genug
    /// um lesbar zu sein.
    private static let collectibleBadgeDuration: TimeInterval = 1.3

    /// Pop-up beim Einsammeln eines Collectible. Zeigt:
    ///   • Art-Icon (Stern / Wurm-Kritzel / Kreis)
    ///   • Name des Items („Seestern", „Würmchen", „Perle")
    ///   • Score-Bonus (+25 / +10 / +60)
    ///
    /// Fade-In 0.12 s, dann Ausfaden über die Restzeit. Nie störend
    /// über der Entscheidungs-Zone — sitzt auf `padding(.top, 178)`
    /// im Body-Overlay, also noch über dem Horizont aber unterhalb
    /// des Combo-Badge-Slots.
    @ViewBuilder
    private var collectiblePickupBadge: some View {
        TimelineView(.animation) { context in
            let intensity = collectibleBadgeIntensity(at: context.date)
            if intensity > 0,
               let kind = game.lastCollectiblePickupKind {
                HStack(spacing: 8) {
                    Image(systemName: kind.iconSystemName)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(badgeIconColor(for: kind))
                    Text("+\(kind.scoreBonus)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(kind.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            Capsule().stroke(badgeIconColor(for: kind).opacity(0.55), lineWidth: 1)
                        )
                )
                .shadow(color: badgeIconColor(for: kind).opacity(0.45), radius: 10, x: 0, y: 4)
                .opacity(intensity)
                .scaleEffect(0.88 + 0.15 * intensity)
                .offset(y: CGFloat(-8 * (1 - intensity)))   // startet leicht über Ziel
            }
        }
        .allowsHitTesting(false)
    }

    private func collectibleBadgeIntensity(at date: Date) -> Double {
        guard let ts = game.lastCollectiblePickupAt else { return 0 }
        let age = date.timeIntervalSince(ts)
        let duration = Self.collectibleBadgeDuration
        guard age >= 0, age < duration else { return 0 }
        let fadeIn: Double = 0.12
        if age < fadeIn {
            return age / fadeIn
        }
        return max(0, pow(1 - (age - fadeIn) / (duration - fadeIn), 1.6))
    }

    private func badgeIconColor(for kind: WordRunnerCollectible) -> Color {
        switch kind {
        case .starfish: return Color(hex: "#FFC46C")    // warmes Gold
        case .worm:     return Color(hex: "#FF9EA8")    // koralliges Rosa
        case .pearl:    return Color(hex: "#CFD6FF")    // perlmutt-Blau
        }
    }

    // MARK: - Slow-Mo-Indikator

    @ViewBuilder
    private var slowMoIndicator: some View {
        TimelineView(.animation) { _ in
            let active = game.runState.isRunning && game.slowMoEndsAt != nil &&
                Date() < (game.slowMoEndsAt ?? .distantPast)
            if active {
                HStack(spacing: 5) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .bold))
                    Text("Slow-Mo")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color(hex: "#5BD9FF").opacity(0.95))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color(hex: "#5BD9FF").opacity(0.55), radius: 8, x: 0, y: 3)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: game.slowMoEndsAt)
        .allowsHitTesting(false)
    }

    // MARK: - Speed-Burst-Indikator

    @State private var lastSpeedBurstSoundAt: Date?

    @ViewBuilder
    private var speedBurstIndicator: some View {
        TimelineView(.animation) { context in
            let elapsed = game.effectiveElapsed(context: context.date)
            let active = game.runState.isRunning &&
                WordRunnerGame.Tuning.isInSpeedBurst(at: elapsed)
            // SFX-Trigger: einmal pro Burst-Beginn (mit Cooldown
            // gegen Re-Trigger durch TimelineView-Body-Re-Renders).
            let _: Void = {
                if active {
                    let cooldownOK = lastSpeedBurstSoundAt
                        .map { Date().timeIntervalSince($0) > 4.0 } ?? true
                    if cooldownOK {
                        WordRunnerSFXPlayer.shared.play(.boost)
                        DispatchQueue.main.async {
                            lastSpeedBurstSoundAt = Date()
                        }
                    }
                }
                return ()
            }()
            if active {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Boost")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(AppTheme.Colors.elumiAmber.opacity(0.95))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: AppTheme.Colors.elumiAmber.opacity(0.55), radius: 8, x: 0, y: 3)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: game.runStart)
        .allowsHitTesting(false)
    }

    // MARK: - Close-Button

    @ViewBuilder
    private var closeButton: some View {
        Button {
            // **Phase 7.6 Bug-Fix** (User: „kreuz während spiel führt
            // zurück zum SPIEL start screen, NICHT zum home"): der
            // X-Button bricht **nur den laufenden Run ab** und kehrt
            // zum WR-Start-Screen (idle state) zurück. Kein
            // `onClose()` mehr — das würde den ganzen WR-Screen
            // dismissen und zum Home navigieren. Der User will
            // danach die Liste ändern oder nochmal starten, ohne
            // das ganze Spiel zu verlassen.
            game.stop()
            music.fadeOut(over: 0.3)
            // Footer wieder zeigen (immersive aus), damit der User
            // Navigation hat. Der WR-Start-Screen selbst rendert
            // sein eigenes Chrome (Chevron oben links).
            setImmersiveArcade?(false)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schließen")
    }

    // MARK: - Vordergrund-Vignette + Player-Glow (Visual-Quality)

    /// Weicher Vignette-Effekt am unteren Bildrand.
    /// Verstärkt die Tiefenwahrnehmung — der Blick wandert
    /// automatisch nach oben in den helleren Horizont-Bereich.
    @ViewBuilder
    private func foregroundVignette(size: CGSize) -> some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.clear,
                Color.black.opacity(0.18),
                Color.black.opacity(0.40)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    /// Weicher pinker Bodenschein unter dem Vehicle. Hebt den
    /// Spieler vom dunklen Road-Plane ab, ohne ihn zu „glühen".
    ///
    /// **Phase 7.6 Fix**: Die X-Position folgt jetzt derselben Logik
    /// wie `playerPuck` — `displayX` (Finger-Tracking während Drag) +
    /// Breath-Offset (statische Lane × Atmung). Vorher hing der Schein
    /// an der statischen Lane-X und „hing" merklich hinter dem Spieler
    /// her, wenn der User die Spur schnell wechselte.
    @ViewBuilder
    private func playerGroundGlow(size: CGSize) -> some View {
        let staticLaneX = size.width * game.currentLane.xFraction
        let playerY = size.height * WordRunnerGame.Tuning.playerYFraction
        TimelineView(.animation) { context in
            let elapsed = game.effectiveElapsed(context: context.date)
            let breathFraction = WordRunnerGame.Tuning.laneXFraction(
                game.currentLane,
                at: elapsed
            ) - game.currentLane.xFraction
            let breathOffset = breathFraction * size.width
            let baseX = displayX ?? staticLaneX
            let centerX = baseX + breathOffset

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.Colors.elumiPink.opacity(0.30),
                            AppTheme.Colors.elumiPink.opacity(0.10),
                            AppTheme.Colors.elumiPink.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 70)
                .blendMode(.plusLighter)
                .position(x: centerX, y: playerY + 22)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Underwater-Hintergrund (Art-Direction)
    //
    // Mehrschichtige Atmosphäre (Step 3):
    //   1. Basis-Gradient (oben dunkel, Mitte hell-Navy, unten dunkler)
    //   2. Horizont-Band: heller Streifen auf Horizonthöhe → Horizont
    //      bewusst sichtbar machen, nicht nur als abstrakter Y-Wert.
    //   3. Mehrere God-Rays (Lichtstrahlen) — 3 schräge Shafts von oben.
    //   4. Aufsteigende Bubbles (Partikel) — sehr subtil, geben der
    //      Szene Lebendigkeit ohne Unruhe.

    @ViewBuilder
    private func underwaterBackground(size: CGSize) -> some View {
        let horizonY = WordRunnerGame.Tuning.horizonY(screenHeight: size.height)

        ZStack {
            // (1) Basis-Gradient — leicht aufgehellt im mittleren
            // Bereich, damit sich ein „Wasser-Licht"-Hauch durchs Bild
            // zieht (Step 3: „Hintergrund heller").
            LinearGradient(
                colors: [
                    AppTheme.Colors.elumiMidnight,
                    AppTheme.Colors.elumiNavy,
                    AppTheme.Colors.elumiBlue.opacity(0.28),   // neu: heller Strahl Mitte
                    AppTheme.Colors.elumiNavy,
                    AppTheme.Colors.elumiMidnight
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // (2) Horizont-Band — dünner horizontaler Cyan-Glow,
            // exakt auf Horizonthöhe. Macht den Fluchtpunkt visuell
            // als Linie greifbar.
            LinearGradient(
                colors: [
                    AppTheme.Colors.elumiBlue.opacity(0),
                    AppTheme.Colors.elumiBlue.opacity(0.32),
                    AppTheme.Colors.elumiBlue.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 48)
            .blendMode(.plusLighter)
            .position(x: size.width * 0.5, y: horizonY)
            .allowsHitTesting(false)

            // (2b) **Sonne / Mond am Horizont** (Phase 6.6) — radialer
            // Glow exakt am Fluchtpunkt. Klein (~ 90 pt), nicht zu hell
            // (Spec: „kein Fokusklau"). Leichter Sinus-Drift gibt der
            // Lichtquelle ein bisschen Leben, ohne abzulenken.
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let glowPulse = 0.85 + 0.15 * (0.5 + 0.5 * sin(t * 0.4))
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.Colors.elumiCream.opacity(0.45 * glowPulse),
                                AppTheme.Colors.elumiBlue.opacity(0.25 * glowPulse),
                                AppTheme.Colors.elumiBlue.opacity(0)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .position(x: size.width * 0.5, y: horizonY - 6)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }

            // (3) God-Rays — 3 schräge Lichtschäfte (diagonal 20°),
            // jeder mit eigenem Sinus-Drift für organisches Schwingen.
            godRays(size: size)

            // (4) Aufsteigende Bubbles — subtile weiße/cyan Kreise,
            // die vom Boden aufsteigen. Rein Hintergrund, nicht
            // interaktiv.
            risingBubbles(size: size)
        }
    }

    /// Drei diagonale Lichtschäfte mit leichter Drift.
    @ViewBuilder
    private func godRays(size: CGSize) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { canvasCtx, canvasSize in
                // Jeder Strahl ist ein Parallelogramm — gezeichnet als
                // gefüllte Path mit Linear-Gradient darüber.
                // Phase 6.6: God-Rays leiser (Spec „Schilder visuell
                // wichtiger als Hintergrund") — Opacity ~halbiert.
                let anchors: [(xFrac: CGFloat, opacity: Double, phase: Double)] = [
                    (0.22, 0.10, 0.0),
                    (0.52, 0.08, 1.8),
                    (0.78, 0.11, 3.2)
                ]
                for anchor in anchors {
                    let drift = CGFloat(sin(t * 0.25 + anchor.phase)) * 20
                    let topX = canvasSize.width * anchor.xFrac + drift
                    let bottomX = topX + 120   // 20°-Neigung nach rechts
                    let width: CGFloat = 70
                    var path = Path()
                    path.move(to: CGPoint(x: topX - width/2, y: 0))
                    path.addLine(to: CGPoint(x: topX + width/2, y: 0))
                    path.addLine(to: CGPoint(x: bottomX + width/2, y: canvasSize.height))
                    path.addLine(to: CGPoint(x: bottomX - width/2, y: canvasSize.height))
                    path.closeSubpath()
                    canvasCtx.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                AppTheme.Colors.elumiBlue.opacity(anchor.opacity),
                                AppTheme.Colors.elumiBlue.opacity(0)
                            ]),
                            startPoint: CGPoint(x: topX, y: 0),
                            endPoint: CGPoint(x: bottomX, y: canvasSize.height)
                        )
                    )
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    /// 10 aufsteigende Bubbles mit unterschiedlichen Perioden.
    @ViewBuilder
    private func risingBubbles(size: CGSize) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { canvasCtx, canvasSize in
                // Phase 6.6: weniger Bubbles (12 → 8) + niedrigeres
                // Max-Alpha — Hintergrund stört nicht mehr.
                for i in 0..<8 {
                    let seed = Double(i) * 0.7
                    // Lineare Aufstiegs-Bewegung + horizontaler Wobble.
                    // Periode: 8-16 Sekunden.
                    let period = 10.0 + (Double(i) * 1.3).truncatingRemainder(dividingBy: 6.0)
                    let cycle = ((t + seed * 2).truncatingRemainder(dividingBy: period)) / period
                    // Y wandert von unten nach oben, X leicht sinus-wobblend.
                    let baseX = (Double(i) * 73).truncatingRemainder(dividingBy: Double(canvasSize.width - 40)) + 20
                    let wobble = sin(t * 0.9 + seed * 3) * 18
                    let x = CGFloat(baseX + wobble)
                    let y = canvasSize.height * (1.0 - CGFloat(cycle)) + 20
                    let bubbleSize: CGFloat = 3 + CGFloat((Double(i) * 0.37).truncatingRemainder(dividingBy: 4))
                    // Opacity fadet am oberen Rand aus.
                    let alpha = min(0.18, 0.18 * (1 - cycle * 0.7))
                    canvasCtx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - bubbleSize/2,
                            y: y - bubbleSize/2,
                            width: bubbleSize,
                            height: bubbleSize
                        )),
                        with: .color(AppTheme.Colors.elumiBlue.opacity(alpha))
                    )
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Midground (Phase 6c)

    /// Dunkle Silhouetten links und rechts vom Spiel-Korridor —
    /// Korallen, Seegras. Parallax: sie scrollen **langsamer** als
    /// die Obstacles (halber Travel), damit sich der Raum in Tiefe
    /// entfaltet, ohne dass sie mit dem Foreground konkurrieren.
    ///
    /// Jede Silhouette hat einen `seed` für Form-Variation (Skalierung,
    /// Spitzen-Count) — so wirken sie nicht geklont. Style bleibt
    /// dunkel und weich: nur als Silhouette vor dem tieferen Blau,
    /// nicht als detailliertes Asset.
    @ViewBuilder
    private func midgroundDecor(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            let elapsed = game.effectiveElapsed(context: context.date)
            // Parallax-Faktor 0.5 → Mittelgrund zieht halb so schnell
            // wie Obstacles. Fühlt sich räumlich an, ohne störend
            // schnell zu wandern.
            let midTravel = WordRunnerGame.Tuning.cumulativeTravel(at: elapsed) * 0.5

            Canvas { ctx, canvasSize in
                // Wir platzieren Silhouetten in einem wiederholenden
                // vertikalen Grid. Der `midTravel`-Offset sorgt für
                // Scrolling; Silhouetten, die unten rausfallen,
                // tauchen oben (am Horizont) wieder auf.
                let spacing: CGFloat = 180
                let horizon = WordRunnerGame.Tuning.horizonY(screenHeight: canvasSize.height)
                let bottomY = canvasSize.height + 100
                let range = bottomY - horizon
                let offset = midTravel.truncatingRemainder(dividingBy: spacing)
                let count = Int(range / spacing) + 3

                for i in 0..<count {
                    // Zwei Seiten: links und rechts.
                    for side in [-1, 1] {
                        let seed = CGFloat((i * 7 + (side == -1 ? 3 : 11)) % 13) / 13.0
                        let y = horizon + CGFloat(i) * spacing - offset
                        guard y >= horizon - 40 && y <= bottomY else { continue }

                        // Depth aus Y, determiniert Skalierung + Blur.
                        // Kleiner in Horizont-Nähe, größer in Player-Nähe.
                        let z = WordRunnerGame.Tuning.depth(
                            forWaveY: y,
                            screenHeight: canvasSize.height
                        )
                        let clampedZ = max(0, min(1.2, z))
                        let eased = pow(max(0, min(1, clampedZ)), 1.4)

                        // X-Position am Rand des Korridors. Je tiefer
                        // (höher z), desto weiter außen — in Horizont-
                        // Nähe kollabieren die Silhouetten ebenfalls
                        // Richtung Mitte.
                        let outwardFraction: CGFloat = 0.92 * eased
                        let centerX = canvasSize.width * 0.5
                        let maxOutward = canvasSize.width * 0.55
                        let outward = centerX + CGFloat(side) * maxOutward * outwardFraction

                        // Silhouetten-Höhe + Breite skalieren mit
                        // Tiefe. `seed` variiert die Spitzen-Anzahl.
                        let siloHeight: CGFloat = (70 + seed * 60) * (0.35 + 0.65 * eased)
                        let siloWidth: CGFloat = (36 + seed * 28) * (0.35 + 0.65 * eased)

                        // Silhouetten-Farbe: sehr dunkles Midnight mit
                        // leichter Blau-Tönung. Opacity wächst mit
                        // Tiefe, damit Horizont-nahe Silhouetten im
                        // Dunst verschwinden.
                        let alpha = 0.12 + 0.38 * eased

                        var path = Path()
                        let baseX = outward
                        let baseY = y + siloHeight * 0.5
                        let topY = y - siloHeight * 0.5
                        // Einfache Silhouette: breite Basis, spitz
                        // zulaufend nach oben, mit 2-3 Wellen.
                        path.move(to: CGPoint(x: baseX - siloWidth * 0.5, y: baseY))
                        path.addQuadCurve(
                            to: CGPoint(x: baseX - siloWidth * 0.2, y: topY + siloHeight * 0.3),
                            control: CGPoint(x: baseX - siloWidth * 0.55, y: y)
                        )
                        path.addQuadCurve(
                            to: CGPoint(x: baseX + siloWidth * 0.1, y: topY),
                            control: CGPoint(x: baseX - siloWidth * 0.15 + seed * 10, y: topY + siloHeight * 0.1)
                        )
                        path.addQuadCurve(
                            to: CGPoint(x: baseX + siloWidth * 0.45, y: topY + siloHeight * 0.35),
                            control: CGPoint(x: baseX + siloWidth * 0.5, y: topY + siloHeight * 0.05)
                        )
                        path.addQuadCurve(
                            to: CGPoint(x: baseX + siloWidth * 0.5, y: baseY),
                            control: CGPoint(x: baseX + siloWidth * 0.55, y: y + siloHeight * 0.2)
                        )
                        path.closeSubpath()

                        ctx.fill(
                            path,
                            with: .color(AppTheme.Colors.elumiMidnight.opacity(alpha))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Small Foreground Decor (Visual-Tuning Schicht 3)

    /// Kleine Steine + Korallen-Knubbel **näher** am Spieler als
    /// die Mittelgrund-Korallen. Parallax 0.7× — schneller als
    /// Mittelgrund, langsamer als Spielfeld.
    ///
    /// Form ist bewusst klein und einfach: kleine Ovale/Kreise mit
    /// dunkler Farbe + leichtem Cyan-Highlight. Sie sollen die
    /// Strecke „atmen lassen", nicht zur Show werden — daher Größe
    /// streng skaliert mit Tiefe + dezente Opacity.
    ///
    /// Position: ausserhalb des Tracks, wo Mittelgrund-Silhouetten
    /// schon stehen, aber an anderen Y-Spawnpunkten — beide Layer
    /// fallen nicht auf die gleiche Y-Linie und konkurrieren nicht.
    @ViewBuilder
    private func smallForegroundDecor(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            let elapsed = game.effectiveElapsed(context: context.date)
            let smallTravel = WordRunnerGame.Tuning.cumulativeTravel(at: elapsed) * 0.7

            Canvas { ctx, canvasSize in
                let spacing: CGFloat = 130   // dichter als Mittelgrund (180)
                let horizon = WordRunnerGame.Tuning.horizonY(screenHeight: canvasSize.height)
                let bottomY = canvasSize.height + 80
                let range = bottomY - horizon
                let offset = smallTravel.truncatingRemainder(dividingBy: spacing)
                let count = Int(range / spacing) + 3

                for i in 0..<count {
                    for side in [-1, 1] {
                        let seed = CGFloat((i * 11 + (side == -1 ? 5 : 17)) % 17) / 17.0
                        let y = horizon + CGFloat(i) * spacing - offset + seed * 25
                        guard y >= horizon - 20 && y <= bottomY else { continue }

                        let z = WordRunnerGame.Tuning.depth(forWaveY: y, screenHeight: canvasSize.height)
                        let clampedZ = max(0, min(1.2, z))
                        let eased = pow(max(0, min(1, clampedZ)), 1.2)

                        // X-Position: weiter außen als die
                        // Mittelgrund-Korallen, damit beide Layer
                        // sichtbar bleiben.
                        let centerX = canvasSize.width * 0.5
                        let outerFraction: CGFloat = 0.78 * eased + 0.30
                        let x = centerX + CGFloat(side) * canvasSize.width * 0.5 * outerFraction

                        // Größe: klein, mit Tiefe wachsend.
                        let stoneSize: CGFloat = (10 + seed * 14) * (0.4 + 0.6 * eased)
                        let alpha = 0.20 + 0.30 * eased

                        // Stein/Knubbel als Ellipse mit leichter
                        // Form-Variation (seed).
                        let aspect: CGFloat = 0.55 + seed * 0.45
                        let rect = CGRect(
                            x: x - stoneSize / 2,
                            y: y - stoneSize * aspect / 2,
                            width: stoneSize,
                            height: stoneSize * aspect
                        )
                        ctx.fill(
                            Path(ellipseIn: rect),
                            with: .color(AppTheme.Colors.elumiMidnight.opacity(alpha))
                        )
                        // Mini-Highlight oben drauf für „solide Form"
                        let highlightRect = CGRect(
                            x: x - stoneSize * 0.18,
                            y: y - stoneSize * aspect * 0.32,
                            width: stoneSize * 0.36,
                            height: stoneSize * aspect * 0.20
                        )
                        ctx.fill(
                            Path(ellipseIn: highlightRect),
                            with: .color(AppTheme.Colors.elumiBlue.opacity(alpha * 0.5))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Seegras-Cluster (Phase 7.4 — Ambient-Life)

    /// Kleine Seegras-Tuffs in **Clustern** (Spec: „nicht gleichmäßig,
    /// sondern in Clustern") beidseits der Spielspur. Jeder Cluster
    /// besteht aus 3–5 Halmen unterschiedlicher Höhe, die leicht im
    /// Takt wiegen (Sin-Wave). Parallax-Scroll langsamer als die
    /// Obstacles → Tiefen-Gefühl.
    ///
    /// **Sicherheits-Regel**: Cluster liegen nur in der **outer zone**
    /// (>46 % vom Zentrum nach außen). Die Lane-Zone (0.18 / 0.50 /
    /// 0.82) bleibt frei, damit Seegras keine Schilder verdeckt.
    @ViewBuilder
    private func seagrassClusters(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            let elapsed = game.effectiveElapsed(context: context.date)
            // Parallax: Seegras scrollt langsamer als die Welt, damit
            // es „weiter hinten" wirkt.
            let travel = WordRunnerGame.Tuning.cumulativeTravel(at: elapsed) * 0.62

            Canvas { gc, canvasSize in
                let clusterSpacing: CGFloat = 180
                let horizon = WordRunnerGame.Tuning.horizonY(screenHeight: canvasSize.height)
                let bottomY = canvasSize.height + 40
                let range = bottomY - horizon
                let offset = travel.truncatingRemainder(dividingBy: clusterSpacing)
                let count = Int(range / clusterSpacing) + 3

                for i in 0..<count {
                    for side in [-1, 1] {
                        // Seed stabil pro Position — gleicher Cluster
                        // zeigt denselben Halm-Mix in jedem Frame.
                        let seed = abs(i * 13 + (side == -1 ? 7 : 23)) % 29
                        let yJitter = CGFloat(seed % 9) * 6
                        let y = horizon + CGFloat(i) * clusterSpacing - offset + yJitter
                        guard y >= horizon - 10 && y <= bottomY else { continue }

                        let z = WordRunnerGame.Tuning.depth(forWaveY: y, screenHeight: canvasSize.height)
                        let eased = pow(max(0, min(1, z)), 1.3)
                        // Cluster komplett überspringen, wenn zu
                        // nah am Spieler (unterste 15 %) — sonst
                        // hebt Seegras den Vordergrund-Dreck zu
                        // sehr hervor. Dort übernehmen die Boden-
                        // Steine aus `smallForegroundDecor`.
                        guard eased < 0.88 else { continue }

                        let centerX = canvasSize.width * 0.5
                        // Weiter außen als smallForegroundDecor (0.46 →
                        // 0.92 vs. 0.30 → 0.78) — Seegras sitzt „am
                        // Rand der Strecke", nicht mittig davor.
                        let outerFraction: CGFloat = 0.46 + 0.46 * eased
                        let x = centerX + CGFloat(side) * canvasSize.width * 0.5 * outerFraction

                        // Cluster-Größe skaliert mit Tiefe.
                        let scaleFactor = 0.35 + 0.65 * eased
                        let clusterHeight: CGFloat = (28 + CGFloat(seed % 10) * 4) * scaleFactor
                        let bladeCount = 3 + (seed % 3)

                        for b in 0..<bladeCount {
                            let bladeSeed = seed &+ b &* 5
                            let bladeOffset = CGFloat(b - bladeCount / 2) * (clusterHeight * 0.14)
                            let bladeHeight = clusterHeight * (0.65 + CGFloat(bladeSeed % 5) / 10.0)
                            // Sway: langsam, phasenversetzt pro Halm
                            let phase = elapsed * 1.25 + Double(bladeSeed) * 0.7
                            let swayMagnitude: Double = Double(bladeHeight) * 0.18
                            let sway = sin(phase) * swayMagnitude

                            let baseX = x + bladeOffset
                            let baseY = y
                            let tipX = baseX + CGFloat(sway)
                            let tipY = baseY - bladeHeight
                            let midX = baseX + CGFloat(sway) * 0.55
                            let midY = baseY - bladeHeight * 0.5

                            var path = Path()
                            path.move(to: CGPoint(x: baseX, y: baseY))
                            path.addQuadCurve(
                                to: CGPoint(x: tipX, y: tipY),
                                control: CGPoint(x: midX, y: midY)
                            )
                            // Farbe: Tiefes Türkis-Grün, etwas heller
                            // an der Spitze für subtile Materialtiefe.
                            let baseAlpha = 0.38 + 0.32 * eased
                            let stroke = GraphicsContext.Shading.linearGradient(
                                Gradient(colors: [
                                    Color(hex: "#1F5E4A").opacity(baseAlpha * 0.85),
                                    Color(hex: "#4FB388").opacity(baseAlpha)
                                ]),
                                startPoint: CGPoint(x: baseX, y: baseY),
                                endPoint: CGPoint(x: tipX, y: tipY)
                            )
                            gc.stroke(path, with: stroke, lineWidth: max(1.0, 2.0 * scaleFactor))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ambient-Fischschwarm (Phase 7.4)

    /// Kleiner Schwarm von 3–4 Fisch-Silhouetten, der **gelegentlich**
    /// horizontal durch den Mittelgrund zieht. Kein VM-State —
    /// TimelineView steuert die Periodik komplett selbst:
    ///
    ///   - Period: 22 s
    ///   - Dauer pro Durchlauf: 6 s
    ///   - Y-Position: obere Bildhälfte (zwischen 18 % und 42 %),
    ///     damit die Spielzone frei bleibt
    ///   - Richtung wechselt pro Periode (links→rechts, dann rechts→links)
    @ViewBuilder
    private func ambientFishSchool(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 22
            let swimWindow: Double = 6
            let localPhase = t.truncatingRemainder(dividingBy: period)
            let isSwimming = localPhase < swimWindow
            let cycleIndex = Int(t / period)
            let swimFraction = CGFloat(localPhase / swimWindow)   // 0…1
            let goesRight = cycleIndex.isMultiple(of: 2)
            // Y-Position: zufällig aus den obersten 25 % der sichtbaren
            // Zone, stabil pro Cycle via cycleIndex-seed.
            let ySeed = Double((cycleIndex * 37) % 11) / 11.0     // 0…1
            let y = size.height * (0.18 + 0.24 * CGFloat(ySeed))
            // Swarm-Geschwindigkeit: ~90 % der Screen-Breite in 6 s.
            let swimSpan = size.width * 1.15
            let baseX = goesRight
                ? (-size.width * 0.10 + swimFraction * swimSpan)
                : ( size.width * 1.10 - swimFraction * swimSpan)

            ZStack {
                if isSwimming {
                    // 4 Fische, leicht versetzt in X + Y für
                    // Schwarm-Feeling.
                    ForEach(0..<4, id: \.self) { i in
                        let offsetX: CGFloat = CGFloat(i) * 22 - 12
                        let offsetY: CGFloat = CGFloat(sin(Double(i) * 1.1 + t * 2.0)) * 6
                        AmbientFishSilhouette(facingRight: goesRight)
                            .frame(width: 36, height: 14)
                            .opacity(0.45)
                            .position(x: baseX + (goesRight ? offsetX : -offsetX),
                                      y: y + offsetY)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    // MARK: - Ambient-Qualle (Phase 7.4)

    /// Eine langsam driftende Qualle — erscheint **selten** (etwa alle
    /// 45 s), driftet 10 s lang vertikal nach oben durch das äußere
    /// Drittel und verblasst. Bewusst **nie mittig** (würde die Lese-
    /// Achse konkurrieren); wechselt pro Zyklus die Seite.
    @ViewBuilder
    private func ambientJellyfish(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = 45
            let driftWindow: Double = 10
            let localPhase = t.truncatingRemainder(dividingBy: period)
            let isVisible = localPhase < driftWindow
            let cycleIndex = Int(t / period)
            let onLeft = cycleIndex.isMultiple(of: 2)
            let driftFraction = CGFloat(localPhase / driftWindow)   // 0…1
            // Vertikal driften von Bildunterkante in Richtung oberer
            // Mitte: startY = height + 60, endY = height * 0.22.
            let startY = size.height + 60
            let endY = size.height * 0.22
            let y = startY + (endY - startY) * driftFraction
            // X-Position: äußerer Rand, leichte Sin-Drift.
            let baseFraction: CGFloat = onLeft ? 0.18 : 0.82
            let xDrift = sin(t * 0.6 + Double(cycleIndex) * 0.9) * 14
            let x = size.width * baseFraction + CGFloat(xDrift)
            // Einblenden am Anfang + Ausblenden am Ende:
            let opacity: Double = {
                if driftFraction < 0.15 { return Double(driftFraction / 0.15) * 0.55 }
                if driftFraction > 0.85 { return Double((1.0 - driftFraction) / 0.15) * 0.55 }
                return 0.55
            }()

            if isVisible {
                JellyfishSilhouette(time: t)
                    .frame(width: 70, height: 95)
                    .opacity(opacity)
                    .position(x: x, y: y)
            }
        }
    }

    // MARK: - Bubble-Partikel (Phase 7.4 — Ambient-Life)

    /// Kleine aufsteigende Luftblasen. **Rein deterministisch** über
    /// Canvas mit Seed-Offset pro Blase — keine State-Mutation im Body,
    /// keine Random-Glitches beim Re-Render.
    ///
    /// Gestaltungsregeln:
    ///   - nur an den **Rändern** dichter; mittlere Spielzone bleibt
    ///     ruhig, damit Schilder klar lesbar sind
    ///   - langsame Aufwärtsbewegung (30 pt/s), leichtes horizontales
    ///     Wiegen via Sin-Wave
    ///   - sehr transparente Pastell-Cyan-Farbe → keine Ablenkung
    @ViewBuilder
    private func bubbleParticles(size: CGSize) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, canvasSize in
                let bubbleCount = 14
                for i in 0..<bubbleCount {
                    let seed = Double(i) * 7.31
                    // X: Blasen sammeln sich an beiden Rändern, nicht
                    // mittig — `|sin(seed)|` → 0..1, dann auf
                    // [0.04, 0.18] ∪ [0.82, 0.96] gemappt.
                    let sideBias = (seed.truncatingRemainder(dividingBy: 2) < 1) ? 0.0 : 1.0
                    let sideSpread = 0.14 * abs(sin(seed * 1.3))
                    let xFraction = sideBias == 0
                        ? 0.04 + sideSpread
                        : 0.82 + sideSpread
                    let x = canvasSize.width * xFraction

                    // Y: aufsteigend, looped alle `period` Sekunden.
                    let period = 7.0 + (seed.truncatingRemainder(dividingBy: 3)) * 2
                    let phase = (t + seed * 0.9).truncatingRemainder(dividingBy: period) / period
                    let yStart = canvasSize.height + 20
                    let yEnd: CGFloat = -20
                    let y = yStart + (yEnd - yStart) * CGFloat(phase)

                    // Seitliches Wiegen
                    let sway = sin((t + seed) * 1.1) * 3.5
                    let drawX = x + CGFloat(sway)

                    // Größe wächst leicht beim Aufsteigen
                    let radius: CGFloat = 1.4 + CGFloat(phase) * 2.4
                    let alpha = 0.28 * (1.0 - CGFloat(phase) * 0.4)

                    let rect = CGRect(x: drawX - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    gc.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(hex: "#9FE1FF").opacity(alpha))
                    )
                    // Mini-Highlight innerhalb der Blase
                    let hiRect = CGRect(
                        x: drawX - radius * 0.5,
                        y: y - radius * 0.6,
                        width: radius * 0.55,
                        height: radius * 0.55
                    )
                    gc.fill(
                        Path(ellipseIn: hiRect),
                        with: .color(Color.white.opacity(alpha * 1.3))
                    )
                }
            }
        }
    }

    // MARK: - World Layer (Perspektivischer Boden + Obstacles)

    @ViewBuilder
    private func worldLayer(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            // „Effective now" friert bei Game-Over ein — dadurch
            // bleiben Stripes + Obstacles am Crash-Ort stehen statt
            // unter dem Spieler durchzuscrollen.
            let elapsed = game.effectiveElapsed(context: context.date)

            ZStack {
                perspectiveFloor(size: size, elapsed: elapsed)
                obstacleLayer(size: size, elapsed: elapsed)
            }
            .onChange(of: context.date) { _, newDate in
                // Tick fährt Kollision + Cleanup im VM — off-body,
                // damit kein State-Mutation-Warnung.
                game.tick(now: newDate, screenHeight: size.height)
            }
        }
    }

    // MARK: - Perspektiv-Boden (Phase 6)

    /// Zeichnet
    ///   • drei **konvergierende Spur-Linien** vom Fluchtpunkt am
    ///     Horizont zu den Spur-X-Positionen auf Spielerebene,
    ///   • **scrollende Quer-Streifen** (Bodenmarkierungen), die
    ///     nach Tiefe skaliert kürzer und heller werden —
    ///     imitiert eine Rennstreifen-Straße, aber in Wasser-
    ///     Farben. Die Streifen fließen vom Horizont Richtung
    ///     Spieler, geben damit die „Bewegung durch den Raum"
    ///     haptisch spürbar.
    @ViewBuilder
    private func perspectiveFloor(size: CGSize, elapsed: TimeInterval) -> some View {
        let horizonY = WordRunnerGame.Tuning.horizonY(screenHeight: size.height)
        let playerY = WordRunnerGame.Tuning.playerY(screenHeight: size.height)
        let centerX = size.width * 0.5
        let outerExtraY = size.height + 200

        Canvas { ctx, canvasSize in
            // Edge-to-edge Road bleibt; Spec-8-Add: die Lane-
            // Separatoren und der äußere Lane-Anker atmen mit der
            // `laneXFraction(at:)`-Variation — Boden bleibt
            // synchron zu Obstacles und Player-Spuren.
            let horizonSpread = WordRunnerGame.Tuning.horizonLaneSpread
            let roadBottomY = outerExtraY
            let roadTopY = horizonY
            let halfAtBottom = canvasSize.width * 0.5
            let halfAtTop = halfAtBottom * horizonSpread

            // ────────────────────────────────────────────────────────
            // (A) **Fahrbahn-Fläche** (gefülltes Trapez). Das ist
            //     der entscheidende Phase-6.4-Fix: die Strecke bekommt
            //     einen **eigenen Untergrund** statt nur Linien. Links
            //     + rechts bleibt Unterwasser-Welt sichtbar.
            // ────────────────────────────────────────────────────────
            var road = Path()
            road.move(to: CGPoint(x: centerX - halfAtBottom, y: roadBottomY))
            road.addLine(to: CGPoint(x: centerX - halfAtTop, y: roadTopY))
            road.addLine(to: CGPoint(x: centerX + halfAtTop, y: roadTopY))
            road.addLine(to: CGPoint(x: centerX + halfAtBottom, y: roadBottomY))
            road.closeSubpath()

            // Road-Gradient: etwas heller als der Wasser-BG — wirkt
            // wie ein illuminierter Pfad im Ozean. Oben dunkler (zieht
            // sich in die Tiefe), unten heller (nah am Spieler).
            ctx.fill(
                road,
                with: .linearGradient(
                    Gradient(colors: [
                        AppTheme.Colors.elumiMidnight.opacity(0.85),
                        AppTheme.Colors.elumiNavy,
                        AppTheme.Colors.elumiBlue.opacity(0.35)
                    ]),
                    startPoint: CGPoint(x: centerX, y: roadTopY),
                    endPoint: CGPoint(x: centerX, y: roadBottomY)
                )
            )

            // ────────────────────────────────────────────────────────
            // (A2) **Subtile Road-Textur** — feine Diagonal-Streifen
            //     auf der gesamten Fahrbahn-Fläche. Innerhalb eines
            //     `drawLayer`-Sub-Contexts geclipped, damit nach-
            //     folgende Borders/Separatoren wieder ungeclippt
            //     zeichnen können.
            // ────────────────────────────────────────────────────────
            ctx.drawLayer { layerCtx in
                layerCtx.clip(to: road)
                let textureSpacing: CGFloat = 22
                let textureCount = Int((roadBottomY - roadTopY) / textureSpacing) + 6
                for i in -2..<textureCount {
                    let y = roadTopY + CGFloat(i) * textureSpacing
                    var diag = Path()
                    diag.move(to: CGPoint(x: -40, y: y))
                    diag.addLine(to: CGPoint(x: canvasSize.width + 40,
                                              y: y - 14))
                    layerCtx.stroke(
                        diag,
                        with: .color(AppTheme.Colors.elumiCream.opacity(0.04)),
                        lineWidth: 1
                    )
                }
            }

            // ────────────────────────────────────────────────────────
            // (B) **Track-Border links + rechts** — dickere helle
            //     Linien, dick genug um als Straßenkante zu lesen.
            // ────────────────────────────────────────────────────────
            for side: CGFloat in [-1, 1] {
                var border = Path()
                border.move(to: CGPoint(x: centerX + side * halfAtBottom, y: roadBottomY))
                border.addLine(to: CGPoint(x: centerX + side * halfAtTop, y: roadTopY))
                ctx.stroke(
                    border,
                    with: .linearGradient(
                        Gradient(colors: [
                            AppTheme.Colors.elumiCream.opacity(0.38),
                            AppTheme.Colors.elumiCream.opacity(0.04)
                        ]),
                        startPoint: CGPoint(x: 0, y: roadBottomY),
                        endPoint: CGPoint(x: 0, y: roadTopY)
                    ),
                    lineWidth: 3
                )
            }

            // ────────────────────────────────────────────────────────
            // (C) **Lane-Separatoren** (dashed, scrollend) —
            //     gestrichelte Linien zwischen den drei Spuren,
            //     klassische Highway-Markierung. Die Striche
            //     wandern mit `cumulativeTravel` nach unten → fühlt
            //     sich wie „wir fahren auf einer Straße" an.
            // ────────────────────────────────────────────────────────
            let travel = WordRunnerGame.Tuning.cumulativeTravel(at: elapsed)
            let offset = travel.truncatingRemainder(dividingBy: Self.stripeSpacing)

            // Boundaries zwischen Lanes (2 Dashed-Reihen):
            // zwischen Left+Center und Center+Right.
            // Spec 8: Spuren atmen via `laneXFraction(at:)` — die
            // Boundaries müssen mit-atmen, sonst driften Stripes
            // gegen die Obstacle-Linien.
            let leftFraction = WordRunnerGame.Tuning.laneXFraction(.left, at: elapsed)
            let centerFraction = WordRunnerGame.Tuning.laneXFraction(.center, at: elapsed)
            let rightFraction = WordRunnerGame.Tuning.laneXFraction(.right, at: elapsed)
            let boundaryFractions: [CGFloat] = [
                (leftFraction + centerFraction) / 2,
                (centerFraction + rightFraction) / 2
            ]

            for fraction in boundaryFractions {
                let baseOffset = (fraction - 0.5) * canvasSize.width
                let steps = Int((outerExtraY - horizonY) / Self.stripeSpacing) + 2
                for i in 0..<steps {
                    let y = horizonY + CGFloat(i) * Self.stripeSpacing - offset
                    guard y >= horizonY && y <= outerExtraY else { continue }
                    let z = WordRunnerGame.Tuning.depth(forWaveY: y, screenHeight: canvasSize.height)
                    let clampedZ = max(0, min(1.3, z))
                    let eased = pow(max(0, min(1, clampedZ)), WordRunnerGame.Tuning.perspectiveEase)
                    let spread = horizonSpread + (1 - horizonSpread) * eased

                    // Dash-Länge + Dicke skalieren mit Tiefe.
                    let dashLength: CGFloat = 20 + 24 * eased
                    let thickness: CGFloat = 2 + 3 * eased
                    let alpha: Double = 0.22 + 0.45 * Double(eased)

                    let xMid = centerX + baseOffset * spread
                    var dash = Path()
                    dash.addRect(CGRect(
                        x: xMid - thickness / 2,
                        y: y - dashLength / 2,
                        width: thickness,
                        height: dashLength
                    ))
                    ctx.fill(
                        dash,
                        with: .color(AppTheme.Colors.elumiCream.opacity(alpha))
                    )
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Obstacles

    @ViewBuilder
    private func obstacleLayer(size: CGSize, elapsed: TimeInterval) -> some View {
        // **Phase 6** — perspektivische Projektion:
        //   • `waveY` kommt aus dem gemeinsamen Helper (identische
        //     Welt-Y wie Kollisions-Detection).
        //   • X kollabiert zur Mitte, je tiefer (am Horizont → alle 3
        //     Spuren bei Screen-Mitte).
        //   • Skalierung sinkt mit Tiefe (am Horizont ~35 %).
        //   • Leichter 3D-Tilt auf Cards (10° vorgekippt) gibt den
        //     „aus der Tiefe ziehend"-Effekt.
        ForEach(game.waves) { wave in
            let waveY = WordRunnerGame.Tuning.waveY(
                elapsed: elapsed,
                wave: wave,
                screenHeight: size.height
            )
            let z = WordRunnerGame.Tuning.depth(forWaveY: waveY, screenHeight: size.height)
            let scale = WordRunnerGame.Tuning.depthScale(z)

            // **Atmospheric Perspective** (Visual-Quality-Pass):
            // Ferne Schilder werden **leicht entsättigt** (0.65 am
            // Horizont, 1.0 am Spieler) und etwas transparenter
            // (0.78 → 1.0). Das gibt echten Tiefen-Dunst, ohne die
            // Lesbarkeit zu killen — bei voller Annäherung sind die
            // Schilder wieder voll satt + opak.
            let zClamped = max(0, min(1, z))
            let opacity = 0.78 + 0.22 * zClamped
            let depthSaturation = 0.65 + 0.35 * zClamped

            ForEach(wave.obstacles) { obs in
                let x = WordRunnerGame.Tuning.perspectiveX(
                    lane: obs.lane,
                    depth: z,
                    width: size.width,
                    elapsed: elapsed
                )
                let seedX = CGFloat(abs(obs.id.uuidString.hashValue % 360)) * .pi / 180
                let seedY = CGFloat(abs(obs.id.uuidString.dropFirst().hashValue % 360)) * .pi / 180
                let bobPhase = elapsed * 1.1
                let wobbleX = sin(bobPhase + Double(seedX)) * 2
                let wobbleY = sin(bobPhase * 0.8 + Double(seedY)) * 1.5
                // **Green-Pass-Marker**: das Schild, durch das der
                // Spieler korrekt durchgefahren ist, bleibt **grün**
                // — auch nachdem es ihn passiert hat. Macht Erfolg
                // sichtbar und dauerhaft, nicht nur als 0.4 s-Pulse.
                let isPassedCorrect = game.consumedCorrectIDs.contains(obs.id)
                obstacleView(
                    obs,
                    isPassedCorrect: isPassedCorrect,
                    colorTheme: wave.colorTheme,
                    signVariant: signVariant(for: obs.id)
                )
                    .scaleEffect(scale)
                    .saturation(depthSaturation)
                    .opacity(opacity)
                    .position(x: x + CGFloat(wobbleX), y: waveY + CGFloat(wobbleY))
            }
        }
        .allowsHitTesting(false)
    }

    /// **Sign-Variante** aus dem Obstacle-UUID ableiten (stabil über
    /// Frames, rotierende Auswahl). Damit bekommen verschiedene
    /// Schilder innerhalb einer Welle bzw. über Wellen hinweg eine
    /// von drei Wegweiser-Formen (Classic, Gate, Marker).
    private func signVariant(for id: UUID) -> SignOnPostView.Variant {
        let hash = abs(id.uuidString.hashValue)
        let variants: [SignOnPostView.Variant] = [.classic, .gate, .marker]
        return variants[hash % variants.count]
    }

    @ViewBuilder
    private func obstacleView(
        _ obs: WordRunnerObstacle,
        isPassedCorrect: Bool = false,
        colorTheme: WordRunnerColorTheme = .turquoise,
        signVariant: SignOnPostView.Variant = .classic
    ) -> some View {
        switch obs.kind {
        case .blocker:
            // STOP-Schild bleibt klassisch rot-achteckig (Verkehrs-
            // Semantik, unabhängig von Task-Farbwelt). Variante wird
            // hier ignoriert — STOP hat eine feste Form.
            SignOnPostView(
                label: "STOP",
                isHazard: true,
                isPassedCorrect: false,
                panelSize: Self.obstacleSize,
                colorTheme: colorTheme,
                variant: .classic
            )
        case .construction:
            // Baustellen-Schild (Phase 7.6) — oranges Warn-Dreieck mit
            // SF-Symbol. Gameplay identisch zu `.blocker` (fatal,
            // jumpable), nur visuelle Variante für mehr Abwechslung in
            // Hazard-Wellen.
            ConstructionObstacleView(size: Self.obstacleSize)
        case .option(let label, _):
            SignOnPostView(
                label: label,
                isHazard: false,
                isPassedCorrect: isPassedCorrect,
                panelSize: Self.obstacleSize,
                colorTheme: colorTheme,
                variant: signVariant
            )
        case .rock(let variant):
            // 5 Shape-Varianten — Variant-Index kommt aus dem Model,
            // damit Replay deterministisch bleibt.
            RockObstacleView(size: Self.obstacleSize, variant: variant)
        case .powerUp(let kind):
            PowerUpView(kind: kind, size: Self.obstacleSize)
        case .collectible(let kind):
            CollectibleView(kind: kind, size: Self.obstacleSize)
        }
    }

    // MARK: - Player

    @ViewBuilder
    private func playerPuck(size: CGSize) -> some View {
        let staticLaneX = size.width * game.currentLane.xFraction
        let playerY = size.height * WordRunnerGame.Tuning.playerYFraction

        TimelineView(.animation) { context in
            let elapsed = game.effectiveElapsed(context: context.date)
            // Spec 8 — Lane-Atmung als additiver Offset:
            // Differenz zwischen dynamischer und statischer Lane-X
            // wird auf die Position aufaddiert. Ergebnis: Player
            // sitzt synchron mit Obstacles auf seiner aktuellen Spur,
            // auch wenn die Spur leicht atmet.
            let breathFraction = WordRunnerGame.Tuning.laneXFraction(
                game.currentLane,
                at: elapsed
            ) - game.currentLane.xFraction
            let breathOffset = breathFraction * size.width
            // Während Drag folgt der Finger; sonst Lane-X (statisch
            // + Breath). `displayX` wird beim Drag-Start gesetzt
            // und bei Drag-End auf staticLaneX zurück-animiert.
            let baseX = displayX ?? staticLaneX
            let playerX = baseX + breathOffset

            // **Jump-Geometrie** (Wall-Clock): Höhe + Landing-Squash.
            // Wall-Clock statt `elapsed`, damit der Sprung auch im
            // Slow-Mo in 0.45 s durchläuft — Spieler-Input bleibt
            // konsistent schnell.
            let jumpH = game.jumpHeight(at: context.date)
            let squashY = game.landingSquashScaleY(at: context.date)
            // Luft-Shadow: Schatten bleibt am Boden (Baseline-Y),
            // schrumpft + wird transparenter, je höher der Spieler
            // fliegt. Bei jumpH == 0 → normale Opazität, keine
            // sichtbare Änderung im stehenden Zustand.
            let jumpProgress = jumpH / WordRunnerGame.Tuning.jumpMaxHeight
            let shadowScale = 1.0 - 0.35 * jumpProgress
            let shadowOpacity = 0.32 * (1.0 - 0.55 * jumpProgress)

            ZStack {
                // Boden-Schatten (liegt auf playerY, folgt nicht dem
                // Jump-Y-Offset — dadurch entsteht der Eindruck, dass
                // der Player vom Boden abhebt).
                Ellipse()
                    .fill(Color.black.opacity(shadowOpacity))
                    .frame(
                        width: Self.playerSize * 0.75 * shadowScale,
                        height: Self.playerSize * 0.22 * shadowScale
                    )
                    .blur(radius: 2)
                    .position(x: playerX, y: playerY + Self.playerSize * 0.44)
                    .allowsHitTesting(false)

                // Vehicle + Shield: folgen Jump-Y-Offset + Squash.
                ZStack {
                    if game.shieldCharges > 0 {
                        ShieldAuraView(charges: game.shieldCharges, size: Self.playerSize)
                    }
                    ElumiVehicleView(
                        lean: tilt,
                        size: Self.playerSize
                    )
                }
                .scaleEffect(x: 1.0, y: squashY, anchor: .bottom)
                .position(x: playerX, y: playerY - jumpH)
            }
        }
        .onAppear {
            // Erster Frame: Spieler auf statische Lane-X — Breath
            // wird erst zur Laufzeit additiv on-top aufgerechnet.
            if displayX == nil {
                displayX = staticLaneX
            }
        }
        .onChange(of: size.width) { _, newWidth in
            displayX = newWidth * game.currentLane.xFraction
        }
    }

    // MARK: - Prompt Banner (Phase 3)

    /// Oben am Screen schwebender Prompt-Banner, nur sichtbar solange
    /// eine Task-Welle **noch nicht durch ist**. Dadurch sieht der
    /// Spieler den Prompt rechtzeitig, während die Welle runterkommt
    /// — und der Banner verschwindet synchron, wenn die Welle passiert
    /// ist (statt bis zur nächsten Welle stehenzubleiben).
    @ViewBuilder
    private func promptBanner(size: CGSize) -> some View {
        // **Phase 6.5 (größter UX-Fix)**: Prompt klebt jetzt direkt
        // **über der aktuell herannahenden Welle**, nicht mehr fix am
        // Screen-Oberrand. Vorher sprang das Auge:
        //   „oben Prompt lesen" → „unten Welle verfolgen" → Entscheidung
        // Jetzt ist beides im selben Fokusbereich:
        //   Prompt + Schilder in **einer** Augenbewegung.
        //
        // Y-Position:
        //   • wave waveY vorhanden → prompt Y = waveY - 65 (knapp drüber)
        //   • Floor-Bounds: nie höher als horizonY + 20 (oben sichtbar
        //     bleiben) und nie tiefer als playerY - 220 (genug Abstand
        //     zum Spieler, damit Prompt den Spieler nicht berührt).

        let activeTaskInfo = activeTaskYInfo(size: size)

        ZStack(alignment: .top) {
            Color.clear
            if let info = activeTaskInfo, let prompt = info.wave.prompt {
                promptCard(
                    prompt: prompt,
                    context: info.wave.contextLine,
                    colorTheme: info.wave.colorTheme
                )
                    .position(x: size.width * 0.5, y: info.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: activeTaskInfo?.wave.id)
        .allowsHitTesting(false)
    }

    /// Paar aus aktiver Task-Welle + gewünschter Prompt-Y-Position.
    /// Getrennt von `currentActiveTaskWave`, weil wir hier zusätzlich
    /// die Wave-Y + Bounds brauchen.
    private func activeTaskYInfo(size: CGSize) -> (wave: WordRunnerWave, y: CGFloat)? {
        guard let wave = currentActiveTaskWave(size: size) else { return nil }
        let now = Date()
        let elapsed = game.effectiveElapsed(context: now)
        let waveY = WordRunnerGame.Tuning.waveY(
            elapsed: elapsed,
            wave: wave,
            screenHeight: size.height
        )
        let horizonY = WordRunnerGame.Tuning.horizonY(screenHeight: size.height)
        let playerY = WordRunnerGame.Tuning.playerY(screenHeight: size.height)
        let targetY = waveY - 65
        let upperBound = horizonY + 22
        let lowerBound = playerY - 230
        let clamped = max(upperBound, min(lowerBound, targetY))
        return (wave, clamped)
    }

    /// Aktuell **relevante** Task-Welle: die erste Welle mit Prompt,
    /// die sich der Spielerzone **nähert**. Phase 3.5 UX-Polish:
    /// Banner erscheint **kurz vor** der Entscheidung, nicht schon
    /// beim Spawn am Screen-Oberrand — sonst hätte der Spieler 2 s
    /// lang einen Prompt vor sich, ohne dass er etwas tun kann.
    ///
    /// Sichtbarkeits-Fenster:
    ///   `playerY - revealDistance  ≤  waveY  ≤  playerY + 20`
    ///
    /// revealDistance = 55 % der Screen-Höhe ≈ 2 s Vorwarnzeit bei
    /// 260 pt/s Scroll-Speed. Unterhalb des Spielers (+20 pt Puffer)
    /// ist die Welle durch → Banner verschwindet.
    private func currentActiveTaskWave(size: CGSize) -> WordRunnerWave? {
        // User-Feedback: „Frage muss sofort sichtbar sein, damit man
        // den ganzen Weg Zeit hat, sich zu entscheiden." Deshalb
        // **keine** `revealTop`-Schwelle mehr — der Banner erscheint
        // mit dem Spawn der Welle und verschwindet, wenn die Welle
        // den Spieler passiert hat.
        let now = Date()
        let elapsed = game.effectiveElapsed(context: now)
        let playerY = WordRunnerGame.Tuning.playerY(screenHeight: size.height)
        return game.waves.first { wave in
            guard wave.prompt != nil else { return false }
            let waveY = WordRunnerGame.Tuning.waveY(
                elapsed: elapsed,
                wave: wave,
                screenHeight: size.height
            )
            return waveY < playerY + 20
        }
    }

    // MARK: - Correct-Feedback (Phase 3.5)

    /// Grüner Spur-Glow, der kurz aufleuchtet wenn eine korrekte
    /// Option unter den Spieler passiert. Liest den Zeitstempel aus
    /// der VM (`lastCorrectFeedbackAt`) und rampt Opacity über die
    /// `correctFeedbackDuration` aus.
    @ViewBuilder
    private func correctLaneFlash(size: CGSize) -> some View {
        TimelineView(.animation) { context in
            let intensity = correctFeedbackIntensity(at: context.date)
            if intensity > 0, let lane = game.lastCorrectLane {
                let elapsed = game.effectiveElapsed(context: context.date)
                let x = size.width * WordRunnerGame.Tuning.laneXFraction(lane, at: elapsed)
                let columnWidth: CGFloat = size.width / 3
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.elumiMint.opacity(0.55 * intensity),
                                AppTheme.Colors.elumiMint.opacity(0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: columnWidth, height: size.height * 0.7)
                    .position(x: x, y: size.height * 0.55)
            }
        }
    }

    private func correctFeedbackIntensity(at date: Date) -> Double {
        guard let ts = game.lastCorrectFeedbackAt else { return 0 }
        let age = date.timeIntervalSince(ts)
        let duration = WordRunnerGame.Tuning.correctFeedbackDuration
        guard age >= 0, age < duration else { return 0 }
        return max(0, 1 - age / duration)
    }

    // MARK: - Wrong-Feedback (Phase 3.5)

    /// Kurzer roter Full-Screen-Flash, wenn ein fataler Treffer
    /// passiert ist. Läuft zeitgleich mit dem Game-Over-Overlay-Delay
    /// — der Spieler sieht in diesen ~0.6 s den eingefrorenen Crash-
    /// Moment + diesen Flash, bevor die Retry-Karte erscheint.
    @ViewBuilder
    private func wrongScreenFlash() -> some View {
        TimelineView(.animation) { context in
            let intensity = wrongFeedbackIntensity(at: context.date)
            if intensity > 0 {
                AppTheme.Colors.elumiErrorRed
                    .opacity(0.35 * intensity)
                    .ignoresSafeArea()
            }
        }
    }

    private func wrongFeedbackIntensity(at date: Date) -> Double {
        guard let ts = game.lastWrongFeedbackAt else { return 0 }
        let age = date.timeIntervalSince(ts)
        let duration = WordRunnerGame.Tuning.wrongFeedbackDuration
        guard age >= 0, age < duration else { return 0 }
        // Stark am Anfang (Impact), schnell ausfadend.
        return max(0, pow(1 - age / duration, 2))
    }

    @ViewBuilder
    private func promptCard(
        prompt: String,
        context: String?,
        colorTheme: WordRunnerColorTheme
    ) -> some View {
        // **Phase 7.4 Prompt-Style**:
        // - kleiner + näher an den Schildern (Font 21 → 18)
        // - keine schwere Box, nur ein **subtiler** Hintergrund mit
        //   der Farbwelt der aktuellen Aufgabe
        // - Akzent-Unterstrich in der Theme-Farbe, dünn → Tie-in zu
        //   den Schildern unten, aber nicht dominant
        //
        // Lesbarkeit: weißer Text auf einem dunklen, halb-transparenten
        // Hintergrund (kein komplett transparenter Prompt — der würde
        // über Fischschwärmen / Korallen unleserlich werden).
        VStack(spacing: 2) {
            Text(prompt)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 1, x: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let context {
                Text(context)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            ZStack {
                // Sehr dezenter Hintergrund: dunkle Panel-Basis mit
                // einem kleinen Akzent der Farbwelt (Tint). Nicht die
                // volle Themenfarbe als Fill — das wäre zu laut und
                // würde mit den Schildern unten konkurrieren.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: colorTheme.primaryHex).opacity(0.15))
                    )
                // Dünner Theme-Unterstrich — visueller Tie-in zu den
                // Schildern, ohne die Card schwer zu machen.
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color(hex: colorTheme.primaryHex).opacity(0.85))
                        .frame(height: 2)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
    }

    // MARK: - State Overlays

    @ViewBuilder
    private func stateOverlay(size: CGSize) -> some View {
        switch game.runState {
        case .idle:
            idleStartScreen
                // **Exit-Transition** (Motion-Spec): Start-Screen fadet
                // + scaled **leicht nach oben** (1.02) raus, sodass der
                // Übergang ins Spiel wie ein „Sprung nach vorn" wirkt
                // — kein harter Cut, kein Bounce. Das Game-World-Layer
                // darunter ist sofort sichtbar.
                .transition(
                    .asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    )
                )

        case .running, .gameOver:
            EmptyView()

        case .summary:
            summaryOverlay
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    /// **Start-Screen** (Phase 7.5 — Start-Flow-Unification +
    /// Layout-Nach-Fix).
    ///
    /// Struktur analog Elumi:
    ///   1. Icon
    ///   2. Name
    ///   3. Große Card: „Ausgewählte Liste" + Dropdown
    ///   4. CTA „Spiel starten"
    ///
    /// Keine Subline, keine Info-Pill — reduziertes Layout, so wie
    /// im User-Spec.
    /// Start-CTA nur aktiv, wenn beide Bedingungen erfüllt:
    ///   • mindestens 1 Spiel übrig (`arcadeCredits >= gamesCost`)
    ///   • brauchbare Liste ausgewählt (`hasUsableList`)
    /// User-Spec Phase 7.5: „CTA nur aktiv, wenn: mindestens 1 Spiel
    /// vorhanden, eine Liste ausgewählt ist".
    private var canStart: Bool {
        hasUsableList && arcadeCredits >= ArcadeCreditSystem.gamesCost
    }

    private var startHintText: String? {
        if !hasUsableList {
            return "Wähle erst eine Liste mit Nomen."
        }
        if arcadeCredits < ArcadeCreditSystem.gamesCost {
            return "Keine Spiele übrig — verdiene welche durchs Lernen."
        }
        return nil
    }

    @ViewBuilder
    private var idleStartScreen: some View {
        GameStartScreen(
            title: "Word Runner",
            subline: nil,
            infoLine: nil,
            primaryCTALabel: "Spiel starten",
            primaryCTAIcon: "play.fill",
            primaryCTAEnabled: canStart,
            hint: startHintText,
            onPrimaryCTA: { startRun() },
            onBack: {
                if let handler = onGoToLists, !hasUsableList {
                    handler()
                } else {
                    dismissEnvironment()
                }
            },
            icon: { wordRunnerStartIcon },
            extraContent: {
                // **Reihenfolge laut User-Spec** (verbindlich):
                //   C. Credit Card (Spiele-Count + „1 Runde kostet …"
                //      + Leben-Row)
                //   E. Listen-Dropdown (Tap öffnet Sheet)
                //   F. Spielregeln (ausklappbar)
                // D ist der Spielname — der wird von GameStartScreen
                // als Titel gerendert.
                VStack(spacing: 14) {
                    wordRunnerSpieleCard
                    listSelectionCard
                    wordRunnerRulesDisclosure
                }
            }
        )
        .onAppear {
            // **Phase 7.6 + Stufe 5 Schritt 2 (2026-04-30)**: WR-Listen-
            // Recall jetzt mit globalem Modus-Routing über den Resolver-
            // Helper. Bei Toggle ON wird die ERSTE UUID aus der globalen
            // Auswahl genommen (WR ist Single-Pick — die globale Multi-
            // Set-Auswahl wird auf eine Liste kollabiert). Bei OFF gilt
            // der bisherige WR-spezifische `wordRunnerLastListIDRaw` —
            // damit eine WR-spezifische Auswahl Module-Wechsel überlebt.
            let effective = VocabularyListSelectionResolver.effectiveSelectedListIDs {
                guard let savedID = UUID(uuidString: wordRunnerLastListIDRaw) else {
                    return []
                }
                return [savedID]
            }
            if let store = listStoreRef.backing,
               let candidate = effective.first,
               store.selectedListID != candidate,
               store.allLists.contains(where: { $0.id == candidate })
                || store.builtInList.id == candidate {
                store.selectedListID = candidate
            }
            recomputeHasUsableList()
            // Phase 7.6 — Audio-Preload, damit `startNewRun` sofort
            // Musik hat statt Decoder-Anlauf. Analog Elumi.
            WordRunnerMusicPlayer.shared.preloadNextTrack()
        }
        .onChange(of: listStoreRef.backing?.selectedListID) { _, newID in
            recomputeHasUsableList()
            game.refreshLiveContent()
            // **Stufe 5 Schritt 2 (2026-04-30)**: Persistenz routet
            // jetzt über den Resolver. Bei Toggle ON wird die globale
            // Auswahl auf `[newID]` kollabiert — alle anderen Module
            // sehen jetzt nur diese eine Liste. Bei OFF wird wie zuvor
            // in den WR-spezifischen Key geschrieben (damit eine
            // dedizierte WR-Auswahl Module-Wechsel übersteht).
            guard let newID else { return }
            VocabularyListSelectionResolver.persistSelectedListIDs([newID]) { _ in
                wordRunnerLastListIDRaw = newID.uuidString
            }
        }
    }

    /// **Word-Runner-Spiele-Card** (Phase 7.5 — Start-Screen-Final).
    /// **Exakt** dasselbe Card-Design wie Elumis `startCreditHeroCard`:
    /// gleiche Struktur, gleiche Abstände, gleiche Farben, gleiche
    /// Leben-Row. Einzige Abweichung: Gamecontroller-Icon statt
    /// Hexagon, „Spiele"-Label, 3 Mini-Icons statt 4. Alles andere
    /// 1:1 übernommen — kein zweites System.
    @ViewBuilder
    private var wordRunnerSpieleCard: some View {
        let hasCredits = arcadeCredits >= ArcadeCreditSystem.gamesCost
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(hasCredits ? AppTheme.Colors.cta : AppTheme.Colors.textSecondary)

                Text("\(arcadeCredits)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()

                Text(arcadeCredits == 1 ? "Spiel" : "Spiele")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(hasCredits
                    ? "1 Runde kostet \(ArcadeCreditSystem.gamesCost) Spiel"
                    : "Lernen bringt Spiele — dann spielen")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            // Leben-Row (analog Elumi) — Mini-Charaktere + Label.
            HStack(spacing: 8) {
                Text("\(WordRunnerGame.startingLives) Leben")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                HStack(spacing: 3) {
                    ForEach(0..<WordRunnerGame.startingLives, id: \.self) { _ in
                        Image("SplashCharacter")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    (hasCredits ? AppTheme.Colors.cta : AppTheme.Colors.border).opacity(hasCredits ? 0.35 : 1),
                    lineWidth: 1
                )
        )
    }

    /// **Spielregeln-Dropdown** (analog Elumi `startRulesDisclosure`).
    /// Tap auf den Header klappt die 4 Kernregeln ein/aus. Bewusst
    /// kurz gehalten — keine langen Erklärungen, nur die 4 Punkte
    /// aus der User-Spec.
    @ViewBuilder
    private var wordRunnerRulesDisclosure: some View {
        VStack(spacing: 10) {
            Button {
                // Phase 7.6 — systemweite State-Animation.
                withAnimation(AppMotion.state) {
                    isShowingRules.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isShowingRules ? "Spielregeln ausblenden" : "Spielregeln anzeigen")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Image(systemName: isShowingRules ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)

            if isShowingRules {
                VStack(alignment: .leading, spacing: 8) {
                    ruleRow("Wähle die richtige Spur")
                    ruleRow("Weiche Hindernissen aus")
                    ruleRow("Tap springt über niedrige Hindernisse")
                    ruleRow("Vertikal draggen steuert das Tempo")
                    ruleRow("Ein Fehler kostet ein Leben")
                    ruleRow("1 Runde kostet 1 Spiel")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.Colors.secondarySurface.opacity(0.55))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func ruleRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.Colors.elumiPink)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    /// **Listen-Auswahl-Card** (Phase 7.5 — Sheet-basiert).
    /// Tap öffnet die dedizierte `WordRunnerListPickerSheet` mit
    /// „Fertig"-Button (User-Spec). Der Card-Look bleibt identisch
    /// zu Elumis Credit-Card-Pattern.
    @ViewBuilder
    private var listSelectionCard: some View {
        if let store = listStoreRef.backing {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.elumiPink)
                    Text("Ausgewählte Liste")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }

                Button {
                    isShowingListPicker = true
                } label: {
                    HStack(spacing: 10) {
                        // **Phase 7.6 Bug-Fix** — Listen-Name wird
                        // **immer** angezeigt, sobald eine Liste
                        // gewählt ist. Der alte Ternär zeigte bei
                        // `hasUsableList == false` (Liste ohne Nomen)
                        // fälschlich „Bitte Liste auswählen", obwohl
                        // der User schon eine Liste gewählt hatte.
                        // Die Warnung „zu wenige Nomen" lebt jetzt
                        // **unter** dem CTA als Hint (siehe
                        // `startHintText`).
                        Text(currentListName(store: store))
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        (hasUsableList
                            ? AppTheme.Colors.elumiPink
                            : AppTheme.Colors.border
                        ).opacity(hasUsableList ? 0.35 : 1),
                        lineWidth: 1
                    )
            )
        }
    }

    /// Spiel-Icon für den WR-Start-Screen: Lauf-Glyph im pinken Kreis.
    private var wordRunnerStartIcon: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.elumiPink.opacity(0.22))
            Image(systemName: "figure.run")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(AppTheme.Colors.elumiPink)
        }
    }

    /// Alle für den Picker relevanten Listen — jetzt identisch zur
    /// `store.allLists`-Quelle, die auch die ListPickerSheet nutzt.
    /// So findet `currentListName` auch Niveau-/Thema-Listen, wenn
    /// der User solche auswählt (vorher fehlten sie und der Card
    /// zeigte generisches „Liste" statt des konkreten Namens).
    private func availableLists(store: VocabularyListStore) -> [VocabularyList] {
        store.allLists
    }

    private func currentListName(store: VocabularyListStore) -> String {
        // **Phase 7.6 Bug-Fix** — User-Report „Liste wird ausgewählt,
        // aber nur `Liste` wird angezeigt". Wir durchsuchen jetzt
        // `store.allLists` **plus** `builtInList` (falls die Selection
        // darauf zeigt und `allLists` sie nicht inkludiert).
        if store.builtInList.id == store.selectedListID {
            return store.builtInList.name
        }
        return store.allLists.first(where: { $0.id == store.selectedListID })?.name
            ?? "Liste"
    }

    private func recomputeHasUsableList() {
        hasUsableList = LiveListRunnerTaskProvider.hasUsableContent(in: listStoreRef.backing)
    }

    /// **Summary-Overlay** (Phase 7.5 — Ende-Flow-Unification).
    ///
    /// Nutzt jetzt die shared `GameSummaryView`-Komponente — identisch
    /// zur Elumi-Arcade-Summary. Spielspezifische Daten:
    ///   - Hero = gesammelte XP aus `SessionRewardOutcome.totalXP`
    ///   - Stats = Richtig / Fehler / Combo / Score
    ///   - Primär-CTA „Noch eine Runde" → `startRun()`
    ///   - Sekundär-CTA „Zur Startseite" → Music-Fadeout + `onClose()`
    ///
    /// Das alte `gameOverScreen`-Zwischen-Overlay + die Nutzung des
    /// geteilten `SessionSummaryView` sind bewusst entfallen — beide
    /// Spiele (Elumi + WR) zeigen jetzt exakt denselben End-Screen.
    @ViewBuilder
    private var summaryOverlay: some View {
        let outcome = game.pendingOutcome ?? .empty
        let correct = game.correctAnswers
        let wrong = game.wrongAnswers
        let combo = game.longestCombo
        let score = game.score
        let headline = wordRunnerHeadline(correct: correct, wrong: wrong)

        GameSummaryView(
            headline: headline,
            subtitle: nil,
            badge: nil,
            heroValue: "+\(outcome.totalXP)",
            heroValueLabel: "XP",
            heroValueColor: AppTheme.Colors.cta,
            stats: [
                .init(title: "Richtig", value: "\(correct)"),
                .init(title: "Fehler",  value: "\(wrong)"),
                .init(title: "Combo",   value: "\(combo)"),
                .init(title: "Score",   value: "\(score)")
            ],
            primaryCTALabel: "Noch eine Runde",
            primaryCTAIcon: "arrow.clockwise",
            onPrimaryCTA: { startRun() },
            secondaryCTALabel: "Zur Startseite",
            onSecondaryCTA: {
                music.fadeOut(over: 0.3)
                game.stop()
                onClose()
            },
            icon: {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.elumiPink.opacity(0.18))
                    Image(systemName: "figure.run")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(AppTheme.Colors.elumiPink)
                }
            }
        )
    }

    /// Kurzer Headline-Picker nach Quote. Bleibt freundlich auch bei
    /// Nullrunden.
    private func wordRunnerHeadline(correct: Int, wrong: Int) -> String {
        let total = correct + wrong
        guard total > 0 else { return "Weiter geht's!" }
        let ratio = Double(correct) / Double(total)
        switch ratio {
        case 0.85...: return "Stark!"
        case 0.6...:  return "Gut gemacht!"
        case 0.3...:  return "Auf gutem Weg"
        default:      return "Weiter üben!"
        }
    }

    // MARK: - Input

    private func startRun() {
        // Start-Gate (User-Spec Phase 7.5):
        //   1. Spiele > 0 (Credits vorhanden)
        //   2. Liste ausgewählt + brauchbar
        // Wenn eine Bedingung nicht erfüllt ist: KEIN Abzug, KEIN Start.
        guard canStart else { return }

        // Credit-Abzug **vor** dem Run-Start — konsistent mit Elumi
        // (dort zieht der Start-CTA auch direkt ab).
        arcadeCredits -= ArcadeCreditSystem.gamesCost

        // Runden-State zurücksetzen, damit das Badge beim ersten
        // Übergang zu Runde 2 korrekt triggert.
        displayedRound = 1
        roundBadgeShownAt = nil

        // Footer ausblenden, sobald das Gameplay läuft.
        setImmersiveArcade?(true)
        // Motion-Spec: Transition idle → running mit 0.20 s Ease-Out.
        // Das Start-Overlay fadet + scaled leicht (.transition oben),
        // der Game-Layer darunter wird instant sichtbar.
        withAnimation(.easeOut(duration: 0.2)) {
            game.start()
        }
        // Musik leicht verzögert starten (User-Motion-Spec: „Musik
        // beginnt ~100–150 ms nach Tap, kein abruptes Starten vor der
        // visuellen Bewegung").
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(130))
            music.startNewRun()
        }
    }
}

// MARK: - ElumiVehicleView (Phase 6.4 — Hard Reset)

/// **Heck-Ansicht eines kleinen U-Boots.** Kein SplashCharacter mehr,
/// kein frontales Mascot. Ein geometrisches Fahrzeug, das man
/// **eindeutig von hinten** sieht — breitformatiger Rumpf, kleine
/// Sail (Aufbau) mit Rück-Fenster obendrauf, zwei Heck-Flossen, zwei
/// Jet-Düsen. Elumi ist maximal als dunkle **Silhouette im Rück-
/// fenster** angedeutet — nicht der Hauptfokus.
///
/// Shapes (hinten → vorn):
///   1. Boden-Schatten (unscharfer Oval darunter)
///   2. Heck-Flossen links + rechts (Stabilisatoren, nach außen
///      gekippt — typische Rear-View-Silhouette)
///   3. Rumpf: **horizontale Ellipse** (breiter als hoch), Ton:
///      Navy + Cyan-Kante. Das Breitformat liest sich als „Fahrzeug
///      von hinten".
///   4. Sail/Aufbau: kleinere Rounded-Rect auf Top-Mitte mit
///      dunklem **Rück-Fenster**. Drin: ein kleines ovales Dark-
///      Light-Detail als Hint „jemand sitzt da drin und schaut
///      nach vorne".
///   5. Zwei Jet-Düsen am Heck unten mit Cyan-Puls-Glow.
///   6. Schräg-Highlight oben auf dem Rumpf (Licht von oben/schräg).
///   7. **Wake-Bubbles**: drei kleine Blasen strömen nach hinten
///      unten, machen die Bewegungsrichtung physisch lesbar.
///
/// Lean: der ganze Vehicle-ZStack kippt beim Lane-Switch um ±6° —
/// nicht nur der Sprite (den gibt's ja nicht mehr), sondern das
/// gesamte Fahrzeug bankt in die Kurve.
private struct ElumiVehicleView: View {
    let lean: Double
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bob = CGFloat(sin(t * 2.5)) * 2
            let jetPulse = 0.65 + 0.35 * (0.5 + 0.5 * CGFloat(sin(t * 7)))

            ZStack {
                // 1) Boden-Schatten
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: size * 1.5, height: size * 0.3)
                    .offset(y: size * 0.55)
                    .blur(radius: 8)
                    .allowsHitTesting(false)

                // 7) Wake-Bubbles (noch HINTER dem Fahrzeug zeichnen)
                wakeBubbles(time: t)

                // 2) Heck-Flossen
                heckFin(side: -1)
                heckFin(side: 1)

                // 3) Hauptrumpf — horizontale Ellipse (breiter als hoch).
                //    Gradient schwerer Mitte zu kühlem Rand.
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.elumiBlue.opacity(0.95),
                                AppTheme.Colors.elumiNavy,
                                AppTheme.Colors.elumiMidnight
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 1.5, height: size * 0.82)
                    .overlay(
                        Ellipse()
                            .stroke(AppTheme.Colors.elumiBlue.opacity(0.75), lineWidth: 1.8)
                    )
                    .shadow(color: AppTheme.Colors.elumiBlue.opacity(0.35), radius: 12, x: 0, y: 5)

                // 4) Sail/Aufbau — kleine rounded Rect mit Fenster.
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.Colors.elumiNavy,
                                    AppTheme.Colors.elumiMidnight
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(AppTheme.Colors.elumiBlue.opacity(0.75), lineWidth: 1.4)
                        )

                    // Rück-Fenster — kleine dunkle Rounded Rect, drin
                    // eine gedimmte Silhouette-Andeutung.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppTheme.Colors.elumiMidnight.opacity(0.9))
                        .overlay(
                            // „Elumi sitzt da drin" — ein kleines ovales
                            // Highlight als Kopf-/Rückenkontur, leicht
                            // Cyan getönt. Kein Gesicht, keine Augen.
                            Ellipse()
                                .fill(AppTheme.Colors.elumiBlue.opacity(0.55))
                                .frame(width: size * 0.15, height: size * 0.12)
                                .offset(y: size * 0.01)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(AppTheme.Colors.elumiBlue.opacity(0.6), lineWidth: 0.8)
                        )
                        .frame(width: size * 0.34, height: size * 0.22)
                }
                .frame(width: size * 0.46, height: size * 0.38)
                .offset(y: -size * 0.36)

                // 5) Jets — unten links + rechts am Heck.
                jetExhaust(xOffset: -size * 0.42, pulse: jetPulse)
                jetExhaust(xOffset: size * 0.42, pulse: jetPulse)

                // 6) Oberes schrägseitiges Highlight — Licht von
                //    links-oben, macht das Fahrzeug „solid".
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.40),
                                Color.white.opacity(0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.9, height: size * 0.22)
                    .offset(x: -size * 0.12, y: -size * 0.18)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .offset(y: bob)
            // Lane-Switch-Lean: ganzes Fahrzeug bankt (nicht nur
            // Sprite). Fühlt sich wie eine echte Kurve an.
            .rotationEffect(.degrees(lean))
        }
        .frame(width: size * 1.6, height: size * 1.35)
    }

    @ViewBuilder
    private func heckFin(side: CGFloat) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.Colors.elumiNavy,
                        AppTheme.Colors.elumiMidnight
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Ellipse().stroke(AppTheme.Colors.elumiBlue.opacity(0.6), lineWidth: 1)
            )
            .frame(width: size * 0.32, height: size * 0.5)
            .rotationEffect(.degrees(Double(side) * 18))
            .offset(x: side * size * 0.7, y: size * 0.08)
    }

    @ViewBuilder
    private func jetExhaust(xOffset: CGFloat, pulse: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.Colors.elumiBlue.opacity(0.8 * pulse),
                            AppTheme.Colors.elumiBlue.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.16 * pulse
                    )
                )
                .frame(width: size * 0.36, height: size * 0.36)
            Ellipse()
                .fill(AppTheme.Colors.elumiMidnight)
                .overlay(
                    Ellipse().stroke(AppTheme.Colors.elumiBlue.opacity(0.95), lineWidth: 1.2)
                )
                .frame(width: size * 0.16, height: size * 0.12)
        }
        .offset(x: xOffset, y: size * 0.35)
        .blendMode(.plusLighter)
    }

    @ViewBuilder
    private func wakeBubbles(time t: TimeInterval) -> some View {
        // Drei ausströmende Blasen nach hinten unten — separate
        // Phasen, schneller als Hintergrund-Bubbles.
        Canvas { ctx, _ in
            for i in 0..<3 {
                let phase = t.truncatingRemainder(dividingBy: 0.9) + Double(i) * 0.3
                let cycle = phase.truncatingRemainder(dividingBy: 0.9) / 0.9
                let xOffset = (i == 1 ? 0 : (i == 0 ? -1 : 1)) * size * 0.18
                let y = size * 0.4 + CGFloat(cycle) * size * 0.5
                let bubbleSize: CGFloat = 4 - CGFloat(cycle) * 3
                guard bubbleSize > 0.5 else { continue }
                let alpha = 0.5 * (1.0 - cycle)
                let rect = CGRect(
                    x: CGFloat(xOffset) - bubbleSize / 2,
                    y: y - bubbleSize / 2,
                    width: bubbleSize,
                    height: bubbleSize
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(AppTheme.Colors.elumiBlue.opacity(alpha)))
            }
        }
        .frame(width: size * 0.8, height: size * 1.0)
        .offset(y: size * 0.1)
        .blendMode(.plusLighter)
    }
}

// MARK: - Shield-Aura (Power-Up-Visual am Player)

/// Pulsierender Cyan-Ring um das Vehicle, sichtbar solange
/// `shieldCharges > 0`. Ein Ring pro Charge — bei mehreren
/// Schilden wachsen die Ringe nach außen.
private struct ShieldAuraView: View {
    let charges: Int
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 0.7 + 0.3 * (0.5 + 0.5 * sin(t * 3.5))

            ZStack {
                ForEach(0..<charges, id: \.self) { idx in
                    Circle()
                        .stroke(
                            Color(hex: "#5BD9FF").opacity(0.65 * pulse),
                            lineWidth: 2.5
                        )
                        .frame(
                            width: size * (1.6 + CGFloat(idx) * 0.18),
                            height: size * (1.6 + CGFloat(idx) * 0.18)
                        )
                        .blur(radius: 0.5)
                }
                // Innerer weicher Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#5BD9FF").opacity(0.18 * pulse),
                                Color(hex: "#5BD9FF").opacity(0)
                            ],
                            center: .center,
                            startRadius: size * 0.3,
                            endRadius: size * 0.85
                        )
                    )
                    .frame(width: size * 1.7, height: size * 1.7)
                    .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - FishSwimAcrossView (Ambient-Event)

/// Eine Fisch-Silhouette, die einmal quer über den Bildschirm zieht.
/// 8 s Lebensdauer, weiche Sinus-Y-Bewegung, fadet am Anfang ein
/// und am Ende aus. Reine Geometrie, keine Asset-Abhängigkeit:
/// Body als horizontale Ellipse, Schwanz als Dreieck-Path.
private struct FishSwimAcrossView: View {
    let startedAt: Date
    let screenSize: CGSize

    private let totalDuration: TimeInterval = 8.0
    private let bodyWidth: CGFloat = 120
    private let bodyHeight: CGFloat = 50

    var body: some View {
        TimelineView(.animation) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startedAt)
            // Aus dem Run, wenn Lebensdauer überschritten.
            if elapsed < 0 || elapsed > totalDuration {
                Color.clear
            } else {
                let progress = CGFloat(elapsed / totalDuration)
                // X: von links außerhalb (-bodyWidth) nach rechts
                // außerhalb (screenWidth + bodyWidth).
                let x = -bodyWidth + (screenSize.width + bodyWidth * 2) * progress
                // Y: ungefähre Mitte mit dezentem Sin-Wave.
                let baseY = screenSize.height * 0.45
                let waveY = sin(elapsed * 1.4) * 24
                let y = baseY + CGFloat(waveY)
                // Fade-In erste 0.6 s, Fade-Out letzte 0.8 s.
                let fade: Double = {
                    if elapsed < 0.6 { return elapsed / 0.6 }
                    if elapsed > totalDuration - 0.8 {
                        return max(0, (totalDuration - elapsed) / 0.8)
                    }
                    return 1.0
                }()
                FishSilhouette(width: bodyWidth, height: bodyHeight)
                    .opacity(fade * 0.55)
                    .position(x: x, y: y)
            }
        }
    }
}

private struct FishSilhouette: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            // Body: horizontale Ellipse mit dunklem Gradient
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.elumiBlue.opacity(0.85),
                            AppTheme.Colors.elumiMidnight
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.78, height: height)
                .offset(x: width * 0.10)

            // Schwanz: Dreieck links
            Path { path in
                path.move(to: CGPoint(x: 0, y: height * 0.2))
                path.addLine(to: CGPoint(x: width * 0.28, y: height * 0.5))
                path.addLine(to: CGPoint(x: 0, y: height * 0.8))
                path.closeSubpath()
            }
            .fill(AppTheme.Colors.elumiMidnight)
            .frame(width: width * 0.3, height: height)
            .offset(x: -width * 0.34)

            // Auge — kleiner heller Punkt vorne rechts
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5, height: 5)
                .offset(x: width * 0.32, y: -height * 0.08)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Ambient-Fisch-Silhouette (Phase 7.4)

/// Kleine flach stilisierte Fisch-Silhouette für den **Schwarm**-
/// Ambient-Layer. Bewusst **kein** Schatten und weniger Details als
/// `FishSilhouette` (der große Event-Fisch) — hier geht es um eine
/// Masse kleiner Silhouetten, nicht um Einzel-Präsenz.
///
/// `facingRight: false` spiegelt die Form horizontal. Damit kann der
/// gleiche Asset-Code beide Schwimm-Richtungen.
private struct AmbientFishSilhouette: View {
    let facingRight: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Körper
                Ellipse()
                    .fill(Color(hex: "#2A4768").opacity(0.9))
                    .frame(width: w * 0.74, height: h)
                    .offset(x: facingRight ? w * 0.1 : -w * 0.1)

                // Schwanz (Dreieck)
                Path { path in
                    if facingRight {
                        path.move(to: CGPoint(x: 0, y: h * 0.2))
                        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.5))
                        path.addLine(to: CGPoint(x: 0, y: h * 0.8))
                    } else {
                        path.move(to: CGPoint(x: w, y: h * 0.2))
                        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.5))
                        path.addLine(to: CGPoint(x: w, y: h * 0.8))
                    }
                    path.closeSubpath()
                }
                .fill(Color(hex: "#1A2F4A").opacity(0.9))
            }
        }
    }
}

// MARK: - Jellyfish-Silhouette (Phase 7.4)

/// Langsam schwebende Qualle: Bell-Kuppel + 4 Tentakeln, leicht
/// pulsierend. Halbtransparent (Alpha wird von außen via `.opacity`
/// skaliert) — die Qualle soll „am Rand des Blicks" sichtbar sein,
/// nicht dominant.
private struct JellyfishSilhouette: View {
    let time: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Bell pulsiert sanft in der Höhe (±6 %)
            let pulse = 1.0 + 0.06 * sin(time * 1.2)
            let bellH = h * 0.42 * pulse
            let bellW = w * 0.95

            ZStack {
                // Glow-Halo
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#B9CEFF").opacity(0.35),
                                Color(hex: "#B9CEFF").opacity(0)
                            ],
                            center: UnitPoint(x: 0.5, y: 0.3),
                            startRadius: 4,
                            endRadius: w * 0.55
                        )
                    )
                    .blendMode(.plusLighter)
                    .frame(width: w * 1.1, height: h * 0.55)
                    .offset(y: h * -0.18)

                // Bell (Kuppel) — Halbellipse via Clip
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#D8E5FF").opacity(0.75),
                                Color(hex: "#98B5EA").opacity(0.55),
                                Color(hex: "#567AAE").opacity(0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: bellW, height: bellH)
                    .offset(y: -h * 0.25)

                // Bell-Glanz-Spot
                Ellipse()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: bellW * 0.25, height: bellH * 0.25)
                    .offset(x: -bellW * 0.15, y: -h * 0.30)
                    .blendMode(.plusLighter)

                // Tentakel — 4 Linien mit Sinus-Bewegung
                ForEach(0..<4, id: \.self) { i in
                    let xBase = (CGFloat(i) - 1.5) * w * 0.16
                    let phase = time * 1.1 + Double(i)
                    JellyfishTentacle(
                        time: time,
                        phase: phase,
                        length: h * 0.6,
                        xBase: xBase
                    )
                }
            }
        }
    }
}

/// Einzelnes Tentakel-Segment. Sinuslinie mit langsamer Welle,
/// verblassend nach unten.
private struct JellyfishTentacle: View {
    let time: TimeInterval
    let phase: Double
    let length: CGFloat
    let xBase: CGFloat

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            Path { path in
                let startY = h * 0.22
                let segments = 14
                let segLen = length / CGFloat(segments)
                var currentX = geo.size.width / 2 + xBase
                var currentY = startY
                path.move(to: CGPoint(x: currentX, y: currentY))
                for seg in 1...segments {
                    let wave = sin(phase + Double(seg) * 0.65) * 3.0
                    currentX += CGFloat(wave) * 0.3
                    currentY += segLen
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(hex: "#B9CEFF").opacity(0.65),
                        Color(hex: "#B9CEFF").opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }
}

// MARK: - Rock-Obstacle — Phase 7.4 Visual Upgrade

/// **Felsen-Hindernis** mit 5 Shape-Varianten (Phase 7.4):
///
///   0. **Runder Klumpen** — sanft ovale Silhouette, klassisch.
///   1. **Flacher Stein** — breiter als hoch, gedrungener Look.
///   2. **Spitz/Kantig** — ein schräg aufsteigender Brocken mit
///      deutlicher Oberkante.
///   3. **Gespalten** — zwei benachbarte Kuppen, wie zwei Steine
///      nebeneinander.
///   4. **Mit Algen-Tuft** — runder Klumpen + grüne Algensträhne
///      auf der Oberseite.
///
/// Alle Varianten teilen:
///   - Boden-Schatten (weich, breit)
///   - **Hellere Oberseite, dunklere Unterseite** → Lichtquelle von oben
///   - Feiner Umriss-Stroke für Kontur-Lesbarkeit
///   - Highlight oben-links (Plus-Lighter-Blend)
/// **Baustellen-Schild** (Phase 7.6) — visuelle Variante zum STOP-
/// Schild. Orangefarbenes Warn-Dreieck (Verkehrs-Semantik: Warnung)
/// mit SF-Symbol mittig. Gameplay identisch: fatal bei Kollision,
/// aber via Jump überspringbar (siehe `WordRunnerObstacle.isJumpable`).
private struct ConstructionObstacleView: View {
    let size: CGSize

    /// Warn-Dreieck-Pfad (oben spitz, unten breit) — klassisches
    /// Verkehrs-Gefahrenzeichen.
    private struct TriangleShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    var body: some View {
        ZStack {
            TriangleShape()
                .fill(Color(red: 0.98, green: 0.60, blue: 0.08))
            TriangleShape()
                .stroke(Color.white, lineWidth: 1.8)
                .padding(2)
            // SF-Symbol als Warn-Marke. `cone.fill` liest sich sofort
            // als „Baustelle" — Farbe bewusst dunkel, damit der Kontrast
            // zum orangen Grund hoch bleibt.
            Image(systemName: "cone.fill")
                .font(.system(size: size.height * 0.42, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))
                .offset(y: size.height * 0.08)
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
        }
        .frame(width: size.width, height: size.height)
    }
}

///
/// Varianten-Auswahl kommt aus `WordRunnerObstacle.Kind.rock(variant:)`.
/// Modulo gegen die View-Anzahl schützt gegen out-of-range-Indizes,
/// sollte der Spawner mehr liefern als die View kennt.
private struct RockObstacleView: View {
    let size: CGSize
    let variant: Int

    // MARK: - Shape-Geometrie

    /// Normierter Shape-Pfad (in 1×1-Unit-Box). Wird von der View
    /// auf `frame(width:height:)` skaliert.
    private struct RockShape: Shape {
        let variantIndex: Int

        func path(in rect: CGRect) -> Path {
            let w = rect.width
            let h = rect.height
            var p = Path()
            switch variantIndex % 5 {
            case 0:
                // Runder Klumpen (etwas verzerrte Ellipse).
                p.addEllipse(in: CGRect(x: w * 0.04, y: h * 0.06, width: w * 0.92, height: h * 0.88))

            case 1:
                // Flacher Stein — gedrungen.
                p.addEllipse(in: CGRect(x: 0, y: h * 0.30, width: w, height: h * 0.68))

            case 2:
                // Spitz/Kantig — asymmetrisch, nach oben-rechts spitz.
                p.move(to: CGPoint(x: w * 0.08, y: h * 0.95))
                p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.40))
                p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.12))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.95))
                p.closeSubpath()

            case 3:
                // Gespalten — zwei Kuppen.
                p.addEllipse(in: CGRect(x: 0, y: h * 0.18, width: w * 0.58, height: h * 0.80))
                p.addEllipse(in: CGRect(x: w * 0.46, y: h * 0.32, width: w * 0.54, height: h * 0.66))

            default:
                // Basis-Ellipse für Variante 4 — Algen kommen als
                // Overlay in der View.
                p.addEllipse(in: CGRect(x: w * 0.04, y: h * 0.14, width: w * 0.92, height: h * 0.84))
            }
            return p
        }
    }

    var body: some View {
        ZStack {
            // Boden-Schatten — weicher, breiter als die Shape selbst,
            // damit der Rock spürbar auf dem Boden liegt.
            Ellipse()
                .fill(Color.black.opacity(0.42))
                .frame(width: size.width * 1.05, height: size.height * 0.22)
                .offset(y: size.height * 0.44)
                .blur(radius: 3.5)

            // Hauptkörper: Gradient von oben (heller) nach unten (dunkler).
            RockShape(variantIndex: variant)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#7A7F8A"),   // hellere Oberseite
                            Color(hex: "#4D5158"),   // mittlerer Ton
                            Color(hex: "#23262C")    // dunkle Unterseite
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Feine Konturlinie — verhindert, dass der Rock im
            // dunklen Untergrund verschwimmt.
            RockShape(variantIndex: variant)
                .stroke(Color(hex: "#8A8F9A").opacity(0.5), lineWidth: 0.9)

            // Highlight-Fleck oben-links — simuliert die von oben
            // kommende Lichtquelle.
            RockShape(variantIndex: variant)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)

            // **Variante 4 — Algen-Tuft** als Overlay oben.
            // Drei kleine grüne „Blätter" in unterschiedlicher Neigung,
            // damit's nicht symmetrisch-langweilig wirkt.
            if variant % 5 == 4 {
                algaeTuft
                    .frame(width: size.width * 0.42, height: size.height * 0.42)
                    .offset(x: -size.width * 0.05, y: -size.height * 0.35)
            }

            // **Variante 0 — kleine Muschel** als Oberflächen-Detail
            // (bei Basic-Rock), damit die Variante nicht zu nackt wirkt.
            if variant % 5 == 0 {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#F5D9C0"), Color(hex: "#B08C6A")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size.width * 0.12, height: size.width * 0.12)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .offset(x: size.width * 0.18, y: size.height * 0.06)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Stilisierte Algen-Strähne — drei gebogene Blätter.
    private var algaeTuft: some View {
        ZStack {
            algaeBlade(angle: -14, height: 0.95, hue: "#5FC27E")
            algaeBlade(angle: 10, height: 1.0, hue: "#3FA05F")
            algaeBlade(angle: 26, height: 0.85, hue: "#59BE76")
        }
    }

    private func algaeBlade(angle: Double, height: CGFloat, hue: String) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(hex: hue).opacity(0.95), Color(hex: hue).opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 4, height: 22 * height)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Collectible-View (Phase 7.4)

/// **Sammelobjekt** — je nach `kind` Seestern, Würmchen oder Perle.
///
/// Gestaltungsregeln (Spec „Sammelobjekt einführen"):
///   - **klar unterscheidbar** von Hindernissen (warme, gesättigte Farben;
///     Rocks sind kühl/dunkel, Signs sind rechteckig)
///   - **visuell attraktiv**, aber nicht dominant (kleiner Size-Faktor
///     gegenüber Rocks/Signs)
///   - leichter Puls + Rotation für „Sparkle"-Gefühl, ohne zu blinken
private struct CollectibleView: View {
    let kind: WordRunnerCollectible
    let size: CGSize

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2.4)                  // 0…1
            let rotation = Angle.degrees(sin(t * 0.8) * 14)       // ±14°
            ZStack {
                // Weicher Bodenschatten
                Ellipse()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: size.width * 0.65, height: size.height * 0.18)
                    .offset(y: size.height * 0.40)
                    .blur(radius: 2.5)

                // Sanfter Glow-Ring (Theme-neutral warm)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(0.45 + 0.25 * pulse),
                                glowColor.opacity(0)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: size.width * 0.55
                        )
                    )
                    .frame(width: size.width * 1.05, height: size.width * 1.05)
                    .blendMode(.plusLighter)

                shapeBody
                    .rotationEffect(rotation)
                    .scaleEffect(0.92 + 0.08 * pulse)
            }
        }
        .frame(width: size.width * 0.82, height: size.height * 0.82)
    }

    @ViewBuilder
    private var shapeBody: some View {
        switch kind {
        case .starfish:
            StarShape(points: 5, innerRatio: 0.45)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FFC46C"),   // warmes Gelb
                            Color(hex: "#E27A3C")    // warmes Orange
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    StarShape(points: 5, innerRatio: 0.45)
                        .stroke(Color(hex: "#A34A18").opacity(0.55), lineWidth: 1)
                )
                .frame(width: size.width * 0.7, height: size.height * 0.7)
                // Glanz-Spot
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: size.width * 0.14, height: size.width * 0.14)
                        .offset(x: -size.width * 0.10, y: -size.height * 0.12)
                        .blendMode(.plusLighter)
                )

        case .worm:
            // Würmchen: kleine wellenförmige Kapsel, pastellig koral.
            WormShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FF9EA8"),
                            Color(hex: "#C95F6B")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    WormShape()
                        .stroke(Color(hex: "#7E2D3A").opacity(0.35), lineWidth: 0.8)
                )
                .frame(width: size.width * 0.75, height: size.height * 0.48)

        case .pearl:
            // Perle: glänzender Kreis mit Lichtspot.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#F5F9FF"),
                                Color(hex: "#B8C6E4"),
                                Color(hex: "#7B8BBD")
                            ],
                            center: UnitPoint(x: 0.38, y: 0.32),
                            startRadius: 1,
                            endRadius: size.width * 0.5
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.6)
                    )
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: size.width * 0.14, height: size.width * 0.14)
                    .offset(x: -size.width * 0.12, y: -size.height * 0.14)
                    .blendMode(.plusLighter)
            }
            .frame(width: size.width * 0.58, height: size.width * 0.58)
        }
    }

    private var glowColor: Color {
        switch kind {
        case .starfish: return Color(hex: "#FFC46C")
        case .worm:     return Color(hex: "#FFA3AD")
        case .pearl:    return Color(hex: "#CFD6FF")
        }
    }
}

/// Fünfzackiger Stern für Seestern + Potential-Bonus-Items.
private struct StarShape: Shape {
    let points: Int
    /// Verhältnis Innenradius zu Außenradius. 0.5 = klassischer Stern.
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let totalVertices = points * 2
        let angleStep = 2 * .pi / Double(totalVertices)
        for i in 0..<totalVertices {
            let r = i.isMultiple(of: 2) ? radius : radius * innerRatio
            let angle = -Double.pi / 2 + Double(i) * angleStep
            let x = center.x + r * CGFloat(cos(angle))
            let y = center.y + r * CGFloat(sin(angle))
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        p.closeSubpath()
        return p
    }
}

/// Einfacher Würmchen-Körper — zwei Kugeln mit leichtem Overlap.
private struct WormShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Vorderer Körper
        p.addEllipse(in: CGRect(x: 0, y: h * 0.15, width: w * 0.60, height: h * 0.70))
        // Hinterer Körper — leicht versetzt
        p.addEllipse(in: CGRect(x: w * 0.45, y: h * 0.05, width: w * 0.55, height: h * 0.70))
        return p
    }
}

// MARK: - PowerUp-View (Schild-Pickup)

/// Pickup-Visual für ein Power-Up. Aktuell nur Schild — runde
/// Cyan-Pille mit Schild-Icon und pulsierendem Glow, klar als
/// „Bonus-Item" lesbar (anderer Look als Schilder/Felsen).
private struct PowerUpView: View {
    let kind: WordRunnerPowerUp
    let size: CGSize

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 0.7 + 0.3 * (0.5 + 0.5 * sin(t * 4.5))

            ZStack {
                // Glow-Ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#5BD9FF").opacity(0.7 * pulse),
                                Color(hex: "#5BD9FF").opacity(0)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: size.width * 0.6
                        )
                    )
                    .frame(width: size.width * 1.2, height: size.width * 1.2)
                    .blendMode(.plusLighter)

                // Inner-Pille
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#5BD9FF"),
                                Color(hex: "#1F6F95")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                    )
                    .frame(width: min(size.width, size.height) * 0.85,
                           height: min(size.width, size.height) * 0.85)

                Image(systemName: iconName)
                    .font(.system(size: min(size.width, size.height) * 0.5, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
            }
            .scaleEffect(0.94 + 0.06 * pulse)
        }
    }

    private var iconName: String {
        switch kind {
        case .shield: return "shield.fill"
        case .slowMo: return "hourglass"
        }
    }
}

// MARK: - OctagonShape (echtes Stop-Schild-Format)

/// Achteckige Form für das STOP-Schild. Acht gleichseitige Ecken,
/// gerechnet als Polygon mit 8 Punkten auf einem Kreis. Die erste
/// Kante liegt **horizontal oben** (klassische Stop-Schild-Orientierung,
/// nicht spitz nach oben).
private struct OctagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // Start bei π/8 sorgt für eine waagrechte Oberkante,
        // genau wie beim realen Verkehrszeichen.
        let startAngle: Double = -.pi / 2 + .pi / 8
        for i in 0..<8 {
            let angle = startAngle + Double(i) * .pi / 4
            let x = center.x + radius * CGFloat(cos(angle))
            let y = center.y + radius * CGFloat(sin(angle))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - SignOnPostView — Phase 7.4 Visual Upgrade

/// **Wegweiser/Schild auf Pfosten** mit dünneren Rahmen, sichtbarem
/// Pfosten + Boden-Schatten, 3 Form-Varianten und Farbwelten pro
/// Task (Phase 7.4).
///
/// Gestaltungsregeln (Spec):
///   - **dünnere Rahmen**: Außen-Stroke 1 pt (statt 2.5 pt), Padding
///     inside 1.5 pt — Schilder wirken leichter, weniger UI-klobig
///   - **sichtbarer Pfosten + Halterung**: zusätzlich zum Post-Stab
///     eine kleine Manschette am Übergang Panel ↔ Pfosten
///   - **Materialtiefe**: subtiler Gradient-Stopp in der Mitte,
///     dünner Highlight-Streifen oben, dunklerer Strich unten
///   - **Boden-Schatten**: weicher Elliptic-Shadow unter dem Pfosten
///     → das Schild steht klar „im Raum"
///   - **Farbwelten**: Türkis/Gold/Violett/Koralle — keine Grün/Rot-
///     Semantik, nur per-Task-Abwechslung
///   - **STOP bleibt rot** (Verkehrs-Semantik) — unabhängig vom Theme
///
/// Form-Varianten:
///   - `.classic` — Rechteck mit weichen Ecken (Default)
///   - `.gate`    — Bogen/Portal (Halbkreis-Kappe oben)
///   - `.marker`  — Parallelogramm (schräge Wegweiser-Form)
///
/// Passed-Correct-Marker: **kein Grün** mehr (Spec: „Keine Grün/Rot
/// Logik"). Stattdessen subtiler Gold-Glow-Ring + leichter Scale-Puls.
private struct SignOnPostView: View {
    let label: String
    let isHazard: Bool
    let isPassedCorrect: Bool
    let panelSize: CGSize
    let colorTheme: WordRunnerColorTheme
    let variant: Variant

    enum Variant: Equatable, CaseIterable {
        case classic
        case gate
        case marker
    }

    private let postHeight: CGFloat = 38
    private let postWidth: CGFloat = 8

    var body: some View {
        VStack(spacing: -1) {
            // --- Panel ---
            Group {
                if isHazard {
                    stopOctagon
                } else {
                    optionPanel
                }
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .shadow(
                // Nach Pass zusätzlich grünen Glow-Schatten, damit das
                // grüne Schild auch „leuchtend" weiter fährt, statt
                // nur die Farbe zu wechseln.
                color: isPassedCorrect
                    ? Color(hex: "#3FB870").opacity(0.55)
                    : .black.opacity(0.35),
                radius: isPassedCorrect ? 10 : 5,
                x: 0,
                y: 3
            )

            // --- Pfosten + Halterung ---
            postWithMount

            // --- Boden-Schatten ---
            Ellipse()
                .fill(Color.black.opacity(0.28))
                .frame(width: panelSize.width * 0.60, height: 5)
                .blur(radius: 2.2)
                .offset(y: -1)
        }
    }

    // MARK: - Option-Panel (Wegweiser — Theme-gefärbt)

    private var optionPanel: some View {
        ZStack {
            panelShape
                .fill(outerFill)
            panelShape
                .fill(innerFill)
                .padding(1.5)
            // Subtiler Highlight-Streifen oben — gibt Materialtiefe
            // (Blechkante wirkt leicht beleuchtet). Per View-Padding
            // leicht nach innen gerückt, damit der Stroke innerhalb
            // der Metall-Fill-Linie sitzt statt sie zu überlagern.
            panelShape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.8
                )
                .blendMode(.plusLighter)
                .padding(2.5)

            Text(label)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
        }
        .animation(.easeOut(duration: 0.22), value: isPassedCorrect)
    }

    // MARK: - STOP-Achteck (Verkehrs-Semantik, Theme-unabhängig)
    //
    // Rot + weiße Innenkante + „STOP" bleibt unverändert — realer
    // Verkehrszeichen-Code. Nur der Stroke wird dünner (1.5 pt statt
    // 2.5 pt), damit das Achteck zum schlankeren Look der Option-
    // Schilder passt.
    private var stopOctagon: some View {
        ZStack {
            OctagonShape()
                .fill(Color(hex: "#D8181C"))
            OctagonShape()
                .stroke(Color.white, lineWidth: 1.5)
                .padding(1.5)
            Text("STOP")
                .font(.system(size: panelSize.height * 0.31, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
        }
    }

    // MARK: - Shape-Varianten

    /// Panel-Umriss-Shape je Variante. Return-Type ist `AnyShape`
    /// (iOS 16+) — `some Shape` aus einem `switch` braucht
    /// @ShapeBuilder, und das Type-Erasure über AnyShape ist hier
    /// einfacher und explizit.
    private var panelShape: AnyShape {
        switch variant {
        case .classic:
            return AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .gate:
            // Portal-Bogen: oben Halbkreis, unten klassisch gerade.
            return AnyShape(GateShape())
        case .marker:
            // Parallelogramm — rechts nach oben geschwungen, klassischer
            // Wegweiser-Look.
            return AnyShape(MarkerShape())
        }
    }

    // MARK: - Fills (Theme vor Pass, Grün nach Pass)

    /// **Vor-Pass**: Theme-Dunkelton als Metallrahmen-Farbe.
    /// **Nach-Pass** (User-Wunsch „gelöste Fragen sollen grün bleiben
    /// und so weiter fahren"): tiefes Grün, passt zur universellen
    /// Erfolgs-Semantik und bleibt stehen, während das Schild weiter
    /// nach unten scrollt.
    private var outerFill: Color {
        if isPassedCorrect { return Color(hex: "#1A6B3A") }    // dunkles Grün
        return Color(hex: colorTheme.deepHex)
    }

    /// Innerer Gradient — nach Pass hellgrün → dunkelgrün, wirkt
    /// wie ein frisches Checkmark-Shield. Die Theme-Farbe wird
    /// **kurz** übermalt (withAnimation 0.22 s), sodass der Wechsel
    /// sichtbar ist, während das Schild aus dem Spieler-Fenster
    /// nach unten weiter scrollt.
    private var innerFill: LinearGradient {
        if isPassedCorrect {
            return LinearGradient(
                colors: [
                    Color(hex: "#3FB870"),     // helles Grün oben
                    Color(hex: "#1A6B3A")      // dunkles Grün unten
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(hex: colorTheme.primaryHex),
                Color(hex: colorTheme.deepHex)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Pfosten + Halterung + Boden-Schatten

    private var postWithMount: some View {
        VStack(spacing: 0) {
            // Kleine Halterung (Manschette) am Übergang Panel → Pfosten.
            // Macht das Schild optisch „angeschraubt" statt schwebend.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#9A9EA8"),
                            Color(hex: "#5F636B")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: postWidth + 6, height: 3)

            // Pfosten — schlanker Zylinder-Look via Gradient.
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#B6BCC8"),
                                Color(hex: "#787D88"),
                                Color(hex: "#474B54")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: postWidth, height: postHeight)
                // Schatten-Streifen rechts — simuliert die runde Seite
                // des zylindrischen Pfostens.
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 1.5, height: postHeight)
                    .offset(x: postWidth * 0.32)
            }
        }
    }

}

// MARK: - Sign-Shape-Varianten

/// Portal-Bogen: oben Halbkreis-Kappe, unten gerade Kante.
private struct GateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let archRadius = min(w / 2, h * 0.4)
        // Links unten
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: archRadius))
        // Halbkreis nach oben-rechts
        p.addArc(
            center: CGPoint(x: w / 2, y: archRadius),
            radius: archRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

/// Parallelogramm-Wegweiser: rechte Seite schräg nach oben geneigt.
private struct MarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let slant: CGFloat = w * 0.12
        p.move(to: CGPoint(x: slant, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w - slant, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: - VocabularyListStoreContainer (Phase 7.4+ Observable-Bridge)

/// Wrapper-ObservableObject, der einen **optionalen** `VocabularyListStore`
/// kapselt und dessen `objectWillChange`-Signal weiterreicht. Damit
/// kann `WordRunnerGameView` ein `@ObservedObject` verwenden, ohne
/// dass der Caller einen nicht-optionalen Store besitzen muss (z. B.
/// in Previews oder wenn der Runner als reiner Gameplay-Test ohne
/// Live-Liste gestartet wird).
///
/// `backing` ist entweder der echte Store (dann ist List-Picker +
/// strict-Live-Modus verfügbar) oder `nil` (dann rendert der Empty-
/// State das „Zu den Listen"-Overlay).
@MainActor
final class VocabularyListStoreContainer: ObservableObject {
    let backing: VocabularyListStore?
    private var cancellable: AnyCancellable?

    init(store: VocabularyListStore?) {
        self.backing = store
        // Änderungen im Store bubbeln wir als eigenes
        // `objectWillChange`-Event hoch → @ObservedObject-Views, die
        // diesen Container halten, rendern bei jeder Store-Mutation
        // (z. B. Listen-Wechsel) neu.
        if let s = store {
            cancellable = s.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}

#if DEBUG
struct WordRunnerGameView_Previews: PreviewProvider {
    static var previews: some View {
        WordRunnerGameView()
    }
}
#endif
