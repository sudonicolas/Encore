import SwiftUI
import AppKit

/// Online lookups under a short text clipping: a currency conversion (fetched right away —
/// only the currency code is sent), and Define / Wikipedia buttons that send the word or
/// phrase only when clicked.
struct LookupsSection: View {
    let text: String

    @Environment(\.textScale) private var textScale
    @State private var candidates: LookupCandidates
    @State private var definition: LookupState<WordDefinition> = .idle
    @State private var article: LookupState<WikipediaSummary> = .idle

    init(text: String) {
        self.text = text
        _candidates = State(initialValue: LookupCandidates(text: text))
    }

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let money = candidates.money {
                    CurrencyCard(amount: money)
                }
                if definition.isIdle || article.isIdle {
                    buttons
                }
                if let word = candidates.word, !definition.isIdle {
                    LookupCard(
                        title: "Definition",
                        symbol: "character.book.closed",
                        source: "Wiktionary",
                        sourceURL: definition.value?.pageURL,
                        state: definition,
                        retry: { define(word) }
                    ) { DefinitionContent(definition: $0) }
                }
                if let topic = candidates.topic, !article.isIdle {
                    LookupCard(
                        title: article.value?.title ?? "Wikipedia",
                        symbol: "book.closed",
                        source: "Wikipedia",
                        sourceURL: article.value?.pageURL,
                        state: article,
                        retry: { lookUpArticle(topic) }
                    ) { ArticleContent(summary: $0) }
                }
            }
            .animation(.snappy(duration: 0.25).motionSafe, value: definition.isIdle)
            .animation(.snappy(duration: 0.25).motionSafe, value: article.isIdle)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let word = candidates.word, definition.isIdle {
                Button {
                    define(word)
                } label: {
                    Label("Define", systemImage: "character.book.closed")
                }
                .help("Look up \u{201C}\(word)\u{201D} on Wiktionary")
            }
            if let topic = candidates.topic, article.isIdle {
                Button {
                    lookUpArticle(topic)
                } label: {
                    Label("Wikipedia", systemImage: "book.closed")
                }
                .help("Look up \u{201C}\(topic)\u{201D} on Wikipedia")
            }
        }
        .buttonStyle(.glass)
        // Bigger buttons to match larger text.
        .controlSize(textScale >= 1.5 ? .large : (textScale > 1 ? .regular : .small))
    }

    private func define(_ word: String) {
        definition = .loading
        Task {
            definition = await LookupState { try await Wiktionary.define(word) }
            announce(definition, loaded: "Definition of \(word) loaded")
        }
    }

    private func lookUpArticle(_ topic: String) {
        article = .loading
        Task {
            article = await LookupState { try await Wikipedia.summary(of: topic) }
            announce(article, loaded: "Wikipedia article loaded")
        }
    }

    /// The card fills in below the buttons without moving VoiceOver, so say when it's done.
    private func announce<Value>(_ state: LookupState<Value>, loaded: String) {
        switch state {
        case .loaded: AssistiveTech.announce(loaded)
        case .failed(let message): AssistiveTech.announce(message)
        case .idle, .loading: break
        }
    }
}

// MARK: - State

enum LookupState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    init(_ load: () async throws -> Value) async {
        do {
            self = .loaded(try await load())
        } catch {
            self = .failed((error as? LocalizedError)?.errorDescription ?? WebLookups.Failure.unavailable.errorDescription!)
        }
    }

    var isIdle: Bool { self == .idle }

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

// MARK: - Cards

