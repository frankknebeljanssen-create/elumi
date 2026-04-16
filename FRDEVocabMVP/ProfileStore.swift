import Foundation
import SwiftUI

/// Zentrale, lokale Profilverwaltung. **Single Source of Truth** für das
/// aktive Nutzerprofil auf diesem Gerät.
///
/// Bewusste Trennung der Stores — jede Domäne hat ihren eigenen Container:
/// • `ProfileStore`  → persönliche Identität (Name, Lernziel, Avatar)
/// • `ProgressStore` → Fortschritt (XP, Credits, Streak, Level)
/// • `@AppStorage`   → App-Präferenzen (Sound, Direction, …)
/// • Auth-Store      → existiert bewusst noch nicht, kommt als eigener Store
///
/// V1 persistiert lokal in UserDefaults als Codable-JSON. Die API ist so
/// gewählt, dass ein späterer Umzug auf Keychain + Cloud-Sync ohne Änderung
/// der Call-Sites möglich ist — Views greifen nur über `shared` zu und nutzen
/// Published-Properties.
@MainActor
final class ProfileStore: ObservableObject {
    /// App-weiter Singleton. Analog zu `ProgressStore.shared`.
    static let shared = ProfileStore()

    /// Das aktive Profil. `nil`, solange das Onboarding noch nicht durchlaufen
    /// wurde (Erstinstall ohne Legacy-Migration).
    @Published private(set) var profile: LearnerProfile?

    /// `true`, sobald der User das Onboarding einmal abgeschlossen hat
    /// (oder eine Legacy-Migration ein Profil erstellt hat). Root-View
    /// nutzt diesen Flag zum Gaten der Onboarding-UI.
    @Published private(set) var hasCompletedOnboarding: Bool

    private let storageKey = appLearnerProfileKey
    private let onboardingKey = appOnboardingCompletedKey

    init() {
        let defaults = UserDefaults.standard
        self.hasCompletedOnboarding = defaults.bool(forKey: appOnboardingCompletedKey)
        if let data = defaults.data(forKey: appLearnerProfileKey),
           let decoded = try? JSONDecoder().decode(LearnerProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = nil
        }
        // Legacy-Migration nach Laden versuchen — für Altnutzer, die die
        // App schon mit `appFirstNameKey` verwendet haben, bevor es ein
        // ProfileStore gab. Kein Onboarding-Zwang nach App-Update.
        migrateLegacyFirstNameIfNeeded()
    }

    // MARK: - Public API

    /// Schließt das Onboarding ab und erstellt das initiale Profil.
    func completeOnboarding(displayName: String, learningGoal: LearningGoal?) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProfile = LearnerProfile(
            displayName: trimmed,
            learningGoal: learningGoal,
            lastActiveAt: Date()
        )
        self.profile = newProfile
        self.hasCompletedOnboarding = true
        persist()
        persistOnboardingFlag()
        mirrorToLegacyFirstName()
    }

    /// Atomisches Update — mutate-Pattern analog `ProgressStore.mutate`.
    /// Aufrufer ändern Felder in der Closure, Store übernimmt Persist.
    func update(_ change: (inout LearnerProfile) -> Void) {
        guard var current = profile else { return }
        change(&current)
        self.profile = current
        persist()
        mirrorToLegacyFirstName()
    }

    /// Leichtgewichtiges Update der `lastActiveAt`-Zeit. Vom Root-View
    /// einmal pro App-Start nach Onboarding-Abschluss getriggert.
    func touchLastActive() {
        update { $0.lastActiveAt = Date() }
    }

    // MARK: - Derived values
    //
    // Zentral berechnete Werte, damit kein Call-Site eigene String-Logik
    // (Trimming, Initialen-Parsing) halten muss.

    /// Anzeigename mit sicherem Fallback. Views können das direkt binden,
    /// ohne einen eigenen nil-Check zu machen.
    var displayName: String {
        let trimmed = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Freund*in" : trimmed
    }

    /// `true`, wenn ein echter Name gesetzt ist (für Personalisierungs-Gates).
    var hasName: Bool {
        let trimmed = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    /// Initialen für den Avatar-Badge. Max. 2 Zeichen, Uppercase.
    /// Fallback ist `?`, wird im Avatar-Badge als Person-Icon gerendert.
    var initials: String {
        guard let name = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2,
           let first = parts.first?.first,
           let second = parts.dropFirst().first?.first {
            return String([first, second]).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    // MARK: - Persistence

    private func persist() {
        guard let profile, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func persistOnboardingFlag() {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
    }

    /// Spiegelt den Anzeigenamen in den Legacy-`appFirstNameKey`-Slot,
    /// damit Views, die noch direkt auf @AppStorage lesen (während der
    /// Migrations-Übergangsphase), einen konsistenten Wert sehen.
    /// Sobald alle Call-Sites auf ProfileStore migriert sind, kann der
    /// Mirror entfernt werden, ohne Daten zu verlieren.
    private func mirrorToLegacyFirstName() {
        guard let profile else { return }
        UserDefaults.standard.set(profile.displayName, forKey: appFirstNameKey)
    }

    /// Wenn es noch kein Profil gibt, aber ein Legacy-firstName explizit
    /// persistiert wurde (Altinstall), erzeugen wir daraus ein minimales
    /// Profil und setzen `hasCompletedOnboarding`. Das spart dem User den
    /// Willkommens-Dialog nach einem App-Update.
    private func migrateLegacyFirstNameIfNeeded() {
        guard profile == nil else { return }
        guard let legacy = UserDefaults.standard.object(forKey: appFirstNameKey) as? String else {
            return
        }
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.profile = LearnerProfile(displayName: trimmed, lastActiveAt: Date())
        self.hasCompletedOnboarding = true
        persist()
        persistOnboardingFlag()
    }
}
