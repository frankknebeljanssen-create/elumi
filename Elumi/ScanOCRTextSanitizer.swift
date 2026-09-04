import Foundation

struct ScanOCRTextSanitizer {
    func sanitizedLine(_ line: String) -> String {
        normalizedParenthesisArtifacts(
            in: line
                .replacingOccurrences(of: #"^\s*[\d\.\-\)\(]+\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\s*[•·]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\b(p|pp|s|seite|page)\.?\s*\d+\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\b(no\s*pl\.?|n\.\s*pl\.?|no\s*plural)\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\b(v|adj|adv|n)\.\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func normalizedParenthesisArtifacts(in text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\s*\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\s+"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*to\)\s+"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(to\s+"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*to\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(to\)\s*\)+\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let protectedPrefix: String
        if normalized.lowercased() == "(to)" {
            return "(to)"
        } else if normalized.lowercased().hasPrefix("(to) ") {
            protectedPrefix = "(to) "
            normalized = String(normalized.dropFirst(5))
        } else {
            protectedPrefix = ""
        }

        let openCount = normalized.filter { $0 == "(" }.count
        let closeCount = normalized.filter { $0 == ")" }.count

        if openCount != closeCount {
            normalized = normalized
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
        }

        normalized = normalized
            .replacingOccurrences(of: #"(?u)^\(+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?u)\s*\)+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (protectedPrefix + normalized)
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
