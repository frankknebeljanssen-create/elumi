import SwiftUI

struct AppSurfaceCard<Content: View>: View {
    let tint: Color?
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        tint: Color? = nil,
        padding: CGFloat = AppTheme.Layout.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if let tint {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                                .stroke(tint.opacity(0.16), lineWidth: 1)
                        }
                    }
            }
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y
            )
    }
}

struct AppBarSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            content
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.chromeBarHeight)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }
}

struct AppListItemRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let tint: Color
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}

struct AppFolderItemRow: View {
    let title: String
    let subtitle: String?
    let tint: Color

    var body: some View {
        AppListItemRow(
            icon: "folder.fill",
            title: title,
            subtitle: subtitle,
            tint: tint
        )
    }
}

struct AppProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.secondarySurface)

                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

struct AppDialogCard<Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Content

    init(title: String, message: String, @ViewBuilder actions: () -> Content) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        AppSurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(title)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(message)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }
        }
    }
}

struct AppSheetHeader: View {
    let title: String
    var leadingTitle: String = "Zurück"
    var trailingTitle: String? = nil
    var leadingTint: Color = AppTheme.Colors.primary
    var trailingTint: Color = AppTheme.Colors.primary
    let onLeading: () -> Void
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button(leadingTitle, action: onLeading)
                .buttonStyle(.plain)
                .font(AppTheme.Typography.body)
                .foregroundStyle(leadingTint)

            Spacer(minLength: 0)

            Text(title)
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            if let trailingTitle, let onTrailing {
                Button(trailingTitle, action: onTrailing)
                    .buttonStyle(.plain)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(trailingTint)
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
    }
}

// MARK: - AppInputField

/// **Eingabefeld-Vereinheitlichung Modul 1 (2026-05-22)** — wiederver-
/// wendbares Lern-Antwort-Eingabefeld im hellen „cream"-Look mit dunkler
/// Schrift. Single Source of Truth für die Tippen-Felder (Pilot:
/// Karteikarten; später Vokabeln/Nomen/Verbformen/Quiz).
///
/// Optik = das frühere inline KK-cream-Feld (1:1): Hintergrund elumiCream,
/// Schrift elumiMidnight, Placeholder als eigener Overlay (volle Farb-
/// kontrolle — der SwiftUI-System-Placeholder rendert im Dark-Theme hell
/// → auf cream unsichtbar), Border elumiMidnight 12 %, Radius.md,
/// minHeight 46. `alignment` ist für Quiz (zentriert) in Modul 2 vorbereitet.
///
/// Lebt in dieser bestehenden In-Target-Datei (statt eigener Datei), weil
/// das Projekt explizite `.pbxproj`-Referenzen nutzt (keine synchronisierten
/// Ordner) — eine neue Datei wäre nicht automatisch im Build-Target.
struct AppInputField: View {
    /// **Daily Drop Modul 2.12 (2026-05-23)** — Optionaler Ergebnis-Zustand
    /// für das Antwort-Feedback im Count-Modus: färbt den Feld-Border grün
    /// (richtig) bzw. rot (falsch). Default `.none` → Border unverändert
    /// (Midnight 12 %). Rein additiv; alle bestehenden Call-Sites bleiben
    /// gleich.
    enum ResultState {
        case none, correct, wrong
    }

    let placeholder: String
    @Binding var text: String

