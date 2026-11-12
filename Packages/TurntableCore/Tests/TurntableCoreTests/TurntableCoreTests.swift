import Testing
import Foundation
import CoreGraphics
import simd
@testable import TurntableCore

private let g = TurntableGeometry.standard

@Suite("TurntableGeometry")
struct GeometryTests {
    @Test func restStylusIsOutsideRecord() {
        let p = g.stylusPosition(swing: g.restSwing)
        #expect(simd_length(p - g.spindle) > g.recordRadius)
    }

    @Test func radiusRoundTrip() {
        for r: Float in [0.06, 0.1, 0.146] {
            let s = g.swing(forRadius: r)
            #expect(abs(g.stylusRadius(swing: s) - r) < 1e-4)
        }
    }

    @Test func leadInIsBeyondLeadOut() {
        #expect(g.leadInSwing > g.leadOutSwing)
    }

    @Test func swingTowardRoundTrip() {
        for s: Float in [-0.2, 0, 0.3, g.restSwing] {
            let back = g.swing(toward: g.stylusPosition(swing: s))
            #expect(abs(back - s) < 1e-4)
        }
    }

    @Test func clampedSwingBounds() {
        #expect(g.clampedSwing(10) == g.restSwing)
        #expect(g.clampedSwing(-10) == g.leadOutSwing)
        let mid = (g.leadOutSwing + g.leadInSwing) / 2
        #expect(g.clampedSwing(mid) == mid)
    }

    @Test func isOverRecord() {
        #expect(g.isOverRecord(swing: g.leadInSwing))
        #expect(g.isOverRecord(swing: g.leadOutSwing))
        #expect(!g.isOverRecord(swing: g.restSwing))
        #expect(!g.isOverRecord(swing: g.leadOutSwing - 0.05))
    }

    @Test func progressEnds() {
        #expect(abs(g.progress(swing: g.leadInSwing)) < 1e-4)
        #expect(abs(g.progress(swing: g.leadOutSwing) - 1) < 1e-4)
        #expect(g.progress(swing: g.restSwing) == 0)
        for p: Float in [0, 0.25, 0.5, 1] {
            #expect(abs(g.progress(swing: g.swing(forProgress: p)) - p) < 1e-4)
        }
    }

    @Test func yawMatchesDirection() {
        for s: Float in [-0.1, 0.2, g.restSwing] {
            let y = g.yaw(swing: s)
            let d = g.armDirection(swing: s)
            #expect(abs(sin(y) - d.x) < 1e-5)
            #expect(abs(cos(y) - d.y) < 1e-5)
        }
    }

    @Test func distanceToArm() {
        let s: Float = 0.3
        let a = g.pivot
        let b = g.stylusPosition(swing: s)
        let mid = (a + b) / 2
        #expect(g.distanceToArm(from: mid, swing: s) < 1e-5)
        let dir = g.armDirection(swing: s)
        let beyondEnd = b + dir * 0.1
        #expect(abs(g.distanceToArm(from: beyondEnd, swing: s) - 0.1) < 1e-5)
        let beforePivot = a - dir * 0.05
        #expect(abs(g.distanceToArm(from: beforePivot, swing: s) - 0.05) < 1e-5)
    }
}

@Suite("TopDownCamera")
struct CameraTests {
    let cam = TopDownCamera(target: SIMD2(0.02, -0.03), height: 0.6, verticalFOV: 40 * .pi / 180)
    let size = CGSize(width: 1200, height: 700)

    @Test func centreMapsToTarget() {
        let p = cam.tablePoint(for: CGPoint(x: 600, y: 350), in: size)
        #expect(abs(p.x - cam.target.x) < 1e-6 && abs(p.y - cam.target.y) < 1e-6)
    }

    @Test func zeroSizeReturnsTarget() {
        #expect(cam.tablePoint(for: CGPoint(x: 5, y: 5), in: .zero) == cam.target)
    }

    @Test func roundTrip() {
        let loc = CGPoint(x: 321, y: 123)
        let p = cam.tablePoint(for: loc, in: size, planeHeight: 0.02)
        let back = cam.viewLocation(for: p, in: size, planeHeight: 0.02)
        #expect(abs(back.x - loc.x) < 1e-2 && abs(back.y - loc.y) < 1e-2)
    }

    @Test(arguments: [CGSize(width: 1400, height: 700), CGSize(width: 500, height: 900)])
    func fitKeepsCornersInside(size: CGSize) {
        let half = SIMD2<Float>(0.25, 0.2)
        let fov: Float = 35 * .pi / 180
        let h = TopDownCamera.height(toFit: half, in: size, verticalFOV: fov)
        let c = TopDownCamera(target: .zero, height: h, verticalFOV: fov)
        for sx: Float in [-1, 1] {
            for sz: Float in [-1, 1] {
                let loc = c.viewLocation(for: SIMD2(half.x * sx, half.y * sz), in: size)
                #expect(loc.x >= 0 && loc.x <= size.width)
                #expect(loc.y >= 0 && loc.y <= size.height)
            }
        }
    }
}

@Suite("PlatterMotion")
struct PlatterTests {
    @Test func spinsUpToFullSpeed() {
        var m = PlatterMotion()
        for _ in 0..<140 { m.advance(by: 0.01, spinning: true) }
        #expect(abs(m.speed - PlatterMotion.fullSpeed) < 1e-3)
        for _ in 0..<100 { m.advance(by: 0.01, spinning: true) }
        #expect(m.speed <= PlatterMotion.fullSpeed)
    }

    @Test func spinsDownToZero() {
        var m = PlatterMotion(speed: PlatterMotion.fullSpeed)
        for _ in 0..<221 { m.advance(by: 0.01, spinning: false) }
        #expect(m.speed == 0)
        #expect(m.speed >= 0)
    }

    @Test func angleStaysWrapped() {
        var m = PlatterMotion()
        for _ in 0..<2000 {
            m.advance(by: 0.016, spinning: true)
            #expect(m.angle >= 0 && m.angle < 2 * .pi)
        }
    }
}
