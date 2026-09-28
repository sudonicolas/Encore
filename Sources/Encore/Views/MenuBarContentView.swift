import SwiftUI
import AppKit

/// Content of the menu bar popover (left click). Three pages share the popover: the
/// clipping list, a clipping's full detail, and Recently Deleted.
///
/// Layout follows the macOS 26+ popover idiom: content scrolls edge to edge under
/// floating glass bars — search on top, actions at the bottom — with a soft scroll-edge
/// effect instead of dividers.
///
/// Keyboard: typing searches; ↑ and ↓ move a highlight through the list, Return copies
/// the highlighted clipping, and ⌘↓ shows its details (Escape or ⌘↑ comes back). On the
/// list itself, Option+1 through Option+0 copies one of the first ten rows outright —
/// the same digits shown on those rows — and Escape clears the search, then closes the
/// popover. ⇧⌘V (see GlobalHotKeyManager) opens and closes the popover from any app.
struct MenuBarContentView: View {
    @Environment(ClipboardStore.self) private var store
    @State private var searchText = ""
    @State private var page: Page = .list
    @State private var selectedText: String?
    @State private var runner = TextActionRunner()
    /// The row chosen with ↑ and ↓.
    @State private var highlightedID: UUID?
    /// The row showing its "Copied" confirmation.
    @State private var copiedID: UUID?
    @State private var copiedTask: Task<Void, Never>?
    @State private var searchAnnouncementTask: Task<Void, Never>?
    @State private var isShowingMoreMenu = false
    @FocusState private var isSearchFocused: Bool

    private let navigator = AppNavigator.shared

    enum Page: Equatable {
        case list
        case detail(UUID)
        case recentlyDeleted
    }

