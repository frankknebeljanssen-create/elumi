import SwiftUI

struct CompactSelectionChip: View {
    let style: AppSectionStyle
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(value)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .appChipBackground(style)
    }
}

struct HomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let cardColor: Color

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            VStack(spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)

            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(accentColor)

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: AppLayout.homeCardHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                        .fill(cardColor)
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
    }
}

struct WideHomeActionButton: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let cardColor: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Name und Profil")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: AppLayout.homeWideCardHeight, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                        .fill(cardColor)
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
    }
}

struct FlashcardStackVisual: View {
    let remainingCount: Int
    let totalCount: Int

    private var remainingRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(remainingCount) / Double(totalCount)
    }

    private var visibleLayers: Int {
        if remainingCount <= 0 {
            return 1
        }
        return max(1, Int(ceil(remainingRatio * 6)))
    }

    private var frontColor: Color {
        if remainingCount <= 0 {
            return Color.green.opacity(0.18)
        }
        return AppSectionStyle.flashcards.accent.opacity(0.16)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(0..<visibleLayers, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(index == 0 ? frontColor : Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(index == 0 ? 0.08 : 0.04), lineWidth: 1)
                        )
                        .frame(width: 134 - CGFloat(index * 7), height: 58 - CGFloat(index * 2))
                        .offset(y: CGFloat(index * 5))
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }

                VStack(spacing: 2) {
                    Text("\(remainingCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .offset(y: 4)
            }
            .frame(height: 82)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FlashcardStackBadge: View {
    let remainingCount: Int
    let totalCount: Int

    private var remainingRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(remainingCount) / Double(totalCount)
    }

    private var visibleLayers: Int {
        if remainingCount <= 0 {
            return 1
        }
        return max(1, Int(ceil(remainingRatio * 4)))
    }

    private var frontColor: Color {
        if remainingCount <= 0 {
            return Color.green.opacity(0.18)
        }
        return AppSectionStyle.flashcards.accent.opacity(0.18)
    }

    var body: some View {
        ZStack {
            ForEach(0..<visibleLayers, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(index == 0 ? frontColor : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(index == 0 ? 0.08 : 0.04), lineWidth: 1)
                    )
                    .frame(width: 64 - CGFloat(index * 4), height: 30 - CGFloat(index * 2))
                    .offset(y: CGFloat(index * 3))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }

            Text("\(remainingCount)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .offset(y: 2)
        }
        .frame(width: 68, height: 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(remainingCount) Karten im Stapel"))
    }
}
