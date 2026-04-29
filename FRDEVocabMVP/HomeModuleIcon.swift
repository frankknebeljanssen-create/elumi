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
    /// Akzente — Modul für französische Akzente (é, è, ê, ç).
    case akzente
    /// Scan — Funktion (kein reines Lernmodul), aber jetzt als
    /// reguläre Home-Tile auf Seite 3 zusammen mit Listen.
    case scan

    /// Asset-Name im Catalog. **Stufe 6 Schritt 3 (2026-04-29)**:
    /// nach dem Imageset-Rename `*B.imageset` → `*.imageset` liefert
    /// `assetName` direkt den Base-Namen — kein Resolver, kein Suffix.
    var assetName: String {
        baseAssetName
    }

    /// Asset-Catalog-Name pro Enum-Case. Vor Stufe 6 gab es ein zweites
    /// Set mit `B`-Suffix, das zur Laufzeit per Resolver gewählt wurde;
    /// nach dem Set-A-Removal und dem B-Rename ist der Catalog flach
    /// und dieser Wert ist 1:1 der Asset-Name.
    private var baseAssetName: String {
        switch self {
        case .karteikarten: return "HomeIconKarteikarten"
        case .nomen:         return "HomeIconNomen"
        case .artikel:       return "HomeIconArtikel"
        case .verben:        return "HomeIconVerben"
        case .verbformen:    return "HomeIconVerbformen"
        case .vokabeln:      return "HomeIconVokabeln"
        case .quiz:          return "HomeIconQuiz"
        case .listen:        return "HomeIconListen"
        case .akzente:       return "HomeIconAkzente"
        case .scan:          return "HomeIconScan"
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
        case .akzente:       return "Akzente"
        case .scan:          return "Scan"
        }
    }

    /// Fallback-Glyph für Icons, die noch kein Asset haben. Aktuell
    /// nicht mehr genutzt — alle Icons haben reale Assets im Catalog.
    /// Bleibt als Hook für zukünftige Module, deren Asset noch fehlt.
    var fallbackGlyph: String? { nil }
}

/// Einheitliche Render-Komponente für ein Modul-Icon. Immer als Image-Asset,
/// immer `scaledToFit` in einer quadratischen Bounding-Box — keine
/// zusätzlichen Shadows/Glows (die Icons bringen ihren Stil selbst mit).
struct HomeModuleIconView: View {
    let icon: HomeModuleIcon
    /// Side-length der Bounding-Box. Default 64 — entspricht der Design-
    /// Spec (64–72 pt im Modul-Grid).
    var size: CGFloat = 64
    /// Tint, der nur für Fallback-Glyph-Icons (ohne Asset) genutzt wird.
    /// Normale Assets bringen ihren eigenen Stil mit.
    var glyphTint: Color = AppTheme.Colors.textPrimary

    /// **Live-Switch-Gate**: das `@AppStorage` zwingt SwiftUI, den View-
    /// Body neu zu evaluieren, sobald der User den Icon-Stil in den
    /// Settings ändert. Ohne diese Property würde nur der erste Render
    /// das aktuelle Set sehen — Settings-Wechsel wären erst nach
    /// App-Neustart sichtbar.
    @AppStorage(AppIconRegistry.storageKey) private var iconSetRaw: String = AppIconSet.a.rawValue

    var body: some View {
        if let glyph = icon.fallbackGlyph {
            // Fallback-Rendering für Icons ohne Asset (z. B. Akzente — bis
            // das Final-Icon geliefert wird). Text-basiert, gleiche Bounding-
            // Box wie ein echtes Asset — Layout-kompatibel.
            Text(glyph)
                .font(.system(size: size * 0.78, weight: .black, design: .rounded))
                .foregroundStyle(glyphTint)
                .frame(width: size, height: size)
                .accessibilityLabel(icon.defaultTitle)
        } else {
            Image(icon.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(icon.defaultTitle)
        }
    }
}