    private var filtered: [Clipping] {
        guard !searchText.isEmpty else { return store.clippings }
        return store.clippings.filter {
            $0.searchableText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var pinned: [Clipping] {
        filtered.filter(\.isPinned)
    }

    private var unpinned: [Clipping] {
        filtered.filter { !$0.isPinned }
    }

    private var recent: [Clipping] {
        Array(unpinned.prefix(store.maxDisplayedCount))
    }

    /// Every row on the list page, top to bottom: what ↑ and ↓ move through.
    private var visibleClippings: [Clipping] {
        pinned + recent
    }

    private var highlighted: Clipping? {
        guard let highlightedID else { return nil }
        return visibleClippings.first { $0.id == highlightedID }
    }

    /// The popover grows a little with Text Size, so larger text still fits a useful
    /// amount on screen: 360 × 480 at 100%, about 490 × 625 at 200%.
    private var popoverSize: CGSize {
        let extra = store.textSize.scale - 1
        return CGSize(width: (360 * (1 + extra * 0.36)).rounded(), height: (480 * (1 + extra * 0.3)).rounded())
    }

    var body: some View {
        ZStack {
            switch page {
            case .list:
                listPage
                    .motionSafeTransition(.move(edge: .leading).combined(with: .opacity))
            case .detail(let id):
                if let clipping = store.clippings.first(where: { $0.id == id }) {
                    detailPage(for: clipping)
                        .motionSafeTransition(.move(edge: .trailing).combined(with: .opacity))
                }
            case .recentlyDeleted:
                RecentlyDeletedPage(onBack: { go(to: .list) })
                    .motionSafeTransition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        // At the root, not on the list page: deleting from the detail page returns to
        // the list, and the toast must survive that page swap.
        .trashUndoToast(bottomPadding: 62)
        .scaledFont(.body)
        .environment(\.textScale, store.textSize.scale)
        .onChange(of: store.clippings) { _, clippings in
            if case .detail(let id) = page, !clippings.contains(where: { $0.id == id }) {
                go(to: .list)
            }
            if highlighted == nil { highlightedID = nil }
        }
        .onChange(of: searchText) { _, newValue in
            // While searching, the top match is ready to copy with Return.
            highlightedID = newValue.isEmpty ? nil : visibleClippings.first?.id
            announceSearchResults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPopoverWillShow)) { _ in
            // Every open starts fresh: list page, empty search, cursor in the field.
            page = .list
            searchText = ""
            selectedText = nil
            highlightedID = nil
            copiedID = nil
            runner.dismiss()
            isSearchFocused = true
        }
    }

    // MARK: - List page

    private var listPage: some View {
        // A ZStack, not a Group: a Group would apply the bars to each branch separately,
        // so a search with no results would swap in a new search field (dropping focus)
        // sized to the empty state rather than the popover.
        ZStack {
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) {
            VStack(spacing: 8) {
                searchField
                if store.isPasteboardAccessDenied {
                    accessDeniedBanner
                        .motionSafeTransition(.move(edge: .top).combined(with: .opacity))
                } else if !store.isRecordingEnabled {
                    pausedBanner
                        .motionSafeTransition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 6)
            .animation(.snappy(duration: 0.25).motionSafe, value: store.isRecordingEnabled)
            .animation(.snappy(duration: 0.25).motionSafe, value: store.isPasteboardAccessDenied)
        }
        .safeAreaBar(edge: .bottom) {
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel("Search Clippings")
                .help("Search clippings. Use \u{2191} and \u{2193} to choose one, Return to copy it, \u{2318}\u{2193} to show its details, and \u{2325}1 through \u{2325}0 to copy one of the first ten. Escape clears the search, then closes.")
                .onSubmit(copyHighlighted)
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in
                    press.modifiers.contains(.command) ? openHighlighted() : moveHighlight(by: 1)
                }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
                    press.modifiers.contains(.command) ? .ignored : moveHighlight(by: -1)
                }
                .onKeyPress(.escape) { handleEscape() }
                // Option+digit copies one of the first ten rows outright, matching the
                // number shown on each (see copyQuickSlot). Plain digits still type into
                // the search field: only bare Option, not Option+Command or the like,
                // triggers it, and .ignored below falls back to normal text insertion.
                .onKeyPress(keys: Self.quickCopyKeys, phases: .down) { press in
                    press.modifiers.contains(.option) ? copyQuickSlot(matching: press.key) : .ignored
                }
            if !searchText.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2).motionSafe) { searchText = "" }
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
                .accessibilityInputLabels(["Clear Search", "Clear"])
                .motionSafeTransition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        // A softly tinted capsule, not glass (glass search fields belong to toolbars) and
        // not an opaque system fill (too bright against the popover's own background).
        .background(.primary.opacity(0.06), in: .capsule)
        .increasedContrastBorder(Capsule())
        .animation(.snappy(duration: 0.2).motionSafe, value: searchText.isEmpty)
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(Color.warningText)
                .accessibilityHidden(true)
            Text("Recording is paused")
                .scaledFont(.callout)
            Spacer()
            Button("Resume") { setRecording(true) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel("Resume Recording")
                .accessibilityInputLabels(["Resume", "Resume Recording"])
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 34)
        .background(.orange.opacity(0.12), in: .capsule)
        .increasedContrastBorder(Capsule())
        .accessibilityElement(children: .contain)
    }

    /// Shown when the user has set Encore to "Deny" in Privacy & Security → Paste from
    /// Other Apps: nothing can be recorded until they allow it.
    private var accessDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.slash.fill")
                .foregroundStyle(Color.errorText)
                .accessibilityHidden(true)
            Text("Clipboard access is turned off")
                .scaledFont(.callout)
                .lineLimit(2)
            Spacer()
            Button("Allow\u{2026}") { ClipboardMonitor.openPasteboardPrivacySettings() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Allow \(AppInfo.name) in Privacy & Security \u{2192} Paste from Other Apps")
                .accessibilityLabel("Allow Clipboard Access")
                .accessibilityInputLabels(["Allow", "Allow Clipboard Access"])
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 34)
        .background(.red.opacity(0.12), in: .capsule)
        .increasedContrastBorder(Capsule())
        .accessibilityElement(children: .contain)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !pinned.isEmpty {
                        sectionHeader("Pinned")
                        rows(pinned)
                    }
                    if !recent.isEmpty {
                        sectionHeader("Recent")
                        // Quick-copy digits number every row in one run, pinned then
                        // recent, matching visibleClippings — so "1" is always the very
                        // top row and "0" the tenth, regardless of which section they fall in.
                        rows(recent, startingAt: pinned.count)
                    }
                    if unpinned.count > recent.count {
                        showAllButton(hiddenCount: unpinned.count - recent.count)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
                .animation(.snappy(duration: 0.25).motionSafe, value: store.clippings)
            }
            .onChange(of: highlightedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15).motionSafe) { proxy.scrollTo(id) }
            }
            // VoiceOver rotors (VO-U) jump straight to pinned clippings, images or files.
            .accessibilityRotor("Pinned Clippings", entries: pinned, entryID: \.id, entryLabel: \.previewTitle)
            .accessibilityRotor("Images", entries: filtered.filter { $0.kind == .image }, entryID: \.id, entryLabel: \.previewTitle)
            .accessibilityRotor("Files", entries: filtered.filter { $0.kind == .fileURL }, entryID: \.id, entryLabel: \.previewTitle)
        }
    }

    private func rows(_ clippings: [Clipping], startingAt offset: Int = 0) -> some View {
        ForEach(Array(clippings.enumerated()), id: \.element.id) { index, clipping in
            ClippingRowView(
                clipping: clipping,
                searchQuery: searchText,
                isHighlighted: clipping.id == highlightedID,
                isCopied: clipping.id == copiedID,
                quickCopyKey: Self.quickCopyLabel(forSlot: offset + index),
                onCopy: copy,
                onOpen: openDetail
            )
            .id(clipping.id)
            .motionSafeTransition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .scaledFont(.subheadline, weight: .semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// The popover only shows the most recent few; say so, and offer the rest.
    private func showAllButton(hiddenCount: Int) -> some View {
        Button {
            navigator.showHistory(search: searchText)
        } label: {
            HStack {
                Text(hiddenCount == 1 ? "1 more in History" : "\(hiddenCount) more in History")
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .accessibilityHidden(true)
            }
            .scaledFont(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(.row)
        }
        .buttonStyle(.plain)
        .help("Open History")
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("No Clippings Yet", systemImage: "doc.on.clipboard")
            } description: {
                Text(store.isRecordingEnabled
                     ? "Text, images and files you copy will appear here."
                     : "Resume recording to start collecting clippings.")
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    /// Floating glass action bar. Recently Deleted lives here (not just in History) so
    /// recovering something is one click from the menu bar.
    private var footer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    navigator.showHistory()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .frame(width: 32, height: 32)
                .help("Open History")
                .accessibilityInputLabels(["History", "Open History", "Show History"])

                Button {
                    go(to: .recentlyDeleted)
                } label: {
                    if store.deletedClippings.isEmpty {
                        Label("Recently Deleted", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    } else {
                        Label("\(store.deletedClippings.count)", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                    }
                }
                .frame(minWidth: 32, minHeight: 32)
                .buttonBorderShape(store.deletedClippings.isEmpty ? .circle : .capsule)
                .help("Recently Deleted")
                .accessibilityLabel("Recently Deleted")
                .accessibilityValue(store.deletedClippings.count == 1 ? "1 clipping" : "\(store.deletedClippings.count) clippings")
                .accessibilityInputLabels(["Recently Deleted", "Trash", "Deleted"])

                Spacer()

                Button {
                    setRecording(!store.isRecordingEnabled)
                } label: {
                    Label(
                        store.isRecordingEnabled ? "Pause Recording" : "Resume Recording",
                        systemImage: store.isRecordingEnabled ? "pause.fill" : "record.circle"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 32, height: 32)
                .help(store.isRecordingEnabled ? "Pause Recording" : "Resume Recording")
                .accessibilityInputLabels(store.isRecordingEnabled
                    ? ["Pause", "Pause Recording"]
                    : ["Resume", "Resume Recording", "Record"])

                Button {
                    navigator.showSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .frame(width: 32, height: 32)
                .help("Settings")
                .accessibilityInputLabels(["Settings", "Preferences"])

                // A plain `Button` — like every sibling here — rather than a `Menu`, whose
                // hit area on macOS depends on its `menuStyle` and doesn't reliably match
                // the glass circle. The dropdown itself is a `.popover` of plain rows,
                // built and styled entirely in SwiftUI.
                Button {
                    isShowingMoreMenu = true
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .frame(width: 32, height: 32)
                .help("More")
                .accessibilityInputLabels(["More", "More Options"])
                .popover(isPresented: $isShowingMoreMenu, arrowEdge: .bottom) {
                    moreMenu
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .labelStyle(.iconOnly)
            .controlSize(.large)
        }
        .padding(10)
    }

    /// Content of the "More" popover: styled to read as a menu without being one.
    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            MoreMenuRow(
                title: "Clear Unpinned Clippings",
                isDisabled: !store.clippings.contains { !$0.isPinned }
            ) {
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.clearUnpinned() }
                isShowingMoreMenu = false
            }
            MoreMenuRow(title: "Clear All Clippings", isDisabled: store.clippings.isEmpty) {
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.clearAll() }
                isShowingMoreMenu = false
            }
            Divider().padding(.vertical, 4)
            MoreMenuRow(title: "Quit \(AppInfo.name)") {
                NSApp.terminate(nil)
            }
        }
        .padding(6)
        .frame(minWidth: 220)
    }

    // MARK: - Detail page

    private func detailPage(for clipping: Clipping) -> some View {
        ClippingDetailView(
            clipping: clipping,
            runner: runner,
            searchQuery: searchText,
            selectedText: $selectedText,
            showsSourceAndDate: false
        )
        .safeAreaBar(edge: .top) {
            DetailHeader(clipping: clipping, runner: runner, selectedText: selectedText) {
                go(to: .list)
            }
        }
    }

    // MARK: - Keyboard

    /// The digit keys Option+quick-copy watches for: 1 through 9, then 0 for the tenth
    /// row — the same order shown on the rows themselves.
    private static let quickCopyKeys = Set("1234567890".map { KeyEquivalent($0) })

    /// The badge shown on a row at this position in `visibleClippings` (0-based): "1"
    /// through "9", then "0" for the tenth row; nothing beyond that.
    private static func quickCopyLabel(forSlot slot: Int) -> String? {
        guard (0..<10).contains(slot) else { return nil }
        return slot == 9 ? "0" : "\(slot + 1)"
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        let items = visibleClippings
        guard !items.isEmpty else { return .ignored }
        let next: Int
        if let current = highlightedID.flatMap({ id in items.firstIndex { $0.id == id } }) {
            next = min(max(current + offset, 0), items.count - 1)
        } else if offset > 0 {
            next = 0
        } else {
            return .ignored
        }
        highlightedID = items[next].id
        // VoiceOver stays in the search field, so say which clipping is now chosen, as
        // Spotlight does.
        let clipping = items[next]
        AssistiveTech.announce(clipping.accessibilityTitle(
            smartTitle: store.generatesSmartTitles ? clipping.smartTitle : nil
        ))
        return .handled
    }

    private func copyHighlighted() {
        guard let highlighted else { return }
        copy(highlighted)
    }

    private func openHighlighted() -> KeyPress.Result {
        guard let highlighted else { return .ignored }
        openDetail(highlighted.id)
        return .handled
    }

    /// Copies the row whose badge matches the digit that was just pressed with Option.
    private func copyQuickSlot(matching key: KeyEquivalent) -> KeyPress.Result {
        guard let typed = key.character.wholeNumberValue else { return .ignored }
        let slot = typed == 0 ? 9 : typed - 1
        guard visibleClippings.indices.contains(slot) else { return .ignored }
        copy(visibleClippings[slot])
        return .handled
    }

    /// Spotlight-style: an active search clears first, and only an already-empty search
    /// closes the popover outright, so clearing a typo never also dismisses the window.
    private func handleEscape() -> KeyPress.Result {
        if searchText.isEmpty {
            navigator.closePopover()
        } else {
            withAnimation(.snappy(duration: 0.2).motionSafe) { searchText = "" }
        }
        return .handled
    }

    /// After typing pauses, tells VoiceOver how many clippings match — the result list
    /// changes silently otherwise.
    private func announceSearchResults() {
        searchAnnouncementTask?.cancel()
        guard !searchText.isEmpty, AssistiveTech.isRunning else { return }
        searchAnnouncementTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            let count = filtered.count
            AssistiveTech.announce(
                count == 0 ? "No results" : (count == 1 ? "1 clipping" : "\(count) clippings"),
                priority: .medium
            )
        }
    }

    // MARK: - Actions

    private func copy(_ clipping: Clipping) {
        clipping.writeToPasteboard()
        ClipboardMonitor.shared.resyncChangeCount()
        AssistiveTech.announce("Copied")
        copiedTask?.cancel()
        withAnimation(.snappy(duration: 0.2).motionSafe) { copiedID = clipping.id }
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2).motionSafe) { copiedID = nil }
        }
    }

    private func setRecording(_ isOn: Bool) {
        store.isRecordingEnabled = isOn
        AssistiveTech.announce(isOn ? "Recording resumed" : "Recording paused")
    }

    // MARK: - Navigation

    private func openDetail(_ id: UUID) {
        go(to: .detail(id))
    }

    private func go(to newPage: Page) {
        selectedText = nil
        runner.dismiss()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86).motionSafe) {
            page = newPage
        }
        if newPage == .list { isSearchFocused = true }
    }
}

