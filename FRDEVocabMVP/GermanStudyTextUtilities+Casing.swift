import Foundation

// MARK: - Detection Utilities
//
// ACHTUNG: Diese Datei enthält KEINE Casing-Regeln mehr.
// Zentrale Casing-Engine: siehe TextNormalizationEngine (TextCasingRules.swift).
//
// Hier verbleiben ausschließlich Detection-Utilities, die an anderen Stellen
// für Nomen-Erkennung, Artikel-Detektion und Gender-Inferenz benötigt werden.

func startsWithGermanArticle(_ text: String) -> Bool {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first else { return false }
    return germanArticleHints.contains(first)
}

func leadingGermanArticle(in text: String) -> String? {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first, germanArticleHints.contains(first) else { return nil }
    return first
}
