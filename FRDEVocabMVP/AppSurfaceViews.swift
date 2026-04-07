import SwiftUI

struct AppSurfaceCard<Content: View>: View {
    let tint: Color?
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        tint: Color? = nil,
        padding: CGFloat = AppTheme.Layout.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if let tint {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .stroke(tint.opacity(0.16), lineWidth: 1)
                        }
                    }
            }
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y
            )
    }
}

struct AppBarSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            content
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.chromeBarHeight)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }
}

struct AppListItemRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let tint: Color
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}

struct AppFolderItemRow: View {
    let title: String
    let subtitle: String?
    let tint: Color

    var body: some View {
        AppListItemRow(
            icon: "folder.fill",
            title: title,
            subtitle: subtitle,
            tint: tint
        )
    }
}

struct AppProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.secondarySurface)

                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

struct AppDialogCard<Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Content

    init(title: String, message: String, @ViewBuilder actions: () -> Content) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(title)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(message)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }
        }
    }
}

struct AppSheetHeader: View {
    let title: String
    var leadingTitle: String = "Zurück"
    var trailingTitle: String? = nil
    var leadingTint: Color = AppTheme.Colors.primary
    var trailingTint: Color = AppTheme.Colors.primary
    let onLeading: () -> Void
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button(leadingTitle, action: onLeading)
                .buttonStyle(.plain)
                .font(AppTheme.Typography.body)
                .foregroundStyle(leadingTint)

            Spacer(minLength: 0)

            Text(title)
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            if let trailingTitle, let onTrailing {
                Button(trailingTitle, action: onTrailing)
                    .buttonStyle(.plain)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(trailingTint)
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
    }
}
