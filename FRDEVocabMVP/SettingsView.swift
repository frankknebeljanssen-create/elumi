import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @Environment(\.appOpenAccountAction) private var openAccountAction
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openInfo: () -> Void
    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Einstellungen",
                subtitle: "",
                systemImage: "gearshape.fill"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Ton")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Spacer(minLength: 0)

                    Image(systemName: feedbackPlayer.areSoundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }

                Toggle(isOn: $feedbackPlayer.areSoundsEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feedbackPlayer.areSoundsEnabled ? "Ton an" : "Ton aus")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("Startsound und Feedback-Töne")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(sectionStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .appCardBackground(sectionStyle, intensity: 0.09)

            Button {
                openAccountAction?()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mein Konto")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Vorname und Profil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: 0.09)
            }
            .buttonStyle(.plain)

            Button {
                openInfo()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Info")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Hilfe und Hinweise zur App")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: 0.09)
            }
            .buttonStyle(.plain)

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
                onSettings: nil,
                isSettingsActive: true
            )
        }
    }
}

