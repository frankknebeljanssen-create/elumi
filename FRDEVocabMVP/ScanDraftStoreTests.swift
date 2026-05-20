// ScanDraftStoreTests.swift
// **Meine Scans — Phase A (2026-05-20)** — Boot-Self-Test für den
// ScanDraft-Foundation-Layer. Folgt dem Projekt-Muster (kein XCTest-
// Target; DEBUG-only Self-Test der beim App-Start einmalig durchläuft
// und in die Konsole reportet — vgl. `ArticleModeClassifierTests`).
//
// **Architektur-Entscheidung (Pattern-Match-Default):** Die Tests fahren
// gegen den `ScanDraftStoreRepository` (synchron, deterministisch) statt
// gegen den `@MainActor`-Store mit debounced/async Save — so bleibt der
// Boot-Self-Test ohne MainActor-Hop und ohne Timing-Warterei. Der Store
// ist ein dünner Wrapper über genau dieses Repository. Isolation: ein
// zufälliger Test-Account-Scope, damit echte User-Drafts nie berührt
// werden; alle Test-Dateien werden am Ende aufgeräumt.

import Foundation
import UIKit

#if DEBUG

enum ScanDraftStoreTests {

    private static var didRun = false

    static func runIfNeeded() {
        guard !didRun else { return }
        didRun = true
        runAllTests()
    }

    static func runAllTests() {
        var passed = 0
        var failed = 0
        var failures: [String] = []

        func check(_ condition: Bool, _ label: String, line: UInt = #line) {
            if condition {
                passed += 1
            } else {
                failed += 1
                failures.append("L\(line): \(label)")
            }
        }

        // Test-isolierter Account-Scope → eigene Dateinamen, keine
        // Kollision mit echten Drafts.
        let testAccountID = UUID()
        let testKey = "FRDEVocabMVP.scanDrafts.test.\(testAccountID.uuidString)"
        let mainFileName = "scan-drafts-v1-\(testAccountID.uuidString).json"
        let lkgFileName = "scan-drafts-v1-\(testAccountID.uuidString).lastKnownGood.json"

        let repository = ScanDraftStoreRepository()
        repository.setCurrentAccount(testAccountID)

        let draftAID = UUID()
        let imageDraftID = UUID()
        let lkgDraftID = UUID()

        func cleanup() {
            AppPersistenceSupport.removeData(named: mainFileName)
            AppPersistenceSupport.removeData(named: lkgFileName)
            UserDefaults.standard.removeObject(forKey: testKey)
            try? ScanDraftImageStore.deleteAll(forDraftID: draftAID)
            try? ScanDraftImageStore.deleteAll(forDraftID: imageDraftID)
            try? ScanDraftImageStore.deleteAll(forDraftID: lkgDraftID)
        }

        // ── Test 1: Save→Load-Roundtrip ohne Bilder ──
        let pair1 = ImportPreviewPair(french: "le chat", german: "die Katze")
        let pair2 = ImportPreviewPair(french: "la maison", german: "das Haus")
        let draftA = ScanDraft(
            id: draftAID,
            title: "Test A",
            previewPairs: [pair1, pair2],
            imageFilenames: []
        )
        repository.persistDrafts([draftA], key: testKey)
        repository.invalidateCache()
        let loadedA = repository.loadDrafts(legacyKey: testKey)
        check(loadedA.count == 1, "roundtrip: 1 draft")
        check(loadedA.first?.id == draftAID, "roundtrip: id matches")
        check(loadedA.first?.previewPairs.count == 2, "roundtrip: 2 pairs")
        check(loadedA.first?.previewPairs.first?.french == "le chat", "roundtrip: pair french preserved")
        check(loadedA.first?.previewPairs.first?.isImportable == true, "roundtrip: toggle state preserved")

        // ── Test 2: Bild speichern → laden ──
        let testImage = solidImage(color: .black, size: CGSize(width: 1, height: 1))
        var savedImageName: String?
        do {
            let name = try ScanDraftImageStore.save(testImage, draftID: imageDraftID, index: 0)
            savedImageName = name
            check(name == "scan-\(imageDraftID.uuidString)-0.jpg", "image: filename scheme")
            check(ScanDraftImageStore.loadImage(filename: name) != nil, "image: loads back non-nil")
        } catch {
            check(false, "image: save threw \(error)")
        }

        // ── Test 3: deleteAll löscht Bild-Dateien ──
        if let name = savedImageName {
            check(ScanDraftImageStore.loadImage(filename: name) != nil, "delete: image present before")
            try? ScanDraftImageStore.deleteAll(forDraftID: imageDraftID)
            check(ScanDraftImageStore.loadImage(filename: name) == nil, "delete: image gone after deleteAll")
        }

        // ── Test 4: Last-Known-Good-Recovery ──
        let draftB = ScanDraft(id: lkgDraftID, title: "Test B", previewPairs: [pair1], imageFilenames: [])
        repository.persistDrafts([draftB], key: testKey) // schreibt non-empty → LKG befüllt
        // Hauptdatei korrumpieren:
        AppPersistenceSupport.writeData(Data("{ corrupt".utf8), named: mainFileName)
        repository.invalidateCache()
        let recovered = repository.loadDrafts(legacyKey: testKey)
        check(recovered.count == 1 && recovered.first?.id == lkgDraftID, "LKG: recovered draft B after main-file corruption")

        cleanup()

        if failed == 0 {
            appDebugLog("✅ [ScanDraftStoreTests] alle \(passed) Selbst-Tests bestanden")
        } else {
            appDebugLog("❌ [ScanDraftStoreTests] \(failed)/\(passed + failed) gefailt:")
            for failure in failures {
                appDebugLog("   FAIL \(failure)")
            }
            assertionFailure("ScanDraftStoreTests: \(failed) Fehler — siehe Konsole")
        }
    }

    /// Erzeugt ein einfarbiges Test-Bild (für den Bild-Roundtrip).
    private static func solidImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

#endif
