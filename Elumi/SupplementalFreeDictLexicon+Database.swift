import Foundation
import SQLite3

/// **Codeaudit 2026-09-03, Stufe 3 (Punkt 21)** — die Lese-Verbindung
/// zur 26-MB-Lexikon-Datenbank wird einmal geoeffnet und offen
/// gehalten.
///
/// Vorher machte jeder einzelne Aufruf ein `sqlite3_open_v2` samt
/// `sqlite3_close`. Bei den Genus-Nachschlagen sind das Tausende
/// Oeffnungen hintereinander — die App misst sich selbst mit
/// `enrichMissingGenderInfo: 6758ms`. Das Oeffnen kostet Dateisystem-
/// Zugriff und wirft ausserdem jedes Mal SQLites eigenen Seiten-Cache
/// weg, sodass jede Abfrage wieder von Platte liest.
///
/// Die Datenbank liegt schreibgeschuetzt im App-Bundle, es gibt also
/// keine Schreiber und keine Konflikte. Ein `NSLock` serialisiert die
/// Zugriffe, damit sich zwei Threads nicht dieselbe Verbindung teilen —
/// SQLite-Handles vertragen das ohne weitere Vorkehrungen nicht.
private nonisolated(unsafe) var sharedReadOnlyDatabase: OpaquePointer?
private let sharedReadOnlyDatabaseLock = NSLock()
private nonisolated(unsafe) var didAttemptSharedDatabaseOpen = false

extension SupplementalFreeDictLexicon {
    static func withReadOnlyDatabase<T>(_ body: (OpaquePointer) -> T?) -> T? {
        sharedReadOnlyDatabaseLock.lock()
        defer { sharedReadOnlyDatabaseLock.unlock() }

        if !didAttemptSharedDatabaseOpen {
            didAttemptSharedDatabaseOpen = true
            openSharedReadOnlyDatabase()
        }

        guard let database = sharedReadOnlyDatabase else { return nil }
        return body(database)
    }

    /// Oeffnet die Verbindung genau einmal. Schlaegt das fehl, bleibt
    /// `sharedReadOnlyDatabase` nil und jeder Aufruf liefert nil — das
    /// entspricht dem bisherigen Verhalten bei einem fehlgeschlagenen
    /// `sqlite3_open_v2`, nur ohne den Versuch bei jedem Aufruf zu
    /// wiederholen.
    private static func openSharedReadOnlyDatabase() {
        guard let url = Bundle.main.url(forResource: "ElumiMasterLexicon", withExtension: "sqlite") else {
            appDebugLog("⚠️ [Lexikon] ElumiMasterLexicon.sqlite nicht im Bundle gefunden")
            return
        }

        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            appDebugLog("⚠️ [Lexikon] Lese-Verbindung fehlgeschlagen (Code \(result))")
            return
        }

        sharedReadOnlyDatabase = database
    }

    static func queryDistinctStrings(in database: OpaquePointer, sql: String, parameter: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }

        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, parameter, -1, sqliteTransient)

        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawText = sqlite3_column_text(statement, 0) else { continue }
            let value = String(cString: rawText)
            if !value.isEmpty {
                results.append(value)
            }
        }
        return results
    }

    static func queryFirstString(in database: OpaquePointer, sql: String, parameter: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }

        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, parameter, -1, sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawText = sqlite3_column_text(statement, 0) else {
            return nil
        }

        let value = String(cString: rawText)
        return value.isEmpty ? nil : value
    }

    static func sqliteTextColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let rawText = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: rawText)
    }

    static func sourceOnlyGender(for sourceTerm: String) -> String? {
        let lookupKey = normalizedLookupText(sourceTerm)
        guard !lookupKey.isEmpty else { return nil }
        return withReadOnlyDatabase { database in
            queryFirstString(
                in: database,
                sql: "SELECT gender_fr FROM entries WHERE LOWER(lemma_fr) = ? AND gender_fr != '' LIMIT 1;",
                parameter: lookupKey
            )
        }
    }
}
