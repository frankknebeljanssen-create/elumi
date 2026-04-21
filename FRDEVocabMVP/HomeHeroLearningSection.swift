import SwiftUI

/// **Hero-Lernsektion** auf dem Home-Screen (Home-Rebuild).
///
/// 2×2 Grid mit den vier wichtigsten Lernformaten — fest und in dieser
/// Reihenfolge:
///
///     [ Karteikarten ]   [ Nomen ]
///     [ Verben       ]   [ Quiz  ]
///
/// Keine Rotation, keine Pagination, keine Dots, kein Scroll. Die Hero-
/// Sektion ist die Hauptentscheidung des Screens und dadurch bewusst
/// statisch. Die übrigen Module (Artikel, Verbformen, Vokabeln, Akzente)
/// leben in `HomeMoreExercisesSection` darunter — der Filter dort zieht
/// `heroModules` heraus, damit keine Dopplungen entstehen.
struct HomeHeroLearningSection: View {

    /// Tap-Handler liefert das gewählte Modul → der Aufrufer (HomeView)
    /// mappt das auf eine `AppScreen`-Route. Section selbst kennt das
    /// Routing nicht.
    let onSelect: (HomeHeroModule) -> Void

    /// Feste Hero-Reihenfolge. Einzige Quelle der Wahrheit — der Filter
    /// in `HomeMoreExercisesSection` liest hier, um Dopplungen zu
    /// vermeiden.
    static let heroModules: [HomeHeroModule] = [
        .karteikarten, .nomen, .verben, .quiz
    ]

    /// 2 gleich breite Spalten — `.flexible()` teilt die Screen-Breite
    /// symmetrisch, Spacing 10 pt zwischen den Spalten.
    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.setupHeadlineToContentSpacing) {
            // Hauptheadline — klar dominant gegenüber den Sektions-
            // Headlines darunter. 20 → 22 pt, .black bleibt.
            Text("Was möchtest du heute lernen?")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(Self.heroModules) { module in
                    HeroModuleCard(module: module, onTap: { onSelect(module) })
                }
            }
        }
    }
}

// MARK: - HomeHeroModule

/// Modul-Identität für die Hero-Sektion. Eigenes Enum, damit die
/// Section nicht auf `HomeModuleIcon` direkt arbeiten muss — Mapping
/// auf Icon + Title + Color + Route lebt zentral in den Properties.
enum HomeHeroModule: String, Identifiable, CaseIterable {
    case karteikarten
    case nomen
    case artikel
    case verben
    case verbformen
    case vokabeln
    case quiz
    case akzente

    var id: String { rawValue }

    var title: String {
        switch self {
        case .karteikarten: return "Karteikarten"
        case .nomen:        return "Nomen"
        case .artikel:      return "Artikel"
        case .verben:       return "Verben"
        case .verbformen:   return "Verbformen"
        case .vokabeln:     return "Vokabeln"
        case .quiz:         return "Quiz"
        case .akzente:      return "Akzente"
        }
    }

    var icon: HomeModuleIcon {
        switch self {
        case .karteikarten: return .karteikarten
        case .nomen:        return .nomen
        case .artikel:      return .artikel
        case .verben:       return .verben
        case .verbformen:   return .verbformen
        case .vokabeln:     return .vokabeln
        case .quiz:         return .quiz
        case .akzente:      return .akzente
        }
    }

    var accent: Color {
        switch self {
        case .karteikarten: return AppTheme.Colors.moduleFlashcards
        case .nomen:        return AppTheme.Colors.moduleNomen
        case .artikel:      return AppTheme.Colors.moduleArticles
        case .verben:       return AppTheme.Colors.moduleVerbs
        case .verbformen:   return AppTheme.Colors.moduleVerbforms
        case .vokabeln:     return AppTheme.Colors.moduleVocabulary
        case .quiz:         return AppTheme.Colors.moduleQuiz
        case .akzente:      return AppTheme.Colors.moduleAccents
        }
    }

    /// Welcher AppScreen soll geöffnet werden? — wird vom Aufrufer
    /// genutzt, damit `HomeHeroLearningSection` Navigation-frei bleibt.
    var screen: AppScreen {
        switch self {
        case .karteikarten: return .flashcards(nil)
        case .nomen:        return .train(TrainingLaunchContext(preferredMode: .nouns))
        case .artikel:      return .train(TrainingLaunchContext(preferredMode: .articles))
        case .verben:       return .train(TrainingLaunchContext(preferredMode: .verbs))
        case .verbformen:   return .train(TrainingLaunchContext(preferredMode: .verbforms))
        case .vokabeln:     return .train(TrainingLaunchContext(preferredMode: .vocabulary))
        case .quiz:         return .quiz(nil)
        case .akzente:      return .accents(nil)
        }
    }
}

// MARK: - HeroModuleCard (quadratisch, XL)

/// Eine Hero-Card im 2×2 Grid. Sizing-Trick: `Color.clear` mit
/// `aspectRatio(1, .fit)` gibt dem Cell-Frame eine zuverlässige 1:1-
/// Kontur (die LazyVGrid-Zellenbreite diktiert Höhe = Breite). Das
/// VStack-Content liegt als Overlay darüber und nimmt genau diese
/// Quadratfläche ein — so ist die Card unabhängig von Icon-/Text-
/// Größen wirklich quadratisch. Inhalt: großes Icon + Label, keine
/// Subtexte.
private struct HeroModuleCard: View {
    let module: HomeHeroModule
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // 1.3 → 1.15 (mehr Höhe, Cards bekommen wieder mehr
            // Präsenz — User-Wunsch „leicht mehr Höhe zulassen").
            Color.clear
                .aspectRatio(1.15, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        HomeModuleIconView(
                            icon: module.icon,
                            size: 95,
                            glyphTint: .white
                        )
                        Text(module.title)
                            // +1 pt (17/18 → 18/19). Karteikarten bleibt
                            // 1 pt unter den anderen, weil das längere
                            // Wort sonst den minimumScaleFactor triggert.
                            .font(.system(
                                size: module == .karteikarten ? 18 : 19,
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                // **Gradient-Background** (User-Spec): subtiler
                // LinearGradient mit 0.95 → 0.75 Opacity vom
                // topLeading nach bottomTrailing. Keine harten
                // Flächen-Trennungen mehr, nur ein weicher Verlauf.
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    module.accent.opacity(0.95),
                                    module.accent.opacity(0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                // Leichtes Depth-Overlay (User-Option 8) — minimale
                // Aufhellung, damit die Fläche nicht komplett flach
                // wirkt, aber ohne harte Kante.
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
