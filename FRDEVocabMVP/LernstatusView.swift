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
                    // **2026-08-04** — Reihenfolge getauscht (User-Spec):
                    // erst Stark/Zum Üben/Im Aufbau anschauen, DANN der
                    // CTA — mit spürbarem Extra-Abstand abgesetzt, damit
                    // er nicht wie eine vierte gleichrangige Sektion
                    // wirkt, sondern als eigener, auffälliger Schlusspunkt.
                    sectionsContent
                    practiceListCTA
                        .padding(.top, AppTheme.Spacing.xl)
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
        .onAppear { silentlyRefreshWackelkandidatenListIfNeeded() }
        // **2026-08-04** — Eigenes Popup statt `.alert(...)` (User-Spec:
        // „nicht grau, sieht aus wie'n Trauerkasten" — der System-Alert
        // lässt sich nicht umfärben, das ist iOS-Fixstil). Gleiches
        // Sheet-Muster wie `WackelkandidatenConfirmationSheet`, im
        // normalen Elumi-Kartendesign.
        .sheet(item: $sectionInfo) { info in
            SectionInfoSheet(info: info) { sectionInfo = nil }
        }
    }

    /// **2026-08-04** — Hält „Meine Wackelkandidaten" automatisch aktuell
    /// (User-Spec: „sollte im Hintergrund geschehen, ohne dass der User
    /// das merkt"). `ItemLearningStatusStore` selbst ist live/published —
    /// die Zahlen bei „Zum Üben"/„Im Aufbau" aktualisieren sich schon von
    /// selbst, sobald irgendwo geübt wird. Die generierte Liste ist aber
    /// ein Snapshot: ohne diesen Hook würden bereits gemeisterte Wörter
    /// erst beim nächsten manuellen Tap auf „Diese Wörter jetzt üben"
    /// wieder rausfallen.
    ///
    /// Sync-Punkt bewusst **Screen-Appear**, nicht live während einer
    /// laufenden Übungs-Session: mitten in einer Karteikarten-Runde
    /// Karten unter dem User wegzuziehen wäre verwirrend. Beim nächsten
    /// Öffnen des Lernstatus-Screens ist der Bestand aber garantiert
    /// frisch — und genau von hier aus wird die Liste sowieso gestartet.
    ///
    /// Baut NUR neu, wenn die Liste schon existiert (User sie also schon
    /// mal explizit angelegt hat) — legt sie nie ungefragt neu an.
    private func silentlyRefreshWackelkandidatenListIfNeeded() {
        guard listStore.customList(with: VocabularyListStore.wackelkandidatenListID) != nil else { return }
        listStore.rebuildWackelkandidatenList(from: statusStore.wackelkandidatenItems)
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
    ///
    /// **2026-08-04** — Auffälliger gemacht (User-Spec: „muss ein
    /// bisschen mehr ins Auge springen"): größeres Icon, kräftiger
    /// Farb-Rahmen in der Wackelkandidaten-Farbe statt der neutralen
    /// Setup-Card, Titel eine Stufe größer.
    ///
    /// **2026-08-05** — Auf CTA-Gelb umgestellt (User-Spec: „ist ja auch
    /// eine Art CTA, müsste dann wahrscheinlich auch so gelblich sein,
    /// wie die Üben-Pill"). Vollflächig `AppTheme.Colors.cta` statt
    /// dunkler Card mit farbigem Rahmen — dieselbe Farbe wie „Los
    /// geht's!" und die „Üben"-Pille, damit sie unmissverständlich als
    /// primäre Aktion auf dem Screen erkennbar ist. Text/Icon dafür auf
    /// Schwarz umgestellt (Kontrast auf hellem Gelb) statt der bisherigen
    /// hellen Primary-/Secondary-Textfarben, die auf Gelb kaum lesbar
    /// wären.
    @ViewBuilder
    private var practiceListCTA: some View {
        // **2026-08-04** — tatsächliche, gefilterte Zahl statt der rohen
        // Wackelkandidaten-Zählung (User-Report: Button sagte „68",
        // Popup danach „58 Wörtern" — die Differenz sind Einträge ohne
        // beide Sprachseiten oder Duplikate, die `rebuildWackelkandidatenList`
        // ohnehin rausfiltert). Beide Zahlen laufen jetzt über dieselbe
        // Filter-Funktion, damit sie strukturell nie auseinanderlaufen
        // können.
        let count = VocabularyListStore.usableWackelkandidatenItems(from: statusStore.wackelkandidatenItems).count
        if count > 0 {
            Button {
                buildAndPracticeWackelkandidaten()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.12))
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diese Wörter jetzt üben")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                        Text(count == 1
                             ? "Baut aus deinem 1 Wackelkandidaten eine Übungsliste."
                             : "Baut aus deinen \(count) Wackelkandidaten eine Übungsliste.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.black.opacity(0.65))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(AppTheme.Colors.cta)
                )
                .shadow(
                    color: AppTheme.Shadow.card.color,
                    radius: AppTheme.Shadow.card.radius,
                    x: AppTheme.Shadow.card.x,
                    y: AppTheme.Shadow.card.y
                )
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

    /// **2026-08-04** — Trägt Titel + Erklärtext für den aktuell offenen
    /// Info-Popup (User-Spec: Unterschied „Zum Üben" vs. „Im Aufbau" war
    /// nicht selbsterklärend). Typ-Definition auf Dateiebene, siehe
    /// `SectionInfo` unten.
    @State private var sectionInfo: SectionInfo?

    @ViewBuilder
    private var sectionsContent: some View {
        let strong = statusStore.strongItems
        // **2026-08-04** — `hasCompleteTranslation`-Filter (User-Report:
        // „Zum Üben" + „Im Aufbau" summierten sich auf 64, aber die
        // Wackelkandidaten-Liste zeigte nur 54 — Einträge mit nur einer
        // Sprachseite zählten hier mit, fielen aber beim Listenbau raus).
        // Beide Zahlen laufen jetzt über dasselbe Kriterium.
        let needsWork = statusStore.needsWorkItems.filter(\.hasCompleteTranslation)
        // Für „Im Aufbau": `.learning` ODER `.sparse`.
        let inProgress = (statusStore.learningItems + statusStore.sparseItems)
            .filter(\.hasCompleteTranslation)

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
            showAccuracy: true,
            infoMessage: "Diese Wörter hast du schon öfter geübt — aber noch nicht oft genug richtig beantwortet. Deshalb lohnt sich hier eine Wiederholung besonders."
        )

        section(
            id: "inProgress",
            title: "Im Aufbau",
            subtitle: "Frisch dabei — nach ein paar weiteren Versuchen sortiert sich das ganz von selbst.",
            tint: AppTheme.Colors.elumiPink,
            items: inProgress,
            showAccuracy: false,
            infoMessage: "Bei diesen Wörtern hat die App noch nicht genug Antworten von dir, um sicher zu sagen, ob sie schon sitzen oder noch wackeln. Übe einfach weiter, dann sortieren sie sich von selbst in „Stark\" oder „Zum Üben\" ein."
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
        showAccuracy: Bool,
        infoMessage: String? = nil
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
                            // **2026-08-04** — Info-Button (User-Spec: der
                            // Unterschied „Zum Üben" vs. „Im Aufbau" war
                            // nicht selbsterklärend). Eigenes 28×28-Tap-
                            // Ziel + `contentShape`, verschachtelt im
                            // Header-Button — dasselbe Pattern wie der
                            // reparierte Umbenennen-Stift bei „Meine
                            // Listen", damit der Tap zuverlässig NUR den
                            // Info-Alert öffnet statt die Sektion zu
                            // klappen.
                            if let infoMessage {
                                Button {
                                    sectionInfo = SectionInfo(title: title, message: infoMessage, tint: tint)
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
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

            // **2026-08-04** — Beide Zweige zeigen jetzt zusätzlich
            // `remainingCorrectForStrong` (User-Spec: „nur die Anzahl
            // Versuche sagt mir nichts — ich brauche richtig/falsch UND
            // wie viel noch fehlt"). Kein Alarm-Ton, sondern eine
            // konkrete, erreichbare Zielgröße.
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
                    // **2026-08-04** — „in Folge" ergänzt (User-Spec: bei
                    // niedriger Quote wirkte eine nackte „noch 10×" ohne
                    // Kontext unverständlich/entmutigend groß — die Zahl
                    // ist so hoch, weil die GESAMT-Quote über alle
                    // bisherigen Versuche hinweg gerechnet wird, nicht
                    // nur die letzten Antworten. „in Folge" macht klar:
                    // das ist der garantierte Weg (ohne einen weiteren
                    // Fehler), nicht die einzig mögliche Reihenfolge.
                    Text("noch \(item.remainingCorrectForStrong)× in Folge")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                // Sparse-/Learning-Items: statt einer nackten Prozentzahl
                // (bei wenigen Versuchen statistisch wenig aussagekräftig)
                // die konkrete richtig/falsch-Aufschlüsselung + Prognose.
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(item.correctCount) richtig · \(item.wrongCount) falsch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .monospacedDigit()
                    // **2026-08-04** — „in Folge" ergänzt (User-Spec: bei
                    // niedriger Quote wirkte eine nackte „noch 10×" ohne
                    // Kontext unverständlich/entmutigend groß — die Zahl
                    // ist so hoch, weil die GESAMT-Quote über alle
                    // bisherigen Versuche hinweg gerechnet wird, nicht
                    // nur die letzten Antworten. „in Folge" macht klar:
                    // das ist der garantierte Weg (ohne einen weiteren
                    // Fehler), nicht die einzig mögliche Reihenfolge.
                    Text("noch \(item.remainingCorrectForStrong)× in Folge")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Trägerobjekt für das Info-Popup zu „Zum Üben"/„Im Aufbau" —
/// `Identifiable`, damit `.sheet(item:)` greift.
private struct SectionInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let tint: Color
}

/// **2026-08-04** — Eigenes, kleines Popup im Elumi-Kartendesign statt
/// `.alert(...)` (User-Spec: „nicht grau, sieht aus wie'n Trauerkasten"
/// — der System-Alert ist fix grau/weiß und nicht themebar). Kompakter
/// als das Wackelkandidaten-Bestätigungs-Popup — hier gibt's nur einen
/// Erklärtext + einen Schließen-Button, kein Detent-Höhen-Bedarf.
private struct SectionInfoSheet: View {
    let info: SectionInfo
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(info.tint.opacity(0.16))
                    .frame(width: 64, height: 64)
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(info.tint)
            }

            VStack(spacing: 8) {
                Text(info.title)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(info.message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Button("Verstanden") { onDismiss() }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(info.tint)
                )
                .buttonStyle(AppCardPressStyle())
                .padding(.top, 4)

            Spacer(minLength: 20)
        }
        .padding(.top, 12)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
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
            // **2026-08-04** — 24pt statt vorher zu wenig Top-Abstand
            // (User-Spec: „Kreis um die Faust ist abgeschnitten"). Der
            // Kreis brauchte mehr Luft zum Drag-Indicator des Sheets.
            Spacer(minLength: 24)

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

                // **2026-08-04** — `fixedSize` erzwingt, dass der Text
                // seine volle benötigte Höhe bekommt, statt bei knappem
                // Sheet-Platz mit „…" abgeschnitten zu werden (User-Spec:
                // „darf nicht abgekürzt werden"). In Kombination mit dem
                // festen `.large`-Detent unten ist immer genug Höhe da.
                Text(count == 1
                     ? "„Meine Wackelkandidaten\" wurde mit 1 Wort gefüllt."
                     : "„Meine Wackelkandidaten\" wurde mit \(count) Wörtern gefüllt.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Was möchtest du üben?")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 24)

            // **2026-08-04** — Icons + Farben 1:1 vom Hauptscreen (User-
            // Spec): `HomeModuleIcon` + `AppTheme.Colors.module*` statt
            // generischer SF-Symbole — dasselbe Karteikarten-/Quiz-/
            // Vokabeln-Icon-Set wie im Home-Grid.
            //
            // **2026-08-04, zweite Runde** — dritter Button hieß erst
            // „Training", sprang aber technisch immer nur in den
            // Vokabeln-Modus (Training hat daneben noch Nomen/Artikel/
            // Verben/Verbformen). User-Entscheidung: Button ehrlich
            // „Vokabeln üben" nennen statt ein Untermenü einzubauen —
            // die anderen Trainingsmodi bleiben über Meine Listen →
            // Liste auswählen → Training-Hub erreichbar.
            VStack(spacing: 12) {
                practiceOptionButton(
                    title: "Karteikarten",
                    icon: .karteikarten,
                    tint: AppTheme.Colors.moduleFlashcards,
                    action: onStartFlashcards
                )
                practiceOptionButton(
                    title: "Quiz",
                    icon: .quiz,
                    tint: AppTheme.Colors.moduleQuiz,
                    action: onStartQuiz
                )
                practiceOptionButton(
                    title: "Vokabeln üben",
                    icon: .vokabeln,
                    tint: AppTheme.Colors.moduleVocabulary,
                    action: onStartTraining
                )
            }
            .padding(.horizontal, 20)

            Button("Später") { onDismiss() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .padding(.top, 2)

            Spacer(minLength: 20)
        }
        .padding(.top, 12)
        // **2026-08-04** — Nur noch `.large` (vorher `[.medium, .large]`):
        // beim `.medium`-Start war zu wenig Höhe für Icon-Kreis + Text +
        // drei Options-Buttons, was zu Beschnitt/Abkürzung führte (User-
        // Spec: „Fenster muss größer aufgehen").
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// **2026-08-04** — Icon bleibt in seinen nativen Asset-Farben (wie
    /// überall sonst in der App, z. B. `moduleResultCard` im GameHub) —
    /// eine vollflächig eingefärbte Pille dahinter würde mit den eigenen
    /// Farben des Icons kollidieren. Der Modul-Akzent färbt stattdessen
    /// den dezenten Card-Hintergrund + Rahmen + Chevron ein.
    private func practiceOptionButton(
        title: String,
        icon: HomeModuleIcon,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                HomeModuleIconView(icon: icon, size: 36)
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(AppCardPressStyle())
    }
}
