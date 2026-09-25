import AppKit
import SwiftUI

/// The portrait set: five 4:5 screenshots (2160x2700) for a carousel seen on a phone.
///
/// One idea per slide: words on top, the real UI below it, both with open space all
/// round (at least 120 points to every edge) so the slide can take a float or zoom
/// without anything hitting the frame. Encore runs at 175% Text Size so clippings stay
/// legible when the whole slide is phone-sized.
@MainActor
extension Scenes {
    static let portrait: [Scene] = [portraitHero, portraitTitles, portraitRewrite, portraitLookups, portraitPrivacy]

    /// The least open space between anything on a slide and the slide's edge.
    static let portraitAir: CGFloat = 120
    /// Where the UI starts, below the words. With the UI `DesktopPanel.height` tall,
    /// this leaves `portraitAir` under it.
    static let portraitUITop: CGFloat = 540
    /// The Settings window is shorter than the popover slides' UI and the words above it
    /// are taller, so both move down to keep the space above and below even.
    static let portraitSettingsTop: CGFloat = 700
    /// Encore's own Text Size, so clippings stay legible when the slide is phone-sized.
    static let portraitTextSize = TextSize.huge

    // MARK: 1 · Hero

    static let portraitHero = Scene(
        name: "hero",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.85, y: 0.05), textZone: .topBand, ground: .night) {
                PortraitCopy(
                    icon: true,
                    headline: "Everything you copy,\nready for an encore.",
                    subhead: "Your clipboard history, one click away.",
                    night: true
                )
                DesktopPanel(top: portraitUITop)
            }
        ),
        run: { stage in
            stage.store.textSize = portraitTextSize
            try await stage.openPinnedPopover(under: DesktopPanel.encoreItem(top: portraitUITop))
        }
    )

    // MARK: 2 · Smart titles

    static let portraitTitles = Scene(
        name: "smart-titles",
        appearance: .darkAqua,
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.1, y: 1.0), textZone: .topBand) {
                PortraitCopy(
                    eyebrow: "Apple Intelligence",
                    headline: "Know what you\ncopied at a glance.",
                    subhead: "Long clippings get a short, clear title."
                )
            }
        ),
        run: { stage in
            stage.store.textSize = portraitTextSize
            // Sidebar and list on the slide, lined up with the other slides' UI; the
            // detail pane runs off the right edge (at this Text Size it can't fit). The
            // height ends the window between two list rows, not through one.
            let window = try await stage.openHistory(frame: CGRect(
                x: DesktopPanel.inset, y: portraitUITop, width: 1300, height: 642
            ))
            // The list as wide as it goes, so titles show in full at this Text Size.
            try await stage.widenList(in: window, to: 520)
            let flight = stage.store.clippings.first { $0.text?.contains(DemoData.Key.flight) == true }!
            try await stage.select(flight.id, in: window)
        }
    )

    // MARK: 3 · Writing tools

    static let portraitRewrite = Scene(
        name: "writing-tools",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.9, y: 0.1), textZone: .topBand, ground: .night) {
                PortraitCopy(
                    eyebrow: "Apple Intelligence",
                    headline: "Rewrite it before\nyou paste it.",
                    subhead: "Proofread or change the tone, on device.",
                    night: true
                )
                DesktopPanel(top: portraitUITop)
            }
        ),
        run: { stage in
            stage.store.textSize = portraitTextSize
            _ = try stage.bringToTop(DemoData.Key.casualUpdate)
            let popover = try await stage.openPinnedPopover(under: DesktopPanel.encoreItem(top: portraitUITop))
            try await stage.openNewestDetailWithKeyboard(in: popover)
            let window = popover.contentViewController!.view.window!
            let frame = stage.stageRect(window.frame)
            try await stage.runIntelligence(
                "Make Professional", clickingAt: CGPoint(x: frame.maxX - 136, y: frame.minY + 38), in: window
            )
            stage.pin(popover, under: DesktopPanel.encoreItem(top: portraitUITop))
        }
    )

    // MARK: 4 · Lookups

    static let portraitLookups = Scene(
        name: "lookups",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.15, y: 0.1), textZone: .topBand, ground: .night) {
                PortraitCopy(
                    headline: "Prices, converted\nthe moment you copy.",
                    subhead: "Plus definitions and Wikipedia summaries.",
                    night: true
                )
                DesktopPanel(top: portraitUITop)
            }
        ),
        run: { stage in
            stage.store.textSize = portraitTextSize
            _ = try stage.bringToTop(DemoData.Key.price)
            let popover = try await stage.openPinnedPopover(under: DesktopPanel.encoreItem(top: portraitUITop))
            try await stage.openNewestDetailWithKeyboard(in: popover)
            // Exchange rates come from the network.
            try await Task.sleep(for: .seconds(3))
            stage.pin(popover, under: DesktopPanel.encoreItem(top: portraitUITop))
        }
    )

    // MARK: 5 · Privacy

    static let portraitPrivacy = Scene(
        name: "privacy",
        backdrop: AnyView(
            Stage.Backdrop(glow: .init(x: 0.9, y: 1.0), textZone: .topBand, ground: .night) {
                PortraitCopy(
                    headline: "Your clipboard\nstays yours.",
                    subhead: "No account. No tracking. No cloud.",
                    features: [
                        ("lock.shield", "Skips what password managers copy"),
                        ("hand.raised", "Ignores any app you choose"),
                        ("cpu", "Apple Intelligence runs on your Mac"),
                    ],
                    region: portraitSettingsTop,
                    night: true
                )
            }
        ),
        run: { stage in
            let window = try await stage.openSettings(tab: 3, origin: CGPoint(x: 0, y: portraitSettingsTop))
            // Centre it, whatever width the pane settled on.
            let frame = stage.stageRect(window.frame)
            let origin = CGPoint(x: ((VirtualScreen.size.width - frame.width) / 2).rounded(), y: portraitSettingsTop)
            window.setFrame(stage.screenRect(CGRect(origin: origin, size: frame.size)), display: true)
        }
    )
}

