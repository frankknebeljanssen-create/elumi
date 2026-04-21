import Foundation
import SwiftUI

/// Zentraler Publisher für Micro-Feedback während einer Lernsession.
/// Aktuelle Signale:
///   • `streakMoment` — gestaffelter Streak-Toast (Small/Medium/Large),
///   • `milestone` — größerer Card-Overlay-Moment bei besonderen Events,
///   • `successPulseTrigger` / `wrongPulseTrigger` — Trigger-Counter für
///     SwiftUI-Micro-Animationen (Scale-Pulse auf richtige Antwort-
///     Buttons, leichtes Shake/Fade auf falsche).
///
/// Ausgelöst vom `FeedbackEngine` (siehe dort). Wird pro Screen über
/// `ComboToastOverlay` + `MilestoneOverlayView` als Overlay gerendert.
@MainActor
final class GamificationFeedbackPresenter: ObservableObject {
    static let shared = GamificationFeedbackPresenter()

    // MARK: - Published State

    @Published var streakMoment: StreakMoment?
    @Published var milestone: MilestoneEvent?

    /// Monoton-zählender Pulse-Trigger. SwiftUI-Views bindet via
    /// `.onChange(of: presenter.successPulseTrigger)` einen kurzen
    /// Scale-Up-Moment. Counter statt Bool, damit **jede** richtige
    /// Antwort einen neuen Trigger auslöst, auch wenn zwei direkt
    /// hintereinander kommen.
    @Published var successPulseTrigger: Int = 0
    @Published var wrongPulseTrigger: Int = 0

    // MARK: - Event-Modelle

    struct StreakMoment: Identifiable, Equatable {
        let id = UUID()
        let tier: FeedbackConfig.StreakTier
        /// Die aktuelle Serie — z. B. 3, 5, 10, 15, … Wird im Toast-Text
        /// als „\(combo) richtig in Folge" angezeigt.
        let combo: Int
    }

    struct MilestoneEvent: Identifiable, Equatable {
        let id = UUID()
        let label: String
    }

    private var streakDismissItem: DispatchWorkItem?
    private var milestoneDismissItem: DispatchWorkItem?

    private init() {}

    // MARK: - API (wird nur vom `FeedbackEngine` aufgerufen)

    /// Trigger für Scale-Up-Pulse-Animation — keine zentrale View, die
    /// Views selbst binden sich per `.onChange`.
    func noteSuccessPulse() {
        successPulseTrigger &+= 1
    }

    func noteWrongPulse() {
        wrongPulseTrigger &+= 1
    }

    /// Abwärtskompatible API für Altcode, der direkt den Presenter
    /// adressiert (z. B. `QuizSessionController`). Leitet an den
    /// `FeedbackEngine` weiter, der selbst die Tier-Entscheidung macht.
    /// Neue Call-Sites sollten besser `FeedbackEngine.shared.record(...)`
    /// direkt nutzen.
    func noteComboProgress(currentCombo: Int) {
        FeedbackEngine.shared.record(.correctAnswer(currentStreak: currentCombo))
    }

    /// Zeigt einen Streak-Moment. Tier bestimmt Größe + Dauer + Kopie.
    func showStreakMoment(tier: FeedbackConfig.StreakTier, combo: Int) {
        streakDismissItem?.cancel()

        withAnimation(.spring(
            response: FeedbackTiming.comboToastEnterResponse,
            dampingFraction: FeedbackTiming.comboToastEnterDamping
        )) {
            streakMoment = StreakMoment(tier: tier, combo: combo)
        }

        let duration = FeedbackConfig.toastVisibleDuration(for: tier)
        let dismiss = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                self.streakMoment = nil
            }
        }
        streakDismissItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismiss)
    }

    /// Zeigt einen Meilenstein-Moment (größer, selten).
    func showMilestone(label: String) {
        milestoneDismissItem?.cancel()

        withAnimation(.spring(response: 0.48, dampingFraction: 0.76)) {
            milestone = MilestoneEvent(label: label)
        }

        let duration = FeedbackConfig.toastVisibleDuration(for: .milestone)
        let dismiss = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.32)) {
                self.milestone = nil
            }
        }
        milestoneDismissItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismiss)
    }
}

// MARK: - Legacy-Bridge für Altcode

extension GamificationFeedbackPresenter {
    /// Abwärtskompatibles Property — alte Views (`ComboToastOverlay`-
    /// Consumer) lesen hier. Wird automatisch gefüllt, wenn
    /// `showStreakMoment` aktiv ist.
    var comboToast: ComboToast? {
        guard let moment = streakMoment else { return nil }
        return ComboToast(
            comboCount: moment.combo,
            xpBonus: moment.tier == .medium || moment.tier == .large
                ? GamificationConfig.xpComboBonus
                : 0
        )
    }

    struct ComboToast: Identifiable, Equatable {
        let id = UUID()
        let comboCount: Int
        let xpBonus: Int
    }
}

// MARK: - Overlays

