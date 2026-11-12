import AppKit
import CoreGraphics

/// Images drawn in code, so the turntable needs no asset files.
enum TurntableTextures {
    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// The grooved surface of a record: fine concentric rings, smooth gaps between tracks, smooth run-out near the label.
    /// - Parameter trackStarts: where each track after the first begins, as 0...1 between lead-in and lead-out.
    static func vinyl(
        size: Int = 2048,
        base: CGFloat,
        leadInFraction: CGFloat,
        leadOutFraction: CGFloat,
        trackStarts: [CGFloat]
    ) -> CGImage {
        let ctx = context(width: size, height: size)
        let centre = CGPoint(x: size / 2, y: size / 2)
        let outer = CGFloat(size) / 2

        ctx.setFillColor(gray: base, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var generator = SeededGenerator(seed: 33)
        let first = leadOutFraction * outer
        let last = leadInFraction * outer
        var radius = first
        var drift: CGFloat = 0.012
        ctx.setLineWidth(1.5)
        while radius < last {
            // A slow drift gives the bands of louder and quieter grooves that read from a distance.
            drift = min(0.03, max(0.0, drift + CGFloat.random(in: -0.005...0.005, using: &generator)))
            let tone = base + drift + CGFloat.random(in: 0.0...0.022, using: &generator)
            ctx.setStrokeColor(gray: tone, alpha: 1)
            ctx.strokeEllipse(in: CGRect(
                x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
            ))
            radius += CGFloat.random(in: 1.0...2.2, using: &generator)
        }

        // Track gaps: narrow smooth bands.
        ctx.setLineWidth(max(4, CGFloat(size) / 220))
        ctx.setStrokeColor(gray: base * 0.5, alpha: 1)
        for start in trackStarts {
            let r = last - start * (last - first)
            ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        }
        return ctx.makeImage()!
    }

    /// Two soft light streaks that stay put while the record turns under them.
    static func sheen(size: Int = 1024, strength: CGFloat, innerFraction: CGFloat, angle: CGFloat) -> CGImage {
        let ctx = context(width: size, height: size)
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
        let half = Double(size) / 2
        var noise: UInt32 = 7
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) + 0.5 - half) / half
                let dy = (Double(y) + 0.5 - half) / half
                let r = (dx * dx + dy * dy).squareRoot()
                var alpha = 0.0
                if r < 1, r > Double(innerFraction) {
                    let theta = atan2(dy, dx) - Double(angle)
                    // One strong streak and a fainter one opposite, each with a soft halo.
                    let facing = cos(theta)
                    let side = facing > 0 ? 1.0 : 0.45
                    let streak = pow(abs(facing), 90) * side
                    let wide = pow(abs(facing), 12) * 0.16 * side
                    let edge = smoothstep(Double(innerFraction), Double(innerFraction) + 0.04, r)
                        * (1 - smoothstep(0.96, 1.0, r))
                    alpha = (streak + wide) * edge * Double(strength)
                }
                // Dither, so the faint end of the streak fades smoothly instead of in visible steps.
                noise = noise &* 1_664_525 &+ 1_013_904_223
                let dither = Double(noise >> 8 & 0xFFFF) / 65535 - 0.5
                let value = UInt8(max(0, min(255, alpha * 255 + (alpha > 0 ? dither : 0))))
                let i = (y * size + x) * 4
                data[i] = value
                data[i + 1] = value
                data[i + 2] = value
                data[i + 3] = value
            }
        }
        return ctx.makeImage()!
    }

    /// The label shown before any music is loaded.
    static func placeholderLabel(size: Int = 1024) -> CGImage {
        let ctx = context(width: size, height: size)
        let s = CGFloat(size)
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.91, blue: 0.86, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

        ctx.setStrokeColor(gray: 0.1, alpha: 1)
        ctx.setLineWidth(s * 0.006)
        ctx.strokeEllipse(in: CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88))

        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        draw("record-player", at: CGPoint(x: s / 2, y: s * 0.70), size: s * 0.075, weight: .semibold)
        draw("33⅓", at: CGPoint(x: s / 2, y: s * 0.24), size: s * 0.05, weight: .regular)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func draw(_ text: String, at centre: CGPoint, size: CGFloat, weight: NSFont.Weight) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(white: 0.1, alpha: 1),
            .kern: size * 0.04,
        ])
        let bounds = string.size()
        string.draw(at: CGPoint(x: centre.x - bounds.width / 2, y: centre.y - bounds.height / 2))
    }

    /// A small studio: dark room, soft overhead light and two strip lights, as an equirectangular image for reflections.
    static func studioEnvironment(width: Int = 1024) -> CGImage {
        let height = width / 2
        let ctx = context(width: width, height: height)
        let w = CGFloat(width)
        let h = CGFloat(height)

        // CoreGraphics origin is bottom-left: y = h is straight up.
        let colors = [
            CGColor(gray: 0.015, alpha: 1), CGColor(gray: 0.05, alpha: 1),
            CGColor(gray: 0.08, alpha: 1), CGColor(gray: 0.13, alpha: 1),
        ] as CFArray
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: colors,
            locations: [0, 0.5, 0.82, 1]
        )!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])

        // Strip lights partway up the walls.
        ctx.setFillColor(gray: 1, alpha: 0.9)
        for centre in [0.18, 0.62] as [CGFloat] {
            let rect = CGRect(x: w * (centre - 0.035), y: h * 0.60, width: w * 0.07, height: h * 0.2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: w * 0.01, cornerHeight: w * 0.01, transform: nil))
            ctx.fillPath()
        }
        return ctx.makeImage()!
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

/// Deterministic random numbers, so the grooves look the same on every launch.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
