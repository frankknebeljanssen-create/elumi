import SwiftUI

extension ElumiArcadeGameView {
    func snackRenderSize(for snack: ElumiArcadeSnackState) -> CGFloat {
        let baseSize: CGFloat
        switch snack.kind {
        case .wuermchen:
            baseSize = 32
        case .wasserfloh:
            baseSize = 42
        case .algenkugel:
            baseSize = 26
        case .bonusblase:
            baseSize = 28
        case .saugglocke:
            baseSize = 38
        case .slowMotionPotion:
            baseSize = 34
        case .falseElumi:
            baseSize = 46
        case .shieldBubble:
            // Power-Up-Spec: „1.5x–2x so groß wie Standard-Objekte"
            baseSize = 62
        }

        return baseSize * snack.renderScale
    }

    func spawnRenderScale(for kind: ElumiArcadeDropKind) -> CGFloat {
        switch kind {
        case .wuermchen:
            return CGFloat.random(in: 1.0...1.45)
        case .wasserfloh:
            return CGFloat.random(in: 1.0...2.0)
        case .algenkugel:
            return CGFloat.random(in: 1.0...2.0)
        case .bonusblase:
            return 1.0
        case .saugglocke:
            return 1.0
        case .slowMotionPotion:
            return 1.0
        case .falseElumi:
            return 1.0
        case .shieldBubble:
            return 1.0
        }
    }

    func snackPoints(for kind: ElumiArcadeDropKind) -> Int {
        switch kind {
        case .wuermchen:
            return 10
        case .wasserfloh:
            return 14
        case .algenkugel:
            return 18
        case .bonusblase:
            return 0
        case .saugglocke:
            return 0
        case .slowMotionPotion:
            return 0
        case .falseElumi:
            return 0
        case .shieldBubble:
            return 0
        }
    }

    func currentSpawnDelay() -> Double {
        let base = ArcadeRoundConfig(round: round).spawnDelay
        return hasActiveSlowMotion() ? base * 1.8 : base
    }

    func currentFallDuration() -> Double {
        ArcadeRoundConfig(round: round).fallDuration
    }

    func elumiPositionX(in width: CGFloat) -> CGFloat {
        let minX: CGFloat = 42
        let maxX = max(minX, width - 42)
        return minX + ((maxX - minX) * elumiX)
    }

    func elumiPositionY(in height: CGFloat) -> CGFloat {
        guard isBonusRound else { return height - 118 }
        let minY: CGFloat = 80
        let maxY = max(minY, height - 80)
        return minY + ((maxY - minY) * elumiY)
    }

    func updateElumiPosition(to x: CGFloat, width: CGFloat) {
        let minX: CGFloat = 42
        let maxX = max(minX, width - 42)
        let clampedX = min(max(x, minX), maxX)
        let normalized = (clampedX - minX) / max(maxX - minX, 1)
        elumiX = normalized
    }

    func updateElumiPosition2D(to point: CGPoint, in size: CGSize) {
        updateElumiPosition(to: point.x, width: size.width)
        let minY: CGFloat = 80
        let maxY = max(minY, size.height - 80)
        let clampedY = min(max(point.y, minY), maxY)
        elumiY = (clampedY - minY) / max(maxY - minY, 1)
    }

    // ── Jellyfish ──

    func jellyfishPosition(for jelly: JellyfishState, at date: Date, in size: CGSize) -> CGPoint {
        let elapsed = date.timeIntervalSince(jelly.spawnedAt)
        let progress = CGFloat(elapsed / jelly.speed)

        let startX: CGFloat = jelly.fromLeft ? -60 : size.width + 60
        let endX: CGFloat = jelly.fromLeft ? size.width + 60 : -60
        let x = startX + (endX - startX) * progress

        let baseY = jelly.normalizedY * size.height
        let y = baseY + sin(elapsed * 1.2 + jelly.wobblePhase) * 25

        return CGPoint(x: x, y: y)
    }

    func tentaclePosition(for tentacle: TentacleDropState, at date: Date, in size: CGSize) -> CGPoint {
        let elapsed = date.timeIntervalSince(tentacle.spawnedAt)
        let progress = CGFloat(elapsed / tentacle.fallDuration)

        let x = tentacle.normalizedX * size.width + sin(elapsed * 2.5) * tentacle.wobbleAmplitude * size.width
        let endY = size.height - 100
        let y = tentacle.startY + (endY - tentacle.startY) * min(progress, 1.0)

        return CGPoint(x: x, y: y)
    }

