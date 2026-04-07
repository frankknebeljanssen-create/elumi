import Foundation

extension AIScanProvider {
    func aiNormalizedLookupText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"[^a-zA-Z0-9+' ]+"#, with: " ", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func aiCompactLookupKey(_ text: String) -> String {
        aiNormalizedLookupText(text)
            .replacingOccurrences(of: " ", with: "")
    }

    func aiNormalizedWords(_ text: String) -> [String] {
        aiNormalizedLookupText(text)
            .split(separator: " ")
            .map(String.init)
    }

    func aiLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)

        for i in 0...left.count { dist[i][0] = i }
        for j in 0...right.count { dist[0][j] = j }

        guard !left.isEmpty, !right.isEmpty else {
            return max(left.count, right.count)
        }

        for i in 1...left.count {
            for j in 1...right.count {
                if left[i - 1] == right[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return dist[left.count][right.count]
    }
}
