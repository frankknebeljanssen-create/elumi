import SwiftUI
import UIKit

/// Loading-/API-Request-Stage des „Freier Text"-Flows.
///
/// Einziger Job: Bild zeigen, Claude-Vision-Request ausführen, per
/// Callback nach oben melden. Bewusst **keine** eigene Sheet/Navigation-
/// Logik — die `FreierTextAnalysisFlowView` steuert den Stage-Wechsel
/// (`onSuccess`/`onFailure`). So bleibt der Flow an einem Ort steuerbar.
///
/// Die API-Anfrage wird in `task { … }` gestartet, damit der SwiftUI-
/// Lifecycle die Task automatisch cancelt, wenn der Nutzer die View
/// verlässt (Dismiss → keine orphan-Netzwerk-Calls).
struct FreierTextProcessingView: View {
    let image: UIImage
    let onSuccess: (FreeTextResult) -> Void
    /// Typ-spezifischer Fehler statt plain `String`, damit der Parent
    /// zwischen Netzwerk-/HTTP-/Decode-Fehlern unterscheiden und passende
    /// user-facing Meldungen + Retry-Optionen anbieten kann.
    let onFailure: (FreierTextError) -> Void
    /// Callback für den „Abbrechen"-Button. Parent kann dismissen und
    /// das Pending-Image zurücksetzen — optional, damit der Screen in
    /// alten Call-Sites (Tests) auch ohne Cancel-Support funktioniert.
    var onCancel: (() -> Void)? = nil

    @State private var hasStarted = false
    @State private var elapsedSeconds: Int = 0

    /// Timeout in Sekunden — nach dieser Zeit wird der Request als
    /// hängend betrachtet und automatisch der Fehler-Callback gefeuert.
    /// Der Nutzer muss nicht die App neu starten.
    private let timeoutSeconds = 90

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top: nur Close-Button (User-Feedback: der Mode-
                // Badge saß hier im Safe-Area-Schatten und war teils
                // abgeschnitten). Das Badge wandert unter den
                // Sekunden-Counter in den Center-Stack, wo es garantiert
                // sichtbar ist und unter dem Bild auch thematisch gut
                // passt („das analysiert den Freien Text").
                if onCancel != nil {
                    HStack {
                        Button(action: { onCancel?() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(AppTheme.Colors.secondarySurface))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Abbrechen")
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Layout.screenPadding)
                    .padding(.top, AppTheme.Spacing.md)
                }

                Spacer()

                // Vorschau des analysierten Bildes — hilft dem Nutzer zu
                // verstehen, **was** gerade analysiert wird, ohne Zusatz-UI.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(AppSectionStyle.scan.accent.opacity(0.35), lineWidth: 1.2)
                    )
                    .padding(.horizontal, AppTheme.Layout.screenPadding)

                VStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppSectionStyle.scan.accent))
                        .scaleEffect(1.5)
                    Text("Analysiere Text…")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    // Dezenter Elapsed-Counter. Gibt dem Nutzer ein
                    // Gefühl dafür, dass etwas passiert — ohne
                    // „falsche Genauigkeit" (API-Progress kennen wir
                    // nicht). Erst ab 3s sichtbar, damit bei
                    // schnellen Responses kein flackernder Zähler
                    // aufpoppt.
                    if elapsedSeconds >= 3 {
                        // Sekunden + KI-Aktivitäts-Hinweis nebeneinander
                        // (User-Wunsch: „kleine Info über KI-Verwendung
                        // /Analyse aktiv"). Pille mit Sparkles-Icon
                        // signalisiert dem User, dass eine externe KI
                        // (Claude Vision API) gerade arbeitet — keine
                        // App-interne Pseudo-Animation.
                        HStack(spacing: 8) {
                            Text("\(elapsedSeconds)s")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text("KI analysiert")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(AppSectionStyle.scan.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(AppSectionStyle.scan.accent.opacity(0.14))
                            )
                            .overlay(
                                Capsule().stroke(AppSectionStyle.scan.accent.opacity(0.35), lineWidth: 0.8)
                            )
                        }
                    }
                    // Mode-Badge direkt unter dem Counter — hier ist
                    // immer Platz und der User sieht klar, dass gerade
                    // der FreeText-Pfad läuft.
                    ScanModeBadge(mode: .text, variant: .card)
                        .padding(.top, 4)
                }
                .padding(.top, AppTheme.Spacing.xl)

                Spacer()

                // Footer: prominenter Abbrechen-Button
                if onCancel != nil {
                    footerBar
                }
            }
        }
        .task {
            // `task` wird bei jedem Mount ausgeführt, auch nach einem
            // Stage-Wechsel zurück auf Processing. `hasStarted` schützt
            // vor Mehrfach-Requests, falls SwiftUI die View zwischenrein
            // neu instanziiert.
            guard !hasStarted else { return }
            hasStarted = true
            await runAnalysis()
        }
        .task {
            // Parallel-Task für Elapsed-Counter + Timeout-Überwachung.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    elapsedSeconds += 1
                    // Timeout: nach 90s gilt der Request als hängend →
                    // Fehler melden, damit der Nutzer nicht ewig wartet
                    // oder die App neu starten muss.
                    if elapsedSeconds >= timeoutSeconds {
                        onFailure(.networkFailure(
                            underlying: URLError(.timedOut)
                        ))
                    }
                }
            }
        }
    }

    private var footerBar: some View {
        Button {
            onCancel?()
        } label: {
            Text("Abbrechen")
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
        .padding(.horizontal, AppTheme.Layout.screenPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func runAnalysis() async {
        guard let client = FreierTextClaudeClient.fromEnvironment() else {
            print("📄 [FreierText] ❌ kein API-Key konfiguriert")
            await MainActor.run {
                onFailure(.missingAPIKey)
            }
            return
        }

        do {
            let result = try await client.analyze(image: image)
            // Zwischen `await` und `MainActor.run` kann der Lifecycle
            // bereits gecancelled sein (User hat Abbrechen getippt) —
            // dann nicht mehr `onSuccess` feuern, sonst leuchtet kurz
            // das Result-UI auf, bevor der Parent dismissed.
            try Task.checkCancellation()
            await MainActor.run {
                onSuccess(result)
            }
        } catch is CancellationError {
            // User hat den Flow abgebrochen — kein Fehler-Alert zeigen.
            // Parent dismissed ohnehin via `onCancel`-Callback.
            print("📄 [FreierText] task cancelled")
        } catch let error as FreierTextError {
            // URLSession-Cancellation landet als `.networkFailure` mit
            // `URLError.cancelled` im underlying-Error. Das ist KEIN
            // echter Fehler — es ist der Nutzer der abbricht. Filtern,
            // damit keine irritierende „Verbindungsproblem"-Alert
            // aufpoppt.
            if case .networkFailure(let underlying) = error,
               (underlying as? URLError)?.code == .cancelled {
                print("📄 [FreierText] URLSession cancelled (user abort)")
                return
            }
            if Task.isCancelled {
                print("📄 [FreierText] task cancelled (after throw)")
                return
            }
            print("📄 [FreierText] ❌ analyze failed: \(error.localizedDescription)")
            await MainActor.run {
                onFailure(error)
            }
        } catch {
            // Sollte nicht passieren — der Client throwt ausschließlich
            // `FreierTextError`. Fallback, damit wir auf keinen Fall
            // silent failen.
            if Task.isCancelled { return }
            print("📄 [FreierText] ❌ unexpected error: \(error.localizedDescription)")
            await MainActor.run {
                onFailure(.invalidResponse)
            }
        }
    }
}
