import SwiftUI

// MARK: - Standalone Icon-Views (überall in der App nutzbar)

/// Echter Elumi-Avatar — gleiches Asset wie im Footer-Button und im Spiel.
struct ArcadeElumiAvatar: View {
    let size: CGFloat
    var withShadow: Bool = true

    var body: some View {
        Image("SplashCharacter")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: withShadow ? .black.opacity(0.16) : .clear,
                    radius: withShadow ? 4 : 0,
                    x: 0,
                    y: withShadow ? 2 : 0)
    }
}

/// Elumi-Freund (blauer „falscher" Elumi). Statische Version des hazardElumiIcon.
struct ArcadeHazardElumiAvatar: View {
    let size: CGFloat
    private let glowColor = Color(red: 0.2, green: 0.6, blue: 0.9)

    var body: some View {
        let friendSize = size * 1.1
        ZStack {
            Circle()
                .fill(glowColor.opacity(0.22))
                .frame(width: friendSize * 1.15, height: friendSize * 1.15)
                .blur(radius: 5)

            Image("SplashCharacter")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: friendSize * 0.92, height: friendSize * 0.92)
                .saturation(0.85)
                .hueRotation(.degrees(-80))
                .brightness(0.05)
                .clipShape(Circle())

            Circle()
                .fill(Color.cyan)
                .frame(width: friendSize * 0.20, height: friendSize * 0.20)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: friendSize * 0.11, weight: .bold))
                        .foregroundStyle(.white)
                )
                .offset(x: friendSize * 0.3, y: -friendSize * 0.28)
        }
        .shadow(color: glowColor.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}

/// Saugglocke — statische Version des suctionCupIcon.
struct ArcadeSuctionIconStandalone: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.warning.opacity(0.16))
                .frame(width: size * 1.2, height: size * 1.2)
                .blur(radius: 6)

            Circle()
                .stroke(AppTheme.Colors.warning.opacity(0.46), lineWidth: 1.6)
                .frame(width: size * 1.08, height: size * 1.08)

            Capsule()
                .fill(AppTheme.Colors.textPrimary.opacity(0.92))
                .frame(width: size * 0.16, height: size * 0.34)
                .offset(y: -size * 0.16)

            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(AppTheme.Colors.warning)
                .frame(width: size * 0.38, height: size * 0.18)
                .offset(y: -size * 0.03)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.elumiMint.opacity(0.88),
                            AppTheme.Colors.primary.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.86, height: size * 0.44)
                .overlay(
                    Ellipse()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
                )
                .offset(y: size * 0.12)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.18, weight: .black))
                .foregroundStyle(Color.white.opacity(0.92))
                .offset(x: size * 0.18, y: -size * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.Colors.warning.opacity(0.28), radius: 12, x: 0, y: 5)
    }
}

/// Zeitlupe-Trank — statische Version des slowMotionPotionIcon.
struct ArcadeSlowMotionIconStandalone: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            Color.blue.opacity(0.85),
                            Color.blue.opacity(0.5)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1.5)
                )

            Text("🧪")
                .font(.system(size: size * 0.48))

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(x: -size * 0.16, y: -size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.blue.opacity(0.4), radius: 14, x: 0, y: 4)
    }
}

extension ElumiArcadeGameView {
    @ViewBuilder
    func fallingObjectView(for snack: ElumiArcadeSnackState, at date: Date) -> some View {
        let renderSize = snackRenderSize(for: snack)
        switch snack.kind {
        case .wuermchen, .wasserfloh, .algenkugel:
            if let snackKind = snack.kind.snackKind {
                ElumiSnackIcon(snackKind, size: renderSize)
                    .scaleEffect(
                        x: arcadeScaleX(for: snack, at: date),
                        y: arcadeScaleY(for: snack, at: date)
                    )
                    .rotationEffect(.degrees(arcadeSnackTilt(for: snack, at: date)))
            }
        case .bonusblase:
            bonusBubbleIcon(size: renderSize, at: date)
        case .saugglocke:
            suctionCupIcon(size: renderSize, at: date)
        case .slowMotionPotion:
            slowMotionPotionIcon(size: renderSize, at: date)
        case .falseElumi:
            hazardElumiIcon(size: renderSize, at: date)
        case .shieldBubble:
            // **Schutz-Bubble**: weiche Seifenblase mit Farbpalette
            // aus `ArcadePowerUps.configs[.shieldBubble]` (#8FD3FF /
            // #D9F4FF / #BDEBFF). Scale-In beim Spawn + subtiles
            // „Atmen" — siehe detailliertes Design im Overlay-File.
            shieldBubbleSpawnIcon(size: renderSize, at: date)
        }
    }

    /// Spawn-/Idle-Darstellung der Schutz-Bubble im Spielfeld.
    /// Wrapped das wiederverwendbare `SchutzBubbleView` — damit die
    /// gleiche echte-Seifenblasen-Optik auch im Aktiv-Zustand rund um
    /// den Spieler greift (siehe `shieldBubbleActiveOverlay`).
    @ViewBuilder
    func shieldBubbleSpawnIcon(size: CGFloat, at date: Date) -> some View {
        SchutzBubbleView(size: size, spawnMode: .popIn)
    }

