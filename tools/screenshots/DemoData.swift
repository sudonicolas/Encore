import AppKit
import SwiftUI

/// The fictional clipboard history the screenshots show: a product designer's day. None of
/// it comes from the real clipboard — the tool never starts ClipboardMonitor.
///
/// Long clippings are left untitled here on purpose: `--prepare` has Apple Intelligence
/// title them with Encore's own SmartTitler, so the titles in the screenshots are real.
@MainActor
enum DemoData {
    /// Text clippings the scenes look up by content.
    enum Key {
        static let flight = "Your flight to Lisbon is confirmed."
        static let casualUpdate = "hey!! so the launch slipped again"
        static let price = "€1.249,00"
        static let word = "serendipity"
    }

    private struct Item {
        var minutesAgo: Double
        var app: String
        var bundleID: String
        var kind: ClippingKind = .text
        var text: String? = nil
        var image: NSImage? = nil
        var files: [String]? = nil
        var pinned = false
        /// Days since it was moved to Recently Deleted, for the deleted ones.
        var deletedDaysAgo: Double? = nil
    }

    // MARK: - Content

    private static var items: [Item] {
        [
            // Pinned
            Item(minutesAgo: 60 * 24 * 6, app: "Mail", bundleID: "com.apple.mail", text: """
                Maya Chen
                Product Designer, Juniper Studio
                maya@juniper.studio · +1 (415) 555-0132
                """, pinned: true),
            Item(minutesAgo: 60 * 24 * 4, app: "Calendar", bundleID: "com.apple.iCal",
                 text: "https://meet.juniper.studio/design-crit", pinned: true),
            Item(minutesAgo: 60 * 24 * 3, app: "Mail", bundleID: "com.apple.mail", text: """
                Thanks so much for sending this over! I'll take a proper look this afternoon \
                and get back to you with notes by end of day.
                """),

            // Recent
            Item(minutesAgo: 1, app: "Messages", bundleID: "com.apple.MobileSMS",
                 text: "Running 5 min late, grab us a table by the window?"),
            Item(minutesAgo: 4, app: "Mail", bundleID: "com.apple.mail", text: """
                Your flight to Lisbon is confirmed.

                Confirmation code: K7Q2VX
                Flight JN 204 · Thursday, October 8
                Depart San Francisco (SFO) 4:25 PM
                Arrive Lisbon (LIS) 12:40 PM (+1)
                Seat 23A · Economy · 1 checked bag

                Online check-in opens 36 hours before departure. Please have your passport \
                ready at the bag drop.
                """),
            Item(minutesAgo: 9, app: "Freeform", bundleID: "com.apple.freeform", kind: .image,
                 image: artwork(DemoArtwork(), size: CGSize(width: 1600, height: 1000))),
            Item(minutesAgo: 18, app: "Xcode", bundleID: "com.apple.dt.Xcode", text: """
                func withRetry<T>(
                    attempts: Int = 3,
                    delay: Duration = .seconds(1),
                    _ operation: () async throws -> T
                ) async throws -> T {
                    for attempt in 1..<attempts {
                        do { return try await operation() }
                        catch { try await Task.sleep(for: delay * attempt) }
                    }
                    return try await operation()
                }
                """),
            Item(minutesAgo: 26, app: "Safari", bundleID: "com.apple.Safari", text: Key.price),
            Item(minutesAgo: 41, app: "Notes", bundleID: "com.apple.Notes", text: """
                Q4 launch sync, Sep 24

                • Marketing site goes live Oct 6, press embargo lifts 9 AM PT
                • Priya to finalize App Store screenshots by Friday
                • Icon tweaks: simpler stack, softer shadow
                • Open question: do we ship the widget in 1.1 or wait for 1.2?

                Next sync Thursday 10:30.
                """),
            Item(minutesAgo: 58, app: "Finder", bundleID: "com.apple.finder", kind: .fileURL,
                 files: ["Brand Guidelines.pdf", "Launch Moodboard.png"]),
            Item(minutesAgo: 72, app: "Safari", bundleID: "com.apple.Safari", text: Key.word),
            Item(minutesAgo: 95, app: "Messages", bundleID: "com.apple.MobileSMS", text: """
                hey!! so the launch slipped again lol. design needs 2 more days for the icons \
                and legal still hasnt signed off on the privacy page. can we push the review \
                to thurs? lmk
                """),
            Item(minutesAgo: 140, app: "Terminal", bundleID: "com.apple.Terminal",
                 text: "git log --oneline --graph --decorate -20"),
            Item(minutesAgo: 190, app: "Maps", bundleID: "com.apple.Maps",
                 text: "Ferry Building Marketplace, 1 Ferry Building, San Francisco, CA 94111"),
            Item(minutesAgo: 60 * 20, app: "Mail", bundleID: "com.apple.mail", text: """
                ¡Hola Maya! Te confirmo la reserva para el jueves a las 20:00 en Casa Lucía. \
                Somos seis y pedimos la mesa de la terraza. ¡Nos vemos allí!
                """),
            Item(minutesAgo: 60 * 22, app: "Reminders", bundleID: "com.apple.reminders",
                 text: "Book the photo studio for the product shoot"),
            Item(minutesAgo: 60 * 26, app: "Freeform", bundleID: "com.apple.freeform", kind: .image,
                 image: artwork(DemoPalette(), size: CGSize(width: 1200, height: 800))),
            Item(minutesAgo: 60 * 30, app: "Safari", bundleID: "com.apple.Safari", text: "Ada Lovelace"),
            Item(minutesAgo: 60 * 50, app: "Safari", bundleID: "com.apple.Safari", text: """
                Heat the oven to 220°C. Toss the squash, red onion and chickpeas with olive \
                oil, smoked paprika and a good pinch of salt, then roast for 25 minutes, \
                turning once, until golden at the edges.
                """),

            // Recently Deleted
            Item(minutesAgo: 60 * 24 * 2, app: "Messages", bundleID: "com.apple.MobileSMS",
                 text: "ok see you there!", deletedDaysAgo: 1),
            Item(minutesAgo: 60 * 24 * 5, app: "Mail", bundleID: "com.apple.mail", text: """
                Hi team, a quick reminder that the studio is closed on Monday for the holiday. \
                Deliveries will be held at the front desk until Tuesday morning.
                """, deletedDaysAgo: 4),
            Item(minutesAgo: 60 * 24 * 10, app: "Safari", bundleID: "com.apple.Safari",
                 text: "https://developer.apple.com/design/human-interface-guidelines/materials",
                 deletedDaysAgo: 9),
            Item(minutesAgo: 60 * 24 * 17, app: "Notes", bundleID: "com.apple.Notes", text: """
                Groceries for Saturday
                Lemons, olive oil, sourdough, burrata, basil, cherry tomatoes
                """, deletedDaysAgo: 16),
            Item(minutesAgo: 60 * 24 * 27, app: "Freeform", bundleID: "com.apple.freeform", kind: .image,
                 image: artwork(DemoArtwork(variant: 1), size: CGSize(width: 1200, height: 900)),
                 deletedDaysAgo: 26),
        ]
    }

