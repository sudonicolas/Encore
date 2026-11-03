import AppKit
import Combine
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
    private var recordingObserver: AnyCancellable?
    /// An invisible 1 pt window the popover hangs from while the icon is not on screen.
    private var fallbackAnchor: NSWindow?
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
        store.finishAllEditing()
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
        // The app icon's own mark, as a template symbol.
        button.image = statusImage("encore.mark")
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

    /// Encore's custom SF Symbols, from `Resources/Assets.xcassets`: `encore.mark` is
    /// the app icon's mark drawn at SF Symbols' own weights and optical size, so it sits
    /// beside system glyphs in the menu bar; `encore.mark.fill` is its solid form.
    ///
    /// Never nil: a status item with no image is an invisible square, and a menu-bar-only
    /// app with an invisible icon looks as if it never launched. If the custom symbol
    /// can't be read, or won't take a symbol configuration, the plain image or a system
    /// clipboard symbol stands in.
    private func statusImage(_ symbol: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let custom = NSImage(named: symbol)
        let image = custom?.withSymbolConfiguration(config)
            ?? custom
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: AppInfo.name)?
                .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 3, yRadius: 3).stroke()
                return true
            }
        image.isTemplate = true
        return image
    }

    /// With "Flash the menu bar icon" on, swaps the mark for its solid form for a
    /// moment when a clipping is recorded: the visual counterpart to the copy sound. A
    /// plain swap, not an animation, so it suits Reduce Motion too.
    private func flashStatusIcon() {
        guard store.flashesMenuBarIconOnCopy, popover?.isShown != true, let button = statusItem?.button else { return }
        flashTask?.cancel()
        button.image = statusImage("encore.mark.fill")
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.updateStatusIcon()
        }
    }

    private func observeRecordingState() {
        // `@Published` reports a change before the property is set, so the icon is
        // updated a turn later, when `updateStatusIcon` reads the new value.
        recordingObserver = store.$isRecordingEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateStatusIcon() }
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
        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.animates = true
        newPopover.delegate = self
        popover = newPopover
    }

    /// A fresh SwiftUI view for every open. Every open starts from the list anyway, and
    /// a view that lives for weeks can end up wedged — buttons that no longer respond,
    /// hover states stuck on rows — until the app is quit. This way nothing outlives a
    /// single use of the popover.
    private func makePopoverContent() -> NSViewController {
        // The content sets its own size, which grows with the Text Size setting.
        let hosting = NSHostingController(rootView: MenuBarContentView().environmentObject(store))
        hosting.sizingOptions = [.preferredContentSize]
        return hosting
    }

    private func showPopover() {
        // A close already animating (after a click outside) can't be cut short.
        if popoverIsClosing {
            reopensPopover = true
            return
        }
        guard let popover, let button = statusItem?.button, !popover.isShown else { return }
        closesOnRequest = false
        popover.contentViewController = makePopoverContent()
        ClipboardMonitor.shared.refreshAccessStatus()
        // Apple Intelligence may have finished downloading since launch.
        SmartTitler.shared.processBacklog()
        // Closing the previous popover may have hidden Encore to return focus.
        // A status-item click is an explicit request to use it again, so restore and
        // activate the app before showing a window that needs to receive clicks.
        NSApp.unhide(nil)
        // The forceful form on purpose: `activate()` defers to the frontmost app, and the
        // popover then often came up in an app that wasn't active (keyboard-check fails).
        NSApp.activate(ignoringOtherApps: true)
        openedPopoverAt = .now
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let anchor = anchorForPopover(button) {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        ClippingPreviewController.shared.anchorView = popover.contentViewController?.view
        // Activation can still not land (macOS 14 and later treat it as a request). A
        // popover up in an app that isn't active gets no pointer tracking: no hover
        // preview, no hover buttons. If so, ask once more once the popover is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let popover = self.popover, popover.isShown, !self.popoverIsClosing, !NSApp.isActive
            else { return }
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
        // On the next turn of the run loop, not now: `makePopoverContent` builds a brand
        // new view for every open, and a notification posted while that view is still
        // being mounted can arrive before it has subscribed — which left the cursor out
        // of the search field, and (before PopoverKeyHandler) the whole popover without a
        // keyboard. The view starts on the list with an empty search anyway, so nothing
        // stale shows in the meantime.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardPopoverWillShow, object: nil)
        }
        closeOnClickElsewhere()
    }

    /// macOS drops a status item it has no room for (a full menu bar, the notch, an app
    /// that hides menu bar icons) off the edge of the screen, and a popover anchored to
    /// it then opens in the top-left corner, nowhere near where anyone is looking. When the
    /// icon isn't really on a screen, hang the popover from the top-right instead, where
    /// the menu extras are. Nil when the icon is where it should be.
    private func anchorForPopover(_ button: NSStatusBarButton) -> NSView? {
        if let frame = button.window?.frame, button.window?.isVisible == true,
           NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
                                              && frame.midX > $0.frame.minX + 60 }) {
            return nil
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let size = NSSize(width: 1, height: 1)
        let origin = NSPoint(x: screen.visibleFrame.maxX - 40, y: screen.visibleFrame.maxY - size.height)
        let anchor = fallbackAnchor ?? {
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            window.contentView = NSView()
            fallbackAnchor = window
            return window
        }()
        anchor.level = .statusBar
        anchor.setFrame(NSRect(origin: origin, size: size), display: false)
        anchor.orderFrontRegardless()
        return anchor.contentView
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
                guard let self, self.statusItem?.button?.window?.frame.contains(location) != true,
                      !self.isInsidePopover(location) else { return }
                self.closePopover()
            }
        }
    }

    /// Whether a screen point is on the popover or its hover preview. A click there is
    /// never "elsewhere", however macOS routed it: the preview lets clicks through to the
    /// window behind it, and a page change can swap the clicked view out mid-click.
    private func isInsidePopover(_ location: NSPoint) -> Bool {
        if let window = popover?.contentViewController?.view.window, window.frame.contains(location) { return true }
        return ClippingPreviewController.shared.frameOnScreen?.contains(location) == true
    }

    private func closePopover(animated: Bool = true) {
        reopensPopover = false
        guard let popover, popover.isShown else { return }
        // Set for the whole close, not just the call: AppKit does not always consult
        // `popoverShouldClose` before `performClose` returns, and clearing this straight
        // away let the veto there reject a close this app had itself asked for — so
        // Escape did nothing when the popover had been reopened within a second or so of
        // the last one closing. Cleared in `popoverDidClose`.
        closesOnRequest = true
        // The hover preview is a child window of the popover's, and `performClose` does
        // nothing at all while one is attached — not even asking the delegate — so the
        // card goes first. This is why Escape did nothing after arrowing down a row: the
        // keyboard was fine, the close was being dropped on the floor.
        ClippingPreviewController.shared.dismiss()
        if animated {
            popover.performClose(nil)
            // `performClose` can still be refused, and Escape has to close the popover
            // either way. If it is somehow still open on the next turn, close it outright.
            DispatchQueue.main.async { [weak self] in
                guard let self, let popover = self.popover, popover.isShown, self.closesOnRequest
                else { return }
                popover.animates = false
                popover.close()
            }
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
            let hosting = NSHostingController(rootView: HistoryWindowView().environmentObject(store))
            // Let SwiftUI's toolbar, search field and navigation title drive the window
            // chrome. macOS 13 has no way to ask for that (see below), so the window gets
            // a plain title there in case SwiftUI doesn't provide one.
            if #available(macOS 14.0, *) {
                hosting.sceneBridgingOptions = [.toolbars, .title]
            }
            let window = NSWindow(contentViewController: hosting)
            if #unavailable(macOS 14.0) {
                window.title = "History"
            }
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
        if #unavailable(macOS 14.0) {
            // macOS 13 can't be asked to bridge SwiftUI's toolbar into a window AppKit
            // made. Later systems do it even unasked, so 13 probably does too, but if the
            // window comes up with no toolbar, search and the actions would be nowhere:
            // then HistoryWindowView draws them in its columns instead. Checked once the
            // window has laid out, and again on each opening.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let window = self.historyWindowController?.window, window.isVisible else { return }
                let hasToolbar = window.toolbar.map { !$0.items.isEmpty } ?? false
                if self.navigator.historyUsesInlineToolbar == hasToolbar {
                    self.navigator.historyUsesInlineToolbar = !hasToolbar
                }
            }
        }
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
        NSApp.activateCompat()
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
        if closesOnRequest { return true }
        // A click on the popover itself never closes it. AppKit can misread one as a
        // click outside when the view under the pointer goes away mid-click, which is
        // exactly what opening a clipping's details does to its row.
        if let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].contains(event.type),
           isInsidePopover(NSEvent.mouseLocation) {
            return false
        }
        guard !NSApp.isActive else { return true }
        let recentlyReopened = focusHandedBackAt.map { $0.duration(to: .now) < .seconds(1.5) } ?? false
        let justShown = openedPopoverAt.map { $0.duration(to: .now) < .seconds(1) } ?? false
        guard recentlyReopened || justShown else { return true }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        return false
    }

    func popoverWillClose(_ notification: Notification) {
        popoverIsClosing = true
        ClippingPreviewController.shared.dismiss()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverIsClosing = false
        closesOnRequest = false
        ClippingPreviewController.shared.anchorView = nil
        // Settle any text being edited, and let the closed view go.
        store.finishAllEditing()
        popover?.contentViewController = nil
        fallbackAnchor?.orderOut(nil)
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
