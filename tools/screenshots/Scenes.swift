import AppKit
import SwiftUI

/// One App Store screenshot: a stage (background, words, drawn menu bar) and the Encore
/// surfaces opened on top of it.
struct Scene {
    let name: String
    var appearance: NSAppearance.Name = .aqua
    /// A Dock along the bottom, for the scenes set on the desktop around the menu bar.
    var showsDock = false
    let backdrop: AnyView
    let run: @MainActor (Stage) async throws -> Void
}

@MainActor
enum Scenes {
    /// Where the History window sits under a centred headline, running off the bottom.
    static let historyFrame = CGRect(x: 150, y: 318, width: 1140, height: 640)

    static let all: [Scene] = [hero, smartTitles, writingTools, lookups, search, privacy, recentlyDeleted]

    // MARK: 1 · Hero

    static let hero = Scene(
        name: "hero",
        showsDock: true,
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.82, y: 0.95), textZone: .leftColumn) {
                MenuBar()
                SideCopy(
                    icon: true,
                    headline: "Everything you copy.\nReady for an encore.",
                    subhead: "Your clipboard history, one click away in the menu bar. With Apple Intelligence built right in."
                )
            }
        ),
        run: { stage in
            try await stage.openPopover(under: MenuBar.encoreItem)
        }
    )

    // MARK: 2 · Smart titles

    static let smartTitles = Scene(
        name: "smart-titles",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.15, y: 1.0), textZone: .topBand) {
                TopCopy(
                    eyebrow: "Apple Intelligence",
                    headline: "Know what you copied at a glance.",
                    subhead: "Long clippings get a short, searchable title, written right on your Mac."
                )
            }
        ),
        run: { stage in
            let window = try await stage.openHistory(frame: Scenes.historyFrame)
            let flight = stage.store.clippings.first { $0.text?.contains(DemoData.Key.flight) == true }!
            try await stage.select(flight.id, in: window)
        }
    )

    // MARK: 3 · Writing tools

    static let writingTools = Scene(
        name: "writing-tools",
        showsDock: true,
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.9, y: 0.9), textZone: .leftColumn) {
                MenuBar()
                SideCopy(
                    eyebrow: "Apple Intelligence",
                    headline: "Rewrite it before\nyou paste it.",
                    subhead: "Proofread, make it friendly or professional, summarize, or find the action items. Privately, on device.",
                    chips: ["Proofread", "Make Professional", "Summarize", "Key Points", "Explain", "Find Action Items"]
                )
            }
        ),
        run: { stage in
            _ = try stage.bringToTop(DemoData.Key.casualUpdate)
            let popover = try await stage.openPopover(under: MenuBar.encoreItem)
            try await stage.openNewestDetail(in: popover)
            // The ✨ button leads the glass group in the popover's header.
            let window = popover.contentViewController!.view.window!
            let frame = stage.stageRect(window.frame)
            try await stage.runIntelligence(
                "Make Professional", clickingAt: CGPoint(x: frame.maxX - 136, y: frame.minY + 38), in: window
            )
        }
    )

    // MARK: 4 · Lookups

    static let lookups = Scene(
        name: "lookups",
        showsDock: true,
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.85, y: 0.95), textZone: .leftColumn) {
                MenuBar()
                SideCopy(
                    headline: "Copy a price.\nSee it in your currency.",
                    subhead: "Prices convert at European Central Bank rates. Words get a definition, names a Wikipedia summary.",
                    chips: ["Currencies", "Wiktionary", "Wikipedia"]
                )
            }
        ),
        run: { stage in
            _ = try stage.bringToTop(DemoData.Key.price)
            let popover = try await stage.openPopover(under: MenuBar.encoreItem)
            try await stage.openNewestDetail(in: popover)
            // Exchange rates come from the network.
            try await Task.sleep(for: .seconds(3))
        }
    )

    // MARK: 5 · Search

    static let search = Scene(
        name: "search",
        appearance: .darkAqua,
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.5, y: 1.05), textZone: .topBand) {
                TopCopy(
                    headline: "Find it by what it is.",
                    subhead: "Search reads the titles Apple Intelligence writes, so “email” finds emails that never say the word."
                )
            }
        ),
        run: { stage in
            let window = try await stage.openHistory(frame: Scenes.historyFrame, search: "email")
            let flight = stage.store.clippings.first { $0.text?.contains(DemoData.Key.flight) == true }!
            try await stage.select(flight.id, in: window)
        }
    )

    // MARK: 6 · Privacy

    static let privacy = Scene(
        name: "privacy",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.9, y: 0.1), textZone: .leftColumn) {
                SideCopy(
                    headline: "Your clipboard\nstays yours.",
                    subhead: "No account. No analytics. No tracking.",
                    features: [
                        ("lock.shield", "Skips what password managers copy"),
                        ("hand.raised", "Ignore any app you choose"),
                        ("cpu", "Apple Intelligence runs on your Mac"),
                        ("internaldrive", "History never leaves this Mac"),
                    ]
                )
            }
        ),
        run: { stage in
            try await stage.openSettings(tab: 3, origin: CGPoint(x: 800, y: 210))
        }
    )

    // MARK: 7 · Recently Deleted

    static let recentlyDeleted = Scene(
        name: "recently-deleted",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.85, y: 1.0), textZone: .topBand) {
                TopCopy(
                    headline: "Deleted? Not for 30 days.",
                    subhead: "Pin what you reuse. Anything you delete waits in Recently Deleted, ready to restore."
                )
            }
        ),
        run: { stage in
            let window = try await stage.openHistory(
                frame: Scenes.historyFrame, section: .recentlyDeleted
            )
            let image = stage.store.deletedClippings.first { $0.kind == .image }!
            try await stage.select(image.id, in: window, section: .recentlyDeleted)
        }
    )
}

