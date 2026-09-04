// ElumiHints.swift
// **2026-05-06** — Hint-Pool für den Maschine-Tab-Header. Vorher
// stand dort hardcoded „Salut \(name)!" — was beim Spielen mitten
// im Flow keinen Sinn ergibt (es ist keine Begrüßung; der User ist
// schon mehrere Tabs tief drin). Jetzt rotiert ein kindgerechter
// Hint-Pool: jeder Tab-Visit zieht zufällig einen Eintrag, sodass
// der Header lebendig wirkt und auf den Slot-Spin-Moment einstimmt.
//
// Auswahl: Random pro Tab-Visit (über `.onAppear` im Tab-Body),
// nicht persistent — `@State` reicht und wird beim Tab-Re-Mount
// neu gewürfelt.
//
// Pattern-Vorlage: `SpeedRoundTerminology` (SpeedRoundSettings.swift)
// — Namespace-Enum mit statischen Properties, kein eigener Store.

import Foundation

/// Hint-Pool für den ELUMI-Tab-Header. Pool-Erweiterung passiert
/// hier in einem Schritt — Caller liest immer `random()`.
enum ElumiHints {
    /// Aktueller Pool. User-Spec 2026-05-06 — sieben Vorschläge,
    /// alle kindgerecht (11–17 J.), französisch-Schul-Kontext, kurz
    /// genug für die Header-Card-Breite.
    ///
    /// Bei Erweiterung: Einträge sollten max. ~30 Zeichen lang
    /// bleiben, sonst bricht die ModuleHeaderCard auf manchen Geräten
    /// um. Stilistisch direkter Du-Ansatz, mit Fragen oder Aufrufen
    /// (kein passiver Begrüßungston wie das alte „Salut!").
    static let pool: [String] = [
        "Was kommt heute raus?",
        "Bereit für eine Überraschung?",
        "Was wird's heute?",
        "Lass dich überraschen!",
        "Drück die Maschine!",
        "Heute ist ein Mix-Tag!",
        "Was hat Elumi für dich?"
    ]

    /// Liefert einen zufällig gewählten Hint. Fallback auf den ersten
    /// Eintrag, falls der Pool leer ist (defensiv — `randomElement()`
    /// gibt theoretisch nil zurück, in der Praxis nie wenn der Pool
    /// nicht leer ist).
    static func random() -> String {
        pool.randomElement() ?? pool.first ?? "Was kommt heute raus?"
    }
}
