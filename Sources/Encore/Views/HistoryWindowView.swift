import SwiftUI
import AppKit

/// The History window: a three-column split view in the Mail/Notes mould — a sidebar of
/// sections (including Recently Deleted), the clipping list, and the selected clipping.
///
/// Everything is native chrome so it picks up the macOS 26+ design for free: the
/// floating glass sidebar, the toolbar search field, concentric row selection, grouped
/// glass toolbar buttons, and scroll-edge effects.
struct HistoryWindowView: View {
    @Environment(ClipboardStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Bindable private var navigator = AppNavigator.shared

    @State private var selection = Set<UUID>()
    @State private var showingClearAllConfirmation = false
    @State private var showingEmptyConfirmation = false
    @State private var pendingPermanentDeletion: Set<UUID> = []
    @State private var copiedToastTask: Task<Void, Never>?
    @State private var showingCopiedToast = false

    private var section: HistorySection { navigator.historySection }
    private var isTrash: Bool { section == .recentlyDeleted }
    private var searchText: String { navigator.historySearch }

    /// Everything in the current section, before search.
    private var sectionItems: [Clipping] {
        isTrash ? store.deletedClippings : store.clippings.filter(section.includes)
    }

    private var items: [Clipping] {
        guard !searchText.isEmpty else { return sectionItems }
        return sectionItems.filter { $0.searchableText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
        } detail: {
            detail
        }
        .searchable(
            text: $navigator.historySearch,
            placement: .toolbar,
            prompt: isTrash ? "Search Recently Deleted" : "Search Clippings"
        )
        .frame(minWidth: 780, minHeight: 440)
        .environment(\.textScale, store.textSize.scale)
        .onChange(of: navigator.historySection) { selection = [] }
        .onChange(of: store.clippings) { pruneSelection() }
        .onChange(of: store.deletedClippings) { pruneSelection() }
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
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            switch section {
            case .recentlyDeleted:
                ContentUnavailableView {
                    Label("No Recently Deleted Clippings", systemImage: "trash")
                } description: {
                    Text("Deleted clippings stay here for \(ClipboardStore.recentlyDeletedRetentionDays) days before they're removed permanently.")
                }
            case .pinned:
                ContentUnavailableView {
                    Label("No Pinned Clippings", systemImage: "pin")
                } description: {
                    Text("Pinned clippings stay at the top and are never removed automatically.")
                }
            default:
                ContentUnavailableView {
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
            ContentUnavailableView {
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
            ContentUnavailableView {
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

    @Environment(ClipboardStore.self) private var store

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

    @Environment(ClipboardStore.self) private var store
    @State private var selectedText: String?
    @State private var runner = TextActionRunner()

    var body: some View {
        ClippingDetailView(
            clipping: clipping,
            runner: isDeleted ? nil : runner,
            searchQuery: searchQuery,
            selectedText: $selectedText
        )
            .navigationTitle(clipping.sourceAppName ?? clipping.kindTitle)
            .toolbar {
                if isDeleted {
                    ToolbarItemGroup {
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
                } else {
                    // Its own glass group, only when there's something to show, so image
                    // and file clippings don't get an empty bubble.
                    if IntelligenceMenu.isShown(for: clipping) {
                        ToolbarItem {
                            IntelligenceMenu(clipping: clipping, runner: runner)
                        }
                        ToolbarSpacer(.fixed)
                    }
                    ToolbarItemGroup {
                        ClippingCopyButton(clipping: clipping, textOverride: selectedText)
                        ClippingPinButton(clipping: clipping)
                        ClippingDeleteButton(clipping: clipping)
                    }
                }
            }
    }
}
