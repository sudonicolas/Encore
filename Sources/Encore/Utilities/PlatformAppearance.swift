import SwiftUI

/// Keeps the macOS 26 appearance where available while using native controls on 15.
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
    /// rounded rectangle. A plain material stands in on macOS 15.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// The hit and hover area of a list row. `.row` follows the concentric row shape on
    /// macOS 26; on 15 the row's own corner radius is the same thing by hand.
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
                    .background(.regularMaterial)
            }
        }
    }
}

/// Compact outlined controls for the pre-Liquid Glass popover. The system bordered
/// style gives icon-only menus an expanding rectangular background on macOS 15.
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