    static let ignoredApps = [
        IgnoredApp(bundleIdentifier: "com.apple.keychainaccess", name: "Keychain Access"),
        IgnoredApp(bundleIdentifier: "com.apple.Passwords", name: "Passwords"),
        IgnoredApp(bundleIdentifier: "com.apple.Terminal", name: "Terminal"),
    ]

    // MARK: - Writing the data folder

    /// Writes the history Encore's store will load, before anything touches the store.
    /// Deleted clippings go in as active ones so `--prepare` can title them too;
    /// `finishPreparing` then moves them to Recently Deleted.
    static func install(in directory: URL, filesDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

        let now = Date()
        // Newest first, the order the store keeps.
        let clippings = items.sorted { $0.minutesAgo < $1.minutesAgo }.map { item -> Clipping in
            var clipping = Clipping(
                kind: item.kind,
                text: item.text,
                sourceAppName: item.app,
                sourceBundleID: item.bundleID,
                createdAt: now.addingTimeInterval(-item.minutesAgo * 60),
                isPinned: item.pinned
            )
            // Stored the way ClipboardMonitor stores a copied image.
            if let image = item.image, let png = image.resized(maxDimension: 600).pngData() {
                clipping.imageData = png
                clipping.text = "Image (\(Int(image.size.width))\u{00D7}\(Int(image.size.height)))"
            }
            if let files = item.files {
                clipping.fileURLs = files.map { name in
                    let url = filesDirectory.appendingPathComponent(name)
                    fileManager.createFile(atPath: url.path, contents: Data())
                    return url
                }
            }
            if let days = item.deletedDaysAgo {
                clipping.deletedAt = now.addingTimeInterval(-days * 86_400)
            }
            return clipping
        }

        // The store keeps a deleted clipping's date in `deletedAt`; until titles are
        // written, park it in the active list with the date stashed aside.
        let active = clippings.map { var c = $0; c.deletedAt = nil; return c }
        try write(active, to: directory.appendingPathComponent("clippings.json"))
        try write([Clipping](), to: directory.appendingPathComponent("deleted-clippings.json"))
        try write(ignoredApps, to: directory.appendingPathComponent("ignored-apps.json"))
        try write(clippings.compactMap { c in c.deletedAt.map { DeletedDate(id: c.id, deletedAt: $0) } },
                  to: directory.appendingPathComponent("deleted-dates.json"))
    }

