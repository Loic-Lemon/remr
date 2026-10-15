import AppKit
import SwiftUI

/// Drives the notch panel's open reveal from outside the view tree.
///
/// The reveal has to restart on every presentation, but the panel's content
/// (and its navigation state) is deliberately kept between opens — replacing
/// the hosting controller's root view is not enough on its own, because a
/// SwiftUI `@State` inside a structurally identical tree survives the swap.
/// Holding the flags in an observed object owned by the app delegate sidesteps
/// that: the delegate resets and re-triggers them around each `show`.
///
/// Width and height reveal separately, with content following on its own ease.
@MainActor
final class NotchRevealController: ObservableObject {
    @Published var widthRevealed = false
    @Published var heightRevealed = false
    @Published var contentRevealed = false
    private var revealGeneration = 0

    /// Silhouette the next open unfolds from, when the panel should grow out
    /// of another surface instead of the notch strip. The calendar sets this
    /// to the visible reminders panel's size so the two read as one shape
    /// changing form. Set it after `reset()` and before `open()`; retracting
    /// and resetting return the shape home to the collapsed strip.
    var startSize: CGSize?

    nonisolated static let openingDuration: TimeInterval = 0.28
    nonisolated static let closingDuration: TimeInterval = 0.42
    let duration: TimeInterval
    let contentFadeDuration: TimeInterval

    init(duration: TimeInterval = openingDuration, contentFadeDuration: TimeInterval = 0.11) {
        self.duration = duration
        self.contentFadeDuration = contentFadeDuration
    }

    /// Width the silhouette starts from while collapsed: the morph override
    /// when one is set, otherwise the strip; never wider than the window.
    func startWidth(windowWidth: CGFloat, collapsed: CGFloat) -> CGFloat {
        min(startSize?.width ?? collapsed, windowWidth)
    }

    /// Height the silhouette starts from while collapsed, mirroring
    /// `startWidth`.
    func startHeight(windowHeight: CGFloat, collapsed: CGFloat) -> CGFloat {
        min(startSize?.height ?? collapsed, windowHeight)
    }

    func open(animated: Bool) {
        revealGeneration &+= 1
        let generation = revealGeneration
        guard animated else {
            widthRevealed = true
            heightRevealed = true
            contentRevealed = true
            return
        }
        withAnimation(.timingCurve(0.16, 0.80, 0.28, 1, duration: duration)) {
            widthRevealed = true
        }
        let heightDelay = duration * (0.011 / Self.openingDuration)
        withAnimation(.timingCurve(0.20, 0.66, 0.30, 1, duration: duration - heightDelay).delay(heightDelay)) {
            heightRevealed = true
        }
        // Delay the state change itself. Native glass can render its target
        // state immediately even when its parent's opacity animation is delayed.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.revealGeneration == generation else { return }
            withAnimation(.easeOut(duration: self.contentFadeDuration)) {
                self.contentRevealed = true
            }
        }
    }

    func retract() {
        retract(into: nil)
    }

    /// Retracts the reveal. With `size` nil the shape withdraws into the notch
    /// strip, as it always has. With a size it shrinks into that silhouette
    /// instead — the mirror of a morph open — so the surface it lands in can
    /// reveal itself over the same outline and the pair reads as one shape
    /// changing form. A morph close runs as a single eased step so the shrink
    /// is the expansion played backwards.
    func retract(into size: CGSize?) {
        revealGeneration &+= 1
        // Withdraw into the notch — or into the silhouette this retract lands
        // in — never the one this presentation grew from.
        startSize = size
        withAnimation(.easeOut(duration: 0.10)) {
            contentRevealed = false
        }
        guard size != nil else {
            withAnimation(.spring(response: 0.30, dampingFraction: 1).delay(0.035)) {
                heightRevealed = false
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 1).delay(0.10)) {
                widthRevealed = false
            }
            return
        }
        withAnimation(.easeInOut(duration: duration)) {
            heightRevealed = false
            widthRevealed = false
        }
    }

    func reset() {
        revealGeneration &+= 1
        startSize = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            widthRevealed = false
            heightRevealed = false
            contentRevealed = false
        }
    }
}

/// The notch panel's silhouette, shaped like the housing it hangs from: the
/// widest point is the top edge, and the sides curve in underneath it with a
/// concave "shoulder" — the same flare the notch and Dynamic Island draw —
/// before the bottom rounds off like the app's other floating surfaces.
///
/// A single closed subpath on purpose. An earlier version unioned a rounded
/// rectangle with two corner squares; Liquid Glass does not tessellate a
/// multi-subpath shape, and `stroke()` outlines every subpath, so it drew a
/// second border inside this one.
struct NotchPanelShape: Shape {
    var bottomRadius: CGFloat = 28
    /// A restrained flare matching the camera housing's small shoulders.
    static let topShoulder: CGFloat = 14
    var topShoulder: CGFloat = NotchPanelShape.topShoulder

