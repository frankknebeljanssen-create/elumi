import SwiftUI

/// Profilansicht V1 — bewusst schlank gehalten.
///
/// Enthält:
/// • Hero mit Avatar-Badge (groß), Name, Lernziel
/// • Inline-Bearbeiten für Name + Lernziel
/// • Nebenweg zu den technischen Settings
///
/// **Nicht enthalten** (bewusst, kommt später):
/// • Komplexer Account-Bereich / Auth
/// • Cloud-Funktionen / Multi-Profile
/// • Avatar-Editor
/// • Große Statistik-Seiten
///
/// Die Ansicht liest ausschließlich aus `ProfileStore.shared` — keine
/// @AppStorage-Direktzugriffe, keine eigenen Namens-Strings.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void

    @State private var isEditing: Bool = false
    @State private var draftName: String = ""
    @State private var draftGoal: LearningGoal?
    @FocusState private var isNameFocused: Bool

    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                profileHero

                if isEditing {
                    editCard
                } else {
                    displayCard
                }

                // Kleine, ruhige Progress-Snapshots — nur wenn wir Daten
                // haben, die wir ohne Kopplung lesen können. Kommt direkt
                // vom zentralen ProgressStore (keine eigene Gamification-
                // Logik hier im Profil).
                progressSnapshotCard

                secondaryLinksCard

                Spacer(minLength: 0)
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

    // MARK: - Hero

    /// Großer Avatar + Name + kleiner Lernziel-Chip. Setzt den persönlichen
    /// Ton gleich am Anfang, ohne den Screen zu überladen.
    private var profileHero: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ProfileAvatarBadge(store: profileStore, size: 84)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)

            Text(profileStore.hasName ? profileStore.displayName : "Dein Profil")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let goal = profileStore.profile?.learningGoal {
                HStack(spacing: 6) {
                    Image(systemName: goal.systemImage)
                        .font(.system(size: 12, weight: .bold))
                    Text(goal.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(sectionStyle.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(sectionStyle.accent.opacity(0.14))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Display Card (Name + Lernziel read-only + Edit-Button)

    private var displayCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Name row
            HStack(alignment: .firstTextBaseline) {
                Text("Name")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text(profileStore.hasName ? profileStore.displayName : "—")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Divider().opacity(0.4)

            // Lernziel row
            HStack(alignment: .firstTextBaseline) {
                Text("Lernziel")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text(profileStore.profile?.learningGoal?.title ?? "Noch nicht gesetzt")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        profileStore.profile?.learningGoal == nil
                            ? AppTheme.Colors.textSecondary
                            : AppTheme.Colors.textPrimary
                    )
                    .multilineTextAlignment(.trailing)
            }

            Button {
                beginEditing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                    Text("Profil bearbeiten")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.top, 4)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    // MARK: - Edit Card (Name + Lernziel bearbeiten)

    private var editCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                TextField("Dein Vorname", text: $draftName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Lernziel")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                VStack(spacing: 6) {
                    ForEach(LearningGoal.allCases) { goal in
                        goalToggleButton(goal: goal)
                    }
                    if draftGoal != nil {
                        Button {
                            feedbackPlayer.playToggle()
                            draftGoal = nil
                        } label: {
                            Text("Kein Lernziel")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    cancelEditing()
                } label: {
                    Text("Abbrechen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

                Button {
                    saveEditing()
                } label: {
                    Text("Speichern")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(
                    color: canSave ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled
                ))
                .disabled(!canSave)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    @ViewBuilder
    private func goalToggleButton(goal: LearningGoal) -> some View {
        let isSelected = draftGoal == goal
        Button {
            feedbackPlayer.playToggle()
            withAnimation(.easeInOut(duration: 0.12)) {
                draftGoal = isSelected ? nil : goal
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: goal.systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? sectionStyle.accent : AppTheme.Colors.textSecondary)
                    .frame(width: 22)

                Text(goal.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? sectionStyle.accent.opacity(0.5) : AppTheme.Colors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginEditing() {
        draftName = profileStore.profile?.displayName ?? ""
        draftGoal = profileStore.profile?.learningGoal
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isNameFocused = true
        }
    }

    private func cancelEditing() {
        isNameFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
    }

    private func saveEditing() {
        guard canSave else { return }
        feedbackPlayer.playStudyAchievement()
        profileStore.update { profile in
            profile.displayName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.learningGoal = draftGoal
        }
        isNameFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
    }

    // MARK: - Progress Snapshot

    /// Kompakter Fortschritts-Spiegel. Bewusst *nur* lesender Zugriff auf
    /// `ProgressStore.shared.progress` — keine eigene Gamification-Logik
    /// hier im Profil, damit die Trennung sauber bleibt.
    private var progressSnapshotCard: some View {
        let progress = progressStore.progress
        return HStack(spacing: 0) {
            snapshotCell(
                value: "\(progress.level)",
                label: "Level",
                systemImage: "star.fill",
                tint: sectionStyle.accent
            )
            snapshotDivider
            snapshotCell(
                value: "\(progress.totalXP)",
                label: "XP",
                systemImage: "sparkles",
                tint: AppTheme.Colors.cta
            )
            snapshotDivider
            snapshotCell(
                value: "\(progress.currentStreak)",
                label: progress.currentStreak == 1 ? "Tag Streak" : "Tage Streak",
                systemImage: "flame.fill",
                tint: Color(hex: "#FF9F40")
            )
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .appCardBackground(sectionStyle, intensity: 0.07)
    }

    @ViewBuilder
    private func snapshotCell(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var snapshotDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.border.opacity(0.6))
            .frame(width: 1, height: 44)
    }

    // MARK: - Secondary Links

    /// Nebenweg zu technischen App-Einstellungen. Bewusst als Sekundär-Link,
    /// nicht als Haupt-Aktion — das Profil ist die persönliche Hülle,
    /// Settings die technische Schicht darunter.
    private var secondaryLinksCard: some View {
        VStack(spacing: 0) {
            Button {
                openSettings()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 22)
                    Text("App-Einstellungen")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .appCardBackground(sectionStyle, intensity: 0.06)
    }
}