    /// Cursor-/Tint-Farbe (Modul-Akzent). Default `primary`.
    var accent: Color = AppTheme.Colors.primary
    /// Ergebnis-Feedback-Zustand (grün/rot Border). Default `.none`.
    var resultState: ResultState = .none
    /// Mindesthöhe (bequemes Touch-Target). Default 46.
    var minHeight: CGFloat = 46
    /// Text-Ausrichtung. `.center` z. B. für Quiz. Default `.leading`.
    var alignment: TextAlignment = .leading
    /// Return-Key-Label. Default `.done`.
    var submitLabel: SubmitLabel = .done
    /// Autocorrect aus (z. B. Verbformen — französische Formen nicht
    /// „korrigieren"). Default false.
    var autocorrectionDisabled: Bool = false
    /// Auto-Großschreibung. Default `.sentences` (System-Standard);
    /// `.never` z. B. für Verbformen.
    var autocapitalization: TextInputAutocapitalization = .sentences
    /// Aktiv/Deaktiviert. Default true.
    var isEnabled: Bool = true
    /// Optionale Focus-Bindung — der Caller steuert den Fokus.
    var focus: FocusState<Bool>.Binding? = nil
    /// Callback bei Return/Submit.
    var onSubmit: (() -> Void)? = nil
    /// Callback bei Tap aufs Feld (z. B. Audio-Mode wechseln).
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: zStackAlignment) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(AppTheme.Colors.elumiMidnight.opacity(0.5))
                    .multilineTextAlignment(alignment)
                    .allowsHitTesting(false)
            }
            fieldCore
        }
        .font(.system(size: 17, weight: .medium, design: .rounded))
        .padding(.horizontal, 14)
        .frame(minHeight: minHeight, alignment: zStackAlignment)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(resultFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(resultBorderColor, lineWidth: resultBorderWidth)
        )
        .animation(.easeOut(duration: 0.18), value: resultState)
    }

    /// **2026-06-09** — Das ganze Feld färbt sich, nicht nur der Rand.
    ///
    /// Vorher blieb die Füllung cremefarben und nur eine 2 pt starke
    /// Kontur wurde grün — im Quiz war die Bestätigung dadurch kaum zu
    /// sehen (User-Report). Andere Fragetypen färben ihre ganze Karte,
    /// das Eingabefeld zieht jetzt nach.
    private var resultFillColor: Color {
        switch resultState {
        case .none:    return AppTheme.Colors.elumiCream
        // Voll deckend — zusammen mit der weißen Schrift (siehe
        // `resultTextColor`) ergibt das dieselbe Sprache wie die
        // Multiple-Choice-Karten: farbige Fläche, helle Schrift.
        // Kräftigeres Grün als `success`: Der helle Mint-Ton trug die
        // weiße Schrift nicht (User-Report „nicht hell genug" — es fehlte
        // nicht Weiß, sondern Kontrast dahinter).
        case .correct: return Color(hex: "#0F9D6E")
        case .wrong:   return AppTheme.Colors.error
        }
    }

    /// **2026-06-09** — Schrift wird weiß, sobald die Fläche farbig ist.
    ///
    /// Auf dem grünen Feld wirkte das dunkle `elumiMidnight` wie
    /// ausgegraut (User-Report) — die Multiple-Choice-Antworten nutzen
    /// bei Treffern längst weiße Schrift auf farbigem Grund. Im
    /// Normalzustand (cremefarbenes Feld) bleibt die Schrift dunkel.
    private var resultTextColor: Color {
        resultState == .none ? AppTheme.Colors.elumiMidnight : .white
    }

    private var resultBorderColor: Color {
        switch resultState {
        case .none:    return AppTheme.Colors.elumiMidnight.opacity(0.12)
        case .correct: return AppTheme.Colors.success
        case .wrong:   return AppTheme.Colors.error
        }
    }

    private var resultBorderWidth: CGFloat {
        resultState == .none ? 1 : 3
    }

    /// TextField mit konditionalem Focus/onTap — `.onTapGesture` wird NUR
    /// angehängt, wenn `onTap` gesetzt ist (sonst würde eine leere Geste
    /// das Tap-to-Focus von Feldern ohne onTap schlucken).
    @ViewBuilder
    private var fieldCore: some View {
        let base = TextField("", text: $text)
            .foregroundStyle(resultTextColor)
            .tint(accent)
            .multilineTextAlignment(alignment)
            .submitLabel(submitLabel)
            .autocorrectionDisabled(autocorrectionDisabled)
            .textInputAutocapitalization(autocapitalization)
            // Kein .disabled() — natives TextField-Dimming überschreibt
            // sonst .foregroundStyle() und macht den Text unlesbar
            // (bereits einmal analog bei Buttons aufgetreten, siehe
            // AppPrimaryButtonStyle-Historie).
            .allowsHitTesting(isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
            .onSubmit { onSubmit?() }

        switch (focus, onTap) {
        case let (focus?, onTap?):
            base.focused(focus).onTapGesture { onTap() }
        case let (focus?, nil):
            base.focused(focus)
        case let (nil, onTap?):
            base.onTapGesture { onTap() }
        case (nil, nil):
            base
        }
    }

    private var zStackAlignment: Alignment {
        switch alignment {
        case .center:   return .center
        case .trailing: return .trailing
        case .leading:  return .leading
        }
    }
}
