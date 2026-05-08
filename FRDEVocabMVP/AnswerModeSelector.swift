// AnswerModeSelector.swift
// **Sweep C — AnswerMode (2026-05-07)** — Generic Component für die
// Sprechen/Tippen-Wahl im Setup. Wiederverwendet von Karteikarten,
// Vokabeln und Nomen.
//
// Visuell angelehnt an das bestehende `nounAnswerModeCard`-Pattern in
// `TrainingView+Layout.swift` (Icon-Puck oben-zentriert, Titel mittig),
// aber generisch: Caller übergibt `Binding<AnswerMode>` + Accent-Color
// + optional Feedback-Closure.
//
// Section-Header „ANTWORTEN MIT" intern (konsistent zu Sweep A
// Section-Header-Naming: CAPS, Source-String selbst CAPS-formuliert).

import SwiftUI

/// Sprechen/Tippen-Selector für die drei Speech-fähigen Setup-Screens.
///
/// **Layout**:
/// ```
/// ANTWORTEN MIT
/// ┌──────────────┬──────────────┐
/// │  [Mic]       │  [Keyboard]  │
/// │  Sprechen    │  Tippen      │
/// └──────────────┴──────────────┘
/// ```
struct AnswerModeSelector: View {
    /// Binding zum persistierten AnswerMode (i. d. R. via `@AppStorage`
    /// im Setup-Screen).
    @Binding var mode: AnswerMode

    /// Modul-Akzent-Farbe für Selected-State (Tint-Fill + Border).
    let accent: Color

    /// Optionaler Feedback-Closure (Tab-Switch-Sound etc.) bei jedem
    /// Mode-Wechsel.
    var onChange: ((AnswerMode) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section-Header — Style + Visuals identisch zum bisherigen
            // `nounAnswerModeSection`-Header (17 pt black, textPrimary,
            // Source-String CAPS für CAPS-Rendering ohne `.textCase`-
            // Modifier).
            Text("ANTWORTEN MIT")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 10) {
                ForEach(AnswerMode.allCases) { option in
                    card(for: option)
                }
            }
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func card(for option: AnswerMode) -> some View {
        let isSelected = (mode == option)

        Button {
            mode = option
            onChange?(option)
        } label: {
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isSelected ? 0.28 : 0.14))
                    Image(systemName: option.systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 38, height: 38)
                .padding(.top, 2)

                Text(option.displayTitle)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(accent.opacity(isSelected ? AppTheme.CardIntensity.medium : AppTheme.CardIntensity.subtle))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? accent : AppTheme.Colors.border.opacity(0.7),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
