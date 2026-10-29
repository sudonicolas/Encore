import SwiftUI
import AppKit

/// One of the popover's keyboard commands, recognised before anything in the popover has
/// a chance to swallow it.
enum PopoverKey: Equatable {
    case escape
    /// Return or Enter.
    case submit
    case moveUp
    case moveDown
    /// \u{2318}\u{2193}: show the highlighted clipping's details.
    case openDetail
    /// \u{2325}1 through \u{2325}0, as a zero-based row index.
    case quickSlot(Int)
    /// A plain character on its way to the search field.
    case typing
}

/// Makes the popover's keyboard commands work no matter what has focus.
///
/// The popover's keys used to hang off the search field, so they only worked while that
/// field held focus — and a fresh view on every open, a click on a row, the text editor,
/// or the hover preview could all leave focus somewhere else, or nowhere at all. Then
/// Escape wouldn't close and Return wouldn't copy.
///
/// A local key monitor, scoped strictly to the popover's own window and alive only while
/// the popover is on screen, sees every key press before it is dispatched to a first
/// responder — including when there is no first responder at all. Commands are decided
/// here; plain typing is always passed through, and so is everything the text editor
/// needs while it is being edited.
struct PopoverKeyHandler: NSViewRepresentable {
    /// Returns true when the key was used up and must not travel any further.
    let handle: (PopoverKey) -> Bool

    func makeNSView(context: Context) -> KeyMonitorView {
        KeyMonitorView()
    }

    /// SwiftUI re-runs this on every update, which is what keeps the closure — and the
    /// view state it reads — current. A stale closure would decide with yesterday's
    /// search text.
    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        nsView.handle = handle
    }

    static func dismantleNSView(_ nsView: KeyMonitorView, coordinator: ()) {
        nsView.stop()
    }
}

/// An invisible view that watches its own window's key presses.
final class KeyMonitorView: NSView {
    var handle: ((PopoverKey) -> Bool)?
    private var monitor: Any?

    override var isOpaque: Bool { false }
    /// It is a hook for key events, not a thing on screen.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityIsIgnored() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stop() : start()
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.route(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        // deinit can land off the main actor; removeMonitor is safe to call anywhere.
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// True when the event was consumed.
    private func route(_ event: NSEvent) -> Bool {
        // Only this popover's keys. Other windows — History, Settings, another app's —
        // keep their own keyboard entirely. A child window counts as the popover's: the
        // hover preview is one, and a key aimed at it is still meant for the list.
        guard let window, let handle,
              event.window === window || event.window?.parent === window
        else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        // While text is being edited, the editor comes first: Return makes a newline,
        // the arrows move the insertion point, Option+digit types a character. Only
        // Escape is taken, and it just leaves the editor — settling the edit through the
        // text view's own textDidEndEditing. A second Escape then does whatever Escape
        // means on this page.
        if isEditingText {
            guard event.keyCode == Self.escapeKey, flags.isEmpty else { return false }
            window.makeFirstResponder(nil)
            return true
        }

        switch (event.keyCode, flags) {
        case (Self.escapeKey, []):
            return handle(.escape)
        case (Self.returnKey, []), (Self.enterKey, []):
            return handle(.submit)
        case (Self.downArrow, .command):
            return handle(.openDetail)
        case (Self.downArrow, []):
            return handle(.moveDown)
        case (Self.upArrow, []):
            return handle(.moveUp)
        default:
            break
        }

        // Option+digit copies one of the first ten rows. Bare Option only: Option+Command
        // and friends belong to whatever else claims them.
        if flags == .option, let digit = event.charactersIgnoringModifiers?.first?.wholeNumberValue {
            // The badges read 1…9 then 0 for the tenth row.
            return handle(.quickSlot(digit == 0 ? 9 : digit - 1))
        }

        // Anything else printable is typing. If nothing has focus, the search field is
        // asked to take it, and the key then lands there as normal — so typing searches
        // even when focus went astray.
        if flags.isEmpty || flags == .shift, let characters = event.charactersIgnoringModifiers,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            if window.firstResponder == nil || window.firstResponder === window {
                _ = handle(.typing)
            }
        }
        return false
    }

    /// Whether a clipping's text is being edited.
    ///
    /// Not merely "an editable NSTextView has focus": a SwiftUI TextField is backed by an
    /// NSTextField, and while it has focus the window's first responder is its *field
    /// editor* — which is an editable NSTextView too. Taking that for the clipping editor
    /// handed every command straight back to the search field, so Return copied nothing
    /// and Escape only dropped focus instead of closing. A field editor is excluded by
    /// the one flag that tells them apart.
    private var isEditingText: Bool {
        guard let textView = window?.firstResponder as? NSTextView else { return false }
        return textView.isEditable && !textView.isFieldEditor
    }

    private static let escapeKey: UInt16 = 53
    private static let returnKey: UInt16 = 36
    private static let enterKey: UInt16 = 76
    private static let upArrow: UInt16 = 126
    private static let downArrow: UInt16 = 125
}
