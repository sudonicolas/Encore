import SwiftUI
import AppKit

/// How large clippings are drawn in the popover and the History window, up to 200%.
/// Chosen in Settings → General, or with View → Make Text Bigger / Smaller (⌘+ / ⌘−).
///
/// macOS has no Dynamic Type: `dynamicTypeSize` and `@ScaledMetric` don't change Mac text
/// styles at all. So, like Mail, Notes and Books, Encore has its own text size. It
/// applies to content (clippings, lookups, Apple Intelligence results); Settings and
/// window chrome keep the system size, as they do in Apple's apps.
enum TextSize: Int, CaseIterable, Identifiable {
    case standard = 100
    case large = 115
    case larger = 130
    case extraLarge = 150
    case huge = 175
    case maximum = 200

    var id: Self { self }

    var scale: CGFloat { CGFloat(rawValue) / 100 }

    var title: String {
        self == .standard ? "\(rawValue)% (Default)" : "\(rawValue)%"
    }

    var bigger: TextSize? {
        Self.allCases.first { $0.rawValue > rawValue }
    }

    var smaller: TextSize? {
        Self.allCases.last { $0.rawValue < rawValue }
    }
}

extension EnvironmentValues {
    /// The Text Size multiplier for clipping content: 1 at the default size, 2 at 200%.
    @Entry var textScale: CGFloat = 1
}

extension Font {
    /// The system font for a text style, scaled by the Text Size setting. At the default
    /// size it's exactly `.system(style)`.
    static func scaled(_ style: Font.TextStyle, by scale: CGFloat) -> Font {
        guard scale != 1 else { return .system(style) }
        let base = NSFont.preferredFont(forTextStyle: style.appKitStyle)
        let scaled = NSFont(descriptor: base.fontDescriptor, size: (base.pointSize * scale).rounded()) ?? base
        return Font(scaled as CTFont)
    }
}

extension View {
    /// `.font(style)` that grows with the Text Size setting. Use for clipping content
    /// rather than `.font(_:)`.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, italic: Bool = false) -> some View {
        modifier(ScaledFont(style: style, weight: weight, italic: italic))
    }
}

private struct ScaledFont: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let italic: Bool
    @Environment(\.textScale) private var scale

    func body(content: Content) -> some View {
        var font = Font.scaled(style, by: scale)
        if let weight { font = font.weight(weight) }
        if italic { font = font.italic() }
        return content.font(font)
    }
}

extension Font.TextStyle {
    var appKitStyle: NSFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
