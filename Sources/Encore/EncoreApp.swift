import SwiftUI

@main
struct EncoreApp: App {
    // AppDelegate owns the status item, popover, and History/Settings windows —
    // needed so right-clicking the menu bar icon can show a different menu than a
    // left click, which `MenuBarExtra` alone can't distinguish.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = ClipboardStore.shared

    var body: some Scene {
        // Placeholder scene; the real Settings window is AppKit-built (see
        // SettingsWindowController). Route the app menu's Settings… (⌘,) — visible
        // while a window is open — to it instead of this empty scene.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    AppNavigator.shared.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Show History") {
                    AppNavigator.shared.showHistory()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            // Text Size, as in Books. The same setting is in Settings → General.
            CommandGroup(before: .toolbar) {
                Button("Actual Size") { store.resetTextSize() }
                    .disabled(store.textSize == .standard)
                Button("Make Text Bigger") { store.makeTextBigger() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(store.textSize.bigger == nil)
                Button("Make Text Smaller") { store.makeTextSmaller() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(store.textSize.smaller == nil)
                Divider()
            }
        }
    }
}