    /// Aktiv-Overlay, das sich um den Spieler legt, solange die
    /// Schutz-Bubble läuft. Nutzt dieselbe Soap-Bubble-Optik wie der
    /// Spawn-Drop, bloß größer (um den Charakter herum) und mit:
    ///   • Snap-In-Animation beim Pickup (Spring 0.4 → 1.0 Overshoot)
    ///   • Ripple-Overlay bei jeder Kollision (expandierender Kreis)
    ///   • End-Fade in den letzten 400 ms (scale +15 %, opacity → 0)
    @ViewBuilder
    func shieldBubbleActiveOverlay(at date: Date) -> some View {
        let endDate = shieldBubbleEndsAt
        let remaining = endDate.map { $0.timeIntervalSince(date) } ?? 0

        // **Warnphase** (Phase 7.6): in den letzten 2 Sekunden vor
        // Ablauf blinkt die Bubble mit zunehmender Frequenz (3 → 9 Hz).
        // Ergibt 6–8 klar sichtbare Blinks über den Warn-Zeitraum.
        // Die kumulative Phase wird analytisch berechnet (lineare
        // Frequenz-Rampe → Phase = ∫ω dt = ½(ω₁+ω₂)·t), damit die
        // Sinus-Welle durchgehend glatt bleibt.
        let warningDuration: TimeInterval = 2.0
        let warningProgress: Double = {
            guard remaining > 0, remaining < warningDuration else { return 0 }
            return 1.0 - (remaining / warningDuration)
        }()
        let warnOpacity: Double = {
            guard warningProgress > 0 else { return 1.0 }
            let elapsed = warningDuration - remaining
            let startHz: Double = 3.0
            let endHz: Double = 9.0
            let avgHz = startHz + 0.5 * (endHz - startHz) * (elapsed / warningDuration)
            let phase = 2 * Double.pi * avgHz * elapsed
            return 0.4 + 0.6 * (0.5 + 0.5 * sin(phase))
        }()

        // **End-Fade** (letzte 0.3 s): kurzer Scale-Up + Fade-Out,
        // damit der Ablauf nicht nur still endet, sondern einen
        // sichtbaren Abschluss bekommt (Scale 1.0 → 1.25).
        let endFadeAmount: Double = {
            guard remaining < 0.3 else { return 0 }
            return max(0, min(1, 1 - remaining / 0.3))
        }()
        let opacity = (1.0 - endFadeAmount) * warnOpacity
        let endScale = 1.0 + 0.25 * CGFloat(endFadeAmount)

        // Ripple-Progress aus Zeit-Differenz zum letzten Impact-Event.
        // Dauer 0.32 s — sichtbar, aber nicht dominant.
        let rippleDuration: TimeInterval = 0.32
        let rippleProgress: Double = {
            guard let rippleStart = shieldBubbleRippleAt else { return 1.0 }
            let elapsed = date.timeIntervalSince(rippleStart)
            if elapsed < 0 || elapsed >= rippleDuration { return 1.0 }
            return elapsed / rippleDuration
        }()

        ZStack {
            SchutzBubbleView(size: 116, spawnMode: .snapIn)

            // Ripple-Kreis: von Bubble-Rand (116 pt) nach außen
            // expandierend (bis ~150 pt), gleichzeitig fade-out.
            // Nur sichtbar während 0 ≤ progress < 1.
            if rippleProgress < 1.0 {
                let scale = 1.0 + 0.35 * CGFloat(rippleProgress)
                let ringOpacity = 0.55 * (1.0 - rippleProgress)
                Circle()
                    .stroke(Color(hex: "#BDEBFF").opacity(ringOpacity), lineWidth: 2.2)
                    .frame(width: 116, height: 116)
                    .scaleEffect(scale)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(endScale)
        .opacity(opacity)
    }
}

// MARK: - SchutzBubbleView (Soap-Bubble Visualisierung)

/// **Hochwertige Seifenblasen-Visualisierung**, komplett in SwiftUI
/// gerendert — keine Asset-Dateien nötig.
///
/// Bringt per Schicht-System (`ZStack`) den 3D-Eindruck, Transparenz,
/// Reflexion, Irisierung und Rand-Dunkelung auf den Screen, die man
/// sonst nur mit einem PNG-Sprite oder Shader erreicht.
///
/// **Layer-Aufbau** (bottom → top):
///   1. **Body-Gradient** — off-center RadialGradient vom weißlichen
///      Highlight-Zentrum zur leicht dunkleren Rim → erzeugt Volumen
///   2. **Rim-Darkening** — zweiter RadialGradient nur auf dem
///      Außenring, sehr dezent (Fresnel-artige Kante)
///   3. **Irisierung** — AngularGradient mit Pastell-Regenbogen-
///      Farben, rotiert langsam, blendMode(.screen) für Additiv-Feel
///   4. **Rim-Light** — dünne, irisierende Ring-Linie
///   5. **Primär-Highlight** — elongiertes weißes Oval oben links,
///      weichgezeichnet → Glanzlicht einer Kugel
///   6. **Sekundär-Highlight** — kleiner Punkt auf der gegenüber-
///      liegenden Seite → zweiter Lichtpunkt verstärkt 3D-Eindruck
///
/// **Animation**:
///   • Irisierungsphase rotiert einmal alle 18 s → farbliches
///     Schimmern ohne Unruhe
///   • Breath-Scale 1.00 ↔ 1.02 alle 2.4 s → „lebendige Spannung"
///
/// Funktioniert auf dunklem Hintergrund. Keine festen Hintergrund-
/// Farben werden gezeichnet; die Bubble ist überall transparent.
struct SchutzBubbleView: View {
    /// Gesamtdurchmesser der Bubble (Breite = Höhe).
    let size: CGFloat

    /// Spawn-Animation-Modus.
    /// • `.popIn` — Bubble ploppt mit Scale 0.65 → 1.0 auf (für den
    ///   Drop, der im oberen Drittel erscheint).
    /// • `.snapIn` — Bubble „schnappt" von 0.40 mit leichtem
    ///   Overshoot auf 1.05 → 1.0 ein (für den Aktiv-Zustand um den
    ///   Spieler, direkt nach Pickup).
    /// • `.none` — ohne Spawn-Animation, direkt auf 1.0 (Debug / Tests).
    enum SpawnMode {
        case popIn
        case snapIn
        case none
    }

    var spawnMode: SpawnMode = .popIn

    // Animations-State — Phase-Werte laufen in `.repeatForever`-
    // Loops, während die View lebt. SwiftUI cache't die Animation,
    // sodass der Overhead minimal ist (keine Body-Neuberechnung pro
    // Frame).
    @State private var iridescencePhase: Double = 0
    @State private var breathScale: CGFloat = 1.0
    /// Start-Skalierung: wird in `.onAppear` auf 1.0 animiert. Bei
    /// `.popIn` easeOut 200 ms, bei `.snapIn` Spring mit Overshoot.
    @State private var spawnScale: CGFloat = 1.0

    // Farbtupel — drei Basis-Blautöne aus der User-Spec-Palette +
    // sehr dezente Pastell-Regenbogen-Töne für die Irisierung.
    private let cyan = Color(hex: "#BDEBFF")   // Akzent
    private let softCyan = Color(hex: "#D9F4FF") // Sekundär (hell)
    private let skyBlue = Color(hex: "#8FD3FF") // Primär

    // Irisierungs-Palette — **extrem subtil**, höchste Opacity 0.18.
    private let irisColors: [Color] = [
        Color(hex: "#FFB6E6"),  // pink
        Color(hex: "#BDEBFF"),  // cyan
        Color(hex: "#FFF7B6"),  // zitrone
        Color(hex: "#D9B6FF"),  // lavendel
        Color(hex: "#B6FFE0"),  // mint
        Color(hex: "#FFB6E6")   // loop zurück
    ]

    var body: some View {
        ZStack {
            // 1. Body — Off-center RadialGradient für Volumen
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: softCyan.opacity(0.42), location: 0.00),
                            .init(color: cyan.opacity(0.22),     location: 0.45),
                            .init(color: skyBlue.opacity(0.14),  location: 0.82),
                            .init(color: skyBlue.opacity(0.28),  location: 1.00)
                        ]),
                        center: UnitPoint(x: 0.34, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.56
                    )
                )

