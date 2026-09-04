import Foundation

struct ScanPreviewTextBridgeDependencies {
    let parsePreviewPairs: (String) -> [ImportPreviewPair]
    let normalizedPreviewPair: (ImportPreviewPair) -> ImportPreviewPair
}

struct ScanPreviewTextBridge {
    let dependencies: ScanPreviewTextBridgeDependencies

    func previewPairs(from importText: String) -> [ImportPreviewPair] {
        dependencies.parsePreviewPairs(importText)
    }

    func importText(from previewPairs: [ImportPreviewPair]) -> String {
        previewPairs
            .filter(\.isImportable)
            .map { pair in
                let normalizedPair = dependencies.normalizedPreviewPair(pair)
                let french = normalizedPair.french
                let german = normalizedPair.german

                if !french.isEmpty && !german.isEmpty {
                    return "\(french) = \(german)"
                }

                return !french.isEmpty ? french : german
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