    // MARK: - Ambient-Sea-Creature Position

    /// Position für die Ambient-Kreatur (Fisch-Schwarm / Hai).
    /// **Organische Schwimmbewegung** (Realismus-Pass 2):
    ///
    ///   • **Tempovariation** (X) — der x-Progress ist nicht streng
    ///     linear, sondern moduliert mit ±1.5 % über eine sehr
    ///     langsame 0.4-Hz-Sinuswelle. Effekt: der Hai wirkt nicht
    ///     wie auf Schienen, sondern beschleunigt/verlangsamt sanft.
    ///   • **Dreifach-Sinus** (Y) — primäre Schwimmkurve, langsame
    ///     Grunddrift UND eine **nicht-rationale** Tertiär-Komponente
    ///     (Faktor √3 ≈ 1.732). Da √3 irrational ist, wird das Muster
    ///     nie periodisch → wirkt natürlich, kein „perfekter Sinus".
    ///   • **Hai gedämpft**: kleinere Y-Amplitude (5 statt 7 pt), da
    ///     die Body-Welle im SharkView die sichtbare Bewegung übernimmt.
    ///
    /// Die Werte für `verticalVelocity` werden analytisch aus
    /// denselben Komponenten in `ambientSeaCreatureVerticalVelocity`
    /// abgeleitet — beide Funktionen müssen identische Parameter haben.
    func ambientSeaCreaturePosition(
        for creature: AmbientSeaCreatureState,
        at date: Date,
        in size: CGSize
    ) -> CGPoint {
        let elapsed = date.timeIntervalSince(creature.spawnedAt)
        let baseProgress = CGFloat(elapsed / creature.speed)

        // **Tempo-Variation** — sehr langsame ±1.5 %-Modulation auf
        // dem x-Progress. Macht aus konstantem Vorbeiziehen ein
        // organisches „Driften". Phase-Offset via `wobblePhase`,
        // damit zwei gleichzeitig spawnende Tiere nicht synchron
        // beschleunigen.
        let tempoJitter = 0.015 * sin(elapsed * 0.4 + creature.wobblePhase * 0.5)
        let progress = baseProgress + CGFloat(tempoJitter)

        let startX: CGFloat = creature.fromLeft ? -80 : size.width + 80
        let endX: CGFloat = creature.fromLeft ? size.width + 80 : -80
        let x = startX + (endX - startX) * progress

        let baseY = creature.normalizedY * size.height
        let phase = creature.wobblePhase

        // Kreatur-spezifische Frequenzen: Hai langsamer + ruhiger,
        // Fisch-Schwarm lebhafter. **Hai-Y-Amplitude reduziert**
        // (Spec „leicht dämpfen"), weil die Body-Welle des SharkView
        // bereits Bewegung beisteuert — wir wollen keine doppelte
        // Sichtbarkeit der gleichen Bewegung.
        let isShark = creature.kind == .shark
        let primaryFreq: Double = isShark ? 0.9 : 1.4
        let primaryAmp: CGFloat = isShark ? 5 : 14
        // Sekundäre Grunddrift — viel langsamer, kleinere Amplitude.
        let secondaryFreq: Double = primaryFreq * 0.22
        let secondaryAmp: CGFloat = primaryAmp * 0.45
        // **Tertiäre Mikro-Drift** mit nicht-rationaler Frequenz-
        // beziehung (√3 ≈ 1.732). Das macht das Gesamtmuster
        // **nicht periodisch** — wirkt natürlich, kein erkennbarer
        // Wiederholungs-Rhythmus.
        let tertiaryFreq: Double = primaryFreq * 1.732
        let tertiaryAmp: CGFloat = primaryAmp * 0.18

        let y = baseY
            + CGFloat(sin(elapsed * primaryFreq + phase)) * primaryAmp
            + CGFloat(sin(elapsed * secondaryFreq)) * secondaryAmp
            + CGFloat(sin(elapsed * tertiaryFreq + phase * 0.7)) * tertiaryAmp

        return CGPoint(x: x, y: y)
    }

