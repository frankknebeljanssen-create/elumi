import SwiftUI

private struct QuizRewardTrail: Identifiable {
    let id = UUID()
    let kind: ElumiSnackKind
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let rotation: Double
    let scale: CGFloat
    let delay: Double
}

struct QuizRewardHeroView: View {
    let dominantKind: ElumiSnackKind
    let worms: Int
    let waterfloh: Int
    let algae: Int
    let accent: Color

    @State private var animateEntrance = false
    @State private var animateGlow = false
    @State private var animateSparkles = false

    private var totalRewardCount: Int {
        worms + waterfloh + algae
    }

    private var glowColor: Color {
        switch dominantKind {
        case .algenkugel:
            return AppTheme.Colors.success
        case .wasserfloh:
            return Color(hex: "#56D7F3")
        case .wuermchen:
            return AppTheme.Colors.primary
        }
    }

    private var flightKinds: [ElumiSnackKind] {
        var kinds: [ElumiSnackKind] = []

        if algae > 0 {
            kinds.append(.algenkugel)
        }
        if waterfloh > 0 {
            kinds.append(.wasserfloh)
        }
        if worms > 0 {
            kinds.append(.wuermchen)
        }

        if kinds.isEmpty {
            kinds = [dominantKind]
        }

        while kinds.count < 3 {
            kinds.append(dominantKind)
        }

        return Array(kinds.prefix(3))
    }

    private var trails: [QuizRewardTrail] {
        let startOffsets: [(CGFloat, CGFloat)]
        let endOffsets: [(CGFloat, CGFloat)] = [(-14, -12), (0, 16), (16, -10)]

        switch dominantKind {
        case .algenkugel:
            startOffsets = [(-90, -38), (0, 112), (88, -30)]
        case .wasserfloh:
            startOffsets = [(-96, 10), (0, 114), (94, 6)]
        case .wuermchen:
            startOffsets = [(-88, -28), (0, 112), (90, -22)]
        }

        return Array(flightKinds.enumerated()).map { index, kind in
            let start = startOffsets[index]
            let end = endOffsets[index]
            return QuizRewardTrail(
                kind: kind,
                startX: start.0,
                startY: start.1,
                endX: end.0,
                endY: end.1,
                rotation: index == 1 ? 0 : (index == 0 ? -18 : 18),
                scale: index == 1 ? 1 : 0.92,
                delay: 0.04 * Double(index)
            )
        }
    }

    private var sparkleOffsets: [CGSize] {
        switch dominantKind {
        case .algenkugel:
            return [
                CGSize(width: -36, height: -28),
                CGSize(width: 34, height: -24),
                CGSize(width: 0, height: 38)
            ]
        case .wasserfloh:
            return [
                CGSize(width: -38, height: -10),
                CGSize(width: 36, height: -10),
                CGSize(width: 0, height: -38)
            ]
        case .wuermchen:
            return [
                CGSize(width: -34, height: -30),
                CGSize(width: 38, height: -18),
                CGSize(width: 0, height: 36)
            ]
        }
    }

    @ViewBuilder
    private var centerRewardView: some View {
        if algae > 0 || waterfloh > 0 {
            ElumiSnackIcon(dominantKind, size: 58)
        } else {
            ElumiSnackCluster(count: worms, size: 42)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 104, height: 104)

            Circle()
                .fill(glowColor.opacity(animateGlow ? 0.24 : 0.1))
                .frame(width: animateGlow ? 126 : 102, height: animateGlow ? 126 : 102)
                .blur(radius: animateGlow ? 18 : 10)

            Circle()
                .stroke(glowColor.opacity(animateGlow ? 0.45 : 0.18), lineWidth: 2)
                .frame(width: animateGlow ? 112 : 96, height: animateGlow ? 112 : 96)

            if totalRewardCount > 0 {
                ForEach(trails) { trail in
                    ElumiSnackIcon(trail.kind, size: 24 * trail.scale)
                        .rotationEffect(.degrees(animateEntrance ? 0 : trail.rotation))
                        .offset(
                            x: animateEntrance ? trail.endX : trail.startX,
                            y: animateEntrance ? trail.endY : trail.startY
                        )
                        .scaleEffect(animateEntrance ? 0.7 : 1)
                        .opacity(animateEntrance ? 0 : 0.96)
                        .animation(
                            .easeIn(duration: 0.62).delay(trail.delay),
                            value: animateEntrance
                        )
                }

                centerRewardView
                    .scaleEffect(animateEntrance ? 1 : 0.28)
                    .rotationEffect(.degrees(animateEntrance ? 0 : -14))
                    .offset(y: animateEntrance ? 0 : 20)
                    .opacity(animateEntrance ? 1 : 0)
                    .shadow(color: glowColor.opacity(0.28), radius: 16, x: 0, y: 8)
                    .animation(
                        .interpolatingSpring(stiffness: 240, damping: 16)
                        .delay(0.12),
                        value: animateEntrance
                    )

                ForEach(Array(sparkleOffsets.enumerated()), id: \.offset) { index, offset in
                    Image(systemName: index == 2 ? "sparkles" : "star.fill")
                        .font(.system(size: index == 2 ? 15 : 10, weight: .bold))
                        .foregroundStyle(glowColor.opacity(index == 2 ? 0.95 : 0.82))
                        .offset(x: offset.width, y: offset.height)
                        .scaleEffect(animateSparkles ? 1 : 0.35)
                        .opacity(animateSparkles ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.55)
                            .delay(0.34 + Double(index) * 0.06),
                            value: animateSparkles
                        )
                }
            } else {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(accent)
                    .scaleEffect(animateEntrance ? 1 : 0.64)
                    .opacity(animateEntrance ? 1 : 0)
                    .animation(.spring(response: 0.52, dampingFraction: 0.76), value: animateEntrance)
            }
        }
        .frame(width: 126, height: 126)
        .onAppear {
            animateEntrance = false
            animateGlow = false
            animateSparkles = false

            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animateEntrance = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                animateSparkles = true
            }

            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
        }
    }
}

