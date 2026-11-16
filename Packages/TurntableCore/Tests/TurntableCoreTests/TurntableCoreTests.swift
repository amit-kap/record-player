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

@Suite("RecordLayout")
struct RecordLayoutTests {
    let layout = RecordLayout(durations: [60, 120, 60])

    @Test func trackStartsAreCumulativeFractions() {
        #expect(layout.trackCount == 3)
        #expect(layout.totalDuration == 240)
        #expect(layout.trackStarts == [0, 0.25, 0.75])
    }

    @Test func progressMidTrack() {
        #expect(abs(layout.progress(track: 1, time: 60) - 0.5) < 1e-6)
        #expect(abs(layout.progress(track: 0, time: 30) - 0.125) < 1e-6)
        #expect(abs(layout.elapsed(track: 2, time: 10) - 190) < 1e-9)
    }

    @Test func roundTripAtTrackStarts() {
        for n in 0..<layout.trackCount {
            let pos = layout.position(forProgress: layout.progress(track: n, time: 0))
            #expect(pos.track == n)
            #expect(pos.time == 0)
        }
    }

    @Test func roundTripAtTrackStartsWithAwkwardDurations() {
        let l = RecordLayout(durations: [187.3, 241.9, 203.17, 95.5, 312.04, 77.7, 150.01])
        for n in 0..<l.trackCount {
            let pos = l.position(forProgress: l.progress(track: n, time: 0))
            #expect(pos.track == n)
            #expect(pos.time == 0)
        }
    }

    @Test func roundTripMidTrack() {
        for (track, time) in [(0, 17.5), (1, 59.9), (1, 119.0), (2, 33.3)] {
            let pos = layout.position(forProgress: layout.progress(track: track, time: time))
            #expect(pos.track == track)
            #expect(abs(pos.time - time) < 0.05)
        }
    }

    @Test func clamping() {
        #expect(layout.elapsed(track: -5, time: 10) == 10)
        #expect(layout.elapsed(track: 99, time: 10) == 190)
        #expect(layout.elapsed(track: 0, time: -3) == 0)
        #expect(layout.elapsed(track: 0, time: 1000) == 60)
        #expect(layout.progress(track: 99, time: 1000) == 1)
        #expect(layout.position(forProgress: -1) == RecordLayout.Position(track: 0, time: 0))
        let end = layout.position(forProgress: 7)
        #expect(end.track == 2 && end.time == 60)
    }

    @Test func progressOneIsEndOfLastTrack() {
        let pos = layout.position(forProgress: 1)
        #expect(pos.track == 2)
        #expect(pos.time == 60)
    }

    @Test func emptyLayout() {
        let l = RecordLayout(durations: [])
        #expect(l.trackCount == 0)
        #expect(l.totalDuration == 0)
        #expect(l.trackStarts.isEmpty)
        #expect(l.elapsed(track: 3, time: 5) == 0)
        #expect(l.progress(track: 3, time: 5) == 0)
        #expect(l.position(forProgress: 0.5) == RecordLayout.Position(track: 0, time: 0))
    }

    @Test func allZeroDurations() {
        let l = RecordLayout(durations: [0, -4, .nan, .infinity])
        #expect(l.durations == [0, 0, 0, 0])
        #expect(l.totalDuration == 0)
        #expect(l.trackStarts == [0, 0, 0, 0])
        #expect(l.progress(track: 1, time: 5) == 0)
        let pos = l.position(forProgress: 0.5)
        #expect(pos.track == 3 && pos.time == 0)
    }

    @Test func zeroLengthTracksAreSkipped() {
        let l = RecordLayout(durations: [0, 100, 0, 100, 0])
        #expect(l.trackStarts == [0, 0, 0.5, 0.5, 1])
        #expect(l.position(forProgress: 0) == RecordLayout.Position(track: 1, time: 0))
        #expect(l.position(forProgress: 0.5) == RecordLayout.Position(track: 3, time: 0))
        #expect(l.position(forProgress: 1) == RecordLayout.Position(track: 3, time: 100))
    }
}

