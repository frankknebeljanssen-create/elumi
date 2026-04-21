import SwiftUI
import UIKit

/// Claude-Vision-Analyse-Flow für „Freier Text".
///
/// Wird ausschließlich **nach** Bildwahl aufgerufen — der Nutzer hat den
/// kompletten Pick-Weg (Mode-Card „Freier Text" → Kamera/Foto-Album →
/// Preparation-Sheet) analog zu Vokabel-Scan durchlaufen. Diese View
/// übernimmt erst ab dem Moment, in dem das Bild feststeht.
///
/// Stages (lokal via `@State`):
///   - `.processing(image)` → triggert Claude-Vision-Request
///   - `.result(FreeTextResult)` → zeigt Lemmata-Liste
///
/// Kein Entry-Screen mehr (die Bildwahl läuft über die bestehenden Scan-
/// Cards). „Fertig" → `dismiss()` → zurück zur Scan-Übersicht.
struct FreierTextAnalysisFlowView: View {
    @Environment(\.dismiss) private var dismiss

    /// Bild, das analysiert werden soll. Wird vom Aufrufer vorgefüllt
    /// (gepickt via Scan-Cards). Nicht optional — wenn wir präsentiert
    /// werden, muss das Bild vorliegen.
    let image: UIImage

    /// Optionales Cleanup-Callback — wird beim Dismiss gefeuert, damit
    /// der Aufrufer `freierTextPendingImage` zurücksetzen kann.
    var onDismiss: () -> Void = {}

    /// Durchgereicht von `ScanImportView` — wird an die Result-View
    /// weitergegeben, damit der „Speichern"-Button dort die Analyse-
    /// Ergebnisse als neue Vokabelliste persistieren kann.
    var listStore: VocabularyListStore? = nil

    /// Post-Save-Callback: Wird aufgerufen, wenn der Nutzer in der
    /// Result-View erfolgreich gespeichert hat. Der Aufrufer
    /// (`ScanImportView`) speichert den Context zwischen und zeigt nach
    /// dem Fullscreen-Cover-Dismiss die `ImportCompletionView` — exakt
    /// wie beim Vokabel-Scan.
    var onImportComplete: ((ImportCompletionContext) -> Void)? = nil

    private enum Stage {
        case processing
        case cancelled     // User hat während laufender Analyse abgebrochen
        case summary(FreeTextResult)
        case result(FreeTextResult)
    }

    @State private var stage: Stage = .processing

    /// Typisierter Fehler statt `String` — erlaubt differenzierte
    /// Alert-Texte (Netzwerk vs. Server vs. Decode) und Retry-Logik.
    @State private var pendingError: FreierTextError?

