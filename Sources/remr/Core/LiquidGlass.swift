import AppKit
import SwiftUI

private struct NativeControlGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct NativeNotchGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Native control lenses must not render ahead of the foreground reveal.
    var nativeControlGlassEnabled: Bool {
        get { self[NativeControlGlassEnabledKey.self] }
        set { self[NativeControlGlassEnabledKey.self] = newValue }
    }

    var nativeNotchGlassEnabled: Bool {
        get { self[NativeNotchGlassEnabledKey.self] }
        set { self[NativeNotchGlassEnabledKey.self] = newValue }
    }
}

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
    /// The full-window surface of the main content, chosen by how it is
    /// presented. The native popover is its own Liquid Glass; the borderless
    /// notch panel must paint the glass itself.
    @ViewBuilder
    func remrMainSurface(_ style: MainSurfaceStyle, notchHeadHeight: CGFloat = 0,
                         notchReveal: NotchRevealController? = nil,
                         notchCollapsedWidth: CGFloat = 172) -> some View {
        switch style {
        case .popover: liquidGlassContainer()
        case .floatingPanel:
            liquidGlassNotchPanel(headHeight: notchHeadHeight, reveal: notchReveal,
                                  collapsedWidth: notchCollapsedWidth)
        }
    }

    /// A frosted backdrop with a refractive glass lens and a soft black attachment
    /// at the screen edge. Content animates independently above this surface.
    @ViewBuilder
    func liquidGlassNotchPanel(headHeight: CGFloat, fade: CGFloat = 180,
                              reveal: NotchRevealController? = nil,
                              collapsedWidth: CGFloat = 172,
                              defersGlassUntilOpen: Bool = false) -> some View {
        if let reveal {
            self.liquidGlassGrouping()
                .notchReveal(reveal, collapsedWidth: collapsedWidth,
                             collapsedHeight: max(24, headHeight),
                             defersGlassUntilOpen: defersGlassUntilOpen,
                             surface: notchPanelSurface(headHeight: headHeight, fade: fade),
                             backdrop: NotchWindowFrost())
        } else {
            self.liquidGlassGrouping()
                .background {
                    ZStack {
                        NotchWindowFrost().clipShape(NotchPanelShape())
                        notchPanelSurface(headHeight: headHeight, fade: fade)
                    }
                }
        }
    }

    private func notchPanelSurface(headHeight: CGFloat, fade: CGFloat) -> some View {
        let shape = NotchPanelShape()
        return PanelGlassBackdrop(shape: shape)
        // Keep the fixed-height blend out of sizing, especially while the
        // glass is still shorter than the blend during its opening frames.
        .overlay(alignment: .top) {
            notchBleedLayer(headHeight: headHeight, fade: fade)
        }
        .clipShape(shape)
        // Light catches the lower rim rather than outlining the screen edge.
        // A primary-colored stroke made the light appearance look boxed in.
        .overlay {
            shape.stroke(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.04), location: 0.25),
                    .init(color: .white.opacity(0.22), location: 1)
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
            .allowsHitTesting(false)
        }
    }

    /// A broad attachment at the top, strongest around the camera and softer
    /// at the shoulders, dissolving downward without a visible band edge.
    private func notchBleedLayer(headHeight: CGFloat, fade: CGFloat) -> some View {
        let height = headHeight + fade
        let horizontal = LinearGradient(
            stops: [
                .init(color: .black.opacity(0.65), location: 0),
                .init(color: .black.opacity(0.94), location: 0.30),
                .init(color: .black, location: 0.5),
                .init(color: .black.opacity(0.94), location: 0.70),
                .init(color: .black.opacity(0.65), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        return Color.black
            .frame(height: height)
            .mask(verticalBleedMask(headHeight: headHeight, height: height))
            .mask(horizontal)
    }

    /// Alpha falloff down the bleed: solid through the head, then smoothed out
    /// to nothing. The curve, rather than a linear ramp, is what keeps it from
    /// reading as a band.
    private func verticalBleedMask(headHeight: CGFloat, height: CGFloat) -> LinearGradient {
        let hold = min(1, headHeight / max(1, height))
        let stops = (0...64).map { index -> Gradient.Stop in
            let t = Double(index) / 64
            let u = t <= hold ? 0 : (t - hold) / max(0.0001, 1 - hold)
            let eased = u * u * (3 - 2 * u)   // smoothstep
            return Gradient.Stop(color: .black.opacity(1 - eased), location: t)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

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
    /// poke past the rounded corners. `frosted` adds the notch panel's real
    /// behind-window blur and quieter lens tint for the capture popup.
    @ViewBuilder
    func liquidGlassPopup(frosted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if frosted {
            self.liquidGlassGrouping()
                .background {
                    ZStack {
                        NotchWindowFrost()
                        PanelGlassBackdrop(shape: shape)
                    }
                    .clipShape(shape)
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04),
                                                .white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(shape)
        } else if #available(macOS 26.0, *) {
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
                .revealAwareControlGlass(tint: AppPalette.controlTint, in: shape)
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 0.75))
        } else {
            self
                .background(shape.fill(AppPalette.fieldFill))
                .overlay(shape.stroke(AppPalette.controlStroke, lineWidth: 1))
        }
    }

    /// Search and the reminder composer share a softly rounded surface with
    /// a focused accent instead of a permanent dark outline.
    func liquidGlassInputField(focused: Bool) -> some View {
        modifier(GlassInputField(focused: focused))
    }
    /// A compact capsule control such as the tag filter button, with a subtle
    /// semantic edge so its pill silhouette remains legible on glass.
    @ViewBuilder
    func liquidGlassCapsule(dimmed: Bool = false) -> some View {
        if dimmed {
            self
                .background(Capsule().fill(Color.black.opacity(0.12)))
                .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.75))
                .opacity(0.42)
        } else if #available(macOS 26.0, *) {
            self
                .revealAwareControlGlass(tint: AppPalette.controlTint, in: Capsule())
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
    func liquidGlassKeycap(refractive: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        if #available(macOS 26.0, *), refractive {
            self
                .foregroundStyle(.primary)
                .revealAwareControlGlass(tint: AppPalette.keycapTint, in: shape)
                .overlay(shape.stroke(AppPalette.keycapStroke, lineWidth: 1))
        } else {
            // Scrolling keycaps use a flat fill: native glass is drawn in a
            // separate layer and can escape the scroll viewport's clip, and a
            // material would re-sample its backdrop for every keycap on every
            // scrolled frame.
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
    func liquidGlassCapsule(tint: Color, dimmed: Bool = false) -> some View {
        if dimmed {
            self
                .background(Capsule().fill(Color.black.opacity(0.12)))
                .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.75))
                .opacity(0.42)
        } else if #available(macOS 26.0, *) {
            self
                .revealAwareControlGlass(tint: tint.opacity(0.18), in: Capsule())
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
                .revealAwareControlGlass(tint: AppPalette.controlTint, in: shape)
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
    func liquidGlassChip(tint: Color? = nil,
                         filled: Bool = false,
                         dimmed: Bool = false) -> some View {
        liquidGlassChip(in: Capsule(), tint: tint, filled: filled, dimmed: dimmed)
    }

    /// A small frosted chip with a custom silhouette, e.g. the tiny tag
    /// rectangles in reminder rows.
    @ViewBuilder
    func liquidGlassChip<S: Shape>(in shape: S,
                                   tint: Color? = nil,
                                   filled: Bool = false,
                                   dimmed: Bool = false) -> some View {
        if dimmed {
            self
                .background(shape.fill(Color.black.opacity(0.12)))
                .overlay(shape.stroke(Color.black.opacity(0.18), lineWidth: 0.75))
                .opacity(0.42)
        } else if #available(macOS 26.0, *) {
            let fill = (tint ?? Color.primary).opacity(filled ? 0.55 : 0.18)
            self
                .revealAwareControlGlass(tint: fill, in: shape)
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
            self.revealAwareControlGlass(in: Capsule())
        } else {
            self
                .background(Capsule().fill(AppPalette.surfaceFill))
                .overlay(Capsule().strokeBorder(AppPalette.controlStroke, lineWidth: 1))
        }
    }
}