            // 2. Rim-Darkening — subtiler Schatten auf dem Außenring
            //    (Fresnel-Effekt: echte Kugeln sind an den Rändern
            //    leicht dichter/dunkler, weil man durch mehr Material
            //    schaut).
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.10)
                        ],
                        center: .center,
                        startRadius: size * 0.36,
                        endRadius: size * 0.50
                    )
                )

            // 3. Irisierung — AngularGradient, langsam rotierend,
            //    Additiv-Blending damit's wirkt wie Reflexionen auf
            //    der Oberfläche, nicht wie aufgemalte Farbflecken.
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: irisColors.map { $0.opacity(0.13) }),
                        center: .center,
                        angle: .degrees(iridescencePhase)
                    )
                )
                .blendMode(.screen)
                .mask(Circle())

            // 4. Rim-Light — sehr dünner, irisierend-schillernder
            //    Rand; beweglich entgegengesetzt zur Körper-Iris, damit
            //    das Schimmern lebendiger wirkt ohne hektisch zu sein.
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            cyan.opacity(0.55),
                            Color(hex: "#FFD1F0").opacity(0.4),
                            Color(hex: "#FFF4D1").opacity(0.3),
                            Color(hex: "#D9C8FF").opacity(0.4),
                            cyan.opacity(0.55)
                        ],
                        center: .center,
                        angle: .degrees(-iridescencePhase * 0.55)
                    ),
                    lineWidth: max(1.0, size * 0.018)
                )

            // 5. Primär-Highlight — weiches, elongiertes Oval oben
            //    links, leicht gedreht + geblurrt → klassische Kugel-
            //    Lichtreflexion.
            Ellipse()
                .fill(Color.white.opacity(0.70))
                .frame(width: size * 0.28, height: size * 0.16)
                .rotationEffect(.degrees(-35))
                .offset(x: -size * 0.20, y: -size * 0.22)
                .blur(radius: max(1, size * 0.025))

            // 6. Sekundär-Highlight — kleiner gegenüberliegender
            //    Reflexpunkt, damit das Gehirn „runde, gewölbte
            //    Oberfläche" als Form erkennt (eine Kugel hat immer
            //    mehrere Lichtpunkte, nicht nur einen).
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.18, y: size * 0.22)
                .blur(radius: max(0.6, size * 0.015))
        }
        .frame(width: size, height: size)
        .scaleEffect(breathScale * spawnScale)
        // Weiches Glow/Shadow rund um die Bubble — simuliert
        // atmosphärische Streuung, macht sie in der Szene „leuchtend".
        .shadow(color: skyBlue.opacity(0.35), radius: size * 0.14, x: 0, y: 0)
        .onAppear {
            // Initial-Scale abhängig vom Spawn-Modus — danach
            // zielorientiert animieren.
            switch spawnMode {
            case .popIn:
                // **Materialisierungs-Animation** (User-Spec): kleiner
                // Kern (0.2) dehnt sich aus, kurzes Overshoot auf
                // 1.1, setzt bei 1.0. Spring mit dampingFraction < 1
                // erzeugt das Overshoot natürlich + weiches Settling.
                // Gesamtdauer ~280 ms — passt zur Spec 220-300 ms.
                spawnScale = 0.2
                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                    spawnScale = 1.0
                }
            case .snapIn:
                spawnScale = 0.40
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                    spawnScale = 1.0
                }
            case .none:
                spawnScale = 1.0
            }

            // Irisierungs-Rotation: einmal pro 18 s — so langsam, dass
            // sie kaum bewusst wahrgenommen wird, aber das Schimmern
            // nie stillsteht.
            withAnimation(.linear(duration: 18.0).repeatForever(autoreverses: false)) {
                iridescencePhase = 360
            }
            // Atmen: Scale 1.00 ↔ 1.02 über 2.4 s easeInOut.
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathScale = 1.02
            }
        }
    }
}

// MARK: - weitere ElumiArcadeGameView-Helper (nach SchutzBubbleView)

extension ElumiArcadeGameView {
    var arcadeSnackPointsHUD: some View {
        HStack(spacing: 6) {
            arcadePointsChip(kind: .wuermchen, value: snackPoints(for: .wuermchen))
            arcadePointsChip(kind: .wasserfloh, value: snackPoints(for: .wasserfloh))
            arcadePointsChip(kind: .algenkugel, value: snackPoints(for: .algenkugel))
        }
    }

