import SwiftUI
import AppKit

/// What's typed in a search field, matched the same way everywhere: the popover, History
/// (toolbar or inline field) and the highlighting in rows and the editor.
///
/// Forgiving, since search text is often pasted: surrounding spaces and newlines don't
/// count, case, accents and full-width forms are ignored ("cafe" finds "Café"), and
/// several words must all appear, in any order ("lisbon flight" finds "Your flight to
/// Lisbon").
struct SearchQuery {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    let terms: [String]
    private let folded: [String]

    init(_ text: String) {
        terms = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        folded = terms.map(Self.fold)
    }

    var isEmpty: Bool { terms.isEmpty }

    func matches(_ text: String) -> Bool {
        let haystack = Self.foldedText(text)
        return folded.allSatisfy { haystack.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: options, locale: nil)
    }

    /// Folding is the slow part of an accent-insensitive search, and every keystroke
    /// searches every clipping, so each text is folded once. NSString's hash reads only a
    /// text's ends and length, so finding a cached text costs next to nothing.
    private static let foldedCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    private static func foldedText(_ text: String) -> String {
        let key = text as NSString
        if let hit = foldedCache.object(forKey: key) { return hit as String }
        let value = fold(text)
        foldedCache.setObject(value as NSString, forKey: key, cost: value.utf8.count)
        return value
    }
}

extension Text {
    /// Builds a `Text` with every case-insensitive occurrence of `query` in `string`
    /// marked with the system find highlight, for search-match highlighting in list rows.
    ///
    /// Dark text on the find highlight, as Notes and Safari do: accent-coloured text
    /// vanished on a selected row's accent fill. Weight is left alone so matches don't
    /// reflow or re-truncate a row while the user types. With Differentiate Without Color
    /// on, matches are underlined too, so they don't rely on the highlight colour alone.
    static func highlighting(_ string: String, matching query: String) -> Text {
        let search = SearchQuery(query)
        guard !search.isEmpty else { return Text(string) }

        let underline = NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
        var attributed = AttributedString(string)
        for term in search.terms {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: term, options: SearchQuery.options) {
                attributed[range].backgroundColor = Color(nsColor: .findHighlightColor)
                attributed[range].foregroundColor = .black
                if underline { attributed[range].underlineStyle = .single }
                searchStart = range.upperBound
            }
        }
        return Text(attributed)
    }
}
