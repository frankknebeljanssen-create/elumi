import Foundation

enum ScanInputMethod {
    case camera
    case library
}

enum ScanRuntimeStage: Equatable {
    case idle
    case ocrPreflight
    case aiConnecting
    case aiPrimary
    case ocrFallback
}
