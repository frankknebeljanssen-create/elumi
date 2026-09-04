import Foundation
import SwiftUI

/// **Multi-Account** — lokale, gerätegebundene Account-Identität.
///
/// Pro Gerät kann es mehrere Accounts geben (z. B. Vater + Kinder auf
/// demselben Family-iPad). Jeder Account trägt eine eigene Identität
/// (Name + Emoji-Avatar) und perspektivisch eigene Daten (Listen, XP,
/// Lernstatus, Streak). Die Account-Identität ist bewusst schlank —
/// kein Login, keine Passwörter, kein Server — und ergänzt das
/// bestehende `LearnerProfile` um eine Mehrbenutzer-Ebene.
///
/// **Trennung zum `LearnerProfile`**: Das `LearnerProfile` bleibt die
/// personalisierungs-taugliche Detail-Identität des aktiven Accounts
/// (Lernziel, Avatar-Stil, Präferenzen). `AccountProfile` hier ist die
/// **lightweight Account-Schicht** für die Multi-User-UI: was steht in
/// der Account-Liste, wer ist gerade angemeldet, wie viele gibt es.
/// Ein `AccountProfile` kann langfristig auf ein eigenes
/// `LearnerProfile` verweisen (UUID-verknüpft) — V1 genügt der Name +
/// Emoji.
struct AccountProfile: Codable, Equatable, Identifiable {
    /// Stabile UUID. Überlebt Umbenennungen. Wird perspektivisch als
    /// Namespace-Präfix für alle Per-Account-UserDefaults-Keys genutzt.
    var id: UUID

    /// Anzeigename. Wird in Avatar + Account-Switcher geführt.
    var displayName: String

    /// Emoji-Avatar (1–2 Unicode-Zeichen). Default „🐟" als Elumi-Bezug.
    /// Emoji wurde gewählt statt Asset, damit Kinder ohne Asset-Editor
    /// aus einem großen Pool wählen können — und damit Accounts sofort
    /// optisch unterscheidbar sind, auch ohne eigene Fotos.
    var avatarEmoji: String

    /// Erstelldatum — für spätere „Seit X Tagen"-Infos nutzbar.
    var createdAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        avatarEmoji: String = "🐟",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.createdAt = createdAt
    }
}

/// Zentraler Account-Store. **Single Source of Truth** für die Liste
/// aller lokalen Accounts auf diesem Gerät + welcher aktiv ist.
///
/// Rolle im System:
///   • `AccountStore`  → Wer benutzt gerade die App? (Multi-User)
///   • `ProfileStore`  → Persönliche Identität des aktiven Accounts
///   • `ProgressStore` → Fortschritt des aktiven Accounts
///
/// Persistenz:
///   • `appAccountListKey`       → Codable-JSON aller Accounts
///   • `appCurrentAccountIDKey`  → UUID-String des aktiven Accounts
///   • `appAccountsMigratedKey`  → Flag: V1-Daten-Migration durchgeführt
///
/// **V1-Scope (dieser Commit)**: Account-Liste + aktiver Account +
/// Create/Switch/Delete/Rename. **Daten-Isolation pro Account** (Listen,
/// XP, Streak) ist in Phase D vorgesehen — in V1 teilen sich alle
/// Accounts den globalen Datenpool. Der Switcher funktioniert trotzdem
/// als UX-Vorstufe, damit sich der Flow (Onboarding / Account-Picker)
/// testen lässt, bevor die Storage-Trennung eingebaut wird.
/// **Per-Account-Daten-Isolation** (Phase E): alle Per-Account-Stores
/// verwenden einen Key-Präfix, damit XP, Credits, Streak und die
/// Vokabel-Listen pro Account getrennt sind. Switch auf einen anderen
/// Account → Stores reloaden aus ihrer namespaced Lage.
///
/// `accountScopedKeys` listet alle Base-Keys auf, die per-Account
/// isoliert gespeichert werden. Die Liste ist zentral, damit Migration
/// + Reload-Hooks eine einzige Wahrheit haben.
enum AccountScopedKeys {

