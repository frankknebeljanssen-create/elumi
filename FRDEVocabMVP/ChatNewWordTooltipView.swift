// ChatNewWordTooltipView.swift
// **Léa-Chat MVP Schritt 2B-1 (2026-05-10)** — Tooltip-Pop-over, das
// erscheint, wenn der User auf ein blau unterstrichenes neues Wort
// in Léas Antwort tippt. Zeigt das französische Wort, die deutsche
// Übersetzung (aus Léas `[NEW: wort|übersetzung]`-Marker) und einen
// noch-deaktivierten „➕ Zu Stapel"-Button als Vorschau auf das
// kommende Personal-Stapel-Feature (Schritt 3).
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

            // Trennlinie, dann der ausgegraute „Zu Stapel"-Button.
            Divider()
                .padding(.vertical, 2)

            // **Schritt 3-Placeholder** — das eigentliche Personal-
            // Stapel-Feature kommt erst später; hier schon der visuelle
            // Anker, damit User den Pfad sieht. Disabled + „Bald
            // verfügbar"-Label macht klar, dass es heute nichts tut.
            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Zu Stapel")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("Bald verfügbar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                )
            }
            .disabled(true)
            .opacity(0.7)
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