@Suite("SceneCamera")
struct SceneCameraTests {
    let fov: Float = 20 * .pi / 180
    let sizes = [CGSize(width: 1280, height: 800), CGSize(width: 800, height: 500), CGSize(width: 600, height: 900)]
    let topFraming = CameraFraming(
        target: .zero, direction: SIMD3(0, 1, 0), up: SIMD3(0, 0, -1), halfExtent: SIMD2(0.23, 0.18))

    @Test func agreesWithTopDownCamera() throws {
        for size in sizes {
            let cam = SceneCamera.fitting(topFraming, in: size, verticalFOV: fov)
            let h = TopDownCamera.height(toFit: topFraming.halfExtent, in: size, verticalFOV: fov)
            #expect(abs(cam.position.y - h) < 1e-4)
            let top = TopDownCamera(target: .zero, height: h, verticalFOV: fov)
            for (fx, fy) in [(0.0, 0.0), (0.5, 0.5), (0.1, 0.9), (0.8, 0.2), (1.0, 1.0)] {
                let loc = CGPoint(x: fx * size.width, y: fy * size.height)
                for ph: Float in [0, 0.035] {
                    let a = try #require(cam.tablePoint(for: loc, in: size, planeHeight: ph))
                    let b = top.tablePoint(for: loc, in: size, planeHeight: ph)
                    #expect(abs(a.x - b.x) < 1e-4 && abs(a.y - b.y) < 1e-4)
                }
            }
        }
    }

    @Test func obliqueRoundTrip() throws {
        let size = CGSize(width: 1000, height: 700)
        let framing = CameraFraming(
            target: .zero, direction: SIMD3(0.3, 0.8, 0.9), up: SIMD3(0, 1, 0), halfExtent: SIMD2(0.23, 0.18))
        let cam = SceneCamera.fitting(framing, in: size, verticalFOV: fov)
        for (x, z) in [(0, 0), (0.1, -0.05), (-0.12, 0.08), (0.05, 0.1)] as [(Float, Float)] {
            for h: Float in [0, 0.02, 0.035] {
                let loc = try #require(cam.viewLocation(for: SIMD3(x, h, z), in: size))
                let p = try #require(cam.tablePoint(for: loc, in: size, planeHeight: h))
                #expect(abs(p.x - x) < 1e-3 && abs(p.y - z) < 1e-3)
            }
        }
    }

    @Test func centreMapsToTarget() throws {
        let size = CGSize(width: 900, height: 600)
        let framing = CameraFraming(
            target: SIMD3(0.05, 0, -0.02), direction: SIMD3(0.3, 0.8, 0.9), up: SIMD3(0, 1, 0), halfExtent: SIMD2(0.2, 0.15))
        let cam = SceneCamera.fitting(framing, in: size, verticalFOV: fov)
        let p = try #require(cam.tablePoint(for: CGPoint(x: 450, y: 300), in: size))
        #expect(abs(p.x - 0.05) < 1e-4 && abs(p.y + 0.02) < 1e-4)
    }

    @Test func tablePointNilCases() {
        let size = CGSize(width: 800, height: 600)
        let level = SceneCamera(position: SIMD3(0, 0.5, -1), target: SIMD3(0, 0.5, 0), up: SIMD3(0, 1, 0), verticalFOV: fov)
        #expect(level.tablePoint(for: CGPoint(x: 400, y: 100), in: size) == nil)
        let down = SceneCamera.fitting(topFraming, in: size, verticalFOV: fov)
        #expect(down.tablePoint(for: CGPoint(x: 1, y: 1), in: .zero) == nil)
        #expect(down.tablePoint(for: CGPoint(x: 1, y: 1), in: CGSize(width: 0, height: 10)) == nil)
    }

    @Test func viewLocationNilBehindCamera() {
        let size = CGSize(width: 800, height: 600)
        let cam = SceneCamera.fitting(topFraming, in: size, verticalFOV: fov)
        #expect(cam.viewLocation(for: SIMD3(0, 5, 0), in: size) == nil)
        #expect(cam.viewLocation(for: .zero, in: .zero) == nil)
    }

    private func cam(_ pos: SIMD3<Float>, fov: Float = 0.4) -> SceneCamera {
        SceneCamera(position: pos, target: SIMD3(0, 0, 0.1), up: SIMD3(0, 1, 0), verticalFOV: fov)
    }

