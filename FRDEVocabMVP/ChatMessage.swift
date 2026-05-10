// ChatMessage.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — SwiftData-Model für eine
// einzelne Chat-Nachricht (User oder Léa). Persistiert lokal über die
// SwiftData-ModelContainer-Wiring in `FRDEVocabMVPApp.swift`.
//
// Schritt 1 nutzt eine einzige hardcodierte `defaultSessionID`; spätere
// Iterationen führen Multi-Persona / Multi-Session-Logic auf demselben
// Schema ein (eine UUID pro Persona-Konversation).
//
// `senderRawValue` ist als String persistiert, weil SwiftData (iOS 17)
// keine native Enum-Persistenz für Codable-Enums unterstützt — wir
// mappen via Computed-Property `sender`.

import Foundation
import SwiftData

enum ChatSender: String, Codable, CaseIterable {
    case user
    case lea
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var senderRawValue: String
    var text: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID = ChatMessage.defaultSessionID,
        sender: ChatSender,
        text: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.sessionId = sessionId
        self.senderRawValue = sender.rawValue
        self.text = text
        self.timestamp = timestamp
    }

    /// Nicht-persistierter Convenience-Getter für den Sender-Enum.
    /// Fallback `.lea`, falls jemand jemals einen ungültigen Raw-Value
    /// in die DB schmuggelt — defensiv gegen Datenkorruption.
    var sender: ChatSender {
        ChatSender(rawValue: senderRawValue) ?? .lea
    }

    /// Single-Session-UUID für Schritt-1-MVP (eine Léa-Konversation pro
    /// User). Bei Multi-Persona / Multi-Session-Erweiterung wird diese
    /// Konstante durch echte Session-UUIDs aus einem Sessions-Store
    /// ersetzt.
    static let defaultSessionID: UUID =
        UUID(uuidString: "DEAFB00B-1EA0-1EA0-1EA0-000000000001")!
}
