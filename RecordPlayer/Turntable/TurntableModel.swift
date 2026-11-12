import Observation
import simd
import TurntableCore

/// A physical button on the plinth.
enum TurntableControl: CaseIterable, Sendable {
    case startStop, previous, next

    /// Centre on the table plane, in metres.
    var centre: SIMD2<Float> {
        switch self {
        case .startStop: [-0.199, 0.147]
        case .previous: [-0.1585, 0.160]
        case .next: [-0.1335, 0.160]
        }
    }

    /// Half width and half depth.
    var halfSize: SIMD2<Float> {
        switch self {
        case .startStop: [0.016, 0.016]
        case .previous, .next: [0.012, 0.006]
        }
    }

    func contains(_ point: SIMD2<Float>) -> Bool {
        let offset = simd_abs(point - centre)
        return offset.x <= halfSize.x + 0.003 && offset.y <= halfSize.y + 0.003
    }
}

/// What the turntable is doing. The 3D scene and the controls both read and drive this.
@MainActor
@Observable
final class TurntableModel {
    let geometry: TurntableGeometry

    /// Where the tonearm should be.
    private(set) var targetSwing: Float
    /// The needle is meant to be on the record.
    private(set) var isNeedleDown = false
    private(set) var isDragging = false
    /// The button being held down.
    private(set) var pressedControl: TurntableControl?

    /// Where each track starts, as 0...1 between the first and last groove. Placeholder until music is loaded.
    private(set) var trackStarts: [Float] = [0, 0.19, 0.37, 0.58, 0.80]

    private var dragOffset: Float = 0

    /// How close to the arm, in metres, a press must be to grab it.
    private let grabDistance: Float = 0.040  // the tube bows up to 34 mm off the pivot-to-stylus line

    init(geometry: TurntableGeometry = .standard) {
        self.geometry = geometry
        self.targetSwing = geometry.restSwing
    }

    /// The platter turns while the needle is down, and as soon as the arm is carried over the record.
    var wantsSpin: Bool {
        isNeedleDown || (isDragging && geometry.isOverRecord(swing: targetSwing))
    }

    /// Starts carrying the tonearm if `point` is on it. Returns false when the press missed the arm.
    func beginDrag(at point: SIMD2<Float>, currentSwing: Float) -> Bool {
        let fromPivot = simd_length(point - geometry.pivot)
        guard fromPivot > 0.05,
              geometry.distanceToArm(from: point, swing: currentSwing) < grabDistance
        else { return false }
        dragOffset = currentSwing - geometry.swing(toward: point)
        isDragging = true
        isNeedleDown = false
        targetSwing = currentSwing
        return true
    }

    func drag(to point: SIMD2<Float>) {
        guard isDragging else { return }
        targetSwing = geometry.clampedSwing(geometry.swing(toward: point) + dragOffset)
    }

    /// Lets go of the tonearm: it lands on the record if it is over it, otherwise it goes back to its rest.
    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        if geometry.isOverRecord(swing: targetSwing) {
            isNeedleDown = true
        } else if targetSwing < geometry.leadInSwing {
            // Inside the last groove: settle on the last groove.
            targetSwing = geometry.leadOutSwing
            isNeedleDown = true
        } else {
            targetSwing = geometry.restSwing
        }
    }

    /// Play from the first groove, or lift the needle and return the arm.
    func togglePlay() {
        guard !isDragging else { return }
        if isNeedleDown {
            isNeedleDown = false
            targetSwing = geometry.restSwing
        } else {
            targetSwing = geometry.leadInSwing
            isNeedleDown = true
        }
    }

    /// The track under the needle, counted from 0.
    var currentTrack: Int {
        let progress = geometry.progress(swing: targetSwing) + 0.001
        return max(0, (trackStarts.lastIndex { $0 <= progress }) ?? 0)
    }

    /// Moves the needle to the start of the next track.
    func nextTrack() {
        guard !isDragging, isNeedleDown else { return }
        play(track: min(currentTrack + 1, trackStarts.count - 1))
    }

    /// Moves the needle to the start of the previous track.
    func previousTrack() {
        guard !isDragging, isNeedleDown else { return }
        play(track: max(currentTrack - 1, 0))
    }

    private func play(track: Int) {
        targetSwing = geometry.swing(forProgress: trackStarts[track])
        isNeedleDown = true
    }

    // MARK: Buttons

    /// Presses the button under `point`, if there is one.
    func press(at point: SIMD2<Float>) {
        pressedControl = TurntableControl.allCases.first { $0.contains(point) }
    }

    /// Lets the held button go. It acts only if the pointer is still on it.
    func release(at point: SIMD2<Float>) {
        guard let control = pressedControl else { return }
        pressedControl = nil
        guard control.contains(point) else { return }
        switch control {
        case .startStop: togglePlay()
        case .previous: previousTrack()
        case .next: nextTrack()
        }
    }
}
