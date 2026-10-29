import SwiftUI
import AppKit
import ImageIO

/// What the hover preview shows for one clipping, measured and ready to draw.
///
/// The preview is a window of its own beside the popover (see `ClippingPreviewController`),
/// so it can't scroll: instead it is sized to the content, as tall as the screen allows,
/// and says how much more there is when a clipping doesn't fit. Everything is measured up
/// front — text with TextKit, so wrapping and the cut-off are exact — which keeps showing
/// a preview to a few milliseconds even for a very large clipping.
@MainActor
@Observable
final class ClippingPreview {
    /// What the screen leaves room for, and the user's Text Size.
    struct Limits {
        var maxWidth: CGFloat
        var maxHeight: CGFloat
        var textScale: CGFloat
        var backingScale: CGFloat
    }

    struct File: Identifiable {
        let url: URL
        let name: String
        let directory: String
        let icon: NSImage
        let exists: Bool
        var id: URL { url }
    }

    // MARK: Geometry (shared by the builder below and the view)

    static let padding: CGFloat = 14
    static let cornerRadius: CGFloat = 22
    static let spacing: CGFloat = 10
    static let swatchHeight: CGFloat = 56

    let clippingID: UUID
    /// The window's size, padding included.
    private(set) var size = CGSize(width: 240, height: 80)
    let textScale: CGFloat

    private(set) var text: PreviewText?
    /// Shown instead of content: "Empty clipping".
    private(set) var placeholder: String?
    private(set) var swatch: NSColor?
    /// Where an image or a file's picture is drawn; its pixels arrive in `image`.
    private(set) var imageSize: CGSize?
    /// Starts as the row's own small thumbnail, sharpened once the full picture is ready.
    var image: NSImage?
    private(set) var files: [File] = []
    private(set) var footer: String?
    private(set) var footerHeight: CGFloat = 0
    private(set) var fileRowHeight: CGFloat = 0
    /// Whether text is cut off at the bottom, so the view fades it out.
    var fadesAtBottom: Bool { text?.isCutOff == true }
    /// The picture still to decode: image data, and the size to decode it for.
    private(set) var pendingImage: Data?

    init(_ clipping: Clipping, query: String, limits: Limits) {
        clippingID = clipping.id
        textScale = limits.textScale
        let footerFont = NSFont.preferredFont(forTextStyle: .caption1)
        footerHeight = Self.lineHeight(of: NSFont.systemFont(ofSize: (footerFont.pointSize * limits.textScale).rounded()))

        switch clipping.kind {
        case .text:
            buildText(of: clipping, query: query, limits: limits)
        case .image:
            buildImage(of: clipping, limits: limits)
        case .fileURL:
            buildFiles(of: clipping, limits: limits)
        }
    }

    // MARK: Text

    private func buildText(of clipping: Clipping, query: String, limits: Limits) {
        let scale = limits.textScale
        let body = PreviewText.body(of: clipping.text ?? "")
        guard !body.isEmpty else {
            placeholder = "Empty clipping"
            size = CGSize(width: 200 * Self.widthFactor(scale), height: Self.chrome(parts: 1, content: Self.lineHeight(of: NSFont.systemFont(ofSize: 13 * scale))))
            return
        }

        swatch = clipping.color
        let isCode = swatch != nil || PreviewText.looksLikeCode(body.text)
        let font = isCode
            ? NSFont.monospacedSystemFont(ofSize: (NSFont.preferredFont(forTextStyle: .callout).pointSize * scale).rounded(), weight: .regular)
            : NSFont.systemFont(ofSize: (NSFont.preferredFont(forTextStyle: .body).pointSize * scale).rounded())

        let wanted = (swatch != nil ? 260 : (isCode ? 540 : 420)) * Self.widthFactor(scale)
        let panelWidth = min(wanted.rounded(), limits.maxWidth)
        let swatchBlock = swatch == nil ? 0 : Self.swatchHeight + Self.spacing
        // The footer's room is always held back: whether it's needed depends on whether
        // the text fits, which depends on that room.
        let reserved = footerHeight + Self.spacing
        let availableHeight = limits.maxHeight - 2 * Self.padding - swatchBlock - reserved
        let laid = PreviewText.layout(body, font: font, isCode: isCode, width: panelWidth - 2 * Self.padding,
                                      maxHeight: max(availableHeight, font.pointSize * 2), query: query)
        text = laid

        // Narrow to the text itself, so a short clipping doesn't float in a wide card.
        let minWidth = (swatch != nil ? 220 : 160) * Self.widthFactor(scale)
        let width = min(panelWidth, max((laid.usedSize.width + 2 * Self.padding + 2).rounded(.up), minWidth.rounded()))

        let chars = body.characterCount
        let showsFooter = laid.isCutOff || body.lineCount > 1 || chars > 120
        var parts = 1
        var content = laid.usedSize.height
        if swatch != nil { parts += 1; content += Self.swatchHeight }
        if showsFooter {
            parts += 1
            content += footerHeight
            footer = Self.textFooter(lines: body.lineCount, characters: chars, shownLines: laid.shownLines, isCutOff: laid.isCutOff)
        }
        size = CGSize(width: width, height: Self.chrome(parts: parts, content: content))
        // The container is exactly as wide as the view that draws it. The lines already
        // fit that width, so wrapping, and the height, don't change.
        laid.container.containerSize = NSSize(width: width - 2 * Self.padding, height: laid.container.containerSize.height)
    }

