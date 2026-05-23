import SwiftUI

/// **Trainings-Chain Pre-Screen** (Stufe 2, 2026-04-30, Branch
/// `feature/training-session-flow`).
///
/// Zwischen-Screen, der nach „Jetzt üben" im Elumi-Tab erscheint und
/// VOR dem ersten Modul-Open. Zweck: dem User vor dem Start ein
/// klares Bild der gleich anstehenden Trainings-Sequenz geben — welche
/// Module, in welcher Reihenfolge, wie viel Zeit pro Modul, welche
/// Game-Slots ihm wie viele Tickets eingebracht haben.
///
/// **Layout-Architektur:**
///   • ModuleHeaderCard mit Back-Chevron oben
///   • Hero-Section: „Dein Trainingsplan" + Total-Dauer-Hint
///     („12 Minuten · 3 Übungen")
///   • Mini-Cards-Stack pro Source-Slot (alle 3, in Slot-Reihenfolge):
///       - Modul-Slot: Modul-Icon + Modul-Name + perStep-Zeit
///       - Game-Slot:  🎫-Icon + „+1 Ticket" (knapp) + „kein Training"
///   • „Übung starten"-CTA unten; bei Jackpot disabled + Hint-Text
///
/// **Navigations-Verhalten:**
///   • CTA → Push aufs erste Modul via `onStartTraining` (Caller
///     berechnet den `screenForChainStep`-AppScreen).
///   • Back-Chevron (`onBack`) → Caller räumt Chain ab via
///     `chainStore.clear()` und pop-t Navigation. `lastSpinResult` im
///     Tab bleibt sichtbar — R12-Spec konform.
///
/// **Game-Slot-Layout:** zeigt knapp das Tickets-Reward + „kein
/// Training" (User-Spec). Die Tickets selbst sind beim
/// `startTraining`-Tap im ElumiTab schon gutgeschrieben (Pre-Screen
/// sieht keinen Re-Grant), die Card hier ist rein informativ.
struct TrainingChainOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    let chain: TrainingChainContext

    /// Wird beim Tap auf „Übung starten" aufgerufen — der Caller pusht
    /// daraus den ersten Modul-AppScreen via `screenForChainStep`. Wenn
    /// `chain.isJackpot`, ist der CTA disabled, dieser Closure wird
    /// nicht ausgelöst.
    let onStartTraining: () -> Void

    /// Caller-Handler für Back-Chevron. Soll
    /// `chainStore.clear()` rufen und Navigation pop-en. `lastSpinResult`
    /// im Tab bleibt unangetastet (R12).
    let onBack: () -> Void

    /// Caller-Handler für Footer-Home / globale Chrome-Buttons.
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void

    @ObservedObject var feedbackPlayer: FeedbackPlayer

    private let sectionStyle: AppSectionStyle = .home

    // MARK: - Derived

    /// Total-Dauer-Anzeige im Hero. Bei Jackpot leer.
    private var totalDurationText: String {
        guard !chain.plannedSteps.isEmpty else { return "" }
        // **Daily Drop Modul 2.5 (2026-05-23)** — Count-Modus: Anzahl
        // statt Minuten.
        if chain.isCountMode {
            let total = chain.totalExerciseCount
            return "\(total) \(total == 1 ? "Übung" : "Übungen")"
        }
        let total = chain.plannedSteps.count * chain.perStepDurationMin
        return "\(total) Minuten · \(chain.plannedSteps.count) \(chain.plannedSteps.count == 1 ? "Übung" : "Übungen")"
    }

    /// Tickets, die der User durch den aktuellen Slot-Spin bekommt
    /// (1×→1, 2×→3, 3×→6). Aus dem `slotCreditGrantTable`-Mapping
    /// nachgebaut, weil der Pre-Screen den Wert nicht aus dem Store
    /// liest — er zeigt ihn nur an.
    private var ticketsFromGameSlots: Int {
        let gameCount = chain.sourceCenterSymbolKinds.filter { kind in
            if case .game = kind { return true }
            return false
        }.count
        switch gameCount {
        case 1: return 1
        case 2: return 3
        case 3: return 6
        default: return 0
        }
    }

    // MARK: - Body

    /// **Bug-Fix 2026-05-02** — Wrapper für die Back-Chevron-Aktion.
    /// Der originale Doc-Comment in `AppDestinationHost` ging davon
    /// aus, dass die Pre-Screen-Eigene `dismiss()` (via @Environment)
    /// den Stack poppt zusätzlich zum Caller-`onBack`-Closure (Chain-
    /// Store-Clear). Tatsächlich war `onBack` aber ungewrappt an
    /// ModuleHeaderCard + AppTopBar weitergegeben → Back-Chevron tat
    /// nur Store-Clear (unsichtbar) und ließ den Pre-Screen
    /// stehen. Wrapper macht jetzt beides: Caller-Closure ausführen
    /// (Store räumt), dann selbst poppen.
    private func handleBackTap() {
        onBack()
        dismiss()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ModuleHeaderCard(
                    systemImage: "list.bullet.rectangle.fill",
                    title: "Dein Trainingsplan",
                    accent: sectionStyle.accent,
                    onBack: handleBackTap
                )

                // **UX-Polish 2026-05-02 (Stufe 7)** — `heroBlock`
                // („Bereit?" + Subtitle „X Min · 3 Übungen" + Tickets)
                // ersetzt durch zwei separate Blöcke: erst die Time-
                // Card oben (Konsistenz mit Slot/Setup-Layout), dann
                // die alleinige pulsierende „Bereit?"-Headline. Subtitle-
                // Zeile mit „Min · Übungen" und die Tickets-Zeile sind
                // entfallen — die Total-Dauer steht in der Time-Card,
                // Tickets sind im Footer-Badge sichtbar (R12).
                if !chain.isJackpot {
                    timeCardBlock
                }

                readyHeadline

                slotCardsStack

                if chain.isJackpot {
                    jackpotHint
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            // **2026-05-08 Padding-Cleanup** — Bottom-Padding lässt
            // weiterhin 100 pt für die sticky-CTA-Höhe; der frühere
            // `footerHeight + insetBottom` ist redundant, weil der
            // globale Footer per `.safeAreaInset(.bottom)` bereits
            // automatisch reserviert ist.
            .padding(.bottom, 100)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottom) {
            startCTA
                .padding(.horizontal, AppLayout.screenPadding)
                // **2026-05-08 Padding-Cleanup** — Sticky-CTA sitzt
                // direkt am Bottom des Content-Bereichs (= Top der
                // Footer-safeAreaInset-Reservierung). Atemraum reicht
                // mit `Spacing.md` aus; vorher zusätzlich Footer-Höhe.
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: handleBackTap, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: goHome,
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings
            )
        }
    }

    // MARK: - Hero

    /// **UX-Polish 2026-05-02 (Stufe 7)** — Time-Card oben auf dem
    /// Pre-Screen, visuell konsistent zum Slot-Screen-`timeDisplayCard`
    /// (XL-Zahl + „min"-Suffix in zentriertem Setup-Card-Background),
    /// jedoch **ohne** Pencil-Pill (auf dem Pre-Screen ist kein Re-Edit
    /// vorgesehen — User hat die Zeit im Setup-Modal gewählt, der
    /// Slot ist gedreht, jetzt ist es Read-Only). Total-Dauer =
    /// `plannedSteps.count * perStepDurationMin`.
    private var timeCardBlock: some View {
        // **UX-Polish 2026-05-02 Iter 2 (User-Spec „zeitcard oben
        // etwas flacher machen, das dann auch im Dein Trainingsplan
        // genauso")**: Number 46 → 28 pt, vertical-padding 8 → 2 pt
        // — identische Maße wie der Slot-Screen-`timeDisplayCard`.
        // Pre-Screen sieht damit visuell konsistent zu Slot, plus
        // das gespartene ~28 pt Card-Höhe schiebt die Übungs-Cards +
        // CTA hoch, weg von der Footer-Linie.
        // **Daily Drop Modul 2.5 (2026-05-23)** — Count-Modus: Anzahl
        // statt Minuten (Label „ANZAHL", Suffix „Übungen").
        let isCount = chain.isCountMode
        let total = isCount
            ? chain.totalExerciseCount
            : chain.plannedSteps.count * chain.perStepDurationMin
        return VStack(spacing: 4) {
            // **Naming-Sweep 2026-05-06** — „TRAININGSZEIT" → „DAUER".
            Text(isCount ? "ANZAHL" : "DAUER")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.Colors.cardLabel)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(total)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)
                    .contentTransition(.identity)

                Text(isCount ? "Übungen" : "min")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    /// **UX-Polish 2026-05-02 (Stufe 7)** — alleinige große Headline
    /// „Bereit?" mit kontinuierlicher Pulsation. Kein Subtitle mehr,
    /// keine Min-Count-/Übungs-Count-Zeile, kein Tickets-Hint — die
    /// Headline soll als reiner Anker für die Aufmerksamkeit auf den
    /// CTA „Training starten" wirken. Pulsation analog zum Slot-CTA
    /// und den Setup-Modal-Time-Cards (zentral via `.pulsing(active:)`).
    private var readyHeadline: some View {
        Text(chain.isJackpot ? "Jackpot — kein Training!" : "Bereit?")
            .font(.system(size: 32, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .pulsing(
                active: !chain.isJackpot,
                peakScale: 1.06,
                glowColor: sectionStyle.accent
            )
    }

    // MARK: - Slot-Cards-Stack

    /// Eine Card pro Slot-Position des Spin-Results, in Original-
    /// Reihenfolge (linker Slot zuerst). Modul-Slots zeigen Zeit-
    /// Anteil, Game-Slots zeigen Tickets-Reward.
    private var slotCardsStack: some View {
        VStack(spacing: 10) {
            ForEach(Array(chain.sourceCenterSymbolKinds.enumerated()), id: \.offset) { idx, kind in
                slotCard(slotIndex: idx, kind: kind)
            }
        }
    }

    @ViewBuilder
    private func slotCard(slotIndex: Int, kind: TrainingChainContext.SourceSlotKind) -> some View {
        switch kind {
        case .module(let module):
            moduleSlotCard(slotIndex: slotIndex, module: module)
        case .game:
            gameSlotCard(slotIndex: slotIndex)
        }
    }

    /// Modul-Card: Index („Reel 1") + Modul-Icon + Modul-Name +
    /// Zeit-Anteil als Pill rechts.
    private func moduleSlotCard(slotIndex: Int, module: HomeHeroModule) -> some View {
        HStack(spacing: 14) {
            HomeModuleIconView(icon: module.icon, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reel \(slotIndex + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Text(module.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            Spacer(minLength: 0)

            // Zeit-Pill: „4 min" — gerundet auf perStepDurationMin.
            // User-Spec: gerundete Anzeige (5/10-Sekunden-Schritte hier
            // nicht relevant, weil perStepDurationMin = totalDuration/N
            // mit N = Anzahl Modul-Slots immer ein ganzzahliges
            // Minuten-Ergebnis liefert: 6/2=3, 12/3=4, 18/2=9, etc.)
            //
            // **UX-Polish 2026-05-02 (Stufe 7) — Punkte 4 + 5**:
            //   * **Lesbarkeit (Punkt 4)**: Foreground von `module.accent`
            //     auf `AppTheme.Colors.textPrimary` umgestellt. Bei
            //     dunklen Modul-Farben (z.B. Vokabeln Indigo-900
            //     `#1E3A8A`) war dunkelblauer Pill-Text auf dunkelblau-
            //     getöntem Pill-Hintergrund auf der dunklen Surface
            //     unlesbar. textPrimary (cream/off-white) gibt sicheren
            //     Kontrast unabhängig von der Modul-Akzent-Farbe; das
            //     Pill-Tint (`accent.opacity(0.18)` Background +
            //     `accent.opacity(0.40)` Border) trägt die Modul-
            //     Identität weiter.
            //   * **Größe (Punkt 5)**: Font 13 → 22 pt, Padding 10/4 →
            //     14/8 pt. Pill verdoppelt sich optisch — Zeit-Anteil
            //     pro Modul wird zur ablesbaren Info, nicht zum
            //     Mini-Etikett.
            Text(chain.isCountMode ? "\(chain.perStepCount ?? 0) Übungen" : "\(chain.perStepDurationMin) min")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(module.accent.opacity(0.18))
                )
                .overlay(
                    Capsule()
                        .stroke(module.accent.opacity(0.40), lineWidth: 1)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(module.accent.opacity(0.30), lineWidth: 1)
        )
    }

    /// Game-Card: Index („Reel N") + Axolotl-Icon + Label „Game" +
    /// Subtitel „kein Training" rechts. Bewusst knapp — User-Spec.
    ///
    /// **Bugfix 2026-05-01**: das frühere `Text("+1 Ticket")` als
    /// Hauptbeschriftung pro Card war irreführend, weil bei 2-Game-
    /// Spins die tatsächliche Tickets-Vergabe +3 ist (Slot-Grant-Table
    /// 1→1, 2→3, 3→6), die summierte Card-Anzeige aber 2× +1 = 2
    /// suggerierte. Total-Tickets wandern jetzt in die `heroBlock`-
    /// Subtitle (siehe dort); die Card selbst bleibt rein deskriptiv.
    ///
    /// **Visual-Tweak 2026-05-01**: Game-Icon vom SF-Symbol
    /// `ticket.fill` (yellow) auf das Axolotl-Maskottchen-Asset
    /// `SplashCharacter` umgestellt. Konsistent zu `ReelSymbol.elumi`
    /// (gleiches Asset, gleicher Match-Identitäts-Visual auf der
    /// Slot Machine — Wiedererkennung „dieser Slot war ein Game-
    /// Slot"). Tickets-Visual lebt jetzt zentral im Footer-Badge
    /// und in der Hero-Subtitle.
    private func gameSlotCard(slotIndex: Int) -> some View {
        HStack(spacing: 14) {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reel \(slotIndex + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Text("Game")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            Spacer(minLength: 0)

            Text("kein Training")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.warning.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Jackpot-Hint

    /// Hinweis-Card statt Übungen, wenn alle 3 Slots Game waren.
    /// Zeigt das Total-Tickets-Reward + Aufforderung neu zu drehen.
    /// Stufe 5 wird hier eine Feier-Animation ergänzen — der Hint-Text
    /// bleibt davon unabhängig nützlich für die Funktionalität.
    private var jackpotHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Du hast +\(ticketsFromGameSlots) Tickets bekommen.")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Drehe noch mal, um Übungen freizuspielen.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.warning.opacity(0.40), lineWidth: 1)
        )
    }

    // MARK: - CTA

    /// Sticky Bottom-CTA „Training starten". Disabled bei Jackpot. Wird
    /// als Overlay über dem ScrollView platziert, damit der CTA immer
    /// sichtbar bleibt unabhängig vom Scroll-State. Label wurde von
    /// „Übung starten" auf „Training starten" angeglichen, damit's mit
    /// der „Jetzt üben"-CTA aus dem Slot-Screen und der Modul-Card-Title-
    /// Sprache („Training abschließen", „Trainingszeit abgelaufen")
    /// konsistent bleibt.
    private var startCTA: some View {
        Button {
            guard !chain.isJackpot else { return }
            onStartTraining()
        } label: {
            Text(chain.isJackpot ? "Zurück zum Setup" : "Training starten")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .opacity(chain.isJackpot ? 0.45 : 1.0)
        .disabled(chain.isJackpot)
        // **UX-Polish 2026-05-02 Iter 2 (Stufe 7)** — pulsierender
        // CTA wie auf dem Slot-Screen-„Maschine starten". Pulse läuft
        // solange die Chain nicht im Jackpot-State ist (dann ist der
        // CTA nur ein Reset-Pfad und braucht keine „tap me"-
        // Affordance). Konsistente Pulse-Defaults via `pulsing(_:)`
        // — gleiche Frequenz/Helligkeit wie Setup-Modal-CTAs +
        // „Bereit?"-Headline.
        .pulsing(active: !chain.isJackpot, glowColor: AppTheme.Colors.cta)
        .accessibilityLabel(chain.isJackpot ? "Zurück zum Setup" : "Training starten")
    }
}
