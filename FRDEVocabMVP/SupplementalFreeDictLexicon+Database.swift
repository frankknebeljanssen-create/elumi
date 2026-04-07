import Foundation
import SQLite3

extension SupplementalFreeDictLexicon {
    static func withReadOnlyDatabase<T>(_ body: (OpaquePointer) -> T?) -> T? {
        guard let url = Bundle.main.url(forResource: "FRDEFreeDictSupplement", withExtension: "sqlite") else {
            return nil
        }

        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }

        defer { sqlite3_close(database) }
        return body(database)
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
}