    func arcadePointsChip(kind: ElumiArcadeDropKind, value: Int) -> some View {
        HStack(spacing: 4) {
            if let snackKind = kind.snackKind {
                ElumiSnackIcon(snackKind, size: kind == .wasserfloh ? 17 : 15)
            }
            Text("+\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppTheme.Colors.secondarySurface.opacity(0.92))
        .clipShape(Capsule())
    }

    func arcadeStatusChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.22))
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.38), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    func suctionCupIcon(size: CGFloat, at date: Date) -> some View {
        // **Spawn-Zustand** (Drop im Spielfeld): langsame Rotation
        // aktiv, Trichter zeigt nach unten. Pickup wechselt dann auf
        // `.docked`-Darstellung in der Elumi-Overlay-Position.
        return ArcadeSaugerFunnel(
            size: size,
            animationDate: date,
            energyIntensity: 1.0,
            phase: .spawning
        )
    }

    func slowMotionPotionIcon(size: CGFloat, at date: Date) -> some View {
        let pulse = 0.90 + (0.10 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 5.0)))

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            Color.blue.opacity(0.85),
                            Color.blue.opacity(0.5)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1.5)
                )

            Text("🧪")
                .font(.system(size: size * 0.48))

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(x: -size * 0.16, y: -size * 0.18)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .shadow(color: Color.blue.opacity(0.4), radius: 14, x: 0, y: 4)
    }

    func bonusBubbleIcon(size: CGFloat, at date: Date) -> some View {
        let pulse = 0.92 + (0.08 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 6.8)))

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            AppTheme.Colors.warning.opacity(0.96),
                            AppTheme.Colors.primary.opacity(0.78)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1.2)
                )

            Image(systemName: "star.fill")
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(Color.white)

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: -size * 0.18, y: -size * 0.2)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .shadow(color: AppTheme.Colors.warning.opacity(0.34), radius: 12, x: 0, y: 4)
    }

    func hazardElumiIcon(size: CGFloat, at date: Date) -> some View {
        let friendSize = size * 1.1
        let pulse = 0.94 + (0.06 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 5.0)))
        let glowColor = Color(red: 0.2, green: 0.6, blue: 0.9)

        return ZStack {
            // Blue glow
            Circle()
                .fill(glowColor.opacity(0.22))
                .frame(width: friendSize * 1.15, height: friendSize * 1.15)
                .blur(radius: 5)
                .scaleEffect(pulse)

            // Blue Elumi friend
            Image("SplashCharacter")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: friendSize * 0.92, height: friendSize * 0.92)
                .saturation(0.85)
                .hueRotation(.degrees(-80))
                .brightness(0.05)
                .clipShape(Circle())

            // Small blue heart badge
            Circle()
                .fill(Color.cyan)
                .frame(width: friendSize * 0.20, height: friendSize * 0.20)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: friendSize * 0.11, weight: .bold))
                        .foregroundStyle(.white)
                )
                .offset(x: friendSize * 0.3, y: -friendSize * 0.28)
        }
        .shadow(color: glowColor.opacity(0.35), radius: 10, x: 0, y: 4)
    }

    // ── Bonus Fish ──

    func bonusFishView(for fish: BonusFishState, at date: Date, in size: CGSize) -> some View {
        let elapsed = date.timeIntervalSince(fish.spawnedAt)
        let wobble = sin(elapsed * 4.0 + fish.wobblePhase) * 5

        let size = 28 * fish.renderScale

        return Text("🐟")
            .font(.system(size: size))
            .scaleEffect(x: fish.fromLeft ? -1 : 1, y: 1)
            .rotationEffect(.degrees(wobble))
            .shadow(color: .cyan.opacity(0.4), radius: 6, x: 0, y: 2)
    }

    // ── Jellyfish ──

    func jellyfishView(for jelly: JellyfishState, at date: Date, in size: CGSize) -> some View {
        let elapsed = date.timeIntervalSince(jelly.spawnedAt)
        let pulse = 0.85 + sin(elapsed * 2.0) * 0.15
        let tentaclePhases: [Double] = [0, 0.8, 1.6, 2.4, 3.2, 4.0, 4.8]

        return ZStack {
            // Outer glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 50
                    )
                )
                .frame(width: 80, height: 60)
                .scaleEffect(CGFloat(pulse) * 1.2)

            // Bell (dome)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.85, green: 0.5, blue: 1.0).opacity(0.7),
                            Color(red: 0.6, green: 0.2, blue: 0.9).opacity(0.5),
                            Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.25)
                        ],
                        center: .init(x: 0.4, y: 0.3),
                        startRadius: 2,
                        endRadius: 30
                    )
                )
                .frame(width: 52, height: 38)
                .scaleEffect(y: CGFloat(pulse))

            // Inner bell highlight
            Ellipse()
                .fill(Color.white.opacity(0.25))
                .frame(width: 24, height: 14)
                .offset(y: -6)
                .blur(radius: 2)

            // Tentacles
            ForEach(0..<7, id: \.self) { i in
                let phase = tentaclePhases[i]
                let baseX = CGFloat(i - 3) * 6
                let sway = sin(elapsed * 2.8 + phase) * 8
                let length: CGFloat = [40, 55, 48, 60, 45, 52, 38][i]

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.6),
                                Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: length)
                    .offset(x: baseX + CGFloat(sway), y: 18 + length * 0.5)
                    .rotationEffect(.degrees(sway * 0.4), anchor: .top)
            }
        }
        .opacity(0.88)
        .shadow(color: Color.purple.opacity(0.5), radius: 12, x: 0, y: 4)
        .scaleEffect(x: jelly.fromLeft ? 1 : -1, y: 1)
    }

    func fallingTentacleView(for tentacle: TentacleDropState, at date: Date) -> some View {
        let elapsed = date.timeIntervalSince(tentacle.spawnedAt)
        let progress = elapsed / tentacle.fallDuration
        let pulse = 0.8 + sin(elapsed * 5.0) * 0.2
        let sway = sin(elapsed * 3.0) * 6

        return ZStack {
            // Glow
            Capsule()
                .fill(Color(red: 0.2, green: 0.9, blue: 0.3).opacity(0.3))
                .frame(width: 12, height: 36)
                .blur(radius: 4)
                .scaleEffect(CGFloat(pulse) * 1.1)

            // Tentacle body
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.7, green: 0.2, blue: 1.0).opacity(0.8),
                            Color(red: 0.1, green: 0.9, blue: 0.3).opacity(0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5, height: 28 + CGFloat(progress) * 8)

            // Poison droplet tip
            Circle()
                .fill(Color(red: 0.1, green: 1.0, blue: 0.3).opacity(0.6))
                .frame(width: 8, height: 8)
                .offset(y: 14 + CGFloat(progress) * 4)
        }
        .rotationEffect(.degrees(sway * 0.5))
        .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.3).opacity(0.5), radius: 6)
    }
}

// MARK: - AmbientSeaCreatureView (Fish/Shark Event)

/// Dezent gerenderte Silhouette eines Fisch-Schwarms oder Hais —
/// schwimmt passiv durch den Screen, kein Gameplay-Einfluss. Ziel:
/// „Atmendes Unterwasser-Feeling" ohne das Spielgeschehen zu stören.
///
/// **Hai-Variante** (User-Spec „realistisches Visuell-Event"):
/// weicher, leicht realistischer Stil. Blau-Grau-Palette
/// (#6B8FA3 / #9FB8C9 / #D6E7F0). Größer als normale Objekte
/// (~2-3× Spielergröße). Im Hintergrund wirkend via Opacity 88 %
/// und leichter Blur. Keine Kollision — das passiert in `Layout.swift`
/// via `.allowsHitTesting(false)` auf dem Container.
struct AmbientSeaCreatureView: View {
    let creature: AmbientSeaCreatureState
    /// Aktuelle Game-Clock-Zeit (aus `TimelineView.context.date`). Wird
    /// für die organische Body-/Tail-Animation genutzt. Per-Frame-
    /// Parameter statt eigener `@State`, damit die Animation in
    /// perfekter Sync zur Position bleibt.
    let now: Date
    /// Vertikale Geschwindigkeit (aus `ambientSeaCreatureVerticalVelocity`).
    /// Positiv = absteigend, negativ = aufsteigend. Steuert den
    /// Body-Tilt — der Hai zeigt die Nase in Schwimmrichtung.
    let verticalVelocity: CGFloat

    // Palette aus der Hai-Spec
    private let sharkPrimary   = Color(hex: "#6B8FA3")
    private let sharkSecondary = Color(hex: "#9FB8C9")
    private let sharkAccent    = Color(hex: "#D6E7F0")

    var body: some View {
        switch creature.kind {
        case .shark:
            sharkView
        case .fishSchool:
            fishSchoolSilhouette
        }
    }

