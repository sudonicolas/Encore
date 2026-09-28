import Foundation

/// The kind of content a single clipping holds.
enum ClippingKind: String, Codable {
    case text
    case image
    case fileURL
}

/// A single entry in the clipboard history.
struct Clipping: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClippingKind
    var text: String?
    var imageData: Data?
    var fileURLs: [URL]?
    var sourceAppName: String?
    var sourceBundleID: String?
    var createdAt: Date
    var isPinned: Bool
    /// Set when the clipping is moved to Recently Deleted; nil while active.
    var deletedAt: Date?
    /// A short title written by the on-device model for long text clippings (see
    /// `SmartTitler`); nil until one has been generated.
    var smartTitle: String?

    init(
        id: UUID = UUID(),
        kind: ClippingKind,
        text: String? = nil,
        imageData: Data? = nil,
        fileURLs: [URL]? = nil,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        deletedAt: Date? = nil,
        smartTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.fileURLs = fileURLs
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.deletedAt = deletedAt
        self.smartTitle = smartTitle
    }

    /// Short human-readable title shown in list rows.
    var previewTitle: String {
        switch kind {
        case .text:
            return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            return text ?? "Image"
        case .fileURL:
            return fileURLs?.map(\.lastPathComponent).joined(separator: ", ") ?? "File"
        }
    }

    /// The preview title on one line, for a second line under an Apple Intelligence title:
    /// "Hi team, Quick reminder that…" rather than just "Hi team,".
    var singleLinePreview: String {
        previewTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Text used when filtering with the search field. Includes the generated title, so a
    /// clipping can be found by what it is as well as by what it says.
    var searchableText: String {
        switch kind {
        case .text:
            guard let smartTitle else { return text ?? "" }
            return smartTitle + "\n" + (text ?? "")
        case .image:
            return text ?? "image"
        case .fileURL:
            return fileURLs?.map(\.lastPathComponent).joined(separator: " ") ?? ""
        }
    }

    /// Whether two clippings hold the same content, for de-duplicating repeat copies.
    /// Compares the content itself: an image's label is only its size, so two different
    /// screenshots of the same size must not count as the same clipping.
    func hasSameContent(as other: Clipping) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return text == other.text && imageData == other.imageData
        case .fileURL: return fileURLs == other.fileURLs
        }
    }
}

extension Clipping {
    /// Generic name for this clipping's kind, used when there's no source app to show.
    var kindTitle: String {
        switch kind {
        case .text: return "Text"
        case .image: return "Image"
        case .fileURL: return (fileURLs?.count ?? 0) > 1 ? "Files" : "File"
        }
    }

    /// SF Symbol for this clipping's kind.
    var kindSymbol: String {
        switch kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .fileURL: return "doc"
        }
    }
}

// MARK: - Accessibility

extension Clipping {
    /// What VoiceOver says for this clipping in a list. A row shows a line or two, not a
    /// whole document, so long text is cut to its opening; an image's stored label,
    /// "Image (1200×800)", is spoken as "Image, 1200 by 800 pixels".
    ///
    /// - Parameter smartTitle: The Apple Intelligence title, when titles are shown.
    func accessibilityTitle(smartTitle: String?) -> String {
        if let smartTitle, !smartTitle.isEmpty { return smartTitle }
        switch kind {
        case .image:
            if let size = (text ?? "").firstMatch(of: #/(\d+)\s*×\s*(\d+)/#) {
                return "Image, \(size.1) by \(size.2) pixels"
            }
            return "Image"
        case .fileURL:
            return previewTitle
        case .text:
            let line = singleLinePreview
            if line.isEmpty { return "Empty clipping" }
            return line.count <= 160 ? line : String(line.prefix(160)) + "\u{2026}"
        }
    }

    /// The kind, when the title doesn't already say it: "File" or "Files". Text needs no
    /// label, and an image's title starts with "Image".
    var accessibilityKind: String? {
        kind == .fileURL ? kindTitle : nil
    }
}

extension Array where Element == String? {
    /// The non-empty parts joined for VoiceOver: "Pinned, Safari, 5 minutes ago". Commas
    /// give a natural pause; the "·" separators drawn on screen are read as "dot".
    var accessibilityJoined: String {
        compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
