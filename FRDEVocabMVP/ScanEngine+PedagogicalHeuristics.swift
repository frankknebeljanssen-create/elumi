import Foundation

extension ScanAnalysisEngine {
    func looksLikePedagogicalTextbookLayout(_ result: ScanProviderResult) -> Bool {
        guard !result.recognizedBoxes.isEmpty else { return false }

        let lineDensity = Double(result.recognizedLineCount) / Double(max(result.entries.count, 1))
        guard lineDensity >= 1.35 else { return false }

        let normalizedTexts = result.recognizedBoxes.map { normalizedPedagogicalProbeText($0.text) }
        let pedagogicalMarkerCount = normalizedTexts.filter {
            $0.contains("fam") || $0.contains("adj") || $0.contains("inv") || $0.contains("name")
        }.count
        let textbookHeadingCount = normalizedTexts.filter {
            $0.hasPrefix("c est parti") ||
            $0.contains("tu tappelles comment") ||
            $0 == "ca va" ||
            $0 == "ca va ?"
        }.count
        let rightDialogueCount = result.recognizedBoxes.filter { box in
            guard box.minX >= 0.58 else { return false }
            let text = box.text
            return text.contains("?") || text.contains("!") || text.contains("—") || text.contains(" - ")
        }.count

        return textbookHeadingCount >= 1 ||
            pedagogicalMarkerCount >= 3 ||
            (pedagogicalMarkerCount >= 2 && lineDensity >= 1.45) ||
            (rightDialogueCount >= 1 && lineDensity >= 1.45) ||
            (rightDialogueCount >= 2 && lineDensity >= 1.35)
    }

    func normalizedPedagogicalProbeText(_ text: String) -> String {
        text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
