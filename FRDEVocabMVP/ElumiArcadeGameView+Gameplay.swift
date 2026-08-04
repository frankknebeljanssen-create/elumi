import SwiftUI

extension ElumiArcadeGameView {
    func spawnSnack() {
        let roll = Double.random(in: 0...1)
        let config = ArcadeRoundConfig(round: round)
        let now = gameClock

        // **Einheitliche Power-Up-Dichtekontrolle** (User-Spec
        // „Power-Up Spawn Balancing"): zentrale Gate-Prüfung, bevor
        // die probabilistische Typ-Wahl läuft. Verhindert Spam (max.
        // ein Power-Up pro 6s), verbietet Multi-on-Screen, respektiert
        // Per-Typ-Mindestabstände (Bubble 11s, Sauger 9s, Trank 14s).
        let powerUpsOnScreen = activeSnacks.filter { snack in
            ArcadePowerUps.type(for: snack.kind) != nil
        }.count
        let mayConsiderPowerUp = powerUpSpawnGate.mayConsiderPowerUp(
            now: now,
            powerUpsOnScreen: powerUpsOnScreen
        ) && !isAnyPowerUpActive(at: now)

        // Kompatibilitäts-Blocker — falls der Spawn-Gate (aus welchem
        // Grund auch immer) den Schutz nicht greift, halten wir die
        // alten Kind-spezifischen Blocker als zweite Verteidigungslinie.
        let suctionBlocked = activeSnacks.contains { $0.kind == .saugglocke } || hasActiveSuction()
        let potionBlocked = activeSnacks.contains { $0.kind == .slowMotionPotion } || hasActiveSlowMotion()
        let shieldBlocked = activeSnacks.contains { $0.kind == .shieldBubble } || hasActiveShieldBubble()

        // Guarantee at least 1 suction per round (after 1/3 of snacks caught)
        let thirdCount = config.snacksRequired / 3
        let forceSuction = !roundSuctionSpawned && roundCatchCount >= thirdCount
            && !suctionBlocked && mayConsiderPowerUp
            && powerUpSpawnGate.mayConsider(type: .vacuum, now: now)

        let kind: ElumiArcadeDropKind
        if forceSuction {
            kind = .saugglocke
            roundSuctionSpawned = true
            powerUpSpawnGate.registerSpawn(type: .vacuum, at: now)
        } else if mayConsiderPowerUp,
                  powerUpSpawnGate.mayConsider(type: .shieldBubble, now: now),
                  !shieldBlocked,
                  roll < ArcadePowerUps.config(for: .shieldBubble).spawnWeight {
            // Schutz-Bubble — selten, aber verlässlich. Hat erste
            // Priorität im Power-Up-Roll, weil sie der neueste Typ
            // ist und im frühen Slice-Status noch nicht unter-
            // repräsentiert sein soll.
            kind = .shieldBubble
            powerUpSpawnGate.registerSpawn(type: .shieldBubble, at: now)
        } else if mayConsiderPowerUp,
                  powerUpSpawnGate.mayConsider(type: .slowMotion, now: now),
                  !potionBlocked,
                  roll < config.slowMotionPotionChance {
            kind = .slowMotionPotion
            powerUpSpawnGate.registerSpawn(type: .slowMotion, at: now)
        } else if mayConsiderPowerUp,
                  powerUpSpawnGate.mayConsider(type: .bonusPoints, now: now),
                  roll < config.slowMotionPotionChance + config.bonusChance {
            kind = .bonusblase
            powerUpSpawnGate.registerSpawn(type: .bonusPoints, at: now)
        } else if mayConsiderPowerUp,
                  powerUpSpawnGate.mayConsider(type: .vacuum, now: now),
                  !suctionBlocked,
                  roll < config.slowMotionPotionChance + config.bonusChance + config.suctionChance {
            kind = .saugglocke
            roundSuctionSpawned = true
            powerUpSpawnGate.registerSpawn(type: .vacuum, at: now)
        } else if roll < config.slowMotionPotionChance + config.bonusChance + config.suctionChance + config.falseElumiChance {
            kind = .falseElumi
        } else {
            kind = [.wuermchen, .wasserfloh, .algenkugel].randomElement() ?? .wuermchen
        }

        let querschlaegerChance = config.querschlaegerChance
        let isQuerschlaeger = kind.isSnack && Double.random(in: 0...1) < querschlaegerChance
        // **Sauger-Fall** (User-Entscheidung): Saugglocke fällt
        // komplett gerade, kein Wobble. Spec „muss gerade runterkommen
        // und sich dann auf Elumis Kopf setzen" — für das Landen auf
        // dem Kopf ist senkrechter Fall entscheidend, damit der User
        // sich auf die X-Position konzentrieren kann.
        let wobbleAmp: CGFloat
        let wobbleFreq: Double
        if kind == .saugglocke {
            wobbleAmp = 0
            wobbleFreq = 0
        } else if isQuerschlaeger {
            wobbleAmp = CGFloat.random(in: config.querschlaegerAmplitude)
            wobbleFreq = Double.random(in: config.querschlaegerFrequency)
        } else {
            wobbleAmp = CGFloat.random(in: 0.01...0.05)
            wobbleFreq = Double.random(in: 1.4...3.1)
        }

        // Power-ups fall slower (easier to catch). Schutz-Bubble hat
        // eine besonders lange „Lebensdauer" — sie soll im oberen
        // Drittel stehen bleiben und dem User Zeit geben, sie bewusst
        // zu erreichen (Spawn-Position-Logik in Motion.swift).
        let fallDuration: Double
        switch kind {
        case .slowMotionPotion:
            fallDuration = config.fallDuration * 1.3
        case .shieldBubble:
            fallDuration = 7.0
        default:
            fallDuration = config.fallDuration
        }

        activeSnacks.append(
            ElumiArcadeSnackState(
                kind: kind,
                spawnedAt: gameClock,
                laneX: CGFloat.random(in: 0.12...0.88),
                wobbleAmplitude: wobbleAmp,
                wobbleFrequency: wobbleFreq,
                fallDuration: fallDuration,
                rotationDrift: Double.random(in: -18...18),
                renderScale: spawnRenderScale(for: kind),
                motionPhase: Double.random(in: 0...(Double.pi * 2)),
                points: snackPoints(for: kind)
            )
        )

        // Spawn-Sound über zentrales SFX-Hook-System. Typ-spezifische
        // Assets werden in `ArcadeSFX` getauscht, sobald sie
        // vorliegen — hier keine weiteren Änderungen nötig.
        if let type = ArcadePowerUps.type(for: kind) {
            arcadeSFX?.fire(.spawn, for: type, at: gameClock)
        }
    }

    /// Ist aktuell **irgendein** Power-Up aktiv? Genutzt vom Spawn-Gate,
    /// um „ein Power-Up gleichzeitig"-Regel aus der User-Spec zu
    /// erzwingen (auch wenn's auf dem Screen keine Drops gibt, aber der
    /// Aktiv-Zustand von vorher noch läuft).
    func isAnyPowerUpActive(at date: Date) -> Bool {
        return hasActiveSuction(at: date)
            || hasActiveBonusPoints(at: date)
            || hasActiveSlowMotion(at: date)
            || hasActiveShieldBubble(at: date)
    }