// MARK: - Driving Encore

extension Stage {
    /// "Copies" a clipping again, which moves it to the top of the history — so scenes
    /// can put the clipping they're about in a known place.
    func bringToTop(_ text: String) throws -> Clipping {
        guard var clipping = store.clippings.first(where: { $0.text?.contains(text) == true }) else {
            throw StageError("No clipping containing “\(text)”")
        }
        clipping.createdAt = Date().addingTimeInterval(-50)
        store.addClipping(clipping)
        return clipping
    }

    /// In the popover: opens the newest clipping's detail page with its chevron. (SwiftUI
    /// only builds an accessibility tree for a connected assistive app, so the chevron is
    /// found by the popover's layout: two pinned rows, then the Recent list.)
    func openNewestDetail(in popover: NSPopover) async throws {
        guard let window = popover.contentViewController?.view.window else { throw StageError("No popover window") }
        let frame = stageRect(window.frame)
        click(at: CGPoint(x: frame.maxX - 34, y: frame.minY + 213), in: window)
        try await Task.sleep(for: .milliseconds(700))
    }

    /// Selects a clipping in the History window's list, by clicking its row.
    func select(_ id: UUID, in window: NSWindow, section: HistorySection = .all) async throws {
        guard let table = tables(in: window).max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }) else {
            throw StageError("No list in History")
        }
        // The same rows HistoryWindowView shows: Pinned and Recent sections (each with a
        // header row) for everything, a plain list elsewhere.
        let search = AppNavigator.shared.historySearch
        var items = section == .recentlyDeleted ? store.deletedClippings : store.clippings.filter(section.includes)
        if !search.isEmpty { items = items.filter { $0.searchableText.localizedCaseInsensitiveContains(search) } }
        let row: Int?
        if section == .all, search.isEmpty, items.contains(where: \.isPinned) {
            let pinned = items.filter(\.isPinned), recent = items.filter { !$0.isPinned }
            row = pinned.firstIndex { $0.id == id }.map { $0 + 1 }
                ?? recent.firstIndex { $0.id == id }.map { $0 + pinned.count + 2 }
        } else {
            row = items.firstIndex { $0.id == id }
        }
        guard let row, row < table.numberOfRows else { throw StageError("Row not found (\(table.numberOfRows) rows)") }
        table.scrollRowToVisible(row)
        let rect = table.convert(table.rect(ofRow: row), to: nil)
        let point = window.convertPoint(toScreen: NSPoint(x: rect.midX, y: rect.midY))
        window.makeFirstResponder(table)
        click(at: CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y), in: window)
        try await Task.sleep(for: .milliseconds(600))
        if table.selectedRow != row {
            print("  (click didn't select row \(row); selecting directly)")
            table.selectRowIndexes([row], byExtendingSelection: false)
            try await Task.sleep(for: .milliseconds(600))
        }
    }

    private func tables(in window: NSWindow) -> [NSTableView] {
        var result: [NSTableView] = []
        func walk(_ view: NSView) {
            if let table = view as? NSTableView { result.append(table) }
            view.subviews.forEach(walk)
        }
        window.contentView.map(walk)
        return result
    }

    /// Picks `item` from the Apple Intelligence menu opened by a click at `point`, then
    /// waits for the model to finish writing.
    func runIntelligence(_ item: String, clickingAt point: CGPoint, in window: NSWindow) async throws {
        var picked = false
        onNextMenu { menu in
            // Once the menu is actually tracking: choose, then close it.
            RunLoop.main.perform(inModes: [.eventTracking, .default]) {
                if let index = menu.items.firstIndex(where: { $0.title == item }) {
                    menu.performActionForItem(at: index)
                    picked = true
                } else {
                    print("  menu items: \(menu.items.map(\.title))")
                }
                menu.cancelTrackingWithoutAnimation()
            }
        }
        DispatchQueue.main.async { [self] in self.click(at: point, in: window) }
        try await wait("the \(item) menu item", timeout: 10) { picked }
        try await waitUntilStill(window, what: "Apple Intelligence")
    }

    /// Waits for a window to stop changing — here, for the model to finish streaming.
    func waitUntilStill(_ window: NSWindow, what: String, quiet: Double = 3, timeout: Double = 90) async throws {
        func render() -> Data? {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.tiffRepresentation
        }
        try await Task.sleep(for: .seconds(1.5))
        let start = Date()
        var last = render(), lastChange = Date()
        while Date().timeIntervalSince(lastChange) < quiet {
            guard Date().timeIntervalSince(start) < timeout else { throw StageError("Timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(400))
            let now = render()
            if now != last { last = now; lastChange = Date() }
        }
    }

    func stageRect(_ screenRect: NSRect) -> CGRect {
        CGRect(
            x: screenRect.minX - screen.frame.minX,
            y: screen.frame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}

// MARK: - Brand

/// Encore's colours: the app icon's sand-to-clay field, and the blue-to-lavender accent
/// that marks Apple Intelligence (docs/COLOR.md). On the field, ink is at least 7.3:1, secondary ink 4.5:1 and
/// the eyebrow (large text) 3.2:1, from the top of the gradient to the bottom.
enum BrandPalette {
    static let fieldTop = Color(.displayP3, red: 0.942, green: 0.904, blue: 0.838)
    static let fieldBottom = Color(.displayP3, red: 0.831, green: 0.718, blue: 0.623)
    static let ink = Color(.displayP3, red: 0.219, green: 0.165, blue: 0.132)
    static let inkSecondary = Color(.displayP3, red: 0.348, green: 0.286, blue: 0.247)
    static let blue = Color(.displayP3, red: 0.193, green: 0.377, blue: 0.691)
    static let lavender = Color(.displayP3, red: 0.406, green: 0.332, blue: 0.584)
    static let glow = Color(.displayP3, red: 0.759, green: 0.708, blue: 0.883)
    /// The ripple field's deep side — between the icon's terracotta and its umber text,
    /// so the field reads as the same material as the icon, not a new colour.
    static let rippleShadow = Color(.displayP3, red: 0.502, green: 0.318, blue: 0.235)

    // MARK: Night ground (portrait slides whose UI is light, so it pops)

    /// Neutral near-black, a touch lifted at the top — no brown, so the clay icon and the
    /// sand desktop are the only warm things on the slide.
    static let nightTop = Color(.displayP3, red: 0.118, green: 0.118, blue: 0.129)
    static let nightBottom = Color(.displayP3, red: 0.063, green: 0.063, blue: 0.071)
    /// Headline and body text on night.
    static let onNight = Color(.displayP3, red: 0.961, green: 0.961, blue: 0.969)
    /// Subheads on night.
    static let onNightSecondary = Color(.displayP3, red: 0.682, green: 0.682, blue: 0.698)
    /// Sparkle, lightened for night (docs/COLOR.md's Dark column).
    static let blueOnNight = Color(.displayP3, red: 0.431, green: 0.686, blue: 0.969)
    static let lavenderOnNight = Color(.displayP3, red: 0.796, green: 0.729, blue: 0.922)
}

/// Concentric rings radiating from a point, wobbled so they read as water rippling out
/// (or a rake through sand) rather than a target. Each ring is stroked twice — a light
/// pass leading it, a deep one trailing — like a crest catching the sun and casting a
/// trough of shadow, so the field has real texture for Liquid Glass to refract instead of
/// reading as one flat colour behind the window.
struct RippleField: View {
    var center: UnitPoint
    /// Offsets the wobble's phase, so different scenes don't all ripple identically.
    var seed: CGFloat = 0
    var strength: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let cx = size.width * center.x
            let cy = size.height * center.y
            let maxRadius = min(sqrt(size.width * size.width + size.height * size.height) * 0.62, 950)
            let phase = seed * 6.283
            var radius: CGFloat = 46
            var index = 0
            while radius < maxRadius {
                let segments = 120
                var path = Path()
                for i in 0...segments {
                    let theta = CGFloat(i) / CGFloat(segments) * 2 * .pi
                    let wobble = sin(theta * 5 + phase + CGFloat(index) * 0.55) * radius * 0.045
                        + sin(theta * 11 - phase + CGFloat(index) * 0.31) * radius * 0.016
                    let r = radius + wobble
                    let point = CGPoint(x: cx + cos(theta) * r, y: cy + sin(theta) * r)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                let fade = 1 - min(radius / maxRadius, 1)
                let accent = index % 4 == 0
                let width: CGFloat = accent ? 3 : 1.4
                context.stroke(
                    path.applying(CGAffineTransform(translationX: -0.8, y: -1)),
                    with: .color(.white.opacity((accent ? 0.30 : 0.20) * fade * strength)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                context.stroke(
                    path.applying(CGAffineTransform(translationX: 1, y: 1.2)),
                    with: .color(BrandPalette.rippleShadow.opacity((accent ? 0.38 : 0.24) * fade * strength)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                radius += 32 + CGFloat(index % 3) * 7
                index += 1
            }
        }
        .blur(radius: 1)
    }
}

extension Stage {
    /// Where the ripple texture must stay clear of the words, with margin, so the
    /// contrast ratios in docs/COLOR.md hold exactly as measured.
    enum TextZone {
        /// SideCopy: words in a column on the left.
        case leftColumn
        /// TopCopy / PortraitCopy: words centred across the top.
        case topBand
    }

    enum Ground {
        /// Warm sand deepening to the icon's clay.
        case sand
        /// Neutral near-black, for slides whose UI is light: the UI is what pops.
        case night
    }

    /// The field every screenshot sits on, lit from the top, rippled outward from the
    /// same point as the Apple Intelligence glow, with a soft lavender glow.
    struct Backdrop<Content: View>: View {
        var glow: UnitPoint
        var textZone: TextZone
        var ground: Ground = .sand
        @ViewBuilder var content: Content

        var body: some View {
            ZStack(alignment: .topLeading) {
                switch ground {
                case .sand:
                    LinearGradient(
                        colors: [BrandPalette.fieldTop, BrandPalette.fieldBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                    RippleField(center: glow, seed: glow.x + glow.y)
                        .mask(textZoneMask)
                    RadialGradient(
                        colors: [.white.opacity(0.35), .clear],
                        center: .init(x: 0.3, y: -0.1), startRadius: 0, endRadius: 900
                    )
                    RadialGradient(
                        colors: [BrandPalette.glow.opacity(0.45), BrandPalette.glow.opacity(0.0)],
                        center: glow, startRadius: 0, endRadius: 600
                    )
                case .night:
                    // Kept neutral and quiet: no ripple or lavender glow, which only read
                    // as smudges and a colour cast on near-black. The UI is the texture.
                    LinearGradient(
                        colors: [BrandPalette.nightTop, BrandPalette.nightBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                    // A faint lift behind the words, so the top isn't a dead flat black.
                    RadialGradient(
                        colors: [.white.opacity(0.05), .clear],
                        center: .init(x: 0.5, y: 0.15), startRadius: 0, endRadius: 700
                    )
                }
                content
            }
            .frame(width: VirtualScreen.size.width, height: VirtualScreen.size.height)
            .environment(\.colorScheme, .light)
        }

        /// Clear over the words' box, feathering in just past its edge.
        @ViewBuilder private var textZoneMask: some View {
            switch textZone {
            case .leftColumn:
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.52), .init(color: .black, location: 0.64)],
                    startPoint: .leading, endPoint: .trailing
                )
            case .topBand:
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.44), .init(color: .black, location: 0.56)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }
}

/// A macOS menu bar's right side — the status items and clock — drawn over the stage so
/// the real popover has something to hang from. Time is the traditional 9:41 (the stage's
/// fixed clock), on today's date, so it agrees with the dates Encore shows.
struct MenuBar: View {
    static let height: CGFloat = 32
    /// Where Encore's status item sits, in stage points.
    static let encoreItem = CGRect(x: 1062, y: 4, width: 36, height: 24)
    /// The menu bar's own format: "Thu Sep 24  9:41 AM".
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d  h:mm a"
        return formatter
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: Self.height)
            // Encore, open.
            Capsule()
                .fill(.black.opacity(0.1))
                .frame(width: Self.encoreItem.width, height: Self.encoreItem.height)
                .offset(x: Self.encoreItem.minX, y: Self.encoreItem.minY)
            item("rectangle.stack", x: Self.encoreItem.midX)
            item("battery.100percent", x: 1134, size: 17)
            item("wifi", x: 1176)
            item("magnifyingglass", x: 1212)
            item("switch.2", x: 1248)
            Text(Self.clock.string(from: .now))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.black)
                .frame(width: 170, alignment: .trailing)
                .position(x: 1440 - 16 - 85, y: Self.height / 2)
        }
        .frame(width: 1440, height: 900, alignment: .topLeading)
    }

    private func item(_ symbol: String, x: CGFloat, size: CGFloat = 14.5) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.black)
            .position(x: x, y: Self.height / 2)
    }
}

/// The Dock of a new Mac: Apple's own apps in their default order, then Encore, kept in
/// the Dock, then the Trash. Icons are read from the apps, so they're always the
/// system's current ones.
struct Dock: View {
    static let iconSize: CGFloat = 50
    static let padding: CGFloat = 7
    static let bottomInset: CGFloat = 6
    /// Stage y of the Dock's top edge; windows end above it.
    static let top = VirtualScreen.size.height - bottomInset - iconSize - padding * 2

    var encoreRunning: Bool

    private static let apps = [
        "/System/Library/CoreServices/Finder.app", "/System/Applications/Apps.app",
        "/Applications/Safari.app", "/System/Applications/Messages.app", "/System/Applications/Mail.app",
        "/System/Applications/Maps.app", "/System/Applications/Photos.app", "/System/Applications/FaceTime.app",
        "/System/Applications/Phone.app", "/System/Applications/Calendar.app", "/System/Applications/Contacts.app",
        "/System/Applications/Reminders.app", "/System/Applications/Notes.app", "/System/Applications/Freeform.app",
        "/System/Applications/TV.app", "/System/Applications/Music.app", "/System/Applications/App Store.app",
        "/System/Applications/System Settings.app",
    ].filter { FileManager.default.fileExists(atPath: $0) }
    /// What else a working day would have open: the apps the demo history was copied from.
    private static let running: Set<String> = ["Finder.app", "Safari.app", "Messages.app", "Mail.app"]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Self.apps, id: \.self) { path in
                // Safari in /Applications is a link into the system cryptex; the link's
                // icon would carry an alias arrow.
                let app = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                tile(NSWorkspace.shared.icon(forFile: app), running: Self.running.contains((path as NSString).lastPathComponent))
            }
            tile(ProcessInfo.processInfo.environment["ENCORE_ICON_PNG"].flatMap(NSImage.init(contentsOfFile:)) ?? NSImage(),
                 running: encoreRunning)
            Capsule()
                .fill(.primary.opacity(0.22))
                .frame(width: 1, height: Self.iconSize * 0.78)
                .padding(.horizontal, 5)
            tile(NSImage(named: NSImage.trashEmptyName) ?? NSImage(), running: false)
        }
        .padding(Self.padding)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func tile(_ icon: NSImage, running: Bool) -> some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .overlay(alignment: .bottom) {
                if running {
                    Circle()
                        .fill(.primary.opacity(0.75))
                        .frame(width: 4, height: 4)
                        .offset(y: 5)
                }
            }
    }
}

