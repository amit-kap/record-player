import Foundation

/// How the tracks of a record map onto its grooves: progress 0 is the first groove, 1 the last, linear in time.
public struct RecordLayout: Sendable, Equatable {
    public struct Position: Sendable, Equatable {
        public var track: Int      // counted from 0
        public var time: Double    // seconds into that track

        public init(track: Int, time: Double) {
            self.track = track
            self.time = time
        }
    }

    /// Seconds per track. Non-positive or non-finite durations are treated as 0.
    public let durations: [Double]

    /// Seconds from the start of the record to the start of each track.
    private let startTimes: [Double]

    /// Progress distance within which a progress value snaps to a track start.
    private static let snapTolerance = 1e-4

    public init(durations: [Double]) {
        let clean = durations.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        self.durations = clean
        var starts: [Double] = []
        starts.reserveCapacity(clean.count)
        var sum = 0.0
        for d in clean {
            starts.append(sum)
            sum += d
        }
        self.startTimes = starts
    }

    public var trackCount: Int { durations.count }

    public var totalDuration: Double { durations.reduce(0, +) }

    /// Where each track starts, 0...1. Empty when there are no tracks; all zeros when totalDuration is 0.
    public var trackStarts: [Float] {
        let total = totalDuration
        guard total > 0 else { return Array(repeating: 0, count: trackCount) }
        return startTimes.map { Float($0 / total) }
    }

    /// Seconds from the start of the record. Track is clamped to the valid range, time to 0...duration of that track.
    public func elapsed(track: Int, time: Double) -> Double {
        guard trackCount > 0 else { return 0 }
        let t = min(max(track, 0), trackCount - 1)
        let d = durations[t]
        let clampedTime = time.isNaN ? 0 : min(max(time, 0), d)
        return startTimes[t] + clampedTime
    }

    /// 0...1. Returns 0 when totalDuration is 0.
    public func progress(track: Int, time: Double) -> Float {
        let total = totalDuration
        guard total > 0 else { return 0 }
        return Float(min(max(elapsed(track: track, time: time) / total, 0), 1))
    }

    /// Inverse of `progress`. Progress is clamped to 0...1. A progress exactly on a track boundary (within 1e-4 of a track start) belongs to the track that starts there, at time 0. Progress 1 is the end of the last track. With no tracks returns Position(track: 0, time: 0).
    public func position(forProgress progress: Float) -> Position {
        guard trackCount > 0 else { return Position(track: 0, time: 0) }
        let total = totalDuration
        let last = trackCount - 1
        guard total > 0 else { return Position(track: last, time: 0) }

        let p = progress.isNaN ? 0 : min(max(Double(progress), 0), 1)
        let positive = durations.indices.filter { durations[$0] > 0 }

        // Progress 1 is the end of the last track that has any length.
        if p >= 1, let lastPositive = positive.last {
            return Position(track: lastPositive, time: durations[lastPositive])
        }

        // Snap to a track start: the last positive-length track starting within tolerance.
        if let snapped = positive.last(where: { abs(p - startTimes[$0] / total) <= Self.snapTolerance }) {
            return Position(track: snapped, time: 0)
        }

        // Otherwise: the last positive-length track that starts at or before this point.
        let target = p * total
        let track = positive.last(where: { startTimes[$0] <= target }) ?? positive[0]
        let time = min(max(target - startTimes[track], 0), durations[track])
        return Position(track: track, time: time)
    }
}
