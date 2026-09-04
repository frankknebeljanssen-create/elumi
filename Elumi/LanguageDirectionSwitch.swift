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
            // **2026-08-06, Redesign** — vorher zwei statische PNG-Assets
            // (`IconLanguageToggle` / `IconLanguageToggleReverse`, je die
            // Flaggen + einen gelb-schwarzen Pfeil fest eingebrannt).
            // User-Kritik: „passt gar nicht mehr zum Look der App … das
            // sieht 'n bisschen komisch aus", und zusätzlich saß der
            // Schalter im Modul-Header sichtbar höher als der Zurück-
            // Pfeil und das Elumi-Abzeichen daneben — weil ein
            // rechteckiges Asset mit fester Höhe nie exakt so zentriert
            // ist wie ein reiner SwiftUI-Chip.
            //
            // Jetzt komplett aus Code gebaut: dieselben `StraightFlagBadge`-
            // Bausteine, die auch anderswo in der App Flaggen zeichnen,
            // plus ein schlichtes SF-Symbol-Pfeilchen, in einer Kapsel im
            // selben Stil wie die übrigen Chips (`secondarySurface` +
            // Border) — dadurch zentriert es sich von selbst exakt wie
            // jeder andere Button in der Zeile, kein Asset-Offset mehr
            // möglich.
            HStack(spacing: spec.innerSpacing) {
                StraightFlagBadge(
                    countryCode: isFrToDE ? "FR" : "DE",
                    width: spec.flagWidth,
                    height: spec.flagHeight
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: spec.arrowSize, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                StraightFlagBadge(
                    countryCode: isFrToDE ? "DE" : "FR",
                    width: spec.flagWidth,
                    height: spec.flagHeight
                )
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .padding(.horizontal, spec.horizontalPadding)
            .padding(.vertical, spec.verticalPadding)
            .frame(maxWidth: spec.expandsWidth ? .infinity : nil)
            .background(
                Capsule().fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                Capsule().stroke(AppTheme.Colors.border, lineWidth: 1)
            )
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
            // Home-Variante: volle Breite, größte Präsenz.
            return Spec(
                flagWidth: 30,
                flagHeight: 20,
                arrowSize: 15,
                innerSpacing: 8,
                horizontalPadding: 16,
                verticalPadding: 11,
                expandsWidth: true
            )
        case .compact:
            // Setup-/Header-Variante — sitzt neben Zurück-Pfeil bzw.
            // Elumi-Abzeichen; Höhe bewusst nah an deren ~34-44 pt
            // gehalten, damit alle drei in der Back-Row gleich wirken.
            return Spec(
                flagWidth: 22,
                flagHeight: 16,
                arrowSize: 12,
                innerSpacing: 6,
                horizontalPadding: 10,
                verticalPadding: 9,
                expandsWidth: false
            )
        }
    }

    private struct Spec {
        let flagWidth: CGFloat
        let flagHeight: CGFloat
        let arrowSize: CGFloat
        let innerSpacing: CGFloat
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
