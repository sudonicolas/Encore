import SwiftUI
import AppKit

/// The sparkles menu for a text clipping: Writing Tools–style rewrites and insights. While
/// Apple Intelligence is off or still downloading it explains that instead; on Macs that
/// can't run it at all, it isn't shown.
///
/// Unstyled: hosts style it like their other buttons (glass in the popover, native in the
/// History toolbar).
struct IntelligenceMenu: View {
    let clipping: Clipping
    let runner: TextActionRunner

    /// Whether the menu has anything to offer: a non-empty text clipping, on a Mac that
    /// can run Apple Intelligence.
    static func isShown(for clipping: Clipping) -> Bool {
        text(of: clipping) != nil && Intelligence.status != .unsupported
    }

    private static func text(of clipping: Clipping) -> String? {
        guard clipping.kind == .text,
              let text = clipping.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    var body: some View {
        let status = Intelligence.status
        if let text = Self.text(of: clipping), status != .unsupported {
            Menu {
                if status == .available {
                    Section("Rewrite") {
                        ForEach(TextAction.rewrites) { item($0, text: text) }
                    }
                    Section("Understand") {
                        ForEach(TextAction.insights) { item($0, text: text) }
                    }
                } else {
                    Text(status.explanation)
                    if status == .notEnabled {
                        Button("Open Apple Intelligence Settings\u{2026}", action: Intelligence.openSettings)
                    }
                }
            } label: {
                Label("Apple Intelligence", systemImage: "sparkles")
            }
            .menuIndicator(.hidden)
            .help("Proofread, rewrite or summarize with Apple Intelligence")
            .accessibilityInputLabels(["Apple Intelligence", "Writing Tools", "Sparkles"])
        }
    }

    private func item(_ action: TextAction, text: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25).motionSafe) {
                runner.run(action, on: text)
            }
        } label: {
            Label(action.title, systemImage: action.symbol)
        }
    }
}

/// The result of a TextAction, streamed in as it's written: a card above the clipping
/// with Copy, Try Again and Close. Copying the result records it as a new clipping.
///
/// VoiceOver: when a result starts, the cursor moves to the card's heading ("Summary"),
/// right above where the text will appear; when it's done, "Summary ready" is announced
/// (or the error). The text streams in silently rather than being read chunk by chunk.
struct TextActionResultCard: View {
    let runner: TextActionRunner

    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @State private var showCopied = false
    @State private var copiedTask: Task<Void, Never>?

    var body: some View {
        if let action = runner.action {
            VStack(alignment: .leading, spacing: 10) {
                header(action)
                content
                if runner.usedExcerpt, runner.phase != .running {
                    Text("Only the beginning of this clipping was used \u{2014} it's longer than Apple Intelligence can read at once.")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.lavender.opacity(0.08), in: .continuous(UIRadius.card))
            .overlay {
                // The soft gradient edge becomes a solid, visible one with Increase Contrast.
                RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                    .strokeBorder(
                        contrast == .increased ? AnyShapeStyle(Brand.blue) : AnyShapeStyle(Brand.sparkle.opacity(0.55)),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
            }
            .accessibilityElement(children: .contain)
            .onChange(of: runner.phase, initial: true) { _, phase in
                announce(phase, action: action)
            }
            .onDisappear { copiedTask?.cancel() }
        }
    }

    private func announce(_ phase: TextActionRunner.Phase, action: TextAction) {
        switch phase {
        case .running:
            Task {
                // Once the card has appeared.
                try? await Task.sleep(for: .milliseconds(300))
                isHeadingFocused = true
            }
        case .finished:
            AssistiveTech.announce(runner.output.isEmpty ? "No result" : "\(action.resultTitle) ready")
        case .failed(let message):
            AssistiveTech.announce(message)
        case .idle:
            break
        }
    }

    private func header(_ action: TextAction) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(contrast == .increased ? AnyShapeStyle(Brand.blue) : AnyShapeStyle(Brand.sparkle))
                .symbolEffect(.pulse, isActive: runner.phase == .running)
                .accessibilityHidden(true)
            Text(action.resultTitle)
                .scaledFont(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(runner.phase == .running ? "Writing" : "")
                .accessibilityFocused($isHeadingFocused)

            Spacer(minLength: 4)

            if runner.phase == .finished, !runner.output.isEmpty {
                Button(action: copy) {
                    Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(showCopied ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .help("Copy Result")
                .accessibilityLabel("Copy Result")
                .accessibilityInputLabels(["Copy", "Copy Result"])
            }
            if runner.phase != .running {
                Button(action: runner.retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .help("Try Again")
                .accessibilityInputLabels(["Try Again", "Retry"])
            }
            Button {
                withAnimation(.snappy(duration: 0.25).motionSafe) { runner.dismiss() }
            } label: {
                Label(runner.phase == .running ? "Stop" : "Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .help(runner.phase == .running ? "Stop" : "Close")
            .accessibilityInputLabels([runner.phase == .running ? "Stop" : "Close"])
        }
        .buttonStyle(IconButtonStyle())
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = runner.phase {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else if runner.output.isEmpty {
            Text("Writing\u{2026}")
                .foregroundStyle(.secondary)
        } else {
            Text(runner.output)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(runner.output, forType: .string)
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

/// The small sparkle that marks a title Apple Intelligence wrote.
struct SmartTitleGlyph: View {
    @Environment(\.backgroundProminence) private var backgroundProminence
    @Environment(\.colorSchemeContrast) private var contrast

    private var style: AnyShapeStyle {
        // On a selected row's accent fill the brand gradient washes out, so it follows
        // the row's text colour there instead. With Increase Contrast it's solid blue:
        // one flat colour reads more crisply than a gradient at this size.
        if backgroundProminence == .increased { return AnyShapeStyle(.primary) }
        return contrast == .increased ? AnyShapeStyle(Brand.blue) : AnyShapeStyle(Brand.sparkle)
    }

    var body: some View {
        Image(systemName: "sparkles")
            .imageScale(.small)
            .foregroundStyle(style)
            .accessibilityLabel("Title by Apple Intelligence")
            .help("Title by Apple Intelligence")
    }
}
