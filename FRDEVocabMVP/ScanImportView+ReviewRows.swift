import SwiftUI

extension ScanImportView {
    @ViewBuilder
    func editablePreviewRow(
        for pair: ImportPreviewPair,
        category: ScanLearningCategory? = nil
    ) -> some View {
        let assessment = previewAssessment(for: pair)
        ScanEditablePreviewRowView(
            pair: pair,
            assessment: assessment,
            sourceLanguageLabel: scanSourceLanguage.rawValue,
            cardTypeTint: pair.cardType == .phrases ? AppTheme.Colors.moduleQuiz : sectionStyle.accent,
            category: category,
            categoryTint: category.map(learningCategoryTint),
            sourceText: Binding(
                get: { bindingValue(for: pair.id)?.french ?? "" },
                set: { newValue in
                    updatePreviewPairForEditing(pair.id) {
                        $0.french = extractedDisplayTerm(from: newValue)
                        $0.isReviewed = false
                    }
                    schedulePreviewEditCommit()
                }
            ),
            targetText: Binding(
                get: { bindingValue(for: pair.id)?.german ?? "" },
                set: { newValue in
                    updatePreviewPairForEditing(pair.id) {
                        $0.german = extractedDisplayTerm(from: newValue)
                        $0.isReviewed = false
                    }
                    schedulePreviewEditCommit()
                }
            ),
            focusedReviewField: $focusedReviewField,
            sourceFieldID: reviewFieldScrollID(for: .source(pair.id)),
            targetFieldID: reviewFieldScrollID(for: .target(pair.id)),
            onMarkReviewed: {
                updatePreviewPair(pair.id) { $0.isReviewed = true }
                focusedReviewField = nil
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            },
            onDelete: {
                previewPairPendingDeletion = pair
            },
            note: pair.note,
            // Wortart inkl. Verb-Infinitiv ("Verb (être)") — gleiche Logik
            // wie der Fullscreen-Review-Sheet, damit der Inline-Review
            // konsistent ist und das Lemma sichtbar bleibt.
            wordClassLabel: reviewWordClassLabel(for: pair),
            wordClassColor: reviewWordClassColor(for: pair)
        )
    }

    func recognizedTextPreviewRow(
        for pair: ImportPreviewPair,
        category: ScanLearningCategory
    ) -> some View {
        ScanRecognizedTextPreviewRowView(
            pair: pair,
            categoryTitle: category.title,
            categoryTint: learningCategoryTint(category)
        )
    }
}
