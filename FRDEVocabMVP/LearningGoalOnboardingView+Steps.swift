import SwiftUI

// LearningGoalOnboardingView+Steps.swift
// Die Frage-Schritte des Ziel-Onboardings — ausgelagert aus
// `LearningGoalOnboardingView.swift`, damit die Haupt-Datei bei
// Flow-Logik/Timing bleibt und diese bei reinem Screen-Aufbau.
//
// **2026-08-05, Typografie- & Interaktions-Pass (User-Spec nach
// Gerätetest)** — deutlich größere Schriften (näher an der
// YAZIO-Referenz), verspielter Bounce beim Antippen von Karten
// (`OnboardingCardBounceStyle`, definiert in der Haupt-Datei), und ein
// Layout-Bug behoben: Auswahl-Karten änderten beim Antippen sichtbar
// ihre Höhe.

extension LearningGoalOnboardingView {

    // MARK: - 2. Anlass

    /// **2026-08-06, Layout-Fix** — Kopf und CTA fest, nur die Karten
    /// scrollen (siehe Doc-Kommentar in `LearningGoalOnboardingView.
    /// body`). Grund: dieser Screen hat 5 Karten, der Rhythmus-Screen
    /// danach nur 4 — im alten, frei mitscrollenden Layout saß "Weiter"
    /// deshalb spürbar tiefer als "Passt!" auf dem nächsten Screen
    /// (User-Report: "dann kann man den Finger drauf lassen oder weiß,
    /// wo's ist"). Mit fester Position ist das für beide identisch.
    var occasionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.md) {
                compactMascot()
                questionTitle("Was steht bei dir an?")
            }
            .padding(.bottom, AppTheme.Spacing.lg)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(LearningOccasion.allCases) { candidate in
                        occasionCard(candidate)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.md)
            }

            primaryButton("Weiter", isEnabled: occasion != nil) { advance() }
                .padding(.top, AppTheme.Spacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    private func occasionCard(_ candidate: LearningOccasion) -> some View {
        let isSelected = occasion == candidate
        return Button {
            occasion = candidate
            selectionTick += 1
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(candidate.emoji)
                    .font(.system(size: 34))
                    .frame(width: 46)

                Text(candidate.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // **2026-08-05, Bug-Fix** — vorher wurde das Häkchen nur
                // bei Auswahl EINGEFÜGT, was der Text-Spalte links Platz
                // wegnahm und bei längeren Titeln ("Meine
                // Wackelkandidaten wegräumen") eine zusätzliche Zeile
                // erzwang — die Karte wurde beim Antippen sichtbar
                // höher (User-Report). Jetzt ist der Platz IMMER
                // reserviert, nur die Opazität wechselt — die
                // verfügbare Breite für den Titel bleibt konstant,
                // gleich ob ausgewählt oder nicht.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(sectionAccent.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .stroke(isSelected ? sectionAccent.accent : Color.clear, lineWidth: 2)
            )
            .onboardingSelectionFlash(
                trigger: isSelected ? selectionTick : 0,
                tint: sectionAccent.accent,
                cornerRadius: AppTheme.Radius.xl
            )
        }
        .buttonStyle(OnboardingCardBounceStyle())
    }

    // MARK: - 3. Termin

    var deadlineStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            questionTitle("Wann ist deine \(occasion?.title.lowercased() ?? "Schulaufgabe")?")

            Text("Kein Stress, du kannst das später jederzeit ändern.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            DatePicker(
                "",
                selection: $deadline,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(sectionAccent.accent)
            .frame(maxWidth: .infinity)

            primaryButton("Alles klar") { advance() }
        }
    }

    // MARK: - 4. Rhythmus

    /// **2026-08-06, Layout-Fix** — siehe Doc-Kommentar an `occasionStep`,
    /// gleicher Grund: feste Kopf-/CTA-Position, unabhängig von der
    /// Kartenzahl (hier 4 statt 5).
    var rhythmStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.md) {
                compactMascot()
                questionTitle("Wie oft schaffst du das?")
            }
            .padding(.bottom, AppTheme.Spacing.lg)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(LearningGoalPlan.weeklyTargetOptions, id: \.self) { days in
                        rhythmCard(days)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.md)
            }

            primaryButton("Passt!") { advance() }
                .padding(.top, AppTheme.Spacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    private func rhythmCard(_ days: Int) -> some View {
        let isSelected = weeklyTarget == days
        return Button {
            weeklyTarget = days
            selectionTick += 1
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Text("\(days)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? accentGreen : AppTheme.Colors.textPrimary)
                    .frame(width: 38)
                    .monospacedDigit()

                Text(days == 1 ? "Tag die Woche" : "Tage die Woche")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                // **2026-08-05** — Label in Grün (User-Spec: "auch die
                // Worte easy, ambitioniert und so weiter in der Farbe,
                // mit einem Grün, das man gut lesen kann"). Emerald ist
                // auf der dunklen Card kontraststark genug.
                Text(LearningGoalPlan.weeklyTargetLabel(for: days))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(accentGreen)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .stroke(isSelected ? accentGreen : Color.clear, lineWidth: 2)
            )
            .onboardingSelectionFlash(
                trigger: isSelected ? selectionTick : 0,
                tint: accentGreen,
                cornerRadius: AppTheme.Radius.xl
            )
        }
        .buttonStyle(OnboardingCardBounceStyle())
    }

    /// Grüner Onboarding-Akzent (Emerald, bereits im Nomen-Modul im
    /// Einsatz — keine neue Farbe). Trägt den Rhythmus-Schritt und
    /// hebt im Modul-Screen den entlastenden Hinweis hervor.
    private var accentGreen: Color { AppTheme.Colors.moduleNomen }

    // MARK: - 5. Vorschau

    var previewStep: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer(minLength: AppTheme.Spacing.xl)

            mascot

            VStack(spacing: 12) {
                // **2026-08-05** — Einflug-Pop (User-Spec: "kann man das
                // kurz animieren? So, wow, dass es groß und klein
                // wird."). Bewusst EIN federnder Auftritt beim
                // Erscheinen, keine Dauerschleife: Ein permanent
                // pulsierender Titel würde beim Lesen stören — und
                // Dauer-Animationen sind in diesem Projekt schon einmal
                // hängengeblieben (siehe `ListeningPulseModifier`).
                Text(previewHeadline)
                    .font(.system(size: previewIsWow ? 30 : 26, weight: .black, design: .rounded))
                    .foregroundStyle(previewIsWow ? AppTheme.Colors.cta : AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(previewHeadlineScale)
                    .onAppear { runPreviewHeadlineAnimation() }

                Text(previewSubtitle)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }

            Spacer(minLength: AppTheme.Spacing.xl)

            // **2026-08-05** — "Weiter" → "Ich bin bereit!" (User-Spec).
            primaryButton("Ich bin bereit!") { advance() }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 440)
    }

    /// Ab 5 Tagen gilt die Wahl als „ambitioniert" — der Titel wird
    /// größer, gelb und bekommt den kräftigeren Auftritt.
    var previewIsWow: Bool { weeklyTarget >= 5 }

    /// **2026-08-05, dritte Runde — Zittern behoben.**
    ///
    /// Vorher liefen drei Animationen hintereinander (klein → über die
    /// Zielgröße → darunter → auf 1.0), jede per `DispatchQueue`
    /// gestartet. Zwei davon waren Federn. Eine Feder, die mitten im
    /// Flug von der nächsten Animation überschrieben wird, hat an dieser
    /// Stelle einen Geschwindigkeitssprung — genau das war das Zittern,
    /// das der Nutzer gesehen hat ("das ist unruhig, wenn's kleiner und
    /// wieder größer wird").
    ///
    /// Jetzt macht das **eine einzige, schwach gedämpfte Feder**. Das
    /// Überschwingen und das Zurückschwingen entstehen von selbst aus
    /// der Physik, sind dadurch stetig und damit glatt. Nebenbei fällt
    /// die ganze Timing-Kette weg.
    ///
    /// `dampingFraction` steuert, wie stark es nachschwingt: 0.42 gibt
    /// ein deutliches Wippen für die WOW-Fassung, 0.62 ein dezenteres
    /// für die normalen Werte.
    private func runPreviewHeadlineAnimation() {
        previewHeadlineScale = previewIsWow ? 0.55 : 0.85

        withAnimation(
            .spring(
                response: previewIsWow ? 0.55 : 0.45,
                dampingFraction: previewIsWow ? 0.42 : 0.62
            )
            .delay(0.05)
        ) {
            previewHeadlineScale = 1.0
        }
    }

    /// **2026-08-05** — Headline reagiert jetzt auf die gewählte Menge
    /// (User-Spec: "bei 7 Tage die Woche muss danach ein WOW kommen").
    /// Vorher stand bei jeder Wahl derselbe Satz, was die ambitionierte
    /// Entscheidung entwertete.
    private var previewHeadline: String {
        switch weeklyTarget {
        case 7:      return "Wow, 7 Tage die Woche!"
        case 5...6:  return "Stark, \(weeklyTarget) Tage die Woche!"
        default:     return "\(weeklyTarget) Tage die Woche. Das packst du!"
        }
    }

    /// Bewusst ohne konkrete Vokabelzahl: die Liste steht erst später
    /// fest. Motivierender Ausblick statt Statistik, analog zur
    /// YAZIO-Referenz — aber Elumi-Maskottchen statt Graph.
    ///
    /// **2026-08-05** — zweigeteilt: Bei hohem Wochenziel geht die
    /// Anerkennung der Menge vor (User-Spec "so geht's richtig
    /// vorwärts"), erst darunter greift der anlassbezogene Text.
    /// Formulierungen bewusst in Schülersprache — "dein Kopf wird
    /// freier" war Erwachsenensprech und ist raus.
    private var previewSubtitle: String {
        if weeklyTarget >= 5 {
            return "So geht's richtig vorwärts! Damit ziehst du dein Ziel locker durch."
        }
        switch occasion {
        case .exam:
            return "Bis zu deiner Schulaufgabe übst du regelmäßig und wirst von Runde zu Runde sicherer."
        case .chapter:
            return "So hast du dein Kapitel bald drauf. Schritt für Schritt, ganz ohne Stress am Ende."
        case .notebook:
            return "So bleiben deine Vokabeln hängen und du wirst immer besser."
        case .shakyItems:
            return "So kriegst du deine Wackelkandidaten weg, eins nach dem anderen."
        case .stayOnTrack, .none:
            return "Kleine Runden, große Wirkung. Ich bin schon gespannt, wie weit wir kommen!"
        }
    }

    // MARK: - 6. Vokabeln-Frage (Ja/Nein)

    /// **2026-08-05, Zwei-Wege-Split (User-Spec)** — ersetzt den
    /// früheren Einzelschritt, der Listen-Auswahl, Scan-Button und
    /// "Später" gleichzeitig auf einem Screen zeigte. Jetzt erst eine
    /// reine Ja/Nein-Entscheidung, danach führt genau EIN Weg weiter
    /// (`selectListsStep` oder `scanPromptStep`) — YAZIO-Stil
    /// ("Stimmt das noch? Ja/Nein").
    var hasVocabQuestionStep: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer(minLength: AppTheme.Spacing.lg)

            compactMascot()

            questionTitle("Hast du die Vokabeln schon in der App?")
                .multilineTextAlignment(.center)

            Text("Egal ob eigene Liste oder schon gescannt. Hauptsache, sie sind schon da.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                yesNoCard(title: "Ja", emoji: "👍", isSelected: hasVocabAlready == true) {
                    hasVocabAlready = true
                    selectionTick += 1
                }
                yesNoCard(title: "Nein", emoji: "👎", isSelected: hasVocabAlready == false) {
                    hasVocabAlready = false
                    selectionTick += 1
                }
            }

            Spacer(minLength: AppTheme.Spacing.lg)

            primaryButton("Weiter", isEnabled: hasVocabAlready != nil) { advance() }
        }
        .frame(maxWidth: .infinity)
    }

    private func yesNoCard(title: String, emoji: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 40))
                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .stroke(isSelected ? sectionAccent.accent : Color.clear, lineWidth: 2)
            )
            .onboardingSelectionFlash(
                trigger: isSelected ? selectionTick : 0,
                tint: sectionAccent.accent,
                cornerRadius: AppTheme.Radius.xl
            )
        }
        .buttonStyle(OnboardingCardBounceStyle())
    }

    // MARK: - 7a. Listen wählen (bei "Ja")

    /// **2026-08-06** — Nur bei „Einfach dranbleiben" gedacht: bei den
    /// anderen Anlässen (Schulaufgabe/Kapitel/Vokabeln üben) hat der
    /// Nutzer gerade "Ja, hab ich schon" beantwortet — dort wäre eine
    /// automatische Vorauswahl unpassend, er soll aktiv wählen. Ohne
    /// konkreten Anlass ist der Grundwortschatz A1 (der App-weite
    /// Standard, `VocabularyListSelectionResolver.
    /// defaultGlobalSelectionListID`) eine sinnvolle Vorbelegung — der
    /// Nutzer sieht sie jetzt und kann sie bewusst ändern, statt dass
    /// sie unsichtbar im Hintergrund greift (User-Report).
    private func preselectDefaultListIfNeeded() {
        guard occasion == .stayOnTrack, selectedListIDs.isEmpty else { return }
        selectedListIDs.insert(VocabularyListSelectionResolver.defaultGlobalSelectionListID)
    }

    /// **2026-08-06, Layout-Fix** — anders als die übrigen Schritte NICHT
    /// mehr in die gemeinsame äußere `ScrollView` eingehängt (siehe
    /// `LearningGoalOnboardingView.body`). Grund: Mit den zwei
    /// aufklappbaren Gruppen kann der Inhalt hier lang werden — User-
    /// Report: nach dem Ankreuzen des Grundwortschatz musste man erst
    /// ganz nach unten scrollen, um den "Fertig"-Button überhaupt zu
    /// erreichen. Jetzt scrollt **nur** die Listen-Fläche in der Mitte,
    /// Kopf und Button stehen fest.
    var selectListsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.md) {
                compactMascot()
                // **2026-08-06** — „Listen" → „Lernlisten" (User-Spec:
                // Wording-Konstanz mit `ListPickerSheet`/
                // `GlobalListPickerSheet`, die denselben Satz benutzen).
                questionTitle("Wähle eine oder mehrere Lernlisten")
            }
            .padding(.bottom, AppTheme.Spacing.md)

            // **2026-08-06** — nur beim reinen Rhythmusziel: die anderen
            // Anlässe fragen vorher schon "Hast du die Vokabeln schon?",
            // hier fehlt dieser Kontext, deshalb der kurze Hinweis, warum
            // schon etwas angehakt ist. Grün statt der sonstigen Pink-
            // Töne dieses Schritts (User-Spec: "damit wir da 'n bisschen
            // Unterschied haben") — dieselbe Akzentfarbe wie der
            // Rhythmus-Schritt (`stepAccentColor`), keine neu erfundene.
            if occasion == .stayOnTrack {
                Text("Wir haben den Grundwortschatz schon für dich angehakt. Passt das, oder willst du etwas anderes üben?")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.moduleNomen)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, AppTheme.Spacing.md)
            }

            if ownLists.isEmpty && builtInLists.isEmpty {
                // Sicherheitsnetz: sollte selten vorkommen (Nutzer hat
                // "Ja" gesagt, aber tatsächlich keine eigene Liste) —
                // bietet trotzdem einen Weg weiter, statt in einer
                // leeren Auswahl steckenzubleiben.
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hier ist noch nichts, aber kein Problem.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    scanLinkButton
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if !ownLists.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                selectListsSectionHeader("Meine eigenen Lernlisten")
                                ForEach(ownLists) { list in
                                    listRow(list)
                                }
                            }
                        }

                        // **2026-08-06** — bisher zeigte dieser Schritt NUR
                        // eigene (gescannte/angelegte) Listen. User-Report:
                        // bei "Ja, hab ich schon" wollte er den Grundwortschatz
                        // der App auswählen können, nicht nur seine eigenen
                        // Scans. Fertige Listen jetzt als eigene Sektion.
                        //
                        // **2026-08-06, Nachschlag** — in "Nach Lernstand" und
                        // "Nach Themen" aufgeteilt, beide aufklappbar (User-
                        // Spec: "sonst ist die Liste so ewig lang, wenn man
                        // sie gar nicht braucht"). Gleiches Zusammenklapp-
                        // Prinzip wie die Kategorie-Karten in "Meine Listen".
                        if !StandardVocabularyLoader.levelLists.isEmpty {
                            collapsibleListGroup(
                                title: "Nach Lernstand",
                                lists: StandardVocabularyLoader.levelLists,
                                isExpanded: $isLevelGroupExpanded
                            )
                        }
                        if !StandardVocabularyLoader.topicLists.isEmpty {
                            collapsibleListGroup(
                                title: "Nach Themen",
                                lists: StandardVocabularyLoader.topicLists,
                                isExpanded: $isTopicGroupExpanded
                            )
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.md)
                }
            }

            primaryButton("Fertig", isEnabled: !selectedListIDs.isEmpty) { advance() }
                .padding(.top, AppTheme.Spacing.md)
        }
        .frame(maxHeight: .infinity)
        .onAppear { preselectDefaultListIfNeeded() }
    }

    private func selectListsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.Colors.textSecondary)
    }

    /// Auf-/zuklappbare Gruppe innerhalb der Lernlisten-Auswahl. Eine
    /// vorausgewählte Liste hält ihre Gruppe automatisch offen — sonst
    /// könnte der Grundwortschatz-Vorschlag bei "Einfach dranbleiben"
    /// hinter einer eingeklappten Sektion verschwinden.
    private func collapsibleListGroup(
        title: String,
        lists: [VocabularyList],
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    selectListsSectionHeader(title)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(spacing: 10) {
                    ForEach(lists) { list in
                        listRow(list)
                    }
                }
            }
        }
        .onAppear {
            if lists.contains(where: { selectedListIDs.contains($0.id) }) {
                isExpanded.wrappedValue = true
            }
        }
    }

    /// Eigene, nutzererstellte Listen.
    private var ownLists: [VocabularyList] {
        listStore.customLists.filter { !$0.isBuiltIn }
    }

    /// Fertige Listen der App insgesamt — nur noch für die
    /// Leer-Zustand-Prüfung gebraucht, das Rendering selbst läuft über
    /// `collapsibleListGroup` mit `levelLists`/`topicLists` getrennt.
    private var builtInLists: [VocabularyList] {
        StandardVocabularyLoader.levelLists + StandardVocabularyLoader.topicLists
    }

    private func listRow(_ list: VocabularyList) -> some View {
        let isSelected = selectedListIDs.contains(list.id)
        return Button {
            if isSelected {
                selectedListIDs.remove(list.id)
            } else {
                selectedListIDs.insert(list.id)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? sectionAccent.accent : AppTheme.Colors.textSecondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("\(list.items.count) Vokabeln")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(isSelected ? sectionAccent.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(OnboardingCardBounceStyle())
    }

    // MARK: - 7b. Scan-Einstieg (bei "Nein")

    /// **2026-08-05** — eigener, dedizierter Screen statt eines
    /// Buttons zwischen anderen Optionen (User-Spec: "Lass uns deine
    /// Vokabeln jetzt scannen und dann führst du den so durch").
    var scanPromptStep: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer(minLength: AppTheme.Spacing.xl)

            mascot

            VStack(spacing: 12) {
                Text("Lass uns deine Vokabeln jetzt scannen.")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Fotografier dein Heft oder Buch. Ich mach dir in ein paar Sekunden eine Übungsliste draus.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }

            Spacer(minLength: AppTheme.Spacing.xl)

            primaryButton("Jetzt scannen") { handOffToScan() }

            Button {
                advance()
            } label: {
                Text("Später")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 460)
    }

    // MARK: - 8. Modul-Orientierung

    /// **2026-08-05** — neuer Screen kurz vor dem Abschluss (User-Spec:
    /// "Dann kannst du ja vielleicht noch eine Seite reinmachen, was
    /// Training, Quiz, Live-Chat, Daily Drop bedeuten? Weil man kommt
    /// dann in den Opening-Screen").
    ///
    /// Zweck: Der Nutzer landet gleich auf Home mit vier großen Karten,
    /// deren Namen ihm nichts sagen. Dieser Screen nimmt die Verwirrung
    /// vorweg — eine Zeile pro Modul, in derselben Reihenfolge und mit
    /// denselben Akzentfarben wie die Home-Karten, damit die Zuordnung
    /// beim Ankommen sofort klappt.
    ///
    /// Léa-Chat erscheint nur, wenn das Feature aktiv ist — sonst
    /// würden wir etwas erklären, das der Nutzer nirgends findet.
    var modulesStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.md) {
                compactMascot()
                questionTitle("Das findest du gleich bei mir")
            }

            // **2026-08-05** — mehr Luft zwischen Überschrift und Liste
            // (User-Spec: "'n bisschen mehr Abstand von unter dem
            // Header, dass Training, Quiz und Daily Drop 'n bisschen
            // weiter unten sind").
            Spacer(minLength: AppTheme.Spacing.lg)

            // **2026-08-05** — Icons sind exakt die vom Home-Screen
            // (User-Spec: "die Icons müssen exakt die Icons aus dem Main
            // Screen sein"). Emoji-Platzhalter raus; hier stehen jetzt
            // dieselben Komponenten wie in `HomeView.wideMethodCards` —
            // `graduationcap.fill` für Training, `HomeModuleIconView`
            // fürs Quiz, `DailyDropStackedCardsIcon` für den Drop.
            // Dadurch erkennt der Nutzer die Karten auf Home sofort
            // wieder; das ist der ganze Zweck dieses Screens.
            VStack(spacing: 10) {
                moduleRow(
                    title: "Training",
                    subtitle: "Karteikarten, Vokabeln und Spezial-Übungen für Französisch",
                    tint: AppTheme.Colors.moduleVocabulary
                ) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                // **2026-08-05, Faktenfehler behoben** — vorher stand
                // hier "mit Punkten und Herzen". Herzen gibt es im Quiz
                // nicht; gesammelt werden Würmchen und XP.
                moduleRow(
                    title: "Quiz",
                    subtitle: "Teste dich und sammle Würmchen und XP",
                    tint: AppTheme.Colors.moduleQuiz
                ) {
                    HomeModuleIconView(icon: .quiz, size: 38, glyphTint: .white)
                }
                if FeatureFlags.leaChatEnabled {
                    moduleRow(
                        title: "Léa-Chat",
                        subtitle: "Schreib auf Französisch mit Léa",
                        tint: AppTheme.Colors.elumiMint
                    ) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                // **2026-08-05** — konkreter formuliert: der Daily Drop
                // ist eine Slot-Maschine, an der man selbst dreht.
                // "Überraschungs-Übung" verschwieg die Interaktion.
                moduleRow(
                    title: "Daily Drop",
                    subtitle: "Einmal am Tag am Rad drehen und deine Übung erspielen",
                    tint: AppTheme.Colors.elumiPinkDeep
                ) {
                    DailyDropStackedCardsIcon(size: 36)
                }
            }

            // **2026-08-05** — größer, zentriert und in Grün (User-Spec:
            // "macht das wieder in der grünen Schrift wie vorher, dann
            // fällt das 'n bisschen besser auf"). Der Satz nimmt Druck
            // raus, deshalb soll er auffallen statt als Kleingedrucktes
            // unterzugehen.
            Text("Musst du dir nicht merken. Ich zeig dir alles, wenn du es brauchst.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(accentGreen)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.sm)

            primaryButton("Alles klar!") { advance() }
        }
    }

    /// Icon kommt als ViewBuilder herein, damit jede Zeile exakt das
    /// Home-Icon ihres Moduls rendern kann (SF-Symbol, Asset-Icon oder
    /// programmatische Illustration) statt eines Emoji-Ersatzes.
    private func moduleRow<Icon: View>(
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                // Gefüllter Akzent-Chip wie auf den Home-Karten, damit
                // die weißen Icons denselben Kontrast haben wie dort.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
                icon()
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
    }

    /// Kompakter Scan-Link fürs Sicherheitsnetz auf `selectListsStep`.
    private var scanLinkButton: some View {
        Button {
            handOffToScan()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Jetzt scannen")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.moduleScan)
        }
        .buttonStyle(OnboardingCardBounceStyle())
    }
}
