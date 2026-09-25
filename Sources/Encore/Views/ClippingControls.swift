import SwiftUI
import AppKit

/// Borderless circular icon button for dense lists: a soft fill on hover, a deeper fill
/// and slight shrink on press. Toolbars and floating bars use `.glass` instead.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    @State private var isHovering = false

    var body: some View {
        // Icons grow with Text Size, but only half as much: a 200% row shouldn't get
        // buttons twice as big.
        let scale = 1 + (textScale - 1) / 2
        configuration.label
            .font(.system(size: 13 * scale))
            .frame(width: 26 * scale, height: 26 * scale)
            .background(
                Circle().fill(.primary.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.08 : 0)))
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Copies a clipping to the pasteboard without creating a new history entry; the icon
/// flips to a checkmark briefly to confirm. When `textOverride` is non-empty (the user
/// has an active selection in the detail screen's text), copies just that substring
/// instead of the whole clipping.
///
/// Unstyled: hosts pick `IconButtonStyle` in rows, `.glass` in floating bars, and
/// toolbars style it natively.
struct ClippingCopyButton: View {
    let clipping: Clipping
    var textOverride: String? = nil

    @State private var showCheckmark = false
    @State private var resetTask: Task<Void, Never>?

    private var hasSelection: Bool {
        guard let textOverride else { return false }
        return !textOverride.isEmpty
    }

    var body: some View {
        Button {
            if hasSelection, let textOverride {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(textOverride, forType: .string)
            } else {
                clipping.writeToPasteboard()
            }
            ClipboardMonitor.shared.resyncChangeCount()
            AssistiveTech.announce(hasSelection ? "Copied selection" : "Copied")

            resetTask?.cancel()
            withAnimation(.snappy(duration: 0.2).motionSafe) { showCheckmark = true }
            resetTask = Task {
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.2).motionSafe) { showCheckmark = false }
            }
        } label: {
            Label(
                hasSelection ? "Copy Selection" : "Copy",
                systemImage: showCheckmark ? "checkmark" : "doc.on.doc"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(showCheckmark ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .contentTransition(.symbolEffect(.replace))
        }
        .help(hasSelection ? "Copy Selection" : "Copy to Clipboard")
        .accessibilityLabel(hasSelection ? "Copy Selection" : "Copy to Clipboard")
        .accessibilityInputLabels(hasSelection ? ["Copy Selection", "Copy"] : ["Copy", "Copy to Clipboard"])
        .onDisappear { resetTask?.cancel() }
    }
}

/// The brief "Copied" confirmation in popover rows and lookup cards: light text on a
/// solid accent capsule. Tinted text alone faded into the glass, which takes on whatever
/// is behind the popover. Announced separately by whoever copies, since it only flashes.
struct CopiedBadge: View {
    var body: some View {
        Label("Copied", systemImage: "checkmark")
            .scaledFont(.caption, weight: .semibold)
            .foregroundStyle(Color.accentBadgeText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(minHeight: 20)
            .background(Color.accentBadgeFill, in: .capsule)
            .accessibilityHidden(true)
    }
}

/// The Option+digit hint shown on the first ten rows: dimmed and unobtrusive, in the
/// same trailing spot `CopiedBadge` and the hover-only pin/delete icons use, so it
/// never adds width to the row and only ever shows when neither of those does.
struct QuickCopyBadge: View {
    let key: String

    var body: some View {
        HStack(spacing: 1) {
            Text("\u{2325}")
            Text(key).monospacedDigit()
        }
        .scaledFont(.caption, weight: .medium)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 7)
        .frame(minHeight: 20)
        .background(.primary.opacity(0.06), in: .capsule)
        .accessibilityHidden(true)
    }
}

/// Toggles a clipping's pinned state.
struct ClippingPinButton: View {
    let clipping: Clipping
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2).motionSafe) {
                store.togglePin(clipping.id)
            }
        } label: {
            Label(clipping.isPinned ? "Unpin" : "Pin", systemImage: clipping.isPinned ? "pin.fill" : "pin")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .help(clipping.isPinned ? "Unpin" : "Pin")
        .accessibilityInputLabels([clipping.isPinned ? "Unpin" : "Pin"])
    }
}

