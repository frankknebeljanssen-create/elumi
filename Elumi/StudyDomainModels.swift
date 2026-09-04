import Foundation

private func quizHeartsAward(for wrongCount: Int) -> Int {
    switch wrongCount {
    case ..<1:
        return 3
    case 1:
        return 2
    case 2:
        return 1
    default:
        return 0
    }
}

extension Sequence {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct ScoreResult {
    let label: String
    let detail: String
}
