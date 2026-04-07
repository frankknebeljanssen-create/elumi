import SwiftUI
import Foundation

struct OCRLineBox: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect

    var midX: CGFloat { boundingBox.midX }
    var midY: CGFloat { boundingBox.midY }
    var height: CGFloat { boundingBox.height }
    var minX: CGFloat { boundingBox.minX }
    var maxX: CGFloat { boundingBox.maxX }
    var width: CGFloat { boundingBox.width }
}

enum ScanMode: String, CaseIterable, Identifiable {
    case list
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            return "Vokabelliste"
        case .text:
            return "Freier Text"
        }
    }

    var shortTitle: String {
        switch self {
        case .list:
            return "Liste"
        case .text:
            return "Text"
        }
    }

    var subtitle: String {
        switch self {
        case .list:
            return ""
        case .text:
            return ""
        }
    }

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet.rectangle.portrait.fill"
        case .text:
            return "text.alignleft"
        }
    }

    var summaryLabel: String {
        switch self {
        case .list:
            return "Als Vokabelliste aufbereitet"
        case .text:
            return "Als Freitext aufbereitet"
        }
    }

    var introMessage: String {
        switch self {
        case .list:
            return "Mach ein Foto oder wähle ein Bild deiner Vokabelliste."
        case .text:
            return "Mach ein Foto oder wähle ein Bild mit freiem Text."
        }
    }
}

struct ImportPreviewPair: Identifiable, Equatable {
    var id = UUID()
    var french: String
    var german: String
    var cardType: CardType = .words
    var learningCategory: ScanLearningCategory? = nil
    var note: String? = nil
    var isImportable: Bool = true
    var isReviewed: Bool = false
}


enum ManualCropTarget {
    case scanPreparation
    case imagePreview
}

struct ManualCropSession: Identifiable {
    let id = UUID()
    let image: UIImage
    let target: ManualCropTarget
}
