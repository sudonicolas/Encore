import Foundation

/// An amount of money read from a clipping like "$1,299.99", "€49,90" or "250 CHF".
struct MoneyAmount: Equatable, Hashable {
    let value: Decimal
    /// ISO 4217 code of a currency the European Central Bank publishes rates for.
    let currency: String
    /// Set when the symbol was ambiguous ("$", "¥") and a currency was assumed.
    let isAssumed: Bool
}

/// What a text clipping could be looked up as online. Only short clippings qualify: a
/// single word (dictionary and encyclopedia), a short name or phrase (encyclopedia), or an
/// amount of money (exchange rates).
struct LookupCandidates: Equatable {
    var money: MoneyAmount?
    var word: String?
    var topic: String?

    var isEmpty: Bool { money == nil && word == nil && topic == nil }

    init(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60, !trimmed.contains(where: \.isNewline) else { return }

        if let money = Self.money(in: trimmed) {
            self.money = money
        } else if trimmed.wholeMatch(of: Self.wordPattern) != nil {
            word = trimmed
            topic = trimmed
        } else if Self.isTopic(trimmed) {
            topic = trimmed
        }
    }

    // MARK: - Words and topics

    /// One word: letters, with inner apostrophes or hyphens ("don't", "self-aware").
    private static let wordPattern = #/\p{L}[\p{L}\p{M}'’-]{0,28}\p{L}/#

    /// Two to five words that look like the name of something ("Ada Lovelace", "New York
    /// City", "iPhone 17 Pro"), not an everyday phrase ("sounds good to me") or a sentence.
    private static func isTopic(_ text: String) -> Bool {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard (2...5).contains(words.count),
              text.rangeOfCharacter(from: CharacterSet(charactersIn: ",;:!?\"()[]{}<>/\\@#=+*_|~")) == nil,
              !text.hasSuffix(".") else { return false }
        let wellFormed = words.allSatisfy { word in
            word.first.map { $0.isLetter || $0.isNumber } == true
                && word.allSatisfy { $0.isLetter || $0.isNumber || "'’-.&".contains($0) }
        }
        // Names are capitalised: the first word and at least half of the other non-numeric
        // words must contain a capital letter.
        let lettered = words.filter { !$0.allSatisfy(\.isNumber) }
        let capitalised = lettered.filter { $0.contains(where: \.isUppercase) }
        return wellFormed
            && !lettered.isEmpty
            && words[0].contains(where: \.isUppercase)
            && capitalised.count * 2 >= lettered.count
    }

    // MARK: - Money

    /// Currencies with daily European Central Bank reference rates (what Frankfurter serves).
    static let supportedCurrencies: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"
    ]

    /// Currency symbols and their codes. `true` marks symbols shared by several currencies
    /// ("$" is also the Canadian or Australian dollar), where the likeliest is assumed.
    private static let symbols: [String: (code: String, assumed: Bool)] = [
        "$": ("USD", true), "US$": ("USD", false), "€": ("EUR", false), "£": ("GBP", false),
        "¥": ("JPY", true), "JP¥": ("JPY", false), "CN¥": ("CNY", false), "RMB": ("CNY", false),
        "₹": ("INR", false), "₩": ("KRW", false), "₪": ("ILS", false), "₺": ("TRY", false),
        "₱": ("PHP", false), "฿": ("THB", false), "R$": ("BRL", false), "zł": ("PLN", false),
        "Kč": ("CZK", false), "Ft": ("HUF", false), "Fr.": ("CHF", false), "A$": ("AUD", false),
        "AU$": ("AUD", false), "C$": ("CAD", false), "CA$": ("CAD", false), "NZ$": ("NZD", false),
        "HK$": ("HKD", false), "S$": ("SGD", false), "SG$": ("SGD", false), "MX$": ("MXN", false),
        "Rp": ("IDR", false), "RM": ("MYR", false), "lei": ("RON", false)
    ]

    private static let numberPattern = #/[0-9](?:[0-9.,' \u{00A0}\u{202F}]*[0-9])?/#

    static func money(in text: String) -> MoneyAmount? {
        guard text.count <= 32, let match = text.firstMatch(of: numberPattern) else { return nil }
        let prefix = text[..<match.range.lowerBound].trimmingCharacters(in: .whitespaces)
        let suffix = text[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
        // Exactly one side names the currency: "$5", "5 USD", but not "$5 USD" or "5".
        guard prefix.isEmpty != suffix.isEmpty,
              let currency = currency(for: prefix.isEmpty ? suffix : prefix),
              let value = decimal(from: String(match.output)), value > 0 else { return nil }
        return MoneyAmount(value: value, currency: currency.code, isAssumed: currency.assumed)
    }

    private static func currency(for token: String) -> (code: String, assumed: Bool)? {
        if let symbol = symbols[token] { return symbol }
        let code = token.uppercased()
        guard code.count == 3, supportedCurrencies.contains(code) else { return nil }
        return (code, false)
    }

    /// Reads "1,299.99", "1.299,99", "1 299,99", "1'299.99" and "49,90" alike: the last
    /// separator is the decimal point only when one or two digits follow it.
    private static func decimal(from raw: String) -> Decimal? {
        let digitsAndSeparators = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        var integerPart = digitsAndSeparators
        var fraction = ""
        if let last = digitsAndSeparators.lastIndex(where: { $0 == "." || $0 == "," }) {
            let tail = digitsAndSeparators[digitsAndSeparators.index(after: last)...]
            if (1...2).contains(tail.count) {
                integerPart = String(digitsAndSeparators[..<last])
                fraction = String(tail)
            }
        }
        let integerDigits = integerPart.filter(\.isNumber)
        guard !integerDigits.isEmpty, integerDigits.count <= 12 else { return nil }
        let normalized = fraction.isEmpty ? integerDigits : "\(integerDigits).\(fraction)"
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
