import CoreGraphics
import simd

/// Every colour, finish and light level of the turntable. A new theme is a new value, not new code.
///
/// The deck is lit the way a dark, glossy product is photographed: a studio around it that shows up as
/// reflections, one lamp that throws the shadows (the key), and a thin light from behind that draws the edges
/// (the rim).
struct TurntableTheme: Sendable {
    struct Finish: Sendable {
        var white: CGFloat
        var roughness: Float
        var metallic: Float
    }

    /// A lamp: where it stands, how bright it is in lumen, its colour, and its cone in degrees.
    struct Lamp: Sendable {
        var position: SIMD3<Float>
        var intensity: Float
        var color: SIMD3<Float>
        var innerAngle: Float
        var outerAngle: Float
    }

    /// The table the deck stands on: dark brushed metal that mirrors the lamps and the studio.
    struct Surface: Sendable {
        var finish: Finish
        /// How strongly the brushing stretches reflections into streaks, 0...1.
        var brushed: Float
        /// How clearly the deck is mirrored in the table, 0...1.
        var mirror: Float
        /// How much of the studio the table mirrors, 0...1. Low, so the deck's reflection reads against a dark
        /// table.
        var studio: Float
    }

    var surface: Surface
    var strobeDots: Finish
    var vinyl: Finish
    /// Roughness of the smooth bands between tracks and of the run-out.
    var vinylSmooth: Float
    /// How strongly the grooves stretch a highlight into a streak across the record, 0...1.
    var vinylStreak: Float
    var label: Finish

    /// The lamp that throws the shadows.
    var key: Lamp
    /// The key is drawn as this many lamps spread over a disc of `keySize` metres, so shadow edges are soft.
    var keySize: Float
    var keySamples: Int
    /// A light from behind that draws the far edges. It throws no shadow.
    var rim: Lamp

    /// The studio around the deck, mirrored in the metal and the vinyl: a photographed 360° image in the app's
    /// resources, without its extension. It is turned about the deck and then tipped forward, in degrees, so its
    /// lamps stand high behind the deck where the table and the record mirror them.
    var studio: String
    var studioTurn: Float
    var studioTilt: Float
    /// The room in the image is darkened below this brightness, so mostly its lamps are mirrored.
    var studioLampLevel: Float
    /// Strength of the studio's light on the deck.
    var environment: Float
    /// Intensity of the small blue light the strobe lamp casts while the platter spins.
    var strobeLight: Float

    static let dark = TurntableTheme(
        surface: Surface(finish: Finish(white: 0.30, roughness: 0.3, metallic: 1), brushed: 0.0, mirror: 0.7, studio: 1.0),
        strobeDots: Finish(white: 0.42, roughness: 0.5, metallic: 0),
        vinyl: Finish(white: 0.012, roughness: 0.38, metallic: 0),
        vinylSmooth: 0.16,
        vinylStreak: 0.85,
        label: Finish(white: 0.85, roughness: 0.6, metallic: 0),
        key: Lamp(
            position: [-0.75, 1.15, 0.45], intensity: 46000, color: [1.0, 0.93, 0.84],
            innerAngle: 16, outerAngle: 42
        ),
        keySize: 0.07,
        keySamples: 5,
        rim: Lamp(
            position: [0.7, 0.55, -1.0], intensity: 13000, color: [0.82, 0.90, 1.0],
            innerAngle: 20, outerAngle: 50
        ),
        studio: "studio",
        studioTurn: 90,
        studioTilt: 75,
        studioLampLevel: 4,
        environment: 1.8,
        strobeLight: 350
    )
}
