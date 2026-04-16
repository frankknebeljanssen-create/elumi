import SwiftUI

/// Einzige Quelle dafür, **welche** SVG-Icons für Module und Home-Elemente
/// verwendet werden. Die Icons sind Teil des Designsystems — SF-Symbols
/// sind für Modul-Darstellung **nicht** erlaubt. Alles geht über dieses
/// Enum, damit Mischungen aus Icon-Sets ausgeschlossen sind.
///
/// Assets werden als Imagesets in `Assets.xcassets` gehalten
/// (`HomeIcon<Name>.imageset`, @1x/@2x/@3x, transparenter Hintergrund).
enum HomeModuleIcon: String, CaseIterable, Hashable {
    case karteikarten
    case nomen
    case artikel
    case verben
    case verbformen
    case vokabeln
    case quiz
    /// Listen ist **kein** gleichwertiges Lernmodul. Wird nur in der
    /// Organisations-Zeile verwendet, nicht im Haupt-Grid.
    case listen

    /// Asset-Name im Catalog.
    var assetName: String {
        switch self {
        case .karteikarten: return "HomeIconKarteikarten"
        case .nomen:         return "HomeIconNomen"
        case .artikel:       return "HomeIconArtikel"
        case .verben:        return "HomeIconVerben"
        case .verbformen:    return "HomeIconVerbformen"
        case .vokabeln:      return "HomeIconVokabeln"
        case .quiz:          return "HomeIconQuiz"
        case .listen:        return "HomeIconListen"
        }
    }

    /// Menschlich lesbarer Titel (Default für Modul-Cards — kann lokal
    /// überschrieben werden, damit der Enum-Case nicht das Label diktiert).
    var defaultTitle: String {
        switch self {
        case .karteikarten: return "Karteikarten"
        case .nomen:         return "Nomen"
        case .artikel:       return "Artikel"
        case .verben:        return "Verben"
        case .verbformen:    return "Verbformen"
        case .vokabeln:      return "Vokabeln"
        case .quiz:          return "Quiz"
        case .listen:        return "Listen"
        }
    }
}

/// Einheitliche Render-Komponente für ein Modul-Icon. Immer als Image-Asset,
/// immer `scaledToFit` in einer quadratischen Bounding-Box — keine
/// zusätzlichen Shadows/Glows (die Icons bringen ihren Stil selbst mit).
struct HomeModuleIconView: View {
    let icon: HomeModuleIcon
    /// Side-length der Bounding-Box. Default 64 — entspricht der Design-
    /// Spec (64–72 pt im Modul-Grid).
    var size: CGFloat = 64

    var body: some View {
        Image(icon.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(icon.defaultTitle)
    }
}
