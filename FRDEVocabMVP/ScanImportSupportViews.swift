import SwiftUI

private struct HomeCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ImportCompletionView: View {
    let context: ImportCompletionContext
    let onTrain: () -> Void
    let onNomen: () -> Void
    let onArticles: () -> Void
    let onVerbs: () -> Void
    let onVerbforms: () -> Void
    let onFlashcards: () -> Void
    let onQuiz: () -> Void
    let onViewList: () -> Void
    let onLater: () -> Void
    private let sectionStyle: AppSectionStyle = .scan
    @State private var isNavigationLocked = false

    var body: some View {
        VStack(spacing: 16) {
            // Import fertig! — outside card
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.success)
                Text("Import fertig!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            // Summary card
            VStack(alignment: .leading, spacing: 6) {
                Text(context.summaryText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Liste: \(context.targetListName)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    )
            )

            // Question — outside card
            Text("Was möchtest du sofort üben?")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            // Module buttons — same layout as Home
            VStack(spacing: 8) {
                // Nomen + Artikel
                HStack(spacing: 8) {
                    completionModuleButton(
                        title: "Nomen",
                        systemImage: "textformat",
                        tint: AppTheme.Colors.moduleNomen,
                        action: onNomen
                    )
                    completionModuleButton(
                        title: "Artikel",
                        systemImage: "textformat.abc.dottedunderline",
                        tint: AppTheme.Colors.moduleArticles,
                        action: onArticles
                    )
                }

                // Verben + Verbformen
                HStack(spacing: 8) {
                    completionModuleButton(
                        title: "Verben",
                        systemImage: "arrow.triangle.branch",
                        tint: AppTheme.Colors.moduleVerbs,
                        action: onVerbs
                    )
                    completionModuleButton(
                        title: "Verbformen",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        tint: AppTheme.Colors.moduleVerbforms,
                        action: onVerbforms
                    )
                }

                // Vokabeln + Quiz
                HStack(spacing: 8) {
                    completionModuleButton(
                        title: "Vokabeln",
                        systemImage: "character.book.closed.fill",
                        tint: AppTheme.Colors.moduleVocabulary,
                        action: onTrain
                    )
                    completionModuleButton(
                        title: "Quiz",
                        systemImage: "lightbulb.fill",
                        tint: AppTheme.Colors.moduleQuiz,
                        action: onQuiz
                    )
                }

                // Karteikarten full width
                completionModuleButton(
                    title: "Karteikarten",
                    systemImage: "square.stack.3d.up.fill",
                    tint: AppTheme.Colors.moduleFlashcards,
                    action: onFlashcards
                )
            }

            HStack(spacing: 10) {
                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onViewList()
                } label: {
                    Label("Liste ansehen", systemImage: "list.bullet")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textSecondary))

                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onLater()
                } label: {
                    Text("Ich übe später")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textSecondary))
            }
        }
        .safeAreaPadding(.top, AppTheme.Spacing.xs)
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isNavigationLocked = false
        }
    }

    private func completionModuleButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            guard !isNavigationLocked else { return }
            isNavigationLocked = true
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(height: 32)
                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isNavigationLocked)
    }
}
