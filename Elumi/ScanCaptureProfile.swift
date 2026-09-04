import Foundation

/// Definiert, **wie** der Scan-Stack eine Szene behandelt.
///
/// Bisher war die Profil-Unterscheidung versteckt in
/// `activeScanMode == .text ? .freierText : .vocabularyOCR` am
/// `SmartScannerView`-Call-Site — das setzte nur den
/// `SmartDocumentProcessor.Config`, ließ aber Tracker, Auto-Capture und
/// Live-Overlay unverändert. Resultat: Auf einer Müslipackung zappelte
/// trotzdem der Dokument-Rahmen und Auto-Capture feuerte auf zufällige
/// Rechtecke im Scene.
///
/// Dieses Profil ist die **einzige** Stelle, an der die beiden
/// Use-Cases divergieren. Jede neue Profil-Asymmetrie gehört hier rein,
/// nicht in die Call-Sites.
///
/// - `.vocabularyList` — Schulbuch, Vokabelheft, Arbeitsblatt. Klare
///   Dokumentseite. Live-Quad, Auto-Capture, aggressive Perspektiv-
///   korrektur erwartet.
/// - `.freeText` — Müslipackung, Poster, Zeitungsartikel, Plakat. Keine
///   Dokument-Annahme. Full-Frame High-Res-Capture ist korrekt;
///   Perspektivkorrektur nur opportunistisch.
enum ScanCaptureProfile: Equatable {
    case vocabularyList
    case freeText

    /// Default-Capture-Modus pro Profil. Wird vom `SmartScannerView`
    /// als Start-Toggle-Stellung verwendet, wenn die Capture-Stage
    /// zum ersten Mal erscheint.
    ///
    /// **Produktentscheidung (FreeText-Stabilisierungs-Slice)**:
    /// - vocabularyList → `.auto` (Dokument-Lock + stabile Quad-
    ///   Detection rechtfertigen Hands-free-Scanning).
    /// - freeText → `.manual` (Szene ohne verlässliche Region-
    ///   Detection. Attention-basiertes Auto-Capture löste auf
    ///   falschen Bereichen aus → User entscheidet selbst den
    ///   Auslöse-Moment.)
    enum CaptureMode: Equatable {
        case auto
        case manual
    }

    var defaultCaptureMode: CaptureMode {
        switch self {
        case .vocabularyList: return .auto
        case .freeText:       return .manual
        }
    }

    // MARK: - Live-UI-Verhalten

    /// Darf Auto-Capture (Hands-Free Auto-Shutter) bei stabilem Lock
    /// feuern?
    ///
    /// **Produkt-Entscheidung (FreeText-Stabilisierungs-Slices A/B)**:
    /// • vocabularyList: ja. Dokument-Quad-Lock ist ausreichend präzise.
    /// • freeText: nein. Auch im FreeText-„Auto/Rahmen"-Modus löst die
    ///   App **nicht** automatisch aus — der User triggert weiterhin
    ///   selbst. „Auto" bedeutet hier nur: Rectangle-Assistenz für
    ///   Plakate/Cover/Schilder, sichtbarer Rahmen + Quad-basierter
    ///   Crop bei Capture, falls eine plausible rechteckige Fläche
    ///   gefunden wurde. Sonst Fallback auf WYSIWYG.
    var allowsAutoCapture: Bool {
        switch self {
        case .vocabularyList: return true
        case .freeText:       return false
        }
    }

    /// Soll die Auto/Manual-Umschalt-UI überhaupt gezeigt werden?
    /// • vocabularyList: ja — Auto-Lock vs. Manual-Shutter.
    /// • freeText: ja — Manuell (WYSIWYG) vs. „Rahmen" (Rectangle-
    ///   Assistenz für rechteckige Objekte). Der Toggle steuert dort
    ///   nicht den Auto-Shutter (gibt es nicht), sondern ob im Live-
    ///   Feed die Rectangle-Detection als Assistenz mitläuft.
    var showsCaptureModeToggle: Bool {
        switch self {
        case .vocabularyList: return true
        case .freeText:       return true
        }
    }

