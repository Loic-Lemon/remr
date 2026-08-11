import SwiftUI

/// Palette for custom controls that remain below the system-provided glass
/// surface. Materials and system colors adapt to the user's appearance.
enum AppPalette {
    /// Input and search fields use the same translucent material in both
    /// appearances; the material itself resolves its light/dark treatment.
    static let fieldFill = AnyShapeStyle(.ultraThinMaterial)
    /// Subtle appearance-aware contrast for compact glass controls.
    static let controlTint = Color.primary.opacity(0.06)
    /// Pale appearance-aware accent for popup chrome; unlike `Color.accentColor`,
    /// this remains a restrained neutral in both light and dark appearances.
    static let popupAccent = Color.primary.opacity(0.48)
    static let controlStroke = Color.primary.opacity(0.16)
    /// Keycaps need stronger separation than ordinary fields while remaining
    /// appearance-aware.
    static let keycapFill = AnyShapeStyle(.thickMaterial)
    static let keycapTint = Color.primary.opacity(0.10)
    static let keycapStroke = Color.primary.opacity(0.28)
    /// Translucent fallback surface for transient chrome below macOS 26.
    static let surfaceFill = AnyShapeStyle(.regularMaterial)
}
