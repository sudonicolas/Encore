import AppKit

/// Decodes and caches the small images shown in list rows, so scrolling doesn't re-decode
/// a clipping's PNG data or re-query Launch Services on every SwiftUI update.
@MainActor
enum ClippingThumbnails {
    private static let images = NSCache<NSUUID, NSImage>()
    /// App and file icons, keyed by bundle ID or `file:<path>`.
    private static let icons = NSCache<NSString, NSImage>()

    /// A downscaled copy of an image clipping, or nil for other kinds.
    static func image(for clipping: Clipping) -> NSImage? {
        guard clipping.kind == .image, let data = clipping.imageData else { return nil }
        let key = clipping.id as NSUUID
        if let cached = images.object(forKey: key) { return cached }
        guard let image = NSImage(data: data)?.resized(maxDimension: 96) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }

    /// The Finder icon for the first file of a file clipping.
    static func fileIcon(for clipping: Clipping) -> NSImage? {
        guard clipping.kind == .fileURL, let url = clipping.fileURLs?.first else { return nil }
        let key = "file:" + url.path as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: key)
        return icon
    }

    /// The icon of the app a clipping was copied from, if it's still installed.
    static func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}
