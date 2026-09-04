// ScanDraftImageStore.swift
// **Meine Scans — Phase A (2026-05-20)** — File-Storage für die
// komprimierten Quell-Bilder eines `ScanDraft`.
//
// Bilder werden als JPEG im selben Persistence-Verzeichnis wie die
// Listen-/Draft-JSONs abgelegt (`AppPersistenceSupport`). Speicher-
// schonend: max 800 px Längskante, JPEG 0.5; wenn das immer noch
// > 80 KB ist, nochmal auf 600 px runter. Dateiname-Schema:
// `scan-<draftID>-<index>.jpg`.
//
// Kein Observation, kein State — pure static API.

import UIKit

enum ScanDraftImageStore {
    enum StoreError: Error {
        case encodingFailed
    }

    // Tuning (Phase-A-Spec): 800 px primär, 600 px Fallback, JPEG 0.5,
    // 80-KB-Schwelle für den zweiten Downscale-Pass.
    private static let primaryLongEdge: CGFloat = 800
    private static let fallbackLongEdge: CGFloat = 600
    private static let jpegQuality: CGFloat = 0.5
    private static let sizeThresholdBytes = 80 * 1024

    /// Dateiname-Schema für ein Draft-Bild.
    static func filename(draftID: UUID, index: Int) -> String {
        "scan-\(draftID.uuidString)-\(index).jpg"
    }

    /// Komprimiert und speichert `image`; gibt den erzeugten Dateinamen
    /// zurück (für `ScanDraft.imageFilenames`).
    @discardableResult
    static func save(_ image: UIImage, draftID: UUID, index: Int) throws -> String {
        let name = filename(draftID: draftID, index: index)

        let primary = DownscaleImageHelper.downscaled(image, maxLongEdge: primaryLongEdge)
        var data = primary.jpegData(compressionQuality: jpegQuality)

        if let current = data, current.count > sizeThresholdBytes {
            let smaller = DownscaleImageHelper.downscaled(image, maxLongEdge: fallbackLongEdge)
            data = smaller.jpegData(compressionQuality: jpegQuality)
        }

        guard let finalData = data else {
            appDebugLog("🖼 [ScanDraftImageStore] ❌ JPEG-Encoding fehlgeschlagen für \(name)")
            throw StoreError.encodingFailed
        }

        AppPersistenceSupport.writeData(finalData, named: name)
        appDebugLog("🖼 [ScanDraftImageStore] saved \(name) (\(finalData.count) bytes)")
        return name
    }

    /// Lädt ein gespeichertes Bild; `nil`, wenn die Datei fehlt oder
    /// nicht dekodierbar ist.
    static func loadImage(filename: String) -> UIImage? {
        guard let data = AppPersistenceSupport.readDataIfFileExists(named: filename) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// Löscht eine einzelne Bild-Datei.
    static func delete(filename: String) throws {
        AppPersistenceSupport.removeData(named: filename)
        appDebugLog("🖼 [ScanDraftImageStore] deleted \(filename)")
    }

    /// Löscht ALLE Bild-Dateien eines Drafts (Prefix-Match im
    /// Persistence-Verzeichnis). Wird vom `ScanDraftStore.remove(_:)`
    /// gerufen. Robust gegen Orphans: löscht alles mit passendem
    /// `scan-<draftID>-`-Prefix und `.jpg`-Endung, unabhängig vom Index.
    static func deleteAll(forDraftID draftID: UUID) throws {
        let prefix = "scan-\(draftID.uuidString)-"
        // Persistence-Verzeichnis über den öffentlichen dataURL-Accessor
        // ableiten (AppPersistenceSupport hält das Verzeichnis privat).
        let directory = AppPersistenceSupport
            .dataURL(named: "directory-probe")
            .deletingLastPathComponent()

        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }

        var deletedCount = 0
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".jpg") {
            AppPersistenceSupport.removeData(named: name)
            deletedCount += 1
        }
        appDebugLog("🖼 [ScanDraftImageStore] deleteAll draft \(draftID.uuidString): \(deletedCount) Datei(en)")
    }
}