// MARK: - Driving Encore

extension Stage {
    /// The popover, hanging from its status item. At 175% Text Size it's taller than
    /// macOS will let it hang this far down the virtual display, which nudges it up over
    /// the drawn menu bar; put it back where a real one would sit.
    @discardableResult
    func openPinnedPopover(under anchor: CGRect) async throws -> NSPopover {
        let popover = try await openPopover(under: anchor)
        pin(popover, under: anchor)
        return popover
    }

    func pin(_ popover: NSPopover, under anchor: CGRect) {
        guard let window = popover.contentViewController?.view.window else { return }
        let frame = stageRect(window.frame)
        let pinned = CGRect(x: (anchor.midX - frame.width / 2).rounded(), y: anchor.maxY + 1, width: frame.width, height: frame.height)
        window.setFrameOrigin(screenRect(pinned).origin)
    }

    /// Drags the History window's list/detail divider so the list is `width` wide.
    func widenList(in window: NSWindow, to width: CGFloat) async throws {
        var splits: [NSSplitView] = []
        func walk(_ view: NSView) {
            if let split = view as? NSSplitView { splits.append(split) }
            view.subviews.forEach(walk)
        }
        window.contentView.map(walk)
        guard let split = splits.first(where: { $0.arrangedSubviews.count == 3 }) else {
            throw StageError("No three-column split view in History")
        }
        let sidebar = split.arrangedSubviews[0].frame.maxX + split.dividerThickness
        split.setPosition(sidebar + width, ofDividerAt: 1)
        try await Task.sleep(for: .milliseconds(500))
    }

    /// In the popover: opens the newest clipping's detail page from the keyboard, as a
    /// person would: ↓ past the two pinned clippings to the first recent one, then ⌘↓.
    /// Unlike a click, this doesn't depend on row heights, which grow with Text Size.
    func openNewestDetailWithKeyboard(in popover: NSPopover) async throws {
        guard let window = popover.contentViewController?.view.window else { throw StageError("No popover window") }
        for _ in 0..<3 {
            pressDownArrow(in: window)
            try await Task.sleep(for: .milliseconds(150))
        }
        pressDownArrow(in: window, modifiers: .command)
        try await Task.sleep(for: .milliseconds(700))
    }

    private func pressDownArrow(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) {
        let arrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers.union([.numericPad, .function]),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: arrow, charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 125
            ) else { continue }
            window.sendEvent(event)
        }
    }
}

// MARK: - Portrait pieces

/// Words centred at the top of a portrait slide: the icon or an eyebrow, a two-line
/// headline, one short line of support, and optionally a few promises.
struct PortraitCopy: View {
    var icon = false
    var eyebrow: String? = nil
    var headline: String
    var subhead: String
    var features: [(String, String)] = []
    /// The space above the UI; the words sit centred in it, clear of the top margin.
    var region: CGFloat = Scenes.portraitUITop
    /// On the night ground (`Stage.Ground.night`): light words instead of ink.
    var night = false

