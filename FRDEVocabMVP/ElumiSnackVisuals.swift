import SwiftUI

enum ElumiSnackKind: CaseIterable {
    case algenkugel
    case wasserfloh
    case wuermchen

    var assetName: String {
        switch self {
        case .algenkugel:
            return "ElumiAlgenkugel"
        case .wasserfloh:
            return "ElumiWasserfloh"
        case .wuermchen:
            return "ElumiWuermchen"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .algenkugel:
            return "Algenkugel"
        case .wasserfloh:
            return "Wasserfloh"
        case .wuermchen:
            return "Würmchen"
        }
    }
}

func elumiSnackKind(for value: Int) -> ElumiSnackKind {
    let kinds = ElumiSnackKind.allCases
    guard !kinds.isEmpty else { return .algenkugel }
    return kinds[abs(value) % kinds.count]
}

struct ElumiSnackIcon: View {
    let kind: ElumiSnackKind
    var size: CGFloat

    init(_ kind: ElumiSnackKind, size: CGFloat = 28) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Image(kind.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(Text(kind.accessibilityLabel))
    }
}

struct ElumiSnackCluster: View {
    let count: Int
    var size: CGFloat = 28
    var maxIcons: Int = 3

    private var displayedKinds: [ElumiSnackKind] {
        guard count > 0 else { return [] }
        let iconCount = min(maxIcons, max(1, count))
        return (0..<iconCount).map { ElumiSnackKind.allCases[$0 % ElumiSnackKind.allCases.count] }
    }

    var body: some View {
        HStack(spacing: -size * 0.18) {
            ForEach(Array(displayedKinds.enumerated()), id: \.offset) { index, kind in
                ElumiSnackIcon(kind, size: size)
                    .rotationEffect(.degrees(index == 1 ? -7 : (index == 2 ? 7 : 0)))
                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
                    .zIndex(Double(displayedKinds.count - index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(countLabel(count, singular: "Snack", plural: "Snacks")))
    }
}

private struct SplashAnimatedSnack: View {
    let kind: ElumiSnackKind
    let size: CGFloat
    let baseRotation: Double

    @State private var animate = false

    private var shadowColor: Color {
        .black.opacity(0.18)
    }

    var body: some View {
        ZStack {
            switch kind {
            case .algenkugel:
                Ellipse()
                    .fill(shadowColor)
                    .frame(width: size * 0.68, height: size * 0.16)
                    .blur(radius: 1.4)
                    .offset(
                        x: animate ? size * 0.16 : -size * 0.16,
                        y: size * 0.34
                    )
                    .scaleEffect(x: animate ? 1.12 : 0.88, y: animate ? 1.0 : 0.84)
                    .opacity(animate ? 0.24 : 0.15)

                ElumiSnackIcon(kind, size: size)
                    .rotationEffect(.degrees(baseRotation + (animate ? 24 : -112)))
                    .offset(
                        x: animate ? size * 0.16 : -size * 0.16,
                        y: animate ? size * 0.02 : -size * 0.1
                    )
                    .scaleEffect(x: animate ? 1.05 : 0.94, y: animate ? 0.95 : 1.06)
                    .shadow(color: AppTheme.Colors.success.opacity(0.26), radius: 10, x: 0, y: 4)
            case .wasserfloh:
                ForEach(0..<3, id: \.self) { bubbleIndex in
                    Circle()
                        .fill(Color.white.opacity(bubbleIndex == 0 ? 0.34 : 0.18))
                        .frame(width: size * (0.1 - (CGFloat(bubbleIndex) * 0.018)),
                               height: size * (0.1 - (CGFloat(bubbleIndex) * 0.018)))
                        .offset(
                            x: (animate ? -size * 0.18 : -size * 0.06) - CGFloat(bubbleIndex * 8),
                            y: (animate ? -size * 0.18 : size * 0.06) - CGFloat(bubbleIndex * 9)
                        )
                        .opacity(animate ? 0.0 : 0.9 - Double(bubbleIndex) * 0.18)
                        .animation(
                            .easeOut(duration: 1.45)
                            .repeatForever(autoreverses: false)
                            .delay(Double(bubbleIndex) * 0.22),
                            value: animate
                        )
                }

                ElumiSnackIcon(kind, size: size)
                    .scaleEffect(x: animate ? -1 : 1, y: 1)
                    .rotationEffect(.degrees(baseRotation + (animate ? 7 : -9)))
                    .offset(
                        x: animate ? size * 0.18 : -size * 0.18,
                        y: animate ? size * 0.1 : -size * 0.14
                    )
                    .shadow(color: AppTheme.Colors.success.opacity(0.22), radius: 10, x: 0, y: 5)
            case .wuermchen:
                Ellipse()
                    .fill(shadowColor)
                    .frame(width: size * 0.74, height: size * 0.14)
                    .blur(radius: 1.3)
                    .offset(y: size * 0.3)
                    .scaleEffect(x: animate ? 0.86 : 1.05, y: animate ? 0.76 : 1.0)
                    .opacity(animate ? 0.13 : 0.22)

                ElumiSnackIcon(kind, size: size)
                    .rotationEffect(.degrees(baseRotation + (animate ? 9 : -7)))
                    .offset(
                        x: animate ? size * 0.2 : -size * 0.2,
                        y: animate ? -size * 0.06 : size * 0.03
                    )
                    .scaleEffect(x: animate ? 1.02 : 0.98, y: animate ? 0.96 : 1.04)
                    .shadow(color: AppTheme.Colors.primary.opacity(0.24), radius: 10, x: 0, y: 4)
            }
        }
        .frame(width: size * 1.8, height: size * 1.6)
        .onAppear {
            guard !animate else { return }
            withAnimation(animation(for: kind)) {
                animate = true
            }
        }
    }

    private func animation(for kind: ElumiSnackKind) -> Animation {
        switch kind {
        case .algenkugel:
            return .easeInOut(duration: 1.45).repeatForever(autoreverses: true)
        case .wasserfloh:
            return .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
        case .wuermchen:
            return .easeInOut(duration: 1.15).repeatForever(autoreverses: true)
        }
    }
}

