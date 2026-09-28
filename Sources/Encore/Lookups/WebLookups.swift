import Foundation

/// Clients for the free, keyless web services behind online lookups (all listed in
/// github.com/public-apis/public-apis):
///
/// - Frankfurter — European Central Bank exchange rates
/// - Wiktionary — definitions (Wikimedia REST API)
/// - Wikipedia — article summaries (Wikimedia REST API)
///
/// Requests use an ephemeral session (no cookies, no disk cache) and go out only for
/// what's needed: a currency code for rates, or the word or phrase the user asked about.
enum WebLookups {
    enum Failure: LocalizedError, Equatable {
        case notFound
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notFound: return "Nothing found."
            case .unavailable: return "Couldn't reach the service. Check your connection and try again."
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = [
            "User-Agent": AppInfo.userAgent,
            "Accept": "application/json"
        ]
        return URLSession(configuration: configuration)
    }()

    static func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            try Task.checkCancellation()
            throw Failure.unavailable
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw Failure.unavailable
            }
        case 404:
            throw Failure.notFound
        default:
            throw Failure.unavailable
        }
    }

    /// `text` as a single URL path component: spaces become underscores (the Wikimedia
    /// title convention) and anything else unsafe is percent-encoded.
    static func pathComponent(_ text: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let title = text.replacingOccurrences(of: " ", with: "_")
        return title.addingPercentEncoding(withAllowedCharacters: allowed) ?? title
    }
}

// MARK: - Frankfurter (exchange rates)

struct ExchangeRates: Decodable, Equatable {
    let base: String
    /// The ECB publication date, "yyyy-MM-dd".
    let date: String
    let rates: [String: Double]

    /// Read in the local time zone: parsed as UTC midnight, "2026-09-24" would display
    /// as Sep 23 anywhere west of Greenwich.
    var publicationDate: Date? {
        try? Date(date, strategy: Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

@MainActor
enum Frankfurter {
    /// Rates change once a day; keep them for an hour so reopening a clipping is instant.
    private static var cache: [String: (rates: ExchangeRates, fetchedAt: Date)] = [:]

    static func rates(from base: String) async throws -> ExchangeRates {
        if let cached = cache[base], cached.fetchedAt.timeIntervalSinceNow > -3_600 {
            return cached.rates
        }
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")!
        components.queryItems = [URLQueryItem(name: "base", value: base)]
        let rates = try await WebLookups.fetch(ExchangeRates.self, from: components.url!)
        cache[base] = (rates, Date())
        return rates
    }
}

// MARK: - Wiktionary (definitions)

struct WordDefinition: Equatable {
    struct Sense: Equatable, Identifiable {
        let id = UUID()
        let partOfSpeech: String
        let definitions: [String]
    }

    let word: String
    let senses: [Sense]
    let pageURL: URL
}

enum Wiktionary {
    private struct Entry: Decodable {
        let partOfSpeech: String
        let definitions: [Definition]
    }

    private struct Definition: Decodable {
        let definition: String
    }

    /// Tries the word as copied, then in lowercase ("Serendipity" → "serendipity"), since
    /// Wiktionary titles are case-sensitive.
    static func define(_ word: String) async throws -> WordDefinition {
        do {
            return try await fetch(word)
        } catch WebLookups.Failure.notFound where word != word.lowercased() {
            return try await fetch(word.lowercased())
        }
    }

    private static func fetch(_ word: String) async throws -> WordDefinition {
        let path = WebLookups.pathComponent(word)
        let url = URL(string: "https://en.wiktionary.org/api/rest_v1/page/definition/\(path)")!
        let languages = try await WebLookups.fetch([String: [Entry]].self, from: url)
        // English Wiktionary describes words from every language; prefer English entries.
        guard let entries = languages["en"] ?? languages.values.first else {
            throw WebLookups.Failure.notFound
        }
        let senses = entries.prefix(3).compactMap { entry -> WordDefinition.Sense? in
            let definitions = entry.definitions
                .map { HTML.plainText($0.definition) }
                .filter { !$0.isEmpty }
                .prefix(3)
            guard !definitions.isEmpty else { return nil }
            return WordDefinition.Sense(partOfSpeech: entry.partOfSpeech, definitions: Array(definitions))
        }
        guard !senses.isEmpty else { throw WebLookups.Failure.notFound }
        return WordDefinition(
            word: word,
            senses: senses,
            pageURL: URL(string: "https://en.wiktionary.org/wiki/\(path)")!
        )
    }
}

// MARK: - Wikipedia (summaries)

struct WikipediaSummary: Decodable, Equatable {
    let title: String
    let description: String?
    let extract: String
    let pageURL: URL

    private enum CodingKeys: String, CodingKey {
        case title, description, extract
        case contentURLs = "content_urls"
    }

    private struct ContentURLs: Decodable {
        struct Page: Decodable { let page: URL }
        let desktop: Page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        extract = try container.decode(String.self, forKey: .extract)
        pageURL = try container.decode(ContentURLs.self, forKey: .contentURLs).desktop.page
    }
}

enum Wikipedia {
    static func summary(of topic: String) async throws -> WikipediaSummary {
        let path = WebLookups.pathComponent(topic)
        let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)")!
        let summary = try await WebLookups.fetch(WikipediaSummary.self, from: url)
        guard !summary.extract.isEmpty else { throw WebLookups.Failure.notFound }
        return summary
    }
}

// MARK: - HTML

enum HTML {
    /// Wiktionary definitions are HTML fragments; this reduces one to plain text.
    static func plainText(_ html: String) -> String {
        var text = html.replacing(#/<[^>]+>/#, with: "")
        text = text.replacing(#/&#(x?)([0-9A-Fa-f]+);/#) { match in
            let radix = match.output.1.isEmpty ? 10 : 16
            guard let code = UInt32(match.output.2, radix: radix), let scalar = Unicode.Scalar(code) else { return "" }
            return String(Character(scalar))
        }
        // &amp; last, so "&amp;lt;" decodes to "&lt;" rather than "<".
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