    /// **Refined Shark — Realismus-Pass 2** (User-Spec):
    ///   1. **Kopf ruhig** — kein „rotierendes Sprite" mehr. Whole-body-
    ///      Tilt drastisch reduziert (max ±5° statt ±12°), die sichtbare
    ///      Bewegung wandert in den Body als echte Wellenpropagation.
    ///   2. **Schwanz als Motor** — der Vortrieb kommt klar aus dem
    ///      Schwanz: stärkere Tail-Amplitude (18°), Body-Welle hat ihre
    ///      maximale Amplitude am Schwanzstiel.
    ///   3. **Stromlinienförmige Silhouette** — schlanker (Aspect ~4.5:1
    ///      statt ~3.3:1), spitze Schnauze, klare Sichelschwanzflosse,
    ///      markante Hai-Rückenflosse mit konkavem Hinterrand.
    ///   4. **Body-Welle** — `AnimatedSharkBodyShape` deformiert die
    ///      Silhouette intern: Wellen-Amplitude wächst mit `tailness^2.4`
    ///      → Kopf bleibt fast still, Welle wird zum Schwanz hin sichtbar.
    private var sharkView: some View {
        let bodyLength: CGFloat = 180   // länger und schlanker
        let bodyHeight: CGFloat = 40
        let elapsed = now.timeIntervalSince(creature.spawnedAt)

        // **Body-Tilt drastisch reduziert** (Spec „Kopf ruhiger" +
        // „kein drehendes Sprite"). Nur noch ein **sehr** dezenter
        // Schwimmrichtungs-Hinweis, max ±5°. Der Hai folgt seiner
        // Bahn, ohne dass die Bahn ihn rotiert.
        let tiltFactor: Double = 0.4
        let bodyTiltDegrees = Double(verticalVelocity) * tiltFactor
        let clampedTilt = max(-5, min(5, bodyTiltDegrees))

        // **Body-Welle** — wandert vom Kopf zum Schwanz, Amplitude
        // wächst dort an. Frequenz und räumliche Wellenlänge müssen
        // exakt zu denen von `AnimatedSharkBodyShape` passen, damit
        // der Tail-Follow-Offset (siehe unten) bündig sitzt.
        let waveFreq: Double = 1.1
        let bodyWavePhase = elapsed * waveFreq + creature.wobblePhase
        let bodyWaveSpatialFreq: Double = 0.65
        let bodyWaveMaxOffset: CGFloat = 5.0

        // **Tail-Follow-Offset** — Y-Position der Schwanzflossen-
        // Andockstelle, exakt nach derselben Formel wie in
        // `AnimatedSharkBodyShape` am Schwanzende (u=0, tailness=1).
        // Dadurch sitzt die Schwanzflosse bündig am wackelnden Body-
        // Schwanzstiel, **ohne eigene Rotation** — sie folgt nur
        // passiv mit. (User-Feedback: „Schwanz muss am Fisch dran sein,
        // darf nicht rotieren, lieber statisch.")
        let tailFollowY = bodyWaveMaxOffset *
            CGFloat(sin(bodyWavePhase + bodyWaveSpatialFreq * 2 * .pi))

        // **Mikro-Sway für Rücken-/Brustflosse** — kleine kohärente
        // Mit-Bewegung mit der Body-Welle an ihrer jeweiligen Position
        // (Rücken bei u≈0.50, Brust bei u≈0.65). Sehr schwach (max
        // ±1.6° / ±1.0°), nur zur visuellen Verbindung mit der Welle.
        let dorsalSwayDeg = 1.6 *
            sin(bodyWavePhase + 0.50 * bodyWaveSpatialFreq * 2 * .pi)
        let pectoralSwayDeg = 1.0 *
            sin(bodyWavePhase + 0.35 * bodyWaveSpatialFreq * 2 * .pi)

        return ZStack {
            // — Körper mit eingebauter Wellenpropagation —
            AnimatedSharkBodyShape(
                phase: bodyWavePhase,
                spatialFrequency: bodyWaveSpatialFreq,
                maxLateralOffset: bodyWaveMaxOffset
            )
            .fill(
                LinearGradient(
                    colors: [
                        sharkSecondary,           // oben heller (Rücken-Countershading)
                        sharkPrimary,             // mitte
                        sharkPrimary.opacity(0.82) // unten dunkler (Bauch-Schatten)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: bodyLength, height: bodyHeight)

            // — Rücken-Highlight — zartes helles Streif-Oval entlang
            //   des oberen Körpers für Volumen-Eindruck.
            Capsule()
                .fill(sharkAccent.opacity(0.45))
                .frame(width: bodyLength * 0.50, height: 2.4)
                .offset(x: -bodyLength * 0.04, y: -bodyHeight * 0.34)
                .blur(radius: 1.6)

            // — Rückenflosse — markante Hai-Form mit konkavem
            //   Hinterrand. Schwingt nur SEHR dezent mit der Body-
            //   Welle an Mid-Body-Phase (max ±1.6°).
            SharkDorsalFinShape()
                .fill(sharkPrimary)
                .frame(width: 26, height: 32)
                .rotationEffect(.degrees(-4 + dorsalSwayDeg))
                .offset(x: -bodyLength * 0.02, y: -bodyHeight * 0.92)

            // — Brustflosse — kleiner, unten vor der Körpermitte.
            Triangle()
                .fill(sharkPrimary.opacity(0.88))
                .rotationEffect(.degrees(200 + pectoralSwayDeg))
                .frame(width: 22, height: 14)
                .offset(x: bodyLength * 0.08, y: bodyHeight * 0.55)

            // — Schwanzflosse: sichelförmig (heterocercal), oberer
            //   Lobus dominanter, hinterer Rand leicht konkav.
            //   **STATISCH** in ihrer Eigenform — keine eigene Rotation.
            //   Sitzt mit ihrem Andockpunkt (rect.minX, rect.midY)
            //   exakt auf dem Body-Schwanzende (-bodyLength/2,
            //   tailFollowY). Frame-Center liegt 17 pt rechts vom
            //   Andockpunkt → offset.x = -bodyLength/2 + 17.
            CrescentTailShape()
                .fill(
                    LinearGradient(
                        colors: [sharkPrimary, sharkPrimary.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 40)
                .offset(x: -bodyLength * 0.50 + 17, y: tailFollowY)

            // — Kiemen-Linien — drei zarte Akzente auf der Kopfseite
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(sharkPrimary.opacity(0.55))
                        .frame(width: 5, height: 1.2)
                }
            }
            .offset(x: bodyLength * 0.30, y: -bodyHeight * 0.05)

            // — Auge — dezenter dunkler Punkt
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 3.0, height: 3.0)
                .offset(x: bodyLength * 0.40, y: -bodyHeight * 0.22)
        }
        // Body-Tilt — sehr dezent. Kein Sprite-Spin: der Körper
        // **folgt** der Bahn weich, er **wird** nicht von ihr gedreht.
        .rotationEffect(.degrees(clampedTilt))
        // Richtung: Shapes sind orientiert „Schnauze nach rechts".
        // Wenn der Hai von rechts nach links schwimmt → horizontal
        // spiegeln, damit die Schnauze in Fahrtrichtung zeigt.
        .scaleEffect(x: creature.fromLeft ? 1 : -1, y: 1)
        // **Tiefen-Effekt** (User-Spec): leicht reduzierte Opacity +
        // minimaler Blur → wirkt „hinter dem Geschehen".
        .opacity(0.88)
        .blur(radius: 0.4)
    }

    private var fishSchoolSilhouette: some View {
        // Schwarm aus 4-5 kleinen Fischchen, leicht versetzt.
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let offsetX: CGFloat = CGFloat(index - 2) * 14
                let offsetY: CGFloat = CGFloat(index % 3 - 1) * 8
                fishSingle()
                    .offset(x: offsetX, y: offsetY)
            }
        }
        .scaleEffect(x: creature.fromLeft ? 1 : -1, y: 1)
        .shadow(color: Color.cyan.opacity(0.2), radius: 4, x: 0, y: 1)
    }

