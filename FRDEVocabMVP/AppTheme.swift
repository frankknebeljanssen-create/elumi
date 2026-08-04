import SwiftUI

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let a, r, g, b: UInt64
        switch sanitized.count {
        case 8:
            (a, r, g, b) = ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        default:
            (a, r, g, b) = (255, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

struct AppShadowSpec {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum AppTheme {
    enum Colors {
        static let elumiMidnight = Color(hex: "#081A2B")
        static let elumiNavy = Color(hex: "#101522")
        static let elumiPink = Color(hex: "#FF4D80")
        static let elumiPinkDeep = Color(hex: "#C93567")
        static let elumiRose = Color(hex: "#FF8FA3")
        static let elumiRoseDeep = Color(hex: "#B9426F")
        static let elumiBlush = Color(hex: "#FFB3BA")
        static let elumiCream = Color(hex: "#FFF0F3")
        static let elumiMint = Color(hex: "#2EC4A9")
        static let elumiAmber = Color(hex: "#FFD166")
        static let elumiAmberDeep = Color(hex: "#B8832F")
        // Semantisch getrenntes Alarm-Rot. Bewusst **nicht** `elumiPinkDeep`,
        // damit Error/Validierungs-Feedback nicht mit der Vokabel-Modulfarbe
        // verwechselt wird. Warm gehalten (kein kühles Material-Rot), aber
        // sattiger/alarmierender als PinkDeep — klar als „etwas stimmt nicht"
        // lesbar.
        static let elumiErrorRed = Color(hex: "#E04456")
        // Eigener Hearts-Ton (Leben/Herz-Semantik). War vorher an `error`
        // gekoppelt — das führte dazu, dass jede Änderung an Error auch
        // Hearts betraf und umgekehrt. Coral-warm, passend zur
        // Warmton-Palette.
        static let elumiHeartsRed = Color(hex: "#FF5A5F")
        // Sekundäre Akzent-Familie: weder Pink noch Amber. Genutzt für Links,
        // Info-Texte (Subtitles wie „1 Liste · 60 Karten gesamt") und allgemein
        // sekundäre Akzente. Hellblau, freundlich, klar erkennbar.
        static let elumiBlue = Color(hex: "#5B9CF5")
        // Setup-Card-Hintergrund + Border — **identisch** zu den Home-Cards
        // (Progress-Board, Daily-Focus, Modul-Kacheln). Ein einziger
        // Card-Look durch die App: `surface` als Fill + cremefarbener
        // 12%-Border. Frühere Abweichung (#0F2D48 heller Setup-Tint)
        // fiel visuell aus dem Raster und ist mit dem Master-Setup-Screen
        // entfallen.
        static let setupCardBackground = surface
        static let setupCardBorder = elumiCream.opacity(0.12)

        static let primary = elumiPinkDeep
        // Material-Semantik korrekt umgesetzt: `background` ist der
        // **dunklere** App-Hintergrund (Y≈20.9), `surface` der
        // **minimal hellere** Card-Fill (Y≈23.4). Naming-Quirk: die
        // Farb-Tokens `elumiMidnight`/`elumiNavy` klingen umgekehrt,
        // aber die tatsächlichen Hex-Werte stellen genau dieses Dunkel-
        // zu-Hell-Gefälle her (Home-Pattern: Screen dunkel, Cards heller).
        static let background = elumiNavy
        static let surface = elumiMidnight
        static let secondarySurface = Color(hex: "#162133")

        static let textPrimary = elumiCream
        static let textSecondary = elumiRose.opacity(0.88)
        static let textDisabled = elumiRose.opacity(0.5)

        static let success = elumiMint
        // Error ist jetzt eigenständig (warmes Signal-Rot `elumiErrorRed`),
        // nicht mehr an `elumiPinkDeep` (= moduleVocabulary) gekoppelt.
        // Semantik sauber: Vokabel-Identität und Fehler-Signal sind
        // verschiedene Dinge.
        static let error = elumiErrorRed
        // Heller, sonniger Amber für alle CTAs und Card-Header — bessere
        // Sichtbarkeit auf den blau-tönigen Card-Hintergründen. Schwarze
        // Schrift auf CTA-Buttons (siehe `AppPrimaryButtonStyle`).
        static let cta = elumiAmber
        // Card-Section-Header (z. B. „Ausgewählte Listen", „Anzahl der
        // Karten") nutzen denselben Ton — Single Source of Truth.
        static let cardLabel = elumiAmber
        static let warning = elumiAmberDeep

        // ── Single Source of Truth: Modul-Farben ──
        static let moduleVocabulary = Color(hex: "#1E3A8A")      // Vokabeln — Dark Blue (Indigo-900; deutlich dunkler als `moduleFlashcards` #3B82F6, damit beide klar unterscheidbar bleiben)
        static let moduleNomen = Color(hex: "#059669")           // Nomen — Emerald
        static let moduleArticles = Color(hex: "#34D399")        // Artikel — Light Emerald (Nomen-Familie)
        static let moduleVerbs = Color(hex: "#8B5CF6")           // Verben — Purple
        static let moduleVerbforms = Color(hex: "#A78BFA")       // Verbformen — Light Purple (Verben-Familie)
        static let moduleFlashcards = Color(hex: "#3B82F6")      // Karteikarten — Blue
        static let moduleQuiz = Color(hex: "#F59E0B")            // Quiz — Amber
        static let moduleLexicon = Color(hex: "#E879F9")         // Wörterbuch — Fuchsia
        static let moduleLists = Color(hex: "#57B8C9")           // Listen — Teal
        static let moduleScan = Color(hex: "#EF6C50")            // Scan — Coral
        static let moduleAccents = Color(hex: "#F43F5E")         // Akzente — Rose (distinct from Vocab-Pink und Hearts-Red, passt thematisch zu „Akzenten")
        /// **Developer-Section-Akzent** (2026-06-09) — kühles Slate-Grau,
        /// bewusst außerhalb der Modul-Farbfamilie, damit alle Cards in
        /// `SettingsView.developerSection` auf einen Blick als „Developer-
        /// Zeug" erkennbar sind (nicht mit einem Lernmodul verwechselbar).
        static let developerAccent = Color(hex: "#64748B")       // Developer — Slate
        static let moduleArcade = elumiPinkDeep                  // Arcade — Pink
        // Hearts (Leben) bekommt einen eigenen Slot und hängt nicht mehr
        // am `error`-Token. So können Error-Semantik und Hearts-Modul
        // unabhängig voneinander geändert werden.
        static let moduleHearts = elumiHeartsRed                 // Hearts — Coral-Rot

        // Legacy aliases
        static let modulePractice = moduleVocabulary
        static let moduleSpecial = moduleLists

        static let border = elumiCream.opacity(0.12)
        static let borderStrong = elumiBlush.opacity(0.22)
        static let shadow = Color.black.opacity(0.24)
        static let shadowStrong = Color.black.opacity(0.34)
    }

    enum Gradients {
        /// Léa-Chat-Home-Card — dunkler Glas-Look mit Mint-Tint (noHistory-State).
        /// Top-Leading: success.opacity(0.18) — Bottom-Trailing: background.opacity(0.6).
        static let leaChatGlass = LinearGradient(
            colors: [
                AppTheme.Colors.success.opacity(0.18),
                AppTheme.Colors.background.opacity(0.6)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold, design: .rounded)
        static let largeTitleLineHeight: CGFloat = 38

        static let screenTitle = Font.system(size: 26, weight: .bold, design: .rounded)
        static let screenTitleLineHeight: CGFloat = 32

        static let cardTitle = Font.system(size: 19, weight: .semibold, design: .rounded)
        static let cardTitleLineHeight: CGFloat = 24

        static let body = Font.system(size: 16, weight: .medium, design: .rounded)
        static let bodyLineHeight: CGFloat = 22

        static let caption = Font.system(size: 12, weight: .semibold, design: .rounded)
        static let captionLineHeight: CGFloat = 16

        static let button = Font.system(size: 17, weight: .bold, design: .rounded)
        static let buttonLineHeight: CGFloat = 22
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        // Systemweit reduziert: Cards 14pt, kleine Elemente (Chips, Badges,
        // Buttons in Listen) 10pt. Größere visuelle Konsistenz und ein
        // ruhigeres, weniger verspieltes Erscheinungsbild.
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let pill: CGFloat = 999
    }

    enum Shadow {
        static let card = AppShadowSpec(color: Colors.shadow, radius: 14, x: 0, y: 6)
        static let floating = AppShadowSpec(color: Colors.shadowStrong, radius: 18, x: 0, y: 10)
        static let button = AppShadowSpec(color: Colors.cta.opacity(0.18), radius: 10, x: 0, y: 4)
    }

    enum Layout {
        static let screenPadding: CGFloat = Spacing.md
        static let cardPadding: CGFloat = Spacing.md
        static let chromeBarHeight: CGFloat = 46
        static let headerHeight: CGFloat = 56
        static let footerHeight: CGFloat = 50
        static let inputHeight: CGFloat = 52
        static let buttonHeight: CGFloat = 54
        static let homeCardHeight: CGFloat = 102
        static let wideCardHeight: CGFloat = 82
        static let selectionHeight: CGFloat = 76
        static let maxContentWidth: CGFloat = 720
    }

    /// Zentrale Intensity-Kaskade für `appCardBackground(sectionStyle, …)`
    /// und verwandte getönte Hintergründe.
    ///
    /// **Warum eine Token-Hierarchie statt Magic Numbers?**
    /// Jede Card in der App trägt die Modul-Akzentfarbe (Nomen = Grün,
    /// Verben = Lila, Quiz = Amber …) als Overlay über dem Surface-Token.
    /// Die `intensity`-Zahl entscheidet, *wie deutlich* der Modul-Ton
    /// durchkommt. Bisher waren diese Werte überall frei verteilt
    /// (0.05 … 0.22, 12 verschiedene Werte, keine Systematik). Dieses
    /// Enum bündelt sie auf 8 klare Stufen mit sprechenden Namen — damit
    /// lassen sich systemweit die Intensitäten in einem Schritt justieren
    /// (z. B. „alle Setup-Cards nochmal dezenter" = `medium` runterdrehen).
    ///
    /// Die heutigen Rohwerte werden 1:1 beibehalten, wo es passt; nur
    /// Zwischenwerte (0.06 / 0.08 / 0.10 / 0.12 / 0.15 / 0.16) runden auf
    /// den nächstliegenden Bucket — maximale Abweichung 0.02, auf dem
    /// dunklen Background unsichtbar.
    ///
    /// Reihenfolge bewusst „whisper → selected": jede Stufe ist ein
    /// **visuelles** Level, kein rein semantisches Label.
    enum CardIntensity {
        /// Kaum wahrnehmbar — unausgewählte Picker-/Listen-Items, die
        /// nur zur Raum-Struktur da sind. Wert: `0.05`.
        static let whisper: Double = 0.05

        /// Dezent — ruhige Content-Rows, Inner-Cards, Mute-/Reward-
        /// Zustände. Wert: `0.07`. (0.06-Legacy rundet hierher.)
        static let subtle: Double = 0.07

        /// Sanft — Such-Ergebnis-Rows, Chips, dezente Detail-Cards.
        /// Eigener Bucket, damit 0.08-Aufrufer nicht in den dominanten
        /// 0.09-Bucket kippen. Wert: `0.08`.
        static let gentle: Double = 0.08

        /// Standard — Default von `appCardBackground`. Die breite Masse
        /// der Content-Cards (Home, Hearts, Profile, Scan, Listen).
        /// Wert: `0.09`. (0.10-Legacy rundet hierher.)
        static let soft: Double = 0.09

        /// Medium — aktiver Content-Bereich, Setup-Cards, Hero-Cards in
        /// Session-Flows. Wert: `0.11`. (0.12-Legacy rundet hierher.)
        static let medium: Double = 0.11

        /// Stark — ausgewählte/aktive Zustände, prominente Stats-Cards,
        /// urgent/strong-highlight-Cards. Wert: `0.14`.
        /// (0.15 und 0.16 Legacy runden hierher; max Drift 0.02.)
        static let strong: Double = 0.14

        /// Bold — Feature-Card, Speed-Round-Active, Settings-Hero.
        /// Wert: `0.18`.
        static let bold: Double = 0.18

        /// Prominent — aktuelle Auswahl im Picker. Einziger Zustand, in
        /// dem der Modul-Ton wirklich „leuchtet". Wert: `0.22`.
        static let selected: Double = 0.22
    }
}

/// Semantische Aliase für globale Action-Farben. Klar getrennt von
/// Modul-Identitätsfarben: Wenn eine View eine Primär-CTA, ein Erfolgs-
/// Feedback, eine Warnung oder einen destruktiven Button zeigen will,
/// referenziert sie hier — **nicht** direkt auf `AppTheme.Colors.cta`,
/// `.success`, `.error` etc. So kann die Zuordnung später zentral
/// verschoben werden (z. B. „alle destruktiven Actions zu Coral"),
/// ohne dass Callsites angefasst werden müssen.
///
/// Zweck ist Semantik, nicht Farbmagie — heute zeigt jeder Slot auf
/// den bereits vorhandenen Token aus `AppTheme.Colors`.
enum ElumiActionStyle {
    /// Primär-CTA: „Weiter", „Start", „Bestätigen". Heute: Amber.
    static let primary: Color = AppTheme.Colors.cta
    /// Positive Zustände: Erfolgs-Feedback, abgeschlossene Tasks. Mint.
    static let success: Color = AppTheme.Colors.success
    /// Hinweis / Achtung: Amber-Deep (anderer Ton als primary-Amber,
    /// damit CTA und Warnung unterscheidbar bleiben).
    static let warning: Color = AppTheme.Colors.warning
    /// Zerstörend: Löschen, Abbrechen-mit-Verlust. Zeigt auf das seit
    /// Commit „Farb-Semantik: Error entkoppeln" eigenständige
    /// `elumiErrorRed` — nicht mehr `elumiPinkDeep`.
    static let destructive: Color = AppTheme.Colors.error
}

enum AppModuleTone {
    case practice
    case special
    case flashcards
    case quiz

    var color: Color {
        switch self {
        case .practice:
            return AppTheme.Colors.modulePractice
        case .special:
            return AppTheme.Colors.moduleSpecial
        case .flashcards:
            return AppTheme.Colors.moduleFlashcards
        case .quiz:
            return AppTheme.Colors.moduleQuiz
        }
    }
}