/// Words on the left, UI on the right.
struct SideCopy: View {
    var icon = false
    var eyebrow: String? = nil
    var headline: String
    var subhead: String
    var chips: [String] = []
    var features: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if icon {
                AppIconImage()
                    .frame(width: 124, height: 124)
                    .shadow(color: BrandPalette.ink.opacity(0.22), radius: 18, y: 10)
                    .padding(.bottom, 30)
                    .padding(.leading, -10)
            }
            if let eyebrow {
                Eyebrow(text: eyebrow).padding(.bottom, 16)
            }
            Text(headline)
                .font(.system(size: 62, weight: .bold))
                .tracking(-1.2)
                .lineSpacing(-2)
                .foregroundStyle(BrandPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subhead)
                .font(.system(size: 23, weight: .regular))
                .lineSpacing(5)
                .foregroundStyle(BrandPalette.inkSecondary)
                .frame(width: 540, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            if !chips.isEmpty {
                ChipCloud(chips: chips)
                    .frame(width: 560, alignment: .leading)
                    .padding(.top, 34)
            }
            if !features.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(features, id: \.1) { symbol, text in
                        HStack(spacing: 16) {
                            Image(systemName: symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(BrandPalette.blue)
                                .frame(width: 30)
                            Text(text)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(BrandPalette.ink)
                        }
                    }
                }
                .padding(.top, 38)
            }
        }
        .frame(width: 640, alignment: .leading)
        .frame(maxHeight: .infinity)
        .padding(.leading, 104)
        .frame(width: 1440, height: 900, alignment: .leading)
    }
}