    /// Y-Geschwindigkeit (analytische Ableitung der Y-Position) —
    /// wird vom SharkView genutzt, um den (sehr dezent gewordenen)
    /// Body-Tilt an die Schwimmrichtung zu koppeln. Muss alle drei
    /// Sinus-Komponenten aus `ambientSeaCreaturePosition` enthalten,
    /// sonst stimmt der Tilt nicht zur sichtbaren Bewegung.
    func ambientSeaCreatureVerticalVelocity(
        for creature: AmbientSeaCreatureState,
        at date: Date
    ) -> CGFloat {
        let elapsed = date.timeIntervalSince(creature.spawnedAt)
        let phase = creature.wobblePhase
        let isShark = creature.kind == .shark
        let primaryFreq: Double = isShark ? 0.9 : 1.4
        let primaryAmp: CGFloat = isShark ? 5 : 14
        let secondaryFreq: Double = primaryFreq * 0.22
        let secondaryAmp: CGFloat = primaryAmp * 0.45
        let tertiaryFreq: Double = primaryFreq * 1.732
        let tertiaryAmp: CGFloat = primaryAmp * 0.18
        // d/dt [sin(w*t + phi)] = w * cos(w*t + phi)
        let dy1 = CGFloat(primaryFreq   * cos(elapsed * primaryFreq + phase))         * primaryAmp
        let dy2 = CGFloat(secondaryFreq * cos(elapsed * secondaryFreq))               * secondaryAmp
        let dy3 = CGFloat(tertiaryFreq  * cos(elapsed * tertiaryFreq + phase * 0.7)) * tertiaryAmp
        return dy1 + dy2 + dy3
    }

    func fishPosition(for fish: BonusFishState, at date: Date, in size: CGSize) -> CGPoint {
        let elapsed = date.timeIntervalSince(fish.spawnedAt)
        let progress = CGFloat(elapsed / fish.speed)

        let startX: CGFloat = fish.fromLeft ? -30 : size.width + 30
        let endX: CGFloat = fish.fromLeft ? size.width + 30 : -30
        let x = startX + (endX - startX) * progress

        let baseY = 80 + (size.height - 160) * fish.normalizedY
        let wobble = sin(elapsed * 5.0 + fish.wobblePhase) * 35
        let y = baseY + CGFloat(wobble)

        return CGPoint(x: x, y: y)
    }

    func snackProgress(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        CGFloat(max(0, date.timeIntervalSince(snack.spawnedAt) / snack.fallDuration))
    }

    func snackPosition(for snack: ElumiArcadeSnackState, at date: Date, in size: CGSize) -> CGPoint {
        let progress = snackProgress(for: snack, at: date)
        let elapsed = date.timeIntervalSince(snack.spawnedAt)

        // **Schutz-Bubble Sonder-Position** (User-Feedback „Bubble
        // bleibt nach Spawn viel zu lange stehen, muss sich sofort
        // bewegen" + „Bubble umschließt Elumi nicht wenn eingesammelt"):
        //
        //   • Phase 1 — ganz kurzer „Pop"-Moment (ersten 8 %):
        //     Y bleibt am idleY im oberen Drittel, damit das Aufploppen
        //     überhaupt sichtbar ist, bevor der Sink startet.
        //   • Phase 2 — sofortiger Sink bis zur Catch-Line (8–100 %):
        //     Y driftet kontinuierlich runter bis **unter** catchLineY,
        //     damit die Bubble einsammelbar ist (vorher war targetY
        //     HÖHER als catchLineY, Bubble war nie catchable — das war
        //     der Grund, warum der Schild nie aktiv wurde).
        //   • Phase 3 — Ende: wird in `updateGame` durch
        //     `progress >= 1.04` als vorbei behandelt (kein Miss-Count).
        //
        // `catchLineY = size.height - 158` ist die Mindest-Y für
        // `isCatchable`. `targetY = size.height - 130` liegt **unter**
        // dieser Linie (höherer Y-Wert in iOS-Koords = tiefer im
        // Screen), damit die Bubble-Spitze die Zone durchläuft und
        // der horizontalDistance ≤ 34-Check triggern kann.
        if snack.kind == .shieldBubble {
            // **User-Feedback „Bubble muss sich sofort bewegen"**:
            // Sink startet schon bei 2 % Progress (~140 ms) —
            // praktisch sofort nach dem Pop-In-Moment. Horizontale
            // Sinus-Drift gibt der Bubble ein natürliches „Schweben"-
            // Gefühl, statt starrer Bahn.
            let anchorX = snack.laneX * size.width
            // Horizontaler Sinus-Drift: leichter, langsamer Schwung
            // (±10 pt) — wirkt wie Luftströmung, nicht wie Wobble.
            let horizontalDrift = sin(elapsed * 0.55) * 10.0
            let idleY = size.height * 0.22
            let targetY = size.height - 130
            let sinkProgress = max(0, min(1, (progress - 0.02) / 0.98))
            let baseY = idleY + (targetY - idleY) * sinkProgress
            // Vertikales Atmen als Zusatz — sehr subtil, damit die
            // Bubble lebendig wirkt ohne vom Pfad abzuweichen.
            let wobbleY = sin(elapsed * 1.3) * 3.0
            return CGPoint(x: anchorX + horizontalDrift, y: baseY + wobbleY)
        }

        let topY: CGFloat = -28
        let bottomY = size.height - 144
        let baseY = topY + ((bottomY - topY) * progress)
        let motionOffset = arcadeMotionOffset(for: snack, at: date, in: size)

        let x: CGFloat
        if snack.wobbleAmplitude >= 0.08 {
            // Querschläger: bounce off screen edges using triangle wave
            let minX: CGFloat = 30
            let maxX = size.width - 30
            let range = maxX - minX
            let rawX = snack.laneX * size.width + sin(elapsed * snack.wobbleFrequency) * snack.wobbleAmplitude * size.width * 2
            // Reflect into [minX, maxX] range
            let normalized = ((rawX - minX) / range).truncatingRemainder(dividingBy: 2.0)
            let reflected = normalized < 0 ? -normalized : normalized
            x = minX + (reflected > 1 ? 2 - reflected : reflected) * range
        } else {
            // Normal snack: simple wobble
            let baseX = snack.laneX * size.width
            let wobble = sin(elapsed * snack.wobbleFrequency) * snack.wobbleAmplitude * size.width
            x = baseX + wobble
        }

        return CGPoint(x: x + motionOffset.width, y: baseY + motionOffset.height)
    }

