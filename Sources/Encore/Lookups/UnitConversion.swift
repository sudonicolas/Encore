import Foundation

/// A measurement read from a clipping like "5 lb", "72°F", "12.5 km", "6'2\"" or "3 mph",
/// and what it comes to in the units people usually convert it to. Everything here is
/// offline: nothing is sent anywhere.
///
/// Clippings are pasted from anywhere, so the reading is forgiving: any case and spacing
/// ("5KG", "5 kg", "5\u{00A0}kg"), labels and wrapping ("Weight: 5 kg", "(5 kg)"),
/// European decimals and thousands separators, fractions ("1 1/2 cups", "½ lb"), common
/// misspellings ("ibs", "celcius"), and two-part amounts ("5 lb 3 oz", "5'10", "1 m 80 cm").
/// It still turns down anything that is not plainly one amount, rather than guess.
struct UnitAmount: Equatable, Hashable {
    enum Kind: String { case mass, length, temperature, volume, speed }

    /// A unit Encore knows, with the spellings it reads and how it is shown.
    struct Unit: Hashable {
        let kind: Kind
        /// Short form for display: "kg", "°F".
        let symbol: String
        /// Spoken form for VoiceOver: "kilograms".
        let name: String
        /// Whether this is a metric (or SI) unit, so conversions lead with the other system.
        let isMetric: Bool
        fileprivate let foundation: Dimension

        /// "1 cup", "2 cups": the two symbols that are words agree with their number.
        func symbol(for value: Double) -> String {
            guard UnitAmount.format(value) == "1" else { return symbol }
            switch symbol {
            case "cups": return "cup"
            case "tons": return "ton"
            default: return symbol
            }
        }

        static func == (lhs: Unit, rhs: Unit) -> Bool { lhs.symbol == rhs.symbol && lhs.kind == rhs.kind }
        func hash(into hasher: inout Hasher) { hasher.combine(symbol); hasher.combine(kind) }
    }

    let value: Double
    let unit: Unit
    /// How a two-part amount reads, "5 ft 10 in", where `value` and `unit` hold its total.
    var original: String?

    var kind: Kind { unit.kind }

    struct Conversion: Equatable, Identifiable {
        let unit: Unit
        let value: Double
        var id: String { unit.symbol }

        /// "11.02", "1,234.5", "-40": enough digits to be useful, not a long tail.
        var formatted: String { UnitAmount.format(value) }
        var symbol: String { unit.symbol(for: value) }
        var copyText: String { "\(formatted) \(symbol)" }
        var spoken: String { "\(formatted) \(unit.name)" }
    }

    /// The same amount in up to four other units: the other system's first, and only
    /// units it reads well in ("2.27 kg", not "0.0018 km" or "2,267,960 mg").
    var conversions: [Conversion] {
        let source = Measurement(value: value, unit: unit.foundation)
        let siblings = Self.allUnits.filter { $0.kind == kind && $0 != unit }
        let ordered = Self.targets(for: kind).compactMap { symbol in siblings.first { $0.symbol == symbol } }
        let all = (ordered.filter { $0.isMetric != unit.isMetric } + ordered.filter { $0.isMetric == unit.isMetric })
            .map { Conversion(unit: $0, value: source.converted(to: $0.foundation).value) }
        // Temperatures read well at any size (-40, 233.15), and zero is zero everywhere.
        let readable = all.filter {
            kind == .temperature || value == 0 || (0.5..<10_000).contains(abs($0.value))
        }
        guard readable.count < 2 else { return Array(readable.prefix(4)) }
        // Too few read well: top up with whichever come closest to a few hundred.
        let rest = all.filter { c in !readable.contains(c) }
            .sorted { abs(log10(max(abs($0.value), 1e-9)) - 2) < abs(log10(max(abs($1.value), 1e-9)) - 2) }
        return Array((readable + rest).prefix(2))
    }

    var displayText: String { original ?? "\(Self.format(value)) \(unit.symbol(for: value))" }
    var spokenText: String {
        original.map { "\($0), \(Self.format(value)) \(unit.name)" } ?? "\(Self.format(value)) \(unit.name)"
    }

    // MARK: - Formatting

    static func format(_ value: Double) -> String {
        let magnitude = abs(value)
        let style: FloatingPointFormatStyle<Double>
        if magnitude == 0 {
            style = .number.precision(.fractionLength(0))
        } else if magnitude < 0.01 {
            style = .number.precision(.significantDigits(2))
        } else if magnitude >= 1000 {
            style = .number.precision(.fractionLength(0...1))
        } else {
            style = .number.precision(.fractionLength(0...2))
        }
        // A tiny negative that rounds to zero must not print as "-0".
        let text = value.formatted(style)
        return text == "-0" ? "0" : text
    }

