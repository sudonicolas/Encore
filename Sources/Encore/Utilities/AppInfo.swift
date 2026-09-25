import Foundation

/// The app's identity, read from Info.plist so the name lives in one place.
enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Encore"

    static let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

    static let repositoryURL = URL(string: "https://github.com/sudonicolas/encore")!

    /// Sent with online lookups. Wikimedia asks API clients to identify themselves with a
    /// way to reach the developer.
    static let userAgent = "Encore/\(shortVersion) (+\(repositoryURL.absoluteString))"
}
