import SwiftUI

/// **Tickets-Integration in das Arcade-Spiel** (2026-04-24, Pool-
/// Vereinheitlichung 2026-04-30 Stufe 1b).
///
/// Isolierte Extension für die Credit-Interaktionen. Mit der Pool-
/// Vereinheitlichung verbrauchen Rescue + Skip aus dem **selben
/// Pool** wie der Spielstart (`appArcadeCreditsKey`). Vorher gab es
/// einen separaten `playCredits`-Pool im jetzt entfernten
/// `ElumiCreditsStore`. Das Mapping ist transparent: ein Ticket =
/// ein Spielstart ODER eine Hilfe (Rescue/Skip).
///
/// **Features:**
///   • `playCreditsHUDChip` — kleiner Chip im Header während des
///     Spiels (dezent, zeigt Bestand). Spec-Punkt #2.
///   • `playCreditsSkipChip` — Button „Überspringen (1 Credit)" im
///     Header. Mapping auf Arcade: überspringt die aktuelle Runde
///     und springt auf die nächste (der natürlichste Analog zu
///     „Aufgabe überspringen" in diesem Arcade-Kontext).
///   • `playCreditsRescueOverlay` — wird **vor** dem normalen
///     Game-Over eingeblendet, wenn Credits > 0. Spec-Punkt #3
///     („Mit 1 Credit retten"): gibt dem Spieler eine Runde zurück,
///     reset Sting-Count auf 0, Spiel läuft weiter.
///   • `consumePlayCreditRescue()` / `consumePlayCreditSkipRound()`
///     — zentrale API-Eingangspunkte, zentralisieren die Consume-
///     Race-Protection.
///
/// **Naming-Note:** Die `playCredit…`-Symbol-Namen sind aus historischen
/// Gründen erhalten geblieben (Rescue/Skip-Mechanik, Call-Sites in
/// `ElumiArcadeGameView+Layout.swift`). Code-intern ist klar: gemeint
/// ist ab Stufe 1b der `arcadeCredits`-Pool.
extension ElumiArcadeGameView {

    // MARK: - HUD: Credits-Anzeige