    private func finite(_ c: SceneCamera) -> Bool {
        (0..<3).allSatisfy { c.position[$0].isFinite && c.target[$0].isFinite && c.up[$0].isFinite } && c.verticalFOV.isFinite
    }

    @Test func interpolateEndpointsAndClamping() {
        let a = cam(SIMD3(0, 1, 0.1), fov: 0.3)
        let b = cam(SIMD3(0.4, 0.3, 0.8), fov: 0.5)
        #expect(SceneCamera.interpolate(from: a, to: b, progress: 0) == a)
        #expect(SceneCamera.interpolate(from: a, to: b, progress: 1) == b)
        #expect(SceneCamera.interpolate(from: a, to: b, progress: -3) == a)
        #expect(SceneCamera.interpolate(from: a, to: b, progress: 7) == b)
    }

    @Test func interpolateMidpointLength() {
        let a = cam(SIMD3(0, 1, 0.1))
        let b = cam(SIMD3(0.4, 0.3, 0.8))
        let m = SceneCamera.interpolate(from: a, to: b, progress: 0.5)
        let la = simd_length(a.position - a.target)
        let lb = simd_length(b.position - b.target)
        #expect(abs(simd_length(m.position - m.target) - (la + lb) / 2) < 1e-4)
        #expect(abs(m.verticalFOV - 0.4) < 1e-6)
        #expect(abs(simd_length(m.up) - 1) < 1e-5)
    }

    @Test func interpolateDegenerateCases() {
        let a = cam(SIMD3(0.2, 0.7, 0.5))
        let same = SceneCamera.interpolate(from: a, to: a, progress: 0.5)
        #expect(finite(same))
        #expect(simd_length(same.position - a.position) < 1e-4)

        let b = cam(SIMD3(0, 1, 0.1))
        let opposite = SceneCamera(position: SIMD3(0, -1, 0.1), target: b.target, up: b.up, verticalFOV: b.verticalFOV)
        for p: Float in [0.25, 0.5, 0.75] {
            let m = SceneCamera.interpolate(from: b, to: opposite, progress: p)
            #expect(finite(m))
            #expect(abs(simd_length(m.position - m.target) - 1) < 1e-4)
        }
    }
}

@Suite("CoverColor")
struct CoverColorTests {
    @Test func sameTitleSameHue() {
        #expect(CoverColor.hue(for: "Cyberpunk") == CoverColor.hue(for: "Cyberpunk"))
    }

    @Test func hueStaysInRange() {
        for title in ["", "O christmas tree", "Aggressive trailer intro", "Cyberpunk cyberpunk music", "日本語"] {
            let hue = CoverColor.hue(for: title)
            #expect(hue >= 0 && hue < 1)
        }
    }

    @Test func differentTitlesGetClearlyDifferentHues() {
        let titles = ["O christmas tree", "Aggressive trailer intro", "Cyberpunk cyberpunk music"]
        let hues = titles.map(CoverColor.hue(for:))
        for i in hues.indices {
            for j in hues.indices where j > i {
                let d = abs(hues[i] - hues[j])
                #expect(min(d, 1 - d) >= 0.08, "\(titles[i]) and \(titles[j]) are too close")
            }
        }
    }
}

@Suite("Leaving room")
struct LeavingRoomTests {
    /// Looking straight down at the deck, with the top of the picture toward the back.
    let framing = CameraFraming(
        target: SIMD3(0.01, 0.02, -0.03), direction: [0, 1, 0], up: [0, 0, -1], halfExtent: SIMD2(0.25, 0.19)
    )
    let fov: Float = 30 * .pi / 180

    @Test func noRoomLeavesFramingUnchanged() {
        #expect(framing.leavingRoom(in: CGSize(width: 800, height: 500)) == framing)
    }