    @ViewBuilder
    private func fishSingle() -> some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.20, green: 0.42, blue: 0.60).opacity(0.55))
                .frame(width: 14, height: 6)
            Triangle()
                .fill(Color(red: 0.20, green: 0.42, blue: 0.60).opacity(0.55))
                .rotationEffect(.degrees(-90))
                .frame(width: 5, height: 4)
                .offset(x: -8)
        }
    }
}

/// **Animierte stromlinienförmige Hai-Silhouette** mit echter
/// Körperwellen-Propagation (Realismus-Pass 2).
///
/// Im Gegensatz zur alten statischen `SharkBodyShape` deformiert
/// dieser Shape sich **intern** über `phase`. Eine longitudinale
/// Welle wandert vom Kopf zum Schwanz, mit nicht-linear (^2.4)
/// wachsender Amplitude. Effekt:
///
///   • Kopf bleibt **fast still** — Spec „Kopf ruhig"
///   • Mitte schwingt leicht
///   • Schwanzstiel schwingt sichtbar — Spec „Schwanz als Motor"
///
/// Geometrie:
///   • Aspect ~4.5:1 — schlank, hydrodynamisch, weniger niedlich
///   • Spitze Schnauze
///   • Sanft konische Verjüngung zum Schwanzstiel
///   • Bauchlinie etwas voller als Rücken (asymmetrisch)
struct AnimatedSharkBodyShape: Shape {
    /// Aktuelle Wellen-Phase (vom Caller getrieben, i.d.R. `elapsed * w`).
    var phase: Double

    /// Räumliche Wellenfrequenz: wie viele 2π-Phasen über die Körper-
    /// länge sichtbar sind. ~0.65 = knapp dreiviertel Welle insgesamt
    /// — ruhig, nicht hektisch.
    var spatialFrequency: Double = 0.65

    /// Maximaler lateraler Versatz am Schwanzende (Punkte).
    var maxLateralOffset: CGFloat = 5.0

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        /// Lateraler (vertikaler) Wellen-Offset als Funktion der
        /// x-Position im Rect. tail = links, snout = rechts.
        /// Amplitude ~ tailness^2.4 — dadurch ist Kopf praktisch
        /// statisch, Schwanz schwingt voll.
        func waveOffset(at x: CGFloat) -> CGFloat {
            let u = (x - rect.minX) / w               // 0=tail, 1=snout
            let tailness = 1 - u
            let amp = maxLateralOffset * pow(tailness, 2.4)
            let waveArg = phase + Double(tailness) * spatialFrequency * 2 * .pi
            return amp * CGFloat(sin(waveArg))
        }

        /// Wendet den Wellen-Offset auf einen Punkt an (nur y).
        func warp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: p.y + waveOffset(at: p.x))
        }

        // Anatomie — schlanke, stromlinienförmige Silhouette
        let snoutX = rect.maxX
        let headX = rect.maxX - w * 0.10
        let bodyFrontX = rect.maxX - w * 0.30
        let bodyMidX = rect.midX
        let bodyBackX = rect.minX + w * 0.30
        let peduncleX = rect.minX + w * 0.10
        let tailX = rect.minX + w * 0.02

        let midY = rect.midY
        let topY = rect.minY + h * 0.10
        let bottomY = rect.maxY - h * 0.10

        var path = Path()

        // Start an der spitzen Schnauze
        path.move(to: warp(CGPoint(x: snoutX, y: midY)))

        // Obere Kontur: Schnauze → Kopf → Rückenscheitel → Schwanzstiel → Schwanzende
        path.addQuadCurve(
            to: warp(CGPoint(x: headX, y: midY - h * 0.30)),
            control: warp(CGPoint(x: snoutX - w * 0.04, y: midY - h * 0.06))
        )
        path.addQuadCurve(
            to: warp(CGPoint(x: bodyMidX, y: topY)),
            control: warp(CGPoint(x: bodyFrontX, y: topY - h * 0.04))
        )
        path.addQuadCurve(
            to: warp(CGPoint(x: peduncleX, y: midY - h * 0.10)),
            control: warp(CGPoint(x: bodyBackX, y: midY - h * 0.30))
        )
        path.addQuadCurve(
            to: warp(CGPoint(x: tailX, y: midY - h * 0.04)),
            control: warp(CGPoint(x: peduncleX - w * 0.04, y: midY - h * 0.07))
        )

        // Schwanzansatz (kurze Vertikale)
        path.addLine(to: warp(CGPoint(x: tailX, y: midY + h * 0.04)))

        // Untere Kontur: Schwanz → Schwanzstiel → Bauch → Kopf → Schnauze
        path.addQuadCurve(
            to: warp(CGPoint(x: peduncleX, y: midY + h * 0.10)),
            control: warp(CGPoint(x: peduncleX - w * 0.04, y: midY + h * 0.07))
        )
        path.addQuadCurve(
            to: warp(CGPoint(x: bodyMidX, y: bottomY)),
            control: warp(CGPoint(x: bodyBackX, y: midY + h * 0.34))
        )
        path.addQuadCurve(
            to: warp(CGPoint(x: headX, y: midY + h * 0.32)),
            control: warp(CGPoint(x: bodyFrontX, y: bottomY + h * 0.04))
        )
        path.addQuadCurve(
            to: warp(CGPoint(x: snoutX, y: midY)),
            control: warp(CGPoint(x: snoutX - w * 0.04, y: midY + h * 0.06))
        )

        path.closeSubpath()
        return path
    }
}

