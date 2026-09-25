import AppKit
import SwiftUI

/// Owns the menu bar icon, the clipping popover, and the History/Settings windows.
///
/// Left click toggles the popover open and closed; right click (or Control-click) shows
/// a standard menu with History/Recently Deleted/Pause/Settings/Quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var historyWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var flashTask: Task<Void, Never>?
    /// The click on the icon last handled by the click monitor, so the button action
    /// never handles the same click again.
    private var lastHandledClick: TimeInterval?
    /// Set while the popover animates out, when `isShown` is still true.
    private var popoverIsClosing = false
    /// The popover was asked to open while animating out, and reopens once it's closed.
    private var reopensPopover = false
    private var outsideClickMonitor: Any?
    /// When the app last hid to hand focus back (see `popoverShouldClose`).
    private var focusHandedBackAt: ContinuousClock.Instant?
    /// When the popover was last asked to show (see `popoverShouldClose`).
    private var openedPopoverAt: ContinuousClock.Instant?
    /// Set while this app closes the popover itself, which is never vetoed.
    private var closesOnRequest = false
    private let store = ClipboardStore.shared
    private let navigator = AppNavigator.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon until a window is opened.
        NSApp.setActivationPolicy(.accessory)
        ClipboardMonitor.shared.start()
        SmartTitler.shared.processBacklog()
        configurePopover()
        configureStatusItem()
        // \u{21e7}\u{2318}V opens the popover from anywhere, and closes it again if it's already open.
        GlobalHotKeyManager.shared.start { [weak self] in self?.togglePopover() }

        navigator.openHistoryWindow = { [weak self] in self?.showHistoryWindow() }
        navigator.openSettingsWindow = { [weak self] in self?.showSettingsWindow() }
        navigator.closePopover = { [weak self] in self?.closePopover() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        GlobalHotKeyManager.shared.stop()
    }

    /// Reopening from Finder/Spotlight while running shows History rather than nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHistoryWindow() }
        return true
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Encore"
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            // On mouse down, like system menu extras.
            button.sendAction(on: [.leftMouseDown])
        }
        statusItem = item
        monitorStatusItemClicks()
        updateStatusIcon()
        observeRecordingState()
        NotificationCenter.default.addObserver(forName: .clipboardDidRecordClipping, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flashStatusIcon() }
        }
    }

    /// Dims the menu bar icon while recording is paused — the standard "inactive"
    /// appearance — so the state is visible without opening anything. VoiceOver hears
    /// the same state in the icon's name, and gets its most-used commands as actions
    /// (VO-Command-Space) without opening the popover.
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let recording = store.isRecordingEnabled
        // The app icon's silhouette — a stack of clippings, newest in front — as a
        // template symbol.
        button.image = statusImage("rectangle.stack")
        button.appearsDisabled = !recording
        button.toolTip = recording ? AppInfo.name : "\(AppInfo.name) \u{2014} recording paused"
        button.setAccessibilityLabel(recording ? AppInfo.name : "\(AppInfo.name), recording paused")
        button.setAccessibilityHelp("Shows your clipboard history. Control-click for more options.")
        button.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Show History") { [weak self] in
                MainActor.assumeIsolated { self?.openHistory() }
                return true
            },
            NSAccessibilityCustomAction(name: recording ? "Pause Recording" : "Resume Recording") { [weak self] in
                MainActor.assumeIsolated { self?.toggleRecording() }
                return true
            },
            NSAccessibilityCustomAction(name: "Show Menu") { [weak self] in
                MainActor.assumeIsolated { self?.showContextMenu() }
                return true
            }
        ])
    }

    private func statusImage(_ symbol: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// With "Flash the menu bar icon" on, swaps the icon for a checkmark for a moment
    /// when a clipping is recorded: the visual counterpart to the copy sound. A plain
    /// swap, not an animation, so it suits Reduce Motion too.
    private func flashStatusIcon() {
        guard store.flashesMenuBarIconOnCopy, popover?.isShown != true, let button = statusItem?.button else { return }
        flashTask?.cancel()
        button.image = statusImage("checkmark.rectangle.stack.fill")
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.updateStatusIcon()
        }
    }

    private func observeRecordingState() {
        withObservationTracking {
            _ = store.isRecordingEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusIcon()
                self?.observeRecordingState()
            }
        }
    }

    /// Toggles the popover for accessibility presses (VoiceOver, Full Keyboard Access);
    /// clicks are handled by the click monitor before the button sees them.
    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.timestamp == lastHandledClick { return }
        togglePopover()
    }

    /// Sorts out clicks on the icon before its button handles them:
    /// - a right or Control-click gets the menu, attached just in time so the button
    ///   shows it natively, and detached when it closes so left clicks still reach
    ///   the popover;
    /// - a left click toggles the popover. The button can't do this itself: it stops
    ///   sending its action while a popover is anchored to it.
    /// Events are always passed on: the button drops the next click if it sees an
    /// unpaired mouse-up.
    private func monitorStatusItemClicks() {
        _ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated { self?.statusItemWillReceive(event) }
            return event
        }
    }

    private func statusItemWillReceive(_ event: NSEvent) {
        guard let button = statusItem?.button, event.window === button.window,
              button.bounds.contains(button.convert(event.locationInWindow, from: nil))
        else { return }
        lastHandledClick = event.timestamp
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            closePopover(animated: false)
            statusItem?.menu = makeContextMenu()
        } else {
            togglePopover()
        }
    }

    /// Goes by where the popover is heading rather than `isShown`, so a click during
    /// the close animation reopens it instead of being lost, however fast the clicks.
    /// Closes instantly, like a system menu extra, so the next click can reopen it.
    private func togglePopover() {
        if popover?.isShown == true && !popoverIsClosing || reopensPopover {
            closePopover(animated: false)
        } else {
            showPopover()
        }
    }

    // MARK: - Popover

    private func configurePopover() {
        let content = MenuBarContentView().environment(store)
        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.animates = true
        // The content sets its own size, which grows with the Text Size setting.
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        newPopover.contentViewController = hosting
        newPopover.delegate = self
        popover = newPopover
    }

    private func showPopover() {
        // A close already animating (after a click outside) can't be cut short.
        if popoverIsClosing {
            reopensPopover = true
            return
        }
        guard let popover, let button = statusItem?.button, !popover.isShown else { return }
        NotificationCenter.default.post(name: .clipboardPopoverWillShow, object: nil)
        ClipboardMonitor.shared.refreshAccessStatus()
        // Apple Intelligence may have finished downloading since launch.
        SmartTitler.shared.processBacklog()
        // Activate so typing goes straight into the popover's search field.
        NSApp.activate()
        openedPopoverAt = .now
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        closeOnClickElsewhere()
    }

    /// Closes the popover on a click anywhere outside the app: the desktop, empty menu
    /// bar space, another app. The transient popover closes when the app resigns
    /// active, but not every such click takes activation away.
    private func closeOnClickElsewhere() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                // Clicks on the icon can come through here too; the click monitor has them.
                guard let self, self.statusItem?.button?.window?.frame.contains(location) != true else { return }
                self.closePopover()
            }
        }
    }

    private func closePopover(animated: Bool = true) {
        reopensPopover = false
        guard let popover, popover.isShown else { return }
        if animated {
            closesOnRequest = true
            popover.performClose(nil)
            closesOnRequest = false
        } else {
            popover.animates = false
            popover.close()
        }
    }

    // MARK: - Context menu

    /// For VoiceOver's "Show Menu" action; clicks get the menu through the click monitor.
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        closePopover()
        makeContextMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Show History", #selector(openHistory)))
        menu.addItem(item("Recently Deleted", #selector(openRecentlyDeleted)))
        menu.addItem(.separator())
        menu.addItem(item(store.isRecordingEnabled ? "Pause Recording" : "Resume Recording", #selector(toggleRecording)))
        menu.addItem(.separator())
        menu.addItem(item("Settings\u{2026}", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(AppInfo.name)", #selector(quitApp), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openHistory() {
        navigator.showHistory(navigator.historySection == .recentlyDeleted ? .all : navigator.historySection)
    }

    @objc private func openRecentlyDeleted() {
        navigator.showHistory(.recentlyDeleted)
    }

    @objc private func toggleRecording() {
        store.isRecordingEnabled.toggle()
    }

    @objc private func openSettings() {
        navigator.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Windows

    private func showHistoryWindow() {
        if historyWindowController == nil {
            let hosting = NSHostingController(rootView: HistoryWindowView().environment(store))
            // Let SwiftUI's toolbar, search field and navigation title drive the window chrome.
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 980, height: 620))
            if !window.setFrameUsingName("HistoryWindow") {
                window.center()
            }
            window.setFrameAutosaveName("HistoryWindow")
            historyWindowController = NSWindowController(window: window)
        }
        present(historyWindowController?.window)
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(store: store)
            controller.window?.delegate = self
            settingsWindowController = controller
        }
        present(settingsWindowController?.window)
    }

    /// While a window is open the app becomes a regular app — Dock icon, ⌘Tab, menu bar —
    /// so the window can't get lost behind others; it drops back to menu-bar-only when
    /// the last window closes.
    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate {
    fileprivate var hasVisibleWindow: Bool {
        [historyWindowController?.window, settingsWindowController?.window].contains { $0?.isVisible == true }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let others = [historyWindowController?.window, settingsWindowController?.window]
            .compactMap { $0 }
            .filter { $0 !== closing && $0.isVisible }
        if others.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // Detached after the button finishes tracking the click that opened it; while
        // attached, every click on the icon would open the menu instead of the popover.
        DispatchQueue.main.async { [weak self] in
            if self?.statusItem?.menu === menu { self?.statusItem?.menu = nil }
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    /// Vetoes a transient close that isn't really a click or Escape, but this app
    /// merely not being active *yet*:
    /// - Reopened right after hiding to hand focus back, the popover would be closed by
    ///   that handoff finishing late: the app it went to activates up to half a second
    ///   later, after the popover has reactivated this one.
    /// - Shown from the global hotkey (see GlobalHotKeyManager) while the frontmost app
    ///   is full screen, in its own Space: reaching the menu bar means switching away
    ///   from that Space, and the switch itself can cost Encore active status for a
    ///   moment right after `showPopover` asked for it — which a transient popover
    ///   reads as "close me" before activation has actually landed.
    /// Either way, keep the popover open and take activation back. Clicks elsewhere
    /// still close it through `closeOnClickElsewhere`, which is never vetoed.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard !NSApp.isActive, !closesOnRequest else { return true }
        let recentlyReopened = focusHandedBackAt.map { $0.duration(to: .now) < .seconds(1.5) } ?? false
        let justShown = openedPopoverAt.map { $0.duration(to: .now) < .seconds(1) } ?? false
        guard recentlyReopened || justShown else { return true }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        return false
    }

    func popoverWillClose(_ notification: Notification) {
        popoverIsClosing = true
    }

    func popoverDidClose(_ notification: Notification) {
        popoverIsClosing = false
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if reopensPopover {
            reopensPopover = false
            showPopover()
            return
        }
        // Hand focus back to the app the user came from, so a clipping copied from the
        // popover can be pasted right away. Deferred a turn so that when the popover
        // closed to open History or Settings, or for the right-click menu, that window
        // or menu is already up and we stay put.
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.isActive, !self.hasVisibleWindow, self.popover?.isShown != true,
                  self.statusItem?.menu == nil
            else { return }
            self.focusHandedBackAt = .now
            NSApp.hide(nil)
        }
    }
}
