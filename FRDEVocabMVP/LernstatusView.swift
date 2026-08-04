import SwiftUI

/// Detail-Screen zum modulübergreifenden Lernstatus pro Vokabel.
///
/// Erreichbar über Tap auf die `HomeLernstatusCard`. Strukturierung in
/// **drei** Sektionen (didaktische Gruppierung von `ItemLearningStatusClass`):
///
///   • **Stark** — sitzt schon; reine Anerkennungs-Sektion.
///   • **Zum Üben** — Priorität hoch; die Sektion, die der User nach dem
///     Öffnen des Screens wahrscheinlich zuerst anschauen will. Orange
///     getönt, damit sie auch beim Überfliegen als „hier anpacken" liest.
///   • **Im Aufbau** — `.learning` **und** `.sparse` zusammengefasst; hier
///     braucht der Status noch mehr Signal, bevor die App eine Aussage
///     trifft. Bewusst positiv beschriftet („Im Aufbau" statt „zu wenig
///     Daten"), damit die Sektion nicht wie eine Mahnung wirkt.
///
/// Empty-State: Wenn der Store noch **gar** keine Einträge hat (=
/// frisch nach Install / Dev-Reset), wird statt der drei Sektionen ein
/// einziger, freundlicher Empty-State gezeigt.
///
/// Navigation: Standard-`AppTopBar` mit Back-Button + Bottom-Bar mit
/// `goHome` — das Muster von `HeartsView` (Progress Hub).
struct LernstatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @ObservedObject var statusStore: ItemLearningStatusStore = .shared
    /// **2026-08-04** — für die generierte Übungsliste „Meine
    /// Wackelkandidaten": der Screen baut die Liste im `listStore` und
    /// springt per `navigate` in die Karteikarten mit genau diesem
    /// Bestand.
    @ObservedObject var listStore: VocabularyListStore
    let goHome: () -> Void
    let openSettings: () -> Void
    let navigate: (AppScreen) -> Void

    /// Home-Akzent — der Screen ist die „Detail-Ebene" der Home-Card, kein
    /// eigenständiges Modul. Dadurch bleibt die visuelle Sprache konsistent
    /// (kein zusätzlicher Section-Accent-Typ im `AppSectionStyle`-Enum).
    let sectionStyle: AppSectionStyle = .home

    /// **2026-08-04** — Non-nil, sobald „Meine Wackelkandidaten" gebaut
    /// wurde. Treibt das Bestätigungs-Popup (User-Spec: nicht direkt in
    /// Karteikarten springen, sondern erst bestätigen + Übungsart wählen
    /// lassen).
    @State private var practiceConfirmation: WackelkandidatenConfirmation?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                header

                if statusStore.totalTracked == 0 {
                    emptyState
                } else {
                    practiceListCTA
                    sectionsContent
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
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
        .sheet(item: $practiceConfirmation) { confirmation in
            WackelkandidatenConfirmationSheet(
                count: confirmation.count,
                onStartFlashcards: {
                    practiceConfirmation = nil
                    navigate(.flashcards(FlashcardLaunchContext(preferredListID: confirmation.listID)))
                },
                onStartQuiz: {
                    practiceConfirmation = nil
                    navigate(.quiz(QuizLaunchContext(preferredListID: confirmation.listID)))
                },
                onStartTraining: {
                    practiceConfirmation = nil
                    navigate(.train(TrainingLaunchContext(preferredListID: confirmation.listID, preferredMode: .vocabulary)))
                },
                onDismiss: {
                    practiceConfirmation = nil
                }
            )
        }
    }

    // MARK: - Header

    /// Systemkonformer Header analog zu ListsView / SettingsView /
    /// AccentsEntryView: Back-Chevron links, Titel mittig, kein Icon
    /// rechts. Der subtile Untertext (Tracking-Zusammenfassung) bleibt
    /// darunter sichtbar — er ist Kontext, keine Nav-Struktur.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Lernstatus",
                subtitle: "",
                systemImage: nil,
                onBack: { dismiss() },
                centeredTitle: true
            )

            Text(headerSubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSubtitle: String {
        let total = statusStore.totalTracked
        if total == 0 {
            return "Noch nichts getrackt — spiel ein paar Runden, dann siehst du hier deinen Fortschritt."
        }
        return "Was du schon kannst — und was noch etwas Übung braucht."
    }

    // MARK: - Übungsliste-CTA („Meine Wackelkandidaten")

    /// **2026-08-04** — Verwandelt den Lernstatus von einer reinen
    /// Anzeige in etwas Handelbares: baut aus allem, was noch nicht
    /// „Stark" ist, eine echte Übungsliste und öffnet ein Bestätigungs-
    /// Popup, in dem der User wählt, womit er üben will (Karteikarten /
    /// Quiz / Training). Die Liste bleibt in „Meine Listen" liegen.
    ///
    /// Nur sichtbar, wenn es überhaupt Wackelkandidaten gibt — bei einem
    /// reinen „alles stark"-Stand wäre der Button sinnlos.
    @ViewBuilder
    private var practiceListCTA: some View {
        let count = statusStore.wackelkandidatenCount
        if count > 0 {
            Button {
                buildAndPracticeWackelkandidaten()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(HomeLernstatusCard.needsWorkTint.opacity(0.18))
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(HomeLernstatusCard.needsWorkTint)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diese Wörter üben")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(count == 1
                             ? "Baut aus deinem 1 Wackelkandidaten eine Übungsliste."
                             : "Baut aus deinen \(count) Wackelkandidaten eine Übungsliste.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appSetupCardBackground()
            }
            .buttonStyle(AppCardPressStyle())
        }
    }

    /// Baut/aktualisiert die Liste „Meine Wackelkandidaten" aus dem
    /// aktuellen Lernstatus.
    ///
    /// **2026-08-04** — springt NICHT mehr direkt in die Karteikarten
    /// (User-Spec: „das ist ein bisschen zu schnell"). Stattdessen öffnet
    /// sich das Bestätigungs-Popup (`practiceConfirmation`), das erst
    /// zeigt, dass die Liste entstanden ist, und dann fragt, welche
    /// Übung der User starten möchte.
    private func buildAndPracticeWackelkandidaten() {
        let weakItems = statusStore.wackelkandidatenItems
        guard let listID = listStore.rebuildWackelkandidatenList(from: weakItems) else { return }
        // Tatsächliche Item-Zahl aus der gebauten Liste lesen — kann kleiner
        // sein als `weakItems.count`, weil `rebuildWackelkandidatenList`
        // unvollständige Einträge (fehlende Übersetzung) & Duplikate filtert.
        let actualCount = listStore.customList(with: listID)?.items.count ?? weakItems.count
        feedbackPlayer.playListAction()
        practiceConfirmation = WackelkandidatenConfirmation(listID: listID, count: actualCount)
    }

    // MARK: - Sections

    /// Welche Kategorien sind aktuell ausgeklappt.
    ///
    /// **2026-08-04** — Default geändert auf **komplett eingeklappt**
    /// (User-Spec: „Zum Üben" wirkte bei jedem Screen-Öffnen — auch nach
    /// App-Neustart — seltsam vorgeplumt und machte den Screen unruhig).
    /// Der User klappt die Sektion, die ihn interessiert, jetzt bewusst
    /// selbst auf.
    @State private var expandedSections: Set<String> = []

    @ViewBuilder
    private var sectionsContent: some View {
        let strong = statusStore.strongItems
        let needsWork = statusStore.needsWorkItems
        // Für „Im Aufbau": `.learning` ODER `.sparse`.
        let inProgress = (statusStore.learningItems + statusStore.sparseItems)

        // User-Request: **immer alle drei Kategorien anzeigen**, auch
        // wenn leer. Auf/Zu-klappbar pro Sektion. Microcopy bewusst
        // warm: keine Mahn- oder Alarm-Tonalität.
        //
        // **2026-06-09** — Reihenfolge: Stark → Zum Üben → Im Aufbau
        // (User-Spec). Vorher stand „Zum Üben" zuerst; der Screen soll
        // aber mit einer Bestätigung öffnen, bevor er zeigt, was noch
        // fehlt — der Blick wandert dann von selbst nach unten zu dem,
        // was als Nächstes dran ist. Der Default-Expand-State bleibt
        // unverändert bei „Zum Üben" (siehe `expandedSections`).
        section(
            id: "strong",
            title: "Stark",
            subtitle: "Sitzt — das kannst du im Schlaf. Schönes Fundament.",
            tint: HomeLernstatusCard.strongTint,
            items: strong,
            showAccuracy: true
        )

        section(
            id: "needsWork",
            title: "Zum Üben",
            subtitle: "Hier lohnt sich die nächste Runde — wiederhol einfach kurz.",
            tint: HomeLernstatusCard.needsWorkTint,
            items: needsWork,
            showAccuracy: true
        )

        section(
            id: "inProgress",
            title: "Im Aufbau",
            subtitle: "Frisch dabei — nach ein paar weiteren Versuchen sortiert sich das ganz von selbst.",
            tint: AppTheme.Colors.elumiPink,
            items: inProgress,
            showAccuracy: false
        )
    }

    /// Einzel-Sektion als **eine** Card — Header + Item-Liste sitzen jetzt
    /// gemeinsam in `appSetupCardBackground()`, demselben Card-Stil wie
    /// „Dein Fortschritt" & Co. auf dem Fortschritt-Hauptscreen (User-
    /// Spec 2026-08-04: „damit sich das Design fortsetzt"). Vorher war
    /// nur der aufgeklappte Inhalt geboxt, der Header schwamm frei auf
    /// dem Screen-Hintergrund — das brach den Card-Look der ersten Seite.
    /// Header ist tapbar und klappt die Sektion auf/zu.
    private func section(
        id: String,
        title: String,
        subtitle: String,
        tint: Color,
        items: [ItemLearningStatus],
        showAccuracy: Bool
    ) -> some View {
        let isExpanded = expandedSections.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            // Tapbarer Header — Chevron rotiert mit State.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedSections.remove(id)
                    } else {
                        expandedSections.insert(id)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            // **2026-06-09** — 17 → 21 pt (User-Spec
                            // „Überschriften größer"). Diese drei
                            // Titel sind die eigentliche Orientierung
                            // auf dem Screen und gingen im 17-pt-Grau
                            // fast unter.
                            Text(title)
                                .font(.system(size: 21, weight: .black, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("\(items.count)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(tint.opacity(0.18))
                                )
                        }
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                        .padding(.top, 4)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if items.isEmpty {
                    // Leere Sektion: dezenter Empty-State-Hinweis statt
                    // vollständig ausgeblendeter Section.
                    Text("Noch nichts in dieser Kategorie.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.top, 2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            LernstatusItemRow(item: item, tint: tint, showAccuracy: showAccuracy)
                            if index < items.count - 1 {
                                Divider()
                                    .background(AppTheme.Colors.border.opacity(0.4))
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.elumiPink.opacity(0.16))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
            }
            .frame(width: 72, height: 72)

            Text("Noch keine Signale")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Sobald du in den Modulen — Karteikarten, Training, Verbformen, Quiz — Antworten gibst, sammelt die App hier pro Vokabel, was schon sitzt und was noch Übung braucht.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Eine Row in einer Lernstatus-Sektion.
///
/// Layout:
///   • 3-pt-Farbstreifen links (status-Tint) als stille Kategorisierung
///   • Zwei-Zeilen-Text: Französisch fett, Deutsch darunter dezent
///   • Rechts: kleiner Stats-Block (Trefferquote in Prozent + N/M Versuche),
///     nur wenn `showAccuracy == true` (Sparse-Items würden sonst irre-
///     führend „0 %" zeigen).
private struct LernstatusItemRow: View {
    let item: ItemLearningStatus
    let tint: Color
    let showAccuracy: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayFrench)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.displayGerman)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if showAccuracy {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int((item.accuracy * 100).rounded()))%")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                    Text("\(item.correctCount)/\(item.totalAttempts)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .monospacedDigit()
                }
            } else {
                // Sparse-Items: statt Prozenten nur die absolute Versuchs-
                // Anzahl — eine Quote aus 2 Antworten wäre statistisch
                // sinnlos und pädagogisch eher verunsichernd.
                Text("\(item.totalAttempts) \(item.totalAttempts == 1 ? "Versuch" : "Versuche")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Trägerobjekt für das Bestätigungs-Popup nach dem Bauen von „Meine
/// Wackelkandidaten" — `Identifiable`, damit `.sheet(item:)` greift.
private struct WackelkandidatenConfirmation: Identifiable {
    let id = UUID()
    let listID: UUID
    let count: Int
}

/// **2026-08-04** — Großes, unübersehbares Bestätigungs-Popup (User-
/// Spec: „muss ein Bildschirm-Popup sein, den man sieht, zur Not
/// wegklicken"). Bestätigt zuerst, dass die Liste entstanden ist, und
/// bietet dann bewusst **drei** gleichwertige Übungswege an, statt den
/// User automatisch in eine davon zu schieben — der Sprung direkt in
/// die Karteikarten fühlte sich laut Feedback zu abrupt an.
private struct WackelkandidatenConfirmationSheet: View {
    let count: Int
    let onStartFlashcards: () -> Void
    let onStartQuiz: () -> Void
    let onStartTraining: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .fill(HomeLernstatusCard.needsWorkTint.opacity(0.16))
                    .frame(width: 84, height: 84)
                Text("💪")
                    .font(.system(size: 38))
            }

            VStack(spacing: 8) {
                Text("Liste erstellt!")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(count == 1
                     ? "„Meine Wackelkandidaten\" wurde mit 1 Wort gefüllt."
                     : "„Meine Wackelkandidaten\" wurde mit \(count) Wörtern gefüllt.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Text("Was möchtest du üben?")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                practiceOptionButton(title: "Karteikarten", systemImage: "rectangle.on.rectangle.angled", action: onStartFlashcards)
                practiceOptionButton(title: "Quiz", systemImage: "checkmark.circle.fill", action: onStartQuiz)
                practiceOptionButton(title: "Training", systemImage: "figure.strengthtraining.traditional", action: onStartTraining)
            }
            .padding(.horizontal, 20)

            Button("Später") { onDismiss() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .padding(.top, 2)

            Spacer(minLength: 12)
        }
        .padding(.top, 16)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func practiceOptionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(HomeLernstatusCard.needsWorkTint)
            )
        }
        .buttonStyle(AppCardPressStyle())
    }
}
