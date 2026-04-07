import SwiftUI

struct ScreenHeaderCard: View {
    let style: AppSectionStyle
    let title: String
    let subtitle: String
    let systemImage: String
    var actionTitle: String? = nil
    var actionSystemImage: String = "house.fill"
    var action: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryActionSystemImage: String = "gearshape.fill"
    var secondaryAction: (() -> Void)? = nil

    private var titleParts: [String] {
        subtitle.isEmpty ? [title] : [title, subtitle]
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: subtitle.isEmpty ? 0 : 4) {
                Text(title)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            ZStack {
                Circle()
                    .fill(style.accent.opacity(0.12))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(style.accent)
            }
            .frame(width: 34, height: 34)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppLayout.headerHeight)
    }
}

struct AppTopBar: View {
    @Environment(\.appOpenAccountAction) private var globalOpenAccountAction
    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue
    var onBack: (() -> Void)? = nil
    var onInfo: (() -> Void)? = nil
    var onAccount: (() -> Void)? = nil

    private var selectedDirection: Direction {
        (Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    private var resolvedAccountAction: (() -> Void)? {
        onAccount ?? globalOpenAccountAction
    }

    private func sourceCountryCode(for direction: Direction) -> String {
        switch direction {
        case .frenchToGerman:
            return "FR"
        case .germanToFrench:
            return "DE"
        case .englishToGerman:
            return "GB"
        case .germanToEnglish:
            return "DE"
        }
    }

    private func targetCountryCode(for direction: Direction) -> String {
        switch direction {
        case .frenchToGerman:
            return "DE"
        case .germanToFrench:
            return "FR"
        case .englishToGerman:
            return "DE"
        case .germanToEnglish:
            return "GB"
        }
    }

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .background(AppTheme.Colors.secondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .accessibilityLabel(Text("Zurück"))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(Direction.frenchOnlyCases) { direction in
                    Button {
                        selectedDirectionRaw = direction.rawValue
                    } label: {
                        Text("\(direction.sourceFlag) → \(direction.targetFlag)  \(direction.compactLabel)")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    StraightFlagBadge(countryCode: sourceCountryCode(for: selectedDirection))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    StraightFlagBadge(countryCode: targetCountryCode(for: selectedDirection))
                }
                .frame(minWidth: 62, minHeight: 30)
                .padding(.horizontal, 8)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .background(AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                .accessibilityLabel(Text(selectedDirection.compactLabel))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 10)
                .frame(width: 10)

            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .background(AppTheme.Colors.secondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .accessibilityLabel(Text("Info"))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 10)
                    .frame(width: 10)
            }

            if let resolvedAccountAction {
                Button(action: resolvedAccountAction) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .background(AppTheme.Colors.secondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .accessibilityLabel(Text("Account"))
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(AppTopBarSurfaceModifier())
    }
}

struct StraightFlagBadge: View {
    let countryCode: String
    var width: CGFloat = 18
    var height: CGFloat = 12
    var labelFontSize: CGFloat = 8

    private var cornerRadius: CGFloat {
        max(3, height * 0.25)
    }

    var body: some View {
        ZStack {
            switch countryCode {
            case "FR":
                HStack(spacing: 0) {
                    Color(red: 0.02, green: 0.22, blue: 0.67)
                    Color.white
                    Color(red: 0.88, green: 0.16, blue: 0.22)
                }
            case "DE":
                VStack(spacing: 0) {
                    Color.black
                    Color(red: 0.78, green: 0.0, blue: 0.07)
                    Color(red: 1.0, green: 0.81, blue: 0.0)
                }
            case "GB":
                ZStack {
                    Color(red: 0.05, green: 0.16, blue: 0.45)
                    Text("GB")
                        .font(.system(size: labelFontSize, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            default:
                ZStack {
                    AppTheme.Colors.secondarySurface
                    Text(countryCode)
                        .font(.system(size: labelFontSize, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 1.5, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}
