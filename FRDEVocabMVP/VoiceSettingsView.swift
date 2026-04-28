import SwiftUI
import UIKit

/// **Stimme-Settings** (Phase 9.1, dynamic) — fully device-agnostic
/// Stimmen-Picker. Listet nur Stimmen, die auf **diesem** iPhone
/// tatsächlich installiert sind. Die Empfehlung („Empfohlen"-Badge)
/// wird per Qualitätsrang ermittelt, nicht per festen Namen.
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store = VoiceSettingsStore.shared
    @StateObject private var service = SpeechVoiceService.shared

    private let sectionStyle: AppSectionStyle = .elumi

    /// Toast-State: pingt dezent, wenn nach dem Refresh eine neue
    /// Enhanced/Premium-Stimme verfügbar ist (= User kam frisch aus
    /// den iPhone-Einstellungen zurück).
    @State private var showToast: Bool = false
    @State private var previousHighQualityCount: Int = 0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    introCard

                    languageSection(language: .german, options: service.germanOptions)

                    languageSection(language: .french, options: service.frenchOptions)

                    if !service.hasAnyHighQualityVoice {
                        installPromptCard
                    }

                    refreshButton

                    actualUsageCard
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.screenHeaderTopPadding)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .overlay(alignment: .top) { toastOverlay }
            .navigationTitle("Stimme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
        .onAppear {
            service.refresh()
            previousHighQualityCount = currentHighQualityCount()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let before = previousHighQualityCount
                service.refresh()
                let now = currentHighQualityCount()
                if now > before {
                    triggerToast()
                }
                previousHighQualityCount = now
            }
        }
    }

    // MARK: - Intro

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Elumi nutzt die Stimmen deines iPhone.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text("Für schönere Sprachausgabe kannst du hochwertige Apple-Stimmen in den iPhone-Einstellungen laden. Deine Auswahl bleibt in Elumi gespeichert.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appSetupCardBackground()
    }

    // MARK: - Language-Section

    private func languageSection(language: ElumiSpeechLanguage, options: [VoiceOption]) -> some View {
        let recommended = service.recommendedOption(for: language)
        return VStack(alignment: .leading, spacing: 10) {
            Text(language.displayName.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(AppTheme.Colors.cardLabel)

            VStack(spacing: 6) {
                ForEach(options) { option in
                    voiceRow(
                        option: option,
                        isRecommended: option.identifier == recommended?.identifier,
                        language: language
                    )
                }
            }

            // Hinweis, wenn es in DIESER Sprache keine Enhanced/Premium-
            // Stimme gibt — transparente Nutzerführung pro Sprache.
            if !service.hasHighQualityVoice(for: language) {
                Text("Für \(language.displayName) ist aktuell keine hochwertige Stimme geladen. Du kannst sie unten in den iPhone-Einstellungen installieren.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func voiceRow(option: VoiceOption, isRecommended: Bool, language: ElumiSpeechLanguage) -> some View {
        let isSelected = store.record(for: language).identifier == option.identifier

        return Button {
            store.setSelection(option)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Selection-Indicator
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? sectionStyle.accent : Color.white.opacity(0.25),
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(sectionStyle.accent)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(option.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if isRecommended {
                            Text("empfohlen")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(sectionStyle.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(sectionStyle.accent.opacity(0.18))
                                )
                        }

                        Spacer(minLength: 0)

                        if let badge = option.qualityBadge {
                            qualityBadgeView(badge)
                        }
                    }

                    if option.isSystemDefault {
                        Text("Verwendet automatisch die Standardstimme deines iPhone.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? sectionStyle.accent.opacity(0.12) : Color(hex: "#1A2A40"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? sectionStyle.accent : Color(hex: "#243B55"),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func qualityBadgeView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(badgeColor(for: text))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(badgeColor(for: text).opacity(0.18))
            )
    }

    private func badgeColor(for text: String) -> Color {
        switch text {
        case "Premium":  return AppTheme.Colors.success
        case "Enhanced": return AppTheme.Colors.cta
        default:         return AppTheme.Colors.textSecondary
        }
    }

    // MARK: - Install Prompt

    private var installPromptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bessere Stimmen laden")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Für schönere Sprachausgabe kannst du in den iPhone-Einstellungen weitere Stimmen laden. Sobald eine neue Stimme installiert ist, erscheint sie automatisch hier.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openSystemSettings()
            } label: {
                Text("iPhone-Einstellungen öffnen")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.Colors.cta)
                    )
            }
            .buttonStyle(.plain)

            Text("Dort findest du unter Bedienungshilfen → Gesprochene Inhalte die weiteren Stimmen.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                .fill(sectionStyle.accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                .stroke(sectionStyle.accent.opacity(0.4), lineWidth: 1.2)
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Refresh

    private var refreshButton: some View {
        Button {
            let before = currentHighQualityCount()
            service.refresh()
            let now = currentHighQualityCount()
            if now > before { triggerToast() }
            previousHighQualityCount = now
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Verfügbarkeit erneut prüfen")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(sectionStyle.accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Aktuell verwendet

    private var actualUsageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AKTUELL VERWENDET")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(AppTheme.Colors.cardLabel)

            usageRow(language: .german)
            usageRow(language: .french)
        }
        .padding(.top, 6)
    }

    private func usageRow(language: ElumiSpeechLanguage) -> some View {
        let record = store.record(for: language)
        let selected = service.selectedOption(forRecord: record, language: language)
        let effective = service.effectiveOption(forRecord: record, language: language)

        return VStack(alignment: .leading, spacing: 4) {
            Text(language.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            labeledLine(label: "Gewählt", value: selected.displayName)
            labeledLine(
                label: "Aktuell verwendet",
                value: effectiveDescription(selected: selected, effective: effective)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    /// Formatiert den „Aktuell verwendet"-Wert user-facing. Wenn die
    /// Wunsch-Stimme tatsächlich resolved wird, zeigen wir ihren Namen.
    /// Weicht die effektive Stimme ab (weil der Identifier nicht mehr
    /// installiert ist), machen wir die Diskrepanz transparent.
    private func effectiveDescription(selected: VoiceOption, effective: VoiceOption) -> String {
        if selected.identifier == effective.identifier {
            return effective.displayName
        }
        if effective.isSystemDefault {
            return "Systemstandard (bis \(selected.displayName) verfügbar ist)"
        }
        return "\(effective.displayName) (Fallback)"
    }

    private func labeledLine(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if showToast {
            Text("Neue Stimme verfügbar.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppTheme.Colors.success))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func triggerToast() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeOut(duration: 0.32)) {
                showToast = false
            }
        }
    }

    // MARK: - Helpers

    /// Zählt Enhanced/Premium-Stimmen über beide Sprachen — Grundlage
    /// für den „neue Stimme verfügbar"-Toast.
    private func currentHighQualityCount() -> Int {
        let all = service.germanOptions + service.frenchOptions
        return all.filter {
            guard let q = $0.quality else { return false }
            return q == .enhanced || q == .premium
        }.count
    }
}
