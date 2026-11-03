import SwiftUI
import AppKit

/// The History window: a three-column split view in the Mail/Notes mould — a sidebar of
/// sections (including Recently Deleted), the clipping list, and the selected clipping.
///
/// Everything is native chrome so it picks up the macOS 26+ design for free: the
/// floating glass sidebar, the toolbar search field, concentric row selection, grouped
/// glass toolbar buttons, and scroll-edge effects.
struct HistoryWindowView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.undoManager) private var undoManager
    @ObservedObject private var navigator = AppNavigator.shared

    @State private var selection = Set<UUID>()
    @State private var showingClearAllConfirmation = false
    @State private var showingEmptyConfirmation = false
    @State private var pendingPermanentDeletion: Set<UUID> = []
    @State private var copiedToastTask: Task<Void, Never>?
    @State private var showingCopiedToast = false

    private var section: HistorySection { navigator.historySection }
    private var isTrash: Bool { section == .recentlyDeleted }
    private var searchText: String { navigator.historySearch }
    private var searchPrompt: String { isTrash ? "Search Recently Deleted" : "Search Clippings" }

    /// Everything in the current section, before search.
    private var sectionItems: [Clipping] {
        isTrash ? store.deletedClippings : store.clippings.filter(section.includes)
    }

    private var items: [Clipping] {
        let query = SearchQuery(searchText)
        guard !query.isEmpty else { return sectionItems }
        return sectionItems.filter { query.matches($0.searchableText) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
        } detail: {
            detail
        }
        .modifier(ToolbarSearch(
            text: $navigator.historySearch,
            prompt: searchPrompt,
            isInToolbar: !navigator.historyUsesInlineToolbar
        ))
        .frame(minWidth: 780, minHeight: 440)
        .environment(\.textScale, store.textSize.scale)
        .onChangeCompat(of: navigator.historySection) { _ in selection = [] }
        .onChangeCompat(of: store.clippings) { _ in pruneSelection() }
        .onChangeCompat(of: store.deletedClippings) { _ in pruneSelection() }
        .confirmationDialog(
            "Move all clippings to Recently Deleted?",
            isPresented: $showingClearAllConfirmation
        ) {
            Button("Clear All", role: .destructive) {
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.clearAll(undoManager: undoManager) }
            }
        } message: {
            Text("This includes pinned clippings. You can restore them from Recently Deleted for \(ClipboardStore.recentlyDeletedRetentionDays) days.")
        }
        .confirmationDialog(
            "Permanently delete all clippings in Recently Deleted?",
            isPresented: $showingEmptyConfirmation
        ) {
            Button("Delete All", role: .destructive) {
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.emptyRecentlyDeleted() }
            }
        } message: {
            Text("You can't undo this action.")
        }
        .confirmationDialog(
            pendingPermanentDeletion.count == 1
                ? "Permanently delete this clipping?"
                : "Permanently delete \(pendingPermanentDeletion.count) clippings?",
            isPresented: Binding(
                get: { !pendingPermanentDeletion.isEmpty },
                set: { if !$0 { pendingPermanentDeletion = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                let ids = pendingPermanentDeletion
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.permanentlyDelete(Array(ids)) }
                pendingPermanentDeletion = []
            }
        } message: {
            Text("You can't undo this action.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding<HistorySection?>(
            get: { navigator.historySection },
            set: { if let newValue = $0 { navigator.historySection = newValue } }
        )) {
            Section("Library") {
                sidebarRow(.all, count: store.clippings.count)
                sidebarRow(.pinned, count: store.clippings.filter(\.isPinned).count)
            }
            Section("Kinds") {
                sidebarRow(.text, count: store.clippings.filter { $0.kind == .text }.count)
                sidebarRow(.images, count: store.clippings.filter { $0.kind == .image }.count)
                sidebarRow(.files, count: store.clippings.filter { $0.kind == .fileURL }.count)
            }
            Section {
                sidebarRow(.recentlyDeleted, count: store.deletedClippings.count)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    private func sidebarRow(_ section: HistorySection, count: Int) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(count)
            .tag(section)
    }

    // MARK: - Content list

    private var content: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(section.title)
        .navigationSubtitle(subtitle)
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
        .toolbar { listToolbar }
        .safeAreaInset(edge: .top, spacing: 0) {
            if navigator.historyUsesInlineToolbar { inlineListBar }
        }
        .trashUndoToast(requiresKeyWindow: true)
        .overlay(alignment: .bottom) {
            if showingCopiedToast {
                ToastView(message: "Copied to Clipboard")
                    .padding(.bottom, 16)
                    .motionSafeTransition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var subtitle: String {
        let count = sectionItems.count
        return count == 1 ? "1 clipping" : "\(count.formatted()) clippings"
    }

    private var list: some View {
        List(selection: $selection) {
            if section == .all, searchText.isEmpty, items.contains(where: \.isPinned) {
                Section("Pinned") {
                    rows(items.filter(\.isPinned))
                }
                Section("Recent") {
                    rows(items.filter { !$0.isPinned })
                }
            } else {
                rows(items)
            }
        }
        .listStyle(.inset)
        .animation(.snappy(duration: 0.25), value: items.map(\.id))
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            // Double-click / Return: copy (or restore, in Recently Deleted).
            if isTrash {
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreClippings(Array(ids)) }
            } else if ids.count == 1, let clipping = activeClipping(ids.first) {
                copy(clipping)
            }
        }
        .onDeleteCommand {
            if isTrash {
                pendingPermanentDeletion = selection
            } else {
                trash(selection)
            }
        }
        // nil in Recently Deleted disables ⌘C there (an empty payload would clear the
        // pasteboard instead).
        .onCopyCommand(perform: isTrash ? nil : {
            let providers = store.clippings.filter { selection.contains($0.id) }.compactMap(\.itemProvider)
            // SwiftUI writes these to the pasteboard after we return; skip recording that.
            DispatchQueue.main.async { ClipboardMonitor.shared.resyncChangeCount() }
            AssistiveTech.announce(providers.count > 1 ? "Copied \(providers.count) clippings" : "Copied")
            return providers
        })
    }

    private func rows(_ clippings: [Clipping]) -> some View {
        ForEach(clippings) { clipping in
            HistoryRow(
                clipping: clipping,
                searchQuery: searchText,
                daysRemaining: isTrash ? store.daysRemaining(for: clipping) : nil
            )
            .tag(clipping.id)
            .swipeActions(edge: .trailing) {
                if isTrash {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingPermanentDeletion = [clipping.id]
                    }
                } else {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        trash([clipping.id])
                    }
                }
            }
            .swipeActions(edge: .leading) {
                if isTrash {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreClipping(clipping.id) }
                    }
                    .tint(Color.restoreActionFill)
                } else {
                    Button(clipping.isPinned ? "Unpin" : "Pin", systemImage: clipping.isPinned ? "pin.slash" : "pin") {
                        withAnimation(.snappy(duration: 0.2).motionSafe) { store.togglePin(clipping.id) }
                    }
                    .tint(Color.pinActionFill)
                }
            }
            // Everything the swipe actions and context menu offer, as VoiceOver actions
            // on the row (VO-Command-Space).
            .accessibilityActions {
                if isTrash {
                    Button("Restore") {
                        withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreClipping(clipping.id) }
                    }
                    Button("Delete Immediately") { pendingPermanentDeletion = [clipping.id] }
                } else {
                    Button("Copy") { copy(clipping) }
                    Button(clipping.isPinned ? "Unpin" : "Pin") {
                        withAnimation(.snappy(duration: 0.2).motionSafe) { store.togglePin(clipping.id) }
                    }
                    Button("Move to Recently Deleted") { trash([clipping.id]) }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        if isTrash {
            Button("Restore") {
                withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreClippings(Array(ids)) }
            }
            Divider()
            Button("Delete Immediately\u{2026}", role: .destructive) {
                pendingPermanentDeletion = ids
            }
        } else if !ids.isEmpty {
            let targets = store.clippings.filter { ids.contains($0.id) }
            if targets.count == 1, let clipping = targets.first {
                Button("Copy") { copy(clipping) }
                if clipping.kind == .fileURL, let urls = clipping.fileURLs {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                }
                Divider()
            }
            let allPinned = targets.allSatisfy(\.isPinned)
            Button(allPinned ? "Unpin" : "Pin") {
                withAnimation(.snappy(duration: 0.2).motionSafe) {
                    for clipping in targets where clipping.isPinned == allPinned {
                        store.togglePin(clipping.id)
                    }
                }
            }
            Divider()
            Button("Move to Recently Deleted", role: .destructive) {
                trash(ids)
            }
        }
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem {
            listActions
        }
    }

    /// macOS 13's stand-in for the toolbar over the list: what the window title and
    /// subtitle say, the list's actions, and the search field.
    private var inlineListBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                listActions
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            InlineSearchField(text: $navigator.historySearch, prompt: searchPrompt)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var listActions: some View {
        if isTrash {
            Menu {
                Button("Restore All") {
                    withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreAllDeleted() }
                }
                Divider()
                Button("Delete All\u{2026}", role: .destructive) {
                    showingEmptyConfirmation = true
                }
            } label: {
                Label("Recently Deleted Actions", systemImage: "ellipsis")
            }
            .disabled(store.deletedClippings.isEmpty)
            .help("Restore or permanently delete everything")
        } else {
            Menu {
                Button("Clear Unpinned Clippings") {
                    withAnimation(.snappy(duration: 0.25).motionSafe) { store.clearUnpinned(undoManager: undoManager) }
                }
                .disabled(!store.clippings.contains { !$0.isPinned })
                Button("Clear All Clippings\u{2026}") {
                    showingClearAllConfirmation = true
                }
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(store.clippings.isEmpty)
            .help("Clear history")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            SearchEmptyStateView(text: searchText)
        } else {
            switch section {
            case .recentlyDeleted:
                EmptyStateView {
                    Label("No Recently Deleted Clippings", systemImage: "trash")
                } description: {
                    Text("Deleted clippings stay here for \(ClipboardStore.recentlyDeletedRetentionDays) days before they're removed permanently.")
                }
            case .pinned:
                EmptyStateView {
                    Label("No Pinned Clippings", systemImage: "pin")
                } description: {
                    Text("Pinned clippings stay at the top and are never removed automatically.")
                }
            default:
                EmptyStateView {
                    Label("No Clippings", systemImage: section.symbol)
                } description: {
                    Text("Anything you copy will appear here.")
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if selection.count == 1, let id = selection.first,
           let clipping = (isTrash ? store.deletedClippings : store.clippings).first(where: { $0.id == id }) {
            HistoryDetail(
                clipping: clipping,
                searchQuery: searchText,
                isDeleted: isTrash,
                onDeleteImmediately: { pendingPermanentDeletion = [id] }
            )
            .id(id)
            .scaledFont(.body)
        } else if selection.count > 1 {
            EmptyStateView {
                Label("\(selection.count) Clippings Selected", systemImage: "square.on.square")
            } actions: {
                if isTrash {
                    Button("Restore") {
                        withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreClippings(Array(selection)) }
                    }
                } else {
                    Button("Move to Recently Deleted") { trash(selection) }
                }
            }
        } else {
            EmptyStateView {
                Label("No Clipping Selected", systemImage: "doc.on.clipboard")
            } description: {
                Text("Select a clipping to see it in full.")
            }
        }
    }

    // MARK: - Actions

    private func activeClipping(_ id: UUID?) -> Clipping? {
        guard let id else { return nil }
        return store.clippings.first { $0.id == id }
    }

    private func copy(_ clipping: Clipping) {
        clipping.writeToPasteboard()
        ClipboardMonitor.shared.resyncChangeCount()
        AssistiveTech.announce("Copied")
        copiedToastTask?.cancel()
        withAnimation(.snappy(duration: 0.25).motionSafe) { showingCopiedToast = true }
        copiedToastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25).motionSafe) { showingCopiedToast = false }
        }
    }

    private func trash(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25).motionSafe) {
            store.removeClippings(Array(ids), undoManager: undoManager)
        }
    }

    private func pruneSelection() {
        let valid = Set(sectionItems.map(\.id))
        if !selection.isSubset(of: valid) {
            selection.formIntersection(valid)
        }
    }
}

