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
    let onArticles: () -> Void
    let onVerbs: () -> Void
    let onFlashcards: () -> Void
    let onQuiz: () -> Void
    let onLater: () -> Void
    private let sectionStyle: AppSectionStyle = .scan
    @State private var isNavigationLocked = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Import fertig")
                        .font(AppTheme.Typography.largeTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(context.summaryText)
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Liste: \(context.targetListName)")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                Text("Wie möchtest du weiterlernen?")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            // 5 module buttons like home screen
            VStack(spacing: 8) {
                completionModuleButton(
                    title: "Vokabeln",
                    systemImage: "character.book.closed.fill",
                    tint: AppTheme.Colors.modulePractice,
                    action: onTrain
                )

                HStack(spacing: 8) {
                    completionModuleButton(
                        title: "Artikel",
                        systemImage: "textformat.abc.dottedunderline",
                        tint: Color(hex: "#F59E0B"),
                        action: onArticles
                    )
                    completionModuleButton(
                        title: "Verben",
                        systemImage: "arrow.triangle.branch",
                        tint: Color(hex: "#8B5CF6"),
                        action: onVerbs
                    )
                }

                HStack(spacing: 8) {
                    completionModuleButton(
                        title: "Karteikarten",
                        systemImage: "square.stack.3d.up.fill",
                        tint: Color(hex: "#3B82F6"),
                        action: onFlashcards
                    )
                    completionModuleButton(
                        title: "Quiz",
                        systemImage: "lightbulb.fill",
                        tint: Color(hex: "#10B981"),
                        action: onQuiz
                    )
                }
            }

            Button("Später") {
                guard !isNavigationLocked else { return }
                isNavigationLocked = true
                onLater()
            }
            .buttonStyle(.plain)
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: 0)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isNavigationLocked)
    }
}