    // **Codeaudit 2026-09-03, Stufe 3 (Punkt 18) — Eigentumsmodell.**
    //
    // Bis hierher gab es EINE Liste, und die Swap-Maschine kopierte
    // beim Account-Wechsel jeden Key blind in beide Richtungen:
    // Bare-Slot -> Namespace (stash) und zurueck (unstash). Das ist nur
    // fuer Keys korrekt, die ausschliesslich ueber `@AppStorage` im
    // globalen Slot leben.
    //
    // Fuer Keys, die ein Store selbst namespaced schreibt, war es
    // zerstoererisch: der Store schreibt in den Namespace, der
    // Bare-Slot bleibt auf dem Stand der einmaligen Migration stehen —
    // und beim naechsten Account-Wechsel kopiert `stash` genau diesen
    // veralteten Bare-Wert ueber die frischen Store-Daten. Betroffen
    // waren unter anderem die eigenen Vokabellisten, das Lernerprofil,
    // die Daily Challenge, das Lernziel und der Tagesabschluss.
    //
    // Deshalb jetzt zwei Listen mit klarem Besitz:
    //
    //   • `storeOwnedKeys` — ein Store ist Eigentuemer und schreibt
    //     selbst ueber `AccountStore.namespacedKey(_:)`. Die
    //     Swap-Maschine fasst diese Keys NICHT an. Wo `@AppStorage`
    //     trotzdem den Bare-Key liest (XP, Credits, Streak), spiegelt
    //     der besitzende Store selbst — siehe `ProgressStore.persist`
    //     und `ProgressStore.reloadForCurrentAccount`.
    //
    //   • `appStorageOwnedKeys` — es gibt keinen Store, nur
    //     `@AppStorage` im globalen Slot. Nur diese Keys werden beim
    //     Account-Wechsel hin und her geswappt.
    //
    // `allKeys` ist die Vereinigung und bleibt die Grundlage der
    // einmaligen Migration aus der Single-User-Welt. Ein `#if DEBUG`-
    // Selbsttest (`AccountScopedKeysTests`) prueft, dass kein Key in
    // beiden Listen steht.

    /// Keys, deren Eigentuemer ein Store ist. **Niemals swappen.**
    static let storeOwnedKeys: [String] = [
        // ProgressStore — schreibt namespaced und spiegelt die vier
        // Werte mit `@AppStorage`-Lesern zusaetzlich in den Bare-Slot.
        appElumiXPKey,
        appArcadeCreditsKey,
        appElumiCurrentStreakKey,
        appElumiBestStreakKey,
        "elumi.gamification.lastSessionDay.v1",
        "elumi.gamification.lastDailyBonusDay.v1",
        "elumi.gamification.awardedStreakMilestones.v1",
        // VocabularyListStore — die eigenen Listen des Kindes.
        "FRDEVocabMVP.customLists.v2",
        "FRDEVocabMVP.selectedListID.v2",
        "FRDEVocabMVP.sampleListsSeeded.v1",
        // ProfileStore
        appLearnerProfileKey,
        appOnboardingCompletedKey,
        // DailyChallengeStore
        appDailyChallengeKey,
        // LearningGoalStore
        appLearningGoalPlanKey,
        appLearningGoalArchiveKey,
        // DailyWrapUpStore
        appDailyWrapUpDayKey,
        appDailyWrapUpReminderSlotKey
    ]

