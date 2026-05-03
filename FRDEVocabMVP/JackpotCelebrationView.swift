import SwiftUI

/// **Jackpot-Feier-Overlay** (Block 5, 2026-05-03, Branch
/// `feature/training-session-flow`).
///
/// Wird vom `ElumiTabView` als Overlay über dem Slot-Screen gerendert,
/// sobald alle drei Reels mit Game-Symbolen (Elumi, also `elumiCount == 3`)
/// landen. Statt — wie bisher — den User auf den
/// `TrainingChainOverviewView`-Pre-Screen mit „Jackpot — kein Training!"
/// zu pushen, feiern wir an Ort und Stelle.
///
/// **Layout-Schichten** (von hinten nach vorne):
///   1. Backdrop — `Color.black.opacity(0.55)` über die ganze Screen.
///   2. `ConfettiBurst` — 120 Partikel, 4 s Lifetime (deutlich dichter +
///      länger als der End-Summary-Burst, weil Jackpot deutlich seltener
///      ist und mehr feiern darf).
///   3. Hero-Stack — „JACKPOT!"-Text (Spring-Scale-In) + Maskottchen-
///      Hopper (kleine Wiggle-Animation um `Image("SplashCharacter")`).
///   4. Tickets-Counter — `+N` mit `.contentTransition(.numericText())`-
///      Animation, läuft beim Erscheinen 1.5 s lang von alt → alt + N.
///   5. CTAs — erscheinen nach 1.5 s Delay (User soll erst die Feier
///      sehen): Primary „Nochmal drehen!" (pulsierend), Secondary
///      „Zur Startseite".
///
/// **Sound + Haptik**: Werden vom Caller (`ElumiTabView`) parallel zum
/// Reveal-Trigger ausgelöst. Diese View löst keine Sounds aus, damit
/// die Komponente entkoppelt bleibt und nicht doppelt feuert.
struct JackpotCelebrationView: View {

    // MARK: - Inputs

    /// Reference-Date für die Konfetti-Animation. Caller setzt
    /// `Date()` in dem Moment, in dem die View erscheinen soll.
    let startDate: Date

    /// Anzahl Tickets *vor* dem Jackpot-Grant. Die View animiert von
    /// `ticketsBefore` auf `ticketsBefore + ticketsGranted`.
    let ticketsBefore: Int

    /// Anzahl Tickets, die mit diesem Jackpot dazukommen (typischerweise
    /// 6, Mapping aus `ElumiTabView.slotCreditGrantTable`).
    let ticketsGranted: Int

    /// CTA-Closure: „Nochmal drehen!" — schließt das Overlay und startet
    /// einen frischen Spin (Caller-seitig: `triggerSpin()`).
    let onSpinAgain: () -> Void

    /// CTA-Closure: „Zur Startseite" — schließt das Overlay und navigiert
    /// zum Home-Tab (Caller-seitig: `goHome()`).
    let onGoHome: () -> Void

    // MARK: - Local Animation State

    /// Aktuell angezeigter Ticket-Wert. Animiert via
    /// `.contentTransition(.numericText())` beim Wechsel.
    @State private var displayedTickets: Int = 0

    /// Hero-Scale-In-Trigger. Wird beim `onAppear` mit Spring auf 1.0
    /// gesetzt; davor bei 0.4 (kleiner Punkt, der reinpoppt).
    @State private var heroScale: CGFloat = 0.4

    /// Hero-Opacity. Synchron mit Scale, damit das Reinpoppen sauber
    /// fadet.
    @State private var heroOpacity: Double = 0.0

    /// CTA-Reveal-Trigger. Wird nach 1.5 s `onAppear`-Delay auf `true`
    /// gesetzt — User sieht erst die Feier, dann die Buttons.
    @State private var ctasVisible: Bool = false

    /// Maskottchen-Hop-Offset. Spring-Animation pendelt zwischen 0 und
    /// `-mascotHopHeight` für kindgerechtes Hopser-Feeling.
    @State private var mascotHopOffset: CGFloat = 0

    /// Maskottchen-Wiggle-Rotation. Synchron mit Hop, leichte Drehung.
    @State private var mascotWiggle: Double = -8

    // MARK: - Konstanten

    private static let confettiDensity: Int = 120
    private static let confettiLifetime: Double = 4.0
    private static let ctaRevealDelay: TimeInterval = 1.5
    private static let ticketAnimationDelay: TimeInterval = 0.4
    private static let mascotHopHeight: CGFloat = 28

    // MARK: - Body

