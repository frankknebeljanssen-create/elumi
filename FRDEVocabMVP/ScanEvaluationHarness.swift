import Foundation

enum ScanEvaluationHarness {
    static func evaluate(
        _ result: ScanProviderResult,
        against fixture: ScanEvalFixture
    ) -> ScanEvalReport {
        let sourceTexts = result.entries.map(\.source)
        let targetTexts = result.entries.map(\.target)
        let entryTexts = sourceTexts + targetTexts
        let normalizedEntryTexts = entryTexts.map(normalizedText)
        let normalizedExactEntryTexts = Set(entryTexts.map(normalizedExactText))
        let normalizedExactSourceTexts = Set(sourceTexts.map(normalizedExactText))
        let normalizedExactTargetTexts = Set(targetTexts.map(normalizedExactText))
        let importableEntries = result.entries.filter(\.reviewMetadata.isImportable)
        let categories = Set(result.entries.compactMap(\.reviewMetadata.learningCategory))

        var failures: [String] = []

        if !fixture.expectedDocumentTypes.isEmpty && !fixture.expectedDocumentTypes.contains(result.documentType) {
            failures.append("document_type=\(result.documentType.rawValue)")
        }

        if let expectedMode = fixture.expectedMode, result.mode != expectedMode {
            failures.append("mode=\(result.mode.rawValue)")
        }

        if result.entries.count < fixture.minimumEntryCount {
            failures.append("entries=\(result.entries.count)")
        }

        if importableEntries.count < fixture.minimumImportableEntryCount {
            failures.append("importable=\(importableEntries.count)")
        }

        let missingCategories = fixture.requiredCategories.subtracting(categories)
        if !missingCategories.isEmpty {
            let categoryNames = missingCategories.map(\.rawValue).sorted().joined(separator: ",")
            failures.append("missing_categories=\(categoryNames)")
        }

        for fragment in fixture.requiredSourceFragments {
            if !normalizedEntryTexts.contains(where: { $0.contains(normalizedText(fragment)) }) {
                failures.append("missing_source=\(fragment)")
            }
        }

        for fragment in fixture.requiredTargetFragments {
            if !normalizedEntryTexts.contains(where: { $0.contains(normalizedText(fragment)) }) {
                failures.append("missing_target=\(fragment)")
            }
        }

        for entry in fixture.requiredExactSourceEntries {
            if !normalizedExactSourceTexts.contains(normalizedExactText(entry)) {
                failures.append("missing_source_exact=\(entry)")
            }
        }

        for entry in fixture.requiredExactTargetEntries {
            if !normalizedExactTargetTexts.contains(normalizedExactText(entry)) {
                failures.append("missing_target_exact=\(entry)")
            }
        }

        for fragment in fixture.forbiddenFragments {
            if normalizedEntryTexts.contains(where: { $0.contains(normalizedText(fragment)) }) {
                failures.append("forbidden=\(fragment)")
            }
        }

        for entry in fixture.forbiddenExactEntries {
            if normalizedExactEntryTexts.contains(normalizedExactText(entry)) {
                failures.append("forbidden_exact=\(entry)")
            }
        }

        return ScanEvalReport(
            fixtureID: fixture.id,
            title: fixture.title,
            passed: failures.isEmpty,
            failures: failures
        )
    }

    static func evaluateAll(
        _ result: ScanProviderResult,
        fixtures: [ScanEvalFixture] = ScanEvaluationFixtures.core
    ) -> [ScanEvalReport] {
        fixtures.map { evaluate(result, against: $0) }
    }

    static func evaluate(
        _ result: ScanProviderResult,
        matchingFixtureImagePath imagePath: String,
        fixtures: [ScanEvalFixture] = ScanEvaluationFixtures.core
    ) -> ScanEvalSuiteReport {
        let matchingFixtures = ScanEvaluationFixtures.matchingFixtures(
            forImagePath: imagePath,
            fixtures: fixtures
        )

        return ScanEvalSuiteReport(
            fixtureImagePath: imagePath,
            reports: evaluateAll(result, fixtures: matchingFixtures)
        )
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedExactText(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"([?!.,;:])"#, with: " $1 ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