/// Sichelförmige (heterocercale) Schwanzflosse — typische Form
/// einer Hai-Caudalflosse: oberer Lobus deutlich größer als unterer,
/// hinterer Rand konkav (Notch). Ansatz links, Spitzen nach rechts.
struct CrescentTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        // Ankerpunkte
        let attach = CGPoint(x: rect.minX, y: rect.midY)
        let upperTip = CGPoint(x: rect.maxX - w * 0.06, y: rect.minY + h * 0.04)
        let lowerTip = CGPoint(x: rect.maxX - w * 0.22, y: rect.maxY - h * 0.10)
        let trailingNotch = CGPoint(x: rect.maxX - w * 0.36, y: rect.midY + h * 0.06)

        var path = Path()
        path.move(to: attach)

        // Vorderkante (Ansatz → obere Spitze) — leicht konvex
        path.addQuadCurve(
            to: upperTip,
            control: CGPoint(x: rect.minX + w * 0.55, y: rect.minY + h * 0.10)
        )
        // Hinterkante: konkav-sichelförmig zur unteren Spitze, mit
        // Notch dazwischen (zwei kubische Bezier-Segmente)
        path.addCurve(
            to: trailingNotch,
            control1: CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + h * 0.30),
            control2: CGPoint(x: rect.maxX - w * 0.18, y: rect.midY - h * 0.02)
        )
        path.addCurve(
            to: lowerTip,
            control1: CGPoint(x: rect.maxX - w * 0.30, y: rect.midY + h * 0.18),
            control2: CGPoint(x: rect.maxX - w * 0.18, y: rect.maxY - h * 0.20)
        )
        // Unterkante zurück zum Ansatz — sanft konvex
        path.addQuadCurve(
            to: attach,
            control: CGPoint(x: rect.minX + w * 0.30, y: rect.midY + h * 0.32)
        )

        path.closeSubpath()
        return path
    }
}

/// Klassische Hai-Rückenflosse: dreieckig, mit konkavem Hinterrand
/// und leicht nach hinten geneigter Spitze. Ansatzbreite gleich der
/// Frame-Breite, Spitze bei ~65 % nach vorn versetzt.
struct SharkDorsalFinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        // vorderer Basis-Punkt
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Vorderkante: konvex zur Spitze
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.65, y: rect.minY),
            control: CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.30)
        )
        // Hinterkante: konkav zurück zur hinteren Basis
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.minX + w * 0.85, y: rect.minY + h * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

/// Einfache Dreieck-Shape für Hai-Finnen und Fisch-Schwanzflossen.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - ArcadeSaugerFunnel (Sauger-Redesign)

/// Energetischer Trichter-Sauger — **Redesign**, das die alte flache
/// „Teller"-Optik ersetzt. Kernaussage: *dieses Ding zieht Dinge
/// aktiv an*. Gebaut mit `Path`-basiertem Bell-Shape + innerer
/// Energie-Spirale + dünnem Rim-Light + leichter Rotation.
///
/// **Design-Entscheidungen** (aus User-Spec + Systemkonsistenz mit
/// Schutz-Bubble):
///
///   • **Form**: asymmetrische Glocke statt flacher Kreis. Oben schmal
///     (≈35 % Breite), unten weit (≈85 %), seitliche Flanken als
///     Quadratic-Bézier-Kurven — wirkt wie ein Energie-Trichter, der
///     nach unten saugt. Nicht technisch/mechanisch, sondern organisch
///     mit weichen Kanten.
///   • **Farbe**: offizielle Vacuum-Palette #A78BFA/#E9D5FF/#C4B5FD
///     (aus `ArcadePowerUps.config(for: .vacuum)`). Hebt den Sauger
///     klar von der blauen Schutz-Bubble ab.
///   • **Innenraum**: heller als außen via RadialGradient →
///     suggeriert Energie-Volumen. Zentrum fast weiß, Rand leicht
///     opak in Primärfarbe.
///   • **Rotation**: 360° über 12 s — das dezente „Drehen" suggeriert
///     aktive Saugkraft, ohne kitschig zu wirken.
///   • **Energie-Spirale**: konzentrische AngularGradient-Ringe
///     rotieren schneller als der Körper (×2.2), Blend-Mode `.screen`.
///
/// Wiederverwendet in zwei Kontexten:
///   1. Als **fallender Drop** im Spielfeld (statisch animiert, `.popIn`)
///   2. Als **an Elumi angedockter** Sauger während des Aktiv-Zustands
///      (über dem Charakter, kleiner, zur Beam-Quelle wird)
///
/// **energyIntensity** (0…1) — skaliert die inneren Lichteffekte:
///   • Drop-Zustand: 1.0 (voll)
///   • Docked-Zustand: 1.2 (leicht intensiver, weil kleiner rendered
///     und aktive Energie signalisiert)
struct ArcadeSaugerFunnel: View {
    /// Lebenszyklus-Zustand der Saugglocke — steuert Rotation,
    /// Orientierung und ob End-Fade aktiv ist.
    ///
    /// • `.spawning` — Drop fällt gerade runter, langsame Rotation
    ///   (~1 Umdrehung/2.8 s) erlaubt, Trichter zeigt nach unten
    ///   (wide opening zum Boden, „Saug-Maul" nach vorn).
    /// • `.docked` — Sauger sitzt auf Elumis Kopf. Keine Rotation.
    ///   Trichter zeigt **nach oben** (wie ein umgekehrter Hut — der
    ///   Sauger nimmt von oben Snacks auf). Stabil, kein Wackeln.
    /// • `.ending` — Sauger löst sich vom Spieler. Kein Rotations-
    ///   Update mehr, nur Fade + Scale-Out (extern via Modifier).
    enum Phase {
        case spawning
        case docked
        case ending
    }

    let size: CGFloat
    let animationDate: Date
    var energyIntensity: Double = 1.0
    var phase: Phase = .spawning

    @State private var energyPhase: Double = 0
    @State private var spawnRotation: Double = 0

    private let primary = Color(hex: "#A78BFA")     // tiefes Lavendel
    private let secondary = Color(hex: "#E9D5FF")    // pastell-lila
    private let accent = Color(hex: "#C4B5FD")       // mittleres Lavendel

