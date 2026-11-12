import Foundation
import CoreGraphics
import simd

/// Positions are on the table plane, in metres: `x` to the right, `y` of the SIMD2 = world z, toward the viewer / bottom of the screen in a top-down view.
public struct TurntableGeometry: Sendable, Equatable {
    public var spindle: SIMD2<Float>
    public var pivot: SIMD2<Float>
    public var armLength: Float
    public var recordRadius: Float
    public var leadInRadius: Float
    public var leadOutRadius: Float
    public var restSwing: Float

    public init(
        spindle: SIMD2<Float>,
        pivot: SIMD2<Float>,
        armLength: Float,
        recordRadius: Float,
        leadInRadius: Float,
        leadOutRadius: Float,
        restSwing: Float
    ) {
        self.spindle = spindle
        self.pivot = pivot
        self.armLength = armLength
        self.recordRadius = recordRadius
        self.leadInRadius = leadInRadius
        self.leadOutRadius = leadOutRadius
        self.restSwing = restSwing
    }

    /// The layout of the modelled turntable (`Turntable.usdz`): spindle and tonearm pivot on the plinth top, a 12-inch record (0.15 m radius), arm resting at 52 degrees.
    public static let standard = TurntableGeometry(
        spindle: SIMD2<Float>(-0.048, 0.0),
        pivot: SIMD2<Float>(0.164, -0.088),
        armLength: 0.2305,
        recordRadius: 0.15,
        leadInRadius: 0.146,
        leadOutRadius: 0.06,
        restSwing: 52 * Float.pi / 180
    )

    private static func rotate(_ v: SIMD2<Float>, by a: Float) -> SIMD2<Float> {
        let c = cos(a), s = sin(a)
        return SIMD2<Float>(v.x * c - v.y * s, v.x * s + v.y * c)
    }

    private var pivotToSpindle: SIMD2<Float> { spindle - pivot }

    /// Unit vector from the pivot toward the stylus.
    public func armDirection(swing: Float) -> SIMD2<Float> {
        let base = simd_normalize(pivotToSpindle)
        return Self.rotate(base, by: -swing)
    }

    public func stylusPosition(swing: Float) -> SIMD2<Float> {
        pivot + armLength * armDirection(swing: swing)
    }

    public func stylusRadius(swing: Float) -> Float {
        simd_length(stylusPosition(swing: swing) - spindle)
    }

    /// Inverse of `stylusRadius` for swing >= 0 (law of cosines).
    public func swing(forRadius radius: Float) -> Float {
        let d = simd_length(pivotToSpindle)
        let denom = 2 * d * armLength
        guard denom > 0 else { return 0 }
        let cosine = (d * d + armLength * armLength - radius * radius) / denom
        return acos(min(1, max(-1, cosine)))
    }

    /// Signed swing that points the arm at `point`.
    public func swing(toward point: SIMD2<Float>) -> Float {
        let base = simd_normalize(pivotToSpindle)
        let v = point - pivot
        guard simd_length(v) > 0 else { return 0 }
        let target = simd_normalize(v)
        // Angle from base to target is -swing.
        let cross = base.x * target.y - base.y * target.x
        let dot = base.x * target.x + base.y * target.y
        return -atan2(cross, dot)
    }

    public var leadInSwing: Float { swing(forRadius: leadInRadius) }
    public var leadOutSwing: Float { swing(forRadius: leadOutRadius) }

    public func clampedSwing(_ swing: Float) -> Float {
        min(restSwing, max(leadOutSwing, swing))
    }

    public func isOverRecord(swing: Float) -> Bool {
        let eps: Float = 1e-4
        return swing >= leadOutSwing - eps && swing <= leadInSwing + eps
    }

    /// 0 at lead-in, 1 at lead-out, linear in stylus radius.
    public func progress(swing: Float) -> Float {
        let span = leadInRadius - leadOutRadius
        guard span > 0 else { return 0 }
        let p = (leadInRadius - stylusRadius(swing: swing)) / span
        return min(1, max(0, p))
    }

    public func swing(forProgress progress: Float) -> Float {
        let p = min(1, max(0, progress))
        let radius = leadInRadius - p * (leadInRadius - leadOutRadius)
        return swing(forRadius: radius)
    }

    /// Rotation about world +y for an arm modelled along local +z.
    public func yaw(swing: Float) -> Float {
        let d = armDirection(swing: swing)
        return atan2(d.x, d.y)
    }

    public func distanceToArm(from point: SIMD2<Float>, swing: Float) -> Float {
        let a = pivot
        let b = stylusPosition(swing: swing)
        let ab = b - a
        let len2 = simd_dot(ab, ab)
        guard len2 > 0 else { return simd_length(point - a) }
        let t = min(1, max(0, simd_dot(point - a, ab) / len2))
        return simd_length(point - (a + t * ab))
    }
}
