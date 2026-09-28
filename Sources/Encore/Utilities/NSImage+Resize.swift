import AppKit

extension NSImage {
    /// Returns a copy of the image scaled down so its largest dimension does not exceed `maxDimension`.
    /// Images already smaller than the limit are returned unchanged.
    ///
    /// Draws into an explicit Core Graphics bitmap context rather than using the older
    /// `lockFocus()`/`unlockFocus()` pair, which draws into the *current* graphics context and can
    /// silently produce a blank image when there isn't one — e.g. a menu bar app reacting to a
    /// copy while the display is asleep or locked, with no window on screen to focus. A bitmap
    /// context we allocate ourselves has no dependency on screen or window state.
    func resized(maxDimension: CGFloat) -> NSImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return self }

        let scale = maxDimension / largestSide
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let pixelWidth = max(1, Int(newSize.width.rounded()))
        let pixelHeight = max(1, Int(newSize.height.rounded()))

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return self }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let resizedImage = context.makeImage() else { return self }
        return NSImage(cgImage: resizedImage, size: newSize)
    }

    /// PNG-encoded data for this image, if it can be rasterized.
    ///
    /// Goes through `cgImage(forProposedRect:context:hints:)` rather than `tiffRepresentation`,
    /// which can return nil for images the pasteboard hands back with only a vector (PDF)
    /// representation — a common case when copying from apps like Preview or Keynote.
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }
}
