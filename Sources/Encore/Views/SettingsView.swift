import SwiftUI
import AppKit

// Settings panes. Each is hosted in its own tab of a native toolbar-style Settings window
// (see SettingsWindowController), so each lays itself out as a grouped Form at a fixed
// width and lets the window resize to fit — the standard macOS Settings behaviour.

private let settingsWidth: CGFloat = 520

struct GeneralSettingsView: View {
    @Environment(ClipboardStore.self) private var store
    @State private var accessBehavior = NSPasteboard.general.accessBehavior

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Record clipboard history", isOn: $store.isRecordingEnabled)
                if let accessNote {
                    LabeledContent {
                        Button("Open Privacy & Security\u{2026}") {
                            ClipboardMonitor.openPasteboardPrivacySettings()
                        }
                    } label: {
                        // Blocked is an error: said with an icon as well as colour.
                        if store.isPasteboardAccessDenied {
                            Label(accessNote, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.errorText)
                        } else {
                            Text(accessNote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("You can also pause recording from the menu bar.")
            }

            Section("When Something Is Copied") {
                Toggle("Play a sound", isOn: $store.playSoundOnCopy)
                Toggle("Flash the menu bar icon", isOn: $store.flashesMenuBarIconOnCopy)
            }

            Section("Menu Bar") {
                Picker("Recent clippings to show", selection: $store.maxDisplayedCount) {
                    ForEach(options([5, 10, 20, 30, 50, 100], including: store.maxDisplayedCount), id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
            }

            Section {
                Picker("Text size", selection: $store.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
            } header: {
                Text("Text")
            } footer: {
                Text("Sets the size of clippings in the menu bar and the History window. You can also use \u{2318}+ and \u{2318}\u{2212}.")
            }

            Section {
                Toggle("Open at login", isOn: $store.launchAtLogin)
                if store.launchAtLogin, store.launchAtLoginStatus == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items\u{2026}") {
                            LaunchAtLoginManager.openLoginItemsSettings()
                        }
                    } label: {
                        Text("Needs your approval in System Settings")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = store.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.errorText)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: settingsWidth, height: accessNote == nil ? 548 : 598)
        .onAppear {
            store.refreshLaunchAtLoginStatus()
            ClipboardMonitor.shared.refreshAccessStatus()
            accessBehavior = NSPasteboard.general.accessBehavior
        }
    }

    /// macOS lets people decide whether apps may read what other apps copied (Privacy &
    /// Security → Paste from Other Apps). A clipboard manager needs "Allow".
    private var accessNote: String? {
        if store.isPasteboardAccessDenied {
            return "\(AppInfo.name) isn't allowed to read the clipboard, so nothing is recorded."
        }
        if accessBehavior == .ask {
            return "macOS asks before \(AppInfo.name) reads the clipboard. Choose Allow to record without interruptions."
        }
        return nil
    }
}

struct HistorySettingsView: View {
    @Environment(ClipboardStore.self) private var store
    @State private var showingClearConfirmation = false
    @State private var showingEmptyConfirmation = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Keep up to", selection: $store.maxStoredCount) {
                    ForEach(options([50, 100, 200, 500, 1000], including: store.maxStoredCount), id: \.self) {
                        Text("\($0) clippings").tag($0)
                    }
                }
                LabeledContent("Currently stored", value: "\(store.clippings.count)")
            } footer: {
                Text("When the limit is reached, the oldest clippings are removed. Pinned clippings are never removed automatically.")
            }

            Section {
                LabeledContent("Recently Deleted", value: "\(store.deletedClippings.count)")
                HStack {
                    Button("Show Recently Deleted") {
                        AppNavigator.shared.showHistory(.recentlyDeleted)
                    }
                    Spacer()
                    Button("Empty Recently Deleted\u{2026}", role: .destructive) {
                        showingEmptyConfirmation = true
                    }
                    .disabled(store.deletedClippings.isEmpty)
                }
            } footer: {
                Text("Deleted clippings are kept for \(ClipboardStore.recentlyDeletedRetentionDays) days, then removed permanently.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Clear History\u{2026}", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .disabled(store.clippings.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: settingsWidth, height: 360)
        .confirmationDialog("Move all clippings to Recently Deleted?", isPresented: $showingClearConfirmation) {
            Button("Clear History", role: .destructive) { store.clearAll() }
        } message: {
            Text("This includes pinned clippings.")
        }
        .confirmationDialog("Permanently delete all clippings in Recently Deleted?", isPresented: $showingEmptyConfirmation) {
            Button("Delete All", role: .destructive) { store.emptyRecentlyDeleted() }
        } message: {
            Text("You can't undo this action.")
        }
    }
}

struct AboutSettingsView: View {
    private var version: String {
        "Version \(AppInfo.shortVersion) (\(AppInfo.build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(AppInfo.name)
                .font(.title2.weight(.semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Everything you copy, ready for an encore.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Link("Source Code on GitHub", destination: AppInfo.repositoryURL)
                .font(.callout)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(width: settingsWidth)
    }
}

/// The preset choices, plus the current value if it isn't one of them (e.g. a value set
/// by an older version's stepper), so the picker never shows a blank selection.
private func options(_ presets: [Int], including current: Int) -> [Int] {
    presets.contains(current) ? presets : (presets + [current]).sorted()
}
