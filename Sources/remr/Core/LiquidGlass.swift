import SwiftUI

/// Liquid Glass surfaces with appearance-aware fallbacks for macOS 13 through
/// 25. On macOS 26 the same native glass effect is used for the popover and
/// compact controls; older systems use translucent materials.
extension View {
    @ViewBuilder
    func liquidGlassContainer() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(AppPalette.controlTint), in: shape)
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        } else {
            self
                .background(.ultraThinMaterial)
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        }
    }

    /// The full-window glass surface for a borderless quick-add popup. The
    /// continuous rounded silhouette keeps the transparent panel's corners
    /// clean; macOS 26 gets the native glass effect while older systems fall
    /// back to a translucent material with a hairline stroke and a soft
    /// floating shadow. Content is clipped to the silhouette so nested glass
    /// pieces never poke past the rounded corners.
    @ViewBuilder
    func liquidGlassPopup() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(AppPalette.controlTint), in: shape)
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
                .clipShape(shape)
        } else {
            self
                .background(shape.fill(AppPalette.surfaceFill))
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
    }

    /// Primary buttons use native Liquid Glass styles on macOS 26+ and retain
    /// their prior style below it. Prominent actions use the filled glass
    /// treatment that replaces `.borderedProminent`.
    @ViewBuilder
    func liquidGlassButtonStyle(_ fallback: some PrimitiveButtonStyle,
                                prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(fallback)
        }
    }

    /// A native Liquid Glass treatment for compact fields such as Search.
    /// Older systems get the same translucent material and hairline fallback.
    @ViewBuilder
    func liquidGlassField() -> some View {
        liquidGlassField(in: RoundedRectangle(cornerRadius: 9))
    }

    /// Apply the same treatment to a field with a custom outer shape.
    @ViewBuilder
    func liquidGlassField<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(AppPalette.controlTint), in: shape)
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        } else {
            self
                .background(shape.fill(AppPalette.fieldFill))
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        }
    }
    /// A compact capsule control such as the tag filter button.
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(AppPalette.controlTint), in: Capsule())
                .overlay(Capsule().stroke(AppPalette.controlStroke, lineWidth: 1))
        } else {
            self
                .background(Capsule().fill(AppPalette.fieldFill))
                .overlay(Capsule().strokeBorder(AppPalette.controlStroke, lineWidth: 1))
        }
    }

    /// A higher-contrast glass treatment for compact keyboard keycaps.
    /// Ordinary fields are intentionally subtle; keycaps need a visible edge
    /// in both appearances so their boundaries remain scannable.
    @ViewBuilder
    func liquidGlassKeycap() -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        if #available(macOS 26.0, *) {
            self
                .foregroundStyle(.primary)
                .glassEffect(.regular.tint(AppPalette.keycapTint), in: shape)
                .overlay(shape.stroke(AppPalette.keycapStroke, lineWidth: 1))
        } else {
            self
                .foregroundStyle(.primary)
                .background(shape.fill(AppPalette.keycapFill))
                .overlay(shape.stroke(AppPalette.keycapStroke, lineWidth: 1))
        }
    }
    /// A compact capsule with a semantic tint, used for the active filter.
    @ViewBuilder
    func liquidGlassCapsule(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(0.18)), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.38), lineWidth: 1))
        } else {
            self
                .background(Capsule().fill(tint.opacity(0.16)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
        }
    }


    /// Small custom transient chrome can use an explicit glass shape without
    /// replacing the system-provided glass surface of the whole popover.
    @ViewBuilder
    func liquidGlassToast() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(Capsule().fill(AppPalette.surfaceFill))
                .overlay(Capsule().strokeBorder(AppPalette.controlStroke, lineWidth: 1))
        }
    }
}
