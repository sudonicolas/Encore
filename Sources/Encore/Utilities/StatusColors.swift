import SwiftUI
import AppKit

/// Colours for status text, icons and fills that meet Apple's contrast minimums — 4.5:1
/// for text, 3:1 for icons — in every appearance, including over the popover's glass.
///
/// The system's orange, red and green are tuned to be seen, not read: in Light Mode
/// orange text on white is about 2.2:1 and red about 3.5:1. These keep the same hues,
/// darker in Light Mode and lighter in Dark Mode, and go further still with Increase
/// Contrast on.
extension Color {
    /// Text and icons that warn, such as a deleted clipping about to be purged.
    static let warningText = Color(nsColor: .adaptive(
        light: (0.62, 0.27, 0.00), dark: (1.00, 0.62, 0.04),
        lightHighContrast: (0.52, 0.22, 0.00), darkHighContrast: (1.00, 0.74, 0.38)
    ))

    /// Text and icons for errors and blocked states.
    static let errorText = Color(nsColor: .adaptive(
        light: (0.77, 0.10, 0.08), dark: (1.00, 0.53, 0.50),
        lightHighContrast: (0.62, 0.05, 0.04), darkHighContrast: (1.00, 0.65, 0.62)
    ))

    /// Icons that confirm something is working.
    static let successIcon = Color(nsColor: .adaptive(
        light: (0.00, 0.50, 0.18), dark: (0.19, 0.82, 0.35),
        lightHighContrast: (0.00, 0.40, 0.14), darkHighContrast: (0.45, 0.92, 0.55)
    ))

    /// Fill behind white text on a destructive confirm button (at least 5.7:1).
    static let destructiveFill = Color(nsColor: .adaptive(
        light: (0.78, 0.12, 0.10), dark: (0.78, 0.12, 0.10),
        lightHighContrast: (0.62, 0.05, 0.04), darkHighContrast: (0.62, 0.05, 0.04)
    ))

    /// Swipe-action fills behind a white label and icon: Pin (orange) and Restore (blue).
    /// The system orange and blue give white only 2.2:1 and 4:1.
    static let pinActionFill = Color(nsColor: .adaptive(
        light: (0.72, 0.36, 0.00), dark: (0.72, 0.36, 0.00),
        lightHighContrast: (0.60, 0.28, 0.00), darkHighContrast: (0.60, 0.28, 0.00)
    ))
    static let restoreActionFill = Color(nsColor: .adaptive(
        light: (0.00, 0.40, 0.85), dark: (0.00, 0.40, 0.85),
        lightHighContrast: (0.00, 0.32, 0.72), darkHighContrast: (0.00, 0.32, 0.72)
    ))

    /// Fill and text for small accent badges ("Copied"): the colours macOS uses for a
    /// selected list row, which keep white text readable whatever the accent colour —
    /// unlike the raw accent (4:1 for the default blue, far less for yellow).
    static let accentBadgeFill = Color(nsColor: .selectedContentBackgroundColor)
    static let accentBadgeText = Color(nsColor: .alternateSelectedControlTextColor)
}

extension NSColor {
    typealias RGB = (red: CGFloat, green: CGFloat, blue: CGFloat)

    /// A colour that follows Light and Dark Mode, and Increase Contrast in each.
    static func adaptive(light: RGB, dark: RGB, lightHighContrast: RGB, darkHighContrast: RGB) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
            ])
            let rgb: RGB
            switch match {
            case .darkAqua: rgb = dark
            case .accessibilityHighContrastAqua: rgb = lightHighContrast
            case .accessibilityHighContrastDarkAqua: rgb = darkHighContrast
            default: rgb = light
            }
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
    }
}
