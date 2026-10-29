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
    /// Whether a text clipping's text can be changed here. Off for Recently Deleted.
    var isEditable = true

    /// Past this many bytes the metadata bar stops counting characters and lines exactly
    /// (see `metadataItems`).
    private static let exactCountLimit = 500_000

    @Environment(ClipboardStore.self) private var store
    @State private var showsVersions = false
    /// The text the lookups work on: it trails what's typed, so a lookup isn't sent for
    /// every keystroke.
    @State private var lookupText: String?

    var body: some View {
        ScrollView(.vertical) {
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
        // Whatever ends the viewing — Back, another clipping, the window closing — also
        // ends an editing session, so its version is settled right away.
        .onDisappear { store.finishEditing(clipping.id) }
    }

    @ViewBuilder
    private var content: some View {
        switch clipping.kind {
        case .text:
            let raw = clipping.text ?? ""
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && !isEditable {
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
                        ClippingTextEditor(
                            text: raw,
                            isEditable: isEditable,
                            highlightQuery: searchQuery,
                            selectedText: selectedText,
                            onEdit: { store.editText(of: clipping.id, to: $0) },
                            onEndEditing: { store.finishEditing(clipping.id) }
                        )
                        .overlay(alignment: .topLeading) {
                            if raw.isEmpty {
                                Text("Empty clipping")
                                    .foregroundStyle(.secondary)
                                    .allowsHitTesting(false)
                            }
                        }
                        .help(isEditable ? "Click to edit. \u{2318}Z undoes and \u{21e7}\u{2318}Z redoes." : "")
                    }
                    if store.offersOnlineLookups, !text.isEmpty {
                        let lookedUp = lookupText ?? text
                        LookupsSection(text: lookedUp)
                            .id(lookedUp)
                    }
                }
                .animation(.snappy(duration: 0.25).motionSafe, value: runner?.isActive)
                .task(id: text) {
                    guard (try? await Task.sleep(for: .seconds(0.8))) != nil else { return }
                    lookupText = text
                }
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
                if let data = clipping.imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.continuous(UIRadius.card))
                        .frame(maxWidth: .infinity)
                        .accessibilityIgnoresInvertColors()
                        .accessibilityHidden(true)
                }
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
            if let versions = clipping.versions, !versions.isEmpty {
                Spacer(minLength: 8)
                Button {
                    showsVersions = true
                } label: {
                    Label(versions.count == 1 ? "1 version" : "\(versions.count) versions",
                          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Version History: see and restore earlier versions of this text")
                .accessibilityLabel("Version History")
                .accessibilityValue(versions.count == 1 ? "1 earlier version" : "\(versions.count) earlier versions")
                .accessibilityInputLabels(["Version History", "Versions", "History"])
                .popover(isPresented: $showsVersions, arrowEdge: .top) {
                    VersionHistoryView(clipping: clipping, canRestore: isEditable) {
                        showsVersions = false
                    }
                }
            }
        }
        // .contain, not .ignore: the Version History button sits in this bar now, and
        // ignoring the children would take it away from VoiceOver and Voice Control
        // altogether. The text describes itself just above instead.
        .accessibilityElement(children: .contain)
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
            // Counting graphemes and splitting lines both walk the whole string, and this
            // bar is rebuilt on every keystroke now that the text is editable here. Past
            // the size where the preview also stops working character by character, the
            // byte count stands in.
            if text.utf8.count > Self.exactCountLimit {
                items.append("\(text.utf8.count.formatted()) bytes")
            } else {
                items.append(text.count == 1 ? "1 character" : "\(text.count.formatted()) characters")
                let lines = text.split(whereSeparator: \.isNewline).count
                if lines > 1 { items.append("\(lines.formatted()) lines") }
            }
        case .image:
            if let label = clipping.text { items.append(label) }
        case .fileURL:
            let count = clipping.fileURLs?.count ?? 0
            items.append(count == 1 ? "1 file" : "\(count) files")
        }
        return items
    }
}

/// One file reference: Finder icon, name, full path (a link that reveals the file in
/// Finder), and a matching icon button — or a note when the file has since been moved or
/// deleted.
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
                if exists {
                    // The full path, spelled out rather than abbreviated — clicking it
                    // reveals the file in Finder, same as the trailing button.
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Text(url.path)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)
                } else {
                    Text("No longer at this location")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Show in Finder") {
                if exists { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }

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