    // MARK: - Reading

    /// Nil unless the whole text is one amount: a number and a unit, or two of them of the
    /// same kind ("5 ft 10 in"), with nothing else but a label or punctuation around it.
    static func parse(_ text: String) -> UnitAmount? {
        guard text.count <= 64, let cleaned = normalized(text), !cleaned.isEmpty else { return nil }

        var parts: [(value: Double, unit: Unit)] = []
        var rest = Substring(cleaned)
        while !rest.isEmpty {
            guard parts.count < 2, let match = rest.prefixMatch(of: partPattern) else { return nil }
            let rawUnit = match.output.2.map(String.init) ?? ""
            guard let value = number(from: String(match.output.1)) else { return nil }
            if rawUnit.isEmpty {
                // A bare number may only follow feet: 5'10, 5 ft 10, 5ft10.
                guard parts.count == 1, parts[0].unit.symbol == "ft", let inch = unitTable["in"] else { return nil }
                parts.append((value, inch))
            } else {
                guard let unit = unit(named: rawUnit) else { return nil }
                parts.append((value, unit))
            }
            rest = rest[match.range.upperBound...].drop(while: \.isWhitespace)
        }

        switch parts.count {
        case 1:
            let (value, unit) = parts[0]
            guard isPlausible(value, unit) else { return nil }
            return UnitAmount(value: value, unit: unit)
        case 2:
            // "5 lb 3 oz": same kind, bigger unit first, a whole first number, and no
            // temperatures or speeds, which are never written that way.
            let (bigValue, big) = parts[0], (smallValue, small) = parts[1]
            guard big.kind == small.kind, big != small,
                  [.mass, .length, .volume].contains(big.kind),
                  bigValue >= 0, smallValue >= 0,
                  bigValue == bigValue.rounded(),
                  Measurement(value: 1, unit: big.foundation).converted(to: small.foundation).value > 1
            else { return nil }
            let total = Measurement(value: bigValue, unit: big.foundation).converted(to: small.foundation).value + smallValue
            return UnitAmount(
                value: total, unit: small,
                original: "\(format(bigValue)) \(big.symbol) \(format(smallValue)) \(small.symbol)"
            )
        default:
            return nil
        }
    }

    /// Below absolute zero, or a negative weight or distance, is not a measurement.
    private static func isPlausible(_ value: Double, _ unit: Unit) -> Bool {
        if unit.kind == .temperature {
            let kelvin = Measurement(value: value, unit: unit.foundation).converted(to: UnitTemperature.kelvin).value
            return kelvin >= 0
        }
        return value >= 0
    }

    /// One amount: a number (whole, decimal, grouped or a fraction), optional spacing or a
    /// hyphen ("5-kg"), and its unit, which runs up to the next number or the end. The
    /// unit may be empty only for the inches of "5'10".
    private static let partPattern = #/([-+]?(?:\d+ \d+/\d+|\d+/\d+|\d{1,3}(?: \d{3})+(?:[.,]\d+)?|\d[\d.,]*\d|\d))\s*-?\s*([a-z°'"µμ/][a-z°'"µμ/. ]*?)?\s*(?=\d|[-+]\d|$)/#

