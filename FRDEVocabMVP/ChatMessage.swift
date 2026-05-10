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
//
// **Schritt 2A (2026-05-10) — Korrektur-Felder:**
// `foundErrorUserText` + `foundErrorGermanTip` + `correctionCardId` sind
// optional und werden NUR auf User-Messages gesetzt, deren Antwort von
// Léa eine Korrektur-Marker enthielt. Lightweight-Migration: SwiftData
// fügt die neuen optionalen Spalten beim ersten Boot automatisch hinzu,
// vorhandene Records werden mit nil befüllt — kein Schema-Bump nötig.
//
// Wiring:
//   • `foundErrorUserText`: der exakte Sub-String aus der User-Message,
//     den Léa als Fehler markiert hat (aus dem `[FEHLER: …]`-Marker).
//     Wird vom Bubble-Renderer für die Underline-Span benutzt.
//   • `foundErrorGermanTip`: Léas deutsche Erklärung. Wird in der
//     CorrectionCardView gerendert.
//   • `correctionCardId`: stabile ID, damit ChatView die zugehörige
//     CorrectionCardView identifizieren und animieren kann (slide-in
//     einmalig beim ersten Render).

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

    /// **Schritt 2A** — exakter User-Text, der von Léa als Fehler markiert
    /// wurde. Nur auf User-Messages gesetzt, sonst `nil`.
    var foundErrorUserText: String?

    /// **Schritt 2A** — deutsche Erklärung aus Léas `Kleiner Tipp:`.
    /// Nur auf User-Messages gesetzt, sonst `nil`. Wird in der
    /// `CorrectionCardView` gerendert (zwischen User-Bubble und Léa-
    /// Bubble eingeblendet).
    var foundErrorGermanTip: String?

    /// **Schritt 2A** — stabile ID für die CorrectionCard, die zwischen
    /// dieser User-Message und Léas Antwort eingeblendet wird. Nötig
    /// für SwiftUI-Identity (`.id(...)`) damit Slide-In-Animation
    /// einmalig spielt und nicht bei jedem Re-Render.
    var correctionCardId: UUID?

    init(
        id: UUID = UUID(),
        sessionId: UUID = ChatMessage.defaultSessionID,
        sender: ChatSender,
        text: String,
        timestamp: Date = .now,
        foundErrorUserText: String? = nil,
        foundErrorGermanTip: String? = nil,
        correctionCardId: UUID? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.senderRawValue = sender.rawValue
        self.text = text
        self.timestamp = timestamp
        self.foundErrorUserText = foundErrorUserText
        self.foundErrorGermanTip = foundErrorGermanTip
        self.correctionCardId = correctionCardId
    }

    /// Nicht-persistierter Convenience-Getter für den Sender-Enum.
    /// Fallback `.lea`, falls jemand jemals einen ungültigen Raw-Value
    /// in die DB schmuggelt — defensiv gegen Datenkorruption.
    var sender: ChatSender {
        ChatSender(rawValue: senderRawValue) ?? .lea
    }

    /// Convenience: hat diese Message eine Korrektur-Annotation?
    /// Wird von ChatView genutzt, um zu entscheiden ob direkt nach
    /// dieser User-Bubble eine CorrectionCard gerendert wird.
    var hasCorrection: Bool {
        foundErrorUserText != nil && foundErrorGermanTip != nil
    }

    /// Single-Session-UUID für Schritt-1-MVP (eine Léa-Konversation pro
    /// User). Bei Multi-Persona / Multi-Session-Erweiterung wird diese
    /// Konstante durch echte Session-UUIDs aus einem Sessions-Store
    /// ersetzt.
    static let defaultSessionID: UUID =
        UUID(uuidString: "DEAFB00B-1EA0-1EA0-1EA0-000000000001")!
}