    var body: some View {
        ZStack {
            // Schicht 1 — Backdrop. Dezent dunkel, damit Hero + Konfetti
            // klar herausstechen, aber Slot-Screen-Restanzeige (Reels)
            // noch durchscheint und Kontext gibt.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .transition(.opacity)

            // Schicht 2 — Konfetti.
            ConfettiBurst(
                startDate: startDate,
                density: Self.confettiDensity,
                lifetime: Self.confettiLifetime
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Schichten 3 + 4 + 5 — Content-Stack, vertikal verteilt.
            //
            // **Bugfix v2 (User-Befund 2026-05-03 nach erstem Smoke)**:
            // Layout vorher mit doppeltem Spacer, was die CTAs unter
            // den Footer-Bar (`AppBottomBar`, ~80 pt) gedrückt hat,
            // weil das Overlay innerhalb des `.safeAreaInset(.bottom)`-
            // Containers von `.appLocalChrome` rendert. Jetzt:
            // expliziter `Spacer()` zwischen Hero/Tickets und CTAs,
            // klar großzügige `bottom`-Reserve (`110 pt`) damit die
            // Buttons sicher über dem Footer landen — auch auf
            // Geräten mit Home-Indicator-Safe-Area.
            VStack(spacing: 24) {
                heroBlock
                ticketsBlock
                Spacer()
                ctaBlock
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, 80)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Hero-Scale-In: Spring von 0.4 auf 1.0.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) {
                heroScale = 1.0
                heroOpacity = 1.0
            }
            // Maskottchen-Hop: bouncy-Spring zwischen 0 und -hopHeight,
            // mit Auto-Reverse über `.repeatForever`. Wiggle synchron.
            withAnimation(.easeInOut(duration: 0.45).repeatCount(4, autoreverses: true)) {
                mascotHopOffset = -Self.mascotHopHeight
                mascotWiggle = 8
            }
            // Tickets-Counter: Start mit `ticketsBefore`, dann nach
            // kurzem Delay auf `ticketsBefore + ticketsGranted`.
            // `.contentTransition(.numericText())` animiert die Ziffern.
            displayedTickets = ticketsBefore
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.ticketAnimationDelay) {
                withAnimation(.easeOut(duration: 1.5)) {
                    displayedTickets = ticketsBefore + ticketsGranted
                }
            }
            // CTAs nach Delay einblenden.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.ctaRevealDelay) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    ctasVisible = true
                }
            }
        }
    }

    // MARK: - Hero-Block

    /// Großer „JACKPOT!"-Text + Maskottchen-Hopper rechts daneben.
    /// Mascot ist im Layout dezent rechts neben dem Text positioniert,
    /// damit die Aufmerksamkeit primär auf dem Text liegt.
    ///
    /// **Bugfix v2 (User-Befund 2026-05-03)**: Font 56 → 44 pt + `lineLimit(1)`
    /// + `minimumScaleFactor(0.8)`. Vorher rutschte das „!" auf
    /// Standard-iPhone-Breite mit der 64-pt-Maskottchen-Spalte daneben
    /// in die nächste Zeile.
    private var heroBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("JACKPOT!")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FFD166"),  // gold
                            Color(hex: "#F8961E")   // tiefes orange
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                .scaleEffect(heroScale)
                .opacity(heroOpacity)

            mascotHopper
                .scaleEffect(heroScale)
                .opacity(heroOpacity)
        }
    }

    /// Kleines Maskottchen mit Hop+Wiggle. Verwendet `SplashCharacter`-
    /// Asset (Pattern aus `HomeHeader`, `ChainStepTimerBar` etc.).
    private var mascotHopper: some View {
        Image("SplashCharacter")
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .offset(y: mascotHopOffset)
            .rotationEffect(.degrees(mascotWiggle))
            .accessibilityHidden(true)
    }

    // MARK: - Tickets-Block

    /// „+N TICKETS"-Anzeige. Counter animiert vom `ticketsBefore` zu
    /// `ticketsBefore + ticketsGranted`, was als spürbares Hochzählen
    /// wirkt (Footer-Badge zieht parallel mit, weil `ProgressStore`
    /// schon zur Reveal-Zeit gegranted hat — siehe Caller-Logik).
    private var ticketsBlock: some View {
        VStack(spacing: 6) {
            Text("+\(ticketsGranted) TICKETS")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: "#FFD166"))
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)

            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "#FFD166"))
                Text("\(displayedTickets)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(displayedTickets)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "#FFD166").opacity(0.6), lineWidth: 1.5)
                    )
            )
        }
        .scaleEffect(heroScale)
        .opacity(heroOpacity)
    }

    // MARK: - CTA-Block

    /// Stacked CTAs unten — Primary „Nochmal drehen!" pulsierend
    /// (Pattern aus `PulsingModifier`), Secondary „Zur Startseite"
    /// als dezenter Text-Button.
    private var ctaBlock: some View {
        VStack(spacing: 14) {
            Button {
                onSpinAgain()
            } label: {
                Text("Nochmal drehen!")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .pulsing(active: ctasVisible, glowColor: AppTheme.Colors.cta)
            .accessibilityLabel(Text("Nochmal drehen"))
            .accessibilityHint(Text("Schließt die Feier und startet einen frischen Spin"))

            Button {
                onGoHome()
            } label: {
                Text("Zur Startseite")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel(Text("Zur Startseite"))
            .accessibilityHint(Text("Schließt die Feier und kehrt zum Home-Tab zurück"))
        }
        .opacity(ctasVisible ? 1 : 0)
        .offset(y: ctasVisible ? 0 : 20)
    }
}