struct ElumiLevelTier: Identifiable, Equatable {
    let level: Int
    let threshold: Int
    let title: String
    let snackKind: ElumiSnackKind
    let rewardWorms: Int
    let rewardWaterfloh: Int
    let rewardAlgenkugel: Int

    var id: Int { level }
}

let elumiLevelTiers: [ElumiLevelTier] = [
    ElumiLevelTier(level: 1, threshold: 0, title: "Rookie", snackKind: .wuermchen, rewardWorms: 10, rewardWaterfloh: 0, rewardAlgenkugel: 0),
    ElumiLevelTier(level: 2, threshold: 100, title: "Explorer", snackKind: .wuermchen, rewardWorms: 20, rewardWaterfloh: 1, rewardAlgenkugel: 0),
    ElumiLevelTier(level: 3, threshold: 300, title: "Challenger", snackKind: .wasserfloh, rewardWorms: 20, rewardWaterfloh: 2, rewardAlgenkugel: 1),
    ElumiLevelTier(level: 4, threshold: 700, title: "Champion", snackKind: .wasserfloh, rewardWorms: 20, rewardWaterfloh: 3, rewardAlgenkugel: 1),
    ElumiLevelTier(level: 5, threshold: 1500, title: "Legend", snackKind: .algenkugel, rewardWorms: 20, rewardWaterfloh: 5, rewardAlgenkugel: 3)
]

func elumiLevelTier(for xp: Int) -> ElumiLevelTier {
    elumiLevelTiers.last(where: { xp >= $0.threshold }) ?? elumiLevelTiers[0]
}

func nextElumiLevelTier(for xp: Int) -> ElumiLevelTier? {
    elumiLevelTiers.first(where: { xp < $0.threshold })
}

private func elumiRewardDayIndex(for date: Date = .now) -> Int {
    let calendar = Calendar(identifier: .gregorian)
    let shiftedDate: Date

    if calendar.component(.hour, from: date) < 6,
       let previousDay = calendar.date(byAdding: .day, value: -1, to: date) {
        shiftedDate = previousDay
    } else {
        shiftedDate = date
    }

    let startOfDay = calendar.startOfDay(for: shiftedDate)
    return Int(startOfDay.timeIntervalSince1970 / 86_400)
}

func elumiStreakMultiplier(for streak: Int) -> Double {
    switch streak {
    case 30...:
        return 3.0
    case 14...:
        return 2.5
    case 7...:
        return 2.0
    case 3...:
        return 1.5
    default:
        return 1.0
    }
}

struct ElumiRewardOutcome {
    let worms: Int
    let waterfloh: Int
    let algenkugel: Int
    let xp: Int
    let currentStreak: Int
    let bestStreak: Int
    let lastRewardDayIndex: Int
    let unlockedLevels: [ElumiLevelTier]
}

func computeElumiRewardOutcome(
    baseWorms: Int,
    baseXP: Int,
    isPerfectLesson: Bool,
    currentXP: Int,
    currentStreak: Int,
    bestStreak: Int,
    lastRewardDayIndex: Int,
    now: Date = .now
) -> ElumiRewardOutcome {
    let todayIndex = elumiRewardDayIndex(for: now)

    let newCurrentStreak: Int
    if lastRewardDayIndex == 0 {
        newCurrentStreak = 1
    } else if lastRewardDayIndex == todayIndex {
        newCurrentStreak = max(1, currentStreak)
    } else if todayIndex - lastRewardDayIndex == 1 {
        newCurrentStreak = max(1, currentStreak + 1)
    } else {
        newCurrentStreak = 1
    }

    let streakMultiplier = elumiStreakMultiplier(for: newCurrentStreak)

    var worms = Int((Double(baseWorms) * streakMultiplier).rounded())
    var waterfloh = 0
    var algenkugel = 0
    var xp = baseXP

    if isPerfectLesson {
        worms += 5
        waterfloh += 1
        xp += 50
    }

    if lastRewardDayIndex != todayIndex {
        if newCurrentStreak == 7 {
            waterfloh += 1
            algenkugel += 1
            xp += 100
        } else if newCurrentStreak == 30 {
            waterfloh += 3
            algenkugel += 1
            xp += 300
        }
    }

    let oldXP = currentXP
    let updatedXP = currentXP + xp
    let unlockedLevels = elumiLevelTiers.filter { $0.threshold > oldXP && $0.threshold <= updatedXP }

    for level in unlockedLevels {
        worms += level.rewardWorms
        waterfloh += level.rewardWaterfloh
        algenkugel += level.rewardAlgenkugel
    }

    return ElumiRewardOutcome(
        worms: worms,
        waterfloh: waterfloh,
        algenkugel: algenkugel,
        xp: xp,
        currentStreak: newCurrentStreak,
        bestStreak: max(bestStreak, newCurrentStreak),
        lastRewardDayIndex: todayIndex,
        unlockedLevels: unlockedLevels
    )
}