    /// Dezenter Credits-Chip im HeaderBar während Spiel läuft.
    /// Spec #2: „kleine Anzeige oben: Credits: X — unauffällig,
    /// aber sichtbar". Liest direkt aus `arcadeCredits` (Pool-
    /// Vereinheitlichung 2026-04-30).
    var playCreditsHUDChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)
            Text("Credits: \(arcadeCredits)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppTheme.Colors.surface.opacity(0.92))
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.Colors.warning.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: arcadeCredits)
    }

    /// Skip-Chip neben dem Credits-Chip. Nur aktiv, wenn der User
    /// Credits hat und sich gerade im regulären Spielfluss befindet
    /// (kein Game-Over, keine Bonus-Runde). Spec #4.
    var playCreditsSkipChip: some View {
        Button {
            consumePlayCreditSkipRound()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Skip (1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppTheme.Colors.primary.opacity(playCreditsSkipEnabled ? 0.85 : 0.3))
            )
        }
        .buttonStyle(.plain)
        .disabled(!playCreditsSkipEnabled)
        .opacity(playCreditsSkipEnabled ? 1.0 : 0.4)
        .allowsHitTesting(playCreditsSkipEnabled)
    }

    /// Gate für den Skip-Button: Credits > 0 UND es läuft gerade
    /// ein regulärer Run (kein Start-Overlay, kein Game-Over, keine
    /// Banner, keine Bonusrunde). Pool-Quelle: `arcadeCredits`
    /// (Vereinheitlichung 2026-04-30).
    var playCreditsSkipEnabled: Bool {
        guard arcadeCredits > 0 else { return false }
        guard !isGameOver, !showingStartOverlay else { return false }
        guard !showingRoundBanner, !bonusRoundWaitingForTap else { return false }
        guard !isBonusRound else { return false }
        return isPlaying
    }

    // MARK: - Rescue-Prompt (Game-Over-Abfangpunkt)

    /// Prompt, der vor dem normalen Game-Over-Overlay auftaucht,
    /// wenn der Spieler Credits hat und noch keine Rescue-Entscheidung
    /// getroffen hat. Spec #3: „Mit 1 Credit retten".
    ///
    /// Wird vom Layout oberhalb des `gameOverOverlay` eingeblendet,
    /// solange `shouldShowRescueOffer == true`. Sobald der User eine
    /// Wahl trifft (Retten oder Weiter), schließt der Prompt und das
    /// Spiel verhält sich entweder regulär (Game-Over) oder läuft
    /// weiter (Rescue).
    var playCreditsRescueOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(AppTheme.Colors.error)
                .shadow(color: AppTheme.Colors.error.opacity(0.4), radius: 8, x: 0, y: 2)

            VStack(spacing: 6) {
                Text("Retten?")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Nutze 1 Credit — du bekommst ein Leben zurück und spielst weiter.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            VStack(spacing: 8) {
                Button {
                    consumePlayCreditRescue()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Mit 1 Credit retten")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.error))

                Button {
                    // User lehnt Rescue ab — Flag setzen, damit der
                    // Prompt nicht wiederkehrt. `gameOverOverlay`
                    // übernimmt ab jetzt den normalen Flow.
                    rescueConsumedForCurrentGameOver = true
                } label: {
                    Text("Nein, Ergebnis zeigen")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.Colors.error.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }

    /// Gate für das Rescue-Prompt: Spiel ist beendet, Credits > 0,
    /// und der Nutzer hat noch nicht entschieden. Pool-Quelle:
    /// `arcadeCredits` (Vereinheitlichung 2026-04-30).
    var shouldShowRescueOffer: Bool {
        isGameOver
            && arcadeCredits > 0
            && !rescueConsumedForCurrentGameOver
    }

    // MARK: - Consume-API (zentrale Eingänge, Race-sicher)

    /// Rescue konsumieren: 1 Credit (`arcadeCredits`) abziehen,
    /// Game-Over rückgängig machen, ein Leben zurückgeben, Sting-Count
    /// reset, Spiel wieder laufen lassen. Race-safe durch den
    /// `rescueConsumedForCurrentGameOver`-Flag — zweiter Tap wird
    /// ignoriert. Plus expliziter `arcadeCredits > 0`-Guard, damit der
    /// Decrement nicht in den Negativ-Bereich rutscht (auch wenn der
    /// Trigger-Pfad das normalerweise schon über `shouldShowRescueOffer`
    /// abfängt).
    func consumePlayCreditRescue() {
        guard !rescueConsumedForCurrentGameOver else { return }
        guard arcadeCredits > 0 else { return }
        arcadeCredits -= 1
        rescueConsumedForCurrentGameOver = true

        // Leben zurückgeben + States neutralisieren.
        // `misses` reduzieren statt auf 0 setzen — fair: der Spieler
        // hat sich bis hierher durchgekämpft und verliert nur das
        // allerletzte Leben nicht. Falls misses schon 0 war (edge),
        // max(0, …) schützt gegen Unterlauf.
        misses = max(0, misses - 1)
        jellyfishStingCount = 0
        isGameOver = false
        isPlaying = true

        // **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`,
        // 2. Iteration)** — User-Report nach 1. Iteration: „retten:
        // elumi ist da, musik an alles da, nur keine snacks, freunde
        // etc". Root Cause: die Spawn-Loop (`beginSnackSpawnTask`-
        // Pattern via `.task(id: gameSeed)` in Layout.swift) lief
        // während des Game-Over aus, weil ihre while-Bedingung
        // `isPlaying && !isGameOver` false wurde → Task hat sich
        // sauber beendet. Setzen von `isGameOver = false` reicht
        // nicht — der Task ist tot, eine neue Iteration startet nicht
        // automatisch. SwiftUI startet den `.task`-Closure nur neu,
        // wenn die `id` ändert. Daher hier `gameSeed = UUID()`
        // setzen — das cancelt einen evtl. noch laufenden Task und
        // startet die Spawn-Loop frisch. Wave-Stream-Reset ist
        // akzeptabel: Score / Round / Welt-State bleiben unangetastet
        // (gameSeed steuert nur die Spawn-Task-ID, keine Wave-
        // Geometrie). User sieht: Charakter da + Musik an + Snacks
        // beginnen wieder zu fallen.
        gameSeed = UUID()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            elumiVisible = true
        }
        ArcadeMusicPlayer.shared.startNewRun()

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        feedbackPlayer.playAchievement()
    }

    /// Skip konsumieren: 1 Credit (`arcadeCredits`) abziehen, Runde
    /// sofort beenden, Banner für nächste Runde triggern. Race-safe —
    /// guarded durch `playCreditsSkipEnabled` (das implizit
    /// `arcadeCredits > 0` prüft).
    ///
    /// **Quick-Fix 2026-04-30 (`v2-elumi-game-flow-fixes`, 2. Iteration)** —
    /// User-Report: „Skip → Spiel-Hintergrund läuft, aber Musik ist
    /// aus und nichts passiert".
    ///
    /// **Iteration 1** versuchte direkt `advanceToNextRound()` zu rufen —
    /// hat das Hänger-Problem nicht gelöst. Vermutung: das überspringt
    /// den natürlichen Round-End-Flow (round-clear-Sound, Banner-Phase 0,
    /// 2s-Wait), den Music-Player oder andere Systeme erwarten.
    ///
    /// **Iteration 2 (jetzt)**: den **natürlichen Round-Complete-Trigger**
    /// simulieren — `roundCatchCount` auf den Schwellwert
    /// (`snacksForRound(round)`) setzen. Im nächsten `updateGame`-Tick
    /// erkennt der bestehende Round-End-Check
    /// (`roundCatchCount >= snacksForRound(round) && !showingRoundBanner`)
    /// das Round-End und ruft `triggerRoundComplete()`. Dadurch läuft
    /// der vollständige normale Round-End-Flow durch:
    /// Round-Clear-Sound + Banner-Phase 0 (2s) + advance zum nächsten
    /// Round + Ready-Blink + Auto-Dismiss. Music bleibt durchgängig
    /// laufen weil kein Pfad das anfasst. Plus: Bonus-Round-Detection
    /// (alle 3 Runden) wird natürlich mit-getriggert.
    func consumePlayCreditSkipRound() {
        guard playCreditsSkipEnabled else { return }
        arcadeCredits -= 1

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        feedbackPlayer.playTabSwitch()

        // **Round-End-Trigger** via natural flow:
        //   • `roundCatchCount` auf Schwellwert setzen → nächster
        //     `updateGame`-Tick triggert `triggerRoundComplete()`
        //     automatisch.
        //   • Aktive Bedrohungen (Tentakel, Quallen-Stings) räumen wir
        //     selbst auf, damit der User in der 2s-Banner-Wartezeit
        //     keinen Schaden nimmt.
        roundCatchCount = snacksForRound(round)
        activeTentacles.removeAll()
        jellyfishStingCount = 0
    }

    /// Aufzurufen, wenn eine neue Game-Over-Episode beginnt — damit
    /// der Rescue-Prompt für den neuen Game-Over wieder erscheint.
    /// Nutzer kann pro Game-Over einmal entscheiden.
    func resetRescueOfferForNewGameOver() {
        rescueConsumedForCurrentGameOver = false
    }
}
