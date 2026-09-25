import SwiftUI

/// A floating glass capsule with a message and an optional action.
struct ToastView: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .scaledFont(.callout)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .scaledFont(.callout, weight: .semibold)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 34)
        .glassEffect(.regular, in: .capsule)
        .increasedContrastBorder(Capsule())
        // The message and its button stay separate, so VoiceOver and Voice Control can
        // press Undo.
        .accessibilityElement(children: .contain)
    }
}

/// Shows "Moved to Recently Deleted · Undo" whenever clippings are deleted, so the
/// Recently Deleted safety net is visible at the moment it matters. The deletion itself
/// is announced to VoiceOver by the store; ⌘Z undoes it too.
private struct TrashUndoToast: ViewModifier {
    var bottomPadding: CGFloat
    /// When true, only reacts while this window is key — so a deletion made in the
    /// popover doesn't also pop a toast in a background History window.
    var requiresKeyWindow: Bool

    @Environment(ClipboardStore.self) private var store
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var event: TrashEvent?
    @State private var hideTask: Task<Void, Never>?
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let event {
                    ToastView(
                        message: event.clippingIDs.count == 1
                            ? "Moved to Recently Deleted"
                            : "Moved \(event.clippingIDs.count) clippings to Recently Deleted",
                        actionTitle: "Undo"
                    ) {
                        withAnimation(.snappy(duration: 0.25).motionSafe) {
                            store.restoreClippings(event.clippingIDs)
                        }
                    }
                    .onHover { isHovering = $0 }
                    .padding(.bottom, bottomPadding)
                    .motionSafeTransition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: store.lastTrash) { _, newValue in
                guard let newValue else {
                    hide()
                    return
                }
                guard !requiresKeyWindow || controlActiveState == .key else { return }
                show(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardPopoverWillShow)) { _ in
                hideTask?.cancel()
                event = nil
            }
    }

    private func show(_ newEvent: TrashEvent) {
        withAnimation(.snappy(duration: 0.25).motionSafe) { event = newEvent }
        scheduleHide()
    }

    /// Hides after 5 seconds (15 with VoiceOver or Switch Control), but never while the
    /// pointer is on the toast, so there's always time to reach Undo.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: AssistiveTech.duration(.seconds(5)))
            guard !Task.isCancelled else { return }
            if isHovering {
                scheduleHide()
            } else {
                hide()
            }
        }
    }

    private func hide() {
        hideTask?.cancel()
        withAnimation(.snappy(duration: 0.25).motionSafe) { event = nil }
    }
}

extension View {
    func trashUndoToast(bottomPadding: CGFloat = 16, requiresKeyWindow: Bool = false) -> some View {
        modifier(TrashUndoToast(bottomPadding: bottomPadding, requiresKeyWindow: requiresKeyWindow))
    }
}