/// Moves a clipping to Recently Deleted. No confirmation: the action is recoverable,
/// so it registers Undo (⌘Z) and the popover shows an Undo toast instead.
struct ClippingDeleteButton: View {
    let clipping: Clipping
    var onDeleted: (() -> Void)?

    @Environment(ClipboardStore.self) private var store
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25).motionSafe) {
                store.removeClipping(clipping.id, undoManager: undoManager)
            }
            onDeleted?()
        } label: {
            Label("Delete", systemImage: "trash")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .help("Move to Recently Deleted")
        .accessibilityInputLabels(["Delete", "Move to Recently Deleted", "Trash"])
    }
}

/// Two-step button for irreversible actions in places a modal dialog would be wrong (the
/// transient menu bar popover): the first click expands it into a red, labelled confirm
/// capsule; a second click performs the action. It reverts on its own after a few
/// seconds — longer with VoiceOver or Switch Control, and never while the pointer is on it.
struct ConfirmingButton: View {
    enum Style {
        /// Borderless icon for list rows; arms into a red capsule.
        case icon
        /// Glass circle for floating bars; arms into a red prominent-glass capsule.
        case glass
    }

    let title: String
    let systemImage: String
    let confirmTitle: String
    var help: String? = nil
    var style: Style = .icon
    let action: () -> Void

    @Environment(\.textScale) private var textScale
    @State private var isArmed = false
    @State private var isHovering = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch style {
            case .icon: iconBody
            case .glass: glassBody
            }
        }
        // On macOS the help tag is also what VoiceOver reads as the hint.
        .help(isArmed ? "Click again to confirm" : (help ?? title))
        .accessibilityLabel(isArmed ? confirmTitle : title)
        .accessibilityInputLabels(isArmed ? [confirmTitle, "Confirm"] : [title])
        .onHover { isHovering = $0 }
        .onDisappear { resetTask?.cancel() }
    }

    private func tap() {
        resetTask?.cancel()
        if isArmed {
            isArmed = false
            action()
        } else {
            withAnimation(.snappy(duration: 0.2).motionSafe) { isArmed = true }
            AssistiveTech.announce("Press again to \(confirmTitle.lowercased())")
            scheduleReset()
        }
    }

    private func scheduleReset() {
        resetTask = Task {
            try? await Task.sleep(for: AssistiveTech.duration(.seconds(3)))
            guard !Task.isCancelled else { return }
            if isHovering {
                scheduleReset()
            } else {
                withAnimation(.snappy(duration: 0.2).motionSafe) { isArmed = false }
            }
        }
    }

    @ViewBuilder
    private var glassBody: some View {
        if isArmed {
            Button(confirmTitle, action: tap)
                .buttonStyle(.glassProminent)
                .tint(Color.destructiveFill)
        } else {
            Button(action: tap) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    private var iconBody: some View {
        let scale = 1 + (textScale - 1) / 2
        return Button(action: tap) {
            if isArmed {
                Text(confirmTitle)
                    .scaledFont(.callout, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .frame(minHeight: 24)
                    .background(Color.destructiveFill, in: .capsule)
                    .motionSafeTransition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))
            } else {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13 * scale))
                    .frame(width: 26 * scale, height: 26 * scale)
                    .contentShape(Circle())
                    .transition(.opacity)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Leading visual for a clipping row: an image thumbnail, the file's Finder icon, or the
/// source app's icon for text. Hidden from VoiceOver: the row's label says what it shows.
struct ClippingThumbnail: View {
    let clipping: Clipping
    var size: CGFloat = 28

    @Environment(\.textScale) private var textScale

    var body: some View {
        // Grows with Text Size, but only half as much, like the row's icon buttons.
        let size = size * (1 + (textScale - 1) / 2)
        Group {
            if let image = ClippingThumbnails.image(for: clipping) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.continuous(UIRadius.thumbnail))
            } else if let icon = ClippingThumbnails.fileIcon(for: clipping)
                        ?? ClippingThumbnails.appIcon(bundleID: clipping.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: clipping.kindSymbol)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        // Photos and app icons keep their real colours under Invert Colors.
        .accessibilityIgnoresInvertColors()
        .accessibilityHidden(true)
    }
}
