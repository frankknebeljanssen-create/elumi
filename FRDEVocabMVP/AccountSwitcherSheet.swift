import SwiftUI

/// **Account-Switcher** — Sheet mit allen lokalen Accounts auf dem
/// Gerät. Wird aus Settings → „Meine Accounts" geöffnet.
///
/// Features:
///   • Liste aller Accounts, der aktive bekommt ein Check-Badge.
///   • Tap auf eine Zeile → `AccountStore.switchAccount(to:)`.
///   • „Neuer Account"-CTA → öffnet `AccountOnboardingView` als
///     verschachteltes Sheet. Nach Anlegen ist der neue Account
///     automatisch aktiv, Sheet schließt sich.
///   • Swipe-to-delete / Lösch-Button — alert-geschützt, damit User
///     nicht ausversehen den aktiven Account kickt.
///
/// **V1-Limit**: die Umbenennung passiert über das bestehende „Mein
/// Konto"-Flow (ProfileStore) für den aktiven Account; pro-Account-
/// Rename in diesem Sheet kommt in einem Folge-Slice. Der Switcher
/// ist bewusst lesbar + schnell-bedienbar, nicht eine Vollverwaltung.
struct AccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    private let sectionStyle: AppSectionStyle = .home

    @State private var showingNewAccountSheet = false
    @State private var pendingDeletion: AccountProfile?

    private var alertTitle: String {
        guard let pending = pendingDeletion else { return "" }
        return "„\(pending.displayName)" + "\" löschen?"
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // **Naming-Sweep 2026-05-06** — Sheet-Title „Meine
            // Accounts" → „Account wechseln" (matched die Card-
            // Beschriftung in SettingsView, klare Aktion).
            AppSheetHeader(
                title: "Account wechseln",
                leadingTitle: "Fertig",
                leadingTint: sectionStyle.accent,
                onLeading: { dismiss() }
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(accountStore.accounts) { account in
                        accountRow(account)
                    }

                    addAccountButton
                }
                .padding(.horizontal, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .sheet(isPresented: $showingNewAccountSheet) {
            AccountOnboardingView(
                accountStore: accountStore,
                onComplete: { _ in
                    // Der neue Account ist bereits aktiv — Switcher
                    // schließt sich automatisch, damit der User sofort
                    // auf Home landet. Ohne dieses Dismiss bliebe er
                    // im Switcher-Sheet stehen.
                    dismiss()
                },
                allowsCancel: true
            )
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Abbrechen", role: .cancel) {
                pendingDeletion = nil
            }
            Button("Löschen", role: .destructive) {
                if let pending = pendingDeletion {
                    accountStore.deleteAccount(id: pending.id)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Dieser Account wird vom Gerät entfernt. Fortschritt und Listen gehen verloren.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func accountRow(_ account: AccountProfile) -> some View {
        let isActive = account.id == accountStore.currentAccountID

        HStack(spacing: 12) {
            // Emoji-Avatar (groß, farbiger Kreis als Hintergrund).
            ZStack {
                Circle()
                    .fill(sectionStyle.accent.opacity(isActive ? 0.28 : 0.14))
                    .frame(width: 44, height: 44)
                Text(account.avatarEmoji)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(isActive ? "Aktiv" : "Tippen zum Wechseln")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        isActive ? sectionStyle.accent : AppTheme.Colors.textSecondary
                    )
            }

            Spacer(minLength: 0)

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
            } else if accountStore.accounts.count > 1 {
                // Delete-Button — nur sichtbar für nicht-aktive
                // Accounts UND wenn mindestens noch zwei Accounts
                // übrig sind. So vermeiden wir den Dead-End „User
                // löscht den letzten Account und landet wieder im
                // Onboarding", obwohl das technisch zwar handhabbar
                // wäre (runMigration/Onboarding greift), aber
                // überraschend wirkt.
                Button {
                    pendingDeletion = account
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? sectionStyle.accent.opacity(0.10) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isActive ? sectionStyle.accent.opacity(0.55) : AppTheme.Colors.border.opacity(0.5),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isActive else { return }
            accountStore.switchAccount(to: account.id)
        }
    }

    // MARK: - Add

    private var addAccountButton: some View {
        Button {
            showingNewAccountSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(sectionStyle.accent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
                Text("Neuer Account")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(sectionStyle.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
