import SwiftUI

/// **Legacy** — nicht mehr via `.account`-Route geöffnet. Die aktive
/// Profilansicht ist jetzt `ProfileView`. Diese Datei bleibt nur noch,
/// damit externe Call-Sites (falls irgendwo ein Direkt-Aufruf übersehen
/// wurde) nicht brechen. Kann bei der nächsten Aufräum-Runde entfernt
/// werden — der Route-Host zeigt ausschließlich `ProfileView`.
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    /// Backing-Binding, damit die alte Text-Field-UI mit minimalem Umbau
    /// weiter funktioniert. Schreibt über den ProfileStore zurück.
    private var firstNameBinding: Binding<String> {
        Binding(
            get: { profileStore.profile?.displayName ?? "" },
            set: { newValue in
                profileStore.update { $0.displayName = newValue }
            }
        )
    }
    private var firstName: String { profileStore.displayName }
    private let sectionStyle = AppSectionStyle.home

    var body: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Account",
                subtitle: "",
                systemImage: "person.crop.circle.fill"
            )

            Button {
                dismiss()
            } label: {
                Label("Zur\u{00FC}ck", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

            VStack(alignment: .leading, spacing: 10) {
                Text("Vorname")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                TextField("Dein Vorname", text: firstNameBinding)
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
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)

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

