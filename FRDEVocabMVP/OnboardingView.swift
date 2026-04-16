import SwiftUI

/// Erststart-Onboarding — sehr leichtgewichtig, freundlich, in ≤ 2 Schritten
/// abschließbar. **Kein Registrierungsgefühl**: keine E-Mail, kein Passwort,
/// keine Agreements, keine technische Sprache.
///
/// Rendering: Root-View entscheidet per `ProfileStore.hasCompletedOnboarding`,
/// ob diese View oder die normale NavigationStack-Home dargestellt wird.
/// Nach `completeOnboarding(...)` flippt das Flag → Root switcht automatisch.
///
/// Schritt 1 („Wie sollen wir dich nennen?") ist verpflichtend.
/// Schritt 2 (Lernziel) ist optional und kann übersprungen werden.
struct OnboardingView: View {
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var feedbackPlayer: FeedbackPlayer

    @State private var typedName: String = ""
    @State private var selectedGoal: LearningGoal?
    @State private var step: Step = .name
    @FocusState private var isNameFocused: Bool

    private let sectionStyle: AppSectionStyle = .home

    enum Step { case name, goal }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            // Sanfter Farbverlauf im Hintergrund, damit das Onboarding visuell
            // nicht „leer" wirkt, ohne die Home-Optik vorwegzunehmen.
            LinearGradient(
                colors: [
                    sectionStyle.accent.opacity(0.10),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Group {
                    switch step {
                    case .name: nameStep
                    case .goal: goalStep
                    }
                }
                .frame(maxWidth: AppTheme.Layout.maxContentWidth)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
        }
        .dismissKeyboardOnTap()
        .transition(.opacity)
    }

    // MARK: - Schritt 1: Name

    private var nameStep: some View {
        VStack(spacing: 20) {
            welcomeHeader(
                icon: "hand.wave.fill",
                title: "Willkommen bei Elumi",
                subtitle: "Wie sollen wir dich nennen?"
            )

            VStack(alignment: .leading, spacing: 10) {
                TextField("Dein Vorname", text: $typedName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($isNameFocused)
                    .onSubmit { advanceFromName() }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    )

                Text("Der Name bleibt auf deinem Gerät.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Button {
                advanceFromName()
            } label: {
                HStack(spacing: 8) {
                    Text("Weiter")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(
                color: canAdvanceFromName ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled
            ))
            .disabled(!canAdvanceFromName)
        }
        .onAppear {
            // Prefill, falls eine Legacy-Migration einen Namen mitgebracht
            // hat (User startet das Onboarding über Profil-Reset später).
            if typedName.isEmpty, let existing = profileStore.profile?.displayName {
                typedName = existing
            }
            // Kurzer Delay, damit der Fokus nach dem Step-Wechsel sauber sitzt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isNameFocused = true
            }
        }
    }

    private var canAdvanceFromName: Bool {
        !typedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func advanceFromName() {
        guard canAdvanceFromName else { return }
        isNameFocused = false
        feedbackPlayer.playToggle()
        withAnimation(.easeInOut(duration: 0.28)) {
            step = .goal
        }
    }

    // MARK: - Schritt 2: Lernziel

    private var goalStep: some View {
        VStack(spacing: 16) {
            welcomeHeader(
                icon: "target",
                title: "Was möchtest du üben?",
                subtitle: "Du kannst das später jederzeit ändern."
            )

            VStack(spacing: 8) {
                ForEach(LearningGoal.allCases) { goal in
                    goalButton(for: goal)
                }
            }

            HStack(spacing: 10) {
                Button {
                    finish(with: nil)
                } label: {
                    Text("Überspringen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

                Button {
                    finish(with: selectedGoal)
                } label: {
                    HStack(spacing: 8) {
                        Text("Los geht's")
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            }
        }
    }

    @ViewBuilder
    private func goalButton(for goal: LearningGoal) -> some View {
        let isSelected = selectedGoal == goal
        Button {
            feedbackPlayer.playToggle()
            withAnimation(.easeInOut(duration: 0.12)) {
                selectedGoal = isSelected ? nil : goal
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isSelected ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .opacity(isSelected ? 0.2 : 1))
                    Image(systemName: goal.systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isSelected ? sectionStyle.accent : AppTheme.Colors.textSecondary)
                }
                .frame(width: 34, height: 34)

                Text(goal.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? sectionStyle.accent.opacity(0.5) : AppTheme.Colors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func finish(with goal: LearningGoal?) {
        feedbackPlayer.playStudyAchievement()
        profileStore.completeOnboarding(
            displayName: typedName,
            learningGoal: goal
        )
    }

    // MARK: - Gemeinsamer Header

    @ViewBuilder
    private func welcomeHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(sectionStyle.accent.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
            }
            .frame(width: 64, height: 64)

            Text(title)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
