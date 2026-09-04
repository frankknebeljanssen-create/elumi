import Foundation
import SwiftUI

struct SplashView: View {
    let onFinish: (Bool) -> Void

    /// **Intro-Skip (Testphase, 2026-09-03)** — überspringt Splash,
    /// Willkommens-Screen, Account-Anlage und Ziel-Onboarding in einem
    /// Rutsch und landet direkt auf Home. `nil` im Release-Pfad, dann
    /// erscheint der Button gar nicht.
    var onSkipIntro: (() -> Void)? = nil

    @State private var animateTitle = false
    @State private var didStart = false
    @State private var didFinish = false
    @State private var finishWorkItem: DispatchWorkItem?
    @State private var splashAnimationStart = Date()
    /// Der Skip-Button kommt bewusst mit kurzer Verzögerung. Sofort
    /// eingeblendet würde er der erste sein, den man sieht — der Splash
    /// soll aber zuerst die Marke zeigen, nicht seine Abkürzung.
    @State private var showsSkipButton = false

    var body: some View {
        GeometryReader { geometry in
            let iconSize = min(geometry.size.width * 0.52, 220)
            let orbitDiameter = iconSize + 112
            let snackSize = min(max(iconSize * 0.35, 56), 76)

            ZStack {
                AppTheme.Colors.background
                    .ignoresSafeArea()

                SplashRisingBubbleField()
                    .opacity(0.9)
                    .allowsHitTesting(false)

                RadialGradient(
                    colors: [
                        AppTheme.Colors.primary.opacity(0.16),
                        AppTheme.Colors.background.opacity(0)
                    ],
                    center: .center,
                    startRadius: 24,
                    endRadius: 260
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer(minLength: geometry.size.height * 0.08)

                    ZStack {
                        Button {
                            completeSplash(immediate: true)
                        } label: {
                            ZStack {
                                Image("SplashCharacter")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: iconSize, height: iconSize)
                                    .shadow(color: AppTheme.Colors.primary.opacity(0.18), radius: 26, x: 0, y: 12)
                                    .scaleEffect(animateTitle ? 1 : 0.92)
                                    .opacity(animateTitle ? 1 : 0.55)

                                SplashCharacterBlinkOverlay(
                                    size: iconSize,
                                    startDate: splashAnimationStart
                                )
                                .scaleEffect(animateTitle ? 1 : 0.92)
                                .opacity(animateTitle ? 1 : 0)
                                .allowsHitTesting(false)
                            }
                            .frame(width: iconSize * 1.18, height: iconSize * 1.18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(y: -34)

                        SplashWormCrawler(
                            size: snackSize * 0.3,
                            travelWidth: min(geometry.size.width - 52, AppTheme.Layout.maxContentWidth) * 0.88,
                            crawlDuration: 4.9,
                            leftToRight: true
                        )
                        .offset(y: -iconSize * 1.22)
                        .scaleEffect(animateTitle ? 1 : 0.82)
                        .opacity(animateTitle ? 1 : 0.0)
                        .animation(.easeInOut(duration: 0.45).delay(0.16), value: animateTitle)
                        .allowsHitTesting(false)

                        SplashWaterflohSwimmer(
                            size: snackSize * 0.5875,
                            travelWidth: min(geometry.size.width - 40, AppTheme.Layout.maxContentWidth) * 0.62
                        )
                        .offset(y: iconSize * 0.82)
                        .scaleEffect(animateTitle ? 1 : 0.82)
                        .opacity(animateTitle ? 1 : 0.0)
                        .animation(.easeInOut(duration: 0.45).delay(0.24), value: animateTitle)
                        .allowsHitTesting(false)
                    }
                    .frame(width: orbitDiameter + 56, height: orbitDiameter + snackSize * 0.9)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .bottom) {
                        Text("Elumi")
                            .font(.system(size: 43, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .scaleEffect(animateTitle ? 1 : 0.92)
                            .opacity(animateTitle ? 1 : 0.55)
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18) + 54)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                completeSplash(immediate: true)
                            }

                        Button {
                            completeSplash(immediate: true)
                        } label: {
                            Color.clear
                                .frame(width: max(iconSize * 1.1, 180), height: 86)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)

                        VStack(spacing: 2) {
                            Text("\u{00A9} Frank Knebel-Janssen 2026")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                            let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                            let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
                            Text("Version \(v) (\(b))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.white.opacity(0.3))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 12) + 8)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // **Intro-Skip (Testphase, 2026-09-03)** — als Overlay über
            // dem gesamten Splash, damit der Button über den
            // Tap-to-continue-Flächen darunter liegt (Maskottchen,
            // Titel, unsichtbarer Button-Streifen). Ein Tap auf die
            // wechselt sonst nur zum Willkommens-Screen; dieser hier
            // überspringt das ganze Intro.
            //
            // Sitzt bewusst im unteren Drittel, über dem „Elumi"-Titel.
            // Erster Versuch war oben rechts — dort war der Button zwar
            // sichtbar, bekam aber keine Taps: In dem Streifen liegt das
            // globale App-Chrome darüber und fängt sie ab.
            .overlay(alignment: .bottom) {
                if let onSkipIntro, showsSkipButton {
                    Button {
                        skipIntro(onSkipIntro)
                    } label: {
                        Text("Intro überspringen")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(
                                Capsule().fill(Color.white.opacity(0.12))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18) + 120)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            splashAnimationStart = Date()
            animateTitle = true

            // Kurze Verzögerung, aber wirklich kurz: Der Splash steht
            // nur 2,8 s, ein halbe-Sekunde-Delay macht den Button
            // schwer zu treffen.
            withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                showsSkipButton = true
            }

            let workItem = DispatchWorkItem {
                completeSplash(immediate: false)
            }
            finishWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
        }
        .onDisappear {
            finishWorkItem?.cancel()
            finishWorkItem = nil
        }
    }

    /// Splash beenden UND das Intro überspringen. Nutzt denselben
    /// `didFinish`-Riegel wie `completeSplash`, damit der Auto-Timer
    /// nicht zusätzlich feuert — ruft aber `onFinish` NICHT auf: der
    /// Skip-Handler im Aufrufer erledigt den Splash-Abschluss selbst
    /// und hängt das Überspringen direkt dahinter.
    private func skipIntro(_ action: () -> Void) {
        guard !didFinish else { return }
        didFinish = true
        finishWorkItem?.cancel()
        finishWorkItem = nil
        action()
    }

    private func completeSplash(immediate: Bool) {
        guard !didFinish else { return }
        didFinish = true
        finishWorkItem?.cancel()
        finishWorkItem = nil
        onFinish(immediate)
    }
}
