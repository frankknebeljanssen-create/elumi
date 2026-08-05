import SwiftUI

// ElumiHelpSheet.swift
// **Elumi-Hilfe (2026-08-05)** — die Oberfläche. Datenmodell, Textkatalog
// und die Begründung des Konzepts stehen in `ElumiHelp.swift`.
//
// **Zwei Zustände, bewusst nicht mehr:**
//   • Fragen-Liste ("Was willst du wissen?")
//   • genau EINE Antwort
// Kein Blättern, keine Unterkapitel, kein Suchfeld. NN/g zu
// Instruktions-Overlays: ein Hinweis pro Moment, niemals Ketten, sonst
// erzwingt man Auswendiglernen statt Anwenden und die App wirkt
// komplizierter als sie ist.
//
// **Optik** bewusst identisch zur bestehenden `DismissibleHintBubble`
// (Maskottchen + Blinzeln, `secondarySurface` mit `elumiBlue`-Tint,
// `elumiBlue`-Stroke): Erstnutzer-Tipp und angeforderte Hilfe sind
// dieselbe Stimme und sollen auch gleich aussehen.
struct ElumiHelpSheet: View {
    let topic: ElumiHelpTopic
    /// Führt die Aktion einer Antwort aus (z. B. "Jetzt scannen").
    /// Der Aufrufer schließt dabei zuerst die Sheet.
    let onNavigate: (AppScreen) -> Void
    /// "Alles über die App" — der vollständige Katalog (`InfoView`).
    let onOpenInfo: () -> Void
    let onClose: () -> Void

    /// `nil` = Fragen-Liste, sonst die aufgeschlagene Antwort.
    @State private var selected: ElumiHelpEntry?

    /// **2026-08-05** — 72 → 58 pt. Zusammen mit dem kleineren
    /// Kopf-Padding rutscht "Was willst du wissen?" spürbar nach oben
    /// (User-Spec: "das muss 'n bisschen höher rauf") und mehr Fragen
    /// passen ohne Scrollen in die halbhohe Sheet.
    private static let mascotSize: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.md) {
                    if let selected {
                        answerView(selected)
                    } else {
                        questionList
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Die Antwort schließen, wenn die Sheet zwischendurch das Thema
        // wechselt (Hilfe von einem anderen Screen aus geöffnet).
        .onChange(of: topic) { _, _ in selected = nil }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                Image("SplashCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.mascotSize, height: Self.mascotSize)
                SplashCharacterBlinkOverlay(size: Self.mascotSize, startDate: .now)
                    .frame(width: Self.mascotSize, height: Self.mascotSize)
            }
            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)

            // **Neugier statt Defizit** (siehe Doku in `ElumiHelp.swift`):
            // niemals "Brauchst du Hilfe?".
            Text(selected == nil ? "Was willst du wissen?" : "Elumi sagt")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        // Klein gehalten: der Drag-Indikator der Sheet sitzt direkt
        // darüber und bringt selbst schon Luft mit.
        .padding(.top, AppTheme.Spacing.xs)
    }

    // MARK: - Fragen-Liste

    private var questionList: some View {
        VStack(spacing: 8) {
            ForEach(topic.entries) { entry in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selected = entry
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(entry.question)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.elumiBlue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(AppTheme.Colors.secondarySurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                    .fill(AppTheme.Colors.elumiBlue.opacity(0.12))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(AppTheme.Colors.elumiBlue.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(AppCardPressStyle())
            }
        }
    }

    // MARK: - Antwort

    private func answerView(_ entry: ElumiHelpEntry) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(entry.question)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiBlue)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Satzweise gesetzt, wie in `DismissibleHintBubble`: der
            // Abstand ZWISCHEN den Sätzen ist größer als der Zeilen-
            // abstand innerhalb eines Satzes, dadurch bleibt die
            // Satzstruktur auch bei Umbruch lesbar.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sentences(of: entry.answer).enumerated()), id: \.offset) { _, sentence in
                    Text(sentence)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Aktion, die die Sache direkt tut, statt sie nur zu
            // beschreiben. Nicht jede Antwort hat eine.
            if let actionTitle = entry.actionTitle, let screen = entry.actionScreen {
                Button {
                    onNavigate(screen)
                } label: {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.elumiBlue))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selected = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Noch was?")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(AppTheme.Colors.elumiBlue.opacity(0.16))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Colors.elumiBlue.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Fuß

    /// **Das dauerhafte Zuhause** (NN/g: Weggeklicktes muss wiederfindbar
    /// bleiben). Die kontextbezogene Hilfe beantwortet die vier Fragen
    /// dieses Screens; wer mehr will, kommt von hier in den vollen
    /// Katalog.
    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(AppTheme.Colors.border)

            HStack(spacing: 14) {
                Button {
                    onOpenInfo()
                } label: {
                    Text("Alles über die App")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.elumiBlue)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    onClose()
                } label: {
                    Text("Schließen")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Helfer

    private func sentences(of text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Einstiegs-Abzeichen

/// **2026-08-05** — Der Hilfe-Einstieg, überall identisch: Elumi mit
/// einem kleinen Fragezeichen unten rechts.
///
/// **Warum als eigene View:** Der Knopf sitzt inzwischen an drei ganz
/// verschiedenen Stellen (Home-Header, farbige Modul-Header-Card,
/// schlichte Screen-Header-Zeile). Ein Nutzer soll ihn überall sofort
/// als dasselbe wiedererkennen; drei Nachbauten würden über die Zeit
/// auseinanderlaufen.
///
/// **Warum das Maskottchen und nicht nur ein Fragezeichen:** Die Hilfe
/// spricht mit Elumis Stimme. Ein neutrales "i" würde nach Handbuch
/// aussehen, und genau davor drücken sich Jugendliche (siehe die
/// Begründung zum Defizit-Framing in `ElumiHelp.swift`).
struct ElumiHelpBadge: View {
    let action: () -> Void
    /// Kantenlänge des Maskottchens. Der Tap-Bereich ist unabhängig davon
    /// immer mindestens 44 pt groß (Apple-Mindestmaß).
    var size: CGFloat = 34

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Image("SplashCharacter")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                    SplashCharacterBlinkOverlay(size: size, startDate: .now)
                        .frame(width: size, height: size)
                }

                Image(systemName: "questionmark")
                    .font(.system(size: size * 0.29, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.44, height: size * 0.44)
                    .background(Circle().fill(AppTheme.Colors.elumiBlue))
                    .overlay(Circle().stroke(AppTheme.Colors.background, lineWidth: 1.5))
                    .offset(x: 2, y: 1)
            }
            .frame(width: size, height: size)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppCardPressStyle())
        .accessibilityLabel("Elumi fragen")
    }
}