    var body: some View {
        ZStack {
            // Außen-Glow, atmosphärische Streuung
            Circle()
                .fill(primary.opacity(0.18 * energyIntensity))
                .frame(width: size * 1.25, height: size * 1.25)
                .blur(radius: 8)

            // Kern-Glocke — unser Trichter-Body
            funnelShape
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.85),        location: 0.00),
                            .init(color: secondary.opacity(0.75),          location: 0.22),
                            .init(color: accent.opacity(0.60),             location: 0.55),
                            .init(color: primary.opacity(0.72),            location: 0.90),
                            .init(color: primary.opacity(0.85),            location: 1.00)
                        ]),
                        center: UnitPoint(x: 0.50, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.60
                    )
                )

            // Energie-Spirale im Inneren — verstärkt den „Zug"-Eindruck
            funnelShape
                .fill(
                    AngularGradient(
                        colors: [
                            accent.opacity(0.35 * energyIntensity),
                            secondary.opacity(0.15 * energyIntensity),
                            primary.opacity(0.28 * energyIntensity),
                            accent.opacity(0.35 * energyIntensity)
                        ],
                        center: .center,
                        angle: .degrees(energyPhase)
                    )
                )
                .blendMode(.screen)

            // Rim-Light — irisierender dünner Rand
            funnelShape
                .stroke(
                    LinearGradient(
                        colors: [
                            secondary.opacity(0.95),
                            accent.opacity(0.70),
                            primary.opacity(0.60)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(1.0, size * 0.020)
                )

            // Primär-Highlight — gleicher Trick wie bei SchutzBubbleView:
            // weiches elongiertes Oval oben-links simuliert Lichtreflex
            // einer gewölbten Oberfläche.
            Ellipse()
                .fill(Color.white.opacity(0.65))
                .frame(width: size * 0.24, height: size * 0.10)
                .rotationEffect(.degrees(-40))
                .offset(x: -size * 0.16, y: -size * 0.26)
                .blur(radius: max(1, size * 0.022))

            // Sekundärer Licht-Puls im unteren Bereich — suggeriert
            // „Energie-Fokus" an der Öffnung.
            Ellipse()
                .fill(secondary.opacity(0.55 * energyIntensity))
                .frame(width: size * 0.56, height: size * 0.10)
                .offset(y: size * 0.30)
                .blur(radius: max(1.2, size * 0.025))
        }
        .frame(width: size, height: size)
        // **Orientierung**: im Docked-State wird der Trichter um
        // 180° geflippt (wide opening oben → „umgedrehter Hut") — so
        // wirkt er wie ein Aufsatz auf Elumis Kopf. In Spawning/Ending
        // bleibt er normal ausgerichtet (wide opening unten).
        .rotationEffect(.degrees(phase == .docked ? 180 : spawnRotation))
        .shadow(color: primary.opacity(0.40), radius: size * 0.12, x: 0, y: 2)
        .onAppear {
            // Innere Energie-Spirale läuft in allen Phasen — suggeriert
            // „Saug-Kraft" auch während des Andockens.
            withAnimation(.linear(duration: 5.4).repeatForever(autoreverses: false)) {
                energyPhase = -360
            }
            // Spawn-Rotation: nur im `.spawning`-Zustand. Langsame
            // Drehung (2.8 s / 360°) — lebendig, aber nicht chaotisch.
            // In `.docked` oder `.ending` bleibt `spawnRotation = 0`.
            if phase == .spawning {
                withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                    spawnRotation = 360
                }
            }
        }
    }

    /// Bell-/Trichter-Form als `Shape`. Oben schmal, unten breit, mit
    /// quadratischen Bezier-Kurven als Flanken — keine scharfen
    /// Kanten, wirkt organisch-weich.
    private var funnelShape: FunnelShape {
        FunnelShape()
    }
}

/// Parametrische Bell-/Trichter-Form. Renderable über `.fill(...)`
/// und `.stroke(...)`. Normierte Koordinaten (0…1) auf beiden Achsen
/// — `size` skaliert beim Einsatz.
struct FunnelShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Design-Parameter — geometrisch so gewählt, dass der Shape
        // wie eine weiche Glocke aussieht. Oben ein runder „Kopf"
        // (Hals des Trichters), unten weites Öffnen mit leicht
        // nach innen geschwungenen Flanken.
        let topWidthRatio: CGFloat     = 0.36   // oben
        let bottomWidthRatio: CGFloat  = 0.88   // unten
        let topYRatio: CGFloat         = 0.14
        let bottomYRatio: CGFloat      = 0.94
        let waistYRatio: CGFloat       = 0.60   // Einziehung bei 60 %
        let waistWidthRatio: CGFloat   = 0.55   // dort 55 % der Breite

        let w = rect.width
        let h = rect.height

        let topY = h * topYRatio
        let waistY = h * waistYRatio
        let bottomY = h * bottomYRatio

        let topLeft  = CGPoint(x: (w - w * topWidthRatio) / 2, y: topY)
        let topRight = CGPoint(x: (w + w * topWidthRatio) / 2, y: topY)
        let waistLeft  = CGPoint(x: (w - w * waistWidthRatio) / 2, y: waistY)
        let waistRight = CGPoint(x: (w + w * waistWidthRatio) / 2, y: waistY)
        let bottomLeft  = CGPoint(x: (w - w * bottomWidthRatio) / 2, y: bottomY)
        let bottomRight = CGPoint(x: (w + w * bottomWidthRatio) / 2, y: bottomY)

        var path = Path()

        // Kopf-Kreis oben (Hals des Trichters) als Halbkreis-Kappe.
        let capCenter = CGPoint(x: w / 2, y: topY)
        let capRadius = w * topWidthRatio / 2
        path.addArc(
            center: capCenter,
            radius: capRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Linke Flanke: Quadratic-Bezier von oben-links
        // zur Taille, dann zur Boden-Ecke — gibt der Glocke ihre
        // weiche Welle.
        path.move(to: topLeft)
        path.addQuadCurve(
            to: waistLeft,
            control: CGPoint(x: topLeft.x - w * 0.02, y: (topY + waistY) / 2)
        )
        path.addQuadCurve(
            to: bottomLeft,
            control: CGPoint(x: waistLeft.x - w * 0.04, y: (waistY + bottomY) / 2)
        )

        // Unterer Rand — leicht gekrümmt nach innen oben, damit
        // die Öffnung wie eine Schüssel wirkt statt einer flachen Linie.
        path.addQuadCurve(
            to: bottomRight,
            control: CGPoint(x: w / 2, y: bottomY + h * 0.03)
        )

        // Rechte Flanke — Spiegelbild.
        path.addQuadCurve(
            to: waistRight,
            control: CGPoint(x: waistRight.x + w * 0.04, y: (waistY + bottomY) / 2)
        )
        path.addQuadCurve(
            to: topRight,
            control: CGPoint(x: topRight.x + w * 0.02, y: (topY + waistY) / 2)
        )

        path.closeSubpath()
        return path
    }
}
