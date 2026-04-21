import SwiftUI

/// Daten-Modell für die Home-Lernstatus-Card.
///
/// Die Card fasst pro Status-Klasse (`.strong`, `.needsWork`, `.sparse`) die
/// Anzahl der getrackten Einträge zusammen. `totalTracked` ist die Summe
/// über **alle** Klassen — wird unten rechts als Hero-Zahl gezeigt, damit
/// der User auf einen Blick sieht, wie viele Vokabeln überhaupt schon
/// Signal im Store haben.
struct HomeLernstatusData: Equatable {
    let strongCount: Int
    let needsWorkCount: Int
    let sparseCount: Int
    let totalTracked: Int

    /// Leerer Status-Zustand: Store ist neu / noch keine Session
    /// abgeschlossen. Die Card zeigt in dem Fall einen freundlichen
    /// Empty-State („Spiel noch ein paar Runden…") statt kühler Nullen.
    var isEmpty: Bool { totalTracked == 0 }
}

/// Home-Card „Lernstatus".
///
/// Zweck: cross-modularer Überblick, welche Vokabeln bereits sitzen
/// (`.strong`) und welche noch Aufmerksamkeit brauchen (`.needsWork`).
/// Gefüttert aus dem `ItemLearningStatusStore`, der von allen 4 Modulen
/// (Karteikarten, Training, Verbformen, Quiz) beschrieben wird.
///
/// Platzierung (`HomeView`): **zwischen** Progress-Board und dem Pager
/// mit den 8 Modul-Kacheln. Damit trennen die zwei Board-Cards (Status
/// heute + Progress) den Begrüßungs-Bereich vom Modul-Grid — die neue
/// Card rutscht sich dazwischen als nächste „Wert-Ebene", ohne den Flow
/// zu brechen.
///
/// Layout:
///   • 3 Segmente mit semantischen Farben (Stark → grün, Üben → orange,
///     Neu → pink) + Divider zwischen den Segmenten — dieselbe Rhythmik
///     wie im Progress-Board darüber, so liest sich das Card-Paar als
///     zusammenhängendes Board-Modul.
///   • Empty-State: ein freundlicher Hinweis statt drei „0"-Zeichen.
///
/// Tap-Interaktion: öffnet den `LernstatusView`-Detail-Screen.
struct HomeLernstatusCard: View {
    let data: HomeLernstatusData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Eine-Zeilen-Layout, symmetrisch zur `HomeStatusCard` und
            // `HomeProgressBoardCard` darüber: Icon-Badge links, Titel
            // + Pills mittig, Chevron rechts. Keine Microcopy-Zeile
            // mehr — Header und die drei Icon-Zahl-Pills reichen aus.
            HStack(alignment: .center, spacing: 11) {
                iconBadge

                // Titel zweizeilig („Dein" / „Lernstatus") — schafft
                // Platz rechts für die drei Pills ohne Scale-Shrink.
                // Keine Chevron-Anzeige mehr; das Antippen der ganzen
                // Card öffnet den Detail-Screen (Tap-Target bleibt
                // voll).
                // `fixedSize(horizontal: true, vertical: false)` verhindert,
                // dass der zweizeilige Titel von der Pills-Spalte
                // gequetscht und dadurch abgeschnitten wird („Lernstat…").
                // Beide Zeilen claimen damit ihre natürliche Breite;
                // überschüssiger Platz geht an den Spacer zwischen
                // Titel und Pills.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Dein")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("Lernstatus")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 6)

                if !data.isEmpty {
                    // Drei kompakte Icon-Zahl-Pills (ohne Label-Text).
                    // Reihenfolge Stark/Üben/Neu beibehält die Semantik;
                    // Farben weiterhin Grün/Orange/Pink.
                    //
                    // Trailing 20 → 12 (−8 pt): da die Pills jetzt
                    // breiter sind und der Titel via `fixedSize` seine
                    // volle Breite beansprucht, würde 20 pt den
                    // „Lernstatus"-Text aus dem Frame drücken. 12 pt
                    // schiebt die Pills trotzdem sichtbar vom Card-Rand
                    // weg (Entlastung für die Sparkles-Pill) und lässt
                    // dem Titel wieder Platz — kein Abschneiden mehr.
                    // **User-Wunsch: weniger „Status-Bar", mehr „bewusste
                    // Info"**. Pills bekommen mehr Atem zwischen sich
                    // (6 → 9 pt) und sitzen nicht mehr aneinander.
                    HStack(spacing: 9) {
                        compactPill(icon: "checkmark.seal.fill", tint: Self.strongTint, value: "\(data.strongCount)")
                        compactPill(icon: "bolt.fill", tint: Self.needsWorkTint, value: "\(data.needsWorkCount)")
                        compactPill(icon: "sparkles", tint: AppTheme.Colors.elumiPink, value: "\(data.sparseCount)")
                    }
                    .padding(.trailing, 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // minHeight synchron zu HomeStatusCard (66) — alle drei
            // Cards darüber bilden optisch ein einheitliches Band.
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(0.55),
                radius: 7,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Öffnet die Lernstatus-Detailansicht.")
    }

    /// Icon-Badge links — gleiche Optik wie `HomeStatusCard` (Icon im
    /// Tint-getönten Kreis). Nutzt `brain.head.profile` als klar
    /// lesbares Lernstatus-Symbol; Tint = Strong-Grün, passt zur
    /// Empty-State-Logik (siehe weiter unten).
    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(Self.strongTint.opacity(0.16))
            Image(systemName: "brain.head.profile")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Self.strongTint)
        }
        .frame(width: 38, height: 38)
    }

    /// Warmer One-Liner über den Pills — motivierend, nicht wertend.
    /// Passt sich an den dominanten Stand an: viel „Stark" → Lob,
    /// viel „Üben" → sachliche Einladung, überwiegend „Neu" → Start-
    /// signal. Bewusst kein Alarm-Ton („du musst"), eher Coach-Ton.
    private var heroMicrocopy: String {
        let total = max(1, data.totalTracked)
        let strongRatio = Double(data.strongCount) / Double(total)
        let needsWorkRatio = Double(data.needsWorkCount) / Double(total)

        if strongRatio >= 0.6 {
            return "\(data.strongCount) sitzen schon fest — stark!"
        }
        if needsWorkRatio >= 0.4 {
            return "\(data.needsWorkCount) wollen noch eine Runde mit dir."
        }
        // Sparse-dominant: User-Wunsch „frische Einträge — los geht's"
        // Text rausnehmen. Fallback auf die neutrale Summary-Zeile, die
        // sowieso den „Stark / in Arbeit"-Stand zeigt.
        return "\(data.strongCount) sicher • \(data.needsWorkCount) in Arbeit"
    }

    /// Kompaktes Icon + Zahl-Paar (ohne Text-Label). Seit der
    /// Kompakt-Umstellung trägt der Icon-Glyph die Semantik (Checkmark
    /// = stark, Bolt = üben, Sparkles = neu); der Label-Text wurde
    /// rausgenommen, damit die drei Pills horizontal in eine Zeile
    /// passen — analog zum ein-zeiligen Layout der beiden Cards darüber.
    private func compactPill(icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        // **User-Wunsch „mehr bewusste Info"**: Pill leicht größer
        // (Icon 11→12, Wert 13→14, vertical 4→6), Border statt
        // nur Fill — Pills lesen sich als eigenständige Info-Tags,
        // nicht als kompakte Status-Bar.
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(tint.opacity(0.14))
        )
        .overlay(
            Capsule().stroke(tint.opacity(0.30), lineWidth: 0.8)
        )
    }

    // MARK: - Segmente

    private var segmentsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            segment(
                count: data.strongCount,
                label: "Stark",
                tint: Self.strongTint,
                icon: "checkmark.seal.fill"
            )
            segmentDivider
            segment(
                count: data.needsWorkCount,
                label: "Üben",
                tint: Self.needsWorkTint,
                icon: "bolt.fill"
            )
            segmentDivider
            segment(
                count: data.sparseCount,
                label: "Neu",
                tint: AppTheme.Colors.elumiPink,
                icon: "sparkles"
            )
        }
    }

    /// Ein Segment: Icon-Badge links, Zahl + kleines Caption-Label
    /// rechts. Icon-Badge ist farbig getönt (Tint als Fill-Opacity 0.16
    /// wie im Progress-Board und in der Status-Card).
    private func segment(count: Int, label: String, tint: Color, icon: String) -> some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .tracking(0.4)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
            .frame(width: 1, height: 28)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        // Empty-State: Nur das Wort „Lernstatus" neben dem Icon-Badge.
        // Die frühere Erklärung („Los geht's — nach ein paar Runden…")
        // ist raus — der User hat den Kontext schon aus dem Home-Flow
        // verstanden, und eine zweite Textzeile machte die Card
        // gesprächiger als nötig. Font-Größe 17 pt .black (statt 13 pt)
        // bringt das Wort auf dieselbe Prominenz wie das „X Aktionen"
        // in der `HomeStatusCard` darüber — damit die beiden Cards
        // ein visuelles Paar bilden, auch wenn die Lernstatus-Card
        // noch leer ist.
        //
        // Farb-Aufteilung (User-Request):
        //   • „Lernstatus"-Text → weiß (`textPrimary`), liest sich als
        //     neutraler Card-Titel — nicht als zweiter Pink-Akzent im
        //     Card-Trio.
        //   • Icon-Badge → `strongTint` (Grün), **bewusst andere Farbe**
        //     als der Pink-Akzent der „Heute"-Card darüber. Semantisch
        //     passend: Grün = „Stark" = Lern-Zielzustand, den die Card
        //     selbst trackt (populated-State nutzt `strongTint` für das
        //     „Stark"-Segment — der Empty-State greift dieselbe Farbe
        //     als Card-Signatur auf).
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill(Self.strongTint.opacity(0.16))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Self.strongTint)
            }
            .frame(width: 38, height: 38)

            Text("Dein Lernstatus")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Chrome (identisch zu HomeProgressBoardCard)

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppSectionStyle.home.accent.opacity(AppTheme.CardIntensity.soft))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
    }

    // MARK: - Tints

    /// Grün für „stark" — bewusst nicht System-Green (wirkt zu schreiend),
    /// sondern ein leicht entsättigter Tone, der mit der Home-Akzentfarbe
    /// harmoniert. `internal` (statt `fileprivate`), weil die Detail-View
    /// `LernstatusView` denselben Tint für ihre „Stark"-Sektion nutzt —
    /// ein geteiltes Farb-Vokabular zwischen Card und Detail-Screen.
    static let strongTint = Color(hex: "#4EB07A")

    /// Orange für „üben" — dieselbe Nuance wie die Flame-Streak-Indikation
    /// im Progress-Board, damit sich ein Farb-Vokabular etabliert
    /// („orange = noch in Bewegung"). `internal`, analog zu `strongTint` —
    /// `LernstatusView` nutzt den Wert für die „Zum Üben"-Sektion.
    static let needsWorkTint = Color(hex: "#FF9F40")

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        if data.isEmpty {
            return "Lernstatus. Noch keine Daten — nach ein paar Runden siehst du hier den Fortschritt."
        }
        return "Lernstatus: \(data.strongCount) stark, \(data.needsWorkCount) zum Üben, \(data.sparseCount) neu."
    }
}
