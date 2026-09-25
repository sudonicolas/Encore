import SwiftUI
import AppKit

// Shared accessibility plumbing: Reduce Motion, VoiceOver announcements, timing for
// assistive technologies, and Increase Contrast borders. Kept in one place so every
// surface (popover, History, Settings) behaves the same way.

// MARK: - Reduce Motion

extension Animation {
    /// This animation, or with Reduce Motion on, a short ease with no bounce or overshoot.
    /// Fades and colour changes stay; springy movement goes (Apple HIG, Motion).
    ///
    /// Read at the moment the animation starts, so it's right for `withAnimation` in
    /// button actions, where the SwiftUI environment isn't available.
    var motionSafe: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.2) : self
    }
}

extension View {
    /// `.transition(transition)`, or a plain cross-fade with Reduce Motion on, so views
    /// appear and disappear without sliding, scaling or zooming.
    func motionSafeTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionSafeTransition(transition: transition))
    }
}

private struct MotionSafeTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

// MARK: - Assistive technologies

/// VoiceOver announcements, and timing that adapts to people using VoiceOver or Switch
/// Control.
@MainActor
enum AssistiveTech {
    /// True while VoiceOver or Switch Control is on. Reaching a control takes longer with
    /// either, so anything that disappears on a timer waits longer.
    static var isRunning: Bool {
        let workspace = NSWorkspace.shared
        return workspace.isVoiceOverEnabled || workspace.isSwitchControlEnabled
    }

    /// How long transient UI (the Undo toast, an armed confirm button) stays up: `base`
    /// normally, three times as long with VoiceOver or Switch Control on.
    static func duration(_ base: Duration) -> Duration {
        isRunning ? base * 3 : base
    }

    /// Speaks `message` with VoiceOver (and shows it on a braille display) without moving
    /// the VoiceOver cursor. For results that aren't otherwise conveyed by focus or a
    /// label change: "Copied", "Moved to Recently Deleted", an Apple Intelligence result
    /// being ready. Does nothing when no assistive technology is listening.
    static func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .high) {
        guard !message.isEmpty else { return }
        // A turn later, so the announcement isn't cut off by VoiceOver echoing the
        // control that was just pressed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: priority.rawValue
                ]
            )
        }
    }
}

// MARK: - Increase Contrast

extension View {
    /// Outlines a softly tinted surface (search field, banner, card) when Increase
    /// Contrast is on, so its edge stays visible at 3:1 or better — what system controls
    /// do in the same setting.
    func increasedContrastBorder<S: InsettableShape>(_ shape: S) -> some View {
        modifier(IncreasedContrastBorder(shape: shape))
    }
}

private struct IncreasedContrastBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                shape.strokeBorder(.primary.opacity(0.55), lineWidth: 1)
            }
        }
    }
}