    @Test(arguments: [
        (CGSize(width: 800, height: 500), CGFloat(300), CGFloat(170)),
        (CGSize(width: 1280, height: 800), 332, 182),
        (CGSize(width: 1600, height: 500), 0, 182),
        (CGSize(width: 1100, height: 900), 332, 0),
        (CGSize(width: 1000, height: 400), 200, 200),
    ])
    func extentFitsCentredBetweenSides(size: CGSize, left: CGFloat, right: CGFloat) throws {
        let camera = SceneCamera.fitting(framing.leavingRoom(left: left, right: right, in: size), in: size, verticalFOV: fov)
        // The original extent with the fitting margin, measured from the original target.
        let half = framing.halfExtent * SceneCamera.fittingMargin
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for sx: Float in [-1, 1] {
            for sz: Float in [-1, 1] {
                let corner = framing.target + SIMD3(half.x * sx, 0, half.y * sz)
                let location = try #require(camera.viewLocation(for: corner, in: size))
                xs.append(location.x)
                ys.append(location.y)
            }
        }
        #expect(xs.min()! >= left - 1 && xs.max()! <= size.width - right + 1)
        #expect(ys.min()! >= -1 && ys.max()! <= size.height + 1)
        #expect(abs((xs.min()! + xs.max()!) / 2 - (left + size.width - right) / 2) < 1)
        #expect(abs((ys.min()! + ys.max()!) / 2 - size.height / 2) < 1)
    }

    @Test func roomOnlyAtTheLeftMovesThePictureRight() throws {
        let size = CGSize(width: 1000, height: 600)
        let camera = SceneCamera.fitting(framing.leavingRoom(left: 300, in: size), in: size, verticalFOV: fov)
        let centre = try #require(camera.viewLocation(for: framing.target, in: size))
        #expect(centre.x > size.width / 2)
    }
}

@Suite("RecordChange")
struct RecordChangeTests {
    private func step(_ change: inout RecordChange, home: Bool = true, stopped: Bool = true, ready: Bool = true,
                      dt: Float = 0.1) -> RecordChange.Events {
        change.advance(by: dt, armIsHome: home, platterIsStopped: stopped, incomingIsReady: ready)
    }

    @Test func waitsForTheArmAndThePlatter() {
        var change = RecordChange(hasOutgoing: true, hasIncoming: true)
        for _ in 0..<20 {
            #expect(step(&change, home: false) == [])
            #expect(step(&change, stopped: false) == [])
        }
        #expect(change.phase == .waiting)
        _ = step(&change)
        #expect(change.phase == .lifting)
    }

    @Test func swapsOnceWhenTheOldRecordIsOff() {
        var change = RecordChange(hasOutgoing: true, hasIncoming: true)
        var swaps = 0
        var finished = false
        var phasesAtSwap: [RecordChange.Phase] = []
        for _ in 0..<100 {
            let events = step(&change)
            if events.contains(.swap) { swaps += 1; phasesAtSwap.append(change.phase) }
            if events.contains(.finished) { finished = true; break }
        }
        #expect(swaps == 1 && finished)
        #expect(phasesAtSwap == [.dropping])
    }

    @Test func holdsTheSwapUntilTheIncomingRecordIsReady() {
        var change = RecordChange(hasOutgoing: true, hasIncoming: true)
        for _ in 0..<30 { #expect(!step(&change, ready: false).contains(.swap)) }
        #expect(change.phase == .lifting && change.progress == 1)
        #expect(step(&change).contains(.swap))
    }

    @Test func emptyPlatterGetsARecordWithoutLifting() {
        var change = RecordChange(hasOutgoing: false, hasIncoming: true)
        #expect(step(&change, ready: false) == [])
        #expect(step(&change) == .swap)
        #expect(change.phase == .dropping)
    }

    @Test func removingARecordEndsAfterTheLift() {
        var change = RecordChange(hasOutgoing: true, hasIncoming: false)
        var last: RecordChange.Events = []
        for _ in 0..<20 where !last.contains(.finished) { last = step(&change) }
        #expect(last == [.swap, .finished])
    }

    @Test func easingRunsFromEndToEnd() {
        #expect(RecordChange.liftEase(0) == 0 && RecordChange.liftEase(1) == 1)
        #expect(RecordChange.dropHeight(0) == 1)
        #expect(abs(RecordChange.dropHeight(1)) < 1e-5)
        var previous: Float = 1
        for i in 0...80 {
            let h = RecordChange.dropHeight(Float(i) / 100)
            #expect(h <= previous + 1e-6)
            previous = h
        }
        for i in 0...100 { #expect(RecordChange.dropHeight(Float(i) / 100) >= 0) }
    }
}
