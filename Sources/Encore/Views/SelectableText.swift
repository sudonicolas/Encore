import SwiftUI
import AppKit

/// A selectable, read-only text view for a clipping's full text in the detail screen.
///
/// SwiftUI's `Text` + `.textSelection(.enabled)` lets the user select and Cmd-C, but
/// never tells app code *what* is selected — and the detail screen's copy button needs
/// exactly that, so it can copy just the selection when there is one and fall back to
/// the whole clipping when there isn't. Hence the AppKit bridge. Also renders inline
/// search-match highlighting.
///
/// Accessibility: VoiceOver reads it as a text area named "Clipping Text", where the
/// usual text navigation works; it follows the Text Size setting; and search matches are
/// underlined with Differentiate Without Color on.
struct SelectableText: View {
    let text: String
    var highlightQuery: String = ""
    @Binding var selectedText: String?

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        SelectableTextRepresentable(
            text: text,
            highlightQuery: highlightQuery,
            fontSize: (NSFont.preferredFont(forTextStyle: .body).pointSize * textScale).rounded(),
            underlinesMatches: differentiateWithoutColor,
            selectedText: $selectedText
        )
    }
}

private struct SelectableTextRepresentable: NSViewRepresentable {
    let text: String
    let highlightQuery: String
    let fontSize: CGFloat
    let underlinesMatches: Bool
    @Binding var selectedText: String?

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Clipping Text")
        textView.textStorage?.setAttributedString(attributedString())
        context.coordinator.lastAttributes = attributeKey
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        // Only rewrite the backing storage when the content actually changed — doing it
        // unconditionally would wipe the user's live selection on every SwiftUI update,
        // including the one *caused by* reporting that selection back up.
        guard context.coordinator.lastAttributes != attributeKey else {
            return
        }
        context.coordinator.lastAttributes = attributeKey
        nsView.textStorage?.setAttributedString(attributedString())
        // The new size changes the text's height.
        nsView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let container = nsView.textContainer, let layoutManager = nsView.layoutManager else {
            return nil
        }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let rect = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: ceil(rect.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    /// Everything the attributed string depends on.
    private var attributeKey: String {
        "\(fontSize)|\(underlinesMatches)|\(highlightQuery)|\(text)"
    }

    private func attributedString() -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
        guard !highlightQuery.isEmpty else { return attributed }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: highlightQuery, options: [.caseInsensitive], range: searchRange) {
            let nsRange = NSRange(range, in: text)
            // Same treatment as list rows (see Text.highlighting).
            attributed.addAttribute(.backgroundColor, value: NSColor.findHighlightColor, range: nsRange)
            attributed.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
            if underlinesMatches {
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return attributed
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let selectedText: Binding<String?>
        var lastAttributes = ""

        init(selectedText: Binding<String?>) {
            self.selectedText = selectedText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let swiftRange = Range(range, in: textView.string) else {
                if selectedText.wrappedValue != nil { selectedText.wrappedValue = nil }
                return
            }
            let selected = String(textView.string[swiftRange])
            if selectedText.wrappedValue != selected {
                selectedText.wrappedValue = selected
            }
        }
    }
}