    private static func textFooter(lines: Int, characters: Int, shownLines: Int, isCutOff: Bool) -> String {
        let chars = characters == 1 ? "1 character" : "\(characters.formatted()) characters"
        if isCutOff {
            return lines > shownLines && shownLines > 0
                ? "First \(shownLines.formatted()) of \(lines.formatted()) lines \u{00B7} \(chars)"
                : "Cut off \u{00B7} \(chars)"
        }
        return lines > 1 ? "\(lines.formatted()) lines \u{00B7} \(chars)" : chars
    }

    // MARK: Images

    private func buildImage(of clipping: Clipping, limits: Limits) {
        guard let data = clipping.imageData, let pixels = Self.pixelSize(of: data) else {
            placeholder = "Image unavailable"
            size = CGSize(width: 200 * Self.widthFactor(limits.textScale), height: Self.chrome(parts: 1, content: 20))
            return
        }
        let reserved = footerHeight + Self.spacing
        let box = CGSize(
            width: min(520 * Self.widthFactor(limits.textScale), limits.maxWidth) - 2 * Self.padding,
            height: limits.maxHeight - 2 * Self.padding - reserved
        )
        let shown = Self.fit(pixels: pixels, backingScale: limits.backingScale, in: box)
        imageSize = shown
        image = ClippingThumbnails.image(for: clipping)
        pendingImage = data
        footer = clipping.text
        let hasFooter = footer != nil
        size = CGSize(
            width: max(shown.width + 2 * Self.padding, 140),
            height: Self.chrome(parts: hasFooter ? 2 : 1, content: shown.height + (hasFooter ? footerHeight : 0))
        )
    }

    /// The display size of a picture: its natural size on this screen, shrunk to fit, and
    /// enlarged (up to twice) only when it would otherwise be a speck.
    private static func fit(pixels: CGSize, backingScale: CGFloat, in box: CGSize) -> CGSize {
        let natural = CGSize(width: pixels.width / backingScale, height: pixels.height / backingScale)
        var factor = min(box.width / natural.width, box.height / natural.height)
        if factor > 1 { factor = min(factor, natural.width < 160 ? 2 : 1) }
        return CGSize(width: (natural.width * factor).rounded(), height: (natural.height * factor).rounded())
    }

    // MARK: Files

    private func buildFiles(of clipping: Clipping, limits: Limits) {
        let scale = limits.textScale
        let urls = clipping.fileURLs ?? []
        fileRowHeight = (38 * max(1, scale * 0.85)).rounded()
        let width = min((360 * Self.widthFactor(scale)).rounded(), limits.maxWidth)

        var parts = 0
        var content: CGFloat = 0
        let reserved = footerHeight + Self.spacing

        // A file's picture (a screenshot, a document's first page), when one was kept.
        if let data = clipping.imageData, let pixels = Self.pixelSize(of: data) {
            let box = CGSize(width: width - 2 * Self.padding, height: min(220, limits.maxHeight * 0.4))
            let shown = Self.fit(pixels: pixels, backingScale: limits.backingScale, in: box)
            imageSize = shown
            image = ClippingThumbnails.image(for: clipping)
            pendingImage = data
            parts += 1
            content += shown.height
        }

        let room = limits.maxHeight - 2 * Self.padding - reserved - content - (parts > 0 ? Self.spacing : 0)
        let rowCount = max(1, min(urls.count, Int(room / fileRowHeight), 14))
        files = urls.prefix(rowCount).map { url in
            File(
                url: url,
                name: url.lastPathComponent,
                directory: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                icon: NSWorkspace.shared.icon(forFile: url.path),
                exists: FileManager.default.fileExists(atPath: url.path)
            )
        }
        parts += 1
        content += fileRowHeight * CGFloat(files.count)

        let hidden = urls.count - files.count
        footer = urls.count == 1 ? "1 file" : (hidden > 0 ? "\(urls.count) files \u{00B7} \(hidden) not shown" : "\(urls.count) files")
        parts += 1
        content += footerHeight
        size = CGSize(width: width, height: Self.chrome(parts: parts, content: content))
    }

