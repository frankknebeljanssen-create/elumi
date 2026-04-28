import SwiftUI

/// **Setup-Slot für einen persönlichen Trainings-Stapel** (Phase 8).
/// Rendert je nach Eingabe entweder einen leeren „+ Neuen Stapel
/// anlegen"-Platzhalter oder eine gefüllte Karte mit Name, Meta-Info,
/// „Weiter"-Button und Fortschritts-Balken.
///
/// Tap auf gefüllten Slot → Session starten (via `onStart`).
/// Tap auf leeren Slot → Create-Sheet öffnen (via `onCreate`).
/// Long-Press auf gefüllten Slot → ActionSheet (Rename/Delete).
struct PersonalDeckSlotView: View {
    let deck: PersonalDeck?
    let cardStatsProvider: (PersonalDeck) -> (totalCards: Int, listCount: Int)
    let onCreate: () -> Void
    let onStart: (PersonalDeck) -> Void
    /// **User-Revision 2026-04-22**: Stift öffnet die Listen-Auswahl
    /// (Listen UND Name des Stapels ändern), nicht mehr nur den
    /// Rename-Alert. Callback kann vom Aufrufer z. B. zu einer Edit-
    /// Sheet-Präsentation verdrahtet werden.
    let onEdit: (PersonalDeck) -> Void
    let onDelete: (PersonalDeck) -> Void

    /// **2-Spalten-Layout (User-Revision 2026-04-22)**: Slots sind jetzt
    /// schmale Cards nebeneinander, nicht mehr über die volle Breite
    /// übereinander. Layout muss entsprechend kompakter werden — die
    /// Fixed-Höhe sorgt für optische Parität zwischen leerem und
    /// gefülltem Slot.
    /// **User-Revision (final-2)**: Card-Höhe 94 → 82 (−12). Footer-Row
    /// rückt näher an den Fortschrittsbalken heran, weil der flexible
    /// Spacer unter der Bar weg ist.
    private let slotHeight: CGFloat = 82

    var body: some View {
        if let deck {
            filledSlot(for: deck)
        } else {
            emptySlot
        }
    }

    // MARK: - Empty Slot

    private var emptySlot: some View {
        Button(action: onCreate) {
            HStack(spacing: 8) {
                // Plus-Icon-Container: 16×16, cornerRadius 4, leicht
                // abgesetzter Hintergrund. Bewusst kein farbiger Frame —
                // der leere Slot soll optisch zurücktreten.
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .frame(width: 16, height: 16)

                Text("Neuen Stapel anlegen")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.25))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color(hex: "#1A3A55"),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filled Slot

    /// **2-Spalten-Layout (Final)**: schlanke Card mit
    ///   • oben: Farbpunkt + Stapelname (weiß, 10 pt — User-Revision +1 pt)
    ///   • Mitte: Meta-Info „X Listen · Y / Z"
    ///   • unten: halber Progress-Balken
    ///   • rechts unten: „Weiter"-Pill + Stift-Icon (Rename)
    ///
    /// Die GESAMTE Karte (außer der Stift) ist als Button markiert und
    /// ruft `onStart(deck)` auf — damit bleibt der „Weiter"-Pill
    /// clickable (vorher via `allowsHitTesting(false)` blockiert).
    /// Der Stift ist ein eigener Button mit Rename-Aktion.
    private func filledSlot(for deck: PersonalDeck) -> some View {
        let stats = cardStatsProvider(deck)
        let totalCards = stats.totalCards
        let listCount = stats.listCount
        let currentIndex = min(deck.currentIndex, deck.cardOrder.count)
        let listsLabel = listCount == 1 ? "1 Liste" : "\(listCount) Listen"
        let metaText = "\(listsLabel) · \(currentIndex) / \(totalCards)"
        let dotColor = PersonalDeck.color(for: deck.colorIndex)

        _ = metaText // Meta-Zeile entfernt — siehe frühere Revision.

        // **User-Revision (final-6, echter Fix)**:
        // Layout ist jetzt eine NICHT-Button-View. Tap-Gestures:
        //   • Weiter-Pill selbst = eigener `Button` mit `onStart(deck)`
        //   • Stift = eigener `Button` mit `onEdit(deck)` als Overlay
        //   • Rest-der-Card-Tap auch → `onStart` via `.onTapGesture`
        // Damit gibt es KEINE nested Buttons mehr und keine Button-
        // in-Button-Hit-Test-Konflikte.
        return VStack(alignment: .leading, spacing: 6) {
            // Header: Dot + Name (weiß, 11 pt)
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(deck.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }

            // Progress-Bar — halbe Card-Breite
            GeometryReader { geo in
                let halfWidth = geo.size.width * 0.5
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: halfWidth)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(dotColor)
                        .frame(width: max(0, halfWidth * deck.progressFraction))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)

            // Footer: Weiter-Pill als ECHTER Button, Pencil als Button
            // im Overlay des ZStacks (unten). Platzhalter rechts sorgt
            // für die Lücke, in der das Pencil-Overlay sitzt.
            HStack(spacing: 6) {
                Button {
                    onStart(deck)
                } label: {
                    Text("Weiter")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FFD166"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: "#FFD166").opacity(0.15))
                        )
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 0)

                Color.clear.frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: slotHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: "#5B9CF5").opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: "#1A3A55"), lineWidth: 1)
        )
        // Pencil als Overlay-Button — eigene Hit-Zone.
        .overlay(alignment: .bottomTrailing) {
            Button {
                onEdit(deck)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 10)
            .padding(.bottom, 9)
        }
        // Tap auf freie Card-Fläche → auch Start. Die inneren Buttons
        // (Weiter, Stift) capturen ihre eigenen Hits zuerst.
        .contentShape(Rectangle())
        .onTapGesture {
            onStart(deck)
        }
    }
}

extension PersonalDeck {
    /// Zentrale Color-Lookup für den `colorIndex`. Hartcodierte
    /// Werte — siehe Spec.
    static func color(for index: Int) -> Color {
        switch index {
        case 1:  return Color(hex: "#5B9CF5") // Blau
        default: return Color(hex: "#FF4D80") // Pink (Default/Fallback)
        }
    }
}
