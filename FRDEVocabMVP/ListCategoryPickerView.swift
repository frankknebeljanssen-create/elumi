import SwiftUI

/// Shared 4-card list category picker used across Training, Flashcards, and Quiz setup screens.
struct ListCategoryPickerView: View {
    let availableLists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let accent: Color
    let style: AppSectionStyle
    let feedbackPlayer: FeedbackPlayer
    let summaryText: String
    let onSelectionChanged: (Set<UUID>) -> Void

    enum Category: Identifiable {
        case own, level, topic, all
        var id: String {
            switch self {
            case .own: return "own"
            case .level: return "level"
            case .topic: return "topic"
            case .all: return "all"
            }
        }
    }

    @State private var activeCategory: Category?

    private var ownLists: [VocabularyList] {
        availableLists.filter { !$0.isBuiltIn || $0.isAggregateVocabulary }
    }

    private var levelLists: [VocabularyList] {
        availableLists.filter { $0.collectionPreset == .standardLevel }
    }

    private var topicLists: [VocabularyList] {
        availableLists.filter { $0.collectionPreset == .standardTopic }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Listen auswählen")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                categoryButton(
                    title: "📝 Meine Listen",
                    count: ownLists.count,
                    category: .own
                )
                categoryButton(
                    title: "📚 Nach Niveau",
                    count: levelLists.count,
                    category: .level
                )
            }

            HStack(spacing: 8) {
                categoryButton(
                    title: "🏷️ Nach Thema",
                    count: topicLists.count,
                    category: .topic
                )
                categoryButton(
                    title: "📖 Komplett",
                    count: 1,
                    category: .all
                )
            }

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .sheet(item: $activeCategory) { category in
            FlashcardStackComposerSheet(
                style: style,
                lists: listsForCategory(category),
                selectedListIDs: selectedListIDs,
                language: .french,
                cardTypeFilter: nil
            ) { updatedSelection in
                onSelectionChanged(updatedSelection)
                activeCategory = nil
            }
        }
    }

    private func listsForCategory(_ category: Category) -> [VocabularyList] {
        switch category {
        case .own: return ownLists
        case .level: return levelLists
        case .topic: return topicLists
        case .all: return [StandardVocabularyLoader.allInOneList]
        }
    }

    private func categoryButton(title: String, count: Int, category: Category) -> some View {
        let hasSelected = !selectedListIDs.isEmpty && {
            let filtered = listsForCategory(category)
            return filtered.contains { selectedListIDs.contains($0.id) }
        }()

        return Button {
            feedbackPlayer.playTabSwitch()
            activeCategory = category
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(hasSelected ? accent.opacity(0.12) : accent.opacity(0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(hasSelected ? accent.opacity(0.4) : AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
