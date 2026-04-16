import SwiftUI

struct ScreenHeaderCard: View {
    let style: AppSectionStyle
    let title: String
    let subtitle: String
    /// Optionales SF-Symbol für den Icon-Kreis rechts. Wenn `nil`, wird
    /// kein Icon-Kreis gezeichnet — der Header bekommt dann das klassische
    /// Navigation-Bar-Layout (Back links, Titel zentriert, rechts leer).
    let systemImage: String?
    var actionTitle: String? = nil
    var actionSystemImage: String = "house.fill"
    var action: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryActionSystemImage: String = "gearshape.fill"
    var secondaryAction: (() -> Void)? = nil
    /// Optionaler Back-Closure. Wenn gesetzt, erscheint links ein
    /// dezenter „< "-Button im gleichen Stil wie der Session-Setup-
    /// Header und der (unter globalChrome unsichtbare) `AppTopBar`.
    /// So wird die Zurück-Navigation bei „normalen" Screens (Listen,
    /// Lexikon, Info, Settings) sichtbar und konsistent — unabhängig
    /// davon, ob das globale Chrome aktiv ist.
    var onBack: (() -> Void)? = nil
    /// Wenn `true`, wird der Titel in der Mitte gesetzt (klassischer
    /// Nav-Bar-Look). Rechts wird bei fehlendem Icon ein unsichtbarer
    /// 34×34-Platzhalter gezeichnet, damit der Titel exakt mittig sitzt.
    var centeredTitle: Bool = false

    private var titleParts: [String] {
        subtitle.isEmpty ? [title] : [title, subtitle]
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            leadingSlot

            if centeredTitle {
                Spacer(minLength: 0)
            }

            VStack(alignment: centeredTitle ? .center : .leading, spacing: subtitle.isEmpty ? 0 : 4) {
                Text(title)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(centeredTitle ? .center : .leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(centeredTitle ? .center : .leading)
                }
            }

            if centeredTitle {
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: AppTheme.Spacing.sm)
            }

            trailingSlot
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppLayout.headerHeight)
        // Systemweites Padding unter dem Header — gleicher Abstand zum
        // nächsten Content-Block auf **jedem** Screen.
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }

    // MARK: - Slots

    @ViewBuilder
    private var leadingSlot: some View {
        if let onBack {
            // Systemweiter Back-Button — nackter Pfeil, kein Rahmen.
            AppBackButton(action: onBack)
        } else if centeredTitle {
            // Symmetric placeholder, damit der Titel bei fehlendem
            // Back-Button trotzdem sauber mittig sitzt. 44 pt = Breite
            // des AppBackButton-Touch-Targets.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        if let systemImage {
            ZStack {
                Circle()
                    .fill(style.accent.opacity(0.12))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(style.accent)
            }
            .frame(width: 34, height: 34)
        } else if centeredTitle {
            // Ohne Trailing-Icon braucht der zentrierte Titel rechts
            // einen Platzhalter von 44×44 — exakt die Breite des
            // Back-Buttons links, damit der Text wirklich mittig sitzt.
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

struct AppTopBar: View {
    @Environment(\.appOpenAccountAction) private var globalOpenAccountAction
    @ObservedObject private var profileStore = ProfileStore.shared
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
                // Systemweiter Back-Button — kein Rahmen mehr, einheitlich
                // mit allen anderen Screens und Headern.
                AppBackButton(action: onBack)
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
                // Profil-Zugang: runder Avatar-Badge statt neutralem Icon.
                // Zeigt Initialen, sobald ein Name gesetzt ist — sonst
                // Personen-Icon. Sichtbar-aber-dezent, matcht Top-Bar-Look.
                Button(action: resolvedAccountAction) {
                    ProfileAvatarBadge(store: profileStore, size: 30)
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
