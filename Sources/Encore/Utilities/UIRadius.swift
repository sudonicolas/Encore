import SwiftUI

/// Corner geometry tokens for the macOS 26+ design language.
///
/// Liquid Glass UI is built from concentric shapes: anything nested inside a rounded
/// container (a window, the popover, a grouped section) takes its radius from that
/// container minus its inset, so curves stay parallel. Standalone controls — buttons,
/// search fields — are capsules. Fixed radii are only a floor for shapes that sit too
/// far from a container corner to derive one.
enum UIRadius {
    /// Floor for concentric row highlights that aren't near a container corner.
    static let rowMinimum: CGFloat = 8
    /// Image previews and other content cards.
    static let card: CGFloat = 12
    /// Small thumbnails inside list rows.
    static let thumbnail: CGFloat = 6
}

extension Shape where Self == ConcentricRectangle {
    /// Row highlight: concentric with the enclosing container, never tighter than the floor.
    static var row: ConcentricRectangle {
        .rect(corners: .concentric(minimum: .fixed(UIRadius.rowMinimum)), isUniform: true)
    }
}

extension Shape where Self == RoundedRectangle {
    static func continuous(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
