import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeaderCard(
                    style: sectionStyle,
                    title: "Info",
                    subtitle: "",
                    systemImage: "info.circle.fill"
                )

                infoCard(
                    title: "So startest du",
                    lines: [
                        "Wähle zuerst, was du machen möchtest.",
                        "Trainieren fragt direkt ab.",
                        "Karteikarten üben arbeitet einen Stapel ab."
                    ]
                )

                infoCard(
                    title: "Scan",
                    lines: [
                        "Wähle zuerst Vokabelliste oder freien Text.",
                        "Fotografiere dann die Vorlage oder wähle ein Bild.",
                        "Prüfe kurz die erkannten Paare.",
                        "Importiere sie in eine Liste und lerne direkt weiter."
                    ]
                )

                infoCard(
                    title: "Listen verwalten",
                    lines: [
                        "Lege eigene Listen an.",
                        "Benenne Listen um oder lösche sie.",
                        "Öffne eine Liste, um Einträge zu bearbeiten."
                    ]
                )

                infoCard(
                    title: "Beim Lernen",
                    lines: [
                        "Du kannst sprechen oder tippen.",
                        "Bei Karteikarten bleiben falsche Karten im Stapel.",
                        "Mit Home kommst du jederzeit zurück ins Hauptmenü."
                    ]
                )
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppLayout.screenPadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() })
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

    private func infoCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }
}