    /// After titling: splits the titled history into active and Recently Deleted.
    static func finishPreparing(_ titled: [Clipping], in directory: URL) throws {
        let dates = try JSONDecoder().decode(
            [DeletedDate].self,
            from: Data(contentsOf: directory.appendingPathComponent("deleted-dates.json"))
        )
        let deletedAt = Dictionary(uniqueKeysWithValues: dates.map { ($0.id, $0.deletedAt) })
        let active = titled.filter { deletedAt[$0.id] == nil }
        let deleted = titled
            .compactMap { c -> Clipping? in
                guard let date = deletedAt[c.id] else { return nil }
                var c = c
                c.deletedAt = date
                return c
            }
            .sorted { $0.deletedAt! > $1.deletedAt! }
        try write(active, to: directory.appendingPathComponent("clippings.json"))
        try write(deleted, to: directory.appendingPathComponent("deleted-clippings.json"))
    }

    private struct DeletedDate: Codable {
        let id: UUID
        let deletedAt: Date
    }

    private static func write(_ value: some Encodable, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private static func artwork(_ view: some View, size: CGSize) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.nsImage ?? NSImage(size: size)
    }
}

// MARK: - Image clippings

/// A quiet abstract landscape at dusk — something a designer might copy out of Freeform.
private struct DemoArtwork: View {
    var variant = 0

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: variant == 0
                        ? [Color(red: 0.93, green: 0.86, blue: 0.77), Color(red: 0.80, green: 0.64, blue: 0.57), Color(red: 0.62, green: 0.57, blue: 0.68)]
                        : [Color(red: 0.79, green: 0.86, blue: 0.89), Color(red: 0.47, green: 0.56, blue: 0.64)],
                    startPoint: .top, endPoint: .bottom
                )
                Circle()
                    .fill(Color(red: 0.98, green: 0.94, blue: 0.88))
                    .frame(width: w * 0.2)
                    .position(x: w * 0.66, y: h * 0.42)
                    .blur(radius: 2)
                hills(w: w, h: h, base: 0.62, amplitude: 0.1, phase: 0.2)
                    .fill(Color(red: 0.55, green: 0.40, blue: 0.33).opacity(0.75))
                hills(w: w, h: h, base: 0.72, amplitude: 0.08, phase: 1.4)
                    .fill(Color(red: 0.40, green: 0.28, blue: 0.23).opacity(0.9))
                hills(w: w, h: h, base: 0.84, amplitude: 0.06, phase: 2.6)
                    .fill(Color(red: 0.25, green: 0.18, blue: 0.15))
            }
        }
    }

    private func hills(w: CGFloat, h: CGFloat, base: CGFloat, amplitude: CGFloat, phase: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: h))
            for step in 0...80 {
                let x = w * CGFloat(step) / 80
                let t = CGFloat(step) / 80 * .pi * 2
                let y = h * (base - amplitude * (sin(t * 1.3 + phase) * 0.6 + sin(t * 2.7 + phase * 2) * 0.4))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
        }
    }
}

/// A colour palette swatch: Encore's own — clay, sand, paper, lavender and blue.
private struct DemoPalette: View {
    private let colors: [Color] = [
        Color(red: 0.70, green: 0.46, blue: 0.36),
        Color(red: 0.85, green: 0.71, blue: 0.61),
        Color(red: 0.95, green: 0.90, blue: 0.83),
        Color(red: 0.77, green: 0.71, blue: 0.90),
        Color(red: 0.29, green: 0.58, blue: 0.92),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(colors.indices, id: \.self) { colors[$0] }
        }
    }
}