    // MARK: - Ambient Sea-Creature Event (Fish/Shark)

    /// Rollt einmal pro Runde nach ~5 s aktiven Gameplays auf ein
    /// Ambient-Event. Reine Visuals — kein Gameplay-Impact, keine
    /// Kollisionen. Zweck: dem Stage Dynamik geben, Unterwasser-Feeling.
    ///
    /// Trigger-Bedingungen:
    ///   • noch nicht in dieser Runde gefeuert
    ///   • noch keines aktiv auf dem Screen
    ///   • Runden-Zeit ≥ 5 s (User hatte Zeit, ins Spiel zu kommen)
    ///   • ~20 % Wahrscheinlichkeit pro Tick-Check (pro 33 ms Game-Loop),
    ///     rolling until fires → garantiert einmal pro Runde spätestens
    ///     nach weiteren ~1.5 s Spieleinsatz.
    func tickAmbientSeaCreature(at date: Date) {
        // Schon gefeuert → nichts zu tun bis Runden-Reset.
        guard !ambientEventFiredThisRound else { return }
        // Aktives Event läuft noch → nichts tun.
        guard ambientSeaCreature == nil else { return }
        // Mindest-Startzeit in Runde abwarten (grob: seit 5 snacks
        // catched). Alternativ schauen wir auf roundCatchCount.
        guard roundCatchCount >= 3 else { return }
        // Probabilistisch: ~2 % pro Tick = bei 30 Hz Game-Loop alle
        // ~1.5 s ein Event. Zusammen mit Streak-Bedingung bekommen
        // User in jeder Runde das Event ungefähr zwischen Sekunde 5-15.
        guard Double.random(in: 0...1) < 0.02 else { return }

        spawnAmbientSeaCreature(at: date)
    }

