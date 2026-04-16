import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @Environment(\.appOpenAccountAction) private var openAccountAction
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openInfo: () -> Void
    private let sectionStyle: AppSectionStyle = .home

    @State private var dictionaryStats: (total: Int, breakdown: [DictionaryWordClassCount]) = (0, [])
    @State private var dictionaryDetailActive: Bool = false
    @State private var arcadeDetailActive: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Einstellungen",
                subtitle: "",
                systemImage: "gearshape.fill"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Ton")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Spacer(minLength: 0)

                    // Cartoon-Lautsprecher toggelt zwischen „an" und „aus".
                    // foregroundStyle entfällt — das SVG bringt eigene
                    // Farbigkeit mit (Sound-an: bunt, Sound-aus: rote
                    // Verbots-Markierung im SVG selbst).
                    ElumiIconView(
                        icon: feedbackPlayer.areSoundsEnabled ? .lautsprecherOn : .lautsprecherOff,
                        size: 28
                    )
                }

                Toggle(isOn: $feedbackPlayer.areSoundsEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feedbackPlayer.areSoundsEnabled ? "Ton an" : "Ton aus")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("Startsound und Feedback-Töne")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(sectionStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)

            Button {
                openAccountAction?()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mein Konto")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Vorname und Profil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    // Cartoon-Mein-Konto statt SF `person.crop.circle.fill`.
                    ElumiIconView(icon: .meinKonto, size: 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            }
            .buttonStyle(.plain)

            Button {
                openInfo()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Info")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Hilfe und Hinweise zur App")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    // Cartoon-Info statt SF `info.circle.fill`.
                    ElumiIconView(icon: .info, size: 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            }
            .buttonStyle(.plain)

            dictionaryStatsCard

            arcadeInfoCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        // Systemweites Top-Padding — Header sitzt auf derselben
        // vertikalen Position wie im Quiz-Setup.
        .padding(.top, AppLayout.screenHeaderTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if dictionaryStats.total == 0 {
                dictionaryStats = SupplementalFreeDictLexicon.dictionaryStatistics()
            }
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
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
                onSettings: nil,
                isSettingsActive: true
            )
        }
    }

    /// Wörterbuch-Header-Card: nur Titel + Anzahl + Icon. Klick öffnet Detail-Sheet.
    private var dictionaryStatsCard: some View {
        Button {
            dictionaryDetailActive = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wörterbuch")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    if dictionaryStats.total > 0 {
                        Text("\(dictionaryStats.total.formatted(.number.locale(Locale(identifier: "de_DE")))) Einträge")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Lade …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "book.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $dictionaryDetailActive) {
            DictionaryStatsDetailSheet(stats: dictionaryStats, sectionStyle: sectionStyle)
        }
    }

    /// Arcade-Spielregeln-Header — Tap öffnet Detail-Sheet mit Icons + Erklärungen.
    private var arcadeInfoCard: some View {
        Button {
            arcadeDetailActive = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Elumi Spiel")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Spielregeln & Icons")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // Cartoon-Elumi-Spiel statt SF `gamecontroller.fill`.
                ElumiIconView(icon: .elumiSpiel, size: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $arcadeDetailActive) {
            ArcadeRulesDetailSheet(sectionStyle: sectionStyle)
        }
    }
}

/// Sheet mit den Arcade-Spielregeln (echte Icons aus dem Spiel).
private struct ArcadeRulesDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sectionStyle: AppSectionStyle

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Elumi Spiel",
                trailingTitle: "Fertig",
                leadingTint: sectionStyle.accent,
                trailingTint: sectionStyle.accent,
                onLeading: { dismiss() },
                onTrailing: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Zeile: Elumi zum Futter ziehen + 3 Snacks
                    HStack(spacing: 8) {
                        Text("Im Startscreen Elumi zum Futter ziehen")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        ElumiSnackIcon(.wuermchen, size: 20)
                        ElumiSnackIcon(.wasserfloh, size: 22)
                        ElumiSnackIcon(.algenkugel, size: 20)
                    }

                    // Zeile: 4 Leben + 4 Mini-Elumi
                    HStack(spacing: 6) {
                        Text("4 Leben")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        ForEach(0..<4, id: \.self) { _ in
                            ArcadeElumiAvatar(size: 22, withShadow: false)
                        }
                    }

                    Text("Verpasstes Futter = −1 Leben")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    // Mini-Elumi-Freund + Text
                    HStack(spacing: 10) {
                        ArcadeHazardElumiAvatar(size: 26)
                        Text("Elumi-Freund fressen = −1 Leben")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }

                    Text("Bonus-Runde Fische fangen = +1 Extra Leben")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    // Saugglocke (echtes Icon)
                    HStack(spacing: 10) {
                        ArcadeSuctionIconStandalone(size: 28)
                        Text("Saugglocke: zieht Snacks heran")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }

                    // Zeitlupe-Trank (echtes Icon)
                    HStack(spacing: 10) {
                        ArcadeSlowMotionIconStandalone(size: 28)
                        Text("Zeitlupe-Trank: alles in Slow-Motion (5 Sek.)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
    }
}

/// Sheet mit der vollständigen Wörterbuch-Statistik (Aufschlüsselung nach Wortart).
private struct DictionaryStatsDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stats: (total: Int, breakdown: [DictionaryWordClassCount])
    let sectionStyle: AppSectionStyle

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Wörterbuch",
                trailingTitle: "Fertig",
                leadingTint: sectionStyle.accent,
                trailingTint: sectionStyle.accent,
                onLeading: { dismiss() },
                onTrailing: { dismiss() }
            )

            // Total
            HStack {
                Text("Gesamt")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text("\(stats.total.formatted(.number.locale(Locale(identifier: "de_DE"))))")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.bold, cornerRadius: AppLayout.largeCardCornerRadius)

            // Breakdown nach Wortart
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(stats.breakdown) { entry in
                        HStack {
                            Text(entry.label)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            Text(entry.count.formatted(.number.locale(Locale(identifier: "de_DE"))))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(sectionStyle.accent)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle, cornerRadius: 14)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
    }
}