/// Streak-Toast-Overlay. Rendert den aktuell sichtbaren Streak-Moment
/// differenziert je nach Tier:
///   • Small — kompakter Pill oben, dezent.
///   • Medium — Hero-Card oberhalb der Mitte, prominenter Text.
///   • Large — wie Medium, aber mit zusätzlichem Bounce + Flame-Icon.
///   • Milestone wird in `MilestoneOverlayView` separat gerendert.
struct ComboToastOverlay: View {
    @ObservedObject private var presenter = GamificationFeedbackPresenter.shared

    var body: some View {
        VStack {
            Spacer(minLength: 0)
                .frame(height: 24)
            if let moment = presenter.streakMoment, moment.tier != .milestone {
                StreakMomentCard(moment: moment)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    ))
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Meilenstein-Overlay — eigene View, weil die Card-Sprache anders ist
/// (zentriert, größer, längere Sichtzeit). Wird zusätzlich zum Streak-
/// Overlay gerendert, falls beide gleichzeitig laufen (passiert durch
/// den Cooldown praktisch nie).
struct MilestoneOverlayView: View {
    @ObservedObject private var presenter = GamificationFeedbackPresenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let milestone = presenter.milestone {
                MilestoneCard(event: milestone)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - Card-Rendering

private struct StreakMomentCard: View {
    let moment: GamificationFeedbackPresenter.StreakMoment

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .black))
                .foregroundStyle(iconTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: titleSize, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: subtitleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.cta)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(iconTint.opacity(0.3), lineWidth: moment.tier == .large ? 2 : 1)
        )
    }

    // MARK: - Tier-abhängige Styling-Tokens

    private var iconName: String {
        switch moment.tier {
        case .small:     return "flame"
        case .medium:    return "flame.fill"
        case .large:     return "bolt.fill"
        case .milestone: return "star.fill"
        }
    }

    private var iconTint: Color {
        switch moment.tier {
        case .small:     return Color(hex: "#FFB366")       // warm-orange, gedeckt
        case .medium:    return Color(hex: "#FF9F40")       // kräftiger Flame-Tone
        case .large:     return AppTheme.Colors.cta         // primärer Action-Akzent
        case .milestone: return AppTheme.Colors.elumiPink   // emotional, seltener
        }
    }

    private var title: String {
        "\(moment.combo) richtig in Folge"
    }

    private var subtitle: String? {
        switch moment.tier {
        case .small:     return "läuft"
        case .medium:    return "stark"
        case .large:     return "weiter so"
        case .milestone: return nil
        }
    }

    // Größen-Progression — kleine Events bleiben kompakt, große wirken.
    private var iconSize: CGFloat {
        switch moment.tier {
        case .small:     return 14
        case .medium:    return 18
        case .large:     return 22
        case .milestone: return 22
        }
    }

    private var titleSize: CGFloat {
        switch moment.tier {
        case .small:     return 14
        case .medium:    return 18
        case .large:     return 22
        case .milestone: return 22
        }
    }

    private var subtitleSize: CGFloat {
        switch moment.tier {
        case .small:     return 11
        case .medium:    return 12
        case .large:     return 13
        case .milestone: return 13
        }
    }

    private var spacing: CGFloat {
        moment.tier == .small ? 8 : 12
    }

    private var horizontalPadding: CGFloat {
        moment.tier == .small ? 14 : 20
    }

    private var verticalPadding: CGFloat {
        switch moment.tier {
        case .small:     return 10
        case .medium:    return 14
        case .large:     return 18
        case .milestone: return 18
        }
    }

    private var cornerRadius: CGFloat {
        moment.tier == .small ? 14 : 18
    }

    private var shadowOpacity: Double {
        moment.tier == .small ? 0.18 : 0.26
    }

    private var shadowRadius: CGFloat {
        moment.tier == .small ? 8 : 14
    }

    private var shadowY: CGFloat {
        moment.tier == .small ? 4 : 8
    }
}

private struct MilestoneCard: View {
    let event: GamificationFeedbackPresenter.MilestoneEvent

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(AppTheme.Colors.elumiPink)
            Text(event.label)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.Colors.elumiPink.opacity(0.35), lineWidth: 2)
        )
    }
}

// MARK: - SuccessPulse-Modifier

/// Kleine Scale-Up-Animation (0.95 → 1.05 → 1.0) auf einer beliebigen
/// View. Wird über den `trigger`-Counter ausgelöst, den der Presenter
/// bei jeder richtigen Antwort inkrementiert.
struct SuccessPulseModifier: ViewModifier {
    let trigger: Int
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _, _ in
                // Phase 1: quick scale-up (~90 ms)
                withAnimation(.easeOut(duration: 0.09)) { scale = 1.05 }
                // Phase 2: ease back to 1.0 — bleibt bei insgesamt ~200 ms.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    withAnimation(.easeOut(duration: 0.11)) { scale = 1.0 }
                }
            }
    }
}

extension View {
    /// Bindet die View an einen zentralen Success-Pulse-Trigger. Zieht
    /// den Counter automatisch aus dem Presenter — Call-Site muss
    /// nichts weiter tun als diesen Modifier anzuhängen.
    func successPulse() -> some View {
        modifier(SuccessPulseModifier(trigger: GamificationFeedbackPresenter.shared.successPulseTrigger))
    }
}
