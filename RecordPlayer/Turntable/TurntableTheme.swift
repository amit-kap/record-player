import CoreGraphics
import simd

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
    /// The one lamp that lights the scene: a spot from one side that throws the shadows.
    var keyPosition: SIMD3<Float>
    var keyLight: Float
    /// The lamp's cone, in degrees: full strength inside the inner angle, dark outside the outer one.
    var keyInnerAngle: Float
    var keyOuterAngle: Float
    /// A weak light from straight above that keeps the shadow side readable. It throws no shadow.
    var fillLight: Float
    /// Strength of the room reflected in the metal and vinyl.
    var environment: Float
    /// Intensity of the small blue light the strobe lamp casts while the platter spins.
    var strobeLight: Float

    static let dark = TurntableTheme(
        ground: Finish(white: 0.05, roughness: 0.9, metallic: 0),
        vinyl: Finish(white: 0.015, roughness: 0.62, metallic: 0),
        labelGlow: 0.25,
        sheen: 0.45,
        keyPosition: [-0.6, 1.0, 0.8],
        keyLight: 26000,
        keyInnerAngle: 30,
        keyOuterAngle: 58,
        fillLight: 800,
        environment: 0.6,
        strobeLight: 600
    )
}
