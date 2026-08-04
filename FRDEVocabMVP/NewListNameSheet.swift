import SwiftUI

/// **Namensabfrage** für den Pfad „In neue Liste importieren"
/// (User-Spec 2026-04-23 morgens).
///
/// Erscheint nach `ImportTargetChoiceSheet`, wenn der User „neue Liste"
/// gewählt hat. Vorher wurde direkt der bestehende `ensureCustomList(...)`
/// mit einem auto-generierten Namen aufgerufen — das hat dem User die
/// Kontrolle über den Namen genommen.
///
/// Zwei CTAs:
///   • „Liste erstellen" — verwendet den eingegebenen Namen (nur aktiv
///     bei nicht-leerem Trim-Input)
///   • „Automatisch benennen" — fallback auf Zeitstempel-Format
///     `YYYY_MM_DD_HH_mm` (siehe `AutomaticListNameFactory.makeName`)
///
/// **Produktregeln**:
///   • Texteingabe-Feld startet IMMER leer (kein vorausgefüllter Name)
///   • „Liste erstellen" disabled bei leerem Trim
///   • „Automatisch benennen" immer aktiv
///   • Nach Tap: Sheet schließt sich, Caller bekommt Name via Callback
struct NewListNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isNameFieldFocused: Bool
    let onCreate: (String) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                introText
                    .padding(.top, 8)

                nameField
                    .padding(.top, 4)

                Spacer()

                actionButtons
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Wie soll die Lernliste heißen?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear {
                // Field bewusst LEER lassen (User-Spec).
                name = ""
                // Tastatur direkt aufploppen, damit User sofort tippen kann.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isNameFieldFocused = true
                }
            }
        }
    }

    // MARK: - Subviews

    private var introText: some View {
        Text("Wähle einen Namen für deine neue Lernliste — oder lass dir automatisch einen Zeitstempel geben.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nameField: some View {
        TextField("Lernlistenname", text: $name)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .focused($isNameFieldFocused)
            .submitLabel(.done)
            .onSubmit {
                if canCreate { confirmCreate(name: trimmedName) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isNameFieldFocused ? AppTheme.Colors.cta : AppTheme.Colors.border, lineWidth: isNameFieldFocused ? 1.5 : 1)
            )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                guard canCreate else { return }
                confirmCreate(name: trimmedName)
            } label: {
                Text("Lernliste erstellen")
                    .font(AppTheme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .disabled(!canCreate)
            .opacity(canCreate ? 1.0 : 0.55)

            Button {
                let auto = AutomaticListNameFactory.makeName()
                confirmCreate(name: auto)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Automatisch benennen")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppTheme.Colors.cta)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Colors.cta.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Colors.cta.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func confirmCreate(name: String) {
        isNameFieldFocused = false
        dismiss()
        DispatchQueue.main.async { onCreate(name) }
    }
}

// MARK: - Auto-Name-Factory

/// Zentrale Hilfsfunktion: erzeugt einen Listen-Namen im exakten
/// Format `YYYY_MM_DD_HH_mm`. Geräte-/App-Lokalzeit, keine
/// Lokalisierung, nur Zahlen und Unterstriche.
///
/// Beispiel: `2026_04_23_14_37`
enum AutomaticListNameFactory {
    static func makeName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        // POSIX-Locale, damit das Format unabhängig von der User-Locale
        // ist (sonst landen z. B. arabische Ziffern oder andere Trenner
        // im Output).
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy_MM_dd_HH_mm"
        return formatter.string(from: now)
    }
}
