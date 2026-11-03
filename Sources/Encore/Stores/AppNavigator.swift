import Combine
import Foundation

/// Cross-surface navigation: lets the popover, the status item's menu and the History
/// window hand off to each other (e.g. "Show all in History" carries the search along)
/// without the SwiftUI views knowing about AppKit window management.
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()

    /// Sidebar selection in the History window.
    @Published var historySection: HistorySection = .all
    /// Search text in the History window.
    @Published var historySearch = ""
    /// Whether the History window draws its search field and actions in its columns
    /// rather than the toolbar. Only ever true on macOS 13, and only if SwiftUI did not
    /// give the window a toolbar there (see `AppDelegate.showHistoryWindow`).
    @Published var historyUsesInlineToolbar = false

    // Wired up by AppDelegate, which owns the windows and the popover.
    var openHistoryWindow: () -> Void = {}
    var openSettingsWindow: () -> Void = {}
    var closePopover: () -> Void = {}

    private init() {}

    func showHistory(_ section: HistorySection = .all, search: String = "") {
        historySection = section
        historySearch = search
        closePopover()
        openHistoryWindow()
    }

    func showSettings() {
        closePopover()
        openSettingsWindow()
    }
}

/// Sidebar sections of the History window.
enum HistorySection: String, Hashable, CaseIterable, Identifiable {
    case all, pinned, text, images, files, recentlyDeleted

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All Clippings"
        case .pinned: return "Pinned"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        case .recentlyDeleted: return "Recently Deleted"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "doc.on.clipboard"
        case .pinned: return "pin"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .files: return "doc"
        case .recentlyDeleted: return "trash"
        }
    }

    func includes(_ clipping: Clipping) -> Bool {
        switch self {
        case .all, .recentlyDeleted: return true
        case .pinned: return clipping.isPinned
        case .text: return clipping.kind == .text
        case .images: return clipping.kind == .image
        case .files: return clipping.kind == .fileURL
        }
    }
}

extension Notification.Name {
    /// Posted right before the menu bar popover opens, so it can reset to a fresh state.
    static let clipboardPopoverWillShow = Notification.Name("clipboardPopoverWillShow")
    /// Posted after a new clipping is recorded from the pasteboard.
    static let clipboardDidRecordClipping = Notification.Name("clipboardDidRecordClipping")
}