    /// Zeigt das Live-Quadrilateral-Overlay (searching/candidate/locked)?
    /// FreeText blendet den Rahmen aus, solange kein **dominantes**
    /// Dokument vorliegt — dafür reicht es, den Overlay-Pfad per Profil
    /// abzuschalten und erst im nächsten Slice (AutoCaptureController)
    /// ein optionales Text-Region-Overlay einzuführen.
    var showsLiveQuadOverlay: Bool {
        switch self {
        case .vocabularyList: return true
        case .freeText:       return false
        }
    }

    /// Zeigt das weiche Attention-Overlay (Text-/Saliency-Bereich)?
    /// Komplement zu `showsLiveQuadOverlay`: FreeText hat kein Dokument-
    /// Quad, aber ein zentraler „Wo ziele ich gerade hin?"-Hinweis
    /// hilft dem User trotzdem. Läuft nur, wenn
    /// `runsAttentionDetection` aktiv ist.
    var showsAttentionOverlay: Bool {
        switch self {
        case .vocabularyList: return false
        case .freeText:       return true
        }
    }

    /// Erwartet der Capture-Flow zwingend ein Dokument-Quad in der
    /// Post-Capture-Refinement? FreeText lässt Full-Frame stehen, wenn
    /// keine dominante Fläche erkannt wird.
    var requiresDocumentQuad: Bool {
        switch self {
        case .vocabularyList: return true
        case .freeText:       return false
        }
    }

    /// Läuft der `RectangleTracker` im Live-Feed?
    ///
    /// **Entscheidung**: Der Rectangle-Tracker läuft **genau dann**, wenn
    /// das Profil seine Outputs (Quad-Overlay UND/ODER Rectangle-Lock-
    /// Gating für Auto-Capture) tatsächlich braucht. Das ist
    /// **ausschließlich** in `vocabularyList` der Fall.
    ///
    /// Bei `freeText` darf der Rectangle-Tracker **nicht** mitlaufen,
    /// auch wenn `allowsAutoCapture == true` ist:
    ///   • Das Live-Overlay kommt aus dem `AttentionRegionTracker`
    ///     (Text-/Saliency-Bereich), nicht aus einem Dokument-Quad.
    ///   • Auto-Capture wird in `emitAttentionGuidance` über die
    ///     **Attention-Stabilität** (`pseudoLockState`) gegated, nicht
    ///     über das Rectangle-Locking.
    ///
    /// **User-Bug, den dieses Decoupling fixt**: vorher OR-te der Flag
    /// `allowsAutoCapture` rein → Rectangle-Tracker lief auch in
    /// FreeText, das `if runsRectangle … else if runsAttention`-
    /// Routing in `captureOutput` schloss damit den Attention-Pfad
    /// AUS — Resultat: kein Attention-Overlay sichtbar, plus dauerhafte
    /// „Näher rangehen"-Hinweise vom Rectangle-Tracker auf Szenen ohne
    /// Dokument-Quad.
    var runsLiveDetection: Bool {
        switch self {
        case .vocabularyList: return true
        case .freeText:       return false
        }
    }

    /// Läuft der `AttentionRegionTracker` im Live-Feed? Nur im FreeText-
    /// Profil aktiv. Erkennt zentralen Text-/Content-Bereich (Text-
    /// Detection primär, Saliency als Fallback) und zeigt ein weiches
    /// Overlay — „wo zielt die Kamera gerade hin". **KEIN Auto-
    /// Capture**, **KEIN harter Rahmen** — der User löst weiterhin
    /// manuell aus. VocabularyList bleibt unverändert: dort gilt
    /// weiterhin Rectangle-Detection.
    ///
    /// Produkt-Verhalten: FreeText fühlt sich dadurch an wie eine
    /// „intelligente Kamera" statt passivem Foto-Tool — der User
    /// bekommt Feedback, dass die App seinen Fokus versteht, ohne
    /// den Auslöse-Moment aus der Hand zu nehmen.
    var runsAttentionDetection: Bool {
        showsAttentionOverlay
    }

