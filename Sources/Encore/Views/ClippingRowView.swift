import SwiftUI
import AppKit

/// A single clipping row in the menu bar popover.
///
/// Clicking the row copies it — the one thing a clipboard popover is for — and flashes
/// "Copied". The trailing chevron opens the full clipping (like the detail chevrons in
/// Control Center); pin and delete appear on hover, and everything is in the context menu.
///
/// For VoiceOver the row is one element — "Flight confirmation email, Pinned, Mail,
/// 5 minutes ago" — whose default action copies, with Show Details, Pin and Move to
/// Recently Deleted as actions (VO-Command-Space). The chevron stays a separate button
/// so Voice Control can click it by name.
struct ClippingRowView: View {
    let clipping: Clipping
    /// The active search query, if any — matching text is highlighted inline.
    var searchQuery: String = ""
    /// Highlighted from the keyboard (↑ and ↓ in the popover's search field).
    var isHighlighted = false
    /// Shows the brief "Copied" confirmation.
    var isCopied = false
    /// "1" through "9", then "0" for the tenth row: the digit that copies this row with
    /// Option held, shown as a hint when nothing else needs that spot. Nil past the
    /// tenth row, which has no shortcut.
    var quickCopyKey: String? = nil
    /// Called when the row is clicked or activated: copy the clipping.
    var onCopy: (Clipping) -> Void
    /// Called with the clipping's id when the detail chevron is clicked.
    var onOpen: (UUID) -> Void

    @Environment(ClipboardStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    private var title: String { store.displayTitle(for: clipping) }
    private var smartTitle: String? { store.generatesSmartTitles ? clipping.smartTitle : nil }

    var body: some View {
        HStack(spacing: 10) {
            summary

            if isCopied {
                CopiedBadge()
                    .motionSafeTransition(.opacity.combined(with: .scale(scale: 0.8)))
            } else if isHovering {
                // Pointer-only shortcuts; VoiceOver and Voice Control reach the same
                // actions through the row's actions and context menu.
                HStack(spacing: 0) {
                    ClippingPinButton(clipping: clipping)
                    ClippingDeleteButton(clipping: clipping)
                }
                .buttonStyle(IconButtonStyle())
                .transition(.opacity)
                .accessibilityHidden(true)
            } else if let quickCopyKey {
                QuickCopyBadge(key: quickCopyKey)
                    .motionSafeTransition(.opacity)
            }

            Button {
                onOpen(clipping.id)
            } label: {
                Label("Show Details", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(IconButtonStyle())
            .help("Show Details")
            .accessibilityInputLabels(["Show Details", "Details", "Open"])
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 5)
        .background {
            if isHighlighted {
                ConcentricRectangle.row
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay {
                        ConcentricRectangle.row
                            .stroke(Color.accentColor.opacity(contrast == .increased ? 1 : 0.55), lineWidth: 1)
                    }
            }
        }
        .contentShape(.row)
        .onTapGesture { onCopy(clipping) }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .contextMenu {
            Button("Copy") { onCopy(clipping) }
            Button("Show Details") { onOpen(clipping.id) }
            Button(clipping.isPinned ? "Unpin" : "Pin", action: togglePin)
            Divider()
            Button("Move to Recently Deleted", role: .destructive, action: delete)
        }
    }

    /// Thumbnail and text: the part VoiceOver reads as the row.
    private var summary: some View {
        HStack(spacing: 10) {
            ClippingThumbnail(clipping: clipping, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if smartTitle != nil {
                        SmartTitleGlyph()
                    }
                    if title.isEmpty {
                        Text("Empty clipping").foregroundStyle(.secondary)
                    } else {
                        Text.highlighting(title, matching: searchQuery)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)

                HStack(spacing: 4) {
                    if clipping.isPinned {
                        Image(systemName: "pin.fill")
                            .imageScale(.small)
                    }
                    if let app = clipping.sourceAppName {
                        Text(app)
                        Text("\u{00B7}")
                    }
                    Text(clipping.createdAt, format: .relative(presentation: .named))
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RowAccessibility(
            label: clipping.accessibilityTitle(smartTitle: smartTitle),
            value: accessibilityDetails,
            isHighlighted: isHighlighted,
            pinTitle: clipping.isPinned ? "Unpin" : "Pin",
            copy: { onCopy(clipping) },
            open: { onOpen(clipping.id) },
            togglePin: togglePin,
            delete: delete
        ))
    }

    private var accessibilityDetails: String {
        [
            clipping.isPinned ? "Pinned" : nil,
            clipping.accessibilityKind,
            clipping.sourceAppName,
            clipping.createdAt.formatted(.relative(presentation: .named)),
            smartTitle != nil ? "Title by Apple Intelligence" : nil,
            quickCopyKey.map { "Option \($0) copies this" }
        ].accessibilityJoined
    }

    private func togglePin() {
        withAnimation(.snappy(duration: 0.2).motionSafe) {
            store.togglePin(clipping.id)
        }
    }

    private func delete() {
        withAnimation(.snappy(duration: 0.25).motionSafe) {
            store.removeClipping(clipping.id, undoManager: undoManager)
        }
    }
}

/// The row as one VoiceOver element: activating it copies, and the other row actions are
/// in the actions menu (VO-Command-Space).
private struct RowAccessibility: ViewModifier {
    let label: String
    let value: String
    let isHighlighted: Bool
    let pinTitle: String
    let copy: () -> Void
    let open: () -> Void
    let togglePin: () -> Void
    let delete: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint("Copies to the clipboard")
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, copy)
            .accessibilityAction(named: "Show Details", open)
            .accessibilityAction(named: pinTitle, togglePin)
            .accessibilityAction(named: "Move to Recently Deleted", delete)
    }
}
