// ChatBubbleView.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Einzelne Chat-Bubble im
// WhatsApp/iMessage-Look. Strikt KEINE Elumi-Card-Tokens (kein
// `appSetupCardBackground`, kein `AppTheme.Spacing`-System), damit
// der Chat-Body sich klar vom Lern-App-Look abhebt.
//
// User-Bubbles: rechts, lila (#5B6AF0), weiß-Text.
// Léa-Bubbles: links, weiß, Avatar links davor, mit dezentem Schatten.
//
// Streaming-Cursor: blinkender vertikaler Strich am Ende des Léa-
// Bubble-Texts während der Stream läuft. Endet wenn `isStreaming`
// auf der Bubble false wird (vom ChatService gesteuert via
// `streamingMessageID`).
//
// **Schritt 2A (2026-05-10) — Korrektur-Transform**:
// Wenn Léa eine Korrektur in ihrer Antwort liefert, schreibt der
// ChatService die Felder `foundErrorUserText` + `foundErrorGermanTip`
// + `correctionCardId` retroaktiv auf die zugehörige User-Message.
// Die Bubble erkennt diesen State und transformiert sich:
//   • Background: lila #5B6AF0 → creme #FFF8E7
//   • Border: orange #FF9F43, 1.5 pt
//   • Text-Color: white → dark #1a1a1a (sonst unlesbar auf creme)
//   • Underline-Span: orange unter dem `foundErrorUserText` (via
//     AttributedString, Substring-Range gegen `message.text` gematcht)
//   • Shake-Animation: ±6 pt horizontal × 3 Schwingungen, einmalig
//     bei `correctionCardId nil → !nil` Transition (NICHT beim
//     Reload aus SwiftData)
//   • 💡-Badge links der Bubble (30×30, gradient #FFD86B → #FF9F43)
//
// Die `CorrectionCardView` selbst wird im Parent (ChatView) zwischen
// dieser User-Bubble und der nachfolgenden Léa-Bubble gerendert.

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
        // **Shake-Trigger** — `initial: false` (default) sorgt dafür,
        // dass der onChange NICHT auf dem ersten Render feuert. Damit
        // wird beim App-Restart (persisted Korrektur) NICHT geshaked,
        // sondern nur wenn der ChatService die Korrektur-Felder live
        // nach dem Stream-End setzt.
        .onChange(of: message.correctionCardId) { _, newID in
            guard newID != nil, !hasShaken else { return }
            hasShaken = true
            withAnimation(.linear(duration: 0.42)) {
                shakeProgress = 1
            }
        }
        .onAppear {
            // Wenn die Bubble GLEICH MIT Korrektur erscheint
            // (App-Restart, History-Load): Shake-State als „schon
            // gespielt" markieren, damit ein späterer onChange-
            // Trigger (z.B. durch unrelated re-render) nicht doch
            // noch shaked.
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

        Text(userTextAttributed(textColor: textColor))
            .font(.system(size: 16, weight: .regular))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // **Bug-Fix 2026-05-10** — `.background(_ style: in: Shape)`-
            // Overload (iOS-17-idiomatic). Vorher
            // `.background(Shape.fill(Color))` → unter Dark-Mode-
            // Trace propagierte `.foregroundStyle(.white)` via View-
            // Tree und überschrieb das Fill. Mit dem ShapeStyle-
            // Overload ist die Farbe explizit isoliert.
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

    /// Baut den AttributedString für den User-Bubble-Text. Bei aktiver
    /// Korrektur wird der `foundErrorUserText`-Substring orange unter-
    /// strichen. Wenn der Substring nicht gefunden wird (z.B. Léa hat
    /// den Marker nicht 1:1 wiedergegeben), wird der Text ohne Underline
    /// gerendert — die Bubble bleibt aber im Korrektur-Look (creme +
    /// border + Badge), sodass der visuelle Anker nicht verloren geht.
    private func userTextAttributed(textColor: Color) -> AttributedString {
        var attr = AttributedString(message.text)
        attr.foregroundColor = textColor

        if let errorText = message.foundErrorUserText,
           !errorText.isEmpty,
           let range = attr.range(of: errorText) {
            // **API-Hinweis (iOS 17 SwiftUI)** — `AttributedString`
            // benutzt `Text.LineStyle` für `underlineStyle`, NICHT
            // `NSUnderlineStyle`. Die Farbe wird über den
            // `init(pattern:color:)` direkt im LineStyle eingebettet
            // (es gibt KEIN separates `underlineColor`-Key auf der
            // SwiftUI-Variante von AttributedString).
            attr[range].underlineStyle = Text.LineStyle(
                pattern: .solid,
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
                Text(message.text.isEmpty && isStreaming ? " " : message.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102)) // #1a1a1a
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

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
}

// MARK: - Korrektur-Badge (💡)

/// 30×30 Circle mit Gold→Orange-Gradient und 💡-Emoji. Wird links der
/// User-Bubble gerendert wenn die Message eine Korrektur hat. Bewusst
/// nicht zu groß und nicht zu prominent — soll als „Lern-Stempel" lesen,
/// nicht als Strafe-Marker.
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
/// Bubble. Wird einmalig getriggert wenn die Message ihren Korrektur-
/// State bekommt (`correctionCardId` von nil → !nil).
///
/// Animation: animatableData 0 → 1 über 0.42 s linear, ergibt 3
/// Schwingungen mit ±6 pt Amplitude.
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
/// Wird in der Léa-Bubble während des Streams am Ende des Texts
/// gerendert. Verschwindet wenn `isStreaming = false`.
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
