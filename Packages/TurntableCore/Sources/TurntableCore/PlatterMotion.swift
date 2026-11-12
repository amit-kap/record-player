import Foundation

/// Platter rotation with linear spin-up and spin-down.
public struct PlatterMotion: Sendable, Equatable {
    /// 33⅓ rpm in rad/s.
    public static let fullSpeed: Float = 2 * Float.pi * (100.0 / 3.0) / 60.0

    public var angle: Float
    public var speed: Float
    public var spinUpTime: Float
    public var spinDownTime: Float

    public init(angle: Float = 0, speed: Float = 0, spinUpTime: Float = 1.4, spinDownTime: Float = 2.2) {
        self.angle = angle
        self.speed = speed
        self.spinUpTime = spinUpTime
        self.spinDownTime = spinDownTime
    }

    public mutating func advance(by dt: Float, spinning: Bool) {
        guard dt > 0 else { return }
        let full = Self.fullSpeed
        if spinning {
            let rate = spinUpTime > 0 ? full / spinUpTime : .infinity
            speed = min(full, speed + rate * dt)
        } else {
            let rate = spinDownTime > 0 ? full / spinDownTime : .infinity
            speed = max(0, speed - rate * dt)
        }
        let twoPi = 2 * Float.pi
        var a = (angle + speed * dt).truncatingRemainder(dividingBy: twoPi)
        if a < 0 { a += twoPi }
        if a >= twoPi { a = 0 }
        angle = a
    }
}
