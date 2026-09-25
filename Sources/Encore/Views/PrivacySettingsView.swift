import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Privacy settings: concealed-content filtering and the ignored-apps list.
struct PrivacySettingsView: View {
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Ignore passwords and other concealed content", isOn: $store.ignoresConcealedContent)
            } footer: {
                Text("Password managers mark what they copy as concealed or temporary. When this is on, it's never recorded.")
            }

            Section {
                if store.ignoredApps.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    ForEach(store.ignoredApps) { app in
                        IgnoredAppRow(app: app) {
                            withAnimation(.snappy(duration: 0.2).motionSafe) {
                                store.removeIgnoredApp(app.bundleIdentifier)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    addMenu
                }
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Nothing copied while one of these apps is in front is recorded.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
    }

    /// Running apps are the likeliest candidates, so they're one click away; anything
    /// else is a Choose… away.
    private var addMenu: some View {
        Menu {
            let running = runningAppCandidates
            if !running.isEmpty {
                Section("Running Apps") {
                    ForEach(running, id: \.bundleIdentifier) { app in
                        Button {
                            if let bundleID = app.bundleIdentifier {
                                store.addIgnoredApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
                            }
                        } label: {
                            if let icon = app.icon {
                                Label { Text(app.localizedName ?? "") } icon: { Image(nsImage: icon) }
                            } else {
                                Text(app.localizedName ?? "")
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Choose App\u{2026}", action: chooseApps)
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .fixedSize()
    }

    private var runningAppCandidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != nil
                    && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    && !store.isIgnored(bundleID: $0.bundleIdentifier!)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Ignore"
        panel.prompt = "Ignore"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            store.addIgnoredApp(bundleID: bundleID, name: name)
        }
    }
}

private struct IgnoredAppRow: View {
    let app: IgnoredApp
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(app.name)
            Spacer()
            Button(action: onRemove) {
                Label("Remove \(app.name)", systemImage: "minus.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop ignoring \(app.name)")
        }
        .contextMenu {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var icon: NSImage {
        ClippingThumbnails.appIcon(bundleID: app.bundleIdentifier) ?? NSWorkspace.shared.icon(for: .application)
    }
}
