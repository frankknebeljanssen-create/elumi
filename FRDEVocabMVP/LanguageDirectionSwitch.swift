import SwiftUI
import UIKit

/// Globaler Language-Direction-Schalter.
///
/// Liest und schreibt den globalen Schlüssel `appDirectionKey` über
/// `@AppStorage` — das ist bereits der zentrale Wahrheitszustand in der
/// App, den alle Module (Quiz, Karteikarten, Training, Vokabeln …)
/// ohnehin beobachten. Mehrere Instanzen dieser Komponente an
/// unterschiedlichen Stellen (Home, Session-Setup) zeigen daher immer
/// denselben Zustand und halten sich gegenseitig synchron — es gibt
/// keinen parallelen Store und keine lokale Override-Logik.
///
/// Umfang des Toggles: `.frenchToGerman` ↔ `.germanToFrench`. Die beiden
/// englischen Varianten der `Direction`-Enum sind im V1-Umfang nicht Teil
/// des Home-Schalters — sie bleiben für Import-/Lexikon-Zwecke aber im
/// Datenmodell erhalten.
///
/// Varianten:
///   • `.regular` — Home-Screen, vollflächig, höherer Präsenz-Wert.
///   • `.compact` — Session-Setup-Zeile, kompakter, als Kontext-Element.
struct LanguageDirectionSwitch: View {
    enum Size {
        case regular
        case compact
    }

    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue
    /// Live-Switch-Gate für Icon-Set A ↔ B. Triggert Re-Render bei
    /// Settings-Wechsel, damit das Asset sofort tauscht (ohne Neustart).
    @AppStorage(AppIconRegistry.storageKey) private var iconSetRaw: String = AppIconSet.a.rawValue

    /// Kompressions-Flag für die Tap-Animation (Scale-Down bei Tap,
    /// Snap-Back nach ~100 ms). Lebt pro Komponente — zwei Instanzen
    /// animieren unabhängig, der Datenzustand bleibt aber identisch.
    @State private var isPressed = false

    var size: Size = .regular
    /// Optionaler Callback nach dem Toggle (z. B. für Sound-Feedback).
    /// Der State-Wechsel selbst passiert bereits über `@AppStorage`.
    var onToggle: (() -> Void)? = nil

    var body: some View {
        let direction = Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman
        let isFrToDE = direction == .frenchToGerman
        let spec = spec(for: size)

        Button(action: toggle) {
            // Ein einziges Asset pro Richtung — FR→DE nutzt `IconLanguageToggle`
            // (FR-Flagge links, blau), DE→FR nutzt `IconLanguageToggleReverse`
            // (DE-Flagge links, gold). Beide Icons enthalten bereits die beiden
            // Flaggen + die bidirektionalen Pfeile — die frühere manuelle
            // Komposition (zwei `StraightFlagBadge` + SF-Symbol dazwischen) ist
            // dadurch entfallen. `.id(…)` triggert beim Richtungswechsel eine
            // saubere Image-Transition, analog zum alten `.id(code)`-Pattern.
            //
            // **User-Fix (Phase 7.6+)**: Bewusst `Image("...")` ohne
            // `appIcon:`-Resolver — damit greift hier *nicht* der globale
            // A/B-Icon-Set-Switch, der Flaggen-Switcher bleibt immer auf
            // dem Original-A-Set-Asset.
            Image(isFrToDE ? "IconLanguageToggle" : "IconLanguageToggleReverse")
                .resizable()
                .scaledToFit()
                .frame(height: spec.iconHeight)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .id(isFrToDE ? "icon-fr-de" : "icon-de-fr")
                .padding(.horizontal, spec.horizontalPadding)
                .padding(.vertical, spec.verticalPadding)
                .frame(maxWidth: spec.expandsWidth ? .infinity : nil)
                // Kein Background, kein Border — das Icon steht nackt auf
                // dem darunterliegenden Screen-/Card-Hintergrund, ohne eigene
                // Mini-Card darum. `padding`/`frame` bleiben als Touch-Target
                // und für das Zentrieren erhalten.
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFrToDE
                ? "Lernrichtung Französisch nach Deutsch. Zum Umschalten tippen."
                : "Lernrichtung Deutsch nach Französisch. Zum Umschalten tippen."
        )
    }

    // MARK: - Toggle

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Sound-Feedback zum Richtungswechsel — zentral hier, damit der
        // Klang auf **jedem** Screen (Home + alle Setup-Screens) spielt,
        // ohne dass jede Aufruferseite explizit eine Sound-Closure
        // verdrahten muss. Der Key ist identisch zu `FeedbackPlayer.
        // areSoundsEnabled`, damit der globale Stummschalter greift.
        let soundsEnabledKey = "FRDEVocabMVP.soundsEnabled.v1"
        let soundsEnabled = UserDefaults.standard.object(forKey: soundsEnabledKey) == nil
            || UserDefaults.standard.bool(forKey: soundsEnabledKey)
        if soundsEnabled {
            SoundPlayer.shared.play("toggle")
        }