    /// Token, das bei jedem „Nochmal versuchen" neu gesetzt wird und
    /// als `.id(...)` der Processing-View dient. Dadurch erzeugt SwiftUI
    /// eine **frische** Processing-Instanz — `hasStarted` und
    /// `elapsedSeconds` resetten, die `.task` läuft neu. Ohne diesen
    /// Remount würde `hasStarted = true` einen zweiten Request
    /// blockieren.
    @State private var retryToken = UUID()

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            switch stage {
            case .processing:
                FreierTextProcessingView(
                    image: image,
                    onSuccess: { result in
                        // Qualitätsfilter + Abkürzungs-Expansion einmal
                        // anwenden — alle nachgelagerten Views und das
                        // Speichern arbeiten auf dem bereinigten +
                        // ausgeschriebenen Result. Expansion läuft in
                        // `.exactAndInline`-Policy, damit z. B. „Hbf"
                        // zu „der Hauptbahnhof (Hbf)" wird und „Köln
                        // Hbf" zu „Köln Hauptbahnhof (Hbf)".
                        let cleaned = result.filtered().expandingAbbreviations()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            stage = .summary(cleaned)
                        }
                    },
                    onFailure: { error in
                        pendingError = error
                    },
                    onCancel: {
                        // User-Abbruch während laufender Analyse — NICHT
                        // direkt rausspringen. Stattdessen in den Cancelled-
                        // Stage wechseln, wo das Bild nochmal gezeigt wird
                        // mit „Nochmal analysieren" / „Zurück"-Optionen.
                        // Der `.task`-Cleanup in der Processing-View cancelt
                        // die laufende URL-Session sauber über den
                        // retryToken-Wechsel (Remount).
                        withAnimation(.easeInOut(duration: 0.25)) {
                            stage = .cancelled
                        }
                    }
                )
                .id(retryToken)
            case .cancelled:
                FreierTextCancelledView(
                    image: image,
                    onRetry: {
                        // Token rotieren → Processing-View remountet
                        // komplett frisch, Analyse läuft mit demselben Bild
                        // erneut.
                        retryToken = UUID()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            stage = .processing
                        }
                    },
                    onBack: {
                        onDismiss()
                        dismiss()
                    }
                )
            case .summary(let result):
                FreierTextSummaryView(
                    result: result,
                    onViewResults: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            stage = .result(result)
                        }
                    },
                    onDone: {
                        onDismiss()
                        dismiss()
                    }
                )
            case .result(let result):
                FreierTextResultView(
                    result: result,
                    onDone: {
                        onDismiss()
                        dismiss()
                    },
                    listStore: listStore,
                    onImportComplete: { context in
                        // 1. Context an ScanImportView übergeben (wird dort
                        //    zwischengespeichert bis das Cover weg ist).
                        onImportComplete?(context)
                        // 2. Fullscreen-Cover schließen — löst am Ende die
                        //    `.fullScreenCover(onDismiss:)` aus, die dann
                        //    `isShowingImportCompletion = true` setzt.
                        onDismiss()
                        dismiss()
                    }
                )
            }
        }
        .alert(errorAlertTitle, isPresented: errorAlertBinding) {
            // „Nochmal versuchen" nur anbieten, wenn der Fehler durch Retry
            // behebbar ist — z. B. Netzwerk-/Server-Hiccups. Bei
            // `missingAPIKey` kann der Nutzer nichts ausrichten.
            if let error = pendingError, canRetry(error) {
                Button("Nochmal versuchen") {
                    pendingError = nil
                    // Token-Rotation → Processing-View remountet → Analyse
                    // läuft mit demselben Bild erneut.
                    retryToken = UUID()
                }
            }
            Button("Abbrechen", role: .cancel) {
                pendingError = nil
                onDismiss()
                dismiss()
            }
        } message: {
            Text(errorAlertMessage)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingError != nil },
            set: { if !$0 { pendingError = nil } }
        )
    }

    /// Alert-Titel passend zur Fehlerklasse — gibt dem Nutzer sofort
    /// einen Hinweis, wo das Problem liegt (Netz? Server? Bild?), ohne
    /// dass er den Message-Text erst lesen muss.
    private var errorAlertTitle: String {
        switch pendingError {
        case .missingAPIKey, .invalidImage:
            return "Analyse nicht möglich"
        case .networkFailure:
            return "Verbindungsproblem"
        case .httpFailure(let code, _):
            return code == 429 ? "Zu viele Anfragen" : "Server nicht erreichbar"
        case .invalidResponse, .decodeFailure:
            return "Ergebnis unvollständig"
        case .none:
            return "Analyse fehlgeschlagen"
        }
    }

    /// Message-Body im Alert — konkret, aber ohne Tech-Details.
    /// Bei Server-Fehlern wird nach Status-Code differenziert: 429 →
    /// Rate-Limit, 5xx → Server-seitiges Problem, alles andere → generisch.
    private var errorAlertMessage: String {
        switch pendingError {
        case .missingAPIKey:
            return "Es ist kein API-Key konfiguriert. Bitte wende dich an den Support."
        case .invalidImage:
            return "Das Bild konnte nicht verarbeitet werden. Versuch es mit einer anderen Aufnahme."
        case .networkFailure:
            return "Prüf deine Internetverbindung und versuch es nochmal."
        case .httpFailure(let code, _):
            if code == 429 {
                return "Der Server ist gerade überlastet. Warte ein paar Sekunden und versuch es nochmal."
            } else if (500..<600).contains(code) {
                return "Der Server meldet ein Problem. Versuch es in ein paar Minuten erneut."
            } else {
                return "Der Server hat die Anfrage abgelehnt (Code \(code))."
            }
        case .invalidResponse, .decodeFailure:
            return "Das Ergebnis konnte nicht vollständig verarbeitet werden. Versuch es mit einem schärferen Foto."
        case .none:
            return "Analyse fehlgeschlagen. Bitte erneut versuchen."
        }
    }

    /// Retry ergibt nur Sinn, wenn das Problem transient sein kann.
    /// Fehlender API-Key oder kaputtes Bild bleiben bei einem zweiten
    /// Versuch genauso kaputt — da zeigen wir nur den Abbrechen-Button,
    /// damit der Nutzer nicht in eine hoffnungslose Retry-Schleife rennt.
    private func canRetry(_ error: FreierTextError) -> Bool {
        switch error {
        case .missingAPIKey, .invalidImage:
            return false
        case .networkFailure, .httpFailure, .invalidResponse, .decodeFailure:
            return true
        }
    }
}

// MARK: - Cancelled-Stage

/// Wird gezeigt, wenn der User während einer laufenden Claude-Vision-
/// Analyse „Abbrechen" drückt. Statt komplett rauszuspringen zeigen wir
/// hier das bereits gewählte Bild nochmal — damit der User entscheiden
/// kann: nochmal versuchen (eventuell besseres WLAN / Server wieder da)
/// oder zurück zur Scan-Übersicht.
private struct FreierTextCancelledView: View {
    let image: UIImage
    let onRetry: () -> Void
    let onBack: () -> Void

    private let sectionStyle: AppSectionStyle = .scan

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: Close (= zurück) oben rechts
                HStack {
                    Spacer()
                    Button(action: onBack) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(AppTheme.Colors.secondarySurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, AppTheme.Spacing.md)

                Spacer()

                // Bild-Vorschau
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(sectionStyle.accent.opacity(0.35), lineWidth: 1.2)
                    )
                    .padding(.horizontal, AppTheme.Layout.screenPadding)

                // Info-Text
                VStack(spacing: AppTheme.Spacing.xs) {
                    Text("Analyse abgebrochen")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Möchtest du es nochmal versuchen?")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, AppTheme.Spacing.lg)

                Spacer()

                // Action-Buttons
                VStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: onRetry) {
                        Text("Nochmal analysieren")
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.Layout.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                    .fill(AppTheme.Colors.cta)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onBack) {
                        Text("Zurück")
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.Layout.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                    .fill(AppTheme.Colors.secondarySurface)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }
}
