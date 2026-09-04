// ChatNewWordTooltipView.swift
// **Léa-Chat MVP Schritt 2B-1 (2026-05-10)** — Tooltip-Pop-over, das
// erscheint, wenn der User auf ein blau unterstrichenes neues Wort
// in Léas Antwort tippt. Zeigt das französische Wort und die deutsche
// Übersetzung (aus Léas `[NEW: wort|übersetzung]`-Marker).
//
// **Schritt 3A (2026-05-10)** — Der „➕ Zu Stapel"-Button wurde
// entfernt: das Personal-Feature ist jetzt eine Auto-Sammlung am
// Session-Ende (siehe `VocabularyListStore.addChatStapelItem(...)`),
// die ohne User-Tap funktioniert. Der Tooltip dient ab jetzt nur
// noch als Vokabel-Lookup während des Chats.
//
// **Visueller Anker (Frank's Spec)**:
//   • ~200 pt breit, weiß bg, dezenter Schatten (0 4 12 / 15 % schwarz),
//     12 pt corner radius, 14 pt padding.
//   • KEIN Elumi-Card-Token — der Chat-Body bleibt strikt im
//     WhatsApp-/iMessage-Look. Tooltip ist eine isolierte UI-Atom-
//     Komponente.
//   • Schließen-Button oben rechts (X-Glyph) plus Tap-outside-to-
//     dismiss (in ChatView via background-Tap implementiert).

import SwiftUI

struct ChatNewWordTooltipView: View {
    let word: String
    let translation: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header-Row mit Schließen-X.
            HStack(alignment: .top) {
                Text(word)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color(red: 0.92, green: 0.92, blue: 0.92))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tooltip schließen")
            }

            // Übersetzung — Mid-Grey, kleinere Schrift, klare Hierarchie.
            Text(translation)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4)) // #666
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        // Frank's Spec: 0 4 12 / 15 % schwarz.
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

#Preview {
    ZStack {
        Color(red: 0.949, green: 0.949, blue: 0.969)
            .ignoresSafeArea()
        ChatNewWordTooltipView(
            word: "vacances",
            translation: "Ferien",
            onClose: {}
        )
    }
}
