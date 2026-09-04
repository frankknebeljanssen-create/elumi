// ChatBubbleView.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Einzelne Chat-Bubble im
// WhatsApp/iMessage-Look. Strikt KEINE Elumi-Card-Tokens (kein
// `appSetupCardBackground`, kein `AppTheme.Spacing`-System), damit
// der Chat-Body sich klar vom Lern-App-Look abhebt.
//
// User-Bubbles: rechts, lila (#5B6AF0), weiß-Text.
// Léa-Bubbles: links, weiß, Avatar links davor, mit dezentem Schatten.
//
// **Schritt 2A (2026-05-10) — Korrektur-Transform**:
// Wenn Léa eine Korrektur in ihrer Antwort liefert, schreibt der
// ChatService die Felder `foundErrorUserText` + `foundErrorGermanTip`
// + `correctionCardId` retroaktiv auf die zugehörige User-Message.
// Die Bubble erkennt diesen State und transformiert sich (creme bg
// + orange Border + Underline-Span + Shake + 💡-Badge).
//
// **Schritt 2B-1 (2026-05-10) — Vocab + New-Word-Highlights**:
//   • `message.vocabUsed`: Lektionswörter, die der User korrekt
//     verwendet hat (aus Léas `[VOCAB: …]`-Markern). Werden in der
//     User-Bubble grün hinterlegt (rgba(76,175,120,0.25)) und in der
//     Léa-Bubble (falls Léa sie auch im Recasting nutzt) dezenter
//     (0.15).
//   • `message.newWords`: neue Wörter, die Léa eingeführt hat (aus
//     `[NEW: wort|übersetzung]`-Markern). Werden in der Léa-Bubble
//     blau unterstrichen (#2C7BE5) und mit einem Custom-URL-Link
//     `leanew://wort` verknüpft. ChatView fängt den Link ab und
//     öffnet `ChatNewWordTooltipView`.
//
// Word-Boundary-Suche: NSRegularExpression mit `\b…\b`-Pattern und
// `useUnicodeWordBoundaries`-Option, damit auch französische Akzente
// (à, ç, é) korrekt als Wort-Anker behandelt werden — sonst würde
// "le" auch in "telle" matchen und falsch hinterlegt.

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool

    /// Wird gesetzt, sobald die Shake-Animation einmal gespielt wurde.
    /// Verhindert Re-Shakes bei View-Updates und beim App-Restart
    /// (persisted Korrektur lädt ohne Shake).
    @State private var hasShaken: Bool = false
    @State private var shakeProgress: CGFloat = 0

    var body: some View {
        switch message.sender {
        case .user:
            userBubble
        case .lea:
            leaBubble
        }
    }

    // MARK: - User-Bubble (rechts)

    private var userBubble: some View {
        // Korrektur-Flag — bestimmt ob die Bubble den „Fehler-Look"
        // hat (creme + orange) oder den Standard-Lila-Look.
        let hasCorrection = message.foundErrorUserText != nil

        return HStack(alignment: .bottom, spacing: 6) {
            // Spacer-min — bei Korrektur etwas kleiner, damit das
            // Badge + Bubble-Set nicht zu schmal wird.
            Spacer(minLength: hasCorrection ? 30 : 60)

            if hasCorrection {
                CorrectionBadge()
                    .transition(.scale.combined(with: .opacity))
            }

            userBubbleContent(hasCorrection: hasCorrection)
                .modifier(ShakeEffect(animatableData: shakeProgress))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .onChange(of: message.correctionCardId) { _, newID in
            guard newID != nil, !hasShaken else { return }
            hasShaken = true
            withAnimation(.linear(duration: 0.42)) {
                shakeProgress = 1
            }
        }
        .onAppear {
            if message.correctionCardId != nil {
                hasShaken = true
            }
        }
    }

    @ViewBuilder
    private func userBubbleContent(hasCorrection: Bool) -> some View {
        // Farb-Set — bei Korrektur creme + dark-text, sonst lila + weiß.
        let textColor: Color = hasCorrection
            ? Color(red: 0.102, green: 0.102, blue: 0.102) // #1a1a1a
            : .white
        let bgColor: Color = hasCorrection
            ? Color(hex: "#FFF8E7")
            : Color(hex: "#5B6AF0")
        let strokeColor: Color = hasCorrection
            ? Color(hex: "#FF9F43")
            : .clear
        let strokeWidth: CGFloat = hasCorrection ? 1.5 : 0

        Text(userTextAttributed(textColor: textColor, hasCorrection: hasCorrection))
            .font(.system(size: 16, weight: .regular))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bgColor,
                in: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 18,
                        bottomLeading: 18,
                        bottomTrailing: 4,
                        topTrailing: 18
                    ),
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 18,
                        bottomLeading: 18,
                        bottomTrailing: 4,
                        topTrailing: 18
                    ),
                    style: .continuous
                )
                .stroke(strokeColor, lineWidth: strokeWidth)
            )
    }

    /// Baut den AttributedString für den User-Bubble-Text.
    /// Effekte (von schwächstem zu stärkstem Visuell):
    ///   1. VOCAB-Highlight (grün hinterlegt, rgba(76,175,120,0.25)).
    ///      Hellster Akzent — bestätigt korrekte Wortverwendung.
    ///   2. FEHLER-Underline (orange #FF9F43). Über VOCAB-Background
    ///      gelegt: AttributedString unterstützt mehrere Attribute
    ///      auf demselben Range nativ, kein Konflikt.
    /// Bei aktiver Korrektur kippt das Bubble-Bg auf creme — der
    /// VOCAB-Background bleibt gegenüber dem creme noch erkennbar.
    private func userTextAttributed(textColor: Color, hasCorrection: Bool) -> AttributedString {
        var attr = AttributedString(message.text)
        attr.foregroundColor = textColor

        // VOCAB-Highlights (heller Grün, weil User aktiv).
        let vocabBg = Self.vocabHighlightColor(forUserBubble: true)
        applyVocabHighlights(to: &attr, words: message.vocabUsed, background: vocabBg)

        // FEHLER-Underline (Orange).
        if let errorText = message.foundErrorUserText, !errorText.isEmpty {
            applyUnderline(
                to: &attr,
                in: message.text,
                substring: errorText,
                color: Color(hex: "#FF9F43")
            )
        }
        return attr
    }

    // MARK: - Léa-Bubble (links, mit Avatar)

    private var leaBubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ChatAvatarView(size: 26)

            HStack(alignment: .bottom, spacing: 2) {
                // Während des Streams haben wir noch keinen sauberen
                // AttributedString-Kontext (Marker können noch nicht
                // gestrippt sein) → fallback auf Plain-Text. Erst nach
                // dem `parsed.cleanText`-Update am Stream-End rendert
                // die Bubble das angereicherte AttributedString.
                if isStreaming {
                    Text(message.text.isEmpty ? " " : message.text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(leaTextAttributed())
                        .font(.system(size: 16, weight: .regular))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isStreaming {
                    StreamingCursorView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 18,
                        bottomLeading: 4,
                        bottomTrailing: 18,
                        topTrailing: 18
                    ),
                    style: .continuous
                )
                .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    /// Léa-Text mit dezentem VOCAB-Highlight (falls Léa Lektionswörter
    /// im Recasting verwendet) + NEW-Word-Underline + Custom-URL-Link
    /// für Tooltip-Tap.
    private func leaTextAttributed() -> AttributedString {
        var attr = AttributedString(message.text)
        attr.foregroundColor = Color(red: 0.102, green: 0.102, blue: 0.102) // #1a1a1a

        // Dezenterer VOCAB-Highlight für Léa (User-Bubble: 0.25 / Léa: 0.15).
        let vocabBg = Self.vocabHighlightColor(forUserBubble: false)
        applyVocabHighlights(to: &attr, words: message.vocabUsed, background: vocabBg)

        // NEW-Word-Underline (blau) + URL-Link für Tap-Detection.
        // ChatView fängt `leanew://wort` via OpenURLAction ab und
        // öffnet den Tooltip mit der zugehörigen Übersetzung.
        for nw in message.newWords {
            applyNewWordUnderline(to: &attr, in: message.text, newWord: nw)
        }
        return attr
    }

    // MARK: - AttributedString Helpers

    /// **Schritt 2B-1** — VOCAB-Highlight-Farbe.
    ///
    /// **Smoke-Polish 2026-05-10** — Frank's initiale Spec hatte
    /// 0.25/0.15 Opacity, das war auf realer Hardware kaum sichtbar
    /// (besonders die Léa-Variante sah aus wie Banding). Jetzt:
    ///   • User-Bubble: 0.45 (deutlich grün, klares Erfolgs-Signal)
    ///   • Léa-Bubble: 0.30 (immer noch dezenter als User, aber
    ///     wahrnehmbar gegen die weiße Bubble-Background)
    private static func vocabHighlightColor(forUserBubble: Bool) -> Color {
        let opacity: Double = forUserBubble ? 0.45 : 0.30
        return Color(red: 76/255, green: 175/255, blue: 120/255).opacity(opacity)
    }

    /// Wendet einen Background-Highlight auf alle Word-Boundary-
    /// Vorkommen jedes übergebenen Wortes an. Case-insensitive,
    /// Unicode-aware (französische Akzente bleiben Wortgrenzen).
    /// Mehrfach-Vorkommen (z.B. „les devoirs" zweimal in derselben
    /// Message) werden alle hinterlegt.
    private func applyVocabHighlights(
        to attr: inout AttributedString,
        words: [String],
        background: Color
    ) {
        let plain = message.text
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            for nsRange in Self.wordBoundaryRanges(of: trimmed, in: plain) {
                // **Swift exclusive-access** — wir müssen die Range
                // ZUERST als Snapshot holen (nicht-mutierender Read)
                // und DANN die Mutation (`attr[range].backgroundColor`)
                // separat anwenden. Würden wir &attr in einen Helper
                // reichen UND im Closure-Body auf attr zugreifen,
                // bricht der Compiler mit „overlapping accesses".
                if let range = Self.attributedRange(for: nsRange, in: plain, of: attr) {
                    attr[range].backgroundColor = background
                }
            }
        }
    }

    /// Wendet eine Single-Underline an einer Substring-Range an
    /// (FEHLER-Marker auf der User-Bubble).
    private func applyUnderline(
        to attr: inout AttributedString,
        in plain: String,
        substring: String,
        color: Color
    ) {
        guard let range = attr.range(of: substring) else { return }
        attr[range].underlineStyle = Text.LineStyle(pattern: .solid, color: color)
    }

    /// Setzt blaue Underline + Custom-URL-Link auf das NEW-Wort in
    /// Léas Bubble. URL-Scheme `leanew://wort` wird vom ChatView
    /// abgefangen, um den Tooltip zu öffnen. Nicht-ASCII-Wörter
    /// werden percent-encoded — sonst lehnt URL(string:) das ab.
    private func applyNewWordUnderline(
        to attr: inout AttributedString,
        in plain: String,
        newWord: FoundNewWord
    ) {
        let trimmed = newWord.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Word-Boundary-Suche, damit "vacances" nicht in "vacancesz"
        // matcht. Wir nehmen das ERSTE Vorkommen — Léas NEW-Marker
        // referenziert genau ein Wort, ein Vorkommen reicht.
        guard let nsRange = Self.wordBoundaryRanges(of: trimmed, in: plain).first,
              let range = Self.attributedRange(for: nsRange, in: plain, of: attr)
        else {
            return
        }
        // **Smoke-Polish 2026-05-10** — Underline allein war auf
        // realer Hardware zu dünn/blass. Jetzt iOS-Link-Look:
        //   • Foreground-Color = saturated blue (#1565C0)
        //   • Font-Weight = .semibold (Wort steht aus dem Text raus)
        //   • Underline = solid in derselben Farbe
        // Result: das Wort liest klar als „tappable Link", Tooltip-
        // Affordanz sofort erkennbar.
        let linkColor = Color(hex: "#1565C0")
        attr[range].foregroundColor = linkColor
        attr[range].font = .system(size: 16, weight: .semibold)
        attr[range].underlineStyle = Text.LineStyle(pattern: .solid, color: linkColor)

        // Custom-URL für Tap-Detection. Percent-encoded weil
        // französische Wörter Apostrophe / Akzente enthalten
        // (z.B. „l'école" → `l%27%C3%A9cole`).
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "leanew://\(encoded)") {
            attr[range].link = url
        }
    }

    /// **Helper** — konvertiert einen `NSRange` (aus dem Plain-String
    /// `plain`) in eine `Range<AttributedString.Index>`. Pure read,
    /// keine Mutation auf `attr` — der Caller appliziert das Attribut
    /// danach selbst (so vermeiden wir „overlapping accesses to
    /// 'attr'", die Swift's exclusive-access-Regel bricht, wenn man
    /// inout + Closure-Capture mischt).
    private static func attributedRange(
        for nsRange: NSRange,
        in plain: String,
        of attr: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard let stringRange = Range(nsRange, in: plain) else { return nil }
        guard let lower = AttributedString.Index(stringRange.lowerBound, within: attr),
              let upper = AttributedString.Index(stringRange.upperBound, within: attr)
        else { return nil }
        return lower..<upper
    }

    /// **Helper** — sucht word-boundary-Vorkommen einer Phrase im
    /// Plain-String. Case-insensitive, Unicode-Word-Boundaries (damit
    /// „ça va" sauber als Wortgruppe matched, nicht innerhalb von
    /// längeren Tokens). Returnt alle Match-Ranges in NSRange-Form.
    private static func wordBoundaryRanges(of phrase: String, in text: String) -> [NSRange] {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"\b\#(escaped)\b"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        ) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).map(\.range)
    }
}

// MARK: - Korrektur-Badge (💡)

/// 30×30 Circle mit Gold→Orange-Gradient und 💡-Emoji. Wird links der
/// User-Bubble gerendert wenn die Message eine Korrektur hat.
private struct CorrectionBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FFD86B"),
                            Color(hex: "#FF9F43")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 1)

            Text("💡")
                .font(.system(size: 16))
        }
    }
}

// MARK: - Shake-Effect (Korrektur-Highlight-Animation)

/// GeometryEffect für eine kurze horizontale Shake-Animation der User-
/// Bubble. ±6 pt × 3 Schwingungen über 0.42 s linear, einmalig beim
/// `correctionCardId nil → !nil`-Übergang.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 6
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// **Streaming-Cursor** — 2px breiter lila Strich, blinkt 0.8 s loop.
private struct StreamingCursorView: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color(hex: "#5B6AF0"))
            .frame(width: 2, height: 18)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
