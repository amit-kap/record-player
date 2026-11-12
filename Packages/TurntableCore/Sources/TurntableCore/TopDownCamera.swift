import Foundation
import CoreGraphics
import simd

/// A perspective camera looking straight down at the table. Screen right = +x, screen down = +z (SIMD2.y).
public struct TopDownCamera: Sendable, Equatable {
    public var target: SIMD2<Float>
    public var height: Float
    public var verticalFOV: Float

    public init(target: SIMD2<Float>, height: Float, verticalFOV: Float) {
        self.target = target
        self.height = height
        self.verticalFOV = verticalFOV
    }

    private func halfExtents(in size: CGSize, planeHeight: Float) -> SIMD2<Float> {
        let d = height - planeHeight
        let halfH = d * tan(verticalFOV / 2)
        let halfW = halfH * Float(size.width / size.height)
        return SIMD2<Float>(halfW, halfH)
    }

    public func tablePoint(for location: CGPoint, in size: CGSize, planeHeight: Float = 0) -> SIMD2<Float> {
        guard size.width > 0, size.height > 0 else { return target }
        let h = halfExtents(in: size, planeHeight: planeHeight)
        let x = target.x + (Float(location.x / size.width) - 0.5) * 2 * h.x
        let z = target.y + (Float(location.y / size.height) - 0.5) * 2 * h.y
        return SIMD2<Float>(x, z)
    }

    public func viewLocation(for point: SIMD2<Float>, in size: CGSize, planeHeight: Float = 0) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        let h = halfExtents(in: size, planeHeight: planeHeight)
        guard h.x != 0, h.y != 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let nx = (point.x - target.x) / (2 * h.x) + 0.5
        let ny = (point.y - target.y) / (2 * h.y) + 0.5
        return CGPoint(x: CGFloat(nx) * size.width, y: CGFloat(ny) * size.height)
    }

    /// Smallest camera height at which a rectangle of half-size `halfExtent` (scaled by `margin`) fits the view.
    public static func height(
        toFit halfExtent: SIMD2<Float>,
        in size: CGSize,
        verticalFOV: Float,
        margin: Float = 1.1
    ) -> Float {
        guard size.width > 0, size.height > 0 else { return 0 }
        let t = tan(verticalFOV / 2)
        guard t > 0 else { return 0 }
        let aspect = Float(size.width / size.height)
        let needHalfH = max(halfExtent.y * margin, halfExtent.x * margin / aspect)
        return needHalfH / t
    }
}
