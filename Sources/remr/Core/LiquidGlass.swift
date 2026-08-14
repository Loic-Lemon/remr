import SwiftUI

/// Liquid Glass surfaces with appearance-aware fallbacks for macOS 13 through
/// 25. On macOS 26 the popover window itself is native Liquid Glass; inner
/// controls get the same native glass effect. Older systems use translucent
/// materials.
///
/// Architecture on macOS 26 (per Apple's WWDC25 guidance):
/// - The NSPopover window already renders Liquid Glass. Painting a full-pane
///   `glassEffect` on top of it stacks glass on glass — the surface reads
///   milky and bordered instead of transparent. Window surfaces are therefore
///   left transparent so the native glass shows through.
/// - Compact controls (fields, chips, capsules) are the only custom glass,
///   and every window's glass elements are grouped in a `GlassEffectContainer`
///   so they sample and morph together instead of sampling other glass.
/// - Fallback-era hairlines are dropped on macOS 26: native glass controls
///   have no visible border. Keycaps and tinted state chips keep theirs
///   because they need a scannable edge.
extension View {
    /// The full-window surface of the main popover. macOS 26: no custom glass —
    /// the NSPopover's native Liquid Glass is the surface; this only groups the
    /// inner glass controls. Older systems get the translucent material and
    /// hairline fallback (the popover window is transparent below 26).
    @ViewBuilder
    func liquidGlassContainer() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            let shape = RoundedRectangle(cornerRadius: 14)
            self
                .background(.ultraThinMaterial)
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        }
    }

    /// The full-window glass surface for a borderless quick-add popup. A
    /// borderless panel gets no native glass (unlike NSPopover), so the
    /// SwiftUI glass here IS the window's surface. The continuous rounded
    /// silhouette keeps the transparent panel's corners clean; no hairline on
    /// macOS 26 (native floating glass panels keep a clean edge). No SwiftUI
    /// shadow is applied: the card grows with the content, and a shadow
    /// re-rendered against the changing silhouette reads as a shimmer at the
    /// top. Content is clipped to the silhouette so nested glass pieces never
    /// poke past the rounded corners.
    @ViewBuilder
    func liquidGlassPopup() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                self
                    .glassEffect(.regular.tint(AppPalette.controlTint), in: shape)
                    .clipShape(shape)
            }
        } else {
            self
                .background(shape.fill(AppPalette.surfaceFill))
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
                .clipShape(shape)
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

    /// A native Liquid Glass treatment for compact fields such as Search. The
    /// subtle semantic edge keeps the control from flattening into its parent.
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
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 0.75))
        } else {
            self
                .background(shape.fill(AppPalette.fieldFill))
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        }
    }
    /// A compact capsule control such as the tag filter button, with a subtle
    /// semantic edge so its pill silhouette remains legible on glass.
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(AppPalette.controlTint), in: Capsule())
                .overlay(Capsule().stroke(AppPalette.controlStroke, lineWidth: 0.75))
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
    /// The stroke stays on macOS 26: tinted chips are the one custom control
    /// that needs a scannable edge in both appearances.
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

    /// A full-width translucent panel (composer band, sync footer) that blurs
    /// list content scrolling beneath it. macOS 26 gets a continuous glass
    /// band; older systems fall back to the translucent surface fill.
    @ViewBuilder
    func liquidGlassBand() -> some View {
        let shape = Rectangle()
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(AppPalette.controlTint), in: shape)
        } else {
            self
                .background(shape.fill(AppPalette.surfaceFill))
        }
    }

    /// The main search/action toolbar already sits on the native macOS 26
    /// popover glass. Do not add a second full-width glass lens underneath its
    /// compact controls: nested glass samples flatten the controls instead of
    /// giving them depth. Older systems still need the fallback band.
    @ViewBuilder
    func liquidGlassToolbarSurface() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            liquidGlassBand()
        }
    }

    /// A small frosted chip (parse-preview pills, tag chips), capsule-shaped.
    /// `tint` colors the glass; `filled` raises the tint so white text stays
    /// legible on strongly colored chips. Older systems get the same tinted
    /// translucent fill with a hairline.
    @ViewBuilder
    func liquidGlassChip(tint: Color? = nil, filled: Bool = false) -> some View {
        liquidGlassChip(in: Capsule(), tint: tint, filled: filled)
    }

    /// A small frosted chip with a custom silhouette, e.g. the tiny tag
    /// rectangles in reminder rows.
    @ViewBuilder
    func liquidGlassChip<S: Shape>(in shape: S, tint: Color? = nil, filled: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            let fill = (tint ?? Color.primary).opacity(filled ? 0.55 : 0.18)
            self
                .glassEffect(.regular.tint(fill), in: shape)
        } else {
            let fill = (tint ?? Color.secondary).opacity(filled ? 0.5 : 0.14)
            let stroke = (tint ?? Color.secondary).opacity(filled ? 0.55 : 0.3)
            self
                .background(shape.fill(fill))
                .overlay(shape.stroke(stroke, lineWidth: 1))
        }
    }

    /// A full-content surface inside a window that already carries native
    /// glass (an inline edit form, a popover's whole body). macOS 26 windows
    /// are their own glass, so the pane is transparent; older systems need an
    /// explicit translucent pane over the transparent window.
    @ViewBuilder
    func liquidGlassPane<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self
                .background(shape.fill(AppPalette.surfaceFill))
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        }
    }

    /// Groups every glass element in this window so they sample and morph
    /// together (Apple: glass cannot sample other glass). macOS 26 only.
    @ViewBuilder
    func liquidGlassGrouping() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
    }

    /// A full-width list-row surface for selection and hover: a flat,
    /// accent-tinted rounded pill — the same treatment Reminders.app uses —
    /// so the selected row reads clearly against the window glass without an
    /// outline box. `hovered: true` (with no selection) shows the neutral
    /// preview; neither state renders nothing.
    @ViewBuilder
    func rowSelectionHighlight(selected: Bool, hovered: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if selected {
            shape.fill(Color.accentColor.opacity(0.18))
        } else if hovered {
            shape.fill(Color.primary.opacity(0.06))
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
