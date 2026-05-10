// ChatErrorBannerView.swift
// **Sweep „Error-Banner" (2026-05-10)** — Banner über der Chat-Input-
// Bar, der Backend-Errors visuell deutlich als System-Meldung kommuniziert
// (statt sie wie früher als Léa-Bubble in den Chat zu schmuggeln).
//
// **Design-Anker** — schlichter horizontaler Streifen mit Icon + Text +
// optionalem X-Close. Hintergrund kind-spezifisch:
//   • `rateLimit` → warmes Orange (#FF9F43, 95 % Opacity) — gleiche
//     Akzent-Farbe wie der Korrektur-Marker, kommuniziert „Pause/
//     Aufmerksamkeit".
//   • `authFailed`/`serverError`/`networkError` → kühles Dunkelgrau
//     (#6B6B7A, 95 % Opacity) — nicht alarmistisch rot, einfach
//     „etwas hakt".
//
// KEIN Elumi-Card-3D-Look — pure WhatsApp-Style flacher Banner mit
// dezentem Drop-Shadow.
//
// **Auto-Dismiss-Logik** — nicht hier (View ist passiv). Der Service
// (`ChatService.showErrorBanner`) plant den Timer und setzt nach 5 s
// `lastErrorBanner = nil`. Dadurch funktioniert Auto-Dismiss auch
// dann, wenn der User in eine andere View navigiert (Banner stirbt
// weiterhin nach 5 s im Service-State, kommt nicht plötzlich beim
// Re-Open des Chats wieder hoch).

import SwiftUI

struct ChatErrorBannerView: View {
    let banner: ChatErrorBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(banner.kind.icon)
                .font(.system(size: 18))

            Text(banner.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Banner schließen")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(banner.kind.background)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        // **Tap-anywhere-to-dismiss** zusätzlich zum X-Button: der
        // ganze Banner-Bereich ist tappable, damit der User mit
        // großem Finger nicht das kleine X treffen muss.
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }
}

private extension ChatErrorBanner.Kind {
    /// Icon-Emoji passend zum Error-Typ. Wird als visueller Anker
    /// links im Banner gerendert; das Message-Text-Feld kann zusätzlich
    /// ein eigenes Emoji enthalten (z.B. 😴 oder 📵) — wirkt als
    /// doppelter Akzent, was bei kurzen Banner-Texten Aufmerksamkeit
    /// verstärkt ohne den Text zu überladen.
    var icon: String {
        switch self {
        case .rateLimit: return "😴"
        case .authFailed: return "🔒"
        case .serverError: return "⚠️"
        case .networkError: return "📵"
        }
    }

    /// Hintergrund-Farbe. RateLimit warm-orange (#FF9F43), alle anderen
    /// kühl-grau (#6B6B7A) — nicht-alarmistisch, signalisiert „temporäres
    /// Problem" ohne Panik-Rot.
    var background: Color {
        switch self {
        case .rateLimit:
            return Color(red: 1.0, green: 0.624, blue: 0.263).opacity(0.95) // #FF9F43
        case .authFailed, .serverError, .networkError:
            return Color(red: 0.420, green: 0.420, blue: 0.478).opacity(0.95) // #6B6B7A
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ChatErrorBannerView(
            banner: ChatErrorBanner(
                id: UUID(),
                message: "Léa muss heute schlafen — bis morgen! 😴",
                kind: .rateLimit
            ),
            onDismiss: {}
        )
        ChatErrorBannerView(
            banner: ChatErrorBanner(
                id: UUID(),
                message: "Léa hat gerade kein Netz 📵",
                kind: .networkError
            ),
            onDismiss: {}
        )
        ChatErrorBannerView(
            banner: ChatErrorBanner(
                id: UUID(),
                message: "Léa schläft gerade — versuch's gleich nochmal 💤",
                kind: .serverError
            ),
            onDismiss: {}
        )
    }
    .padding()
    .background(Color(red: 0.949, green: 0.949, blue: 0.969))
}
