import SwiftUI

/// Recently Deleted as a page inside the menu bar popover: restore or erase clippings
/// without opening a window. Irreversible actions confirm inline (a popover shouldn't
/// raise modal dialogs), mirroring how Photos and Notes treat Recently Deleted.
struct RecentlyDeletedPage: View {
    var onBack: () -> Void

    @Environment(ClipboardStore.self) private var store
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        // ZStack, not Group, so the bars stay in place when the last clipping goes (see
        // MenuBarContentView.listPage).
        ZStack {
            if store.deletedClippings.isEmpty {
                ContentUnavailableView {
                    Label("No Recently Deleted Clippings", systemImage: "trash")
                } description: {
                    Text("Deleted clippings stay here for \(ClipboardStore.recentlyDeletedRetentionDays) days.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.deletedClippings) { clipping in
                            DeletedClippingRow(clipping: clipping)
                                .motionSafeTransition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .animation(.snappy(duration: 0.25).motionSafe, value: store.deletedClippings)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) { header }
        .safeAreaBar(edge: .bottom) {
            if !store.deletedClippings.isEmpty {
                Text("Clippings are permanently deleted after \(ClipboardStore.recentlyDeletedRetentionDays) days.")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(10)
            }
        }
        .onAppear { store.purgeExpiredDeletions() }
        .task {
            // After the page transition, move VoiceOver to the page's title.
            try? await Task.sleep(for: .milliseconds(350))
            isTitleFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .labelStyle(.iconOnly)
            .keyboardShortcut(.cancelAction)
            .help("Back")
            .accessibilityInputLabels(["Back", "Go Back"])

            Text("Recently Deleted")
                .scaledFont(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)

            Spacer()

            if !store.deletedClippings.isEmpty {
                Button("Restore All") {
                    withAnimation(.snappy(duration: 0.25).motionSafe) { store.restoreAllDeleted() }
                }
                .buttonStyle(.glass)

                ConfirmingButton(
                    title: "Empty",
                    systemImage: "trash.slash",
                    confirmTitle: "Delete All",
                    help: "Permanently delete everything in Recently Deleted",
                    style: .glass
                ) {
                    withAnimation(.snappy(duration: 0.25).motionSafe) { store.emptyRecentlyDeleted() }
                }
            }
        }
        .controlSize(.large)
        .padding(10)
    }
}

/// One deleted clipping in the popover: days until it's purged, Restore, and a two-step
/// permanent delete.
private struct DeletedClippingRow: View {
    let clipping: Clipping
    @Environment(ClipboardStore.self) private var store

    private var title: String { store.displayTitle(for: clipping) }
    private var smartTitle: String? { store.generatesSmartTitles ? clipping.smartTitle : nil }
    private var daysRemaining: Int { store.daysRemaining(for: clipping) }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ClippingThumbnail(clipping: clipping, size: 26)
                    .opacity(0.7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? "Empty clipping" : title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    DaysRemainingText(days: daysRemaining)
                        .scaledFont(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clipping.accessibilityTitle(smartTitle: smartTitle))
            .accessibilityValue([clipping.accessibilityKind, DaysRemainingText.phrase(daysRemaining)].accessibilityJoined)
            .accessibilityAction(named: "Restore", restore)

            Button(action: restore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(IconButtonStyle())
            .help("Restore")
            .accessibilityInputLabels(["Restore"])

            ConfirmingButton(
                title: "Delete Immediately",
                systemImage: "trash",
                confirmTitle: "Delete"
            ) {
                withAnimation(.snappy(duration: 0.25).motionSafe) {
                    store.permanentlyDelete(clipping.id)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .contentShape(.row)
        .contextMenu {
            Button("Restore", action: restore)
        }
    }

    private func restore() {
        withAnimation(.snappy(duration: 0.25).motionSafe) {
            store.restoreClipping(clipping.id)
        }
    }
}

/// "12 days left", in the warning colour in the final few days — and with a clock badge
/// too when Differentiate Without Color is on.
struct DaysRemainingText: View {
    let days: Int

    @Environment(\.backgroundProminence) private var backgroundProminence
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var isUrgent: Bool { days <= 3 }

    /// The text on its own, for VoiceOver labels.
    static func phrase(_ days: Int) -> String {
        if days <= 0 { return "Deleting soon" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    var body: some View {
        HStack(spacing: 3) {
            if isUrgent, differentiateWithoutColor {
                Image(systemName: "clock.badge.exclamationmark")
                    .accessibilityHidden(true)
            }
            Text(Self.phrase(days))
        }
        .foregroundStyle(style)
    }

    private var style: AnyShapeStyle {
        guard isUrgent else { return AnyShapeStyle(.secondary) }
        // On a selected row's accent fill, orange would clash and lose contrast.
        return backgroundProminence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.warningText)
    }
}
