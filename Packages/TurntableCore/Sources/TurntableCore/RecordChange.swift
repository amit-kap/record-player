import Foundation

/// The timing of swapping the record on the platter. The old record waits until the arm is home and the platter
/// has stopped, lifts off, and the new one drops on. This holds only the clock and the order; the scene draws it.
public struct RecordChange: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Nothing moves yet: the arm is going home and the platter is slowing.
        case waiting
        /// The old record rises away.
        case lifting
        /// The new record comes down onto the platter.
        case dropping
    }

    /// What happened in one `advance`.
    public struct Events: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// The old record is fully off: the new one becomes the current record now.
        public static let swap = Events(rawValue: 1)
        /// The change is over.
        public static let finished = Events(rawValue: 2)
    }

    public static let liftDuration: Float = 0.6
    public static let dropDuration: Float = 0.7
    /// How long the platter takes to stop from full speed while a record is waiting to be changed, instead of
    /// its usual slow spin-down.
    public static let brakeTime: Float = 0.8
    /// The platter counts as stopped below this share of its full speed.
    public static let stoppedBelow: Float = 0.02
    /// Where in the drop the record touches down; after that it only settles.
    static let touchdown: Float = 0.8
    /// How far the record springs back up after touching down, as a share of the drop height.
    static let settleHeight: Float = 0.02

    public private(set) var phase: Phase = .waiting
    /// 0...1 through the current phase.
    public private(set) var progress: Float = 0
    public let hasOutgoing: Bool
    public let hasIncoming: Bool
    /// The swap has happened.
    public private(set) var isSwapped = false

    /// A change from a record (or an empty platter) to another. They must not both be empty.
    public init(hasOutgoing: Bool, hasIncoming: Bool) {
        self.hasOutgoing = hasOutgoing
        self.hasIncoming = hasIncoming
    }

    /// Moves the clock on. Nothing moves until the arm is home and the platter has stopped, and the swap waits
    /// until the incoming record is ready to be drawn.
    public mutating func advance(by dt: Float, armIsHome: Bool, platterIsStopped: Bool, incomingIsReady: Bool) -> Events {
        var events: Events = []
        switch phase {
        case .waiting:
            guard armIsHome, platterIsStopped else { return [] }
            if hasOutgoing {
                phase = .lifting
                progress = 0
            } else {
                guard incomingIsReady else { return [] }
                events.formUnion(startDrop())
            }
        case .lifting:
            progress = min(1, progress + dt / Self.liftDuration)
            if progress >= 1, incomingIsReady { events.formUnion(startDrop()) }
        case .dropping:
            progress = min(1, progress + dt / Self.dropDuration)
            if progress >= 1 { events.insert(.finished) }
        }
        return events
    }

    private mutating func startDrop() -> Events {
        isSwapped = true
        guard hasIncoming else { return [.swap, .finished] }
        phase = .dropping
        progress = 0
        return .swap
    }

    /// How far the old record has gone, 0 on the platter and 1 gone: a slow start, then away.
    public static func liftEase(_ t: Float) -> Float {
        let t = min(max(t, 0), 1)
        return t * t
    }

    /// The new record's height above the platter as a share of the drop height: 1 at the start, 0 at touchdown,
    /// then a small spring back and rest.
    public static func dropHeight(_ t: Float) -> Float {
        let t = min(max(t, 0), 1)
        if t < touchdown {
            let u = 1 - t / touchdown
            return u * u * u
        }
        return max(0, settleHeight * sin(Float.pi * (t - touchdown) / (1 - touchdown)))
    }
}