/// A row in the History list. No hover buttons: in a window, actions live in the
/// toolbar, context menu, swipe actions and keyboard (⌫, ⌘C, Return).
private struct HistoryRow: View {
    let clipping: Clipping
    let searchQuery: String
    /// Set in Recently Deleted, where the countdown replaces the capture time.
    let daysRemaining: Int?

    @EnvironmentObject private var store: ClipboardStore

    /// With an Apple Intelligence title, the title leads and the text's opening follows.
    private var smartTitle: String? {
        store.generatesSmartTitles ? clipping.smartTitle : nil
    }

    var body: some View {
        HStack(spacing: 10) {
            ClippingThumbnail(clipping: clipping, size: 30)
                .opacity(daysRemaining == nil ? 1 : 0.7)


            VStack(alignment: .leading, spacing: 2) {
                if let smartTitle {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        SmartTitleGlyph()
                        Text.highlighting(smartTitle, matching: searchQuery)
                            .fontWeight(.medium)
                    }
                    .lineLimit(1)
                    Text.highlighting(clipping.singleLinePreview, matching: searchQuery)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Group {
                        if clipping.previewTitle.isEmpty {
                            Text("Empty clipping").foregroundStyle(.secondary)
                        } else {
                            Text.highlighting(clipping.previewTitle, matching: searchQuery)
                        }
                    }
                    .lineLimit(2)
                    .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    if clipping.isPinned {
                        Image(systemName: "pin.fill")
                            .imageScale(.small)
                    }
                    if let app = clipping.sourceAppName {
                        Text(app)
                        Text("\u{00B7}")
                    }
                    if let daysRemaining {
                        DaysRemainingText(days: daysRemaining)
                    } else {
                        Text(clipping.createdAt, format: .relative(presentation: .named))
                    }
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        // Explicit: List gives its rows their own font, which would win over an
        // inherited one.
        .scaledFont(.body)
        // One VoiceOver element per row: "Flight confirmation email, Pinned, Mail,
        // yesterday". Its actions are added by the list.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clipping.accessibilityTitle(smartTitle: smartTitle))
        .accessibilityValue(accessibilityDetails)
    }

    private var accessibilityDetails: String {
        [
            clipping.isPinned ? "Pinned" : nil,
            clipping.accessibilityKind,
            clipping.sourceAppName,
            daysRemaining.map(DaysRemainingText.phrase)
                ?? clipping.createdAt.formatted(.relative(presentation: .named)),
            smartTitle != nil ? "Title by Apple Intelligence" : nil
        ].accessibilityJoined
    }
}

/// The detail column. Its own view so text-selection and Apple Intelligence state reset
/// cleanly whenever the selection moves to a different clipping.
private struct HistoryDetail: View {
    let clipping: Clipping
    let searchQuery: String
    let isDeleted: Bool
    var onDeleteImmediately: () -> Void

    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var navigator = AppNavigator.shared
    @State private var selectedText: String?
    @StateObject private var runner = TextActionRunner()

    var body: some View {
        ClippingDetailView(
            clipping: clipping,
            runner: isDeleted ? .inactive : runner,
            searchQuery: searchQuery,
            selectedText: $selectedText,
            isEditable: !isDeleted
        )
            .navigationTitle(clipping.sourceAppName ?? clipping.kindTitle)
            .toolbar {
                if isDeleted {
                    ToolbarItemGroup {
                        deletedActions
                    }
                } else {
                    // Its own glass group, only when there's something to show, so image
                    // and file clippings don't get an empty bubble.
                    if IntelligenceMenu.isShown(for: clipping) {
                        ToolbarItem {
                            IntelligenceMenu(clipping: clipping, runner: runner)
                        }
                        if #available(macOS 26.0, *) {
                            ToolbarSpacer(.fixed)
                        }
                    }
                    ToolbarItemGroup {
                        clippingActions
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if navigator.historyUsesInlineToolbar { inlineBar }
            }
    }

    @ViewBuilder
    private var deletedActions: some View {
        Button {
            withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreClipping(clipping.id) }
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        .help("Restore")

        Button(role: .destructive, action: onDeleteImmediately) {
            Label("Delete Immediately", systemImage: "trash")
        }
        .help("Delete Immediately")
    }

    @ViewBuilder
    private var clippingActions: some View {
        ClippingCopyButton(clipping: clipping, textOverride: selectedText)
        ClippingPinButton(clipping: clipping)
        ClippingDeleteButton(clipping: clipping)
    }

    /// macOS 13's stand-in for the toolbar over the clipping: the title the window would
    /// show, and the clipping's actions. (No Apple Intelligence menu: it needs macOS 26.)
    private var inlineBar: some View {
        HStack(spacing: 12) {
            Text(clipping.sourceAppName ?? clipping.kindTitle)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if isDeleted { deletedActions } else { clippingActions }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Puts the History window's search field in the toolbar, where it has one.
private struct ToolbarSearch: ViewModifier {
    @Binding var text: String
    let prompt: String
    let isInToolbar: Bool

    func body(content: Content) -> some View {
        if isInToolbar {
            content.searchable(text: $text, placement: .toolbar, prompt: prompt)
        } else {
            content
        }
    }
}

/// A search field for macOS 13's inline bar, in the look of the toolbar's.
private struct InlineSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
