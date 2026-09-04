import Foundation

/// **Codeaudit 2026-09-03, Stufe 3 (Punkt 18)** — Selbsttest fuer das
/// Eigentumsmodell der per-Account isolierten UserDefaults-Keys.
///
/// Der eigentliche Fehler war kein Tippfehler, sondern eine fehlende
/// Regel: Es gab eine einzige Key-Liste, und die Swap-Maschine im
/// `AccountStore` kopierte jeden Eintrag blind in beide Richtungen.
/// Fuer Keys, die ein Store selbst namespaced schreibt, hat das beim
/// Account-Wechsel frische Daten mit dem veralteten Bare-Wert
/// ueberschrieben.
///
/// Diese Suite haelt die Regel fest, damit ein spaeter hinzugefuegter
/// Key nicht still in die falsche Liste rutscht:
///
///   1. Kein Key steht in beiden Listen.
///   2. Innerhalb einer Liste gibt es keine Duplikate.
///   3. `allKeys` ist wirklich die Vereinigung beider Listen.
///   4. Kein Key traegt bereits ein Namespace-Trennzeichen — die
///      Listen enthalten ausschliesslich Base-Keys.
///
/// Aufruf: `AccountScopedKeysTests.runIfNeeded()` beim App-Start,
/// dieselbe Test-Kultur wie `ArticleModeClassifierTests`.
enum AccountScopedKeysTests {

    static func runIfNeeded() {
        #if DEBUG
        runAllTests()
        #endif
    }

    #if DEBUG
    private static var failures = 0

    static func runAllTests() {
        failures = 0
        let storeOwned = AccountScopedKeys.storeOwnedKeys
        let appStorageOwned = AccountScopedKeys.appStorageOwnedKeys

        // 1. Keine Ueberschneidung — ein Key hat genau einen Eigentuemer.
        let overlap = Set(storeOwned).intersection(Set(appStorageOwned))
        expect(
            overlap.isEmpty,
            "Keys in beiden Eigentums-Listen: \(overlap.sorted().joined(separator: ", "))"
        )

        // 2. Keine Duplikate innerhalb einer Liste.
        expect(
            Set(storeOwned).count == storeOwned.count,
            "storeOwnedKeys enthaelt Duplikate"
        )
        expect(
            Set(appStorageOwned).count == appStorageOwned.count,
            "appStorageOwnedKeys enthaelt Duplikate"
        )

        // 3. allKeys ist die Vereinigung — sonst verliert die
        //    einmalige Migration stillschweigend Keys.
        expect(
            Set(AccountScopedKeys.allKeys) == Set(storeOwned).union(appStorageOwned),
            "allKeys ist nicht die Vereinigung beider Listen"
        )

        // 4. Nur Base-Keys, keine bereits gescopten.
        let separator = AccountStore.keyNamespaceSeparator
        let alreadyScoped = AccountScopedKeys.allKeys.filter { $0.contains(separator) }
        expect(
            alreadyScoped.isEmpty,
            "Bereits gescopte Keys in der Liste: \(alreadyScoped.joined(separator: ", "))"
        )

        if failures == 0 {
            appDebugLog("✅ [AccountScopedKeysTests] \(AccountScopedKeys.allKeys.count) Keys, Eigentumsmodell konsistent")
        } else {
            appDebugLog("❌ [AccountScopedKeysTests] \(failures) Fehler")
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        appDebugLog("❌ [AccountScopedKeysTests] \(message)")
    }
    #endif
}