    func arcadeMotionOffset(for snack: ElumiArcadeSnackState, at date: Date, in size: CGSize) -> CGSize {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            let horizontal = sin(elapsed * 4.8 + snack.motionPhase) * size.width * 0.035 * snack.renderScale
            let vertical = sin(elapsed * 6.2 + snack.motionPhase * 0.8) * 10 * snack.renderScale
            return CGSize(width: horizontal, height: vertical)
        case .wuermchen:
            let horizontal = sin(elapsed * 3.9 + snack.motionPhase) * size.width * 0.022 * snack.renderScale
            let vertical = sin(elapsed * 9.8 + snack.motionPhase * 1.3) * 6 * snack.renderScale
            return CGSize(width: horizontal, height: vertical)
        default:
            return .zero
        }
    }

    func arcadeScaleX(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            let facing: CGFloat = cos(elapsed * 4.8 + snack.motionPhase) >= 0 ? -1 : 1
            let pulse = 0.96 + (0.06 * abs(sin(elapsed * 6.4 + snack.motionPhase)))
            return facing * pulse
        case .wuermchen:
            return 0.92 + (0.12 * ((sin(elapsed * 10.2 + snack.motionPhase) + 1) / 2))
        default:
            return 1
        }
    }

    func arcadeScaleY(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            return 0.97 + (0.05 * abs(cos(elapsed * 5.3 + snack.motionPhase)))
        case .wuermchen:
            return 1.08 - (0.12 * ((sin(elapsed * 10.2 + snack.motionPhase) + 1) / 2))
        default:
            return 1
        }
    }

    func arcadeSnackTilt(for snack: ElumiArcadeSnackState, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            return sin(elapsed * 5.2 + snack.motionPhase) * 8
        case .wuermchen:
            return sin(elapsed * 10.8 + snack.motionPhase) * 14 + cos(elapsed * 3.6 + snack.motionPhase) * 4
        default:
            return 0
        }
    }

    func arcadeBubble(
        seed: CGFloat,
        size: CGFloat,
        drift: CGFloat,
        duration: Double,
        delay: Double,
        time: Double
    ) -> some View {
        let phase = positiveFraction((time - delay) / duration)
        let x = seed * gameSize.width + (sin(phase * .pi * 2) * drift)
        let y = gameSize.height + 30 - ((gameSize.height + 60) * phase)

        return Circle()
            .fill(Color.white.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .position(x: x, y: y)
    }

    func positiveFraction(_ value: Double) -> CGFloat {
        let fraction = value.truncatingRemainder(dividingBy: 1)
        return CGFloat(fraction >= 0 ? fraction : fraction + 1)
    }
}