        // 1) Kompression anziehen — kurzer „Druck"-Effekt auf Flaggen + Pfeil.
        withAnimation(.easeOut(duration: 0.08)) {
            isPressed = true
        }

        // 2) State flippen — geschieht in der Mitte der Animation, damit
        //    die Flaggen während des Skalen-Tiefpunkts wechseln und der
        //    visuelle „Swap" organisch wirkt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            selectedDirectionRaw = (selectedDirectionRaw == Direction.frenchToGerman.rawValue)
                ? Direction.germanToFrench.rawValue
                : Direction.frenchToGerman.rawValue
            withAnimation(.easeOut(duration: 0.10)) {
                isPressed = false
            }
            onToggle?()
        }
    }

    // MARK: - Spec

    private func spec(for size: Size) -> Spec {
        switch size {
        case .regular:
            // SVG-ViewBox ist auf den Content-Bereich getrimmt (96×44 px
            // statt 96×96) — der gerenderte Frame ist jetzt identisch mit
            // der sichtbaren Fahnen-/Pfeil-Komposition, kein vertikaler
            // Leerraum mehr innerhalb des Bildes. Dadurch wirkt das Icon
            // bei gleicher Höhe wesentlich dichter; der alte 56-pt-Wert
            // wäre mit dem getrimmten Asset optisch fast doppelt so groß.
            // iconHeight: 32 → 28 → 24 → **20** pt (−15 % nach User-
            // Request „fr-de de-fr icon überall bisschen kleiner").
            // 20 pt bleibt gut lesbar und rückt den Home-Switch näher an
            // das visuelle Gewicht der umliegenden Chips, statt als
            // eigene Schwergewichts-Zeile zu wirken.
            return Spec(
                // Phase 7.6+: Flaggen-Icon verdoppelt (20 → 40 pt),
                // ohne umliegende Paddings zu ändern (User-Spec
                // „NICHTS anderes verschieben").
                iconHeight: 40,
                horizontalPadding: 16,
                verticalPadding: 4,
                expandsWidth: true
            )
        case .compact:
            // Kompakt-Variante (Session-Setup-Zeile): nach User-Feedback
            // („etwas größer, aber der riesige Abstand oben/unten muss
            // weg") wurde die SVG-ViewBox von 96×96 auf 96×44 getrimmt —
            // dadurch entfällt der bislang sichtbare 25-pt-Leerraum
            // ober- und unterhalb der Flaggen, der aus dem quadratischen
            // Canvas resultierte. iconHeight: 52 → 44 → 38 → **32** pt
            // (−15 % nach User-Request „fr-de de-fr icon überall bisschen
            // kleiner"). Der Setup-Switch rückt damit als Setting-
            // Element näher an die Ausgewählte-Listen-Card darüber,
            // ohne seine Lesbarkeit zu verlieren.
            return Spec(
                // Phase 7.6+: Flaggen-Icon verdoppelt (32 → 64 pt),
                // Paddings bleiben identisch — der Icon-Frame wird
                // höher, Nachbar-Cards verschieben sich durch den
                // VStack-Spacing-Rhythmus, aber kein manuelles
                // Reposition.
                iconHeight: 64,
                horizontalPadding: 12,
                verticalPadding: 2,
                expandsWidth: false
            )
        }
    }

    private struct Spec {
        /// Feste Rendering-Höhe des Assets. Breite ergibt sich automatisch
        /// (`.scaledToFit()` auf einem 96×96-Frame).
        let iconHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        /// `true` → die Komponente spannt auf die verfügbare Breite (Home).
        /// `false` → sie dimensioniert sich nach Inhalt (Session-Setup-Zeile).
        let expandsWidth: Bool
    }
}

/// Gemeinsame Zeile für das Session-Setup — **nur noch** das Flaggen-Icon,
/// mittig und **freistehend**. Nach User-Feedback ist der frühere
/// Card-Hintergrund (`SessionCardBackground`) entfernt: das neue Asset trägt
/// beide Flaggen + bidirektionale Pfeile in sich und wirkt als eigenständiges
/// Symbol, nicht als Button-Kachel. Dadurch liest sich die Zeile ruhiger und
/// gibt den Nachbar-Cards („Ausgewählte Listen" etc.) optisches Gewicht.
///
/// Absichtlich **keine** eigene State-Logik: die Komponente ist reiner
/// Layout-Wrapper um den `LanguageDirectionSwitch`.
struct SessionDirectionRow: View {
    var onToggle: (() -> Void)? = nil

    var body: some View {
        LanguageDirectionSwitch(size: .compact, onToggle: onToggle)
            // Zentriert in der verfügbaren Breite — das Asset dimensioniert
            // sich selbst, kein Card-Wrapper mehr drumherum. Keine eigene
            // vertikale Padding mehr: der Spacing-Rhythmus zu den
            // benachbarten Setup-Cards kommt bereits aus dem umgebenden
            // `VStack(spacing:)`. Zusätzliche 8 pt oben+unten liessen die
            // Flaggen optisch aus der Zeile „herausfallen".
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Lernrichtung")
    }
}
