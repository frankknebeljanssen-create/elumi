// ChatSessionSummarySheet.swift
// **Léa-Chat MVP Schritt 2B-2B (2026-05-10)** — Post-Session-Summary,
// die ChatView nach explizitem Back-Tap zeigt, wenn der Threshold
// erreicht ist (5+ User-Messages ODER ≥1 Message + ≥5 Min Dauer).
//
// **Drei Sektionen, alle conditional**:
//   1. Lektionswörter, die der User korrekt verwendet hat (aus
//      `vocabUsed` der User-Messages, dedupliziert).
//   2. Sätze zum Nachüben (aus `foundErrorUserText` +
//      `foundErrorGermanTip` der User-Messages).
//   3. Neue Wörter, die Léa eingeführt hat (aus `newWords` der Léa-
//      Messages, dedupliziert by word).
//
// Wenn ALLE Sektionen leer sind: Edge-Case-View „Bis bald!" mit nur
// XP-Placeholder + Schließen-Button (kein „Üben"-Button).
//
// **CTA-Logik**:
//   • Wenn corrections oder newWords vorhanden → „Üben in Karteikarten"-
//     Button als Primary-CTA (existing `AppPrimaryButtonStyle`).
//   • Schließen-Button immer als Secondary.
//
// **Visueller Anker** — schlichtes iOS-Sheet-Layout: ScrollView mit
// Sektionen, Pills + Cards in matching-WhatsApp-Look (kein Elumi-3D).
// Sektion-Headers in 14 pt semibold. Pills für Wörter mit Capsule-
// Background im VOCAB-Grün-Token. Korrektur-Cards mit creme-bg +
// orange-Border (Konsistenz zur User-Bubble-Korrektur).

import SwiftUI

struct ChatSessionSummarySheet: View {
    /// Alle Messages der aktuellen Session (gefiltert auf
    /// `timestamp >= sessionStartTimestamp` vom Caller).
    let sessionMessages: [ChatMessage]

    /// Schließen-Button-Tap oder Drag-Down — Caller dismissed das
    /// Sheet UND popt ChatView zu Home.
    let onDismiss: () -> Void

    /// „Üben in Karteikarten"-Tap — Caller dismissed das Sheet UND
    /// navigiert zu Karteikarten-Setup (replaceTop, sodass ChatView
    /// aus dem Stack verschwindet).
    let onPracticeInFlashcards: () -> Void

    /// XP-Display. Bis Schritt 2B-2B war das ein Placeholder; ab
    /// **Schritt 3A (2026-05-10)** wird der eigentliche Increment
    /// von `ChatService.recordSessionEnd` ausgelöst, der Sheet
    /// rendert nur die Zahl.
    var xpEarned: Int = 15