    /// Keys ohne Store — nur `@AppStorage` im globalen Slot. Diese
    /// werden beim Account-Wechsel geswappt.
    static let appStorageOwnedKeys: [String] = [
        // Lernziel-Nebenwerte. **Hinweis (2026-09-04)**: Beide Keys
        // werden aktuell nirgends gelesen oder geschrieben — sie
        // bleiben registriert, bis geklaert ist, ob sie noch gebraucht
        // werden.
        appLearningGoalPracticedDaysKey,
        appLearningGoalWeekIndexKey,
        // Spiel- und Belohnungswerte
        appQuizHeartsKey,
        appElumiWaterflohKey,
        appElumiAlgenkugelKey,
        appElumiLastRewardDayIndexKey,
        appElumiArcadeHighScoreKey,
        // Listen-Auswahl pro Modul
        appTrainingSelectedListIDsKey,
        // **Pre-existing-Bugfix Stufe 5 Schritt 2 (2026-04-30)**: die
        // Per-Mode-v2-Keys (vocabulary/nouns/articles/verbs/verbforms)
        // waren bisher NICHT account-scoped, obwohl ihre v1-Legacy-
        // Variante (`appTrainingSelectedListIDsKey`) registriert ist.
        // Side-Effect: bei Account-Wechsel haben Trainings-Modes ihre
        // Listen-Selektion vom alten Account behalten.
        trainingSelectedListIDsKey(for: TrainingMode.vocabulary.storageKey),
        trainingSelectedListIDsKey(for: TrainingMode.nouns.storageKey),
        trainingSelectedListIDsKey(for: TrainingMode.articles.storageKey),
        trainingSelectedListIDsKey(for: TrainingMode.verbs.storageKey),
        trainingSelectedListIDsKey(for: TrainingMode.verbforms.storageKey),
        appQuizSelectedListIDsKey,
        appFlashcardsSelectedListIDsKey,
        appFlashcardsMasteryThresholdKey,
        // Onboarding-Hints (UX Stufe 4) — neu angelegte Accounts
        // sollen den Trainings-Generator-Hint einmal sehen, auch wenn
        // der Owner-Account ihn schon weggeklickt hat.
        appTrainingGeneratorOnboardingSeenKey,
        // Trainings-Generator Default-Trainingsdauer (Sache B,
        // 2026-04-29) — pro Account isoliert, sodass jeder Nutzer
        // seine eigene zuletzt gewaehlte Dauer behaelt.
        appTrainingGeneratorDurationKey,
        // Globale Listen-Auswahl (Stufe 5, 2026-04-29) — Toggle +
        // UUID-Set, pro Account isoliert.
        appUseGlobalListSelectionKey,
        appGlobalSelectedListIDsKey,

        // **Codeaudit 2026-09-03, Stufe 3 (Punkt 18, zweiter Teil)** —
        // die folgenden Werte waren bis 2026-09-04 GAR NICHT
        // account-getrennt: Geschwister auf einem Geraet teilten sich
        // persoenliche Stapel, Tagesaktivitaet, die Karteikarten-Session
        // und die Word-Runner-Bestwerte. Der Arcade-Highscore stand
        // dagegen sehr wohl in der Liste — die Trennung war also
        // gewollt, nur unvollstaendig.
        //
        // Alle diese Keys leben im globalen Slot, deshalb gehoeren sie
        // hierher und nicht zu `storeOwnedKeys`. **Wichtig**: Wo ein
        // Store einen solchen Wert im Speicher haelt, braucht er einen
        // `reloadForCurrentAccount()`-Hook — sonst schreibt der noch
        // geladene Store des vorigen Kindes seine Daten ueber die des
        // neuen. Siehe `PersonalDeckStore`, `DailyStatsStore` und
        // `FlashcardSessionStore`.

        // Word Runner + Daily Drop
        appLastCompletedDailyDropDateKey,
        appWordRunnerBestScoreKey,
        appWordRunnerTotalTrophiesKey,
        appWordRunnerLastListIDKey,
        // Lern-Einstellungen des Kindes
        appLernjahrMaxKey,
        appLeaFocusOnLessonKey,
        appDirectionKey,
        appFlashcardsSelectedCardCountKey,
        appAnswerModeKarteikartenKey,
        appAnswerModeVokabelnKey,
        appAnswerModeNomenKey,
        // PersonalDeckStore — die zwei persoenlichen Trainingsstapel.
        appPersonalDecksKey,
        // DailyStatsStore — Tagesaktivitaet.
        "elumi.dailyStats.actionsToday.v1",
        "elumi.dailyStats.lastSessionDelta.v1",
        "elumi.dailyStats.dayIndex.v1",
        // FlashcardSessionStore — laufende Karteikarten-Session + Stapelwahl.
        "FRDEVocabMVP.flashcardSession.v1",
        "FRDEVocabMVP.flashcardDeck.v1"

        // **Bewusst NICHT account-getrennt**: die TTS-Stimmenauswahl
        // (`appVoiceGermanSelectionKey` / `appVoiceFrenchSelectionKey`).
        // Das ist eine Geraete-Audio-Einstellung, keine Lerndaten —
        // welche Systemstimme gut klingt, haengt am Geraet, nicht am Kind.
    ]