    // MARK: - Bridges zu existierenden Configs

    /// Processor-Profil, das in die Post-Capture-Pipeline fließt.
    /// Mapping hält die bestehende `SmartDocumentProcessor.Config`-API
    /// unverändert — nur die Wahl wandert aus dem Call-Site in den
    /// Profil-Typ.
    var processorConfig: SmartDocumentProcessor.Config {
        switch self {
        case .vocabularyList: return .vocabularyOCR
        case .freeText:       return .freierText
        }
    }

    /// Tracker-Profil. Heute beide gleich (Default), weil freeText den
    /// Tracker komplett abschaltet (`runsLiveDetection == false`) —
    /// falls in einem späteren Slice ein sanfter freeText-Tracker
    /// eingeführt wird (z. B. für eine opportunistische Dokument-
    /// Hint-Marke), lebt die Tuning hier.
    var trackerConfig: RectangleTracker.Config {
        switch self {
        case .vocabularyList: return .default
        case .freeText:       return .default
        }
    }
}

// MARK: - Capture-Geometry-Policy

/// Explizite Policy für die **Geometrie-Behandlung** des Captures —
/// macht klar, was nach dem Shutter mit dem Bild passiert.
///
/// Die Policy ergibt sich aus (`profile`, `autoCaptureEnabled`):
///
///   • vocabularyList + auto    → `.documentCropAndPerspective`
///       (Volle Document-Pipeline: Quad-Detection, Crop, Perspective.
///        Auto-Shutter über RectangleTracker.lockState=.locked.)
///
///   • vocabularyList + manual  → `.documentPerspectiveIfPlausible`
///       (Manual-Shutter; Pipeline läuft trotzdem mit Quad-Detection
///        + Perspective, weil Vokabelblätter typisch flach + rechteckig
///        sind. Wenn kein Quad → Original durchgereicht.)
///
///   • freeText + auto/Rahmen   → `.rectangleAssistWithFallback`
///       (Manual-Shutter; RectangleTracker läuft als Assistenz,
///        bei stabilem Quad → Crop+Perspective, sonst WYSIWYG-Fallback.)
///
///   • freeText + manual        → `.wysiwygNoPerspective`
///       (Manual-Shutter; **keine** Quad-Detection, **keine** Perspective,
///        **kein** Auto-Crop. Nur analytischer aspectFill-Crop auf den
///        sichtbaren Sucher-Ausschnitt. Optional sanfte Bild-Verbesserung
///        über Auto-Optimieren-Button im Review.)
enum CaptureGeometryPolicy: Equatable {
    case documentCropAndPerspective
    case documentPerspectiveIfPlausible
    case rectangleAssistWithFallback
    case wysiwygNoPerspective

    static func from(profile: ScanCaptureProfile, autoCaptureEnabled: Bool) -> CaptureGeometryPolicy {
        switch (profile, autoCaptureEnabled) {
        case (.vocabularyList, true):  return .documentCropAndPerspective
        case (.vocabularyList, false): return .documentPerspectiveIfPlausible
        case (.freeText, true):        return .rectangleAssistWithFallback
        case (.freeText, false):       return .wysiwygNoPerspective
        }
    }

    /// Kurzer Tag für Debug-Logs.
    var debugLabel: String {
        switch self {
        case .documentCropAndPerspective:     return "documentCropAndPerspective"
        case .documentPerspectiveIfPlausible: return "documentPerspectiveIfPlausible"
        case .rectangleAssistWithFallback:    return "rectangleAssistWithFallback"
        case .wysiwygNoPerspective:           return "wysiwygNoPerspective"
        }
    }
}
