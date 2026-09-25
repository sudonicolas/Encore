import SwiftUI
import AppKit

/// Full content of a single clipping — the text in full, the full-size image, or the
/// list of files — with a metadata bar pinned to the bottom. Text clippings also show
/// their Apple Intelligence title, any Apple Intelligence result, and online lookups.
/// Pure content: hosts decide how to frame it (a floating glass header in the popover,
/// native toolbar in History) and where the Apple Intelligence menu goes.
struct ClippingDetailView: View {
    let clipping: Clipping
    /// Streams Apple Intelligence results; owned by the host, whose menu starts them.
    var runner: TextActionRunner? = nil
    /// The active search query, if any — matching text is highlighted inline.
    var searchQuery: String = ""
    /// The user's current text selection, if any; the host's copy button reads this to
    /// copy just the selection instead of the whole clipping.
    var selectedText: Binding<String?> = .constant(nil)
    /// The popover's header already names the source app and time, so it hides them here.
    var showsSourceAndDate = true

    @Environment(ClipboardStore.self) private var store

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A scroll-edge bar (not a divider + material strip): content blurs softly
        // beneath it as it scrolls, per the macOS 26+ scroll edge effect.
        .safeAreaBar(edge: .bottom) {
            metadata
        }
    }

    @ViewBuilder
    private var content: some View {
        switch clipping.kind {
        case .text:
            let text = clipping.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                Text("Empty clipping")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let runner, runner.isActive {
                        TextActionResultCard(runner: runner)
                            .motionSafeTransition(.move(edge: .top).combined(with: .opacity))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if store.generatesSmartTitles, let title = clipping.smartTitle {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                SmartTitleGlyph()
                                Text.highlighting(title, matching: searchQuery)
                                    .scaledFont(.headline)
                                    .textSelection(.enabled)
                            }
                            // "Title by Apple Intelligence, Flight confirmation email",
                            // as a heading VoiceOver can jump to.
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                        }
                        SelectableText(text: text, highlightQuery: searchQuery, selectedText: selectedText)
                    }
                    if store.offersOnlineLookups {
                        LookupsSection(text: text)
                            .id(text)
                    }
                }
                .animation(.snappy(duration: 0.25).motionSafe, value: runner?.isActive)
            }

        case .image:
            if let data = clipping.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.continuous(UIRadius.card))
                    .frame(maxWidth: .infinity)
                    .accessibilityIgnoresInvertColors()
                    .accessibilityLabel(clipping.accessibilityTitle(smartTitle: nil))
            } else {
                Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }

        case .fileURL:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(clipping.fileURLs ?? [], id: \.self) { url in
                    FileRow(url: url, searchQuery: searchQuery)
                }
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if showsSourceAndDate, let icon = ClippingThumbnails.appIcon(bundleID: clipping.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .accessibilityIgnoresInvertColors()
            }
            Text(metadataItems.joined(separator: " \u{00B7} "))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metadataItems.map(Optional.some).accessibilityJoined)
        .scaledFont(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var metadataItems: [String] {
        var items: [String] = []
        if showsSourceAndDate {
            if let app = clipping.sourceAppName { items.append(app) }
            items.append(clipping.createdAt.formatted(.dateTime.month().day().hour().minute()))
        }
        switch clipping.kind {
        case .text:
            let text = clipping.text ?? ""
            items.append(text.count == 1 ? "1 character" : "\(text.count.formatted()) characters")
            let lines = text.split(whereSeparator: \.isNewline).count
            if lines > 1 { items.append("\(lines.formatted()) lines") }
        case .image:
            if let label = clipping.text { items.append(label) }
        case .fileURL:
            let count = clipping.fileURLs?.count ?? 0
            items.append(count == 1 ? "1 file" : "\(count) files")
        }
        return items
    }
}

/// One file reference: Finder icon, name, containing folder, and Show in Finder — or a
/// note when the file has since been moved or deleted.
private struct FileRow: View {
    let url: URL
    let searchQuery: String

    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(exists ? 1 : 0.4)
                .accessibilityIgnoresInvertColors()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text.highlighting(url.lastPathComponent, matching: searchQuery)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Not just the dimmed icon: the missing state is always written out.
                Text(exists ? (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath : "No longer at this location")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if exists {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Show in Finder")
                .accessibilityInputLabels(["Show in Finder", "Reveal"])
            }
        }
    }
}