    var body: some View {
        let headlineColor = night ? BrandPalette.onNight : BrandPalette.ink
        let subheadColor = night ? BrandPalette.onNightSecondary : BrandPalette.inkSecondary
        let accentBlue = night ? BrandPalette.blueOnNight : BrandPalette.blue
        let accentLavender = night ? BrandPalette.lavenderOnNight : BrandPalette.lavender
        VStack(spacing: 0) {
            if icon {
                AppIconImage()
                    .frame(width: 100, height: 100)
                    .shadow(color: night ? .black.opacity(0.5) : BrandPalette.ink.opacity(0.22), radius: 16, y: 8)
                    .padding(.bottom, 22)
            }
            if let eyebrow {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(eyebrow)
                }
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [accentBlue, accentLavender], startPoint: .leading, endPoint: .trailing)
                )
                .padding(.bottom, 16)
            }
            Text(headline)
                .font(.system(size: 62, weight: .bold))
                .tracking(-1.4)
                .lineSpacing(-6)
                .foregroundStyle(headlineColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(subhead)
                .font(.system(size: 30))
                .foregroundStyle(subheadColor)
                .frame(width: 680)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            if !features.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(features, id: \.1) { symbol, text in
                        HStack(spacing: 18) {
                            Image(systemName: symbol)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(accentBlue)
                                .frame(width: 40)
                            Text(text)
                                .font(.system(size: 29, weight: .medium))
                                .foregroundStyle(headlineColor)
                        }
                    }
                }
                .padding(.top, 48)
            }
        }
        .multilineTextAlignment(.center)
        // Centred between the slide's top margin and a smaller gap above the UI.
        .padding(.top, Scenes.portraitAir)
        .padding(.bottom, 60)
        .frame(width: VirtualScreen.size.width, height: region)
        .frame(width: VirtualScreen.size.width, height: VirtualScreen.size.height, alignment: .top)
    }
}

/// A slice of a Mac desktop: its wallpaper and the right side of its menu bar, with
/// Encore's status item in the middle of the slide so the popover hangs centred.
/// A card with all four corners rounded, floating clear of every edge of the slide.
struct DesktopPanel: View {
    var top: CGFloat
    static let width: CGFloat = 744
    /// Room for the popover at 175% Text Size, with some wallpaper showing under it.
    static let height: CGFloat = 690
    static let radius: CGFloat = 40
    static var inset: CGFloat { ((VirtualScreen.size.width - width) / 2).rounded() }

    /// Encore's status item, in stage points.
    static func encoreItem(top: CGFloat) -> CGRect {
        CGRect(x: VirtualScreen.size.width / 2 - 18, y: top + 4, width: 36, height: 24)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d  h:mm a"
        return formatter
    }()

    var body: some View {
        let width = Self.width
        let item = Self.encoreItem(top: 0)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        ZStack(alignment: .topLeading) {
            // A wallpaper a shade deeper than the field, rippled, so the glass popover reads.
            LinearGradient(
                colors: [
                    Color(.displayP3, red: 0.880, green: 0.826, blue: 0.880),
                    Color(.displayP3, red: 0.842, green: 0.720, blue: 0.640),
                    Color(.displayP3, red: 0.690, green: 0.530, blue: 0.445),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RippleField(center: .init(x: 0.5, y: 0.12), seed: 0.42, strength: 1.15)
            RadialGradient(
                colors: [.white.opacity(0.4), .clear],
                center: .init(x: 0.5, y: 0.2), startRadius: 0, endRadius: 460
            )
            // Menu bar.
            Rectangle().fill(.white.opacity(0.28)).frame(height: MenuBar.height)
            Group {
                Capsule()
                    .fill(.black.opacity(0.1))
                    .frame(width: item.width, height: item.height)
                    .position(x: item.midX - Self.inset, y: MenuBar.height / 2)
                symbol("rectangle.stack", x: item.midX)
                symbol("battery.100percent", x: item.midX + 54, size: 17)
                symbol("wifi", x: item.midX + 96)
                symbol("magnifyingglass", x: item.midX + 132)
                symbol("switch.2", x: item.midX + 168)
                Text(Self.clock.string(from: .now))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.black)
                    .fixedSize()
                    .frame(width: 170, alignment: .trailing)
                    .position(x: width - 16 - 85, y: MenuBar.height / 2)
            }
        }
        .frame(width: width, height: Self.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 40, y: 20)
        .offset(x: Self.inset, y: top)
        .frame(width: VirtualScreen.size.width, height: VirtualScreen.size.height, alignment: .topLeading)
    }

    private func symbol(_ name: String, x: CGFloat, size: CGFloat = 14.5) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.black)
            .position(x: x - Self.inset, y: MenuBar.height / 2)
    }
}
