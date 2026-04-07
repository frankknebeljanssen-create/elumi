import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appFirstNameKey) private var firstName = "Frank"
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    private let sectionStyle = AppSectionStyle.home

    var body: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Account",
                subtitle: "",
                systemImage: "person.crop.circle.fill"
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Vorname")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                TextField("Frank", text: $firstName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.white.opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("Dieser Name wird im Startscreen und in der App verwendet.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .appCardBackground(sectionStyle, intensity: 0.09)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() }
            )
        }
    }
}

