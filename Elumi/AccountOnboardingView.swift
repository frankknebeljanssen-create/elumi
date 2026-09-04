import SwiftUI

/// **Account-Onboarding** — einmaliger Willkommens-Flow beim Anlegen
/// eines neuen Accounts.
///
/// Nutzung:
///   • **Erstinstall** (keine Accounts): Root-UI präsentiert diese
///     View modal, User legt den ersten Account an.
///   • **Account hinzufügen** (aus Settings → „Meine Accounts" →
///     „Neuer Account"): View wird als Sheet eingeblendet. User
///     legt Account an, Sheet schließt, der neue Account ist aktiv.
///
/// Keine Demo-Einführung (User-Spec) — der Flow führt direkt zum Ziel:
/// Name + Emoji, dann „Los geht's!". Beim Abschluss feuert
/// `onComplete(_:)` mit dem erstellten `AccountProfile`.
///
/// Bewusst **nicht** enthalten:
///   • Lernziel, App-Präferenzen, Demo-Slides — kommt bei Bedarf
///     später als optionaler Zweitschritt.
///   • Cloud-Sync / Passwort — alle Accounts sind lokal.
struct AccountOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    /// Rufer-Callback nach Account-Anlegen. Default-Implementation
    /// dismisst die View. Der Root-Use-Case überschreibt das nicht
    /// (AccountStore aktiviert den Account automatisch).
    var onComplete: (AccountProfile) -> Void = { _ in }

    /// `true` zeigt einen „Später" / „Abbrechen"-Button oben rechts —
    /// Default `false` für den Erstinstall (keine Skip-Option, sonst
    /// gerät die App in einen Zustand ohne Account). Beim Sheet aus
    /// Settings auf `true` setzen, damit der User den Flow verlassen
    /// kann, ohne einen neuen Account anlegen zu müssen.
    var allowsCancel: Bool = false

    @State private var nameInput: String = ""
    @State private var selectedEmoji: String = "🐟"
    @FocusState private var nameFieldFocused: Bool

    private let sectionStyle: AppSectionStyle = .home

    /// Emoji-Pool — bewusst begrenzt (10 Stück), damit die Auswahl
    /// scroll-frei in einem 5×2-Grid passt. Erste Reihe: Wasser-/Elumi-
    /// Themen (knüpft an Elumi-Maskottchen an). Zweite Reihe: Kind-
    /// freundliche Tiere/Symbole für Kinder ohne Wassertier-Bezug.
    private static let emojiPool: [String] = [
        "🐟", "🐠", "🐡", "🦈", "🐙",
        "🦊", "🦁", "🐼", "🚀", "⭐"
    ]

    private var trimmedName: String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    header
                    nameSection
                    emojiSection
                    startButton
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppTheme.Spacing.xl)
                .padding(.bottom, AppTheme.Spacing.xxl)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(alignment: .topTrailing) {
            if allowsCancel {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppTheme.Colors.secondarySurface))
                }
                .buttonStyle(.plain)
                .padding(.trailing, AppLayout.screenPadding)
                .padding(.top, AppTheme.Spacing.md)
            }
        }
        .onAppear {
            // Leichten Fokus-Delay — ohne Delay feuert der First-
            // Responder zu früh, die Keyboard-Animation kämpft mit
            // dem Modal-Präsentations-Animator.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                nameFieldFocused = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(allowsCancel ? "Neuer Account" : "Willkommen bei Elumi")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Leg einen Account an, damit dein Fortschritt dir gehört.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dein Name")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.Colors.cardLabel)

            TextField("z. B. Frank", text: $nameInput)
                .focused($nameFieldFocused)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { if canSubmit { submit() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(sectionStyle.accent.opacity(nameFieldFocused ? 0.6 : 0.25), lineWidth: 1.2)
                )
        }
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dein Avatar")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.Colors.cardLabel)

            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 5
            )
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.emojiPool, id: \.self) { emoji in
                    emojiTile(emoji)
                }
            }
        }
    }

    @ViewBuilder
    private func emojiTile(_ emoji: String) -> some View {
        let isSelected = emoji == selectedEmoji
        Button {
            selectedEmoji = emoji
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? sectionStyle.accent.opacity(0.25) : AppTheme.Colors.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? sectionStyle.accent : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private var startButton: some View {
        Button {
            submit()
        } label: {
            Text(allowsCancel ? "Account erstellen" : "Los geht's!")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : 0.5)
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        let account = accountStore.createAccount(
            name: trimmedName,
            emoji: selectedEmoji
        )
        onComplete(account)
        if allowsCancel {
            dismiss()
        }
    }
}

// Hinweis: Der memberwise-Init der `AccountOnboardingView` reicht für
// beide Nutzungs-Pfade (Root-Onboarding und Sheet aus Settings). Pro
// Call-Site:
//   • `AccountOnboardingView(accountStore: store)`
//     — Erstinstall, kein Cancel, kein onComplete-Side-Effect.
//   • `AccountOnboardingView(accountStore: store, onComplete: { … }, allowsCancel: true)`
//     — Sheet aus Settings → Account-Switcher: User kann abbrechen,
//     `onComplete` feuert bei Erfolg.
