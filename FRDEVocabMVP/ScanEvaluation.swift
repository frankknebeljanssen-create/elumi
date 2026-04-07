import Foundation

struct ScanEvalFixture: Identifiable {
    let id: String
    let title: String
    let sampleImagePaths: [String]
    let expectedDocumentTypes: Set<ScanDocumentType>
    let expectedMode: ScanMode?
    let minimumEntryCount: Int
    let minimumImportableEntryCount: Int
    let requiredCategories: Set<ScanLearningCategory>
    let requiredSourceFragments: [String]
    let requiredTargetFragments: [String]
    let requiredExactSourceEntries: [String]
    let requiredExactTargetEntries: [String]
    let forbiddenFragments: [String]
    let forbiddenExactEntries: [String]
}

struct ScanEvalReport {
    let fixtureID: String
    let title: String
    let passed: Bool
    let failures: [String]

    var summary: String {
        passed ? "PASS" : "FAIL: " + failures.joined(separator: " | ")
    }
}

struct ScanEvalSuiteReport {
    let fixtureImagePath: String?
    let reports: [ScanEvalReport]

    var passed: Bool {
        reports.allSatisfy(\.passed)
    }

    var passedCount: Int {
        reports.filter(\.passed).count
    }

    var failedCount: Int {
        reports.count - passedCount
    }

    var summary: String {
        guard !reports.isEmpty else { return "Keine passenden Scan-Fixtures gefunden." }
        if passed {
            return "PASS (\(passedCount)/\(reports.count))"
        }
        return "FAIL (\(failedCount)/\(reports.count))"
    }
}
