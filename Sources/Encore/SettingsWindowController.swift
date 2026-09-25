import AppKit
import SwiftUI

/// The Settings window, built the way macOS apps build it: a toolbar of icon tabs
/// (`NSTabViewController.tabStyle = .toolbar`) in a window with the `.preference` toolbar
/// style, which resizes to fit each pane. A SwiftUI `TabView` in a plain window renders
/// in-content tabs instead, which is not what Settings windows look like.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(store: ClipboardStore) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true

        func pane(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
            let host = NSHostingController(rootView: AnyView(view.environment(store)))
            host.sizingOptions = [.preferredContentSize]
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }

        tabs.addTabViewItem(pane("General", symbol: "gearshape", GeneralSettingsView()))
        tabs.addTabViewItem(pane("History", symbol: "clock.arrow.circlepath", HistorySettingsView()))
        tabs.addTabViewItem(pane("Intelligence", symbol: "sparkles", IntelligenceSettingsView()))
        tabs.addTabViewItem(pane("Privacy", symbol: "hand.raised", PrivacySettingsView()))
        tabs.addTabViewItem(pane("About", symbol: "info.circle", AboutSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
