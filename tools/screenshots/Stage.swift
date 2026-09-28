import AppKit
import SwiftUI
import ScreenCaptureKit
import UniformTypeIdentifiers

// Renders Encore's App Store screenshots. See make-screenshots.sh, which builds this
// together with Encore's own sources and runs it.
//
// How it works:
// - A virtual HiDPI display (1440x900 points at 2x) is created, so everything renders at
//   a true 2880x1800 even on a 1x monitor. Nothing appears on the real screen.
// - Each scene puts a full-screen "stage" window on it (background, headline, a drawn
//   menu bar), then opens Encore's real popover, History and Settings windows on top,
//   so Liquid Glass refracts the real stage.
// - The display is captured with ScreenCaptureKit, limited to this process's own windows.
//   Capturing your own windows needs no Screen Recording permission.
// - The history is fictional (DemoData), in a throwaway home folder: the tool refuses to
//   run unless CFFIXED_USER_HOME points somewhere other than the real home, and never
//   starts ClipboardMonitor, so nothing from the real clipboard can appear.

@main
@MainActor
enum StageMain {
    private static let director = Director()

    static func main() {
        let app = NSApplication.shared
        app.delegate = director
        app.run()
    }
}

// MARK: - Director

@MainActor
final class Director: NSObject, NSApplicationDelegate {
    private let arguments = Arguments(CommandLine.arguments)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            do {
                try checkIsolation()
                switch arguments.mode {
                case "prepare": try await prepare()
                case "capture": try await capture()
                default: throw StageError("Usage: encore-stage prepare | capture --out DIR [--portrait] [--only a,b] [--dump]")
                }
                finish(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                finish(1)
            }
        }
    }

    private func finish(_ status: Int32) {
        // Settings the store wrote went to this tool's own defaults domain; leave nothing behind.
        UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        exit(status)
    }

    /// Encore's store reads and writes Application Support and runs a one-time migration
    /// there. Make sure that's a throwaway folder before anything touches the store.
    private func checkIsolation() throws {
        guard let fakeHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"],
              let realHome = getpwuid(getuid())?.pointee.pw_dir.map({ String(cString: $0) }),
              URL(fileURLWithPath: fakeHome).standardizedFileURL != URL(fileURLWithPath: realHome).standardizedFileURL,
              NSHomeDirectory().hasPrefix(fakeHome) || NSHomeDirectory().hasPrefix("/private" + fakeHome),
              supportDirectory.path.hasPrefix(NSHomeDirectory())
        else {
            throw StageError("Run through tools/screenshots/make-screenshots.sh (CFFIXED_USER_HOME must point to a scratch folder).")
        }
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        // Nothing to migrate from the old "clipboard" app in a scratch home.
        defaults.set(true, forKey: "didMigrateFromClipboard")
    }

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Encore", isDirectory: true)
    }

    // MARK: Prepare

    /// Writes the demo history and has Apple Intelligence title it, with Encore's own
    /// SmartTitler, so the titles in the screenshots are real ones.
    private func prepare() async throws {
        let files = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Launch", isDirectory: true)
        try DemoData.install(in: supportDirectory, filesDirectory: files)

        let store = ClipboardStore.shared
        guard Intelligence.status == .available else {
            throw StageError("Apple Intelligence isn't available (\(Intelligence.status.summary)); titles can't be generated.")
        }
        SmartTitler.shared.processBacklog()

        // SmartTitler tries each clipping once; wait until the untitled count stops moving.
        var remaining = Int.max
        var stableSince = Date()
        while true {
            let now = store.clippings.filter(SmartTitler.needsTitle).count
            if now != remaining { remaining = now; stableSince = Date() }
            if remaining == 0 || Date().timeIntervalSince(stableSince) > 20 { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        for clipping in store.clippings where clipping.smartTitle != nil {
            print("✦ \(clipping.smartTitle!)  \u{2190}  \(clipping.singleLinePreview.prefix(48))")
        }
        try DemoData.finishPreparing(store.clippings, in: supportDirectory)
    }

    // MARK: Capture

    private func capture() async throws {
        guard FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent("deleted-clippings.json").path) else {
            throw StageError("No demo data. Run the prepare step first.")
        }
        let output = URL(fileURLWithPath: arguments.value("--out") ?? "screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // Few enough rows that the popover's list ends above its floating footer.
        ClipboardStore.shared.maxDisplayedCount = 5
        if arguments.flag("--portrait") {
            VirtualScreen.size = VirtualScreen.portraitSize
            // Rows are taller at the portrait set's Text Size.
            ClipboardStore.shared.maxDisplayedCount = 4
        }
        let display = try await VirtualScreen.make()
        let stage = Stage(screen: display.screen, displayID: display.id)

        let catalog = arguments.flag("--portrait") ? Scenes.portrait : Scenes.all
        let scenes = catalog.filter { arguments.only.isEmpty || arguments.only.contains($0.name) }
        for (index, scene) in scenes.enumerated() {
            print("→ \(scene.name)")
            NSApp.appearance = NSAppearance(named: scene.appearance)
            try await stage.present(scene)
            if arguments.flag("--dump") { stage.dumpViews() }
            let number = (catalog.firstIndex { $0.name == scene.name } ?? index) + 1
            let url = output.appendingPathComponent(String(format: "%02d-%@.png", number, scene.name))
            try await stage.capture(to: url)
            print("  \(url.path)")
            stage.tearDown()
        }
        withExtendedLifetime(display) {}
    }
}

struct StageError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Arguments {
    let all: [String]
    init(_ all: [String]) { self.all = all }

    var mode: String? { all.dropFirst().first }
    func flag(_ name: String) -> Bool { all.contains(name) }
    func value(_ name: String) -> String? {
        guard let index = all.firstIndex(of: name), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
    var only: Set<String> { Set((value("--only") ?? "").split(separator: ",").map(String.init)) }
}

// MARK: - Virtual display

/// A HiDPI display that exists only while this process runs.
@MainActor
final class VirtualScreen {
    /// 1440x900 for the Mac App Store; 1080x1350 (2160x2700 pixels, 4:5) with --portrait.
    static var size = CGSize(width: 1440, height: 900)
    /// 4:5, at twice the usual 1080x1350, with room around the words and the UI for a
    /// float or zoom added later.
    static let portraitSize = CGSize(width: 1080, height: 1350)
    private static let name = "Encore Stage"

    let id: CGDirectDisplayID
    let screen: NSScreen
    private let display: CGVirtualDisplay

    private init(display: CGVirtualDisplay, screen: NSScreen) {
        self.display = display
        self.id = display.displayID
        self.screen = screen
    }

    static func make() async throws -> VirtualScreen {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = .main
        descriptor.name = name
        descriptor.maxPixelsWide = UInt32(size.width * 2)
        descriptor.maxPixelsHigh = UInt32(size.height * 2)
        // A 14" panel's pixel density (a 16:10 one is 302 x 189 mm).
        descriptor.sizeInMillimeters = CGSize(width: size.width * 302 / 1440, height: size.height * 189 / 900)
        descriptor.serialNum = 0xE11C
        descriptor.productID = 0xE11C
        descriptor.vendorID = 0xE11C
        descriptor.terminationHandler = { _, _ in }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            throw StageError("Couldn't create the virtual display.")
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 60)!]
        guard display.apply(settings) else { throw StageError("Couldn't configure the virtual display.") }
        // macOS may start a portrait display in its 1x mode; switch to the 2x one.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        if let modes = CGDisplayCopyAllDisplayModes(display.displayID, options) as? [CGDisplayMode],
           let retina = modes.first(where: { $0.width == Int(size.width) && $0.pixelWidth == Int(size.width * 2) }) {
            CGDisplaySetDisplayMode(display.displayID, retina, nil)
        }

        for _ in 0..<100 {
            if let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }),
               screen.backingScaleFactor == 2, screen.frame.size == size {
                return VirtualScreen(display: display, screen: screen)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let seen = NSScreen.screens.first { $0.displayID == display.displayID }
        throw StageError("The virtual display didn't come up at 2x (\(seen.map { "\($0.frame.size) @\($0.backingScaleFactor)x" } ?? "not found")).")
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

// MARK: - Stage

/// Everything on the virtual display during one scene.
@MainActor
final class Stage {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let store = ClipboardStore.shared

    /// Above the menu bar and Dock, so nothing of the system shows through; Encore's own
    /// windows go one level up, the drawn Dock above them (as the real one is), and the
    /// popover and menus on top.
    static let backdropLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
    static let windowLevel = NSWindow.Level(rawValue: backdropLevel.rawValue + 1)
    static let dockLevel = NSWindow.Level(rawValue: backdropLevel.rawValue + 2)
    static let popoverLevel = NSWindow.Level(rawValue: backdropLevel.rawValue + 3)

    private var backdrop: NSWindow?
    private var dock: NSWindow?
    private var windows: [NSWindow] = []
    private var popovers: [NSPopover] = []
    private var anchors: [String: NSView] = [:]
    private var menuObserver: NSObjectProtocol?

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.screen = screen
        self.displayID = displayID
    }

    // MARK: Scenes

    func present(_ scene: Scene) async throws {
        let window = StageWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen
        )
        window.level = Self.backdropLevel
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .black
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let hosting = NSHostingView(rootView: scene.backdrop.ignoresSafeArea())
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        backdrop = window

        activate()
        try await scene.run(self)
        if scene.showsDock {
            // Encore only has a running dot while one of its windows is open; from the
            // menu bar alone it's an accessory app.
            showDock(encoreRunning: !windows.isEmpty)
        }
        // Let animations, symbol effects and the scroll-edge blur settle.
        try await Task.sleep(for: .seconds(1.2))
    }

    /// Windows only draw as active (coloured traffic lights, accent selection) in the
    /// frontmost app. A process started from a terminal isn't frontmost, so ask for it.
    func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func tearDown() {
        popovers.forEach { $0.close() }
        popovers = []
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = []
        anchors = [:]
        backdrop?.orderOut(nil)
        backdrop = nil
        dock?.orderOut(nil)
        dock = nil
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        menuObserver = nil
        AppNavigator.shared.historySearch = ""
        AppNavigator.shared.historySection = .all
    }

    /// The Dock, in its own window so its glass refracts whatever is behind it.
    private func showDock(encoreRunning: Bool) {
        let top = Dock.top - 12   // room for the glass's shadow
        let frame = screenRect(CGRect(x: 0, y: top, width: screen.frame.width, height: screen.frame.height - top))
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = Self.dockLevel
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView:
            Dock(encoreRunning: encoreRunning)
                .padding(.bottom, Dock.bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        )
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        dock = window
    }

    // MARK: Geometry (stage points, origin top left, like the design)

    func screenRect(_ rect: CGRect) -> NSRect {
        NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: Encore's surfaces

    /// The menu bar popover, open under a drawn status item at `anchor` (stage points).
    @discardableResult
    func openPopover(under anchor: CGRect) async throws -> NSPopover {
        guard let backdrop, let container = backdrop.contentView else { throw StageError("No stage") }
        let anchorView = NSView(frame: NSRect(
            x: anchor.minX, y: container.bounds.height - anchor.maxY, width: anchor.width, height: anchor.height
        ))
        container.addSubview(anchorView)

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuBarContentView().environment(store))
        NotificationCenter.default.post(name: .clipboardPopoverWillShow, object: nil)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.level = Self.popoverLevel
        popover.contentViewController?.view.window?.makeKey()
        popovers.append(popover)
        try await Task.sleep(for: .milliseconds(600))
        return popover
    }

    /// The History window, built like AppDelegate builds it, at `frame` (stage points).
    @discardableResult
    func openHistory(frame: CGRect, section: HistorySection = .all, search: String = "") async throws -> NSWindow {
        AppNavigator.shared.historySection = section
        AppNavigator.shared.historySearch = search
        let hosting = NSHostingController(rootView: HistoryWindowView().environment(store))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = StageWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = Self.windowLevel
        window.setFrame(screenRect(frame), display: true)
        activate()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        try await Task.sleep(for: .milliseconds(800))
        // Toolbar sizing can nudge the frame; put it back.
        window.setFrame(screenRect(frame), display: true)
        return window
    }

    /// The Settings window on the given tab, with its top-left corner at `origin`.
    @discardableResult
    func openSettings(tab: Int, origin: CGPoint) async throws -> NSWindow {
        let controller = SettingsWindowController(store: store)
        guard let window = controller.window,
              let tabs = window.contentViewController as? NSTabViewController else { throw StageError("No Settings window") }
        tabs.selectedTabViewItemIndex = tab
        window.level = Self.windowLevel
        // SettingsWindowController centres the window on the main display; move it to
        // the stage before it's ever shown (a key window moved across displays can keep
        // drawing as inactive).
        tabs.view.layoutSubtreeIfNeeded()
        window.setFrame(screenRect(CGRect(origin: origin, size: window.frame.size)), display: false)
        activate()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        try await Task.sleep(for: .milliseconds(800))
        // The pane may have resized the window; pin its top-left corner again.
        window.setFrame(screenRect(CGRect(origin: origin, size: window.frame.size)), display: true)
        objc_setAssociatedObject(window, &Self.controllerKey, controller, .OBJC_ASSOCIATION_RETAIN)
        return window
    }
    private static var controllerKey = 0

    // MARK: Driving the UI

    /// Waits until `condition` holds, polling; fails the scene after `timeout`.
    func wait(_ what: String, timeout: Double = 60, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw StageError("Timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Clicks at a point in stage coordinates, delivered straight to the window under it.
    func click(at point: CGPoint, in window: NSWindow) {
        let screenPoint = NSPoint(x: screen.frame.minX + point.x, y: screen.frame.maxY - point.y)
        let location = window.convertPoint(fromScreen: screenPoint)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
        // Controls that track the mouse pull the mouse-up from the queue.
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
    }

    /// Runs `handler` with the next menu that opens (a SwiftUI Menu's NSMenu).
    func onNextMenu(_ handler: @escaping (NSMenu) -> Void) {
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let menu = note.object as? NSMenu, menu.supermenu == nil else { return }
            MainActor.assumeIsolated {
                if let observer = self?.menuObserver { NotificationCenter.default.removeObserver(observer) }
                self?.menuObserver = nil
                handler(menu)
            }
        }
    }

    // MARK: Capture

    /// Captures the virtual display — only this process's windows — at 2x, flattened to
    /// an opaque sRGB PNG as App Store Connect expects.
    func capture(to url: URL) async throws {
        // macOS treats activation as a request, and gives focus back to whatever you
        // click while this runs; inactive windows draw grey. So check that Encore is in
        // front both before and after taking the shot, and take it again if not.
        for _ in 0..<8 {
            try await bringToFront()
            let image = try await captureImage()
            if NSApp.isActive, frontWindow?.isKeyWindow != false {
                try Self.writeOpaquePNG(image, to: url)
                return
            }
            print("  (lost focus during the capture; retaking)")
        }
        throw StageError("macOS kept another app in front. Leave the Mac alone for a minute and run again.")
    }

    private var frontWindow: NSWindow? {
        popovers.last?.contentViewController?.view.window ?? windows.last
    }

    private func bringToFront() async throws {
        let front = frontWindow
        for _ in 0..<40 where !NSApp.isActive || front?.isKeyWindow == false {
            activate()
            front?.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(250))
        }
        // A window that became key before the app was active can keep its inactive
        // drawing (grey traffic lights and controls); ordering it in again redraws it.
        if let front, popovers.isEmpty {
            front.orderOut(nil)
            front.makeKeyAndOrderFront(nil)
        }
        try await Task.sleep(for: .seconds(1.2))
    }

    private func captureImage() async throws -> CGImage {
        let content = try await SCShareableContent.currentProcess
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw StageError("The virtual display isn't shareable")
        }
        let pid = getpid()
        let ours = content.windows.filter { $0.owningApplication?.processID == pid && $0.isOnScreen }
        let filter = SCContentFilter(display: display, including: ours)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw StageError("Couldn't make a bitmap") }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw StageError("Couldn't write \(url.lastPathComponent)") }
        CGImageDestinationAddImage(destination, flattened, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StageError("Couldn't write \(url.lastPathComponent)") }
    }

    // MARK: Debugging

    /// Prints each window's toolbar and view hierarchy, for working out how to drive it.
    func dumpViews() {
        for window in NSApp.windows where window.isVisible && window !== backdrop {
            print("── window \(type(of: window)) “\(window.title)” \(window.frame)")
            for item in window.toolbar?.items ?? [] {
                print("  toolbar \(type(of: item)) “\(item.label)” \(item.itemIdentifier.rawValue) menu=\((item as? NSMenuToolbarItem)?.menu.items.map(\.title) ?? [])")
            }
            func walk(_ view: NSView, _ depth: Int) {
                guard depth < 30 else { return }
                let extra = (view as? NSTableView).map { " rows=\($0.numberOfRows)" } ?? ""
                print(String(repeating: "  ", count: depth) + "\(type(of: view)) \(view.frame)\(extra)")
                view.subviews.forEach { walk($0, depth + 1) }
            }
            if let root = window.contentView?.superview { walk(root, 1) }
        }
    }
}

/// A window macOS won't nudge back on screen or under the menu bar, so scenes can let
/// windows bleed off the edge of the frame.
final class StageWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
