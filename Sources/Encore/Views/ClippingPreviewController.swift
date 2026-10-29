import SwiftUI
import AppKit

/// Shows a clipping's preview in a window beside the popover while the pointer rests on
/// its row, or the keyboard highlight is on it.
///
/// - Appears after a short rest of the pointer; once one preview is up, moving to another
///   row swaps it at once, so running down the list reads like flipping through cards.
/// - Sits to the left of the popover, top-aligned with it, as tall as the screen allows.
///   Where the left has no room (an icon near the screen's left edge) it goes to the
///   right, and with no room on either side it simply doesn't appear.
/// - Never takes the mouse or focus: the popover keeps both, and a preview can't get in
///   the way of a click, or close the popover by being clicked.
@MainActor
final class ClippingPreviewController {
    static let shared = ClippingPreviewController()

    /// The popover's content view: what the preview lines up beside.
    weak var anchorView: NSView?

    private let store = ClipboardStore.shared
    private var panel: NSPanel?
    private var hosting: NSHostingView<ClippingPreviewView>?
    private var current: ClippingPreview?

    private var pointerID: UUID?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    /// Bumped by every hide, so a fade-out that is overtaken never orders the window out.
    private var hideGeneration = 0

    private var isShown: Bool { panel?.isVisible == true && current != nil }
    private var animates: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private init() {}

    // MARK: - Events

    /// The pointer came onto a row.
    func pointerEntered(_ clipping: Clipping, query: String) {
        guard store.showsHoverPreview else { return }
        pointerID = clipping.id
        hideTask?.cancel()
        if isShown {
            show(clipping, query: query)
            return
        }
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled, let self, self.pointerID == clipping.id else { return }
            self.show(clipping, query: query)
        }
    }

    /// The pointer left a row. Ignored when it has already entered another: those two
    /// events can arrive in either order.
    func pointerExited(_ id: UUID) {
        guard pointerID == id else { return }
        pointerID = nil
        showTask?.cancel()
        guard isShown else { return }
        hideTask?.cancel()
        // Long enough to cross the gap between two rows without the card blinking out.
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.dismiss(animated: true)
        }
    }

    /// The keyboard highlight moved to a row: shown at once, there is no pointer to wait for.
    func present(_ clipping: Clipping, query: String) {
        guard store.showsHoverPreview else { return }
        showTask?.cancel()
        hideTask?.cancel()
        show(clipping, query: query)
    }

    /// Hides the preview now: the page changed, the popover is closing, a search began.
    func dismiss(animated: Bool = false) {
        showTask?.cancel()
        hideTask?.cancel()
        imageTask?.cancel()
        pointerID = nil
        current = nil
        guard let panel, panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        let finish = { [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.detach()
        }
        if animated, animates {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated(finish)
            }
        } else {
            finish()
        }
    }

    /// Hides the preview if its clipping is gone, so a deleted clipping never lingers.
    func validate(against clippings: [Clipping]) {
        guard let id = current?.clippingID, !clippings.contains(where: { $0.id == id }) else { return }
        dismiss()
    }

    // MARK: - Showing

    private func show(_ clipping: Clipping, query: String) {
        guard let anchor = anchorView, let window = anchor.window, window.isVisible else { return }
        // Already showing this clipping (a hover that follows the keyboard onto the same
        // row, say): nothing to redo.
        if isShown, current?.clippingID == clipping.id { return }

        let anchorFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        guard let screen, let place = Placement(anchor: anchorFrame, visible: screen.visibleFrame, textScale: store.textSize.scale) else {
            dismiss()
            return
        }

        imageTask?.cancel()
        let preview = ClippingPreview(clipping, query: query, limits: .init(
            maxWidth: place.maxWidth,
            maxHeight: place.maxHeight,
            textScale: store.textSize.scale,
            backingScale: screen.backingScaleFactor
        ))
        current = preview

        let panel = ensurePanel()
        let size = preview.size
        let origin = NSPoint(
            x: place.isOnLeft ? anchorFrame.minX - Placement.gap - size.width : anchorFrame.maxX + Placement.gap,
            y: place.top - size.height
        )
        hosting?.rootView = ClippingPreviewView(preview: preview)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()

        hideGeneration += 1
        if panel.isVisible {
            // A plain assignment would not stop a fade-out still running from a hover-out
            // a moment ago, which would carry on to zero and leave the card invisible.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = animates ? 0 : 1
            panel.level = window.level
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            if animates {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    panel.animator().alphaValue = 1
                }
            }
        }

        imageTask = Task { await preview.loadImage() }
    }

    private func detach() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.setAccessibilityElement(false)

        let hosting = NSHostingView(rootView: ClippingPreviewView(preview: ClippingPreview(
            Clipping(kind: .text, text: ""), query: "",
            limits: .init(maxWidth: 400, maxHeight: 400, textScale: 1, backingScale: 2)
        )))
        // The window's size is set from the preview, never the other way round.
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    /// A card that cannot take the keyboard. Without this the panel, ordered above the
    /// popover as its child, could become the key window — and then Return, Escape and
    /// even plain typing went to a window with nothing to receive them, so the popover
    /// appeared to stop responding while a preview was up.
    private final class PreviewPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    // MARK: - Placement

    /// Where the preview goes relative to the popover, and how much room it has there.
    private struct Placement {
        static let gap: CGFloat = 8
        private static let margin: CGFloat = 8
        /// Narrower than this and a preview isn't worth showing.
        private static let minimumWidth: CGFloat = 220
        private static let maximumHeight: CGFloat = 880

        let isOnLeft: Bool
        let maxWidth: CGFloat
        let maxHeight: CGFloat
        /// Screen y of the preview's top edge: level with the popover's.
        let top: CGFloat

        init?(anchor: NSRect, visible: NSRect, textScale: CGFloat) {
            let wanted = (580 * (1 + (textScale - 1) * 0.36)).rounded()
            let left = anchor.minX - Self.gap - (visible.minX + Self.margin)
            let right = (visible.maxX - Self.margin) - (anchor.maxX + Self.gap)
            if left >= Self.minimumWidth || left >= right {
                guard left >= Self.minimumWidth else { return nil }
                isOnLeft = true
                maxWidth = min(wanted, left)
            } else {
                guard right >= Self.minimumWidth else { return nil }
                isOnLeft = false
                maxWidth = min(wanted, right)
            }
            top = min(anchor.maxY, visible.maxY - Self.margin)
            maxHeight = min(Self.maximumHeight, top - (visible.minY + Self.margin))
            guard maxHeight >= 80 else { return nil }
        }
    }
}
