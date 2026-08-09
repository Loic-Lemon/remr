import SwiftUI

/// The app's light glass palette: a near-transparent popover with input and
/// search fields that are maximally see-through, defined by a hairline
/// outline instead of a fill.
enum AppPalette {
    /// Input and search field fill: just a whisper of frost.
    static let fieldFill = AnyShapeStyle(.ultraThinMaterial.opacity(0.35))
    /// Subtle hairline outline around fields.
    static let fieldStroke = Color.primary.opacity(0.12)
    /// Opaque surface for transient chrome (the completion toast).
    static let surface = Color.white
}
