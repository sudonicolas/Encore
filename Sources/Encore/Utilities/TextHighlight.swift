import SwiftUI
import AppKit

extension Text {
    /// Builds a `Text` with every case-insensitive occurrence of `query` in `string`
    /// marked with the system find highlight, for search-match highlighting in list rows.
    ///
    /// Dark text on the find highlight, as Notes and Safari do: accent-coloured text
    /// vanished on a selected row's accent fill. Weight is left alone so matches don't
    /// reflow or re-truncate a row while the user types. With Differentiate Without Color
    /// on, matches are underlined too, so they don't rely on the highlight colour alone.
    static func highlighting(_ string: String, matching query: String) -> Text {
        guard !query.isEmpty else { return Text(string) }

        let underline = NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
        var attributed = AttributedString(string)
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: query, options: [.caseInsensitive]) {
            attributed[range].backgroundColor = Color(nsColor: .findHighlightColor)
            attributed[range].foregroundColor = .black
            if underline { attributed[range].underlineStyle = .single }
            searchStart = range.upperBound
        }
        return Text(attributed)
    }
}