/// Frame shared by every lookup: an icon and title, the content (or progress, or an error
/// with Try Again), and the source's attribution — Wikimedia content is CC BY-SA.
private struct LookupCard<Value: Equatable, Content: View>: View {
    let title: String
    let symbol: String
    let source: String
    let sourceURL: URL?
    let state: LookupState<Value>
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .scaledFont(.headline)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)

            switch state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Loading")
            case .loaded(let value):
                content(value)
            case .failed(let message):
                HStack {
                    Text(message)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Try Again", action: retry)
                        .controlSize(.small)
                }
            }

            if let sourceURL {
                Link(destination: sourceURL) {
                    Text("From \(source) \u{2197}")
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .help("Open in \(source)")
                // Without the arrow, which VoiceOver reads as "north east arrow".
                .accessibilityLabel("From \(source)")
                .accessibilityInputLabels([source, "Open in \(source)"])
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: .continuous(UIRadius.card))
        .increasedContrastBorder(RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct DefinitionContent: View {
    let definition: WordDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(definition.senses) { sense in
                VStack(alignment: .leading, spacing: 3) {
                    Text(sense.partOfSpeech)
                        .scaledFont(.subheadline, italic: true)
                        .foregroundStyle(.secondary)
                    ForEach(Array(sense.definitions.enumerated()), id: \.offset) { index, text in
                        Text("\(index + 1). \(text)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct ArticleContent: View {
    let summary: WikipediaSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let description = summary.description {
                Text(description)
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(summary.extract)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
}

/// "$1,299.00 is about" followed by the amount in the user's currency and a few majors.
/// Click a converted amount to copy it.
private struct CurrencyCard: View {
    let amount: MoneyAmount

    @State private var state: LookupState<ExchangeRates> = .loading

    private var targets: [String] {
        let local = Locale.current.currency?.identifier
        let candidates = [local, "USD", "EUR", "GBP", "JPY", "CAD"].compactMap { $0 }
        var seen: Set<String> = [amount.currency]
        return candidates
            .filter { LookupCandidates.supportedCurrencies.contains($0) && seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("\(amount.value.formatted(.currency(code: amount.currency))) is about")
            } icon: {
                Image(systemName: "dollarsign.arrow.circlepath")
            }
            .scaledFont(.headline)
            .accessibilityAddTraits(.isHeader)

            switch state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading exchange rates")
            case .loaded(let rates):
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(targets, id: \.self) { code in
                        if let rate = rates.rates[code] {
                            ConvertedAmountRow(value: amount.value * Decimal(rate), currency: code)
                        }
                    }
                }
                Text(footnote(for: rates))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                HStack {
                    Text(message)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Try Again") { Task { await load() } }
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: .continuous(UIRadius.card))
        .increasedContrastBorder(RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .task(id: amount) { await load() }
    }

    private func load() async {
        state = .loading
        state = await LookupState { try await Frankfurter.rates(from: amount.currency) }
    }

    private func footnote(for rates: ExchangeRates) -> String {
        var parts: [String] = []
        if amount.isAssumed {
            let name = Locale.current.localizedString(forCurrencyCode: amount.currency) ?? amount.currency
            parts.append("Read as \(name)")
        }
        let date = rates.publicationDate?.formatted(.dateTime.month(.abbreviated).day()) ?? rates.date
        parts.append("European Central Bank rates, \(date), via Frankfurter")
        return parts.joined(separator: " \u{00B7} ")
    }
}

private struct ConvertedAmountRow: View {
    let value: Decimal
    let currency: String

    @State private var isHovering = false
    @State private var showCopied = false
    @State private var copiedTask: Task<Void, Never>?

    private var formatted: String {
        value.formatted(.currency(code: currency))
    }

    /// "€1,193.12, Euro" rather than the code spelled out letter by letter.
    private var spokenLabel: String {
        [formatted, Locale.current.localizedString(forCurrencyCode: currency)].accessibilityJoined
    }

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 8) {
                Text(formatted)
                    .scaledFont(.title3, weight: .semibold)
                    .monospacedDigit()
                Text(currency)
                    .scaledFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if showCopied {
                    CopiedBadge()
                        .transition(.opacity)
                } else if isHovering {
                    Image(systemName: "doc.on.doc")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Copy \(formatted)")
        .accessibilityLabel(spokenLabel)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onDisappear { copiedTask?.cancel() }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formatted, forType: .string)
        AssistiveTech.announce("Copied")
        copiedTask?.cancel()
        withAnimation(.snappy(duration: 0.2).motionSafe) { showCopied = true }
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2).motionSafe) { showCopied = false }
        }
    }
}
