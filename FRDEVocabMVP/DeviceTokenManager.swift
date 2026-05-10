// DeviceTokenManager.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Anonymer Device-Token für
// die Backend-Auth (X-Device-Token-Header). Generiert einmalig pro
// Gerät, persistiert via iOS Keychain (`kSecClassGenericPassword`).
//
// Ohne Account-System nutzen wir den Token als Pseudo-Identifier für
// Rate-Limiting auf Backend-Seite (30 Messages/Tag). Da der Token im
// Keychain liegt, überlebt er App-Reinstall (auf demselben iCloud-
// Account) — würde User durch sauberes Login-System ersetzt, sobald
// Multi-User-Auth dazukommt.
//
// Native Security-Framework-API ohne Third-Party-Dependency
// (KeychainAccess o. ä.) — minimaler Footprint.

import Foundation
import Security

enum DeviceTokenManager {
    /// Service-Identifier — pro Bundle-Identifier eindeutig.
    private static let service = "com.frank.FRDEVocabMVP.deviceToken"

    /// Account-Slot — fix `default` für Schritt 1, weil's nur eine
    /// Léa-Konversation pro Gerät gibt. Bei Multi-User-Auth wird
    /// hier der Account-Identifier eingesetzt.
    private static let account = "default"

    /// Liefert den existierenden Token oder generiert + persistiert
    /// einen neuen. Idempotent: kann beliebig oft aufgerufen werden,
    /// bleibt stabil über App-Lifetime.
    static func getOrCreateToken() -> String {
        if let existing = readToken() {
            return existing
        }
        let token = UUID().uuidString
        saveToken(token)
        return token
    }

    /// Liest den Token aus dem Keychain. Liefert `nil` wenn kein
    /// Eintrag existiert oder der Read-Status fehlschlägt
    /// (z. B. Keychain-Lock auf Lock-Screen — sehr unwahrscheinlich,
    /// weil `AccessibleAfterFirstUnlock` den Read sofort nach
    /// erstem Unlock zulässt).
    private static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    /// Schreibt einen neuen Token in den Keychain. Existierende
    /// Einträge werden vorher gelöscht (defensiv, sollte nie
    /// vorkommen, weil `getOrCreateToken` nur bei `nil`-Read schreibt).
    @discardableResult
    private static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}
