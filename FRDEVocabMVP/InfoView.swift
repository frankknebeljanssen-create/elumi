import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    private let sectionStyle: AppSectionStyle = .home

    /// Reserviert Platz für die global gerenderte Bottom-Bar. Ohne diese
    /// Clearance steckt die unterste Info-Card (und der Copyright-Block)
    /// hinter dem Footer — der Screen wirkt dann wie „schon am Ende",
    /// obwohl die letzten Cards nur abgeschnitten sind. Ergebnis: der
    /// User konnte scrollen, kam aber nicht unten an, weil nichts mehr
    /// visible reservierte, dass es weiter geht.
    private var footerClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg
            : AppTheme.Spacing.lg
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // Systemweiter Header: Back-Chevron links, Titel mittig.
                // Der frühere separate „Zurück"-Button unter dem Header
                // ist entfallen — der Back-Chevron im Header ersetzt ihn.
                ScreenHeaderCard(
                    style: sectionStyle,
                    title: "Info",
                    subtitle: "",
                    systemImage: nil,
                    onBack: { dismiss() },
                    centeredTitle: true
                )

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
                        // Dauer kommt aus der globalen Settings-Einstellung —
                        // Info-Zeile bleibt damit automatisch korrekt, wenn
                        // der User die Dauer auf 20/30/60 s stellt.
                        "\(SpeedRoundTerminology.name): \(SpeedRoundSettings.currentLabel) Countdown!"
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

                // **Spiele & Fortschritt** — übergeordnete Card, die beide
                // Spiele (Elumi + Word Runner) unter einer einheitlichen
                // Logik erklärt. Begriffs-Konsistenz: „XP" + „Spiele",
                // kein „Credits" / „Tokens" / „Points" mehr (Spec 7.6+).
                gamesProgressInfoCard


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
            // Systemweites Top-Padding — Header sitzt auf derselben
            // vertikalen Position wie im Quiz-Setup.
            .padding(.top, AppLayout.screenHeaderTopPadding)
            // Bottom-Padding = Footer-Clearance (siehe `footerClearance`).
            // Ersetzt das bisherige flache `screenPadding`, das zu klein
            // war, um die unterste Card komplett über der Bottom-Bar zu
            // halten → der User empfand den Screen als „endet dort",
            // was dem Symptom „lässt sich nicht scrollen" entsprach.
            .padding(.bottom, footerClearance)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        // `ignoresSafeArea(.keyboard)` verhindert, dass die ScrollView
        // ihre Höhe ändert, wenn irgendwo in der App die Tastatur
        // animiert hoch-/runterfährt — stabilisiert das Scroll-Verhalten.
        .scrollContentBackground(.hidden)
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
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

    // MARK: - Spiele & Fortschritt (Info)
    //
    // Kindgerechte Info-Card (Zielgruppe 10–14 Jahre). Struktur folgt
    // der UX-Spec „Settings > Info > Spiele & Fortschritt":
    //
    //   1. Header:     🎮  „Spiele & Fortschritt"
    //   2. Einstieg:   2 Zeilen Erklär-Text
    //   3. Abschnitt:  ⭐  XP (was das ist, wofür du es bekommst)
    //   4. Abschnitt:  🎮  Spiele (was das ist, wofür du sie brauchst)
    //   5. Abschnitt:  🧠  So bekommst du Spiele (ohne Zahlen / Formeln)
    //   6. Abschnitt:  Die Spiele (beide Spiele je 1 Zeile: 🧍 Elumi,
    //                  🛤️ Word Runner)
    //
    // **Text-Änderungen** passieren direkt in diesem View — keine
    // Localisation-Schicht, kein Resource-File. Jeder Text-Block ist
    // als Array gepflegt (`lines: […]`), neue Zeilen einfach dazu.
    // Die Sub-Komponenten `gamesProgressSubsection(emoji:title:lines:)`
    // und `gamesProgressGameLine(emoji:title:line:)` regeln das
    // Rendering, damit Typo/Spacing systemweit konsistent bleibt.
    //
    // **Regeln (laut Spec):**
    //   – Keine technischen Begriffe (kein „Credits", „Tokens").
    //   – Keine Zahlen im Text („250 XP = 1 Spiel" ist verboten).
    //   – Kurze Sätze, max. 2 Zeilen pro Game-Beschreibung.

    private var gamesProgressInfoCard: some View {
        let tint = AppTheme.Colors.warning
        return VStack(alignment: .leading, spacing: 16) {
            // Card-Header (analog zu `colorInfoCard`)
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Text("Spiele & Fortschritt")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            // Abschnitt 1 — Einstieg (max. 2 Zeilen, sehr einfach)
            VStack(alignment: .leading, spacing: 4) {
                Text("In den Spielen lernst du und wirst immer besser.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text("Dabei sammelst du XP und bekommst Spiele.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            // Abschnitt 2 — XP (zuerst, weil XP die Basis für Spiele sind)
            gamesProgressSubsection(
                emoji: "⭐",
                title: "XP",
                lines: [
                    "XP bekommst du für richtige Antworten.",
                    "Je mehr XP du hast, desto höher steigst du im Level.",
                    "XP zeigen, wie gut du bist."
                ]
            )

            // Abschnitt 3 — Spiele
            gamesProgressSubsection(
                emoji: "🎮",
                title: "Spiele",
                lines: [
                    "Spiele bekommst du durch Lernen.",
                    "Du kannst sie im Arcade-Spiel einsetzen.",
                    "Ein Spiel ist ein Versuch im Arcade."
                ]
            )

            // Abschnitt 4 — So bekommst du Spiele
            // WICHTIG: keine konkreten Zahlen (250 XP etc.) — nur das
            // Konzept „genug XP gesammelt" + Level/Tagesziele.
            gamesProgressSubsection(
                emoji: "🧠",
                title: "So bekommst du Spiele",
                lines: [
                    "Wenn du genug XP gesammelt hast, bekommst du ein Spiel.",
                    "Du kannst auch Spiele durch Level oder Tagesziele bekommen."
                ]
            )

            // Abschnitt 5 — Die Spiele (beide je 1 Zeile, sehr einfach)
            VStack(alignment: .leading, spacing: 10) {
                Text("Die Spiele")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                gamesProgressGameLine(
                    emoji: "🧍",
                    title: "Elumi",
                    line: "Steuere Elumi, weiche aus und sammle Punkte."
                )
                gamesProgressGameLine(
                    emoji: "🛤️",
                    title: "Word Runner",
                    line: "Laufe durch die Strecke und triff die richtigen Antworten."
                )
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

    /// Sub-Komponente für die Abschnitte XP / Spiele / So bekommst du
    /// Spiele. Emoji + Titel bilden eine kleine Headline, darunter
    /// 1–3 kurze Zeilen in Secondary-Farbe. Spacing (4 pt innen,
    /// 16 pt zwischen den Abschnitten via äußerem VStack) wurde an die
    /// Kinder-Lesbarkeits-Spec angepasst — mehr Luft als die alten
    /// `colorInfoCard`-Blöcke.
    private func gamesProgressSubsection(emoji: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Eine der beiden Spiele-Zeilen (Elumi / Word Runner) — Emoji +
    /// Spielname auf einer Zeile, darunter 1 Satz Erklärung. Bewusst
    /// flacher als `gamesProgressSubsection`, weil die Spec eine
    /// 1-Zeilen-Erklärung vorsieht.
    private func gamesProgressGameLine(emoji: String, title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            Text(line)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
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