    /// **Schritt 3A (2026-05-10)** — wird in `.onAppear` aufgerufen.
    /// ChatView wired das auf `chatService.recordSessionEnd(...)`,
    /// das die drei Session-End-Pflichten erfüllt: Auto-Sammlung
    /// in den Chat-Stapel, +15 XP, Streak-Hook.
    let onSessionEnded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // **Sweep „3A Bug-Fix Iter-2" (2026-05-10)** — explizite
            // Drag-Indicator-Capsule oben, zusätzlich zum
            // `.presentationDragIndicator(.visible)`. Frank's Smoke-
            // Befund: das System-Indicator war zu dezent erkennbar,
            // User wusste nicht ob Sheet draggable ist. Custom-
            // Capsule ist 36×4 pt grau (#C7C7CC) — klare iOS-Sheet-
            // Affordance-Optik, sitzt direkt über dem Header.
            Capsule()
                .fill(Color(white: 0.78))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)

            header

            content
        }
        .background(Color(red: 0.973, green: 0.973, blue: 0.980).ignoresSafeArea())
        .presentationDetents([.large])
        // System-Indicator ausgeschaltet — die Custom-Capsule oben
        // übernimmt die Drag-Affordance allein, sonst zwei Indicators
        // übereinander.
        .presentationDragIndicator(.hidden)
        // **Schritt 3A** — Session-End-Hooks feuern genau einmal
        // beim Sheet-Open. Auto-Sammlung passiert silent (keine
        // UI-Indikation), XP/Streak via existing ProgressStore-
        // Mechanik. Side-Effects synchron — wenn der User
        // unmittelbar danach „Üben in Karteikarten" tippt, ist die
        // Liste schon gefüllt.
        .onAppear {
            onSessionEnded()
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if hasContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if !vocabUsed.isEmpty { vocabUsedSection }
                        if !corrections.isEmpty { correctionsSection }
                        if !newWords.isEmpty { newWordsSection }
                        xpFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                }
            } else {
                emptyContent
            }

            actionButtons
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Heute mit Léa 🎯")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(red: 0.92, green: 0.92, blue: 0.92))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Summary schließen")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Sektion 1: Verwendete Lektionswörter

    private var vocabUsedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✓ Du hast diese Wörter benutzt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.176, green: 0.478, blue: 0.243)) // #2D7A3E

            // Adaptive-Grid für Pill-Wrap-Layout. SwiftUI hat keine
            // native FlowLayout vor iOS 17 — `LazyVGrid` mit
            // `.adaptive(minimum:)` ist der pragmatische MVP-Ansatz.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(vocabUsed, id: \.self) { word in
                    Text(word)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(red: 76/255, green: 175/255, blue: 120/255).opacity(0.30))
                        )
                        .foregroundStyle(Color(red: 0.176, green: 0.478, blue: 0.243))
                }
            }
        }
    }

    // MARK: - Sektion 2: Korrekturen

    private var correctionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📚 Diese Sätze üben wir nochmal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.30, blue: 0.10))

            VStack(spacing: 8) {
                ForEach(Array(corrections.enumerated()), id: \.offset) { _, item in
                    correctionCard(userText: item.userText, germanTip: item.germanTip)
                }
            }
        }
    }

    @ViewBuilder
    private func correctionCard(userText: String, germanTip: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Falscher User-Text — durchgestrichen + grau, als
            // visueller „das war's"-Anker.
            Text(userText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(white: 0.5))
                .strikethrough(true, color: Color(white: 0.5))
                .lineLimit(2)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.176, green: 0.478, blue: 0.243))

                Text(germanTip)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "#FFF8E7"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: "#FF9F43").opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Sektion 3: Neue Wörter

    private var newWordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("➕ Neue Wörter entdeckt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#1565C0"))

            VStack(spacing: 6) {
                ForEach(newWords, id: \.word) { nw in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(nw.word)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "#1565C0"))

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(nw.translation)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#1565C0").opacity(0.06))
                    )
                }
            }
        }
    }

    // MARK: - XP-Footer (Placeholder bis Schritt 3)

    private var xpFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("+\(xpEarned) XP")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.93))
        )
    }

    // MARK: - Empty-Edge-Case

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text("Bis bald! 👋")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
            Text("Du warst kurz da, das ist auch okay. Beim nächsten\nMal sammelst du wieder Wörter.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            xpFooter
                .padding(.horizontal, 24)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action-Buttons

    @ViewBuilder
    private var actionButtons: some View {
        // **Schritt 3A Smoke-Fix Bug B (2026-05-10) Iter-2** —
        // Schließen-Button als Tertiary-Style (clear bg, cta-color
        // text) statt vorher `.bordered`. Frank-Spec: „secondary
        // Button (z.B. clear background, text-Color cta)". Damit
        // ist der Üben-CTA visuell prominent als Primary; Schließen
        // ist sekundär aber klar tappable. Empty-Edge-Case behält
        // Schließen als Solo-Primary.
        VStack(spacing: 0) {
            if canPractice {
                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Schließen")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.cta)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onPracticeInFlashcards) {
                        Text("Üben in Karteikarten")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
            } else {
                Button(action: onDismiss) {
                    Text("Schließen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .background(
            // Dezenter Top-Hairline trennt die Action-Zone vom Scroll.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(white: 0.85))
                    .frame(height: 0.5)
                Color(red: 0.973, green: 0.973, blue: 0.980)
            }
        )
    }

    // MARK: - Computed Data

    private var hasContent: Bool {
        !vocabUsed.isEmpty || !corrections.isEmpty || !newWords.isEmpty
    }

    /// Wenn `true`, zeigen wir den primären „Üben in Karteikarten"-CTA.
    /// Bei nur-Vocab-verwendet (= keine Korrekturen, keine NEW-Wörter)
    /// gibt es nichts Konkretes zu üben — dann ist „Schließen" die
    /// einzige sinnvolle Aktion (selbst wenn Vocab-Pills stehen, weiß
    /// das Karteikarten-Modul nicht, was daraus zu trainieren wäre).
    private var canPractice: Bool {
        !corrections.isEmpty || !newWords.isEmpty
    }

    /// Lektionswörter, die der User in Session-Messages benutzt hat
    /// — case-insensitive dedupliziert, Reihenfolge bleibt iteration-
    /// stable (erstes Vorkommen wird gehalten).
    private var vocabUsed: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for msg in sessionMessages where msg.sender == .user {
            for word in msg.vocabUsed {
                let key = word.lowercased()
                if seen.insert(key).inserted {
                    result.append(word)
                }
            }
        }
        return result
    }

    /// Korrektur-Pairs aus User-Messages mit `foundErrorUserText` und
    /// `foundErrorGermanTip`. Tuple statt struct, weil nur lokal
    /// benutzt — keine Equatable-Semantik nötig.
    private var corrections: [(userText: String, germanTip: String)] {
        sessionMessages.compactMap { msg in
            guard msg.sender == .user,
                  let userText = msg.foundErrorUserText,
                  let germanTip = msg.foundErrorGermanTip
            else { return nil }
            return (userText, germanTip)
        }
    }

    /// Neue Wörter aus den Léa-Messages (decodiert aus `newWordsData`).
    /// Dedupliziert by `word` (lowercased) — falls Léa dasselbe Wort
    /// in zwei Antworten neu einführt (z.B. weil sie's zwischendurch
    /// vergessen hat, dass sie's schon erklärt hat), nehmen wir nur
    /// das erste Vorkommen.
    private var newWords: [FoundNewWord] {
        var seen = Set<String>()
        var result: [FoundNewWord] = []
        for msg in sessionMessages where msg.sender == .lea {
            for nw in msg.newWords {
                let key = nw.word.lowercased()
                if seen.insert(key).inserted {
                    result.append(nw)
                }
            }
        }
        return result
    }
}