/// One row of the "More" popover: full-width tappable, with a hover highlight standing
/// in for the native menu's selection color.
private struct MoreMenuRow: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .foregroundStyle(isDisabled ? .secondary : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isHovering && !isDisabled ? Color.primary.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }
}

/// The detail page's floating header: Back, what the clipping is, and its actions. When
/// it appears, VoiceOver moves to the clipping's name, so the page change is heard.
private struct DetailHeader: View {
    let clipping: Clipping
    let runner: TextActionRunner
    let selectedText: String?
    var onBack: () -> Void

    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .keyboardShortcut(.cancelAction)
            .help("Back")
            .accessibilityInputLabels(["Back", "Go Back"])
            // ⌘↑ also goes back, pairing with ⌘↓ in the list (as in Finder).
            .background {
                Button("Back", action: onBack)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
            }

            ClippingThumbnail(clipping: clipping, size: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(clipping.sourceAppName ?? clipping.kindTitle)
                    .scaledFont(.headline)
                    .lineLimit(1)
                Text(clipping.createdAt, format: .dateTime.month().day().hour().minute())
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($isTitleFocused)

            Spacer(minLength: 4)

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    IntelligenceMenu(clipping: clipping, runner: runner)
                        .menuStyle(.button)
                    ClippingCopyButton(clipping: clipping, textOverride: selectedText)
                    ClippingPinButton(clipping: clipping)
                    ClippingDeleteButton(clipping: clipping, onDeleted: onBack)
                }
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .labelStyle(.iconOnly)
        .controlSize(.large)
        .padding(10)
        .task {
            // After the page transition, so VoiceOver lands on the settled view.
            try? await Task.sleep(for: .milliseconds(350))
            isTitleFocused = true
        }
    }
}