    /// Lowercased, one kind of space, typographic marks made plain, and the clutter people
    /// copy along trimmed away. Nil when the text has something no amount would contain.
    private static func normalized(_ text: String) -> String? {
        var s = text
        // ½ and friends, before compatibility mapping turns "1½" into "11⁄2".
        let vulgar: [Character: String] = [
            "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4", "⅕": "1/5",
            "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6", "⅛": "1/8",
            "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
        ]
        s = s.reduce(into: "") { out, character in
            if let fraction = vulgar[character] {
                // "1½" is one and a half: keep the whole number apart from the fraction.
                if let last = out.last, last.isNumber { out.append(" ") }
                out.append(fraction)
            } else {
                out.append(character)
            }
        }
        // Degree look-alikes first: compatibility mapping turns the ordinal "º" into "o".
        s = s.replacingOccurrences(of: "º", with: "°").replacingOccurrences(of: "˚", with: "°")
        // Full-width digits and letters, ℃ and ℉.
        s = s.precomposedStringWithCompatibilityMapping
        let replacements: [(String, String)] = [
            ("\u{2044}", "/"), ("\u{2215}", "/"),                       // fraction slashes
            ("\u{2212}", "-"), ("\u{2013}", "-"), ("\u{2014}", "-"),    // minus, en and em dashes
            ("\u{2032}", "'"), ("\u{2019}", "'"), ("\u{2018}", "'"),    // prime, curly apostrophes
            ("\u{2033}", "\""), ("\u{201D}", "\""), ("\u{201C}", "\""), // double prime, curly quotes
            ("''", "\"")
        ]
        for (from, to) in replacements { s = s.replacingOccurrences(of: from, with: to) }
        // "5M" and "5 M" are millions far more often than meters.
        if s.contains(#/\d\s*M\s*$/#) { return nil }
        s = s.lowercased()
        // Every kind of space and tab as one plain space.
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")

        // A label ("Weight:", "Temp -"), and words that soften an amount ("about", "~").
        s = s.replacing(#/^[a-z][a-z ]{0,24}?\s*[:=]\s*/#, with: "")
        s = s.replacing(#/^(?:~|≈|approx\.?|approximately|about|around|ca\.?|circa)\s*/#, with: "")
        // Wrapping brackets or quotes, and trailing punctuation. An amount never starts
        // with a quote, so a leading one is wrapping; a trailing one alone is inches (5'10").
        for _ in 0..<3 {
            guard let first = s.first, let last = s.last, s.count >= 2 else { break }
            if (first == "(" && last == ")") || (first == "[" && last == "]") {
                s = String(s.dropFirst().dropLast())
            } else if first == "\"" || first == "'" {
                s.removeFirst()
                if s.last == first { s.removeLast() }
            } else {
                break
            }
            s = s.trimmingCharacters(in: .whitespaces)
        }
        while let last = s.last, ".,;:!?".contains(last) { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        // ".5 kg" is half a kilo.
        if s.first == ".", s.dropFirst().first?.isNumber == true { s = "0" + s }
        guard s.first.map({ $0.isNumber || "-+".contains($0) }) == true else { return nil }
        return s
    }

    /// The unit a spelling means. Spacing, dots and "per" are tidied first, so "m.p.h.",
    /// "km / h", "km per hour" and "fl. oz." all find their unit.
    private static func unit(named raw: String) -> Unit? {
        var name = raw.trimmingCharacters(in: .whitespaces)
        name = name.replacingOccurrences(of: ".", with: "")
        name = name.replacing(#/\s*\/\s*/#, with: "/")
        name = name.replacing(#/\s+per\s+/#, with: "/")
        name = name.replacing(#/^°\s+/#, with: "°")
        name = name.split(separator: " ").joined(separator: " ")
        return unitTable[name]
    }

    /// "1,299.5", "1.299,5", "12,5", "1 299", "1 1/2", "3/4": the last separator is the
    /// decimal point unless it is a comma with exactly three digits after it.
    static func number(from raw: String) -> Double? {
        var text = raw
        let negative = text.hasPrefix("-")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))

        if let fraction = text.wholeMatch(of: #/(?:(\d+) )?(\d+)/(\d+)/#) {
            let whole = fraction.output.1.flatMap { Double($0) } ?? 0
            guard let top = Double(fraction.output.2), let bottom = Double(fraction.output.3), bottom > 0 else { return nil }
            let value = whole + top / bottom
            return negative ? -value : value
        }

        text = text.replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }
        let dots = text.filter { $0 == "." }.count
        let commas = text.filter { $0 == "," }.count
        if dots > 0 && commas > 0 {
            let lastDot = text.lastIndex(of: ".")!, lastComma = text.lastIndex(of: ",")!
            let decimal: Character = lastDot > lastComma ? "." : ","
            let group: Character = decimal == "." ? "," : "."
            text = text.filter { $0 != group }.map { $0 == decimal ? "." : $0 }.reduce("") { $0 + String($1) }
        } else if commas > 0 {
            let tail = text.split(separator: ",", omittingEmptySubsequences: false).last ?? ""
            text = commas == 1 && tail.count != 3
                ? text.replacingOccurrences(of: ",", with: ".")
                : text.replacingOccurrences(of: ",", with: "")
        } else if dots > 1 {
            text = text.replacingOccurrences(of: ".", with: "")
        }
        guard let value = Double(text), value.isFinite, value < 1e15 else { return nil }
        return negative ? -value : value
    }

    // MARK: - Units

    private struct Definition {
        let kind: Kind, symbol: String, name: String, metric: Bool, unit: Dimension, spellings: [String]
    }

    /// Every unit, with every spelling Encore reads for it (lowercase, without dots).
    ///
    /// Deliberately missing: a bare "k" (kilo-what?), "t" (tonne, or teaspoon in a recipe),
    /// "c" as cups (it reads as Celsius), and "degrees" without a scale.
    private static let definitions: [Definition] = [
        // Mass
        .init(kind: .mass, symbol: "mg", name: "milligrams", metric: true, unit: UnitMass.milligrams,
              spellings: ["mg", "mgs", "milligram", "milligrams", "milligramme", "milligrammes"]),
        .init(kind: .mass, symbol: "g", name: "grams", metric: true, unit: UnitMass.grams,
              spellings: ["g", "gr", "grm", "grms", "gm", "gms", "gram", "grams", "gramme", "grammes"]),
        .init(kind: .mass, symbol: "kg", name: "kilograms", metric: true, unit: UnitMass.kilograms,
              spellings: ["kg", "kgs", "kgm", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes", "kilogrm"]),
        .init(kind: .mass, symbol: "t", name: "metric tons", metric: true, unit: UnitMass.metricTons,
              spellings: ["tonne", "tonnes", "metric ton", "metric tons", "mt"]),
        .init(kind: .mass, symbol: "oz", name: "ounces", metric: false, unit: UnitMass.ounces,
              spellings: ["oz", "ozs", "ounce", "ounces", "onces"]),
        .init(kind: .mass, symbol: "lb", name: "pounds", metric: false, unit: UnitMass.pounds,
              spellings: ["lb", "lbs", "ib", "ibs", "lbm", "pound", "pounds", "pnd", "pnds"]),
        .init(kind: .mass, symbol: "st", name: "stone", metric: false, unit: UnitMass.stones,
              spellings: ["st", "stone", "stones"]),
        .init(kind: .mass, symbol: "tons", name: "US tons", metric: false, unit: UnitMass.shortTons,
              spellings: ["ton", "tons", "short ton", "short tons"]),
        // Length
        .init(kind: .length, symbol: "mm", name: "millimeters", metric: true, unit: UnitLength.millimeters,
              spellings: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"]),
        .init(kind: .length, symbol: "cm", name: "centimeters", metric: true, unit: UnitLength.centimeters,
              spellings: ["cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres"]),
        .init(kind: .length, symbol: "m", name: "meters", metric: true, unit: UnitLength.meters,
              spellings: ["m", "mtr", "mtrs", "meter", "meters", "metre", "metres"]),
        .init(kind: .length, symbol: "km", name: "kilometers", metric: true, unit: UnitLength.kilometers,
              spellings: ["km", "kms", "klm", "kilometer", "kilometers", "kilometre", "kilometres", "kilometer"]),
        .init(kind: .length, symbol: "in", name: "inches", metric: false, unit: UnitLength.inches,
              spellings: ["in", "ins", "inch", "inches", "inchs", "\""]),
        .init(kind: .length, symbol: "ft", name: "feet", metric: false, unit: UnitLength.feet,
              spellings: ["ft", "fts", "foot", "feet", "feets", "'"]),
        .init(kind: .length, symbol: "yd", name: "yards", metric: false, unit: UnitLength.yards,
              spellings: ["yd", "yds", "yard", "yards"]),
        .init(kind: .length, symbol: "mi", name: "miles", metric: false, unit: UnitLength.miles,
              spellings: ["mi", "mis", "mile", "miles"]),
        // Temperature
        .init(kind: .temperature, symbol: "°C", name: "degrees Celsius", metric: true, unit: UnitTemperature.celsius,
              spellings: ["°c", "c", "c°", "degc", "deg c", "degree c", "degrees c", "celsius", "celcius", "celsuis",
                          "centigrade", "°celsius", "°celcius", "deg celsius", "degree celsius", "degrees celsius",
                          "degrees celcius", "degree celcius"]),
        .init(kind: .temperature, symbol: "°F", name: "degrees Fahrenheit", metric: false, unit: UnitTemperature.fahrenheit,
              spellings: ["°f", "f", "f°", "degf", "deg f", "degree f", "degrees f", "fahrenheit", "farenheit",
                          "fahrenheight", "farenheight", "fahrenhiet", "°fahrenheit", "°farenheit", "deg fahrenheit",
                          "degree fahrenheit", "degrees fahrenheit", "degrees farenheit", "degree farenheit"]),
        .init(kind: .temperature, symbol: "K", name: "kelvin", metric: true, unit: UnitTemperature.kelvin,
              spellings: ["kelvin", "kelvins", "°k", "deg k", "degrees kelvin"]),
        // Volume (US customary for the non-metric ones)
        .init(kind: .volume, symbol: "ml", name: "milliliters", metric: true, unit: UnitVolume.milliliters,
              spellings: ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres", "cc"]),
        .init(kind: .volume, symbol: "L", name: "liters", metric: true, unit: UnitVolume.liters,
              spellings: ["l", "lt", "ltr", "ltrs", "liter", "liters", "litre", "litres", "lts"]),
        .init(kind: .volume, symbol: "fl oz", name: "fluid ounces", metric: false, unit: UnitVolume.fluidOunces,
              spellings: ["fl oz", "floz", "fl ozs", "fluid oz", "fluid ounce", "fluid ounces", "fl ounce", "fl ounces"]),
        .init(kind: .volume, symbol: "tsp", name: "teaspoons", metric: false, unit: UnitVolume.teaspoons,
              spellings: ["tsp", "tsps", "teaspoon", "teaspoons"]),
        .init(kind: .volume, symbol: "tbsp", name: "tablespoons", metric: false, unit: UnitVolume.tablespoons,
              spellings: ["tbsp", "tbsps", "tbs", "tbl", "tablespoon", "tablespoons"]),
        // Foundation's `cups` is a 240 ml metric cup; recipes mean the US cup, 236.59 ml.
        .init(kind: .volume, symbol: "cups", name: "cups", metric: false, unit: usCup,
              spellings: ["cup", "cups"]),
        .init(kind: .volume, symbol: "pt", name: "pints", metric: false, unit: UnitVolume.pints,
              spellings: ["pt", "pts", "pint", "pints"]),
        .init(kind: .volume, symbol: "qt", name: "quarts", metric: false, unit: UnitVolume.quarts,
              spellings: ["qt", "qts", "quart", "quarts"]),
        .init(kind: .volume, symbol: "gal", name: "gallons", metric: false, unit: UnitVolume.gallons,
              spellings: ["gal", "gals", "gallon", "gallons"]),
        // Speed
        .init(kind: .speed, symbol: "km/h", name: "kilometers per hour", metric: true, unit: UnitSpeed.kilometersPerHour,
              spellings: ["km/h", "km/hr", "km/hour", "kmh", "kmph", "kph", "kmhr", "kilometers/hour", "kilometres/hour",
                          "kilometer/hour", "kilometre/hour", "kilometers/hr", "kilometres/hr"]),
        .init(kind: .speed, symbol: "mph", name: "miles per hour", metric: false, unit: UnitSpeed.milesPerHour,
              spellings: ["mph", "mi/h", "mi/hr", "mi/hour", "miles/hour", "mile/hour", "miles/hr", "mile/hr"]),
        .init(kind: .speed, symbol: "m/s", name: "meters per second", metric: true, unit: UnitSpeed.metersPerSecond,
              spellings: ["m/s", "m/sec", "m/second", "mps", "meters/second", "metres/second", "meter/second",
                          "metre/second", "meters/sec", "metres/sec"]),
        .init(kind: .speed, symbol: "kn", name: "knots", metric: false, unit: UnitSpeed.knots,
              spellings: ["kn", "kt", "kts", "knot", "knots"])
    ]

    /// The US customary cup: half a US pint, exactly 0.2365882365 liters.
    private static let usCup = UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.2365882365))

    private static let allUnits: [Unit] = definitions.map {
        Unit(kind: $0.kind, symbol: $0.symbol, name: $0.name, isMetric: $0.metric, foundation: $0.unit)
    }

    private static let unitTable: [String: Unit] = {
        var table: [String: Unit] = [:]
        for (definition, unit) in zip(definitions, allUnits) {
            for spelling in definition.spellings { table[spelling] = unit }
        }
        return table
    }()

    /// Which units a kind is shown in, most useful first.
    private static func targets(for kind: Kind) -> [String] {
        switch kind {
        case .mass: return ["kg", "lb", "g", "oz", "st"]
        case .length: return ["km", "mi", "m", "ft", "cm", "in", "yd"]
        case .temperature: return ["°C", "°F", "K"]
        case .volume: return ["L", "gal", "ml", "fl oz", "cups", "tbsp", "tsp"]
        case .speed: return ["km/h", "mph", "m/s", "kn"]
        }
    }
}
