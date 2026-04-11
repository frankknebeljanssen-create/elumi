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

        static let primary = elumiPinkDeep
        static let background = elumiMidnight
        static let surface = elumiNavy
        static let secondarySurface = Color(hex: "#162133")

        static let textPrimary = elumiCream
        static let textSecondary = elumiRose.opacity(0.88)
        static let textDisabled = elumiRose.opacity(0.5)

        static let success = elumiMint
        static let error = elumiPinkDeep
        static let cta = elumiAmberDeep
        static let warning = elumiAmberDeep

        static let modulePractice = elumiPinkDeep          // Vokabeln
        static let moduleSpecial = Color(hex: "#57B8C9")  // Listen — Teal
        static let moduleFlashcards = Color(hex: "#3B82F6") // Karteikarten — Blue
        static let moduleQuiz = Color(hex: "#10B981")       // Quiz — Green

        static let border = elumiCream.opacity(0.12)
        static let borderStrong = elumiBlush.opacity(0.22)
        static let shadow = Color.black.opacity(0.24)
        static let shadowStrong = Color.black.opacity(0.34)
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
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
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
        static let homeCardHeight: CGFloat = 107
        static let wideCardHeight: CGFloat = 82
        static let selectionHeight: CGFloat = 76
        static let maxContentWidth: CGFloat = 720
    }
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
