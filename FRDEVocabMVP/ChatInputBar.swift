// ChatInputBar.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — TextField + Send-Button am
// unteren Rand des Chats. Pure iOS-Messaging-Look (weißer Hintergrund,
// Border-Top-Hairline) — KEINE Elumi-Card-Tokens.

import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isSendDisabled: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // **Bug-Fix 2026-05-10** — explizite Text-Farbe auf
            // dunkles #1a1a1a. Vorher kein `.foregroundStyle()`
            // gesetzt → iOS-Default greift, der unter Dark-Mode
            // weiß rendert → weißer Text auf hellem #F8F8FA-
            // Background = unlesbar. Chat-Body ist by-design
            // immer light (WhatsApp-Look), daher harte Farbwahl.
            TextField("Écris un message…", text: $text, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102)) // #1a1a1a
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.973, green: 0.973, blue: 0.980)) // #F8F8FA
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(red: 0.878, green: 0.878, blue: 0.890), lineWidth: 1)
                )
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit { triggerSend() }

            Button(action: triggerSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(
                                isSendDisabled
                                ? Color(red: 0.867, green: 0.867, blue: 0.867)
                                : Color(red: 0.357, green: 0.416, blue: 0.941)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
            .accessibilityLabel("Senden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0.910, green: 0.910, blue: 0.929))
                .frame(height: 0.5)
        }
    }

    private func triggerSend() {
        guard !isSendDisabled else { return }
        onSend()
    }
}
