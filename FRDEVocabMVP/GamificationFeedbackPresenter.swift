import Foundation
import SwiftUI

/// Zentraler Publisher für Micro-Feedback während einer Lernsession —
/// aktuell: Combo-Toasts. Wird von allen vier Modulen (Karteikarten, Quiz,
/// Training, Verbformen) beschickt und vom jeweiligen View als Overlay
/// gerendert (`ComboToastOverlay`).
///
/// Designziele (analog `SessionSummaryView` / `ProgressService`):
/// • Ruhig, Elumi-konsistent, keine Arcade-Optik.
/// • Kein Blockieren der Session — Toast ist reiner Anzeige-Moment.
/// • Single Source of Truth für Schwellenwerte (`GamificationConfig`).
@MainActor
final class GamificationFeedbackPresenter: ObservableObject {
    static let shared = GamificationFeedbackPresenter()

    @Published var comboToast: ComboToast?

    struct ComboToast: Identifiable, Equatable {
        let id = UUID()
        let comboCount: Int
        let xpBonus: Int
    }

    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    /// Wird von `recordAnswer(correct: true)` in den Controllern aufgerufen.
    /// Zeigt einen Toast, wenn der aktuelle Combo-Stand ein Vielfaches der
    /// XP-Combo-Schwelle ist (5, 10, 15, 20, …) — das entspricht genau den
    /// Stellen, an denen `ProgressService` einen Combo-Bonus vergibt.
    func noteComboProgress(currentCombo: Int) {
        let threshold = GamificationConfig.xpComboThreshold
        guard currentCombo >= threshold, currentCombo % threshold == 0 else { return }
        show(ComboToast(
            comboCount: currentCombo,
            xpBonus: GamificationConfig.xpComboBonus
        ))
    }

    private func show(_ toast: ComboToast) {
        dismissWorkItem?.cancel()
        // Timings zentral aus `FeedbackTiming` — Phase 7 zentrale Steuerung.
        withAnimation(.spring(
            response: FeedbackTiming.comboToastEnterResponse,
            dampingFraction: FeedbackTiming.comboToastEnterDamping
        )) {
            comboToast = toast
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                self.comboToast = nil
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + FeedbackTiming.comboToastVisibleDuration,
            execute: workItem
        )
    }
}

/// Overlay-View mit dem aktuell sichtbaren Combo-Toast. Nutzt `.allowsHitTesting(false)`
/// auf dem Container, damit der Toast keine Session-Eingaben blockiert.
struct ComboToastOverlay: View {
    @ObservedObject private var presenter = GamificationFeedbackPresenter.shared

    var body: some View {
        VStack {
            if let toast = presenter.comboToast {
                ComboToastCard(combo: toast.comboCount, xp: toast.xpBonus)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

private struct ComboToastCard: View {
    let combo: Int
    let xp: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "#FF9F40"))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(combo)x Combo")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("+\(xp) XP Bonus")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.cta)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
        )
    }
}