    /// Alle per-Account isolierten Keys. Grundlage der einmaligen
    /// Migration aus der Single-User-Welt — die kopiert bare ->
    /// namespaced und ist fuer beide Sorten korrekt, weil sie nur
    /// schreibt, wenn im Namespace noch nichts steht.
    static let allKeys: [String] = storeOwnedKeys + appStorageOwnedKeys
}

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    /// Trennzeichen zwischen Account-UUID und Base-Key. Bewusst `/` —
    /// kommt in UserDefaults-Keys regulär nicht vor und macht die
    /// Scope-Zugehörigkeit beim Debug-Dump sofort erkennbar.
    static let keyNamespaceSeparator = "/"

    /// Liefert den per-Account-Key für den Base-Key. Wenn kein Account
    /// aktiv ist (Erstinstall vor Onboarding-Abschluss), fällt auf den
    /// unpräfixten Base-Key zurück — Daten landen dann im globalen
    /// Slot, bis der erste Account angelegt ist.
    func namespacedKey(_ baseKey: String) -> String {
        guard let id = currentAccountID else { return baseKey }
        return "\(id.uuidString)\(Self.keyNamespaceSeparator)\(baseKey)"
    }

    /// Alle lokal bekannten Accounts. Bei leerem Array greift das
    /// Root-UI das Onboarding für den allerersten Account.
    @Published private(set) var accounts: [AccountProfile] = []

    /// Aktive Account-UUID. `nil` = noch kein Account ausgewählt
    /// (typisch beim Erstinstall, bevor Onboarding durchlaufen ist).
    @Published private(set) var currentAccountID: UUID?

    init() {
        loadFromDefaults()
        runMigrationIfNeeded()
    }

    // MARK: - Derived

    var currentAccount: AccountProfile? {
        guard let id = currentAccountID else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    /// `true`, wenn mindestens ein Account angelegt ist. Root-UI nutzt
    /// das, um zwischen Onboarding und normaler App zu unterscheiden.
    var hasAnyAccount: Bool { !accounts.isEmpty }

    // MARK: - Create / Switch / Delete / Rename

    /// Legt einen neuen Account an **und** schaltet auf diesen um.
    /// Wird von der Onboarding-View und vom Account-Switcher gerufen.
    /// Trimmt Namen defensiv (leere Namen werden als „Neuer Account"
    /// gespeichert — Defensive, weil Onboarding die UI-seitige
    /// Validierung bereits macht).
    @discardableResult
    func createAccount(name: String, emoji: String = "🐟") -> AccountProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Neuer Account" : trimmed
        let account = AccountProfile(displayName: finalName, avatarEmoji: emoji)
        // Gleiche Swap-Logik wie beim Switch: Werte des vorigen
        // Accounts in seinen Namespace stashen, bevor wir umschalten.
        // Neuer Account hat (noch) keinen Namespace-Inhalt, deshalb
        // cleart `unstashNamespaceIntoGlobalSlot()` den globalen Slot
        // zurück auf Defaults — frischer Start für den neuen User.
        stashGlobalSlotIntoCurrentNamespace()
        accounts.append(account)
        currentAccountID = account.id
        persist()
        unstashNamespaceIntoGlobalSlot()
        // Neue Identität → Stores reloaden, ProfileStore-Namen syncen.
        applyPostSwitchSideEffects()
        return account
    }

    /// Wechselt den aktiven Account. No-op, wenn die ID unbekannt ist
    /// (defensiv — verhindert Ghost-IDs, wenn der Caller eine veraltete
    /// Referenz hält). Nach dem Wechsel:
    ///   • Per-Account-Stores (Progress) reloaden aus dem neuen
    ///     Namespace.
    ///   • Personalisierungs-Stores (ProfileStore) übernehmen den
    ///     Namen des neuen Accounts, damit „Salut, …"-Greetings
    ///     überall sofort stimmen.
    func switchAccount(to id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        // **Phase E.5 Swap-Pattern**: bevor wir die aktive ID wechseln,
        // den globalen Slot (wo `@AppStorage` liest/schreibt) in den
        // Namespace des **alten** Accounts stashen. Danach ID wechseln
        // und den Namespace des **neuen** Accounts wieder in den
        // globalen Slot hebeln. So sehen @AppStorage-Views nach dem
        // Switch den korrekten Wert des neuen Users, und die Werte
        // des vorigen Users sind sauber in seinem Namespace abgelegt.
        stashGlobalSlotIntoCurrentNamespace()
        currentAccountID = id
        persistCurrentAccountID()
        unstashNamespaceIntoGlobalSlot()
        applyPostSwitchSideEffects()
    }

    /// Löscht einen Account. Schaltet automatisch auf einen der
    /// verbleibenden (falls der gelöschte aktiv war). Wenn kein Account
    /// mehr übrig ist, wird `currentAccountID` auf `nil` gesetzt — die
    /// Root-UI zeigt dann wieder Onboarding.
    func deleteAccount(id: UUID) {
        accounts.removeAll(where: { $0.id == id })
        if currentAccountID == id {
            currentAccountID = accounts.first?.id
        }
        persist()
    }

    /// Namenswechsel eines Accounts. Leere Namen werden verworfen
    /// (kein Update, kein Crash). Wenn der aktive Account umbenannt
    /// wird, syncen wir den Namen sofort in den `ProfileStore`, damit
    /// alle personalisierten Views (Greeting „Salut, …", Avatar-
    /// Initialen etc.) den neuen Namen zeigen.
    func rename(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].displayName = trimmed
        persist()
        if id == currentAccountID {
            syncProfileStoreFromActiveAccount()
        }
    }

    /// Wechsel des Emojis eines Accounts.
    func updateEmoji(id: UUID, to emoji: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].avatarEmoji = emoji
        persist()
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: appAccountListKey),
           let decoded = try? JSONDecoder().decode([AccountProfile].self, from: data) {
            self.accounts = decoded
        }
        if let idString = defaults.string(forKey: appCurrentAccountIDKey),
           let id = UUID(uuidString: idString),
           accounts.contains(where: { $0.id == id }) {
            self.currentAccountID = id
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: appAccountListKey)
        }
        persistCurrentAccountID()
    }

    private func persistCurrentAccountID() {
        let defaults = UserDefaults.standard
        if let id = currentAccountID {
            defaults.set(id.uuidString, forKey: appCurrentAccountIDKey)
        } else {
            defaults.removeObject(forKey: appCurrentAccountIDKey)
        }
    }

    // MARK: - Swap-Pattern (Phase E.5)
    //
    // `@AppStorage`-Property-Wrapper sind an einen festen Key gebunden.
    // Um Multi-Account-fähig zu bleiben **ohne** jede Call-Site
    // umzubauen, kopieren wir die Werte beim Account-Wechsel zwischen
    // dem globalen Slot (wo `@AppStorage` liest) und dem account-
    // scoped Namespace hin und her.
    //
    //   • `stashGlobalSlotIntoCurrentNamespace()` — schreibt die
    //     `AccountScopedKeys.appStorageOwnedKeys` vom globalen Slot in
    //     den Namespace des **aktuellen** Accounts. Store-eigene Keys
    //     bleiben bewusst aussen vor (siehe Eigentumsmodell oben). Wird vor dem
    //     ID-Wechsel gerufen, damit die Daten des vorigen Users
    //     landen, wo sie hingehören.
    //
    //   • `unstashNamespaceIntoGlobalSlot()` — kopiert in die andere
    //     Richtung: vom Namespace des **neuen** Accounts in den
    //     globalen Slot. Wenn der Namespace leer ist (neuer Account),
    //     wird der globale Slot geleert → @AppStorage-Views starten
    //     auf ihren Default-Werten.

    private func stashGlobalSlotIntoCurrentNamespace() {
        guard let _ = currentAccountID else { return }
        let defaults = UserDefaults.standard
        for base in AccountScopedKeys.appStorageOwnedKeys {
            let scoped = namespacedKey(base)
            if let value = defaults.object(forKey: base) {
                defaults.set(value, forKey: scoped)
            }
        }
    }

    private func unstashNamespaceIntoGlobalSlot() {
        let defaults = UserDefaults.standard
        for base in AccountScopedKeys.appStorageOwnedKeys {
            let scoped = namespacedKey(base)
            if let value = defaults.object(forKey: scoped) {
                defaults.set(value, forKey: base)
            } else {
                // Keine persistierten Daten im Namespace → Default-
                // Zustand. Globalen Slot leeren, damit der neue User
                // nicht die Zahlen des Vorgängers sieht.
                defaults.removeObject(forKey: base)
            }
        }
    }

    // MARK: - Post-Switch-Sync

    /// Notification, die nach jedem Account-Wechsel gefeuert wird.
    /// Stores, die nicht als Singleton laufen (z. B.
    /// `VocabularyListStore` ist Container-scoped), abonnieren dieses
    /// Event und rufen ihren eigenen `reloadForCurrentAccount()` auf.
    static let didSwitchAccount = Notification.Name("elumi.accounts.didSwitch.v1")

    /// Zentrale Hook, die nach jeder Änderung der aktiven-Account-
    /// Identität (Switch, Create, erste Aktivierung nach Migration)
    /// gerufen wird. Macht drei Dinge:
    ///   1. Per-Account-Singleton-Stores direkt reloaden
    ///      (`ProgressStore`).
    ///   2. Notification fan-out an Container-scoped Stores
    ///      (`VocabularyListStore` → via NotificationCenter).
    ///   3. `ProfileStore.displayName` auf den aktiven Account spiegeln
    ///      — alle personalisierten Stellen (Home-Greeting, Avatar-
    ///      Initialen, Session-End) lesen ProfileStore.
    private func applyPostSwitchSideEffects() {
        ProgressStore.shared.reloadForCurrentAccount()
        // **Codeaudit 2026-09-03, Stufe 1** — `StreakJokerStore` existierte
        // samt `reloadForCurrentAccount()` und dem Kommentar „Wird vom
        // AccountStore nach einem Account-Switch gerufen", wurde aber
        // nirgends aufgerufen. Ohne diese Zeile behielt ein neu
        // gewechselter Account den Joker-Verbrauch des vorigen — Kind B
        // erbte den verbrauchten Joker von Kind A und verlor seine Serie.
        StreakJokerStore.shared.reloadForCurrentAccount()
        // **Ziel-System (2026-08-05)** — Singleton wie ProgressStore, muss
        // deshalb direkt reloaden statt über die Notification. Ohne das
        // würde nach einem Account-Wechsel weiterhin das Ziel des vorigen
        // Kindes im Balken stehen.
        LearningGoalStore.shared.load()
        // Dito für den Tagesabschluss (2026-08-06) — sonst behielte der
        // neue Account den Abschluss-Status und die Erinnerungszeit des
        // vorigen.
        DailyWrapUpStore.shared.load()
        // **Wichtig**: `syncProfileStoreFromActiveAccount` läuft NICHT
        // hier. Die Notification unten triggert den `ProfileStore.
        // reloadForCurrentAccount()`, der das Profil frisch aus dem
        // Account-Namespace-Slot lädt. Ein zusätzlicher direkter
        // `update(…)`-Aufruf würde das alte Profil mit dem neuen Namen
        // in den neuen Slot schreiben und damit den existierenden
        // Profile-Payload des Ziel-Accounts zerstören. Für Rename
        // (siehe `rename`) ist der direkte Sync korrekt, weil dort
        // nur der Name geändert wird — keine Profil-Zerstörung.
        NotificationCenter.default.post(name: Self.didSwitchAccount, object: nil)
    }

    /// Aktualisiert den `ProfileStore.displayName` auf den aktiven
    /// Account-Namen. Wenn noch kein `LearnerProfile` existiert, legen
    /// wir das Onboarding als abgeschlossen mit dem Account-Namen an —
    /// das hält ProfileStore-Reader (Home-Greeting etc.) konsistent.
    private func syncProfileStoreFromActiveAccount() {
        guard let active = currentAccount else { return }
        let store = ProfileStore.shared
        if store.profile == nil {
            store.completeOnboarding(displayName: active.displayName, learningGoal: nil)
        } else {
            store.update { $0.displayName = active.displayName }
        }
    }

    // MARK: - Migration (Phase D)
    //
    // **One-Shot-Migration** aus der früheren Single-User-Welt in die
    // Account-Welt:
    //   1. Wenn bereits migriert → nichts tun.
    //   2. Wenn ein Legacy-`LearnerProfile` oder `appFirstNameKey`
    //      existiert → daraus einen ersten Account anlegen („Frank"
    //      als Test-Account des Geräte-Owners laut User-Ansage) und
    //      aktivieren. Datenfreier Neustart bei Neu-Install.
    //   3. Flag setzen, damit die Migration nur einmal läuft.
    //
    // **Wichtig**: Die Migration erzeugt bewusst **keinen** leeren
    // Account. Wenn der User noch nicht onboarded war, bleibt
    // `accounts == []` und die Root-UI zeigt das Onboarding.
    private func runMigrationIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: appAccountsMigratedKey) else { return }
        defer { defaults.set(true, forKey: appAccountsMigratedKey) }

        // Legacy-Profile lesen (Codable oder Legacy-FirstName-String).
        let legacyName: String? = {
            if let data = defaults.data(forKey: appLearnerProfileKey),
               let decoded = try? JSONDecoder().decode(LearnerProfile.self, from: data) {
                return decoded.displayName
            }
            return defaults.string(forKey: appFirstNameKey)
        }()

        let trimmed = legacyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            // Frischer Install — keine Legacy-Daten, kein Account
            // erzeugen. Root-UI zeigt Onboarding.
            return
        }

        // Legacy-User wird als Test-Account eingeführt. Emoji-Standard
        // 🐟 (Elumi-Bezug); User kann in den Settings umbenennen.
        let migrated = AccountProfile(displayName: trimmed, avatarEmoji: "🐟")
        accounts = [migrated]
        currentAccountID = migrated.id
        persist()

        // **Daten-Isolations-Migration** (Phase E): die Per-Account-
        // Stores lesen/schreiben ab jetzt unter dem account-präfixten
        // Key. Damit die existierenden Daten nicht „verschwinden",
        // kopieren wir alle bekannten Per-Account-UserDefaults-Keys
        // einmalig vom globalen Slot in den namespaced Slot des
        // gerade migrierten Accounts. Der globale Slot bleibt erhalten
        // (defensive Dual-Writes) — Stores, die ihn noch lesen, fallen
        // auf den alten Wert zurück. Sobald alle Call-Sites auf
        // namespaced Keys umgestellt sind, kann der globale Slot
        // gelöscht werden.
        let defs = UserDefaults.standard
        for base in AccountScopedKeys.allKeys {
            let scopedKey = namespacedKey(base)
            // Wenn im namespaced Slot schon was steht, nicht
            // überschreiben (idempotent bei Mehrfach-Start).
            guard defs.object(forKey: scopedKey) == nil else { continue }
            if let value = defs.object(forKey: base) {
                defs.set(value, forKey: scopedKey)
            }
        }
    }
}
