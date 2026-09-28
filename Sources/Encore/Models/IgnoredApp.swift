import Foundation

/// An application whose clipboard changes should not be recorded.
struct IgnoredApp: Identifiable, Codable, Equatable, Hashable {
    var id: String { bundleIdentifier }
    var bundleIdentifier: String
    var name: String
}
