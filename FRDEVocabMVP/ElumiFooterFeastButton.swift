import SwiftUI

struct ElumiFooterFeastButton: View {
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @State private var showingArcadeGame = false
    @State private var activeSnackKind: ElumiSnackKind?
    @State private var snackFlightProgress: CGFloat = 0
    @State private var isMouthOpen = false
    @State private var characterScale: CGFloat = 1
    @State private var characterRotation: Double = 0
    @State private var sparkleBurst = false
    @State private var isAnimating = false

    private let feastSequence: [ElumiSnackKind] = [.wuermchen, .wasserfloh, .algenkugel]

    var body: some View {
        Button {
            showingArcadeGame = true
        } label: {
            ZStack {
                if let activeSnackKind {
                    ElumiSnackIcon(activeSnackKind, size: snackSize(for: activeSnackKind))
                        .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 2)
                        .scaleEffect(snackScale(for: activeSnackKind))
                        .rotationEffect(.degrees(snackRotation(for: activeSnackKind)))
                        .offset(snackOffset(for: activeSnackKind))
                        .opacity(snackOpacity)
                        .zIndex(1)
                }

                Image("SplashCharacter")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .scaleEffect(characterScale)
                    .rotationEffect(.degrees(characterRotation))
                    .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
                    .overlay(alignment: .bottomTrailing) {
                        Capsule()
                            .fill(AppTheme.Colors.elumiNavy.opacity(0.92))
                            .frame(width: isMouthOpen ? 9 : 5, height: isMouthOpen ? 5 : 2)
                            .offset(x: -8, y: -7)
                            .opacity(isMouthOpen ? 0.95 : 0.0)
                    }
                    .overlay {
                        if sparkleBurst {
                            ZStack {
                                sparkleDot(x: 8, y: -5, size: 4)
                                sparkleDot(x: 13, y: 0, size: 3)
                                sparkleDot(x: 7, y: 5, size: 3)
                            }
                            .transition(.opacity)
                        }
                    }
            }
            .frame(width: 48, height: 38)
            .contentShape(Rectangle())
            .accessibilityLabel(Text("Elumi"))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingArcadeGame) {
            ElumiArcadeGameView(feedbackPlayer: feedbackPlayer)
        }
    }

    private var snackOpacity: Double {
        let fadeStart: CGFloat = 0.84
        if snackFlightProgress <= fadeStart { return 1 }
        let normalized = min(1, (snackFlightProgress - fadeStart) / (1 - fadeStart))
        return Double(1 - normalized)
    }

    private func sparkleDot(x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(0.92))
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }

    private func snackStartOffset(for kind: ElumiSnackKind) -> CGSize {
        switch kind {
        case .wuermchen:
            return CGSize(width: -22, height: -2)
        case .wasserfloh:
            return CGSize(width: 18, height: -16)
        case .algenkugel:
            return CGSize(width: 14, height: 16)
        }
    }

    private func snackEndOffset(for kind: ElumiSnackKind) -> CGSize {
        switch kind {
        case .wuermchen:
            return CGSize(width: 8, height: 3)
        case .wasserfloh:
            return CGSize(width: 9, height: 2)
        case .algenkugel:
            return CGSize(width: 8, height: 4)
        }
    }

    private func snackSize(for kind: ElumiSnackKind) -> CGFloat {
        switch kind {
        case .wuermchen:
            return 16
        case .wasserfloh:
            return 15
        case .algenkugel:
            return 14
        }
    }

    private func snackScale(for kind: ElumiSnackKind) -> CGFloat {
        let start: CGFloat
        let end: CGFloat
        switch kind {
        case .wuermchen:
            start = 1
            end = 0.34
        case .wasserfloh:
            start = 0.95
            end = 0.32
        case .algenkugel:
            start = 0.92
            end = 0.28
        }

        return start + ((end - start) * snackFlightProgress)
    }

    private func snackRotation(for kind: ElumiSnackKind) -> Double {
        let start: Double
        switch kind {
        case .wuermchen:
            start = -8
        case .wasserfloh:
            start = 10
        case .algenkugel:
            start = -14
        }
        return start * (1 - Double(snackFlightProgress))
    }

    private func snackOffset(for kind: ElumiSnackKind) -> CGSize {
        let start = snackStartOffset(for: kind)
        let end = snackEndOffset(for: kind)
        return CGSize(
            width: start.width + ((end.width - start.width) * snackFlightProgress),
            height: start.height + ((end.height - start.height) * snackFlightProgress)
        )
    }

    @MainActor
    private func playFeastSequence() async {
        guard !isAnimating else { return }
        isAnimating = true

        for kind in feastSequence {
            activeSnackKind = kind
            snackFlightProgress = 0
            sparkleBurst = false
            isMouthOpen = false
            characterScale = 1
            characterRotation = 0

            withAnimation(.easeInOut(duration: 0.45)) {
                snackFlightProgress = 1
            }

            try? await Task.sleep(for: .milliseconds(280))

            withAnimation(.easeInOut(duration: 0.1)) {
                isMouthOpen = true
                characterScale = 1.08
                characterRotation = -4
                sparkleBurst = true
            }

            try? await Task.sleep(for: .milliseconds(140))

            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                isMouthOpen = false
                characterScale = 1
                characterRotation = 3
            }

            try? await Task.sleep(for: .milliseconds(90))

            withAnimation(.easeOut(duration: 0.12)) {
                sparkleBurst = false
                characterRotation = 0
            }

            activeSnackKind = nil
            snackFlightProgress = 0

            try? await Task.sleep(for: .milliseconds(110))
        }

        isAnimating = false
    }
}
