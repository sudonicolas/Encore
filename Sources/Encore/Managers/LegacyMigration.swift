import AppKit

/// One-time carry-over from when the app was called "clipboard" (bundle ID
/// `com.clipboard.mac`). The new bundle ID means a new preferences domain and a new
/// Application Support folder, so without this the history would appear to vanish.
enum LegacyMigration {
    private static let legacyBundleID = "com.clipboard.mac"
    private static let legacyFolderName = "clipboard"
    private static let dataFiles = ["clippings.json", "deleted-clippings.json", "ignored-apps.json"]
    private static let completedKey = "didMigrateFromClipboard"

    /// Copies settings and moves history into place. Runs before the store reads either,
    /// and only once: after that, the old locations are left alone.
    static func runIfNeeded(settingsKeys: [String], supportDirectory: URL) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: completedKey) else { return }
        defer { defaults.set(true, forKey: completedKey) }

        migrateSettings(settingsKeys + ["NSWindow Frame HistoryWindow"], into: defaults)
        migrateFiles(into: supportDirectory)
    }

    private static func migrateSettings(_ keys: [String], into defaults: UserDefaults) {
        guard let legacy = defaults.persistentDomain(forName: legacyBundleID) else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
    }

    /// Moves (not copies) the files: they hold clipboard history, which shouldn't be left
    /// behind in a second place. Files already present at the destination win.
    private static func migrateFiles(into destination: URL) {
        let fileManager = FileManager.default
        let legacyDirectory = destination
            .deletingLastPathComponent()
            .appendingPathComponent(legacyFolderName, isDirectory: true)
        guard fileManager.fileExists(atPath: legacyDirectory.path) else { return }

        // The old app saves after every change, so quitting it loses nothing — and
        // leaving it running would split the history across two folders.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID) {
            app.terminate()
        }

        for name in dataFiles {
            let source = legacyDirectory.appendingPathComponent(name)
            let target = destination.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: target.path) else { continue }
            try? fileManager.moveItem(at: source, to: target)
        }

        // "clipboard" is a generic folder name, so only remove it if nothing else lives there.
        let remaining = (try? fileManager.contentsOfDirectory(atPath: legacyDirectory.path)) ?? []
        if remaining.allSatisfy({ $0 == ".DS_Store" }) {
            try? fileManager.removeItem(at: legacyDirectory)
        }
    }
}
