import SwiftUI

/// Zentraler Namespace für die **Cartoon-Icon-Familie** außerhalb des Home-
/// Grids. SF-Symbols dürfen in großen Icon-Slots (≥24 pt) nicht mehr
/// eingesetzt werden — stattdessen wird über `ElumiIcon` referenziert, damit
/// Icon-Sets nicht mischbar sind.
///
/// Assets liegen als Imagesets in `Assets.xcassets` (`Icon<Name>.imageset`,
/// SVG mit `preserves-vector-representation = true` und
/// `template-rendering-intent = original`). Das `original` ist bewusst
/// gewählt: die Cartoon-Icons bringen ihre Farbigkeit selbst mit und dürfen
/// **nicht** durch `foregroundStyle` umgefärbt werden.
///
/// Für die Pendants, die im Home-Modul-Grid erscheinen, siehe
/// `HomeModuleIcon`.
enum ElumiIcon: String, CaseIterable, Hashable {
    // MARK: Training / Vokabel-Aktionen
    /// Spracheingabe-Button (Mikrofon). Ersetzt `mic.fill` in großen Slots.
    case mikrofon
    /// Tastatur-Eingabe-Button. Ersetzt `keyboard`.
    case tastatur
    /// TTS-Vorlese-Button. Ersetzt `speaker.wave.2.fill` nur im
    /// Vorlese-Kontext (nicht im Settings-Toggle).
    case lautsprecher
    /// „Nächstes Wort" / Karte überspringen. Ersetzt `arrow.right` **nur**
    /// in Trainings-Kontexten (Flashcards/Session), nicht in generischer
    /// Navigation.
    case naechstesWort
    /// „Lösung anzeigen". Ersetzt Kontext-SF-Symbole für Lösung/Antwort.
    case loesung
    /// „Ganzes Wörterbuch". Ersetzt `book.fill` im Wörterbuch-Einstieg.
    case woerterbuch

    // MARK: App-Chrome
    /// Info-Hinweis. Ersetzt `info.circle.fill` in großen Slots (Info-Modal-
    /// Header, Settings-Eintrag). In kleinen Slots (Top-Bar-Badge) bleibt das
    /// SF-Symbol erhalten.
    case info
    /// „Mein Konto". Ersetzt `person.crop.circle` in großen Slots.
    case meinKonto
    /// Elumi-Spiel-Einstieg. Für den Arcade-Launcher im Home-Bereich.
    case elumiSpiel
    /// Ton-Toggle EIN (Settings). Ersetzt `speaker.wave.2.fill` im
    /// Settings-Toggle-Kontext.
    case lautsprecherOn
    /// Ton-Toggle AUS (Settings). Ersetzt `speaker.slash.fill` im
    /// Settings-Toggle-Kontext.
    case lautsprecherOff

    /// Asset-Name im Catalog.
    var assetName: String {
        switch self {
        case .mikrofon:          return "IconMikrofon"
        case .tastatur:          return "IconTastatur"
        case .lautsprecher:      return "IconLautsprecher"
        case .naechstesWort:     return "IconNaechstesWort"
        case .loesung:           return "IconLoesung"
        case .woerterbuch:       return "IconWoerterbuch"
        case .info:              return "IconInfo"
        case .meinKonto:         return "IconMeinKonto"
        case .elumiSpiel:        return "IconElumiSpiel"
        case .lautsprecherOn:    return "IconLautsprecherOn"
        case .lautsprecherOff:   return "IconLautsprecherOff"
        }
    }

    /// Default-VoiceOver-Label. Kann lokal überschrieben werden, damit der
    /// Enum-Case nicht das User-facing Label diktiert.
    var defaultAccessibilityLabel: String {
        switch self {
        case .mikrofon:          return "Mikrofon"
        case .tastatur:          return "Tastatur"
        case .lautsprecher:      return "Vorlesen"
        case .naechstesWort:     return "Nächstes Wort"
        case .loesung:           return "Lösung anzeigen"
        case .woerterbuch:       return "Wörterbuch"
        case .info:              return "Info"
        case .meinKonto:         return "Mein Konto"
        case .elumiSpiel:        return "Elumi-Spiel"
        case .lautsprecherOn:    return "Ton an"
        case .lautsprecherOff:   return "Ton aus"
        }
    }
}

/// Einheitliche Render-Komponente für ein Cartoon-Icon. Immer als
/// Image-Asset, immer `scaledToFit` in einer quadratischen Bounding-Box —
/// keine zusätzlichen Shadows/Glows und **kein** `foregroundStyle`, damit die
/// vom Icon mitgebrachten Farben bestehen bleiben.
///
/// Empfohlene Mindestgröße: 24 pt. In kleineren Slots (Badges, Inline-Pfeile)
/// bleibt das SF-Symbol-Set aus Kohärenzgründen erhalten.
struct ElumiIconView: View {
    let icon: ElumiIcon
    /// Side-length der Bounding-Box. Default 28 — gängige Größe für
    /// Action-Buttons in Training und Settings-Rows.
    var size: CGFloat = 28

    var body: some View {
        Image(icon.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(icon.defaultAccessibilityLabel)
    }
}