    // MARK: Helpers

    /// Text Size widens the card along with the popover (see `MenuBarContentView.popoverSize`).
    private static func widthFactor(_ textScale: CGFloat) -> CGFloat {
        1 + (textScale - 1) * 0.36
    }

    /// Window height for stacked parts: their heights, the gaps between, and the padding.
    private static func chrome(parts: Int, content: CGFloat) -> CGFloat {
        (content + CGFloat(max(parts - 1, 0)) * spacing + 2 * padding).rounded(.up)
    }

    static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// Pixel dimensions from the image's header alone, without decoding it.
    nonisolated static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        // Rotated by EXIF: 5 through 8 swap the axes.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    /// Decodes an image straight to preview size, off the main thread. Even a huge
    /// screenshot becomes a ~1800 px bitmap without ever being held at full size.
    nonisolated static func downsampled(_ data: Data, maxPixel: Int = 1800) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary)
    }

    /// Decoded previews, so hovering back over a picture is instant.
    private static let decoded = NSCache<NSUUID, NSImage>()

    /// The full-size picture for this preview, from the cache or decoded in the background.
    func loadImage() async {
        guard let data = pendingImage else { return }
        pendingImage = nil
        let key = clippingID as NSUUID
        if let cached = Self.decoded.object(forKey: key) {
            image = cached
            return
        }
        let cgImage = await Task.detached(priority: .userInitiated) { Self.downsampled(data) }.value
        guard !Task.isCancelled, let cgImage else { return }
        let decoded = NSImage(cgImage: cgImage, size: imageSize ?? .zero)
        Self.decoded.setObject(decoded, forKey: key, cost: cgImage.width * cgImage.height * 4)
        image = decoded
    }
}

// MARK: - Text layout

/// A clipping's text laid out with TextKit in a container exactly as tall as the preview
/// can be. Only the lines that fit are ever laid out, so a megabyte of text costs no more
/// than a paragraph — and what fits, and what doesn't, is known before anything is drawn.
struct PreviewText {
    /// The text kept alive for the view that draws it.
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let container: NSTextContainer
    /// Size of the lines that fit.
    let usedSize: CGSize
    /// Whole lines (as in the original text, not wrapped) that are visible, or partly so.
    let shownLines: Int
    /// There is more text than fits.
    let isCutOff: Bool

    /// More than a screen holds is never read from the string, however long it is.
    private static let characterLimit = 30_000

    /// The text between its leading and trailing blank lines, with what's needed to
    /// describe it. Indentation on the first line is kept: it matters in code.
    struct Body {
        let text: Substring
        /// The text was longer than `characterLimit`, and has been cut there.
        let isClipped: Bool
        let lineCount: Int
        let characterCount: Int
        var isEmpty: Bool { text.isEmpty }
    }

    static func body(of string: String) -> Body {
        var start = string.startIndex
        // Leading blank lines only.
        while let newline = string[start...].firstIndex(where: \.isNewline),
              string[start..<newline].allSatisfy(\.isWhitespace) {
            start = string.index(after: newline)
        }
        var end = string.endIndex
        while end > start, string[string.index(before: end)].isWhitespace {
            end = string.index(before: end)
        }
        let whole = string[start..<end]
        guard !whole.isEmpty else { return Body(text: whole, isClipped: false, lineCount: 0, characterCount: 0) }

        let head = whole.prefix(characterLimit)
        // Counting characters properly is slow for enormous text; UTF-16 is close enough there.
        let characters = whole.utf8.count < 500_000 ? whole.count : whole.utf16.count
        return Body(text: head, isClipped: head.endIndex != whole.endIndex, lineCount: lineCount(of: whole), characterCount: characters)
    }

    private static func lineCount(of text: Substring) -> Int {
        let counted = text.utf8.withContiguousStorageIfAvailable { bytes in
            bytes.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        }
        return counted ?? text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// Source code, shell commands, URLs and the like read better in a monospaced font:
    /// mostly indented or punctuated lines, or a single unbroken token.
    static func looksLikeCode(_ text: Substring) -> Bool {
        let lines = text.prefix(3000).split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard !lines.isEmpty else { return false }
        if lines.count == 1 {
            let line = lines[0]
            return (!line.contains(where: \.isWhitespace) && line.count > 12) || isCodeLine(line)
        }
        return Double(lines.filter(isCodeLine).count) / Double(lines.count) >= 0.4
    }

    private static let codeMarks = ["{", "}", ";", "=>", "->", "</", "/>", "==", "!=", "&&", "||", "::", "#include", "$ "]

    private static func isCodeLine(_ line: Substring) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t") || codeMarks.contains { line.contains($0) }
    }

