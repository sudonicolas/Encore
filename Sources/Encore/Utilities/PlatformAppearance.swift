import SwiftUI
import AppKit

// Encore runs on macOS 13 and later, but is designed for 26. Everything newer than 13
// goes through the helpers here, so each view states what it wants once and the
// fallbacks live in one place. With the deployment target at 13 the compiler rejects
// any ungated use, so the gating is checked rather than trusted.

/// Keeps the macOS 26 appearance where available while using native controls before it.
struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            buttonStyle(LegacyGlassButtonStyle(prominent: prominent))
        }
    }

    @ViewBuilder
    func adaptiveGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    /// A glass background in any shape, not just a capsule: the hover preview card is a
    /// rounded rectangle. A plain material stands in before macOS 26.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// The hit and hover area of a list row. `.row` follows the concentric row shape on
    /// macOS 26; before it the row's own corner radius is the same thing by hand.
    @ViewBuilder
    func adaptiveRowContentShape() -> some View {
        if #available(macOS 26.0, *) {
            contentShape(.row)
        } else {
            contentShape(RoundedRectangle(cornerRadius: UIRadius.rowMinimum, style: .continuous))
        }
    }

    @ViewBuilder
    func compactOnLegacyMacOS() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    func adaptiveSafeAreaBar<Bar: View>(
        edge: VerticalEdge,
        @ViewBuilder content: () -> Bar
    ) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0) {
                content()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

/// Compact outlined controls for the pre-Liquid Glass popover. The system bordered
/// style gives icon-only menus an expanding rectangular background before macOS 26.
private struct LegacyGlassButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .frame(minWidth: 36, minHeight: 36)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                prominent
                    ? Color.destructiveFill
                    : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.035),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(prominent ? 0 : 0.14), lineWidth: 1)
            }
            .contentShape(Capsule())
    }
}

// MARK: - macOS 13 and 14

extension View {
    /// `onChange(of:initial:)`, which is macOS 14 and later. On 13 the older form stands
    /// in, and `initial` is honoured by running the action when the view appears.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ newValue: V) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value, initial: initial) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
                .onAppear { if initial { action(value) } }
        }
    }

    /// An SF Symbol swapping for another one in place (macOS 14); a cross-fade on 13.
    @ViewBuilder
    func symbolReplaceTransition() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            contentTransition(.opacity)
        }
    }

    /// A symbol that pulses while something is in progress (macOS 14). Nothing on 13,
    /// where the "Writing" text beside it says the same.
    @ViewBuilder
    func pulsingSymbol(isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            symbolEffect(.pulse, isActive: isActive)
        } else {
            self
        }
    }

    /// Round (or, with `circle` false, capsule) bordered buttons. Both shapes are macOS 14
    /// and later; on 13 the popover's buttons are drawn by `LegacyGlassButtonStyle`,
    /// which is a capsule already, and other buttons keep their default shape.
    @ViewBuilder
    func roundButtonBorder(_ circle: Bool = true) -> some View {
        if #available(macOS 14.0, *) {
            buttonBorderShape(circle ? .circle : .capsule)
        } else {
            self
        }
    }

    /// Before macOS 26 the popover is a solid panel. Its own translucent material was
    /// being stacked with the bars' materials and the wallpaper behind it, and the result
    /// was muddy, with a visibly different shade band at the top and bottom.
    @ViewBuilder
    func solidOnLegacyMacOS() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// For Settings panes, whose fixed heights fit their grouped form exactly on macOS 26.
    /// Earlier systems lay grouped forms out with other metrics, so there the pane keeps
    /// scrolling: anything that doesn't fit stays reachable instead of being cut off.
    @ViewBuilder
    func scrollDisabledWhereSizedToFit() -> some View {
        if #available(macOS 26.0, *) {
            scrollDisabled(true)
        } else {
            self
        }
    }

    /// The pointing-hand cursor of a link. `pointerStyle` is macOS 15 and later; before
    /// it the cursor is pushed and popped by hand as the pointer comes and goes.
    @ViewBuilder
    func linkPointer() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.link)
        } else {
            modifier(LegacyLinkPointer())
        }
    }
}

private struct LegacyLinkPointer: ViewModifier {
    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isPushed else { return }
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                isPushed = hovering
            }
            // A view that goes away under the pointer gets no hover-out.
            .onDisappear {
                if isPushed { NSCursor.pop() }
                isPushed = false
            }
    }
}

/// Reads `backgroundProminence` — whether the view sits on a selected row's accent fill —
/// where it exists (macOS 14). On 13 it is always reported as standard, so custom colours
/// stay as they are on a selected row.
struct BackgroundProminenceReader<Content: View>: View {
    @ViewBuilder let content: (_ isIncreased: Bool) -> Content

    var body: some View {
        if #available(macOS 14.0, *) {
            ProminenceReader(content: content)
        } else {
            content(false)
        }
    }
}

@available(macOS 14.0, *)
private struct ProminenceReader<Content: View>: View {
    let content: (Bool) -> Content
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        content(prominence == .increased)
    }
}

/// `ContentUnavailableView` on macOS 14 and later, and the same layout drawn by hand on
/// 13: a large secondary symbol, a bold title, a secondary description and any actions,
/// centred in the space available.
struct EmptyStateView<Title: View, Description: View, Actions: View>: View {
    private let title: Title
    private let description: Description
    private let actions: Actions

    init(
        @ViewBuilder label: () -> Title,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        title = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                title
            } description: {
                description
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 6) {
                title
                    .labelStyle(EmptyStateLabelStyle())
                description
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                actions
                    .padding(.top, 10)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(@ViewBuilder label: () -> Title, @ViewBuilder description: () -> Description) {
        self.init(label: label, description: description) { EmptyView() }
    }
}

extension EmptyStateView where Description == EmptyView {
    init(@ViewBuilder label: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.init(label: label, description: { EmptyView() }, actions: actions)
    }
}

/// `ContentUnavailableView.search(text:)`, with its wording on macOS 13.
struct SearchEmptyStateView: View {
    let text: String

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView.search(text: text)
        } else {
            EmptyStateView {
                Label("No Results for \u{201C}\(text)\u{201D}", systemImage: "magnifyingglass")
            } description: {
                Text("Check the spelling or try a new search.")
            }
        }
    }
}

/// The macOS 13 stand-in for `ContentUnavailableView`'s label: symbol above title.
private struct EmptyStateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 10) {
            configuration.icon
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            configuration.title
                .font(.title2.bold())
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

/// SF Symbols newer than macOS 13, with the closest older symbol before them. A name the
/// system doesn't have draws nothing at all, and the compiler can't catch that.
enum SymbolName {
    static var versionHistory: String {
        if #available(macOS 15.0, *) { return "clock.arrow.trianglehead.counterclockwise.rotate.90" }
        return "clock.arrow.circlepath"
    }

    static var imageUnavailable: String {
        if #available(macOS 15.0, *) { return "photo.badge.exclamationmark" }
        return "exclamationmark.triangle"
    }
}

extension NSApplication {
    /// Brings the app forward. `activate()` is macOS 14 and later, and the call it
    /// replaces is the one that works on 13.
    func activateCompat() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
