import AppKit

extension Clipping {
    /// The colour a text clipping names, when it's nothing but a hex colour: "#E4572E",
    /// "#fa0" or "#E4572ECC" (with alpha). Rows show it as a swatch.
    var color: NSColor? {
        guard kind == .text, let text else { return nil }
        return NSColor(hexString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension NSColor {
    /// An sRGB colour from "#RGB", "#RRGGBB" or "#RRGGBBAA"; nil for anything else.
    convenience init?(hexString: String) {
        guard hexString.hasPrefix("#") else { return nil }
        var digits = String(hexString.dropFirst())
        guard [3, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 6 { digits += "FF" }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        func channel(_ shift: UInt32) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
        self.init(srgbRed: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }
}