/// Words centred at the top, a window below.
struct TopCopy: View {
    var eyebrow: String? = nil
    var headline: String
    var subhead: String

    var body: some View {
        VStack(spacing: 0) {
            if let eyebrow {
                Eyebrow(text: eyebrow).padding(.bottom, 14)
            }
            Text(headline)
                .font(.system(size: 58, weight: .bold))
                .tracking(-1.1)
                .foregroundStyle(BrandPalette.ink)
            Text(subhead)
                .font(.system(size: 23))
                .foregroundStyle(BrandPalette.inkSecondary)
                .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
        .frame(width: 1440)
        .padding(.top, eyebrow == nil ? 96 : 72)
        .frame(width: 1440, height: 900, alignment: .top)
    }
}

/// "✦ Apple Intelligence" in the sparkle's colours, deepened to read on sand.
struct Eyebrow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text(text)
        }
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(
            LinearGradient(colors: [BrandPalette.blue, BrandPalette.lavender], startPoint: .leading, endPoint: .trailing)
        )
    }
}

/// Small glass capsules naming what a feature can do.
struct ChipCloud: View {
    let chips: [String]

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(BrandPalette.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .glassEffect(.clear, in: .capsule)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .init(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Encore's icon, rendered from Resources/AppIcon.icon by make-screenshots.sh.
struct AppIconImage: View {
    var body: some View {
        if let path = ProcessInfo.processInfo.environment["ENCORE_ICON_PNG"], let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white.opacity(0.2))
        }
    }
}
