import SwiftUI

struct HeartsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appQuizHeartsKey) var collectedWorms = 0
    @AppStorage(appElumiWaterflohKey) var collectedWaterfloh = 0
    @AppStorage(appElumiAlgenkugelKey) var collectedAlgenkugel = 0
    @AppStorage(appElumiXPKey) var collectedXP = 0
    @AppStorage(appElumiCurrentStreakKey) var currentStreak = 0
    @AppStorage(appElumiBestStreakKey) var bestStreak = 0
    // Profilname wird zentral aus dem ProfileStore gelesen — kein eigener
    // @AppStorage-Slot mehr, damit der Screen ohne Umwege reagiert, wenn
    // der User seinen Namen im Profil ändert.
    @ObservedObject var profileStore: ProfileStore = .shared
    // Tagesaufgabe — wird im Lernstand-Strip als dezente Footer-Zeile
    // eingeblendet, damit der Hub ohne eigene Mission-Sektion auskommt.
    @ObservedObject var dailyChallengeStore: DailyChallengeStore = .shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @ObservedObject var listStore: VocabularyListStore
    let goHome: () -> Void
    let openSettings: () -> Void
    let sectionStyle: AppSectionStyle = .hearts

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Progress Hub — Phase 2 Redesign:
            // Weg von „N kleine Einzelkarten gestapelt", hin zu *wenigen,
            // klar getitelten Sektionen* mit einem dominanten Hero.
            //
            // Struktur:
            //  1) Titel + personalisierter Untertitel
            //  2) Hero (Level, XP, Progress, Meilenstein → in **einer** Karte)
            //  3) Beute-Sektion (3 Währungen, eine Gruppe)
            //  4) Lernstand-Sektion (Streak + Multiplier + Streak-Meilenstein)
            //  5) Dein-Weg-Sektion (Level-Liste, eine Container-Karte mit Rows)
            //
            // Visueller Rhythmus: generös zwischen Sektionen (`Spacing.lg`),
            // eng innerhalb (`10pt`). Kein doppeltes Card-Chrome mehr.
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                progressHubHeader

                progressHeroCard

                VStack(alignment: .leading, spacing: 10) {
                    ProgressSectionHeader(
                        title: "Beute",
                        subtitle: "Was du dir erspielt hast."
                    )
                    resourceStrip
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProgressSectionHeader(
                        title: "Lernstand",
                        subtitle: learningStandSubtitle
                    )
                    learningStandStrip
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProgressSectionHeader(
                        title: "Dein Weg",
                        subtitle: "Erreicht · aktuell · kommt noch."
                    )
                    levelPathList
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: nil)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            // Progress Hub ist nicht mehr der Footer-Favorite-Target — der
            // Snack-Button öffnet jetzt den Game Hub. Daher `isHeartsActive: false`.
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() },
                isHeartsActive: false
            )
        }
    }

}