    func path(in rect: CGRect) -> Path {
        let shoulder = max(0, min(topShoulder, rect.height * 0.19))
        let bottom = max(0, min(bottomRadius, rect.height / 2, (rect.width - shoulder * 2) / 2))
        let tangent: CGFloat = 0.55228475
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y))
        // Right shoulder: outward-bulging curve from the top edge into the side.
        path.addCurve(to: CGPoint(x: x + w - shoulder, y: y + shoulder),
                      control1: CGPoint(x: x + w - shoulder * tangent, y: y),
                      control2: CGPoint(x: x + w - shoulder, y: y + shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: x + w - shoulder, y: y + h - bottom))
        path.addCurve(to: CGPoint(x: x + w - shoulder - bottom, y: y + h),
                      control1: CGPoint(x: x + w - shoulder, y: y + h - bottom * (1 - tangent)),
                      control2: CGPoint(x: x + w - shoulder - bottom * (1 - tangent), y: y + h))
        path.addLine(to: CGPoint(x: x + shoulder + bottom, y: y + h))
        path.addCurve(to: CGPoint(x: x + shoulder, y: y + h - bottom),
                      control1: CGPoint(x: x + shoulder + bottom * (1 - tangent), y: y + h),
                      control2: CGPoint(x: x + shoulder, y: y + h - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: x + shoulder, y: y + shoulder))
        // Left shoulder, mirroring the right.
        path.addCurve(to: CGPoint(x: x, y: y),
                      control1: CGPoint(x: x + shoulder, y: y + shoulder * (1 - tangent)),
                      control2: CGPoint(x: x + shoulder * tangent, y: y))
        path.closeSubpath()
        return path
    }
}

/// The backdrop follows the visible outline, so its refractive bottom rim
/// travels with the panel instead of being uncovered at the end of a wipe.
/// Foreground layout and text stay at their final size throughout.
struct NotchReveal<Surface: View, Backdrop: View>: ViewModifier {
    @ObservedObject var controller: NotchRevealController
    var collapsedWidth: CGFloat
    var collapsedHeight: CGFloat
    var defersGlassUntilOpen: Bool
    var surface: Surface
    var backdrop: Backdrop

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let width = controller.widthRevealed
                ? proxy.size.width
                : controller.startWidth(windowWidth: proxy.size.width, collapsed: collapsedWidth)
            let height = controller.heightRevealed
                ? proxy.size.height
                : controller.startHeight(windowHeight: proxy.size.height, collapsed: collapsedHeight)
            ZStack(alignment: .top) {
                // The window-server blur keeps one backing size. Only its
                // clipping outline changes; resizing the effect view itself
                // forces a new backdrop allocation on every animation frame.
                backdrop
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(alignment: .top) {
                        NotchPanelShape().frame(width: width, height: height)
                    }
                surface
                    .environment(\.nativeNotchGlassEnabled, !defersGlassUntilOpen || controller.contentRevealed)
                    .frame(width: width, height: height)
                content
                    .mask(alignment: .top) {
                        NotchPanelShape().frame(width: width, height: height)
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

/// Content settles independently of the surface: the glass never fades away
/// while its silhouette is opening or retracting into the screen edge.
private struct NotchContentReveal: ViewModifier {
    @ObservedObject var controller: NotchRevealController

    func body(content: Content) -> some View {
        content
            .opacity(controller.contentRevealed ? 1 : 0)
            // Leave text at its native scale and apply diffusion only to
            // the backdrop. Filtering this tree also rasterizes its fields.
            .allowsHitTesting(controller.contentRevealed)
            .accessibilityHidden(!controller.contentRevealed)
    }
}

extension View {
    func notchReveal<Surface: View, Backdrop: View>(_ controller: NotchRevealController,
                                                  collapsedWidth: CGFloat, collapsedHeight: CGFloat,
                                                  defersGlassUntilOpen: Bool = false,
                                                  surface: Surface, backdrop: Backdrop) -> some View {
        modifier(NotchReveal(controller: controller,
                             collapsedWidth: collapsedWidth, collapsedHeight: collapsedHeight,
                             defersGlassUntilOpen: defersGlassUntilOpen,
                             surface: surface, backdrop: backdrop))
    }

    @ViewBuilder
    func notchContentReveal(_ controller: NotchRevealController?) -> some View {
        if let controller {
            modifier(NotchContentReveal(controller: controller))
        } else {
            self
        }
    }
}
