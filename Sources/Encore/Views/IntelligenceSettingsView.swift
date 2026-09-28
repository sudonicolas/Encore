import SwiftUI

/// Settings for the features that go beyond recording: Apple Intelligence (on device) and
/// online lookups (free web services, sent only what's needed).
struct IntelligenceSettingsView: View {
    @Environment(ClipboardStore.self) private var store
    @State private var status = Intelligence.status

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                LabeledContent("Status") {
                    Label {
                        Text(status.summary)
                    } icon: {
                        Image(systemName: status == .available ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(status == .available ? Color.successIcon : Color.warningText)
                    }
                }
                if status != .available {
                    LabeledContent {
                        if status == .notEnabled {
                            Button("Open Settings\u{2026}", action: Intelligence.openSettings)
                        }
                    } label: {
                        Text(status.explanation)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Title long clippings automatically", isOn: $store.generatesSmartTitles)
                    .disabled(status == .unsupported)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Long clippings get a short title, and the \(Image(systemName: "sparkles")) menu in a clipping can proofread, rewrite, summarize or explain it. It all runs on this Mac \u{2014} nothing is sent anywhere.")
            }

            Section {
                Toggle("Offer online lookups", isOn: $store.offersOnlineLookups)
            } header: {
                Text("Online Lookups")
            } footer: {
                Text("Short clippings can be looked up with free services that need no account: definitions from Wiktionary, summaries from Wikipedia, and European Central Bank exchange rates from Frankfurter. A word or phrase is sent only when you click Define or Wikipedia; for exchange rates, only the currency is sent.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520, height: status == .available ? 360 : 410)
        .onAppear { status = Intelligence.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings, where Apple Intelligence may have been turned on.
            status = Intelligence.status
            if status == .available { SmartTitler.shared.processBacklog() }
        }
    }
}
