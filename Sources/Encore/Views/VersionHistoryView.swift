import SwiftUI

/// The earlier versions of an edited text clipping, newest first, under the text as it is
/// now. Restoring one makes it the text again; the text it replaces is kept as a version
/// of its own, so a restore is never a one-way trip.
struct VersionHistoryView: View {
    let clipping: Clipping
    var canRestore = true
    var onDone: () -> Void

    @Environment(ClipboardStore.self) private var store

    private var earlier: [TextVersion] {
        (clipping.versions ?? []).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Version History")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 1) {
                    row(
                        title: "Current",
                        date: clipping.editedAt ?? clipping.createdAt,
                        text: clipping.text ?? "",
                        version: nil
                    )
                    ForEach(earlier) { version in
                        row(
                            title: version.id == clipping.versions?.first?.id ? "Original" : "Earlier",
                            date: version.date,
                            text: version.text,
                            version: version
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 320)
    }

    private func row(title: String, date: Date, text: String, version: TextVersion?) -> some View {
        let preview = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).fontWeight(.medium)
                    Text("\u{00B7}")
                    Text(date, format: .dateTime.month().day().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(preview.isEmpty ? "Empty" : preview)
                    .lineLimit(3)
                    .foregroundStyle(preview.isEmpty ? .secondary : .primary)
                Text(text.count == 1 ? "1 character" : "\(text.count.formatted()) characters")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let version, canRestore {
                Button("Restore") {
                    withAnimation(.snappy(duration: 0.25).motionSafe) {
                        store.restoreVersion(version.id, of: clipping.id)
                    }
                    onDone()
                }
                .controlSize(.small)
                .help("Make this the text again. The current text stays in the history.")
                .accessibilityLabel("Restore \(title) Version")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(version == nil ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
    }
}
