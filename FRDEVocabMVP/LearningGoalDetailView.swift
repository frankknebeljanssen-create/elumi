import SwiftUI

// LearningGoalDetailView.swift
// **Ziel-System Phase 3 (2026-08-05)** — der Screen, auf dem das Ziel
// tatsächlich geändert wird.
//
// Löst das Versprechen aus dem Onboarding ein ("Keine Sorge, du kannst
// dein Ziel jederzeit ändern!"). Vorher gab es dafür keine Oberfläche —
// das Ziel war nur über die Dev-Card erreichbar.
//
// **Aufteilung der beiden Ebenen** (siehe `LearningGoalPlan`):
//   • Das **Tagesziel** wird hier direkt geändert. Das ist die
//     Stellschraube, die man realistisch öfter anfasst ("20 Minuten war
//     zu viel").
//   • Das **Inhaltsziel** wird nicht hier zusammengeklickt, sondern über
//     "Neues Ziel setzen" — das löscht den Plan, wodurch das
//     Onboarding-Overlay wieder erscheint (`shouldShowGoalOnboarding`
//     prüft auf `plan == nil`). So gibt es die Anlass-/Termin-/Listen-
//     Auswahl genau EINMAL im Code statt zweimal.
//
// Tagesziel-Änderung kostet bewusst keinen Fortschritt: `updateDailyTarget`
// lässt den heutigen Zähler unangetastet. Wer mittags von 20 auf 10
// Minuten geht, soll nicht bei null landen.
struct LearningGoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject private var goalStore = LearningGoalStore.shared
    let goHome: () -> Void
    let openSettings: () -> Void

    @State private var isShowingResetConfirm = false

    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        ScrollView(showsIndicators: false) {
            // **2026-08-05** — Spacing gestrafft (User-Spec: „oben unter
            // dein Ziel sehr viel Luft, unten ist neues Zielsetzen halb
            // verdeckt durch den Footer, das darf nicht scrollbar sein
            // müssen"). `.lg` → `.sm` (analog TrophyView), Top-Padding von
            // `contentTopPadding` (32 pt) auf `screenHeaderTopPadding`
            // (4 pt) — der systemweite Wert für Screens mit
            // `ScreenHeaderCard` — und Bottom-Padding von `.xxl` (32 pt)
            // auf `.md` (16 pt), weil der Footer bereits über
            // `safeAreaInset` reserviert wird (siehe TrophyView-Kommentar
            // zum selben Fix).
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ScreenHeaderCard(
                    style: sectionStyle,
                    title: "Dein Ziel",
                    subtitle: "",
                    systemImage: nil,
                    onBack: { dismiss() },
                    centeredTitle: true,
                    onHelp: { ElumiHelpPresenter.shared.show(.goal) }
                )

                if goalStore.plan == nil {
                    emptyState
                } else {
                    rhythmSection
                    if let content = goalStore.plan?.content {
                        contentSection(content)
                    }
                    // **2026-08-06** — eigener Abstand nach oben (User-
                    // Spec: "'n bisschen absetzen"), damit der Button
                    // nicht wie eine vierte, gleichrangige Zeile direkt
                    // an den Inhaltsziel-Block anschließt, sondern klar
                    // als eigene, andersartige Aktion danach kommt.
                    Spacer(minLength: AppTheme.Spacing.sm)
                    newGoalButton
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Spacing.md)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: nil)
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
        // **2026-08-05** — eigenes Sheet statt `.alert(...)` (User-Spec:
        // "bitte nie keine grauen Popups, nicht mehr, das sieht aus wie
        // eine Geschäftsapp"). System-Alerts sind fix grau/weiß und
        // nicht themebar. Gleiches Muster wie `SectionInfoSheet` und
        // `WackelkandidatenConfirmationSheet` im Lernstatus.
        .sheet(isPresented: $isShowingResetConfirm) {
            NewGoalConfirmSheet(
                onConfirm: {
                    isShowingResetConfirm = false
                    // Plan löschen → `RootContentView.shouldShowGoalOnboarding`
                    // greift und legt das Onboarding-Overlay wieder über
                    // die App. Kein zweiter Satz Auswahl-Screens nötig.
                    goalStore.reset()
                    goHome()
                },
                onCancel: { isShowingResetConfirm = false }
            )
        }
    }

    // MARK: - Tagesziel

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Wie viel Zeit hast du am Tag?")

            let progress = goalStore.dailyProgress
            HStack(spacing: 8) {
                Text(progress.isReached
                     ? "Heute geschafft! 🎉"
                     : (progress.remainingItems == 1
                        ? "Noch 1 Vokabel heute"
                        : "Noch \(progress.remainingItems) Vokabeln heute"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(progress.isReached ? accentGreen : AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text("\(progress.doneItems)/\(progress.targetItems)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            VStack(spacing: 6) {
                ForEach(LearningGoalPlan.dailyTargetMinuteOptions, id: \.self) { minutes in
                    rhythmOption(minutes)
                }
            }

            Text("Ändern kostet dich nichts. Dein heutiger Fortschritt bleibt stehen.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func rhythmOption(_ minutes: Int) -> some View {
        let isSelected = goalStore.plan?.dailyTargetMinutes == minutes
        return Button {
            feedbackPlayer.playListAction()
            goalStore.updateDailyTarget(minutes: minutes)
        } label: {
            HStack(spacing: 12) {
                Text("\(minutes)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? accentGreen : AppTheme.Colors.textPrimary)
                    .frame(width: 30)
                    .monospacedDigit()

                Text("Minuten am Tag")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                Text(LearningGoalPlan.dailyTargetLabel(for: minutes))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(accentGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(isSelected ? accentGreen : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(AppCardPressStyle())
    }

    // MARK: - Inhaltsziel

    private func contentSection(_ content: LearningGoalContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Was du dir vorgenommen hast")

            HStack(spacing: 12) {
                Text(content.occasion.emoji)
                    .font(.system(size: 28))
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.displayTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let days = content.daysRemaining() {
                        Text(days < 0
                             ? "Termin war vor \(-days) Tag(en)"
                             : (days == 0 ? "Heute!" : "Noch \(days) Tag(e)"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if content.isAwaitingList {
                Text("Diesem Ziel fehlen noch die Vokabeln.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.error)
            } else if let progress = goalStore.contentProgress(listStore: listStore),
                      !progress.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(progress.strongCount) von \(progress.totalCount) sitzen")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text("\(Int(progress.fraction * 100)) %")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(accentGreen)
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.18))
                            Capsule()
                                .fill(accentGreen)
                                .frame(width: geo.size.width * progress.fraction)
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
        // **2026-08-06** — Grüner Rand + leichte Grün-Füllung (User-Spec:
        // "das kommt aus dem Onboarding und geht da 'n bisschen unter").
        // Vorher trug diese Card denselben neutralen Rahmen wie
        // `rhythmSection` direkt darüber — nichts unterschied "was du dir
        // vorgenommen hast" (Anlass aus dem Onboarding) vom Rhythmus
        // (der hier direkt geändert wird). Dieselbe Akzentfarbe wie im
        // Onboarding selbst (`accentGreen` = `moduleNomen`), keine neu
        // erfundene.
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(accentGreen.opacity(0.5), lineWidth: 1.5)
        )
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(accentGreen.opacity(0.08))
        )
    }

    // MARK: - Bausteine

    /// **2026-08-06** — Farbe von neutralem `textPrimary` auf `warning`
    /// (Amber) gewechselt (User-Spec: "farbig noch anders kennzeichnen").
    /// Signalisiert "das ist eine andere Art von Aktion als der Rest
    /// dieses Screens" — passend, weil sie den Rhythmus zurücksetzt und
    /// erneut durchs Onboarding führt, nicht bloß eine Einstellung ändert.
    private var newGoalButton: some View {
        Button {
            isShowingResetConfirm = true
        } label: {
            Text("Neues Ziel setzen")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.warning))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Du hast noch kein Ziel")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Starte die App neu, dann führt dich Elumi durch die Zielauswahl.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
    }

    private var accentGreen: Color { AppTheme.Colors.moduleNomen }
}

/// **2026-08-05** — Bestätigung im Elumi-Design statt System-Alert.
/// Der graue iOS-Alert ist nicht themebar und bricht die Bildsprache
/// („sieht aus wie eine Geschäftsapp"). Aufbau bewusst identisch zu den
/// anderen Popups der App: Icon-Kreis, Titel, Erklärtext, Aktion,
/// unauffälliger Abbruch darunter.
private struct NewGoalConfirmSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(AppTheme.Colors.cta.opacity(0.18))
                    .frame(width: 84, height: 84)
                Text("🎯")
                    .font(.system(size: 38))
            }

            VStack(spacing: 8) {
                Text("Neues Ziel setzen?")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Du gehst die Fragen noch einmal durch. Dein Wochenfortschritt fängt dabei von vorne an.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Button(action: onConfirm) {
                Text("Neues Ziel")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.horizontal, 24)
            .padding(.top, 4)

            Button("Doch nicht") { onCancel() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: 20)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.background)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}
