// ScanDraft.swift
// **Meine Scans — Phase A (2026-05-20)** — Persistierbarer Scan-Entwurf.
//
// Foundation-Layer für das „Meine Scans"-Feature: bündelt den Review-
// State eines Scans (die editierbaren `ImportPreviewPair`s) plus
// Referenzen auf die komprimierten Quell-Bilder. Die Bilder selbst
// liegen NICHT im Struct, sondern als JPEG-Dateien im
// `ScanDraftImageStore`; hier stehen nur die Dateinamen (`imageFilenames`).
//
// `Codable` für die Persistenz im `ScanDraftStore` (JSON, analog
// `VocabularyList`). `ImportPreviewPair` wurde dafür Codable gemacht.
//
// Kein UI, kein Auto-Wire zum bestehenden Scan-Flow — pure Foundation.

import Foundation

struct ScanDraft: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    /// Anzeige-Titel. Wird beim Erstellen mit `autoTitle(at:)` vorbelegt,
    /// falls leer übergeben (siehe `init`). Editierbar (`var`).
    var title: String

    /// Erstellzeitpunkt — unveränderlich.
    let createdAt: Date

    /// Letzte Änderung. Wird vom `ScanDraftStore.update(_:)` auf `.now`
    /// gesetzt.
    var updatedAt: Date

    /// Der editierbare Review-State (französisch/deutsch-Paare inkl.
    /// `isImportable`/`isReviewed`-Toggles). Direkt persistiert.
    var previewPairs: [ImportPreviewPair]

    /// Dateinamen der komprimierten Quell-Bilder im `ScanDraftImageStore`
    /// (NICHT die Bilddaten selbst). Schema: `scan-<draftID>-<idx>.jpg`.
    var imageFilenames: [String]

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        previewPairs: [ImportPreviewPair] = [],
        imageFilenames: [String] = []
    ) {
        self.id = id
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? Self.autoTitle(at: createdAt) : trimmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.previewPairs = previewPairs
        self.imageFilenames = imageFilenames
    }

    /// Generiert einen Default-Titel im Format „Scan TT.MM." (nur Datum —
    /// die Uhrzeit steht in der Card-Meta-Zeile, daher kein Duplikat im Titel).
    /// Deutsche Locale, damit Tag.Monat-Reihenfolge stimmt.
    static func autoTitle(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM."
        let datePart = formatter.string(from: date)
        return "Scan \(datePart)"
    }
}
