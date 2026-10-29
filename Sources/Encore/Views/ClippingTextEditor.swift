import SwiftUI
import AppKit

/// A clipping's full text in the detail screen: selectable, and editable for text
/// clippings you own (not in Recently Deleted).
///
/// SwiftUI's `TextEditor` can't report the selection, and the detail screen's copy
/// button needs it, so it can copy just the selection when there is one and the whole
/// clipping when there isn't. Hence the AppKit bridge. It also renders inline
/// search-match highlighting.
///
/// Editing: every change goes to `onEdit` as it's made, so Copy, search and the list
/// always see the current text, and `onEndEditing` fires when the text loses focus.
/// Undo and redo are this editor's own (⌘Z and ⇧⌘Z, and Control-Z and Control-⇧Z too),
/// kept apart from the window's, so they only ever undo typing in this clipping. Earlier
/// versions of the whole text are the store's job (see `ClipboardStore.editText`).
///
/// Accessibility: VoiceOver reads it as a text area named "Clipping Text", where the
/// usual text navigation works; it follows the Text Size setting; and search matches are
/// underlined with Differentiate Without Color on.
struct ClippingTextEditor: View {
    let text: String
    var isEditable = true
    var highlightQuery: String = ""
    @Binding var selectedText: String?
    var onEdit: (String) -> Void = { _ in }
    var onEndEditing: () -> Void = {}

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        EditorRepresentable(
            text: text,
            isEditable: isEditable,
            highlightQuery: highlightQuery,
            fontSize: (NSFont.preferredFont(forTextStyle: .body).pointSize * textScale).rounded(),
            underlinesMatches: differentiateWithoutColor,
            selectedText: $selectedText,
            onEdit: onEdit,
            onEndEditing: onEndEditing
        )
    }
}

/// Undo, redo and text-navigation shortcuts that must reach the editor before the
/// popover's own shortcuts (⌘↑ goes Back in the popover, but in text it means "start").
private final class EditorTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if event.charactersIgnoringModifiers?.lowercased() == "z" {
            if flags == .command || flags == .control {
                if undoManager?.canUndo == true { undoManager?.undo() }
                return true
            }
            if flags == [.command, .shift] || flags == [.control, .shift] {
                if undoManager?.canRedo == true { undoManager?.redo() }
                return true
            }
        }
        if flags == .command {
            switch event.keyCode {
            case 126: moveToBeginningOfDocument(nil); return true
            case 125: moveToEndOfDocument(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Escape leaves the text first; a second Escape then goes Back.
    override func cancelOperation(_ sender: Any?) {
        if isEditable, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        } else {
            super.cancelOperation(sender)
        }
    }
}

private struct EditorRepresentable: NSViewRepresentable {
    let text: String
    let isEditable: Bool
    let highlightQuery: String
    let fontSize: CGFloat
    let underlinesMatches: Bool
    @Binding var selectedText: String?
    let onEdit: (String) -> Void
    let onEndEditing: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = EditorTextView()
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.isSelectable = true
        textView.isEditable = isEditable
        // Plain text, exactly as copied: no smart quotes, dashes, links or corrections
        // rewriting code or addresses behind the user's back, and pasting drops styling.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Clipping Text")
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.string = text
        context.coordinator.apply(to: textView, parent: self)
        context.coordinator.undoManager.removeAllActions()
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(to: nsView, parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let container = nsView.textContainer, let layoutManager = nsView.layoutManager else {
            return nil
        }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        let extra = layoutManager.extraLineFragmentRect.maxY
        let line = layoutManager.defaultLineHeight(for: NSFont.systemFont(ofSize: fontSize))
        return CGSize(width: width, height: ceil(max(used, extra, line)))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorRepresentable
        /// This editor's own undo stack, so ⌘Z never reaches into another clipping.
        let undoManager = UndoManager()
        private var lastPassedText: String?
        private var appliedFontSize: CGFloat = 0
        private var appliedHighlight = ""
        private var appliedUnderline = false

        init(parent: EditorRepresentable) {
            self.parent = parent
            undoManager.levelsOfUndo = 500
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        /// Brings the view in line with SwiftUI's state without disturbing the user:
        /// text only when it really differs (an external change such as restoring a
        /// version, which stays undoable), never while an input method is composing.
        func apply(to textView: NSTextView, parent: EditorRepresentable) {
            textView.isEditable = parent.isEditable

            // Only when SwiftUI's text actually changed since the last pass: an update
            // still carrying the text from before the latest keystroke is stale, and
            // must not overwrite what was just typed.
            let externalChange = parent.text != lastPassedText
            lastPassedText = parent.text
            if externalChange, textView.string != parent.text, !textView.hasMarkedText() {
                let selection = textView.selectedRange()
                let whole = NSRange(location: 0, length: (textView.string as NSString).length)
                // Its own undo step, not folded into the typing before it.
                textView.breakUndoCoalescing()
                if textView.shouldChangeText(in: whole, replacementString: parent.text) {
                    textView.textStorage?.replaceCharacters(in: whole, with: parent.text)
                    textView.didChangeText()
                }
                textView.breakUndoCoalescing()
                let length = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
                appliedFontSize = 0
                textView.invalidateIntrinsicContentSize()
            }

            if appliedFontSize != parent.fontSize {
                appliedFontSize = parent.fontSize
                // Styling isn't an edit: it must not become a step ⌘Z has to undo.
                undoManager.disableUndoRegistration()
                textView.font = NSFont.systemFont(ofSize: parent.fontSize)
                textView.textColor = .labelColor
                undoManager.enableUndoRegistration()
                textView.invalidateIntrinsicContentSize()
            }

            if appliedHighlight != parent.highlightQuery || appliedUnderline != parent.underlinesMatches
                || !parent.highlightQuery.isEmpty {
                appliedHighlight = parent.highlightQuery
                appliedUnderline = parent.underlinesMatches
                highlight(in: textView)
            }
        }

        /// Search matches are drawn with temporary attributes, which never become part
        /// of the text: typing beside a match isn't highlighted, and undo ignores them.
        private func highlight(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let string = textView.string as NSString
            let whole = NSRange(location: 0, length: string.length)
            for key in [NSAttributedString.Key.backgroundColor, .foregroundColor, .underlineStyle] {
                layoutManager.removeTemporaryAttribute(key, forCharacterRange: whole)
            }
            let query = parent.highlightQuery
            guard !query.isEmpty else { return }
            var search = whole
            while search.length > 0 {
                let found = string.range(of: query, options: .caseInsensitive, range: search)
                guard found.location != NSNotFound, found.length > 0 else { break }
                // Same treatment as list rows (see Text.highlighting).
                layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.findHighlightColor, forCharacterRange: found)
                layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.black, forCharacterRange: found)
                if parent.underlinesMatches {
                    layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: found)
                }
                let next = found.location + found.length
                search = NSRange(location: next, length: whole.length - next)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // First, before anything below can trigger a SwiftUI update.
            parent.onEdit(textView.string)
            highlight(in: textView)
            textView.invalidateIntrinsicContentSize()
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let swiftRange = Range(range, in: textView.string) else {
                if parent.selectedText != nil { parent.selectedText = nil }
                return
            }
            let selected = String(textView.string[swiftRange])
            if parent.selectedText != selected {
                parent.selectedText = selected
            }
        }
    }
}
