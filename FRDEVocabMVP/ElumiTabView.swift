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
///   Card: „Dein Training" (flach)                       ← IMMER sichtbar
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

    @ObservedObject private var profileStore = ProfileStore.shared
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0

    // MARK: - Slot-Machine + Trainingsgenerator-State (vorher in TrainingGeneratorView)

    @StateObject private var generatorStore = TrainingGeneratorStore.shared
    @StateObject private var dropRate = ElumiDropRateControllerStore()
    @StateObject private var budget = SlotMachineSpinBudgetStore()
    /// **Elumi-Play-Credits** (Test-System 2026-04-24). Getrennt vom
    /// `SlotMachineSpinBudgetStore` (der ist Slot-intern für weitere
    /// Spins) und vom GameHub-`arcadeCredits` (der ist „1 = 1 Spiel
    /// starten"). Dieser Pool wandert **persistent** mit dem Nutzer
    /// in das Elumi-Arcade-Spiel und wird dort für Rescue/Skip
    /// verbraucht.
    @ObservedObject private var playCredits = ElumiCreditsStore.shared

    /// User-gewählte Trainingsdauer in Minuten. **2026-04-24**: jetzt
    /// optional — der „Los geht's"-Button ist erst aktiv, sobald der
    /// User eine Zeit gewählt hat. Vorher war Default 10 und der Spin
    /// konnte ohne explizite User-Aktion gestartet werden.
    @State private var selectedDuration: Int? = nil
    /// Slot-Phase — externe Sicht der State-Maschine in `SlotMachineView`.
    @State private var slotPhase: SlotPhase = .idle
    /// Trigger-Token — Setzen auf `true` startet einen Spin.
    @State private var slotStartToken: Bool = false
    /// Ziel-Symbole pro Reel — vor dem Spin gefüllt.
    @State private var spinTargets: [ReelSymbol?] = [nil, nil, nil]
    /// Letztes Spin-Ergebnis — Quelle für die Ergebnis-Sektion.
    @State private var lastSpinResult: SlotSpinResult?

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
        currentSpinNumber == 0 ? "Los geht's!" : "Nochmal drehen"
    }

    private let sectionStyle: AppSectionStyle = .elumi

    // MARK: - Palette (2026-04-25 User-Spec „Pink reduzieren")
    //
    // Exakte Hex-Werte aus dem User-Spec — Single Source of Truth,
    // damit die Farben screen-übergreifend konsistent bleiben.

    /// Mint-Background der Zeit-Card, ruhig und neutral.
    private let durationCardBackground: Color = Color(hex: "#E8F7F4")
    /// Leichte Mint-Umrandung der Zeit-Card.
    private let durationCardBorder: Color = Color(hex: "#CFEDE7")
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

    private static let durationOptions: [Int] = [10, 15, 20]

    // MARK: - Body

    var body: some View {
        // **2026-04-24 Vereinfachung**: Status-Card am Footer komplett
        // entfernt — sie war die „halb sichtbar unter Footer"-Card.
        // Kein `.safeAreaInset(.bottom)` mehr → bottom-padding deutlich
        // reduziert, damit nichts mehr unter dem AppBottomBar hängt.
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
                    title: headerTitle,
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )

                // 1) Zeit-Card oben.
                durationCard

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

    // MARK: - Header-Title

    /// **User-Spec 2026-04-24 Update**: kurzer Header „Salut XXX!".
    /// Vorher „Salü Frank, schön, dass du da bist" — die zweite Hälfte
    /// raus für ruhigeres Layout. Name aus Profil; ohne Name nur „Salut!".
    private var headerTitle: String {
        let raw = profileStore.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = raw, !name.isEmpty {
            return "Salut \(name)!"
        }
        return "Salut!"
    }

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
                feedbackPlayer.playLaunch()
                #if DEBUG
                print("🔊 [Slot] Spin-Start-Sound (session primed)")
                #endif
            }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Zeit-Card („Wie lange willst du üben?") — IMMER sichtbar

    /// Card oberhalb der Slot Machine (User-Spec 2026-04-24).
    /// Drei Zeit-Chips, immer sichtbar. Auswahl entscheidet, ob
    /// „Los geht's!" aktiv wird.
    private var durationCard: some View {
        // **2026-04-25 System-Consistency-Final** (User-Spec „surfaceSecondary
        // / appSetupCardBackground, keine hellen Flächen"). Das App-Theme
        // ist DARK (surface=elumiMidnight, textPrimary=cream) — der zuvor
        // probierte Mint-Hintergrund `#E8F7F4` passte nicht zum System.
        // Zurück zum kanonischen `appSetupCardBackground()`-Modifier.
        VStack(alignment: .leading, spacing: 6) {
            Text("Wie lange willst du üben?")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            HStack(spacing: 12) {
                ForEach(Self.durationOptions, id: \.self) { minutes in
                    durationChip(minutes: minutes)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

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
        //   2. `.frame(maxWidth: .infinity, minHeight: 52)` — klar
        //      großzügige Tap-Area (>= 44pt Apple HIG) und expliziter
        //      Full-Width-Stretch, damit der ganze 1/3-Slot tappbar ist.
        //   3. `.contentShape(Rectangle())` NACH dem Background — setzt
        //      die Hit-Area auf das volle Rechteck. Hätte `.contentShape`
        //      VOR dem Background gestanden, wäre die Hit-Area auf den
        //      Content-Zustand eingefroren.
        //   4. `.onTapGesture { ... }` — schneller, reliabler Tap-
        //      Handler. Kein `withAnimation`-Wrapping um die State-
        //      Mutation: SwiftUI re-rendert synchron, der nächste Tap
        //      trifft garantiert die frische View.
        //   5. Farb-Transition kommt über `.animation(_, value:)` auf
        //      der Chip-Ebene — nur auf Color-Änderung, nicht auf den
        //      Input-Pfad.
        //
        // Zusätzlich `#if DEBUG`-Print-Logs, damit im Console direkt
        // sichtbar ist, dass jeder Tap ankommt und der State umspringt.
        // **2026-04-25 Attention-Pulse (User-Spec „solange noch kein
        // Wahl getroffen wurde, blinken um User zu animieren")**.
        //
        // `needsAttention = selectedDuration == nil` — alle drei Chips
        // pulsieren so lange NICHTS ausgewählt ist. Mit leichtem
        // `stagger` pro Chip-Wert (10/15/20) entsteht eine Wellen-
        // Bewegung von links nach rechts, die klar zur Auswahl
        // einlädt ohne nervig zu wirken. Sobald der User einen Chip
        // tippt, geht `selectedDuration` auf einen Wert → Pulse endet
        // sofort, Selected-State übernimmt.
        let moduleColor = sectionStyle.accent
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let isSelected = selectedDuration == minutes
            let needsAttention = selectedDuration == nil
            let t = context.date.timeIntervalSinceReferenceDate
            // Wellen-Stagger: 10min → offset 0, 15min → 0.22s,
            // 20min → 0.44s. Cycle 1.2s → gemütliches Pulsen.
            let cycle: Double = 1.2
            let stagger = Double(minutes - 10) / 5.0 * 0.22
            let rawPhase = (t + stagger).truncatingRemainder(dividingBy: cycle) / cycle
            let wave = (sin(rawPhase * 2 * .pi) + 1) / 2  // 0…1
            let attentionBorderOpacity = needsAttention ? 0.3 + 0.55 * wave : 0
            let attentionGlow = needsAttention ? 0.25 + 0.45 * wave : 0
            let attentionScale: CGFloat = needsAttention
                ? CGFloat(1.0 + 0.012 * wave)
                : 1.0

            return ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? moduleColor.opacity(0.25)
                            : AppTheme.Colors.secondarySurface
                    )
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? moduleColor
                            : (needsAttention
                                ? moduleColor.opacity(attentionBorderOpacity)
                                : Color.clear),
                        lineWidth: isSelected ? 2 : (needsAttention ? 1.5 : 0)
                    )
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(minutes)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("min")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.78))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(isSelected ? 1.0 : 0.85)
            .scaleEffect(isSelected ? 1.03 : attentionScale)
            .shadow(
                color: needsAttention ? moduleColor.opacity(attentionGlow) : .clear,
                radius: 12,
                x: 0,
                y: 0
            )
            .contentShape(Rectangle())
            .onTapGesture {
                #if DEBUG
                print("🕒 [DurationChip] tap on \(minutes) (prev=\(selectedDuration.map(String.init) ?? "nil"))")
                #endif
                selectedDuration = minutes
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #if DEBUG
                print("🕒 [DurationChip] selectedDuration → \(minutes) ✓")
                #endif
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
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
        VStack(spacing: 8) {
            // Caption „Versuch X von 3" nur sichtbar wenn 2-Button-State
            // (= mind. 1 Spin gemacht UND noch Versuche übrig).
            if currentSpinNumber > 0 && hasRemainingSpins {
                Text(currentAttemptDisplay)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if currentSpinNumber == 0 {
                singleSpinButton
            } else if hasRemainingSpins {
                twinCTAs
            } else {
                singleTrainingButton
            }
        }
    }

    /// State 1: erster Versuch — ein Full-Width-Button „Los geht's!".
    private var singleSpinButton: some View {
        Button {
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
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityLabel(Text("Los geht's"))
        .accessibilityHint(Text("Startet den ersten Slot-Spin"))
    }

    /// State 2: 2-Button-State nach erstem Spin, solange Versuche übrig.
    /// Beide Buttons gelb gefüllt, gleiche Höhe, gleiche Schriftgröße,
    /// `frame(maxWidth: .infinity)` → 50/50-Aufteilung.
    private var twinCTAs: some View {
        HStack(spacing: 12) {
            Button {
                triggerSpin()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                    Text(spinPrimaryLabel)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: ctaYellow))
            .disabled(!canTriggerSpin)
            .opacity(canTriggerSpin ? 1.0 : 0.45)
            .accessibilityLabel(Text(spinPrimaryLabel))
            .accessibilityHint(Text("\(currentAttemptDisplay). Erzeugt eine andere zufällige Trainings-Zusammenstellung."))

            Button {
                startTraining()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Jetzt üben")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: ctaYellow))
            .accessibilityLabel(Text("Jetzt üben"))
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
        .buttonStyle(AppPrimaryButtonStyle(color: ctaYellow))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityLabel(Text("Jetzt üben"))
        .accessibilityHint(Text("Startet die generierte Trainingseinheit"))
    }

    /// **Spin-Gate** (User-Spec 2026-04-24): Spin ist nur dann erlaubt,
    /// wenn (a) die Phase es zulässt, (b) eine Zeit gewählt wurde UND
    /// (c) noch Versuche übrig sind.
    private var canTriggerSpin: Bool {
        isSpinAllowed && selectedDuration != nil && hasRemainingSpins
    }

    /// Spin ist nur in `.idle` und `.revealed` erlaubt — während
    /// `.spinning` / `.stopping` / `.landed` muss der Button deaktiviert
    /// sein, damit kein zweiter Spin in einen laufenden Spin reinhackt.
    private var isSpinAllowed: Bool {
        slotPhase == .idle || slotPhase == .revealed
    }

    // MARK: - „Dein Training"-Card — IMMER sichtbar

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
            Text("Dein Training")
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
        // **2026-04-25 Visibility-Pass** (User-Feedback „leere Slots
        // zu dunkel, wirken unfertig"). Vorher: secondarySurface.opacity(0.4)
        // + dashed-border-opacity(0.45) → fast unsichtbar auf der
        // hellen Card. Jetzt:
        //   • Bg deutlich heller — volle `secondarySurface`-Fläche mit
        //     leichter `surface`-Aufhellung → wirkt wie eine
        //     vorbereitete Karte.
        //   • Dashed Outer-Border intensiver (opacity 0.75, stride
        //     5/3), der „noch nicht gefüllt"-Charakter ist klar.
        //   • Circle stärker sichtbar: Fill `surface`, dashed stroke
        //     mit sichtbarer Border-Farbe, größere 32pt statt 28pt.
        //   • Hint-Symbol („+"-Sparkle) im Circle, signalisiert dass
        //     hier gleich ein Modul erscheint.
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.surface)
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(
                        AppTheme.Colors.border,
                        style: StrokeStyle(lineWidth: 1.4, dash: [3, 2])
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.65))
            }
            Text("—")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
        // Icon-Größen dadurch nochmal hoch:
        //   • HomeModuleIconView 32 → 40 (+25%)
        //   • Elumi-Asset 30 → 38 (+27%)
        VStack(spacing: 5) {
            if let module = symbol.homeModule {
                HomeModuleIconView(icon: module.icon, size: 40)
            } else if let assetName = symbol.assetImage {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
            }
            Text(symbol.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
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
    /// **2026-04-24 Gate**: läuft nur, wenn auch eine Zeit gewählt
    /// wurde. Ohne Zeit kein Spin.
    private func triggerSpin() {
        guard canTriggerSpin else { return }
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
    /// **2026-04-24**: Zusätzlich zum internen Spin-Budget-Bonus
    /// (`budget.awardBonusCredits`) vergeben wir hier auch
    /// **persistente Play-Credits** an `ElumiCreditsStore`. Regeln
    /// identisch (1/3/6), aber anderer Pool: Play-Credits folgen dem
    /// Nutzer ins Arcade-Spiel und helfen dort (Rescue). Die
    /// Vergabe läuft **nach** dem vollständigen Reel-Stop (dieser
    /// Callback wird von der Slot-Phase `.revealed` exakt einmal
    /// ausgelöst) — dadurch kein Doppel-Grant möglich.
    ///
    /// **Versuchslogik**: Hier — und NUR hier — wird
    /// `currentSpinNumber` inkrementiert. Bei bloßem Button-Tap oder
    /// während einer abgebrochenen Animation wird dieser Pfad NICHT
    /// erreicht, Versuche gehen nicht verloren.
    private func handleSlotLanded(_ result: SlotSpinResult) {
        lastSpinResult = result
        currentSpinNumber = min(currentSpinNumber + 1, maxSpins)
        dropRate.registerSpinResult(elumiCount: result.elumiCount)
        budget.awardBonusCredits(for: result.elumiCount)
        // Play-Credits persistieren für Rescue/Skip im Arcade-Spiel.
        let granted = playCredits.grantForSlot(elumiCount: result.elumiCount)
        #if DEBUG
        print("🎰 [ElumiTab] Spin abgeschlossen — currentSpinNumber=\(currentSpinNumber)/\(maxSpins), Elumis=\(result.elumiCount), Credits+\(granted)")
        #endif
        _ = granted
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

    // **2026-04-24 User-Spec**: Der separate `playCreditsChip` ist
    // entfallen — Credits werden im Arcade-Spiel-HUD angezeigt
    // (siehe `ElumiArcadeGameView+PlayCredits.swift`). Der Store
    // `playCredits` bleibt erhalten (wird in `handleSlotLanded`
    // befüllt), nur die Card in diesem Tab ist weg.

    /// Generiert die echte Trainings-Session aus der gewählten Dauer
    /// (Fokus = .mixed als V1-Default — Fokus-Auswahl-Screen wurde
    /// per User-Spec entfernt) und navigiert zum ersten Block.
    /// **2026-04-24**: `selectedDuration` ist jetzt optional — wenn
    /// nicht gewählt (sollte UI-seitig nicht passieren, weil der CTA
    /// dann nicht aktiv ist), defensiver Fallback auf 10 Min.
    ///
    /// **Versuchslogik-Reset**: Vor der Navigation setzen wir
    /// `currentSpinNumber` auf 0 + räumen das lastSpinResult auf.
    /// Damit hat der Nutzer bei Rückkehr zum Tab frische 3 Versuche.
    private func startTraining() {
        let duration = selectedDuration ?? 10
        let session = TrainingGenerator.generate(
            duration: duration,
            focus: .mixed
        )
        generatorStore.storeSession(session)
        guard let firstBlock = session.blocks.first else { return }
        feedbackPlayer.playTabSwitch()
        // Versuchszähler zurücksetzen, Ergebnis löschen — bei Rückkehr
        // sieht der User wieder „Versuch 1/3".
        currentSpinNumber = 0
        lastSpinResult = nil
        slotPhase = .idle
        resultHighlightScale = 1.0
        resultHighlightGlow = 0.0
        navigate(routeForBlock(firstBlock))
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

    /// Maps `TrainingExerciseType` auf die beste verfügbare App-Route.
    private func routeForBlock(_ block: TrainingBlock) -> AppScreen {
        switch block.exerciseType {
        case .warmup, .flashcards, .review:
            return .flashcards(nil)
        case .quiz:
            return .quiz(nil)
        case .speed, .writing, .match:
            return .train(nil)
        case .articles:
            return .train(nil)
        case .accents:
            return .accents(nil)
        }
    }

    // **2026-04-24 Vereinfachung**: statusCard + statusMetric +
    // statusDivider entfernt. Sie waren am Footer gepinnt und
    // verursachten den „halb sichtbar unter Footer"-Bug. Streak/Level
    // bleiben im Trophy-Tab sichtbar — der Elumi-Tab fokussiert sich
    // jetzt nur auf die Slot-Machine.
}
