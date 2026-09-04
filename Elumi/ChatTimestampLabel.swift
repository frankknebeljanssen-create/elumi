// ChatTimestampLabel.swift
// **Léa-Chat MVP Schritt 2B-2A (2026-05-10)** — schlichter Datum/
// Uhrzeit-Anker zwischen Bubbles im Chat-Body. Wird vom
// `ChatView`-ForEach periodisch eingestreut (siehe
// `shouldShowTimestamp(at:in:)`):
//   • Vor der ersten Message
//   • Vor jeder Message, die >2 Min nach der vorigen kommt
//   • Vor jeder 4. Message (auch wenn keine Pause)
//
// **Visueller Anker** — schlichtes 11 pt-Grau zentriert mit
// vertikalem Padding 8 pt. KEIN Elumi-Card-Token, kein Border,
// kein Background. Nähert sich iMessage/WhatsApp-Date-Header an.
//
// **Format-Logik** (Locale `de_DE` festgenagelt, weil die App
// Léa-spezifisch deutsch ist; `Locale.current` wäre overkill bei
// einer Single-Language-Anwendung):
//   • heute → „HH:mm"
//   • gestern → „Gestern HH:mm"
//   • älter → „dd.MM. HH:mm"

import Foundation
import SwiftUI

struct ChatTimestampLabel: View {
    let date: Date

    var body: some View {
        Text(Self.formatted(date))
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color(white: 0.55))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    /// Formatiert ein Datum nach der oben beschriebenen 3-Stufen-Regel.
    /// `static` damit der Aufruf-Site (z.B. zukünftiger Aggregations-
    /// Layer) die Logik wiederverwenden kann ohne View-Instanz.
    static func formatted(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Gestern \(Self.timeFormatter.string(from: date))"
        } else {
            return Self.dateTimeFormatter.string(from: date)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()
}

#Preview {
    VStack(spacing: 0) {
        ChatTimestampLabel(date: Date())
        ChatTimestampLabel(date: Date().addingTimeInterval(-86400)) // gestern
        ChatTimestampLabel(date: Date().addingTimeInterval(-86400 * 5)) // 5 Tage
    }
    .padding()
    .background(Color(red: 0.949, green: 0.949, blue: 0.969))
}
