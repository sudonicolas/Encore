import SwiftUI
import AppKit

/// Encore's two accent colours: Apple blue fading into a soft lavender. Used sparingly —
/// only to mark things Apple Intelligence produced.
/// Everything else is the system's own colours, so Encore looks like part of macOS.
///
/// The blue is the system blue's hue, the lavender a muted, pastel purple. In Light Mode
/// both are a little deeper than their pastel selves so the sparkle glyph keeps 3:1
/// against the popover's glass; with Increase Contrast they go deeper still (4.5:1 and
/// up). See docs/COLOR.md.
enum Brand {
    static let blue = Color(nsColor: .adaptive(
        light: (0.124, 0.453, 0.824), dark: (0.429, 0.686, 0.970),
        lightHighContrast: (0.001, 0.322, 0.706), darkHighContrast: (0.638, 0.799, 0.968)
    ))
    static let lavender = Color(nsColor: .adaptive(
        light: (0.507, 0.430, 0.672), dark: (0.795, 0.731, 0.923),
        lightHighContrast: (0.395, 0.313, 0.558), darkHighContrast: (0.865, 0.816, 0.969)
    ))

    static let sparkle = LinearGradient(
        colors: [blue, lavender],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
