import SwiftUI

// **Codeaudit 2026-09-03, Stufe 4 (Punkt 24)** — `ElumiTabView` war eine
// Datei mit 2198 Zeilen. Sie ist entlang der bereits vorhandenen
// `MARK:`-Abschnitte aufgeteilt; verschoben wurde nur, nichts
// umgeschrieben. Hier: das Setup-Modal.
//
// Damit die Abschnitte in eigenen Dateien liegen koennen, sind die
// Mitglieder, die sie benutzen, nicht mehr `private` — dieselbe
// Entscheidung, die `TrainingView` und `FlashcardSessionStore` fuer ihre
// Extension-Dateien schon getroffen haben.

extension ElumiTabView {
    // MARK: - Setup-Modal (Sache B Stufe 2)

    /// Modal-Layer mit Dimm-Backdrop + Card. **Backdrop-Tap dismisst**
    /// (Sache B Stufe 2): da das Modal mit einem sinnvollen Default-
    /// Preselect (`Self.durationDefault` = 10) öffnet, kann der User
    /// keinen „undefined state" produzieren. Backdrop-Tap übernimmt den
    /// aktuellen Preselect — `selectedDuration` ist schon via
    /// `@AppStorage` persistiert, der Dismiss-Pfad braucht nichts
    /// zusätzlich zu schreiben (siehe `dismissSetupModal()`-Doc).
    ///
    /// Begründung der Dismissable-Decision: konsistente Modal-Semantik
    /// über Erstöffnung und Re-Edit (Stufe 3) — Forcing-Function bei
    /// einer Low-Stakes-10/15/20-Wahl wäre unnötige Reibung.
    var setupModalOverlay: some View {
        // **2026-05-06 Refactor (Pop-up-Only)** — vorher zeigte das
        // Modal Listen-Card + Zeit-Cards + „Los geht's"-CTA. Mit dem
        // Refactor:
        //   • Listen-Card raus — globale Auswahl wird transparent aus
        //     `globalSelectedListIDs` gezogen (Default: A1 Grundwortschatz
        //     via Resolver-Fallback `effectiveSelectedListIDs`).
        //   • CTA raus — Tap auf Time-Card schließt direkt (Auto-Close).
        //   • Sparkles + Subline raus — Pop-up wirkt minimaler, klar als
        //     Single-Question „Wie lange?".
        //   • Skip-X oben rechts — User kann Pop-up schließen ohne Wahl;
        //     Slot-CTA bleibt dann disabled (`canTriggerSpin`).
        ZStack(alignment: .top) {
            // **Naming-Sweep 2026-05-06** — Backdrop von 0.92 → 0.97
            // (User-Feedback „Hintergrund schimmert zu transparent
            // durch, Hero-Card und CTA sichtbar"). Quasi opak, nur
            // ein Hauch Transparenz für leichte Layering-Tiefe.
            Color.black.opacity(0.97)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSetupModal()
                }

            // **2026-05-06 Iteration 3** — Modal-Karte wieder vertikal
            // mittig (User-Feedback nach dem Hero+Wide-Layout-Refactor:
            // „Mix-Training Pop mittig vertikal"). Vorher mit
            // Top-Padding 120 in der oberen Bildschirmhälfte
            // verankert. Mit dem neuen Home-Layout (Hero-Cards →
            // Mix-Training-Card als Wide-Card → Pop-up) wirkt die
            // dead-center-Position jetzt wieder natürlich, weil die
            // Slot-Maschine erst nach Auto-Close gerendert wird.
            VStack(spacing: 18) {
                // **Bug-Fix 2026-05-06** — Back-Chevron oben links
                // ergänzt (User-Feedback „kein Chevron oben links").
                // Tap geht direkt zurück zur Home (`dismiss()` —
                // pop NavigationStack). Der bestehende Skip-X oben
                // rechts schließt nur das Modal selbst und lässt den
                // User auf dem Slot-Screen.
                HStack {
                    Button {
                        dismissSetupModal()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Zurück"))

                    Spacer(minLength: 0)

                    Button {
                        dismissSetupModal()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Schließen"))
                }

                // **Polish-Iteration 3 2026-05-06** — Headline jetzt
                // zwei-zeilig: oben kleiner Eyebrow „Trainingsmix"
                // (Modul-Kontext, Akzent-Pink), darunter die original
                // Frage „Wie lange möchtest du üben?" (User-Feedback
                // „2-zeilig, Text wie vorher und darüber Trainingsmix").
                VStack(spacing: 4) {
                    // **Naming-Sweep 2026-05-06** — „Trainingsmix" →
                    // „DAILY DROP" (Brand-Begriff systemweit).
                    // Headline „Wie lange möchtest du üben?" → „Wie
                    // lange?" (1-zeilig; der Pre-Title gibt schon
                    // den Modul-Kontext, die Headline kann dadurch
                    // kürzer werden und bricht nicht mehr um).
                    // **Naming-Sweep 2026-05-06** — beide Pop-up-
                    // Headlines +3pt (User-Feedback). „Daily Drop"
                    // 16 → 19 pt black, „Wie lange?" 22 → 25 pt
                    // black. Modal-Karte hat genug intrinsic Höhe
                    // (`.fixedSize(vertical: true)`) — wächst
                    // automatisch mit dem Text.
                    Text("Daily Drop")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(sectionStyle.accent)
                    Text("Wie viele Übungen?")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                // **Daily Drop Modul 3 (2026-05-23)** — Anzahl-Picker:
                // Kurz/Mittel/Lang (10/20/30 Übungen). Längen ohne genug
                // Material sind ausgegraut (`exerciseCountChip`); reicht es
                // nicht mal für Kurz (Material < 10/2 = 5), erscheint ein
                // Hinweis statt der Chips. Tap löst auto-close aus.
                if cachedDailyDropMaterial < materialThreshold(for: Self.exerciseCountOptions.first ?? 10) {
                    // **2026-06-09** — Statt nur zu SAGEN, wo die Auswahl
                    // liegt, führt ein Button jetzt direkt dorthin. Der
                    // Lernjahr-Zusatz entfällt, solange die Lernjahr-
                    // Auswahl per Flag versteckt ist — sonst verweist der
                    // Text auf eine UI, die es gerade nicht gibt.
                    VStack(spacing: 10) {
                        Text(
                            FeatureFlags.learningYearSelectionEnabled
                            ? "Zu wenig Material für einen Drop. Wähle mehr Lernlisten aus oder erweitere die Lernjahre."
                            : "Zu wenig Material für einen Drop. Wähle mehr Lernlisten aus."
                        )
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Button {
                            dismissSetupModal()
                            navigate(.lists(nil))
                        } label: {
                            Text("Zu Meine Lernlisten")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ForEach(Self.exerciseCountOptions, id: \.self) { count in
                                exerciseCountChip(count: count)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // **Daily Drop Modul 3 (2026-05-23)** — Material-Hinweis
                        // unter den Chips: nennt die NÄCHSTE erreichbare Schwelle
                        // (kleinste ausgegraute Länge) statt aller — eine klare,
                        // umsetzbare Zeile. Sobald sie erreicht ist, rückt der
                        // Hinweis automatisch auf die nächste Länge. Kein Hinweis
                        // wenn alle Längen verfügbar sind (`first(where:)` == nil).
                        if let nextLocked = Self.exerciseCountOptions.first(where: { cachedDailyDropMaterial < materialThreshold(for: $0) }) {
                            Text("Für \(exerciseLengthLabel(nextLocked)) brauchst du mehr Vokabeln")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            // **Layout-Fix** (Sache B Stufe 2): `.fixedSize(vertical:
            // true)` zwingt die Modal-VStack zur intrinsischen
            // Vertikal-Höhe. Sonst proposed der äußere ZStack (mit
            // dem screen-füllenden Backdrop) volle Screen-Höhe an
            // die VStack, die diese auf flexible Kinder (HStack der
            // Chips mit `minHeight: 44` und ohne `maxHeight`)
            // verteilt — Chips würden mehrere hundert Punkte hoch
            // gerendert. `.fixedSize` koppelt die VStack-Höhe an
            // die Summe der intrinsischen Kind-Höhen (~218pt) und
            // hält die Modal-Card kompakt.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#101522"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(sectionStyle.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
            // **Naming-Sweep 2026-05-06** — Pop-up wieder höher
            // im Screen verankert (User-Feedback „Daily-Drop-
            // Zeitwahl alles etwas höher"). 120pt Top-Padding zieht
            // die Modal-Karte ins obere Drittel zurück, sodass die
            // Frage-Stellung in der Daumen-Zone der Zeit-Cards
            // ergonomisch greifbar bleibt.
            .padding(.top, 120)
        }
        .sheet(isPresented: $showListPicker) {
            // **Stufe 1c (2026-04-30)** — Multi-Select-Sheet für die
            // globale Listen-Auswahl. Schreibt direkt via
            // `setGlobalSelectedListIDs(...)` (R11: Toggle-State wird
            // ignoriert) und gibt die neue Selection per `onCommit`
            // zurück, damit die Card im Setup-Modal sofort aktualisiert.
            GlobalListPickerSheet(
                allLists: listStore.allLists,
                initialSelection: globalSelectedListIDs,
                onCommit: { newSelection in
                    globalSelectedListIDs = newSelection
                },
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() }
            )
        }
    }

    /// **Listen-Auswahl-Card im Setup-Modal** (Stufe 1c, 2026-04-30 /
    /// Block 4 Restyle 2026-05-03).
    ///
    /// Zeigt die aktuelle globale Listen-Auswahl (gemeinsam genutzt mit
    /// Karteikarten/Quiz/Word Runner/Training). Tap auf die Card öffnet
    /// den `ChainListSelectionSheet` für Multi-Select-Editing.
    ///
    /// **Block 4 (2026-05-03) Restyle**: Card-Stil von der eigenen
    /// kompakten Layout-Variante (cornerRadius 12, Pencil-Pill, kleine
    /// Icon-Plate) auf das Time-Card-Pattern (cornerRadius 14,
    /// minHeight 88, Selected-State mit Modul-Akzent-Tönung) angeglichen
    /// — User-Spec „selbe Höhe, Padding, Border, Background wie
    /// Zeit-Cards". Pulsations-Hint solange noch keine Liste gewählt;
    /// stoppt bei erster Auswahl, übergibt parallel an den Zeit-Cards-
    /// und CTA-Pulse-Pfad.
    ///
    /// **Anzeige-Logik:**
    ///   • Empty → „Listen wählen" als Hinweis-Text (User muss tippen)
    ///   • 1 Liste  → Listen-Name als zentrale Zeile
    ///   • 2 Listen → beide Namen untereinander
    ///   • 3+ Listen → erste 2 Namen + „+N weitere"-Hinweis
    private var listSelectionCard: some View {
        let isEmpty = globalSelectedListIDs.isEmpty
        let isSelected = !isEmpty
        let moduleColor = sectionStyle.accent

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? moduleColor.opacity(0.25)
                        : AppTheme.Colors.secondarySurface
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? moduleColor : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(moduleColor)
                    .frame(width: 32, height: 32)

                if isEmpty {
                    Text("Lernlisten wählen")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    listSummaryView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .opacity(isSelected ? 1.0 : 0.85)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            showListPicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        // **Block 4 (2026-05-03)** — Pulsations-Hint solange keine
        // Liste gewählt. Stoppt bei erster Auswahl. Glow in Modul-
        // Akzent-Farbe analog zu den Zeit-Cards.
        .pulsing(active: isEmpty, glowColor: moduleColor)
    }

    /// Sub-View für die nicht-leere Anzeige in `listSelectionCard`.
    /// Resolved die UUIDs auf Display-Namen via `listStore.allLists`
    /// und zeigt bis zu 2 Namen + Restzähler.
    /// **Block 4 (2026-05-03)** — User-Spec-konformes Format:
    ///   • 1-3 Listen → Namen kommagetrennt + Total-Einträge-Count
    ///   • 4+ Listen  → „X Listen ausgewählt" + Total-Einträge-Count
    /// Total-Count via `VocabularyListSelectionResolver.effectiveItems`
    /// pro Liste, summiert. Lernjahr-Max wird respektiert (gleicher
    /// Resolver wie Quiz/Karteikarten/Train).
    @ViewBuilder
    private var listSummaryView: some View {
        let resolvedLists: [VocabularyList] = globalSelectedListIDs
            .compactMap { id in listStore.allLists.first(where: { $0.id == id }) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let totalEntries = resolvedLists.reduce(0) { acc, list in
            acc + VocabularyListSelectionResolver.effectiveItems(
                for: list,
                lernjahrMax: lernjahrMax
            ).count
        }

        let listLine: String = {
            if resolvedLists.count >= 4 {
                return "\(resolvedLists.count) Lernlisten ausgewählt"
            }
            return resolvedLists.map(\.name).joined(separator: ", ")
        }()

        // **Phase 5 (2026-05-04)** — optionales LJ-Range vor dem Total.
        let summaryText: String = {
            let totalText = "\(totalEntries) Einträge"
            if let range = VocabularyListSelectionResolver.lernjahrRangeLabel(forSelectedLists: resolvedLists) {
                return "\(range) · \(totalText)"
            }
            return totalText
        }()

        VStack(alignment: .leading, spacing: 3) {
            Text(listLine)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)

            Text(summaryText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // **Slot-Layout-Tighten 2026-05-07** — VStack-Spacing
            // 8 → 4 pt, damit der Slot-Screen-Content enger an den
            // Chevron rückt und die "Drop starten"-CTA klar über der
            // Bottom-Footer-Linie sitzt (vorher vom globalen Footer
            // verdeckt). Chevron-Position selbst bleibt unverändert
            // (sitzt im äußeren ModuleHeaderCard-Wrapper).
            //
            // Reihenfolge unverändert: Header → Zeit → Slot →
            // Ergebnis → CTA.
            VStack(alignment: .leading, spacing: 4) {
                // **Slot-Header-Icon-Sweep 2026-05-07** — Sparkles-
                // SF-Symbol durch programmatische Stacked-Cards-
                // Illustration ersetzt (analog Home-Daily-Drop-Card,
                // siehe `DailyDropStackedCardsIcon`). Das Asset trägt
                // die Daily-Drop-Identität konsistent von Home in den
                // Slot-Screen — der gleiche Karten-Stack der die
                // Slot-Maschine semantisch repräsentiert.
                //
                // Size 50 pt — passt visuell in den 64×64-Frame der
                // `ModuleHeaderCard`-Icon-Slot, mit etwas Innen-
                // Padding für Atemraum. (Default Size 40 pt für die
                // 52-pt-WideMethodCard auf Home; hier etwas größer
                // weil das Frame mehr Platz bietet.)
                ModuleHeaderCard(
                    customIcon: DailyDropStackedCardsIcon(size: 38),
                    title: "Daily Drop",
                    accent: sectionStyle.accent,
                    onBack: { dismiss() },
                    onHelp: { ElumiHelpPresenter.shared.show(.dailyDrop) },
                    compact: true
                )

                // 1) Trainingszeit-Anzeige (Sache B Stufe 3): XXL-Zahl
                //    + Pencil-Pill für Re-Edit. Statt der alten
                //    `durationCard` mit drei Chips. Die Chips leben
                //    jetzt im Setup-Modal (`setupModalOverlay`).
                // **Iter 6 (2026-05-07)** — Externer Atemraum
                // oben/unten zur Nachbarschaft (Header oben +
                // Slot-Area unten). User-Befund: Card stieß an
                // beide Nachbarn an, wirkte gequetscht. 10 pt
                // padding pro Seite gibt der Dauer-Card einen
                // klaren visuellen Atem-Rahmen, ohne die anderen
                // VStack-Gaps zu beeinflussen.
                timeDisplayCard
                    .padding(.vertical, 10)

                // 2) Slot Machine.
                slotMachineArea

                // 3) Ergebnisbereich — Placeholder vor Spin,
                //    gezogene Module nach Reveal.
                trainingResultCard

                // 4) CTA als LETZTES inhaltliches Element. Zeigt
                //    „Los geht's! (Versuch X/3)" oder transformiert
                //    nach dem 3. Spin zu „Training starten". Kein
                //    Overlay, kein safeAreaInset — im normalen
                //    VStack-Flow.
                spinCTA

                Spacer(minLength: 0)
            }
            .animation(.easeInOut(duration: 0.28), value: slotPhase)
            .animation(.easeInOut(duration: 0.22), value: lastSpinResult)
            .animation(.easeInOut(duration: 0.25), value: currentSpinNumber)
            .onChange(of: slotPhase) { _, newPhase in
                // **Result-Highlight-Trigger** (2026-04-25): sobald
                // die Slot-Machine in `.revealed` wechselt, bekommt
                // die Ergebnis-Card einen initialen Glow-Burst +
                // anschließend sanftes Pulsieren. Bei einem neuen
                // Spin (`.spinning` / `.stopping`) reset.
                switch newPhase {
                case .revealed:
                    triggerResultHighlight()
                    // **Block 5 (2026-05-03)** — Jackpot-Feier-Trigger.
                    // Wenn alle drei Reels Game-Symbole zeigen, fahren
                    // wir das Overlay direkt hier hoch (statt den User
                    // den „Jetzt üben"-CTA tappen zu lassen, der dann
                    // den Pre-Screen mit „Jackpot — kein Training!"
                    // gerendert hätte).
                    triggerJackpotIfApplicable()
                    // **Daily-Drop-Habit-Tracking 2026-05-06** —
                    // Slot ist vollständig revealed → Daily Drop
                    // gilt als „heute gemacht". Persistiert das
                    // Datum, sodass die HomeView-Card-Badge auf
                    // „✓ Heute gemacht" wechselt. Mehrfache Reveals
                    // am selben Tag sind idempotent (überschreiben
                    // nur den Timestamp innerhalb desselben Tages).
                    DailyDropTracker.markCompletedNow()
                case .spinning, .stopping:
                    resultHighlightScale = 1.0
                    resultHighlightGlow = 0.0
                case .idle, .landed:
                    break
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .navigationBarBackButtonHidden(true)
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
                onSettings: openSettings
            )
        }
        // **Erstnutzer-Hint (2026-06-09)** — erklärt, was einen beim
        // Daily Drop erwartet. Der Modus ist der erklärungs-
        // bedürftigste: die Slot-Maschine würfelt Übungsart und Liste
        // aus, das versteht man ohne Hinweis nicht.
        .hintBubble(
            id: "daily_drop_intro",
            text: """
            Dein Mix des Tages — jeden Tag neu.
            Ich würfel dir aus, was du übst: mal Vokabeln, mal Verben, mal was anderes.
            Du wählst nur, wie lang es sein soll.
            Dann einfach loslegen und deine Serie am Laufen halten.
            """,
            // **2026-06-09** — Setup-Modal („Wie viele Übungen?") erst
            // NACH dem Hint öffnen, nicht gleichzeitig damit (siehe
            // Gate in `.onAppear` oben).
            onDismiss: { checkSetupModalState() }
        )
    }

}
