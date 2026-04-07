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
    let onFlashcards: () -> Void
    let onLists: () -> Void
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

                Text("Du kannst jetzt direkt üben oder später weitermachen.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onTrain()
                } label: {
                    completionActionCard(
                        title: "Jetzt trainieren",
                        systemImage: "mic.fill",
                        isPrimary: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNavigationLocked)

                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onFlashcards()
                } label: {
                    completionActionCard(
                        title: "Karteikarten üben",
                        systemImage: "rectangle.stack.fill",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNavigationLocked)

                Button {
                    guard !isNavigationLocked else { return }
                    isNavigationLocked = true
                    onLists()
                } label: {
                    completionActionCard(
                        title: "Zur Liste",
                        systemImage: "list.bullet.rectangle.fill",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNavigationLocked)
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

    private func completionActionCard(title: String, systemImage: String, isPrimary: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 42, height: 42)
                .background((isPrimary ? Color.white.opacity(0.22) : AppTheme.Colors.cta.opacity(0.14)))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(isPrimary ? .white : AppTheme.Colors.cta)

            Text(title)
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(isPrimary ? .white : AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isPrimary ? Color.white.opacity(0.82) : AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(isPrimary ? AppTheme.Colors.cta : AppTheme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isPrimary ? AppTheme.Colors.cta.opacity(0.18) : AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
    }
}