    /// Erzeugt ein neues Ambient-Ereignis. Hai **nur** im mittleren
    /// Rundenfenster (ca. 10–25 s nach Rundenstart, approximiert via
    /// `roundCatchCount` 6–18 bei ~1.5 s/Catch). Außerhalb des Fensters
    /// kommt statt Hai immer der Fisch-Schwarm — Hai ist das seltene
    /// Premium-Event, das sich lohnen muss. Fisch-Schwarm kann
    /// jederzeit kommen.
    func spawnAmbientSeaCreature(at date: Date) {
        let catches = roundCatchCount
        let sharkEligible = (catches >= 6 && catches <= 18)
        let isShark = sharkEligible && Double.random(in: 0...1) < 0.40
        let kind: AmbientSeaCreatureState.Kind = isShark ? .shark : .fishSchool
        // Hai langsamer + majestätischer; Fisch-Schwarm flinker.
        let speed = isShark ? Double.random(in: 8.0...11.0) : Double.random(in: 4.0...6.0)
        let creature = AmbientSeaCreatureState(
            kind: kind,
            spawnedAt: date,
            fromLeft: Bool.random(),
            normalizedY: CGFloat.random(in: 0.25...0.55),
            speed: speed,
            wobblePhase: Double.random(in: 0...(.pi * 2))
        )
        ambientSeaCreature = creature
        ambientEventFiredThisRound = true
        // **Sound-Hook-Platzhalter** (User-Spec: „Splash /
        // Wasserbewegung / leises whoosh"): sobald das Audio-Asset
        // vorliegt, hier `feedbackPlayer.playSharkWhoosh()` oder
        // `feedbackPlayer.playFishSplash()` einbauen. Aktuell
        // stumm, damit das Event rein visuell bleibt.
        #if DEBUG
        appDebugLog("🐟 [AmbientEvent] \(kind): from=\(creature.fromLeft ? "left" : "right"), y=\(creature.normalizedY), duration=\(speed)s (sharkEligible=\(sharkEligible))")
        #endif

        // Nach Crossing + kleinem Puffer remove. Dauer = speed,
        // Puffer = 0.5 s, damit die Kreatur ganz off-screen ist.
        let lifetime = speed + 0.5
        let myId = creature.id
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            if self.ambientSeaCreature?.id == myId {
                self.ambientSeaCreature = nil
            }
        }
    }

    /// Reset beim Rundenwechsel — frischer Roll in der neuen Runde.
    func resetAmbientEventForNewRound() {
        ambientEventFiredThisRound = false
    }

    func startGame() {
        // **Bug-Fix** (User-Report „Elumi nicht mehr sichtbar im Arcade-
        // Spiel"): vorher hat `guard showingStartOverlay else { return }`
        // den AutoStart-Pfad gekillt, weil der aufrufende `onAppear` das
        // Overlay bereits auf `false` gesetzt hatte, BEVOR er `startGame()`
        // rief — die guard schnappte zu, `elumiVisible` blieb auf `false`,
        // Elumi unsichtbar.
        //
        // Neu: idempotent via `elumiVisible` — wenn der Character bereits
        // sichtbar ist (Spiel läuft), keine Aktion. Sonst regulärer
        // Start-Pfad, egal ob aus Overlay-Tap oder AutoStart.
        guard !elumiVisible else { return }

        // **Hard-Reset von Welt-State** (User-Report „beim Start kommen
        // manchmal 50–100 Items auf einmal runter, vor allem beim
        // Wechsel zwischen Elumi und Word Runner"):
        //
        //   1. Ursprungs-Snack-Reset: `activeSnacks` + Power-Ups
        //      (Phase 7.6 – Commit 52285b6).
        //   2. **Zusätzlich** (dieser Patch): `gameClock` / `lastFrameDate`
        //      zurücksetzen. Sonst läuft die Game-Uhr weiter, während
        //      der User in Word Runner unterwegs ist — beim Rückkehr
        //      glaubt der Spawner, es seien 30+ Sekunden vergangen und
        //      rendert den kumulierten Spawn-Plan auf einmal ab.
        //   3. Runden-/Combo-Counter (`round`, `roundCatchCount`,
        //      `comboCount`, `totalCaught`, `bestCombo`, `lastCatchDate`)
        //      ebenfalls mit aufsetzen — ein stehen gelassener
        //      `roundCatchCount` triggert sonst den Runden-Abschluss
        //      beim ersten Snack.
        activeSnacks = []
        activeJellyfish = nil
        activeTentacles = []
        activeFish = []
        suctionEndsAt = nil
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        shieldBubbleEndsAt = nil
        shieldBubbleRippleAt = nil
        ambientSeaCreature = nil
        ambientEventFiredThisRound = false
        arcadeSFX?.reset()
        powerUpSpawnGate.reset()
        powerUpRuntime.hardReset()
        // Zeit-State neu synchronisieren, damit der Spawner ohne
        // Zeit-Sprung bei 0 s startet.
        gameClock = Date()
        lastFrameDate = nil
        // Runden- + Catch-State — Sonst trägt ein stehen gelassener
        // `roundCatchCount` den Fortschritt der vorherigen Session mit.
        round = 1
        roundCatchCount = 0
        roundSuctionSpawned = false
        showingRoundBanner = false
        roundBannerPhase = 0
        readyBlinkVisible = true
        comboCount = 0
        totalCaught = 0
        bestCombo = 0
        lastCatchDate = nil
        comboBannerText = nil
        // Score/Misses zurücksetzen, falls der Re-Start ohne Game-Over
        // passiert (z.\u{00A0}B. Dismiss + Re-Open ohne endGame-Pfad).
        score = 0
        misses = 0
        // Bonus-Runden-State ebenfalls leeren.
        isBonusRound = false
        bonusFishCaught = 0
        bonusFishSpawned = 0
        bonusRoundStartedAt = nil
        bonusRoundResultText = nil
        bonusRoundWaitingForTap = false

        // **Phase 7.6** — `playLaunch()` hier entfernt. Der Start-
        // Sound kommt schon **beim Erscheinen** des Start-Screens
        // (siehe `ElumiArcadeGameView+Layout.onAppear`). Beim
        // Run-Start soll sofort die Musik einsetzen — kein zweiter
        // SFX-Trigger (User-Spec „dann geht sofort die musik los").
        showingStartOverlay = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            elumiVisible = true
        }
        gameSeed = UUID()
        consumeArcadeTestModusQueue()
        // **Arcade-Musik** (Phase „Arcade Music"): pro Run einen
        // neuen Track, alternierend aus der Rotation. ArcadeMusicPlayer
        // nutzt die gleiche `SoundPlayer`-Infrastruktur wie die SFX
        // und der Word-Runner — keine parallelen Audio-Systeme.
        // Dank `preloadNextTrack()` im onAppear ist der Decoder warm,
        // play() startet ohne Anlauf.
        ArcadeMusicPlayer.shared.startNewRun()
    }

    /// Liest die Testmodus-Arcade-Flags aus UserDefaults und löst die
    /// entsprechenden Runtime-Aktionen aus. Wird beim Start jeder
    /// Arcade-Session einmal konsumiert (Flags werden dabei NICHT
    /// gelöscht — User kann mehrere Starts mit derselben Queue machen,
    /// bis er sie bewusst in Settings aus-toggeled).
    ///
    /// Für Test/Demo — auch in Release-Builds verfügbar, damit
    /// Familien-Tester und TestFlight-User ohne Xcode-Zugriff
    /// Power-Ups direkt ausprobieren können. Side-Effect-frei
    /// (nur visuelle/temporäre In-Game-Effekte, kein Save-State).
    func consumeArcadeTestModusQueue() {
        let defaults = UserDefaults.standard
        let now = Date()
        if defaults.bool(forKey: appArcadeTestModusQueueShieldBubbleKey) {
            appDebugLog("🛠 [Arcade Testmodus] force-spawn shield bubble via queue")
            powerUpRuntime.activateOrCreate(
                type: .shieldBubble,
                at: now,
                durationOverride: shieldBubbleDuration
            )
            shieldBubbleEndsAt = now.addingTimeInterval(shieldBubbleDuration)
        }
        if defaults.bool(forKey: appArcadeTestModusQueueVacuumKey) {
            appDebugLog("🛠 [Arcade Testmodus] force-spawn vacuum via queue")
            activateSuction(at: now)
        }
        if defaults.bool(forKey: appArcadeTestModusQueueAmbientFishKey) {
            appDebugLog("🛠 [Arcade Testmodus] force fish event via queue")
            powerUpRuntime.debugForceAmbientEvent(type: .fish, durationSeconds: 5.0, at: now)
            // Auch die Legacy-Ambient-State setzen, damit die View-
            // Schicht (die noch den alten Pfad nutzt) ebenfalls ein
            // sichtbares Event hat.
            spawnAmbientSeaCreatureAsType(.fishSchool, at: now)
        }
        if defaults.bool(forKey: appArcadeTestModusQueueAmbientSharkKey) {
            appDebugLog("🛠 [Arcade Testmodus] force shark event via queue")
            powerUpRuntime.debugForceAmbientEvent(type: .shark, durationSeconds: 8.0, at: now)
            spawnAmbientSeaCreatureAsType(.shark, at: now)
        }
    }

    /// Hilfs-Spawn für Testmodus: erzwingt einen bestimmten Typ
    /// (Fisch/Hai), ohne den Random-Selection-Pfad in
    /// `spawnAmbientSeaCreature` zu durchlaufen. Garantiert, dass der
    /// User wirklich das sieht, was er in Settings getoggled hat.
    private func spawnAmbientSeaCreatureAsType(
        _ kind: AmbientSeaCreatureState.Kind,
        at date: Date
    ) {
        let isShark = kind == .shark
        let speed = isShark ? Double.random(in: 8.0...11.0) : Double.random(in: 4.0...6.0)
        let creature = AmbientSeaCreatureState(
            kind: kind,
            spawnedAt: date,
            fromLeft: Bool.random(),
            normalizedY: CGFloat.random(in: 0.25...0.55),
            speed: speed,
            wobblePhase: Double.random(in: 0...(.pi * 2))
        )
        ambientSeaCreature = creature
        ambientEventFiredThisRound = true
        let lifetime = speed + 0.5
        let myId = creature.id
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            if self.ambientSeaCreature?.id == myId {
                self.ambientSeaCreature = nil
            }
        }
    }

    func restartGame() {
        showingStartOverlay = false
        elumiVisible = true
        gameSeed = UUID()
        // **2026-04-24 Play-Credits**: bei einem echten Restart den
        // Rescue-Consumed-Flag zurücksetzen, damit im neuen Run ein
        // frisches Game-Over wieder einen Rescue-Prompt anbieten kann.
        // Pro Game-Over-Episode eine Rescue-Entscheidung — nicht
        // pro App-Session.
        rescueConsumedForCurrentGameOver = false
        // Restart rotiert auf den nächsten Track, wie beim normalen
        // Run-Start — jeder Run bekommt frische Musik, sodass
        // „Nochmal" sich klanglich wie ein neuer Versuch anfühlt.
        ArcadeMusicPlayer.shared.startNewRun()
    }

    func triggerCatchAnimation() {
        withAnimation(.easeInOut(duration: 0.1)) {
            mouthOpen = true
            characterScale = 1.08
            characterRotation = -3
            sparkleBurst = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                mouthOpen = false
                characterScale = 1
                characterRotation = 2
            }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.14)) {
                sparkleBurst = false
                characterRotation = 0
            }
        }
    }

    func hasActiveSuction(at date: Date = Date()) -> Bool {
        guard let suctionEndsAt else { return false }
        return suctionEndsAt > date
    }

    func hasActiveBonusPoints(at date: Date = Date()) -> Bool {
        guard let bonusPointsEndsAt else { return false }
        return bonusPointsEndsAt > date
    }

    func hasActiveSlowMotion(at date: Date = Date()) -> Bool {
        guard let slowMotionEndsAt else { return false }
        return slowMotionEndsAt > date
    }

    func hasActiveShieldBubble(at date: Date = Date()) -> Bool {
        guard let shieldBubbleEndsAt else { return false }
        return shieldBubbleEndsAt > date
    }

    func shieldBubbleSecondsRemaining(at date: Date = Date()) -> Int {
        guard let shieldBubbleEndsAt else { return 0 }
        return max(0, Int(ceil(shieldBubbleEndsAt.timeIntervalSince(date))))
    }

    func suctionSecondsRemaining(at date: Date = Date()) -> Int {
        guard let suctionEndsAt else { return 0 }
        return max(0, Int(ceil(suctionEndsAt.timeIntervalSince(date))))
    }

    func bonusPointsSecondsRemaining(at date: Date = Date()) -> Int {
        guard let bonusPointsEndsAt else { return 0 }
        return max(0, Int(ceil(bonusPointsEndsAt.timeIntervalSince(date))))
    }

    func slowMotionSecondsRemaining(at date: Date = Date()) -> Int {
        guard let slowMotionEndsAt else { return 0 }
        return max(0, Int(ceil(slowMotionEndsAt.timeIntervalSince(date))))
    }

    func activateSuction(at date: Date) {
        // Dock-in animation: scale Elumi up briefly
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            suctionDockScale = 1.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                suctionDockScale = 1.0
            }
        }

        activateSlowMotion(at: date)
        suctionEndsAt = date.addingTimeInterval(suctionDuration)
        showComboBanner("Saugstrahl aktiviert")
        // Activation whir, then seamless transition to loop
        feedbackPlayer.playSuctionWhir()
        let loopDelay: TimeInterval = 0.7 // after whir fades
        let duration = suctionDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + loopDelay) {
            self.feedbackPlayer.playSuctionLoop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.feedbackPlayer.stopSuctionLoop()
        }
    }

    func activateBonusPoints(at date: Date) {
        bonusPointsEndsAt = date.addingTimeInterval(bonusPointsDuration)
        showComboBanner("x2 Punkte aktiv")
        feedbackPlayer.playAchievement()
    }

    /// Aktiviert die Schutz-Bubble um den Spieler für
    /// `shieldBubbleDuration` Sekunden. Während dieser Zeit:
    ///   • `falseElumi`-Treffer → kein Leben-Verlust, kein Banner
    ///   • Snack-Collection → **keine** Punkte (per Spec: „sammelt
    ///     während aktiv auch keine Punkte")
    ///   • Power-Up-Pickups bleiben funktional (Sauger etc. darf
    ///     aufgenommen werden — die Bubble blockt nur Damage + Points)
    ///
    /// Der Aktiv-Zustand wird am Ende automatisch durch Zeit-Ablauf
    /// beendet — kein expliziter Cleanup nötig, weil
    /// `hasActiveShieldBubble(at:)` nur den Timer prüft.
    func activateShieldBubble(at date: Date) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            shieldBubbleDockScale = 1.18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                shieldBubbleDockScale = 1.0
            }
        }
        shieldBubbleEndsAt = date.addingTimeInterval(shieldBubbleDuration)
        // **Runtime-Sync**: parallel zum Timestamp wird die formale
        // State-Machine aktualisiert. Der Drop war `.idle`/`.spawning`,
        // wir transitionieren direkt in `.active` mit der Shield-Dauer.
        powerUpRuntime.activateOrCreate(
            type: .shieldBubble,
            at: date,
            durationOverride: shieldBubbleDuration
        )
        showComboBanner("Schutz-Bubble aktiviert")
        // Sound-Events über zentrale Hook: Pickup-Sound feuert sofort
        // beim Einsammeln, Activate separat — beide werden aktuell
        // vom gleichen Achievement-Sound serviced, bis dedizierte
        // Assets vorliegen (siehe `ArcadeSFX.handlePickup/Activate`).
        arcadeSFX?.fire(.pickup, for: .shieldBubble, at: date)
        arcadeSFX?.fire(.activate, for: .shieldBubble, at: date)
    }

    func endGame() {
        isGameOver = true
        isPlaying = false
        // Stop all sounds silently
        feedbackPlayer.sp.stop("saugloop")
        // Phase 7.6 — legacy `bgm_fischfang` + `stopBGM` entfernt
        // (paralleles Altsystem zur ArcadeMusicPlayer-Infrastruktur).
        feedbackPlayer.playGameOver()
        // Arcade-Musik weich ausfaden (nicht hart abreißen); der
        // Game-Over-SFX liegt darüber ungestört, weil die Fade-Dauer
        // (~0.8 s) deutlich kürzer ist als der Game-Over-Jingle.
        ArcadeMusicPlayer.shared.fadeOut()
        // Clear power-up state
        suctionEndsAt = nil
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        shieldBubbleEndsAt = nil
        shieldBubbleRippleAt = nil
        ambientSeaCreature = nil
        ambientEventFiredThisRound = false
        arcadeSFX?.reset()
        powerUpSpawnGate.reset()
        powerUpRuntime.hardReset()
        // Clear all snacks from screen
        activeSnacks = []
        // Hide Elumi
        withAnimation(.easeOut(duration: 0.25)) {
            elumiVisible = false
        }
    }

    /// Sauberer Totalausstieg ohne Game-Over-Sound — genutzt beim X-Button
    /// oder falls der Cover auf anderem Weg dismissed wird. Beendet ALLE
    /// laufenden Sounds (BGM, Loops, Ambient) und den aktiven Spielzustand,
    /// damit nach dem Verlassen sofort Stille herrscht.
    func exitArcadeSilently() {
        isPlaying = false
        isGameOver = true
        // Alle laufenden/Loop-Sounds stoppen
        feedbackPlayer.sp.stop("saugloop")
        // Phase 7.6 — legacy `bgm_fischfang` + `stopBGM` entfernt.
        feedbackPlayer.stopJellyfishAmbient()
        feedbackPlayer.stopAllFeedback()
        // Arcade-Musik sofort abbrechen — der Silent-Exit soll
        // wirklich still sein (kein nachhängender Fade).
        ArcadeMusicPlayer.shared.stopArcadeMusic()
        // Power-Up / Spielzustand zurücksetzen
        suctionEndsAt = nil
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        shieldBubbleEndsAt = nil
        shieldBubbleRippleAt = nil
        ambientSeaCreature = nil
        ambientEventFiredThisRound = false
        arcadeSFX?.reset()
        powerUpSpawnGate.reset()
        powerUpRuntime.hardReset()
        activeSnacks = []
        activeJellyfish = nil
        activeTentacles = []
        activeFish = []
        elumiVisible = false
    }

    func triggerFriendEaten() {
        // **Schutz-Bubble-Check**: während aktiv darf kein Leben
        // verloren werden (User-Spec). Wir blockieren den Damage-Pfad
        // komplett + zeigen stattdessen einen Schutz-Bounce (Dock-
        // Scale-Impuls) + einen expandierenden Ripple-Kreis, damit
        // der User den Block klar visuell wahrnimmt.
        if hasActiveShieldBubble() {
            triggerShieldBubbleImpact(at: gameClock)
            return
        }
        misses += 1
        // **Quick-Fix 2026-04-30** — `triggerScreenShake()` ersetzt
        // durch `triggerLifeLossVisual()` (= Shake + Character-Zucker
        // + Red-Flash + Error-Haptic). User-Spec: Lebens-Verlust muss
        // am Charakter sichtbar sein.
        triggerLifeLossVisual()
        feedbackPlayer.playSnackMiss()
        showComboBanner("Elumi-Freund! −1 Leben", duration: 1500)
        resetCombo()
    }

    /// Zentraler Kollisions-Impuls für die aktive Schutz-Bubble:
    /// Scale-Bounce + Ripple-Trigger. Wird sowohl von `triggerFriendEaten`
    /// als auch von der Snack-Block-Branch in `updateGame` aufgerufen.
    ///
    /// **Spam-Schutz**: Debouncing — Ripple/Bounce nur wenn seit dem
    /// letzten Event mindestens 120 ms vergangen sind. Verhindert,
    /// dass mehrere gleichzeitige Snack-Kollisionen in einem Frame
    /// die Bubble völlig zappeln lassen.
    func triggerShieldBubbleImpact(at date: Date) {
        if let last = shieldBubbleRippleAt,
           date.timeIntervalSince(last) < 0.12 {
            return
        }
        shieldBubbleRippleAt = date
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            shieldBubbleDockScale = 1.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                shieldBubbleDockScale = 1.0
            }
        }
        // Ripple-Sound über zentrales SFX-Hook-System. Debouncing
        // (0.15 s) innerhalb von `ArcadeSFX` verhindert Spam bei
        // schnellen Kollisions-Salven.
        arcadeSFX?.fire(.collision, for: .shieldBubble, at: date)
    }

    func activateSlowMotion(at date: Date) {
        slowMotionEndsAt = date.addingTimeInterval(slowMotionDuration)
    }

    func activateSlowMotionPotion(at date: Date) {
        slowMotionEndsAt = date.addingTimeInterval(slowMotionPotionDuration)
        showComboBanner("Zeitlupe aktiviert")
        feedbackPlayer.playSlowMotionActivate()
    }

    func advanceGameClock(now: Date) -> Date {
        let previousFrameDate = lastFrameDate ?? now
        let delta = max(0, now.timeIntervalSince(previousFrameDate))
        lastFrameDate = now

        let motionScale = hasActiveSlowMotion(at: now) ? 0.4 : 1.0
        gameClock = gameClock.addingTimeInterval(delta * motionScale)
        return gameClock
    }

    func triggerScreenShake() {
        Task { @MainActor in
            let sequence: [CGFloat] = [13, -11, 8, -6, 4, -2, 0]
            for offset in sequence {
                withAnimation(.easeOut(duration: 0.045)) {
                    screenShakeOffset = offset
                }
                try? await Task.sleep(for: .milliseconds(38))
            }
            screenShakeOffset = 0
        }
    }

    /// **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`, 2. Iteration)** —
    /// Sichtbares Feedback bei jedem Lebens-Verlust. User-Report nach
    /// 1. Iteration: „noch zu schwach". 2. Iteration mit ALLEN
    /// Verstärkern kombiniert (Variante v aus dem Spec-Vorschlag):
    ///
    ///   1. **Screen-Shake** (existing `triggerScreenShake`).
    ///   2. **Character-Scale-Zucker mit Bounce** — 1.0 → 0.70 → 1.05 → 1.0
    ///      (~450ms). Stärkeres Schrumpfen + Overshoot-Bounce zurück
    ///      simuliert „Treffer + Erholung".
    ///   3. **Charakter-Opacity-Flash** — 1.0 → 0.40 → 1.0 (synchron
    ///      mit dem Scale-Zucker). „Getroffen-und-sichtbar-blass"-
    ///      Effekt — der Charakter wirkt für einen kurzen Moment
    ///      verletzt.
    ///   4. **Roter Flash-Overlay** vergrößert (140pt statt 100pt) +
    ///      länger sichtbar (0.8s statt 0.5s, gesteuert über
    ///      `lifeLostFlashAt`-Zeitstempel im Layout-Overlay).
    ///   5. **Bolt-Icon** als Overlay über dem Charakter (~0.6s),
    ///      „Schlag/Damage"-Symbol für den Treffer-Moment.
    ///   6. **Error-Haptic** — `.notificationOccurred(.error)`.
    ///
    /// Wird aus allen drei `misses += 1`-Pfaden aufgerufen
    /// (`triggerFriendEaten`, off-screen-Snack-Miss, Quallen-Sting bei
    /// >=3). Existierende `triggerScreenShake()` an diesen Stellen
    /// wird durch diesen kombinierten Helper ersetzt.
    func triggerLifeLossVisual() {
        lifeLostFlashAt = Date()
        triggerScreenShake()

        // **2026-06-09** — Kurze Zäsur wie im Arcade-Automaten: Spiel
        // anhalten, „Bereit?" zeigen, dann weiter. Nicht beim letzten
        // Leben — da folgt ohnehin der Game-Over-Screen.
        if misses < maxMisses {
            let now = Date()
            lifeLostPauseStartedAt = now
            lifeLostPauseUntil = now.addingTimeInterval(lifeLostPauseDuration)
        }

        // Scale-Zucker mit Bounce: kurz hart schrumpfen, dann mit
        // Overshoot zurück.
        withAnimation(.easeOut(duration: 0.12)) {
            characterScale = 0.70
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.55)) {
                self.characterScale = 1.05
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.easeOut(duration: 0.20)) {
                self.characterScale = 1.0
            }
        }

        // Opacity-Flash: schnell halbtransparent, dann zurück.
        withAnimation(.easeOut(duration: 0.10)) {
            characterOpacityHit = 0.40
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.20)) {
                self.characterOpacityHit = 1.0
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func pointsForCaughtSnack(_ snack: ElumiArcadeSnackState, at date: Date) -> Int {
        let isComboCatch: Bool
        if let lastCatchDate {
            isComboCatch = date.timeIntervalSince(lastCatchDate) <= 1.1
        } else {
            isComboCatch = false
        }

        comboCount = isComboCatch ? comboCount + 1 : 1
        bestCombo = max(bestCombo, comboCount)
        lastCatchDate = date
        totalCaught += 1

        let comboBonus = comboCount >= 3 ? min(12, (comboCount - 2) * 2) : 0
        if comboCount >= 3 {
            let multiplierLabel = hasActiveBonusPoints(at: date) ? " · x2" : ""
            let prefix = comboCount >= 5 ? "Mega-Combo" : "Combo"
            showComboBanner("\(prefix) x\(comboCount) · +\(comboBonus)\(multiplierLabel)")
        }

        let rawPoints = snack.points + comboBonus
        return hasActiveBonusPoints(at: date) ? rawPoints * 2 : rawPoints
    }

    func showComboBanner(_ text: String, duration: Int = 900) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            comboBannerText = text
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(duration))
            guard comboBannerText == text else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                comboBannerText = nil
            }
        }
    }

    func resetCombo() {
        comboCount = 0
        lastCatchDate = nil
    }

    func triggerRoundComplete() {
        showingRoundBanner = true
        roundBannerPhase = 0
        readyBlinkVisible = true
        activeSnacks = []
        feedbackPlayer.playRoundClear()

        Task { @MainActor in
            // Phase 0: "Runde X geschafft!" für 2s
            try? await Task.sleep(for: .seconds(2))
            guard showingRoundBanner else { return }

            // Bonus round every 3 rounds (after R3, R6, R9...)
            if ArcadeRoundConfig(round: round).isBonusRoundTrigger {
                showingRoundBanner = false
                startBonusRound()
                return
            }

            advanceToNextRound()
        }
    }

    func advanceToNextRound() {
        Task { @MainActor in
            round += 1
            roundCatchCount = 0
            roundSuctionSpawned = false
            // Ambient-Event Reset bei Rundenwechsel — neuer Roll in
            // der neuen Runde, sodass jede Runde ihre eigene Chance
            // auf einen Fisch/Hai bekommt.
            resetAmbientEventForNewRound()
            ambientSeaCreature = nil
            // Runtime: nur Ambient-Lock freigeben, Power-Up-Cooldowns
            // bleiben (wir geben dem User nicht bei jedem Rundenwechsel
            // einen frischen Cooldown-Reset für Power-Ups).
            powerUpRuntime.resetForNewRound()
            roundBannerPhase = 1
            readyBlinkVisible = true
            showingRoundBanner = true

            // Ensure clean state after bonus round
            isBonusRound = false
            activeFish = []
            activeSnacks = []
            activeTentacles = []
            activeJellyfish = nil
            jellyfishStingCount = 0
            elumiY = 0.5
            bonusRoundWaitingForTap = false
            bonusRoundResultText = nil
            feedbackPlayer.stopJellyfishAmbient()
            if !isPlaying { isPlaying = true }

            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = false }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = true }
                try? await Task.sleep(for: .milliseconds(300))
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard showingRoundBanner else { return }
            showingRoundBanner = false
        }
    }

    // ── BONUS FISH ROUND ──

    func startBonusRound() {
        isBonusRound = true
        bonusFishCaught = 0
        bonusFishSpawned = 0
        activeFish = []
        activeSnacks = []           // Clear leftover snacks from previous round
        activeJellyfish = nil       // Clear jellyfish
        activeTentacles = []        // Clear tentacles
        jellyfishStingCount = 0
        feedbackPlayer.stopJellyfishAmbient()
        suctionEndsAt = nil         // Clear power-ups
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        comboBannerText = nil
        elumiY = 0.5
        bonusRoundStartedAt = Date()
        bonusRoundWaitingForTap = true
        // Phase 7.6 — `stopBGM` entfernt (Legacy).
        feedbackPlayer.playPowerUpSpawn()
        // Fish-Event-Musik: harter Cut vom Arcade-Track auf das
        // Fish-Theme über den `ArcadeMusicPlayer`.
        ArcadeMusicPlayer.shared.enterFishEvent()
    }

    func handleBonusRoundTap() {
        guard bonusRoundWaitingForTap else { return }

        if bonusFishSpawned == 0 && bonusRoundResultText == nil {
            // Tap to START fishing
            beginBonusFishSpawning()
        } else if bonusRoundResultText != nil {
            // Tap to CONTINUE after result
            bonusRoundWaitingForTap = false
            bonusRoundResultText = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                elumiY = 0.5
            }
            advanceToNextRound()
        }
    }

    func beginBonusFishSpawning() {
        bonusRoundWaitingForTap = false
        // Phase 7.6 — alter `bgm_fischfang`-Loop entfernt. Die
        // Fish-Runden-Musik kommt jetzt exklusiv vom
        // `ArcadeMusicPlayer.enterFishEvent()` (siehe
        // `beginBonusRoundTransition` oben). Kein paralleler
        // Legacy-Loop mehr, der über die `ArcadeMusic`-Spur läuft.

        Task { @MainActor in
            for i in 0..<bonusFishTotal {
                guard isBonusRound, !isGameOver else { break }
                spawnBonusFish()
                bonusFishSpawned = i + 1
                try? await Task.sleep(for: .milliseconds(800))
            }

            try? await Task.sleep(for: .seconds(2.0))
            guard isBonusRound else { return }
            endBonusRound()
        }
    }

    func spawnBonusFish() {
        let fromLeft = Bool.random()
        // First fish round (R3) is easier: bigger fish, slower
        let isFirstFishRound = round <= 3
        let fishSpeed = isFirstFishRound
            ? Double.random(in: 1.2...2.2)   // Slower
            : Double.random(in: 0.7...1.6)   // Fast
        let fishScale = isFirstFishRound
            ? CGFloat.random(in: 1.5...3.0)   // Bigger minimum
            : CGFloat.random(in: 1.0...3.0)

        activeFish.append(BonusFishState(
            spawnedAt: Date(),
            fromLeft: fromLeft,
            normalizedY: CGFloat.random(in: 0.15...0.75),
            speed: fishSpeed,
            wobblePhase: Double.random(in: 0...(Double.pi * 2)),
            renderScale: fishScale
        ))
    }

    func updateBonusRound(now: Date) {
        guard isBonusRound, gameSize != .zero else { return }

        let elumiPos = CGPoint(
            x: elumiPositionX(in: gameSize.width),
            y: elumiPositionY(in: gameSize.height)
        )

        var updated = activeFish
        for i in updated.indices {
            guard !updated[i].isCaught else { continue }
            let fishPos = fishPosition(for: updated[i], at: now, in: gameSize)
            let dist = hypot(fishPos.x - elumiPos.x, fishPos.y - elumiPos.y)
            if dist <= 42 {
                updated[i].isCaught = true
                bonusFishCaught += 1
                feedbackPlayer.playSuccess()
                // Catch animation
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    mouthOpen = true
                    characterScale = 1.06
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        self.mouthOpen = false
                        self.characterScale = 1
                    }
                }
            }
        }

        // Remove fish that left the screen (progress > 1.2)
        updated.removeAll { fish in
            if fish.isCaught { return true }
            let elapsed = now.timeIntervalSince(fish.spawnedAt)
            return elapsed / fish.speed > 1.3
        }

        activeFish = updated
    }

    func endBonusRound() {
        isBonusRound = false
        activeFish = []
        activeSnacks = [] // Clear any lingering friend/snack sprites
        activeJellyfish = nil
        activeTentacles = []
        jellyfishStingCount = 0
        feedbackPlayer.stopJellyfishAmbient()
        // Phase 7.6 — Legacy `bgm_fischfang` + `startBGM` entfernt.
        // Fish-Theme stoppen + zurück zum Arcade-Track exklusiv.
        ArcadeMusicPlayer.shared.exitFishEvent()

        // Reset Elumi to bottom rail (normal game mode position)
        elumiY = 0.5

        let success = bonusFishCaught >= Int(Double(bonusFishTotal) * 0.8) // 80%

        if success {
            misses = max(0, misses - 1)
            feedbackPlayer.playHighScore()
        } else {
            feedbackPlayer.playRoundClear()
        }

        // Show bonus result — tap to continue
        comboBannerText = nil
        bonusRoundResultText = success
            ? "🎉 +1 Leben! (\(bonusFishCaught)/\(bonusFishTotal) Fische)"
            : "🐟 \(bonusFishCaught)/\(bonusFishTotal) Fische gefangen"
        bonusRoundWaitingForTap = true
    }

    /// Dauer der Zäsur nach einem Lebens-Verlust: 0.9 s Standbild plus
    /// die Einblendung — lang genug, dass der Verlust ankommt, kurz
    /// genug, dass der Spielfluss nicht reißt.
    var lifeLostPauseDuration: TimeInterval { 1.4 }

    /// Läuft gerade die Lebens-Verlust-Zäsur?
    func isInLifeLostPause(at date: Date) -> Bool {
        guard let until = lifeLostPauseUntil else { return false }
        return date < until
    }

    func updateGame(now: Date) {
        guard gameSize != .zero else { return }

        // **2026-06-09** — Während der Zäsur steht das Spielfeld still:
        // keine Bewegung, kein Spawn, keine Kollision. Der Game-Clock
        // wird nicht weitergedreht, damit Snacks nach dem Fortsetzen
        // dort weiterlaufen, wo sie standen, statt zu springen.
        if isInLifeLostPause(at: now) { return }
        if lifeLostPauseUntil != nil {
            // Zäsur gerade abgelaufen → aufräumen und normal weiter.
            lifeLostPauseUntil = nil
            lifeLostPauseStartedAt = nil
            gameClock = Date()
        }

        // Bonus round uses its own update logic
        if isBonusRound {
            updateBonusRound(now: now)
            return
        }

        if let suctionEndsAt, suctionEndsAt <= now {
            self.suctionEndsAt = nil
        }
        if let bonusPointsEndsAt, bonusPointsEndsAt <= now {
            self.bonusPointsEndsAt = nil
        }
        if let slowMotionEndsAt, slowMotionEndsAt <= now {
            self.slowMotionEndsAt = nil
            feedbackPlayer.playSlowMotionEnd()
        }

        let motionNow = advanceGameClock(now: now)

        var survivors: [ElumiArcadeSnackState] = []
        var earnedPoints = 0
        var missedAnySnack = false
        var caughtSnackCount = 0
        let elumiXPosition = elumiPositionX(in: gameSize.width)
        // **Phase 7.6 Fix** (User-Wunsch „Snack verschwindet genau
        // wenn Elumi ihn berührt, nicht vorher/nachher"): Catch-Zone
        // ist jetzt ein **Kreis um Elumis aktuelle Position** (X + Y),
        // nicht mehr eine statische horizontale Linie. Damit bewegt
        // sich der Catch-Punkt vertikal mit Elumi mit — bewegt er
        // sich hoch, fängt er Snacks höher; bewegt er sich runter,
        // fängt er sie tiefer. Fühlt sich realistisch an.
        let elumiYPosition = elumiPositionY(in: gameSize.height)
        /// Radius um Elumis Zentrum, in dem ein Snack eingefangen wird.
        /// Matched in etwa die 80 pt Icon-Größe — ~34 pt horizontaler
        /// Abstand war schon der alte Wert, 32 pt vertikal gibt ein
        /// leicht flachovales Hit-Fenster (Elumi ist breiter als hoch
        /// im Visual wegen Tentakel).
        let catchRadiusX: CGFloat = 34
        let catchRadiusY: CGFloat = 32
        let suctionActive = hasActiveSuction(at: now)

        for snack in activeSnacks {
            let progress = snackProgress(for: snack, at: motionNow)
            let position = snackPosition(for: snack, at: motionNow, in: gameSize)
            let horizontalDistance = abs(position.x - elumiXPosition)
            let verticalDistance = abs(position.y - elumiYPosition)
            let isCatchable = horizontalDistance <= catchRadiusX
                && verticalDistance <= catchRadiusY
            // Beam greift **oberhalb** von Elumi und zieht Snacks an.
            let isInSuctionBeam = suctionActive &&
                snack.kind.isSnack &&
                position.y < elumiYPosition - catchRadiusY &&
                horizontalDistance <= suctionBeamHalfWidth

            if snack.kind == .falseElumi {
                if isCatchable && horizontalDistance <= 34 {
                    triggerFriendEaten()
                    triggerCatchAnimation()
                    continue // Remove from screen, don't return (game continues)
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if snack.kind == .saugglocke {
                if isCatchable && horizontalDistance <= 34 {
                    activateSuction(at: now)
                    triggerCatchAnimation()
                    continue
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if snack.kind == .bonusblase {
                if isCatchable && horizontalDistance <= 34 {
                    activateBonusPoints(at: now)
                    triggerCatchAnimation()
                    continue
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if snack.kind == .slowMotionPotion {
                if isCatchable && horizontalDistance <= 34 {
                    activateSlowMotionPotion(at: now)
                    triggerCatchAnimation()
                    continue
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if snack.kind == .shieldBubble {
                if isCatchable && horizontalDistance <= 34 {
                    activateShieldBubble(at: now)
                    triggerCatchAnimation()
                    continue
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            // **Shield-Bubble-Policy Phase 2** (User-Revision
            // „Snacks weiterhin einsammelbar"): Snacks werden auch
            // während des Shields regulär gesammelt. Nur Damage-
            // Kontakte (falseElumi → triggerFriendEaten mit
            // Shield-Guard) werden weiterhin sanft abgelenkt. Damit
            // der Shield sich wertvoll anfühlt — nicht als Blockade,
            // sondern als Stärkung.
            if isInSuctionBeam || (isCatchable && horizontalDistance <= 34) {
                earnedPoints += pointsForCaughtSnack(snack, at: now)
                caughtSnackCount += 1
                continue
            }

            if progress >= 1.04 {
                misses += 1
                missedAnySnack = true
                // **Quick-Fix 2026-04-30** — Visuelles Feedback bei
                // Off-Screen-Snack-Miss (vorher kein sichtbarer Cue,
                // nur ein Sound). User-Spec: Lebens-Verlust muss am
                // Charakter sichtbar sein.
                triggerLifeLossVisual()
                feedbackPlayer.playSnackMiss()
                continue
            }

            survivors.append(snack)
        }

        activeSnacks = survivors

        if caughtSnackCount > 0 {
            triggerCatchAnimation()
            if comboCount >= 3 || caughtSnackCount >= 2 {
                feedbackPlayer.playArcadeCombo()
            } else {
                feedbackPlayer.playSuccess()
            }
        }

        if earnedPoints > 0 {
            score += earnedPoints
            if score > highScore {
                if !didBeatHighScore {
                    feedbackPlayer.playHighScore()
                }
                didBeatHighScore = true
                highScore = score
            }
        }

        if caughtSnackCount > 0 {
            roundCatchCount += caughtSnackCount
            if roundCatchCount >= snacksForRound(round) && !showingRoundBanner {
                triggerRoundComplete()
            }
        }

        if missedAnySnack {
            resetCombo()
        }

        // ── Jellyfish update ──
        updateJellyfish(now: now)
        tickAmbientSeaCreature(at: now)
        // **Runtime-Tick** — zentraler State-Machine-Update für alle
        // Power-Ups. Schreibt `.active` → `.ending` → `.consumed`
        // fort und entfernt erledigte Instanzen automatisch.
        powerUpRuntime.tick(at: now)

        if misses >= maxMisses && !bonusRoundWaitingForTap {
            gameOverTitle = "Game Over"
            gameOverSubtitle = ""
            endGame()
        }
    }

    @MainActor
    func resetGameState() {
        activeSnacks = []
        score = 0
        misses = 0
        elumiX = 0.5
        isPlaying = true
        isGameOver = false
        // Phase 7.6 — Legacy `startBGM()` entfernt. Die Spiel-Musik
        // läuft exklusiv über `ArcadeMusicPlayer.startNewRun()`,
        // aufgerufen in `startGame()` / bei Restart.
        comboCount = 0
        totalCaught = 0
        bestCombo = 0
        lastCatchDate = nil
        gameClock = Date()
        lastFrameDate = nil
        comboBannerText = nil
        didBeatHighScore = false
        suctionEndsAt = nil
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        screenShakeOffset = 0
        gameOverTitle = "Game Over"
        gameOverSubtitle = ""
        mouthOpen = false
        characterScale = 1
        characterRotation = 0
        sparkleBurst = false
        round = 1
        roundCatchCount = 0
        roundSuctionSpawned = false
        showingRoundBanner = false
        isBonusRound = false
        activeFish = []
        bonusFishCaught = 0
        bonusFishSpawned = 0
        elumiY = 0.5
        bonusRoundStartedAt = nil
        bonusRoundResultText = nil
        bonusRoundWaitingForTap = false
        roundBannerPhase = 0
        readyBlinkVisible = true
        activeJellyfish = nil
        activeTentacles = []
        jellyfishStingCount = 0
        feedbackPlayer.stopJellyfishAmbient()
    }

    // ── JELLYFISH ──

    func spawnJellyfish() {
        let fromLeft = Bool.random()
        let jelly = JellyfishState(
            spawnedAt: Date(),
            fromLeft: fromLeft,
            normalizedY: CGFloat.random(in: 0.15...0.38),
            speed: Double.random(in: 7...10),
            wobblePhase: Double.random(in: 0...(.pi * 2))
        )
        activeJellyfish = jelly
        feedbackPlayer.playJellyfishAppear()
        feedbackPlayer.playJellyfishAmbientLoop()
    }

    func updateJellyfish(now: Date) {
        guard var jelly = activeJellyfish, gameSize != .zero else { return }

        let elapsed = now.timeIntervalSince(jelly.spawnedAt)
        let progress = elapsed / jelly.speed

        // Jellyfish left the screen
        if progress > 1.15 {
            activeJellyfish = nil
            activeTentacles = []
            jellyfishStingCount = 0
            feedbackPlayer.stopJellyfishAmbient()
            return
        }

        // Drop tentacles (max 4, every 1.5–2.5s while on screen 10%–90%)
        if progress > 0.10 && progress < 0.90 && jelly.tentaclesDropped < 4 {
            let timeSinceLastDrop = jelly.lastTentacleDropAt.map { now.timeIntervalSince($0) } ?? 999
            let dropInterval = Double.random(in: 1.5...2.5)
            if timeSinceLastDrop >= dropInterval {
                let jellyPos = jellyfishPosition(for: jelly, at: now, in: gameSize)
                let tentacle = TentacleDropState(
                    spawnedAt: now,
                    startY: jellyPos.y + 30,
                    normalizedX: jellyPos.x / gameSize.width,
                    wobbleAmplitude: CGFloat.random(in: 0.02...0.05),
                    fallDuration: Double.random(in: 2.8...3.5)
                )
                activeTentacles.append(tentacle)
                jelly.tentaclesDropped += 1
                jelly.lastTentacleDropAt = now
                activeJellyfish = jelly
                feedbackPlayer.playTentacleDrop()
            }
        }

        // Tentacle collision with Elumi
        let elumiPos = CGPoint(
            x: elumiPositionX(in: gameSize.width),
            y: elumiPositionY(in: gameSize.height)
        )
        let catchLineY = gameSize.height - 158

        var hitTentacleIDs: Set<UUID> = []
        var missedTentacleIDs: Set<UUID> = []

        for tentacle in activeTentacles {
            let tPos = tentaclePosition(for: tentacle, at: now, in: gameSize)
            let tProgress = now.timeIntervalSince(tentacle.spawnedAt) / tentacle.fallDuration

            if tPos.y >= catchLineY && abs(tPos.x - elumiPos.x) <= 30 {
                hitTentacleIDs.insert(tentacle.id)
                jellyfishStingCount += 1
                feedbackPlayer.playTentacleSting()

                // Screen shake proportional to sting count
                withAnimation(.easeOut(duration: 0.08)) {
                    screenShakeOffset = jellyfishStingCount >= 2 ? 8 : 4
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeOut(duration: 0.12)) { screenShakeOffset = 0 }
                }

                if jellyfishStingCount >= 3 {
                    misses += 1
                    jellyfishStingCount = 0
                    // **Quick-Fix 2026-04-30** — Visuelles Feedback bei
                    // Quallen-Lebens-Verlust (vorher nur die kleineren
                    // Per-Sting-Shakes oben). User-Spec: Lebens-Verlust
                    // muss am Charakter sichtbar sein.
                    triggerLifeLossVisual()
                    feedbackPlayer.playSnackMiss()
                    resetCombo()
                }
            }

            if tProgress > 1.1 {
                missedTentacleIDs.insert(tentacle.id)
            }
        }

        activeTentacles.removeAll { hitTentacleIDs.contains($0.id) || missedTentacleIDs.contains($0.id) }
    }

    func runGameLoops() async {
        guard await MainActor.run(body: { !self.showingStartOverlay }) else { return }

        await MainActor.run {
            resetGameState()
            // Show "Runde 1 / Ready?" at game start
            showingRoundBanner = true
            roundBannerPhase = 1
            readyBlinkVisible = true
        }

        // Ready blink sequence
        for _ in 0..<3 {
            await MainActor.run { withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = false } }
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run { withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = true } }
            try? await Task.sleep(for: .milliseconds(300))
        }
        try? await Task.sleep(for: .milliseconds(200))
        await MainActor.run { showingRoundBanner = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while await MainActor.run(body: { self.isPlaying && !self.isGameOver }) {
                    let delay = await MainActor.run { currentSpawnDelay() }
                    // **Bugfix „Rapid-Fire-Spawn beim Restart"**: vorher
                    // `try? await Task.sleep(...)` — das schluckt jede
                    // CancellationError. Wenn `.task(id: gameSeed)`
                    // beim Start einer neuen Runde die vorherige Task
                    // cancelt, war der Sleep sofort zurück, die
                    // while-Bedingung `isPlaying` noch `true` aus dem
                    // Frisch-Start → Schleife hämmerte `spawnSnack()`
                    // ohne Delay und 50–80 Items fielen gleichzeitig.
                    // Jetzt: CancellationError bricht die Schleife
                    // sauber ab.
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                    guard await MainActor.run(body: { self.isPlaying && !self.isGameOver }) else { break }
                    let isBannerUp = await MainActor.run { self.showingRoundBanner }
                    guard !isBannerUp else { continue }
                    await MainActor.run {
                        // Phase 7.6 Bug-Fix (User: „in fischrunde
                        // KEINE Bubble spawnen"): während der
                        // Bonus-/Fischrunde werden **keine** Snacks /
                        // Power-Ups / Bubbles gespawnt. Nur der
                        // Fisch-Spawn aus `beginBonusFishSpawning`
                        // läuft in dieser Phase.
                        if !isBonusRound {
                            spawnSnack()
                            // Jellyfish spawn check
                            let config = ArcadeRoundConfig(round: round)
                            if activeJellyfish == nil && config.jellyfishChance > 0 {
                                if Double.random(in: 0...1) < config.jellyfishChance {
                                    spawnJellyfish()
                                }
                            }
                        }
                    }
                }
            }

            group.addTask {
                while await MainActor.run(body: { self.isPlaying && !self.isGameOver }) {
                    await MainActor.run {
                        updateGame(now: Date())
                    }
                    // Gleicher Cancel-Fix für den Update-Loop — ohne
                    // den würde das Frame-Update nach Task-Cancel mit
                    // 0 ms Delay spinnen, was CPU frisst und je nach
                    // Timing Ghost-Updates produziert.
                    do {
                        try await Task.sleep(for: .milliseconds(33))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                }
            }
        }
    }
}

