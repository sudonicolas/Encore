import Foundation
import Observation

/// Single source of truth for clipping history, ignored apps, and general settings.
/// Backed by JSON files in Application Support plus UserDefaults for scalar settings.
///
/// Pinning, deleting and restoring are announced to VoiceOver here rather than in the
/// views, so every path to them — buttons, menus, swipe actions, VoiceOver actions, Undo —
/// reports the same outcome.
@MainActor
@Observable
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var clippings: [Clipping] = []
    private(set) var deletedClippings: [Clipping] = []

    /// The most recent move to Recently Deleted, so the popover can offer an Undo toast.
    private(set) var lastTrash: TrashEvent?

    /// Deleted clippings older than this are purged automatically.
    static let recentlyDeletedRetentionDays = 30
    private var recentlyDeletedRetention: TimeInterval {
        TimeInterval(Self.recentlyDeletedRetentionDays) * 24 * 60 * 60
    }

    var ignoredApps: [IgnoredApp] = [] {
        didSet { saveIgnoredApps() }
    }

    var maxStoredCount: Int {
        didSet {
            UserDefaults.standard.set(maxStoredCount, forKey: Keys.maxStored)
            trimToLimit()
            saveClippings()
        }
    }

    var maxDisplayedCount: Int {
        didSet { UserDefaults.standard.set(maxDisplayedCount, forKey: Keys.maxDisplayed) }
    }

    var isRecordingEnabled: Bool {
        didSet { UserDefaults.standard.set(isRecordingEnabled, forKey: Keys.recording) }
    }

    var playSoundOnCopy: Bool {
        didSet { UserDefaults.standard.set(playSoundOnCopy, forKey: Keys.sound) }
    }

    /// Briefly swap the menu bar icon for a checkmark when something is recorded: the
    /// visual counterpart to the sound, for people who can't hear it or keep it off.
    var flashesMenuBarIconOnCopy: Bool {
        didSet { UserDefaults.standard.set(flashesMenuBarIconOnCopy, forKey: Keys.flash) }
    }

    /// Size of clipping text in the popover and the History window.
    var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: Keys.textSize) }
    }

    /// Skip pasteboard writes that password managers and similar apps mark as concealed,
    /// transient, or auto-generated (the nspasteboard.org conventions).
    var ignoresConcealedContent: Bool {
        didSet { UserDefaults.standard.set(ignoresConcealedContent, forKey: Keys.concealed) }
    }

    /// Give long text clippings a short title with the on-device Apple Intelligence model.
    var generatesSmartTitles: Bool {
        didSet {
            UserDefaults.standard.set(generatesSmartTitles, forKey: Keys.smartTitles)
            if generatesSmartTitles { SmartTitler.shared.processBacklog() }
        }
    }

    /// Offer definitions, encyclopedia summaries and currency conversions from free web
    /// services in a clipping's detail view.
    var offersOnlineLookups: Bool {
        didSet { UserDefaults.standard.set(offersOnlineLookups, forKey: Keys.onlineLookups) }
    }

    /// True when the user has set Encore to "Deny" in Privacy & Security → Paste from Other
    /// Apps, so nothing can be recorded. Refreshed by ClipboardMonitor.
    var isPasteboardAccessDenied = false

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            launchAtLoginError = LaunchAtLoginManager.setEnabled(launchAtLogin)
            launchAtLoginStatus = LaunchAtLoginManager.status
        }
    }

    /// Set when the launch-at-login system call fails, so Settings can surface it.
    var launchAtLoginError: String?
    /// Live login-item status; `.requiresApproval` means the user must allow it in System Settings.
    private(set) var launchAtLoginStatus: LaunchAtLoginManager.Status

    private enum Keys {
        static let maxStored = "maxStoredCount"
        static let maxDisplayed = "maxDisplayedCount"
        static let recording = "isRecordingEnabled"
        static let sound = "playSoundOnCopy"
        static let concealed = "ignoresConcealedContent"
        static let smartTitles = "generatesSmartTitles"
        static let onlineLookups = "offersOnlineLookups"
        static let flash = "flashesMenuBarIconOnCopy"
        static let textSize = "textSize"

        /// Settings that existed before the rename, carried over by LegacyMigration.
        static let legacy = [maxStored, maxDisplayed, recording, sound, concealed]
    }

    private let fileManager = FileManager.default
    private let supportDirectory: URL

    private var clippingsFileURL: URL { supportDirectory.appendingPathComponent("clippings.json") }
    private var deletedClippingsFileURL: URL { supportDirectory.appendingPathComponent("deleted-clippings.json") }
    private var ignoredAppsFileURL: URL { supportDirectory.appendingPathComponent("ignored-apps.json") }

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Encore", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        supportDirectory = base
        LegacyMigration.runIfNeeded(settingsKeys: Keys.legacy, supportDirectory: base)

        let defaults = UserDefaults.standard
        maxStoredCount = (defaults.object(forKey: Keys.maxStored) as? Int) ?? 200
        maxDisplayedCount = (defaults.object(forKey: Keys.maxDisplayed) as? Int) ?? 20
        isRecordingEnabled = (defaults.object(forKey: Keys.recording) as? Bool) ?? true
        playSoundOnCopy = (defaults.object(forKey: Keys.sound) as? Bool) ?? false
        ignoresConcealedContent = (defaults.object(forKey: Keys.concealed) as? Bool) ?? true
        generatesSmartTitles = (defaults.object(forKey: Keys.smartTitles) as? Bool) ?? true
        offersOnlineLookups = (defaults.object(forKey: Keys.onlineLookups) as? Bool) ?? true
        flashesMenuBarIconOnCopy = (defaults.object(forKey: Keys.flash) as? Bool) ?? false
        textSize = TextSize(rawValue: defaults.integer(forKey: Keys.textSize)) ?? .standard
        // The login item can be removed in System Settings behind our back, so the
        // system — not a cached default — is the source of truth.
        let status = LaunchAtLoginManager.status
        launchAtLoginStatus = status
        launchAtLogin = status == .enabled || status == .requiresApproval

        loadClippings()
        loadDeletedClippings()
        loadIgnoredApps()
        purgeExpiredDeletions()
    }

    // MARK: - Clipping CRUD

    /// Adds a new clipping to the top of the history. Copying something already in the
    /// history moves it to the top instead of duplicating it (keeping its pin and title).
    func addClipping(_ clipping: Clipping) {
        var clipping = clipping
        if let index = clippings.firstIndex(where: { $0.hasSameContent(as: clipping) }) {
            if index == 0 { return }
            let existing = clippings.remove(at: index)
            clipping.isPinned = existing.isPinned
            clipping.smartTitle = existing.smartTitle
        }
        clippings.insert(clipping, at: 0)
        trimToLimit()
        saveClippings()
    }

    /// Moves a clipping to Recently Deleted rather than erasing it outright.
    func removeClipping(_ id: UUID, undoManager: UndoManager? = nil) {
        removeClippings([id], undoManager: undoManager)
    }

    /// Moves every unpinned clipping to Recently Deleted.
    func clearUnpinned(undoManager: UndoManager? = nil) {
        removeClippings(clippings.filter { !$0.isPinned }.map(\.id), undoManager: undoManager)
    }

    /// Moves everything, including pinned clippings, to Recently Deleted.
    func clearAll(undoManager: UndoManager? = nil) {
        removeClippings(clippings.map(\.id), undoManager: undoManager)
    }

    /// Moves clippings to Recently Deleted as one event: one Undo step, one toast.
    func removeClippings(_ ids: [UUID], undoManager: UndoManager? = nil) {
        let idSet = Set(ids)
        let removed = clippings.filter { idSet.contains($0.id) }
        guard !removed.isEmpty else { return }
        clippings.removeAll { idSet.contains($0.id) }
        let now = Date()
        deletedClippings.insert(contentsOf: removed.map {
            var c = $0
            c.deletedAt = now
            return c
        }, at: 0)
        purgeExpiredDeletions()
        saveClippings()
        saveDeletedClippings()

        let restoredIDs = removed.map(\.id)
        lastTrash = TrashEvent(clippingIDs: restoredIDs)
        undoManager?.registerUndo(withTarget: self) { store in
            store.restoreClippings(restoredIDs)
        }
        undoManager?.setActionName(removed.count == 1 ? "Delete Clipping" : "Delete Clippings")
        AssistiveTech.announce(removed.count == 1
            ? "Moved to Recently Deleted"
            : "Moved \(removed.count) clippings to Recently Deleted")
    }

    /// Moves a clipping out of Recently Deleted and back into active history.
    func restoreClipping(_ id: UUID) {
        restoreClippings([id])
    }

    /// Moves clippings out of Recently Deleted, back into their original chronological
    /// place in the history (not the top — restoring shouldn't reorder recency).
    func restoreClippings(_ ids: [UUID]) {
        let idSet = Set(ids)
        let restored = deletedClippings.filter { idSet.contains($0.id) }
        guard !restored.isEmpty else { return }
        deletedClippings.removeAll { idSet.contains($0.id) }
        for var clipping in restored {
            clipping.deletedAt = nil
            let index = clippings.firstIndex { $0.createdAt < clipping.createdAt } ?? clippings.endIndex
            clippings.insert(clipping, at: index)
        }
        if lastTrash.map({ !idSet.isDisjoint(with: $0.clippingIDs) }) == true {
            lastTrash = nil
        }
        saveDeletedClippings()
        saveClippings()
        AssistiveTech.announce(restored.count == 1 ? "Restored" : "Restored \(restored.count) clippings")
    }

    func restoreAllDeleted() {
        restoreClippings(deletedClippings.map(\.id))
    }

    /// Erases a clipping from Recently Deleted for good.
    func permanentlyDelete(_ id: UUID) {
        permanentlyDelete([id])
    }

    /// Erases clippings from Recently Deleted for good.
    func permanentlyDelete(_ ids: [UUID]) {
        let idSet = Set(ids)
        let before = deletedClippings.count
        deletedClippings.removeAll { idSet.contains($0.id) }
        let count = before - deletedClippings.count
        guard count > 0 else { return }
        saveDeletedClippings()
        AssistiveTech.announce(count == 1 ? "Deleted permanently" : "Deleted \(count) clippings permanently")
    }

    /// Erases everything in Recently Deleted for good.
    func emptyRecentlyDeleted() {
        deletedClippings.removeAll()
        lastTrash = nil
        saveDeletedClippings()
        AssistiveTech.announce("Emptied Recently Deleted")
    }

    /// Whole days left before a deleted clipping is purged (Photos-style countdown).
    func daysRemaining(for clipping: Clipping) -> Int {
        guard let deletedAt = clipping.deletedAt else { return Self.recentlyDeletedRetentionDays }
        let expiry = deletedAt.addingTimeInterval(recentlyDeletedRetention)
        let seconds = expiry.timeIntervalSinceNow
        return max(0, Int((seconds / 86_400).rounded(.up)))
    }

    /// Drops deleted clippings past the retention window. Runs at launch and whenever
    /// something is deleted, since a menu bar app can stay running for weeks.
    func purgeExpiredDeletions() {
        let cutoff = Date().addingTimeInterval(-recentlyDeletedRetention)
        let before = deletedClippings.count
        deletedClippings.removeAll { ($0.deletedAt ?? .distantPast) < cutoff }
        if deletedClippings.count != before {
            saveDeletedClippings()
        }
    }

    func clipping(withID id: UUID) -> Clipping? {
        clippings.first { $0.id == id }
    }

    /// The title a list row shows: the generated one while titles are on, else the text.
    func displayTitle(for clipping: Clipping) -> String {
        if generatesSmartTitles, let smartTitle = clipping.smartTitle { return smartTitle }
        return clipping.previewTitle
    }

    func setSmartTitle(_ title: String, for id: UUID) {
        guard let index = clippings.firstIndex(where: { $0.id == id }) else { return }
        clippings[index].smartTitle = title
        saveClippings()
    }

    func togglePin(_ id: UUID) {
        guard let index = clippings.firstIndex(where: { $0.id == id }) else { return }
        clippings[index].isPinned.toggle()
        saveClippings()
        AssistiveTech.announce(clippings[index].isPinned ? "Pinned" : "Unpinned")
    }

    // MARK: - Text size

    func makeTextBigger() {
        guard let bigger = textSize.bigger else { return }
        textSize = bigger
        AssistiveTech.announce("Text size \(bigger.rawValue) percent")
    }

    func makeTextSmaller() {
        guard let smaller = textSize.smaller else { return }
        textSize = smaller
        AssistiveTech.announce("Text size \(smaller.rawValue) percent")
    }

    func resetTextSize() {
        textSize = .standard
        AssistiveTech.announce("Actual size")
    }

    private func trimToLimit() {
        let unpinnedIDs = clippings.filter { !$0.isPinned }.map(\.id)
        guard unpinnedIDs.count > maxStoredCount else { return }

        let idsToRemove = Set(unpinnedIDs.suffix(unpinnedIDs.count - maxStoredCount))
        guard !idsToRemove.isEmpty else { return }
        clippings.removeAll { idsToRemove.contains($0.id) }
    }

    // MARK: - Launch at login

    /// Re-reads the login-item status (e.g. after the user approves it in System Settings).
    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginManager.status
    }

    // MARK: - Ignored apps

    func isIgnored(bundleID: String) -> Bool {
        ignoredApps.contains { $0.bundleIdentifier == bundleID }
    }

    func addIgnoredApp(bundleID: String, name: String) {
        guard !isIgnored(bundleID: bundleID) else { return }
        ignoredApps.append(IgnoredApp(bundleIdentifier: bundleID, name: name))
        ignoredApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func removeIgnoredApp(_ id: String) {
        ignoredApps.removeAll { $0.bundleIdentifier == id }
    }

    // MARK: - Persistence

    private func loadClippings() {
        guard let data = try? Data(contentsOf: clippingsFileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Clipping].self, from: data) {
            clippings = decoded
        }
    }

    private func saveClippings() {
        guard let data = try? JSONEncoder().encode(clippings) else { return }
        try? data.write(to: clippingsFileURL, options: .atomic)
    }

    private func loadDeletedClippings() {
        guard let data = try? Data(contentsOf: deletedClippingsFileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Clipping].self, from: data) {
            deletedClippings = decoded
        }
    }

    private func saveDeletedClippings() {
        guard let data = try? JSONEncoder().encode(deletedClippings) else { return }
        try? data.write(to: deletedClippingsFileURL, options: .atomic)
    }

    private func loadIgnoredApps() {
        guard let data = try? Data(contentsOf: ignoredAppsFileURL) else { return }
        if let decoded = try? JSONDecoder().decode([IgnoredApp].self, from: data) {
            ignoredApps = decoded
        }
    }

    private func saveIgnoredApps() {
        guard let data = try? JSONEncoder().encode(ignoredApps) else { return }
        try? data.write(to: ignoredAppsFileURL, options: .atomic)
    }
}

/// One move to Recently Deleted — a single delete or a bulk clear.
struct TrashEvent: Equatable {
    let id = UUID()
    let clippingIDs: [UUID]
}
