import CoreGraphics

/// Every colour, finish and light level of the turntable. A new theme is a new value, not new code.
struct TurntableTheme: Sendable {
    struct Finish: Sendable {
        var white: CGFloat
        var roughness: Float
        var metallic: Float
    }

    var ground: Finish
    var vinyl: Finish
    /// How much the label glows by itself, so artwork stays vivid in a dark scene. 0...1.
    var labelGlow: Float

    /// Strength of the fixed light streaks on the spinning record, 0...1.
    var sheen: CGFloat
    var keyLight: Float
    var spotLight: Float
    var environment: Float
    /// Intensity of the small blue light the strobe lamp casts while the platter spins.
    var strobeLight: Float

    static let dark = TurntableTheme(
        ground: Finish(white: 0.02, roughness: 0.9, metallic: 0),
        vinyl: Finish(white: 0.015, roughness: 0.62, metallic: 0),
        labelGlow: 0.45,
        sheen: 0.55,
        keyLight: 1500,
        spotLight: 2200,
        environment: 1.0,
        strobeLight: 600
    )
}
