import AppKit
import Carbon

/// Registers a single system-wide keyboard shortcut — \u{21e7}\u{2318}V, the shortcut Flycut,
/// CopyClip and Paste already use for "show clipboard history" — so the popover can be
/// opened (and, pressed again, closed) from any app without touching the menu bar icon.
///
/// Uses the classic Carbon Hot Key Manager rather than a global `NSEvent` monitor: it
/// keeps working inside the App Sandbox with no Accessibility/Input Monitoring
/// permission, and the OS delivers the key combo to Encore alone, so it's never also
/// seen (or acted on) by whichever app is frontmost — nothing else on the system is
/// assigned \u{21e7}\u{2318}V by default, so registering it can't take a shortcut away from macOS
/// or another app.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    /// Arbitrary but stable; only distinguishes our hot key from others in-process, and
    /// nothing else here registers one.
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x456e_6b48), id: 1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onToggle: (() -> Void)?

    private init() {}

    func start(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKeyManager.shared.onToggle?() }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            Self.hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
