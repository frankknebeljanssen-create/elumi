import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @Environment(\.appOpenAccountAction) private var openAccountAction
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    /// **2026-08-05** — für den Ziel-System-Testblock der Dev-Card: der
    /// Inhalts-Fortschritt rechnet gegen eine echte Vokabelliste. Gleiches
    /// Durchreich-Muster wie bei `TrophyView` / `LernstatusView`.
    @ObservedObject var listStore: VocabularyListStore
    let goHome: () -> Void
    let openInfo: () -> Void
    private let sectionStyle: AppSectionStyle = .home

    @State private var dictionaryStats: (total: Int, breakdown: [DictionaryWordClassCount]) = (0, [])
    @State private var dictionaryDetailActive: Bool = false
    @State private var arcadeDetailActive: Bool = false
    /// Gate für das Multi-Account-Switcher-Sheet. Zeigt `AccountSwitcherSheet`.
    @State private var isShowingAccountSwitcher: Bool = false
    @ObservedObject private var accountStore = AccountStore.shared
    /// **2026-08-05** — Ziel-System-Testblock der Dev-Card. `@ObservedObject`
    /// ist hier der Punkt: Ohne die Beobachtung würde ein Tap auf
    /// „Ziel: 3 Tage" den Store zwar ändern, die Card aber nicht neu
    /// zeichnen — der Button bliebe ungefärbt und es sähe aus, als wäre
    /// nichts passiert.
    @ObservedObject private var goalStore = LearningGoalStore.shared
    /// Für das Zustands-Lämpchen auf der „Tipps erneut anzeigen"-Card —
    /// die Farbe muss sich ändern, sobald Tipps gesehen oder
    /// zurückgesetzt wurden.
    @ObservedObject private var hintStore = HintStore.shared
    /// Zweistufige Alerts für die beiden User-sichtbaren Resets. Getrennte
    /// Flags, damit versehentlich nie beides zusammen geöffnet wird —
    /// das würde die Warnlogik untergraben.
    @State private var isShowingGameStateResetAlert: Bool = false
    @State private var isShowingListsResetAlert: Bool = false
    #if DEBUG
    @State private var isShowingDevResetAlert: Bool = false
    /// Dev-Tools: aktuell im Stepper ausgewählter Spiele-Wert (0…5).
    /// Initial aus `ProgressStore.arcadeCredits` gespiegelt — wird beim
    /// Card-Appear gesetzt.
    @State private var devSpiele: Int = 0
    #endif

    /// Globale Speed-Round-Dauer — einzige Schreibstelle für den
    /// App-Storage-Key. Alle Module lesen denselben Wert (via
    /// `SpeedRoundSettings.currentSeconds` oder eigenem
    /// @AppStorage-Binding auf `appSpeedRoundDurationKey`).
    @AppStorage(appSpeedRoundDurationKey) private var speedRoundDurationSeconds: Int = SpeedRoundDuration.defaultDuration.rawValue

    /// **Scan — Smart-Region-Crop (Opt-in, Slice 11)**: Power-User-
    /// Toggle. Aktiv → FreeText-Scans werden nach der
    /// Perspektivkorrektur zusätzlich auf den erkannten Textbereich
    /// beschnitten. Default aus — die meisten User wollen das volle
    /// Foto behalten. Im Smart-Scanner wird der Toggle über
    /// `ScanSettings.smartRegionCropEnabled` gelesen.
    @AppStorage(appScanSmartRegionCropKey) private var scanSmartRegionCropEnabled: Bool = false

    /// Sub-Zeile unter der „Stimme"-Card — zeigt die aktuelle User-Wahl
    /// pro Sprache kompakt (z. B. „Deutsch: Anna · Französisch:
    /// Systemstandard"). Die Namen sind dynamisch — was der User
    /// tatsächlich auf seinem Gerät wählt, nicht eine feste Liste.
    private var voiceSettingsSubline: String {
        let de = SpeechVoiceService.shared.selectedOption(
            forRecord: VoiceSettingsStore.shared.germanRecord,
            language: .german
        ).displayName
        let fr = SpeechVoiceService.shared.selectedOption(
            forRecord: VoiceSettingsStore.shared.frenchRecord,
            language: .french
        ).displayName
        return "Deutsch: \(de) · Französisch: \(fr)"
    }

    /// Sub-Zeile unter der „Meine Accounts"-Card: zeigt den aktiven
    /// Account-Namen plus, falls es mehrere gibt, die Gesamtzahl.
    /// Beispiel: „Frank · 1 weiterer" / „Frank · 2 weitere".
    private var accountSwitcherSubline: String {
        guard let active = accountStore.currentAccount else {
            return "Kein Account aktiv"
        }
        let others = max(0, accountStore.accounts.count - 1)
        if others == 0 { return active.displayName }
        if others == 1 { return "\(active.displayName) · 1 weiterer" }
        return "\(active.displayName) · \(others) weitere"
    }

    /// **Voice-Settings-Sheet (Phase 9)** — Gate für die Stimme-
    /// Auswahl-View. Eigener Flag, damit die Präsentation klar vom
    /// Account-Switcher / Dictionary-Sheet / Arcade-Sheet getrennt ist.
    @State private var isShowingVoiceSettings: Bool = false

    /// **Developer-Gruppe (User-Revision 2026-04-22)** — faltet
    /// Icon-Stil, Spiel-Events-Test, „Meine Listen löschen" und (in
    /// DEBUG) den Entwicklungs-Spielstand-Reset in eine einzige
    /// ausklappbare Section zusammen. Entlastet die Haupt-Settings-
    /// Liste und trennt optisch User-relevante Aktionen (oben) vom
    /// Developer-Kram (unten, ausgeklappt bei Bedarf).
    @State private var isDeveloperExpanded: Bool = false

    /// Footer-Clearance analog zu `HomeView` / `InfoView`: die Card-
    /// Liste wird sonst von der globalen Bottom-Bar verdeckt — der User
    /// sah dann die letzten Cards nur halb und konnte nicht scrollen,
    /// weil der äußere Container gar kein `ScrollView` war. Fix: den
    /// VStack in ein `ScrollView` wrappen und unten genug Luft für den
    /// Footer reservieren.
    ///
    /// **2026-05-08 Padding-Cleanup** — Global-Chrome-Branch reserviert
    /// keine Footer-Höhe mehr (Footer-Migration zu `.safeAreaInset`
    /// macht das System-seitig). Beide Branches geben jetzt nur den
    /// kleinen Atemraum-Buffer `Spacing.lg` zurück. Property bleibt
    /// für etwaige zukünftige Lokal-Chrome-Pfade erhalten.
    private var footerClearance: CGFloat {
        AppTheme.Spacing.lg
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 14) {
            // Systemweiter Header: Back-Chevron links, Titel mittig.
            // Kein Icon rechts — einheitlich mit Listen / Lernstatus /
            // Akzente usw.
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Einstellungen",
                subtitle: "",
                systemImage: nil,
                onBack: { dismiss() },
                centeredTitle: true
            )

            // **Mein Konto** — jetzt als erste Card in der Settings-
            // Liste (User-Wunsch: wichtigste Aktion nach oben).
            Button {
                openAccountAction?()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        // **Naming-Sweep 2026-05-06** — „Mein Konto"
                        // → „Mein Profil" (passt zum Subtitle
                        // „Vorname und Profil" und zum visuellen
                        // Avatar-Pattern).
                        Text("Mein Profil")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("Vorname und Profil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    // Cartoon-Mein-Konto statt SF `person.crop.circle.fill`.
                    ElumiIconView(icon: .meinKonto, size: 56)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            }
            .buttonStyle(.plain)

            // **Meine Accounts** — Multi-User-Switcher (Phase 8).
            // Zeigt aktiven Account + Anzahl weiterer Accounts;
            // Tap öffnet `AccountSwitcherSheet` mit Liste + Neu-CTA +
            // Löschen. Bewusst als **zweite** Card unter „Mein Konto":
            // „Mein Konto" = Details des aktiven Users, „Meine
            // Accounts" = zwischen Usern wechseln.
            Button {
                isShowingAccountSwitcher = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        // **Naming-Sweep 2026-05-06** — „Meine
                        // Accounts" → „Account wechseln" (klare
                        // Aktion: Multi-User-Switcher öffnen).
                        Text("Account wechseln")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(accountSwitcherSubline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if let active = accountStore.currentAccount {
                        ZStack {
                            Circle()
                                .fill(sectionStyle.accent.opacity(0.22))
                                .frame(width: 56, height: 56)
                            Text(active.avatarEmoji)
                                .font(.system(size: 28))
                        }
                    } else {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(sectionStyle.accent)
                            .frame(width: 56, height: 56)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            }
            .buttonStyle(.plain)

            // **Ton-Toggle** — kompakt: ein einziger Row, Icon + Toggle-
            // Label + Switch. Die frühere Header-Zeile „Ton" + Doppel-
            // Label ist entfallen; Padding + Size reduziert.
            HStack(spacing: 12) {
                ElumiIconView(
                    icon: feedbackPlayer.areSoundsEnabled ? .lautsprecherOn : .lautsprecherOff,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    // **Naming-Sweep 2026-05-06** — „Ton an/aus" →
                    // „Sound" (statisch, der Toggle-Switch zeigt
                    // den Zustand). Subtitle gekürzt: „Startsound
                    // und Feedback-Töne" → „Effekte und Töne".
                    Text("Sound")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Effekte und Töne")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $feedbackPlayer.areSoundsEnabled)
                    .toggleStyle(.switch)
                    .tint(sectionStyle.accent)
                    .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)

            // **Stimme** (Phase 9) — Apple-interne TTS-Stimmen wählen
            // (Vicki / Yannick / Thomas + Systemstandards). Details
            // siehe `VoiceSettingsView` — der Screen führt den User
            // inkl. Deep-Link in die iPhone-Einstellungen, wenn eine
            // empfohlene Stimme noch nicht installiert ist.
            Button {
                isShowingVoiceSettings = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stimme")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(voiceSettingsSubline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                        .frame(width: 56, height: 56)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            }
            .buttonStyle(.plain)

            Button {
                openInfo()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        // **Naming-Sweep 2026-05-06** — „Info" →
                        // „Tipps zur App" (zeigt sofort, was es
                        // ist: praktische Hinweise, nicht
                        // bürokratisches Info-Sammelbecken).
                        // Subtitle bleibt unverändert.
                        Text("Tipps zur App")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("Hilfe und Hinweise zur App")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    // Cartoon-Info statt SF `info.circle.fill`.
                    ElumiIconView(icon: .info, size: 56)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            }
            .buttonStyle(.plain)

            speedRoundDurationCard

            dictionaryStatsCard

            globalListSelectionCard

            arcadeInfoCard

            scanSmartRegionCard

            // **Developer-Section** — ausklappbare Gruppe mit Entwickler-
            // nahen Reglern: Spiel-Events-Testmodus, Custom-Listen-
            // Löschen, Credits zurücksetzen, Tipps erneut anzeigen und
            // (im DEBUG-Build) dem Entwicklungs-Spielstand-Reset. Nicht
            // mehr einzeln im Haupt-Flow — wird bei Bedarf aufgeklappt.
            // **2026-06-09**: „Credits zurücksetzen" + „Tipps erneut
            // anzeigen" aus dem Haupt-Flow hierher verschoben — beides
            // sind Tester-/Entwickler-Aktionen, keine alltäglichen
            // User-Settings.
            developerSection

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        // **Chevron-Y-Sweep 2026-05-07** — Auf
        // `headerChevronTopPadding` (= 0) umgezogen, damit der
        // Settings-Chevron auf TrainingHub-Höhe sitzt — gemeinsam mit
        // allen anderen Push-Screens.
        .padding(.top, AppLayout.headerChevronTopPadding)
        // Bottom-Padding = Footer-Clearance, damit die unterste Card
        // (Wörterbuch / Arcade / DEBUG-Reset) komplett über der globalen
        // Bottom-Bar sitzt. Vorher: flaches `screenPadding` → letzte
        // Card unter Footer abgeschnitten → wirkte wie „nicht scrollbar".
        .padding(.bottom, footerClearance)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .center)
        }  // ← ScrollView-Ende
        .onAppear {
            if dictionaryStats.total == 0 {
                dictionaryStats = SupplementalFreeDictLexicon.dictionaryStatistics()
            }
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingAccountSwitcher) {
            AccountSwitcherSheet(accountStore: accountStore)
        }
        .sheet(isPresented: $isShowingVoiceSettings) {
            VoiceSettingsView()
        }
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

    /// Globale Speed-Round-Dauer — eine einzige Stelle in den Settings
    /// steuert, wie lang die Speed-Round in **allen** Modulen läuft
    /// (Training, Verbformen, Akzente, künftige Kurzmodi).
    ///
    /// Layout: Überschrift + kurze Untertitel-Erklärung + segmentierter
    /// Picker mit den vier festen Optionen 20/30/45/60 Sekunden. Der
    /// aktuelle Wert wird live über den zentralen App-Storage-Key
    /// (`appSpeedRoundDurationKey`) an alle Module verteilt.
    private var speedRoundDurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // **Naming-Sweep 2026-05-06** — Title
                    // „SpeedRoundTerminology.name Dauer" →
                    // „Speed-Dauer" (kürzer, der Subtitle gibt den
                    // Kontext). Subtitle „Gilt für alle Speed-
                    // Moduss in der App" → „Wie lange läuft Speed-
                    // Modus?" (Tippfehler „Moduss" raus, klare
                    // Frage statt Beamten-Ankündigung).
                    Text("Speed-Dauer")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Wie lange läuft Speed-Modus?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // Blitz-Icon spiegelt den Speed-Round-Look aus den
                // Modus-Cards (Training, Verbformen, Akzente).
                Image(systemName: "bolt.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(sectionStyle.accent.opacity(0.18))
                    )
            }

            // Segmented Picker — einfach, eindeutig, für Eltern und
            // Kinder gleichermaßen verständlich. Binding über
            // `SpeedRoundDuration?`, damit ungültige persistierte Werte
            // (z. B. aus Future-Versionen mit mehr Optionen) auf den
            // Default kippen, statt die Auswahl zu leeren.
            Picker(
                "Dauer in Sekunden",
                selection: Binding<SpeedRoundDuration>(
                    get: {
                        SpeedRoundDuration(rawValue: speedRoundDurationSeconds)
                            ?? SpeedRoundDuration.defaultDuration
                    },
                    set: { newValue in
                        speedRoundDurationSeconds = newValue.rawValue
                    }
                )
            ) {
                ForEach(SpeedRoundDuration.allCases, id: \.self) { duration in
                    Text(duration.compactLabel).tag(duration)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    /// **Smart-Region-Crop (Power-User, Slice 11)** — Opt-in-Toggle im
    /// Scan-Bereich. Wenn aktiv, beschneidet der FreeText-Scan das
    /// korrigierte Bild zusätzlich auf den erkannten Textbereich,
    /// statt das volle Foto zu übernehmen.
    ///
    /// Default aus (die meisten User wollen das volle Foto). Nur
    /// sichtbar in FreeText-Scans; die Vokabel-Liste bleibt
    /// unberührt (hat eigene Dokument-Quad-Logik). Nur-Text-Card,
    /// keine eigene Detail-Sheet — ein Satz Erklärung plus Switch
    /// reicht für diese Power-User-Option.
    private var scanSmartRegionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text enger zuschneiden")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Scan: Freier Text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "crop")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(sectionStyle.accent.opacity(0.18))
                    )
            }

            Toggle(isOn: $scanSmartRegionCropEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scanSmartRegionCropEnabled ? "Zuschneiden aktiv" : "Ganzes Foto behalten")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(
                        scanSmartRegionCropEnabled
                            ? "Schneidet Poster-/Packungs-Fotos auf den erkannten Textbereich."
                            : "FreeText-Fotos bleiben so, wie du sie aufgenommen hast."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(sectionStyle.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    /// Wörterbuch-Header-Card: nur Titel + Anzahl + Icon. Klick öffnet Detail-Sheet.
    private var dictionaryStatsCard: some View {
        Button {
            dictionaryDetailActive = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wörterbuch")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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

                // Cartoon-Wörterbuch statt SF `book.fill`. Kein
                // foregroundStyle — das SVG bringt eigene Farbigkeit mit.
                ElumiIconView(icon: .woerterbuch, size: 56)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $dictionaryDetailActive) {
            DictionaryStatsDetailSheet(stats: dictionaryStats, sectionStyle: sectionStyle)
        }
    }

    /// **Globale Listen-Auswahl** (Stufe 5, 2026-04-29). Master-Switch:
    /// wenn aktiv, nutzen alle Lern-Module dieselbe Listen-Auswahl. Wenn
    /// aus, behält jedes Modul seine eigene Auswahl. Akzente und
    /// persönliche Stapel sind außerhalb dieses Schalters.
    ///
    /// **Initial-Default-Logik (im Setter):** wenn der User den Toggle
    /// von OFF auf ON wechselt UND die globale Auswahl aktuell leer/nil
    /// ist, wird sie mit der UUID der „A1 Grundwortschatz"-Liste
    /// initialisiert. Spec 5: „Beim Aktivieren wird die globale Auswahl
    /// auf Grundwortschatz A1 zurückgesetzt." Bei Re-Aktivierung mit
    /// vorhandener Auswahl wird diese **nicht** überschrieben — der
    /// User-Workflow „mal eben ausschalten und wieder ein" verliert
    /// keine Wahl.
    private var globalListSelectionCard: some View {
        @AppStorage(appUseGlobalListSelectionKey) var useGlobal: Bool = true

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                Text("Globale Lernlisten-Auswahl")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            Text("Wenn aktiv, nutzen Karteikarten, Quiz, Training und Word Runner dieselbe Lernlisten-Auswahl. Wenn aus, behält jedes Modul seine eigene. Akzente und persönliche Stapel sind unabhängig.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { useGlobal },
                set: { newValue in
                    // Initial-Default-Logik: erste Aktivierung füllt die
                    // globale Auswahl mit der „A1 Grundwortschatz"-UUID,
                    // damit kein leerer Pool entsteht. Re-Aktivierung
                    // (Auswahl bereits vorhanden) lässt den State intakt.
                    if newValue, VocabularyListSelectionResolver.currentGlobalSelectedListIDs() == nil {
                        VocabularyListSelectionResolver.setGlobalSelectedListIDs(
                            [VocabularyListSelectionResolver.defaultGlobalSelectionListID]
                        )
                    }
                    useGlobal = newValue
                }
            )) {
                Text("Aktivieren")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .toggleStyle(.switch)

            Text("Beim Aktivieren wird die globale Auswahl auf Grundwortschatz A1 zurückgesetzt. Du kannst sie danach jederzeit anpassen.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(AppTheme.Colors.elumiBlue.opacity(0.30), lineWidth: 1)
        )
    }

    /// Arcade-Spielregeln-Header — Tap öffnet Detail-Sheet mit Icons + Erklärungen.
    private var arcadeInfoCard: some View {
        Button {
            arcadeDetailActive = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Elumi Spiel")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Spielregeln & Icons")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // Cartoon-Elumi-Spiel statt SF `gamecontroller.fill`.
                ElumiIconView(icon: .elumiSpiel, size: 56)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $arcadeDetailActive) {
            ArcadeRulesDetailSheet(sectionStyle: sectionStyle)
        }
    }

    // MARK: - Developer-Section (Phase 9)

    /// Kollabierbare Gruppe mit Entwickler-nahen Reglern. Default
    /// collapsed — expandiert auf Tap-Header. Enthält (in dieser
    /// Reihenfolge): Spiel-Events-Test → Meine Listen löschen → Credits
    /// zurücksetzen → Tipps erneut anzeigen → (DEBUG) Entwicklungs-
    /// Spielstand-Reset.
    ///
    /// **Alle Cards in dieser Section** (inkl. Header) nutzen den
    /// `appCardBackground(tint:)`-Overload mit `developerAccent` statt
    /// `sectionStyle` — ein einheitliches Slate-Grau, das sich klar von
    /// den Modul-Farben der übrigen Settings-Cards absetzt, damit auf
    /// einen Blick erkennbar ist: alles hier ist Developer-Kram.
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isDeveloperExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.developerAccent)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Developer")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(isDeveloperExpanded
                             ? "Regler für Tester:innen & Entwicklung"
                             : "Spiel-Events, Listen-Reset, Credits, Tipps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.developerAccent)
                        .rotationEffect(.degrees(isDeveloperExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCardBackground(tint: AppTheme.Colors.developerAccent)
            }
            .buttonStyle(.plain)

            if isDeveloperExpanded {
                VStack(spacing: 14) {
                    // **2026-06-09** — Ganz oben: die im Test am
                    // häufigsten gebrauchte Aktion, und ihr Lämpchen
                    // zeigt gleich den Zustand der Tipps an.
                    hintsResetCard
                    testModusArcadeCard
                    customListsResetCard
                    gameStateResetCard
                    #if DEBUG
                    devResetCard
                    #endif
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// **Tipps erneut anzeigen** (2026-06-09) — setzt den `HintStore`
    /// zurück, damit alle dismissible Erstnutzer-Hints wieder
    /// erscheinen. Nicht-destruktiv (nur UI-State, keine Lerndaten),
    /// daher ohne Bestätigungs-Alert — anders als die Reset-Cards
    /// daneben. In die Developer-Section verschoben (vorher im
    /// Haupt-Flow) — reine Tester-Aktion.
    private var hintsResetCard: some View {
        // **2026-06-09** — Das Lämpchen zeigt den Zustand: grün, solange
        // noch Tipps offen sind, grau sobald alle gesehen wurden. Vorher
        // war es dauerhaft grau — man konnte nicht erkennen, ob der Tap
        // etwas bewirkt hat oder ob noch Tipps zu erwarten sind.
        let hasPending = hintStore.hasPendingHints
        let openCount = HintStore.allHintIDs.subtracting(hintStore.seenHintIDs).count
        return Button {
            HintStore.shared.resetAll()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tipps erneut anzeigen")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(hasPending
                         ? "\(openCount) von \(HintStore.allHintIDs.count) Tipps offen"
                         : "Alle Tipps gesehen — tippen zum Zurücksetzen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "lightbulb.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(hasPending
                                     ? AppTheme.Colors.success
                                     : AppTheme.Colors.developerAccent)
                    // Leichter Schein im aktiven Zustand — macht den
                    // Unterschied auch im Augenwinkel sichtbar.
                    .shadow(color: hasPending
                            ? AppTheme.Colors.success.opacity(0.55)
                            : .clear,
                            radius: 8)
                    .frame(width: 56, height: 56)
                    .animation(.easeInOut(duration: 0.22), value: hasPending)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appCardBackground(tint: hasPending
                               ? AppTheme.Colors.success
                               : AppTheme.Colors.developerAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - User-sichtbare Resets

    /// Spielstand-Reset — user-sichtbar (Release + DEBUG). Ruhige,
    /// systemkonforme Card-Optik (kein rotes „Entwicklung"-Badge).
    /// Ein Tap öffnet einen Alert mit klarer Warnung — der eigentliche
    /// Reset passiert erst nach Bestätigung.
    ///
    /// Scope identisch zum Debug-Reset (`GameStateResetService`):
    /// XP, Streak, Credits, Highscore, Sammelwerte, Tages-Challenge,
    /// Session-Resume-Snapshots. Profil und Custom-Listen bleiben.
    /// **User-Revision 2026-04-22**: Card umbenannt zu „Credits
    /// zurücksetzen" + graue Subline-Erklärung entfernt. Fachlich
    /// unverändert — `GameStateResetService.resetGameState()` setzt
    /// Credits, XP, Streak, Tagesaufgabe zurück und vergibt dadurch
    /// wieder neue Credits beim nächsten Start.
    private var gameStateResetCard: some View {
        Button {
            isShowingGameStateResetAlert = true
        } label: {
            HStack(spacing: 12) {
                Text("Credits zurücksetzen")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(width: 56, height: 56)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appCardBackground(tint: AppTheme.Colors.developerAccent)
        }
        .buttonStyle(.plain)
        .alert("Credits zurücksetzen?", isPresented: $isShowingGameStateResetAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Zurücksetzen", role: .destructive) {
                GameStateResetService.resetGameState()
            }
        } message: {
            Text("Credits, XP, Streak und Tagesaufgabe werden auf den Ausgangszustand gesetzt. Beim nächsten Start werden neue Credits vergeben. Profil und eigene Lernlisten bleiben erhalten.")
        }
    }

    /// Listen-Reset — **destruktiver** User-Reset. Löscht alle vom
    /// Nutzer angelegten Vokabel-Listen inklusive der dort gespeicherten
    /// Einträge. Eigene Card + eigener Alert, damit niemand diese Aktion
    /// versehentlich mit dem Spielstand-Reset verwechselt.
    ///
    /// Icon ist der `trash`-Typ + Error-Tint — liest sich klar als
    /// „Löschaktion", nicht als „Reset".
    private var customListsResetCard: some View {
        Button {
            isShowingListsResetAlert = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meine Lernlisten löschen")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Entfernt alle selbst angelegten Lernlisten. Nicht rückgängig zu machen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.error)
                    .frame(width: 56, height: 56)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appCardBackground(tint: AppTheme.Colors.developerAccent)
        }
        .buttonStyle(.plain)
        .alert("Meine Lernlisten löschen?", isPresented: $isShowingListsResetAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                GameStateResetService.resetCustomLists()
            }
        } message: {
            Text("Alle vom dir angelegten Lernlisten werden entfernt. Die App-Startlisten bleiben. Eventuell einmal die App neu starten, damit die Änderung überall sichtbar wird.")
        }
    }

    #if DEBUG
    /// Dev-Reset-Card — **nur im DEBUG-Build sichtbar**. Setzt den gesamten
    /// Spielstand (XP, Streak, Credits, Highscore, Sammelwerte, Tages-
    /// Challenge) auf den Ausgangszustand zurück. Profil und Custom-Listen
    /// bleiben unberührt. Im Release-Build ist der komplette Block via
    /// `#if DEBUG` ausgeblendet — kein manuelles Aufräumen später nötig.
    ///
    /// **Erweitert (Dev-Tools, Phase 7)**: zusätzlich Spiele-Stepper
    /// (direkt Credits setzen, 0…5) und XP-Setter (0 / 100 / 500 / 1000
    /// / 2500 / 5000) zum schnellen Reproduzieren von Progress-Zuständen
    /// ohne komplette Lernsessions durchzuspielen.
    /// Kompakter Button im Dev-Card-Stil — gleiche Optik wie die
    /// XP-Setter-Buttons darüber, damit der Block nicht aus der Card fällt.
    ///
    /// `isActive` färbt den Button ein, wenn der zugehörige Zustand
    /// gerade gesetzt ist. Ohne diese Rückmeldung sieht ein Tap aus, als
    /// wäre nichts passiert — die Wirkung lag bisher nur in der Konsole.
    private func devGoalButton(
        _ title: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .black : AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? AppTheme.Colors.cta : AppTheme.Colors.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.Colors.cta, lineWidth: isActive ? 0 : 1)
                        .opacity(isActive ? 0 : 0.35)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    /// Live-Statuszeile des Ziel-Systems. Liest direkt aus dem Store, ist
    /// also nach jedem Tap sofort aktuell — das ist der eigentliche
    /// Verifikations-Punkt für Phase 1.
    @ViewBuilder
    private var devGoalStatusBox: some View {
        let rhythm = goalStore.rhythmProgress
        VStack(alignment: .leading, spacing: 4) {
            if goalStore.plan == nil {
                Text("Kein Ziel gesetzt")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text("Woche: \(rhythm.practicedDays)/\(rhythm.targetDays) Tage")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .monospacedDigit()
                    if rhythm.isReached {
                        Text("✅")
                    }
                    Spacer(minLength: 0)
                }

                // Der Balken ist hier nur Testhilfe — die echte Anzeige
                // bekommt später ihre eigene Gestaltung.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.2))
                        Capsule()
                            .fill(AppTheme.Colors.cta)
                            .frame(width: geo.size.width * rhythm.fraction)
                    }
                }
                .frame(height: 6)

                if let content = goalStore.plan?.content {
                    Text(content.displayTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    if content.isAwaitingList {
                        Text("⚠️ Noch keine Liste zugeordnet")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.error)
                    } else if let progress = goalStore.contentProgress(listStore: listStore) {
                        Text(progress.isEmpty
                             ? "Bestand leer"
                             : "\(progress.strongCount)/\(progress.totalCount) sitzen · \(Int(progress.fraction * 100)) %")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if let days = content.daysRemaining() {
                        Text(days < 0
                             ? "⏰ Termin war vor \(-days) Tag(en)"
                             : "Termin: noch \(days) Tag(e)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface.opacity(0.6))
        )
    }

    private var devResetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Klar sichtbare „Entwicklung"-Markierung als roter Capsule-Badge,
            // damit die Card nie mit einer normalen User-Einstellung
            // verwechselt werden kann.
            HStack(spacing: 8) {
                Text("Entwicklung")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.Colors.error)
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }

            // Reset-Block
            VStack(alignment: .leading, spacing: 4) {
                Text("Spielstand zurücksetzen")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("XP, Streak, Credits, Highscore, Tages-Challenge und Sammelwerte (Würmer, Wasserfloh, Algenkugel) auf Ausgangszustand. Profil und Custom-Lernlisten bleiben erhalten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                isShowingDevResetAlert = true
            } label: {
                Text("Jetzt zurücksetzen")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(AppTheme.Colors.error)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.vertical, 4)

            // Spiele-Stepper (überschreibt den aktuellen Credit-Stand)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Spiele manuell setzen")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Text("\(devSpiele)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.cta)
                        .monospacedDigit()
                }
                // Segmentierter Picker 0…5 — direkte Auswahl ohne lange
                // Stepper-Bedienung.
                Picker("Spiele", selection: $devSpiele) {
                    ForEach(0...5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: devSpiele) { _, newValue in
                    applyDevSetGames(newValue)
                }
                Text("Überschreibt den aktuellen Credit-Stand direkt. Für UI-Tests ohne Lernsession.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            // XP-Setter (setzt XP auf vordefinierte Werte — triggert
            // automatisch Level-Neuberechnung, weil Level aus XP abgeleitet
            // wird).
            VStack(alignment: .leading, spacing: 8) {
                Text("XP manuell setzen")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    ForEach([0, 100, 500, 1000, 2500, 5000], id: \.self) { xp in
                        Button {
                            applyDevSetXP(xp)
                        } label: {
                            Text("\(xp)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AppTheme.Colors.secondarySurface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Setzt XP auf den Zielwert. Level und Level-Up-Credits werden neu berechnet.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            // **Ziel-System (2026-08-05)** — Verifikations-Block, solange
            // die Onboarding-Screens noch nicht stehen.
            //
            // Zeigt den Zustand **direkt in der Card** statt nur in der
            // Konsole: Beim Testen am echten Gerät ist der Xcode-Log
            // unpraktisch, und ein Button ohne sichtbare Reaktion lässt
            // einen im Unklaren, ob überhaupt etwas passiert ist.
            // Aktive Buttons sind eingefärbt, darunter läuft eine
            // Live-Statuszeile mit.
            VStack(alignment: .leading, spacing: 8) {
                Text("Ziel-System testen")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                devGoalStatusBox

                HStack(spacing: 6) {
                    devGoalButton(
                        "Ziel: 3 Tage",
                        isActive: goalStore.plan != nil && goalStore.plan?.content == nil
                    ) {
                        LearningGoalStore.shared.debugSeedGoal(weeklyTargetDays: 3)
                    }
                    devGoalButton(
                        "+ Schulaufgabe",
                        isActive: goalStore.plan?.content?.occasion == .exam
                    ) {
                        LearningGoalStore.shared.debugSeedGoal(
                            weeklyTargetDays: 3,
                            occasion: .exam,
                            listIDs: [listStore.selectedListID],
                            deadlineInDays: 5
                        )
                    }
                }

                HStack(spacing: 6) {
                    devGoalButton("+1 Tag geübt") {
                        LearningGoalStore.shared.debugAddPracticedDays(1)
                    }
                    devGoalButton("Ziel löschen") {
                        LearningGoalStore.shared.reset()
                    }
                }

                Text("„+ Schulaufgabe\" hängt das Inhaltsziel an die aktuell ausgewählte Liste mit Termin in 5 Tagen. Details zusätzlich in der Konsole (Filter „🎯\").")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCardBackground(tint: AppTheme.Colors.developerAccent)
        .alert("Spielstand zurücksetzen?", isPresented: $isShowingDevResetAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Zurücksetzen", role: .destructive) {
                DebugResetService.resetGameState()
                devSpiele = 0  // UI-Stepper auch zurück
            }
        } message: {
            Text("Setzt XP, Streak, Credits, Highscore und Sammelwerte zurück. Profil und Custom-Lernlisten bleiben erhalten.")
        }
        .onAppear {
            // Stepper spiegelt beim Öffnen den echten Stand wider.
            devSpiele = min(5, max(0, ProgressStore.shared.progress.arcadeCredits))
        }
    }

    /// Schreibt den Stepper-Wert direkt in den ProgressStore +
    /// @AppStorage-Key. Klammert auf [0, 5].
    private func applyDevSetGames(_ count: Int) {
        let clamped = max(0, min(5, count))
        ProgressStore.shared.mutate { $0.arcadeCredits = clamped }
        UserDefaults.standard.set(clamped, forKey: appArcadeCreditsKey)
    }

    /// Setzt die XP-Summe direkt — Level ergibt sich daraus automatisch
    /// (`ProgressSnapshot.level` ist computed aus `totalXP`). Reader
    /// (HomeView, GameHub, SessionSummary) aktualisieren beim nächsten
    /// Re-Render.
    private func applyDevSetXP(_ xp: Int) {
        let clamped = max(0, xp)
        ProgressStore.shared.mutate { p in
            p.totalXP = clamped
        }
    }

    #endif

    /// **Testmodus · Arcade** (in allen Builds sichtbar): stellt Flags
    /// in UserDefaults, die der `ElumiArcadeGameView` beim nächsten
    /// `startGame()` konsumiert. Damit kannst du gezielt Power-Ups
    /// oder Ambient-Events im Arcade testen, ohne auf Random-Spawns
    /// zu warten.
    ///
    /// Vorsicht-Markierung über den blaugrauen Badge — Nutzer sehen,
    /// dass das eine Test-/Experiment-Funktion ist, nicht eine
    /// normale Einstellung. Kein Reset-Risiko (nur kosmetische
    /// In-Game-Effekte).
    // **Stufe 6 Schritt 4 (2026-04-29)**: `iconStyleCard` (Icon-Set-A/B-
    // Toggle) entfernt. Set A wurde aus dem Asset-Catalog gelöscht, der
    // Resolver ist weg, das Toggle hatte keine Wirkung mehr. Verwaister
    // UserDefaults-Key `appIconSet` bleibt auf existierenden Geräten —
    // harmlos, kein Migration-Pfad nötig (Backlog: bei nächstem ohnehin
    // notwendigen Migration-Pfad mit-aufräumen).

    private var testModusArcadeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                Text("Testmodus")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(hex: "#6B8FA3"))
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text("Spiel-Events ausprobieren")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Wähle, welches Event beim nächsten Spielstart direkt erscheinen soll. Für Tester und Neugierige. Mehrere gleichzeitig möglich.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                testModusQueueButton(
                    label: "Schutz-Bubble beim Start",
                    icon: "shield.lefthalf.filled",
                    tint: Color(hex: "#8FD3FF"),
                    key: appArcadeTestModusQueueShieldBubbleKey
                )
                testModusQueueButton(
                    label: "Sauger beim Start",
                    icon: "tornado",
                    tint: Color(hex: "#A78BFA"),
                    key: appArcadeTestModusQueueVacuumKey
                )
                testModusQueueButton(
                    label: "Fisch-Schwarm beim Start",
                    icon: "fish.fill",
                    tint: Color(hex: "#60A5FA"),
                    key: appArcadeTestModusQueueAmbientFishKey
                )
                testModusQueueButton(
                    label: "Hai beim Start",
                    icon: "fish",
                    tint: Color(hex: "#6B8FA3"),
                    key: appArcadeTestModusQueueAmbientSharkKey
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCardBackground(tint: AppTheme.Colors.developerAccent)
    }

    /// Toggle-Button für den Testmodus: persistiert den Flag in
    /// UserDefaults, invertiert bei Tap. Queue-System, damit der User
    /// seinen Wunsch VOR dem Arcade-Öffnen setzen kann — die Runtime
    /// konsumiert dann beim Game-Start.
    private func testModusQueueButton(
        label: String,
        icon: String,
        tint: Color,
        key: String
    ) -> some View {
        let isQueued = UserDefaults.standard.bool(forKey: key)
        return Button {
            UserDefaults.standard.set(!isQueued, forKey: key)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text(isQueued ? "Bereit" : "Aus")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isQueued ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
                Image(systemName: isQueued ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isQueued ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Testmodus-UserDefaults-Keys (Release-sichtbar)

/// Keys für die Testmodus-Arcade-Queue. Früher unter `elumi.debug.*`
/// und DEBUG-only — jetzt unter `elumi.testmode.*` und in allen
/// Builds verfügbar. Alte DEBUG-Keys werden ignoriert.
let appArcadeTestModusQueueShieldBubbleKey = "elumi.testmode.arcade.queue.shieldBubble"
let appArcadeTestModusQueueVacuumKey = "elumi.testmode.arcade.queue.vacuum"
let appArcadeTestModusQueueAmbientFishKey = "elumi.testmode.arcade.queue.ambient.fish"
let appArcadeTestModusQueueAmbientSharkKey = "elumi.testmode.arcade.queue.ambient.shark"

/// Sheet mit den Arcade-Spielregeln — kindgerecht erklärt mit echten
/// Icons aus dem Spiel. Aufgebaut als mehrere thematische Sektionen,
/// damit Kinder und Jugendliche alles einmal in Ruhe nachlesen
/// können. Reihenfolge orientiert sich am Spielfluss:
///   1. Was ist das Spiel?
///   2. Wie bewege ich Elumi?
///   3. Futter
///   4. Leben
///   5. Vorsicht (falsche Freunde, Qualle)
///   6. Power-Ups (Helfer)
///   7. Events (Hai, Fisch, Querschläger)
///   8. Runden + Bonus-Runden
///   9. Tipps
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
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

                    // ─────────────── Worum geht's? ───────────────
                    section(title: "Worum geht's?") {
                        bodyText("""
                            Elumi ist ein kleines Wesen, das im Wasser \
                            schwimmt. Es hat Hunger! Deine Aufgabe: \
                            fange leckeres Futter für Elumi und pass auf, \
                            dass du ihm nicht die falschen Sachen gibst.
                            """)
                    }

                    // ─────────────── Wie bewege ich Elumi? ───────────────
                    section(title: "Wie bewege ich Elumi?") {
                        bodyText("""
                            Halte den Finger auf dem Bildschirm und ziehe \
                            nach links oder rechts. Elumi folgt deinem \
                            Finger. Je ruhiger du bewegst, desto leichter \
                            fängst du alles.
                            """)
                    }

                    // ─────────────── Futter ───────────────
                    section(title: "Was kann Elumi fressen?") {
                        ruleRow(
                            leadingIcons: { ElumiSnackIcon(.wuermchen, size: 20) },
                            text: "Würmchen — 10 Punkte"
                        )
                        ruleRow(
                            leadingIcons: { ElumiSnackIcon(.wasserfloh, size: 22) },
                            text: "Wasserfloh — 14 Punkte"
                        )
                        ruleRow(
                            leadingIcons: { ElumiSnackIcon(.algenkugel, size: 20) },
                            text: "Algenkugel — 18 Punkte"
                        )
                        bodyText("Fängst du 3 oder mehr schnell hintereinander? Dann gibt's extra **Combo-Punkte**!")
                    }

                    // ─────────────── Leben ───────────────
                    section(title: "Deine Leben") {
                        HStack(spacing: 6) {
                            ForEach(0..<4, id: \.self) { _ in
                                ArcadeElumiAvatar(size: 22, withShadow: false)
                            }
                            Text("= 4 Leben zum Start")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        bodyText("""
                            Jedes Mal, wenn du ein Leben verlierst, \
                            verschwindet ein Elumi oben am Bildschirm. \
                            Alle 4 weg? Spiel vorbei — aber du kannst \
                            sofort nochmal starten.
                            """)
                        bulletText("Futter verpasst → 1 Leben weg")
                        bulletText("Einen Elumi-Freund versehentlich gefressen → 1 Leben weg")
                        bulletText("Von einer Quallen-Tentakel getroffen → 1 Leben weg")
                    }

                    // ─────────────── Vorsicht: falsche Freunde ───────────────
                    section(title: "Vorsicht: Elumi-Freunde!") {
                        ruleRow(
                            leadingIcons: { ArcadeHazardElumiAvatar(size: 26) },
                            text: "Das sind Elumi-Freunde — bitte nicht fressen!"
                        )
                        bodyText("""
                            Elumi-Freunde sehen fast aus wie Elumi selbst, \
                            haben aber ein kleines Herz-Zeichen. Die darfst \
                            du nicht essen! Ein Freund kostet dich 1 Leben.
                            """)
                    }

                    // ─────────────── Power-Ups ───────────────
                    section(title: "Power-Ups — deine Helfer") {
                        bodyText("Ab und zu tauchen besondere Objekte auf. Fange sie — sie helfen dir!")

                        ruleRow(
                            leadingIcons: { ArcadeSuctionIconStandalone(size: 28) },
                            text: "Saugglocke: saugt Futter zu dir heran"
                        )
                        bodyText("Der Sauger setzt sich auf Elumis Kopf und zieht für ein paar Sekunden alles Futter magisch an.")

                        ruleRow(
                            leadingIcons: { ArcadeSlowMotionIconStandalone(size: 28) },
                            text: "Zeitlupe-Trank: alles wird langsamer (5 Sek.)"
                        )

                        ruleRow(
                            leadingIcons: { powerUpColorDot(color: Color(hex: "#FBBF24")) },
                            text: "Bonus-Blase: doppelte Punkte (5 Sek.)"
                        )

                        ruleRow(
                            leadingIcons: { powerUpColorDot(color: Color(hex: "#8FD3FF")) },
                            text: "Schutz-Bubble: schützt dich vor Treffern"
                        )
                        bodyText("""
                            Die blaue Seifenblase legt sich für ca. 6,5 \
                            Sekunden um dich. Du kannst weiter Futter \
                            sammeln, aber Gefahren prallen an der Bubble \
                            ab — kein Leben weg!
                            """)
                    }

                    // ─────────────── Querschläger + Qualle ───────────────
                    section(title: "Vorsicht: schwieriges Futter") {
                        bulletText("Ab Runde 3: **Querschläger** — Futter fliegt im Zickzack statt gerade. Schwerer zu fangen, aber es lohnt sich!")
                        bulletText("Ab Runde 3: **Quallen** — große Tiere, die schräg durchs Bild schwimmen. Ihre Tentakel fallen runter — weg von denen, sonst gibt's Schaden!")
                    }

                    // ─────────────── Ambient-Events ───────────────
                    section(title: "Hai und Fisch-Schwarm") {
                        bodyText("""
                            Manchmal schwimmt ein Hai oder ein Schwarm \
                            Fische durchs Bild. Keine Angst — die tun dir \
                            nichts. Sie sind nur zum Schauen, damit das \
                            Meer lebendig wirkt.
                            """)
                        bulletText("Der Hai kommt höchstens einmal pro Runde.")
                        bulletText("Er kann nicht berührt werden und macht kein Leben weg.")
                    }

                    // ─────────────── Runden ───────────────
                    section(title: "Runden schaffen") {
                        bodyText("""
                            Du brauchst 12 Futter pro Runde, um sie zu \
                            schaffen. Danach geht's in die nächste Runde — \
                            die wird ein kleines bisschen schwerer, aber \
                            du wirst auch besser.
                            """)
                        bulletText("Runde 3 und jede 3. danach: **Bonus-Runde!**")
                    }

                    // ─────────────── Bonus-Runden ───────────────
                    section(title: "Bonus-Runden") {
                        bodyText("""
                            Alle 3 Runden (nach Runde 3, 6, 9 …) gibt's \
                            eine kurze Bonus-Runde. Fange dort große Fische \
                            quer durchs Bild — je mehr du fängst, desto \
                            mehr Extra-Punkte. Und wer 10 Fische schafft, \
                            bekommt sogar ein extra Leben!
                            """)
                    }

                    // ─────────────── Spiele verdienen ───────────────
                    section(title: "Wie bekomme ich neue Spiele?") {
                        bodyText("""
                            Jedes Spiel verbraucht 1 Credit. Neue Credits \
                            verdienst du durchs Lernen:
                            """)
                        bulletText("Tagesaufgabe erledigen → +1 Spiel")
                        bulletText("250 XP gesammelt → +1 Spiel")
                        bulletText("Level aufsteigen → +3 Spiele")
                        bulletText("Streak halten (3/7/14/30 Tage) → Bonus-Spiele")
                    }

                    // ─────────────── Tipps ───────────────
                    section(title: "Tipps für mehr Punkte") {
                        bulletText("**Ruhe bewahren** — nicht hektisch wedeln. Elumi folgt sanft.")
                        bulletText("**Combos**: 3 Futter hintereinander → Extra-Punkte!")
                        bulletText("**Power-Ups nutzen**: Sauger + Bonus-Blase = doppelter Punkteregen.")
                        bulletText("**Freunde erkennen**: beim kleinen Herz-Zeichen ausweichen.")
                        bulletText("**Hai/Fisch genießen**: nur gucken, nicht jagen — die sind zur Deko da.")
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

    // MARK: - Layout-Bausteine

    /// Thematische Sektion mit Überschrift + Content. Gibt jeder
    /// Regel-Kategorie eine klare Trennung.
    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(sectionStyle.accent)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    /// Ein-Zeilen-Regel mit Icon vorne, Text hinten.
    @ViewBuilder
    private func ruleRow<Leading: View>(
        @ViewBuilder leadingIcons: () -> Leading,
        text: String
    ) -> some View {
        HStack(spacing: 10) {
            leadingIcons()
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fließtext im Regel-Sheet — leicht weicherer Foreground.
    @ViewBuilder
    private func bodyText(_ markdown: String) -> some View {
        Text(.init(markdown))
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bulletpoint-Zeile mit kleinem Dot vorne.
    @ViewBuilder
    private func bulletText(_ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(sectionStyle.accent)
            Text(.init(markdown))
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Mini-Farbkreis für Power-Ups, die kein eigenes Standalone-Icon
    /// haben (Schutz-Bubble, Bonus-Blase).
    @ViewBuilder
    private func powerUpColorDot(color: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.85), color.opacity(0.35)],
                    center: .init(x: 0.35, y: 0.30),
                    startRadius: 2,
                    endRadius: 14
                )
            )
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1))
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
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text("\(stats.total.formatted(.number.locale(Locale(identifier: "de_DE"))))")
                    .font(.system(size: 19, weight: .black, design: .rounded))
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
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            Text(entry.count.formatted(.number.locale(Locale(identifier: "de_DE"))))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
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

