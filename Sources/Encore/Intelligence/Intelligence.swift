import AppKit
import FoundationModels

/// Apple Intelligence — the on-device Foundation Models framework: whether it can run on
/// this Mac right now, and how to explain it when it can't. Everything Encore does with it
/// happens on device; no clipping is sent anywhere.
enum Intelligence {
    enum Status: Equatable {
        case available
        /// Apple Intelligence is turned off in System Settings.
        case notEnabled
        /// Turned on, but the model is still downloading or preparing.
        case notReady
        /// This Mac can't run Apple Intelligence.
        case unsupported

        var summary: String {
            switch self {
            case .available: return "Ready"
            case .notEnabled: return "Turned off"
            case .notReady: return "Getting ready"
            case .unsupported: return "Not available on this Mac"
            }
        }

        var explanation: String {
            switch self {
            case .available:
                return "Apple Intelligence is ready."
            case .notEnabled:
                return "Turn on Apple Intelligence in System Settings to use it in \(AppInfo.name)."
            case .notReady:
                return "Apple Intelligence is still downloading. This can take a while after it's turned on."
            case .unsupported:
                return "Apple Intelligence isn't available on this Mac."
            }
        }
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .notReady
        case .unavailable:
            return .unsupported
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The first `maxLength` characters of `text`, cut at a word boundary, and whether
    /// anything was cut. The on-device model has a small context window.
    static func excerpt(_ text: String, maxLength: Int) -> (text: String, isTruncated: Bool) {
        guard text.count > maxLength else { return (text, false) }
        let prefix = text.prefix(maxLength)
        let cut = prefix.lastIndex(where: \.isWhitespace) ?? prefix.endIndex
        return (String(prefix[..<cut]), true)
    }

    static let tooLongMessage = "This clipping is too long for Apple Intelligence."
    private static let declinedMessage = "Apple Intelligence can't help with this clipping."
    private static let languageMessage = "Apple Intelligence doesn't support this language yet."
    private static let busyMessage = "Apple Intelligence is busy. Try again in a moment."
    private static let genericMessage = "Apple Intelligence couldn't finish. Try again."

    // macOS 27 reports failures as `LanguageModelError`; macOS 26 as
    // `LanguageModelSession.GenerationError`. Both are handled so behaviour matches on each.

    /// Whether generation failed because the input didn't fit the context window.
    static func isContextOverflow(_ error: Error) -> Bool {
        if #available(macOS 27.0, *), let error = error as? LanguageModelError,
           case .contextSizeExceeded = error {
            return true
        }
        if let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error {
            return true
        }
        return false
    }

    /// A sentence to show when generation fails.
    static func message(for error: Error) -> String {
        if isContextOverflow(error) { return tooLongMessage }
        if #available(macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return declinedMessage
            case .unsupportedLanguageOrLocale: return languageMessage
            case .rateLimited, .timeout: return busyMessage
            default: return genericMessage
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal: return declinedMessage
            case .unsupportedLanguageOrLocale: return languageMessage
            case .assetsUnavailable: return Status.notReady.explanation
            case .rateLimited, .concurrentRequests: return busyMessage
            default: return genericMessage
            }
        }
        return genericMessage
    }
}
