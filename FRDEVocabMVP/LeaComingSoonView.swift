// LeaComingSoonView.swift
// **2026-06-09** — Platzhalter-Screen für den Léa-Chat, solange
// `FeatureFlags.leaChatEnabled == false` ist.
//
// Hintergrund: Der Chat ist wegen eines Backend-Bugs nicht nutzbar. Die
// Home-Card blieb aber tappbar und führte in einen kaputten Screen. Statt
// den Tap tot zu stellen (fühlt sich wie ein Bug an) landet der User hier
// und bekommt eine Erklärung.
//
// `ChatView` und `ChatService` sind bewusst NICHT angefasst — die Weiche
// sitzt allein in `AppDestinationHost` bei `case .leaChat`. Sobald das
// Flag auf `true` geht, ist der echte Chat wieder erreichbar und dieser
// Screen wird nicht mehr instanziiert.

import SwiftUI

struct LeaComingSoonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void

    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppTheme.Spacing.lg) {
                ScreenHeaderCard(
                    style: sectionStyle,
                    title: "Live-Chat",
                    subtitle: "",
                    systemImage: nil,
                    onBack: { dismiss() },
                    centeredTitle: true
                )

                mascot
                message

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.headerChevronTopPadding)
            .padding(.bottom, AppTheme.Spacing.lg)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
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
    }

    // MARK: - Maskottchen

    private var mascot: some View {
        ZStack {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 108, height: 108)
            SplashCharacterBlinkOverlay(size: 108, startDate: .now)
                .frame(width: 108, height: 108)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        .padding(.top, AppTheme.Spacing.xl)
    }

    // MARK: - Nachricht

    private var message: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Léa lernt gerade noch dazu.")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Der Chat kommt in einer der nächsten Versionen.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Bis dahin: üb weiter, dann kannst du Léa nachher richtig was erzählen. 🇫🇷")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppTheme.Spacing.xs)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(AppTheme.Colors.success.opacity(0.12))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Colors.success.opacity(0.35), lineWidth: 1)
        )
    }
}