/// The expensive window-server blur stays at the full panel size during the
/// reveal. It is clipped separately from the moving glass lens.
private struct NotchWindowFrost: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                BehindWindowBlur(material: .underWindowBackground)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Shared lens and directional lighting for the notch and quick-add surfaces.
/// The expensive behind-window frost is supplied separately.
private struct PanelGlassBackdrop<Surface: Shape>: View {
    let shape: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nativeNotchGlassEnabled) private var nativeGlassEnabled

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color.clear
            } else {
                // Large panels animate with the fixed blur, light and moving
                // rim first. Mount the native lens only at its final size.
                if #available(macOS 26.0, *), nativeGlassEnabled {
                    Color.clear.glassEffect(
                        .regular.tint(colorScheme == .dark
                                      ? .black.opacity(0.06) : .white.opacity(0.04)),
                        in: shape
                    )
                }
                // A small directional light gives the broad surface depth
                // without adding a second outline around its silhouette.
                LinearGradient(stops: [
                    .init(color: .white.opacity(colorScheme == .dark ? 0.06 : 0.12), location: 0),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(colorScheme == .dark ? 0.08 : 0.025), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GlassInputField: ViewModifier {
    let focused: Bool
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    @ViewBuilder
    private func surface(for content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Associate native field text with its glass foreground. Moving
            // the lens to a separate background breaks that association.
            content.revealAwareControlGlass(tint: Color.primary.opacity(0.035), in: shape)
        } else {
            content.background(shape.fill(AppPalette.fieldFill))
        }
    }

    func body(content: Content) -> some View {
        surface(for: content)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(focused ? Color.accentColor.opacity(0.6) : .clear,
                                   lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// A real behind-window blur for the borderless floating panels.
///
/// SwiftUI's `.background(.ultraThinMaterial)` inside a transparent window is a
/// translucent wash, and the Liquid Glass surface is a lens rather than a blur,
/// so neither actually blurs the desktop behind the panel. An
/// `NSVisualEffectView` with `.behindWindow` blending does, which is what gives
/// the notch panel the depth the native popover has.
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = .active
    }
}

@available(macOS 26.0, *)
private struct RevealAwareControlGlass<S: Shape>: ViewModifier {
    let tint: Color?
    let shape: S
    @Environment(\.nativeControlGlassEnabled) private var enabled

    func body(content: Content) -> some View {
        content.glassEffect(enabled ? .regular.tint(tint) : .identity, in: shape)
    }
}

extension View {
    @available(macOS 26.0, *)
    fileprivate func revealAwareControlGlass<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        modifier(RevealAwareControlGlass(tint: tint, shape: shape))
    }
}
