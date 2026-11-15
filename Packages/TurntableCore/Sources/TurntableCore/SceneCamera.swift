import Foundation
import CoreGraphics
import simd

/// What a camera view must show: a point to look at, the side to look from, and how much around the point stays visible.
public struct CameraFraming: Sendable, Equatable {
    public var target: SIMD3<Float>
    /// From the target toward the camera. Need not be unit length.
    public var direction: SIMD3<Float>
    public var up: SIMD3<Float>
    /// Half width and half height, in metres, that must stay visible around the target, measured in the plane through the target that faces the camera.
    public var halfExtent: SIMD2<Float>

    public init(target: SIMD3<Float>, direction: SIMD3<Float>, up: SIMD3<Float>, halfExtent: SIMD2<Float>) {
        self.target = target
        self.direction = direction
        self.up = up
        self.halfExtent = halfExtent
    }
}

/// A perspective camera anywhere in the scene. World y is up; the table is the plane y = 0; table points are SIMD2(x, z).
public struct SceneCamera: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    public var verticalFOV: Float   // radians

    public init(position: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>, verticalFOV: Float) {
        self.position = position
        self.target = target
        self.up = up
        self.verticalFOV = verticalFOV
    }

    // MARK: Basis

    private static func normalized(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let l = simd_length(v)
        guard l.isFinite, l > 1e-12 else { return fallback }
        return v / l
    }

    /// Forward, right and true-up unit vectors.
    private var basis: (f: SIMD3<Float>, r: SIMD3<Float>, u: SIMD3<Float>) {
        let f = Self.normalized(target - position, fallback: SIMD3<Float>(0, 0, -1))
        var r = simd_cross(f, up)
        if simd_length(r) < 1e-9 {
            // up is parallel to the view direction; pick any perpendicular.
            let alt: SIMD3<Float> = abs(f.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, 1)
            r = simd_cross(f, alt)
        }
        r = Self.normalized(r, fallback: SIMD3<Float>(1, 0, 0))
        let u = simd_cross(r, f)
        return (f, r, u)
    }

    // MARK: Fitting

    /// The nearest camera on the framing's direction at which `halfExtent * margin` fits a view of `size`.
    public static func fitting(
        _ framing: CameraFraming,
        in size: CGSize,
        verticalFOV: Float,
        margin: Float = 1.1
    ) -> SceneCamera {
        var distance: Float = 0
        let t = tan(verticalFOV / 2)
        if size.width > 0, size.height > 0, t > 0 {
            let aspect = Float(size.width / size.height)
            let needHalfH = max(framing.halfExtent.y * margin, framing.halfExtent.x * margin / aspect)
            distance = needHalfH / t
        }
        let dir = normalized(framing.direction, fallback: SIMD3<Float>(0, 1, 0))
        return SceneCamera(
            position: framing.target + dir * distance,
            target: framing.target,
            up: framing.up,
            verticalFOV: verticalFOV
        )
    }

    // MARK: Projection

    /// Where the ray through a view location meets the horizontal plane y = planeHeight, as (x, z). Nil when the size is empty, the ray is parallel to the plane, or the plane is behind the camera.
    public func tablePoint(for location: CGPoint, in size: CGSize, planeHeight: Float = 0) -> SIMD2<Float>? {
        guard size.width > 0, size.height > 0 else { return nil }
        let t = tan(verticalFOV / 2)
        let aspect = Float(size.width / size.height)
        let b = basis
        let sx = (Float(location.x / size.width) - 0.5) * 2 * t * aspect
        let sy = (Float(location.y / size.height) - 0.5) * 2 * t
        let dir = b.f + b.r * sx - b.u * sy
        guard abs(dir.y) > 1e-9 else { return nil }
        let s = (planeHeight - position.y) / dir.y
        guard s.isFinite, s > 0 else { return nil }
        let p = position + dir * s
        return SIMD2<Float>(p.x, p.z)
    }

    /// Where a world point appears in the view. Nil when the size is empty or the point is not in front of the camera.
    public func viewLocation(for point: SIMD3<Float>, in size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        let t = tan(verticalFOV / 2)
        guard t > 0 else { return nil }
        let aspect = Float(size.width / size.height)
        let b = basis
        let v = point - position
        let depth = simd_dot(v, b.f)
        guard depth > 1e-6 else { return nil }
        let x = simd_dot(v, b.r) / depth
        let y = simd_dot(v, b.u) / depth
        let nx = x / (2 * t * aspect) + 0.5
        let ny = -y / (2 * t) + 0.5
        return CGPoint(x: CGFloat(nx) * size.width, y: CGFloat(ny) * size.height)
    }

    // MARK: Interpolation

    /// A camera between two others, for animating a change of view. progress is clamped to 0...1. The target and the up vector are interpolated linearly (up renormalised); the offset from target to camera has its direction interpolated along the great arc (slerp) and its length linearly; verticalFOV linearly. progress 0 returns `from` exactly and 1 returns `to` exactly.
    public static func interpolate(from: SceneCamera, to: SceneCamera, progress: Float) -> SceneCamera {
        let p = progress.isNaN ? 0 : min(max(progress, 0), 1)
        if p == 0 { return from }
        if p == 1 { return to }

        let target = from.target + (to.target - from.target) * p
        let upMix = from.up + (to.up - from.up) * p
        let up = normalized(upMix, fallback: normalized(from.up, fallback: SIMD3<Float>(0, 1, 0)))
        let fov = from.verticalFOV + (to.verticalFOV - from.verticalFOV) * p

        let o0 = from.position - from.target
        let o1 = to.position - to.target
        let l0 = simd_length(o0)
        let l1 = simd_length(o1)
        let length = l0 + (l1 - l0) * p

        let tiny: Float = 1e-9
        let dir: SIMD3<Float>
        if l0 < tiny && l1 < tiny {
            dir = SIMD3<Float>(0, 1, 0)
        } else if l0 < tiny {
            dir = o1 / l1
        } else if l1 < tiny {
            dir = o0 / l0
        } else {
            dir = slerp(o0 / l0, o1 / l1, p)
        }

        return SceneCamera(position: target + dir * length, target: target, up: up, verticalFOV: fov)
    }

    /// Great-arc interpolation between unit vectors, safe for near-parallel and near-opposite inputs.
    private static func slerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let d = min(max(simd_dot(a, b), -1), 1)
        if d > 0.9995 {
            return normalized(a + (b - a) * t, fallback: a)
        }
        if d < -0.9995 {
            // Nearly opposite: the arc is ambiguous, so swing through a vector perpendicular to a.
            let axis: SIMD3<Float> = abs(a.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let perp = normalized(simd_cross(a, axis), fallback: SIMD3<Float>(1, 0, 0))
            let angle = Float.pi * t
            return a * cos(angle) + perp * sin(angle)
        }
        let theta = acos(d)
        let s = sin(theta)
        let wa = sin((1 - t) * theta) / s
        let wb = sin(t * theta) / s
        return normalized(a * wa + b * wb, fallback: a)
    }
}
