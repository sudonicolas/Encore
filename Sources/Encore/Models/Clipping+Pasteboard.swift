import AppKit

extension Clipping {
    /// Writes this clipping's content back onto the system pasteboard so it can be pasted.
    @MainActor
    func writeToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch kind {
        case .text:
            if let text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let imageData, let image = NSImage(data: imageData) {
                pasteboard.writeObjects([image])
            }
        case .fileURL:
            if let fileURLs, !fileURLs.isEmpty {
                pasteboard.writeObjects(fileURLs as [NSURL])
            }
        }
    }
}

extension Clipping {
    /// This clipping as a drag/copy item, for SwiftUI's copy and drag commands.
    @MainActor
    var itemProvider: NSItemProvider? {
        switch kind {
        case .text:
            return text.map { NSItemProvider(object: $0 as NSString) }
        case .image:
            guard let imageData, let image = NSImage(data: imageData) else { return nil }
            return NSItemProvider(object: image)
        case .fileURL:
            guard let url = fileURLs?.first else { return nil }
            return NSItemProvider(object: url as NSURL)
        }
    }
}
