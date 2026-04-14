import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeaderCard(
                    style: sectionStyle,
                    title: "Info",
                    subtitle: "",
                    systemImage: "info.circle.fill"
                )

                Button {
                    dismiss()
                } label: {
                    Label("Zur\u{00FC}ck", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

                colorInfoCard(
                    title: "Karteikarten",
                    icon: "square.stack.3d.up.fill",
                    tint: AppTheme.Colors.moduleFlashcards,
                    lines: [
                        "Arbeite einen Stapel Karte für Karte ab.",
                        "Falsche Karten bleiben im Stapel.",
                        "Tippe auf die Karte um die Lösung zu sehen."
                    ]
                )

                colorInfoCard(
                    title: "Nomen",
                    icon: "textformat",
                    tint: AppTheme.Colors.moduleNomen,
                    lines: [
                        "Französische Nomen und ihre Übersetzung üben.",
                        "la ville → die Stadt, le chat → die Katze.",
                        "Fokus auf Wortschatz und Bedeutung."
                    ]
                )

                colorInfoCard(
                    title: "Artikel",
                    icon: "textformat.abc.dottedunderline",
                    tint: AppTheme.Colors.moduleArticles,
                    lines: [
                        "le, la, l', les — den richtigen Artikel üben.",
                        "Nur Nomen werden abgefragt.",
                        "Perfekt für Genus-Training!"
                    ]
                )

                colorInfoCard(
                    title: "Verben",
                    icon: "arrow.triangle.branch",
                    tint: AppTheme.Colors.moduleVerbs,
                    lines: [
                        "Französische Verben und ihre Übersetzungen.",
                        "Fokus auf die wichtigsten Verben.",
                        "Sprechen oder Tippen — du entscheidest."
                    ]
                )

                colorInfoCard(
                    title: "Verbformen",
                    icon: "text.line.first.and.arrowtriangle.forward",
                    tint: AppTheme.Colors.moduleVerbforms,
                    lines: [
                        "Konjugation französischer Verben üben.",
                        "je vais, tu vas, il va — alle Formen trainieren.",
                        "Kommt bald — Konjugationsdaten werden aufgebaut."
                    ]
                )

                colorInfoCard(
                    title: "Vokabeln",
                    icon: "character.book.closed.fill",
                    tint: AppTheme.Colors.moduleVocabulary,
                    lines: [
                        "Alle Vokabeln aus deinen Listen üben.",
                        "Sprechen oder Tippen — du entscheidest.",
                        "Speed Round: 45 Sekunden Countdown!"
                    ]
                )

                colorInfoCard(
                    title: "Quiz",
                    icon: "lightbulb.fill",
                    tint: AppTheme.Colors.moduleQuiz,
                    lines: [
                        "Multiple Choice, Paare finden, Tippen, Lückentext.",
                        "Wähle 5 bis 30 Fragen pro Runde.",
                        "Ergebnis am Ende mit Auswertung."
                    ]
                )

                colorInfoCard(
                    title: "Scan",
                    icon: "camera.viewfinder",
                    tint: AppTheme.Colors.moduleScan,
                    lines: [
                        "Fotografiere eine Vokabel-Seite.",
                        "KI erkennt Vokabelpaare automatisch.",
                        "Prüfen, importieren, direkt loslegen."
                    ]
                )

                colorInfoCard(
                    title: "Listen & Wörterbuch",
                    icon: "list.bullet.rectangle.fill",
                    tint: AppTheme.Colors.moduleLists,
                    lines: [
                        "Eigene Listen anlegen und verwalten.",
                        "Wörterbuch zeigt alle gelernten Vokabeln.",
                        "Einträge bearbeiten und löschen."
                    ]
                )

                colorInfoCard(
                    title: "XP & Fortschritt",
                    icon: "star.fill",
                    tint: AppTheme.Colors.warning,
                    lines: [
                        "Quiz: 5 XP, Training & Karteikarten: 2 XP.",
                        "Alle 20 XP = 1 Arcade Credit.",
                        "Lerne regelmäßig für mehr Credits!"
                    ]
                )

                colorInfoCard(
                    title: "Elumi Spiel",
                    icon: "gamecontroller.fill",
                    tint: AppTheme.Colors.primary,
                    lines: [
                        "1 Credit = 1 Spiel. Zieh Elumi zum Futter.",
                        "4 Leben — 12 Snacks pro Runde fangen!",
                        "Elumi-Freunde nicht fressen (−1 Leben).",
                        "Saugglocke: Saugstrahl zieht Snacks an.",
                        "Zeitlupe-Trank: Verlangsamt alles für 5 Sek.",
                        "Bonusblase: Doppelte Punkte für 5 Sek.",
                        "Querschläger: Snacks prallen an den Rändern ab.",
                        "Giftqualle: Weiche den Tentakeln aus! 3 Treffer = −1 Leben.",
                        "Alle 3 Runden: Fische fangen = Extra-Leben!",
                        "Runden werden immer schneller!"
                    ]
                )

                // Credits
                VStack(spacing: 4) {
                    Text("\u{00A9} Frank Knebel-Janssen 2026")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
                    Text("Version \(v) (\(b))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppLayout.screenPadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() })
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

    private func colorInfoCard(title: String, icon: String, tint: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }
}
