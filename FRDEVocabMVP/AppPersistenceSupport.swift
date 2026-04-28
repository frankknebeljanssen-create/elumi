import Foundation

enum AppPersistenceSupport {
    private static let fileManager = FileManager.default
    private static let persistenceFolderName = "Persistence"

    static func readData(
        named fileName: String,
        legacyDefaults: UserDefaults? = nil,
        legacyKey: String? = nil
    ) -> Data? {
        let url = dataURL(named: fileName)
        if let data = try? Data(contentsOf: url) {
            return data
        }

        guard let legacyDefaults, let legacyKey, let legacyData = legacyDefaults.data(forKey: legacyKey) else {
            return nil
        }

        writeData(legacyData, named: fileName)
        legacyDefaults.removeObject(forKey: legacyKey)
        return legacyData
    }

    static func writeData(_ data: Data, named fileName: String) {
        let url = dataURL(named: fileName)
        ensureDirectoryExists(for: url.deletingLastPathComponent())
        try? data.write(to: url, options: .atomic)
    }

    static func removeData(named fileName: String) {
        let url = dataURL(named: fileName)
        try? fileManager.removeItem(at: url)
    }

    /// Prüft, ob eine Daten-Datei am erwarteten Pfad existiert.
    /// **Wichtig** für die Unterscheidung „Fresh Install / Datei nicht
    /// vorhanden" vs. „Datei vorhanden aber korrupt" — letzteres ist
    /// ein Datenverlust-Signal und darf nicht still mit Defaults
    /// überschrieben werden.
    static func fileExists(named fileName: String) -> Bool {
        let url = dataURL(named: fileName)
        return fileManager.fileExists(atPath: url.path)
    }

    /// Liest reine Datei-Daten OHNE Legacy-UserDefaults-Fallback.
    /// Caller, die zwischen den beiden Quellen unterscheiden müssen,
    /// nutzen diesen Pfad statt `readData(named:legacyDefaults:legacyKey:)`.
    static func readDataIfFileExists(named fileName: String) -> Data? {
        let url = dataURL(named: fileName)
        return try? Data(contentsOf: url)
    }

    static func dataURL(named fileName: String) -> URL {
        persistenceDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    private static func persistenceDirectory() -> URL {
        let baseDirectory =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let bundleFolderName = Bundle.main.bundleIdentifier ?? "FRDEVocabMVP"
        let directory = baseDirectory
            .appendingPathComponent(bundleFolderName, isDirectory: true)
            .appendingPathComponent(persistenceFolderName, isDirectory: true)
        ensureDirectoryExists(for: directory)
        return directory
    }

    private static func ensureDirectoryExists(for directory: URL) {
        var isDirectory: ObjCBool = false
        let path = directory.path
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