    static func layout(_ body: Body, font: NSFont, isCode: Bool, width: CGFloat, maxHeight: CGFloat, query: String) -> PreviewText {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        if isCode {
            // Four columns per tab, as most editors show it.
            style.defaultTabInterval = font.maximumAdvancement.width * 4
            style.tabStops = []
        }
        let string = String(body.text)
        let storage = NSTextStorage(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ])
        highlight(query, in: storage)

        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: maxHeight))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        // Lays out only as much as the container holds.
        let glyphs = layoutManager.glyphRange(for: container)
        let used = layoutManager.usedRect(for: container)
        let visible = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        let ns = string as NSString
        var shown = visible.length > 0 ? 1 : 0
        var index = 0
        while index < visible.length {
            if ns.character(at: index) == 0x0A { shown += 1 }
            index += 1
        }
        // A newline right where the text stops belongs to the line above.
        if visible.length > 0, ns.character(at: visible.length - 1) == 0x0A { shown -= 1 }

        return PreviewText(
            storage: storage,
            layoutManager: layoutManager,
            container: container,
            usedSize: CGSize(width: ceil(used.width), height: ceil(used.height)),
            shownLines: shown,
            isCutOff: body.isClipped || NSMaxRange(visible) < ns.length
        )
    }

    /// Search matches get the same treatment as in the list.
    private static func highlight(_ query: String, in storage: NSTextStorage) {
        guard !query.isEmpty else { return }
        let underline = NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
        let string = storage.string as NSString
        var search = NSRange(location: 0, length: string.length)
        while search.length > 0 {
            let found = string.range(of: query, options: .caseInsensitive, range: search)
            guard found.location != NSNotFound, found.length > 0 else { break }
            storage.addAttributes([.backgroundColor: NSColor.findHighlightColor, .foregroundColor: NSColor.black], range: found)
            if underline { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: found) }
            let next = found.location + found.length
            search = NSRange(location: next, length: string.length - next)
        }
    }
}

/// Draws a `PreviewText`. It never takes the mouse: the preview window is click-through.
private struct PreviewTextView: NSViewRepresentable {
    let text: PreviewText

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: NSRect(origin: .zero, size: text.usedSize), textContainer: text.container)
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = false
        view.textContainerInset = .zero
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {}
}

// MARK: - View

/// The preview's content on a glass card. The window is exactly `preview.size`, so the
/// card needs no layout negotiation with it.
struct ClippingPreviewView: View {
    let preview: ClippingPreview

    var body: some View {
        VStack(alignment: .leading, spacing: ClippingPreview.spacing) {
            if let swatch = preview.swatch {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: swatch))
                    .frame(height: ClippingPreview.swatchHeight)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                    }
            }
            if let size = preview.imageSize {
                picture(size: size)
            }
            if let text = preview.text {
                PreviewTextView(text: text)
                    .id(preview.clippingID)
                    .frame(width: preview.size.width - 2 * ClippingPreview.padding, height: text.usedSize.height, alignment: .topLeading)
                    .mask { fade }
            }
            if let placeholder = preview.placeholder {
                Text(placeholder)
                    .foregroundStyle(.secondary)
            }
            if !preview.files.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.files) { file in
                        FileRow(file: file)
                            .frame(height: preview.fileRowHeight)
                    }
                }
            }
            if let footer = preview.footer {
                Text(footer)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: preview.footerHeight)
            }
        }
        .padding(ClippingPreview.padding)
        .frame(width: preview.size.width, height: preview.size.height, alignment: .topLeading)
        .environment(\.textScale, preview.textScale)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ClippingPreview.cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func picture(size: CGSize) -> some View {
        Group {
            if let image = preview.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIgnoresInvertColors()
    }

    /// Text that continues fades out at the bottom rather than ending mid-air.
    private var fade: some View {
        VStack(spacing: 0) {
            Rectangle()
            if preview.fadesAtBottom {
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
        }
    }
}

private struct FileRow: View {
    let file: ClippingPreview.File

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: file.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .opacity(file.exists ? 1 : 0.4)
                .accessibilityIgnoresInvertColors()
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .scaledFont(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.exists ? file.directory : "No longer at this location")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
    }
}
