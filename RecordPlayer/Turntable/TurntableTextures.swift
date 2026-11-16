import AppKit
import CoreGraphics
import simd


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
        var drift: CGFloat = 0.008
        ctx.setLineWidth(1.5)
        while radius < last {
            // A slow drift gives the bands of louder and quieter grooves that read from a distance.
            drift = min(0.018, max(0.0, drift + CGFloat.random(in: -0.003...0.003, using: &generator)))
            let tone = base + drift + CGFloat.random(in: 0.0...0.012, using: &generator)
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

    /// The record's roughness: fine grooves are a little rough; the smooth bands between tracks and the run-out are
    /// glossier.
    static func vinylRoughness(
        size: Int = 1024,
        grooves: CGFloat,
        smooth: CGFloat,
        leadInFraction: CGFloat,
        leadOutFraction: CGFloat,
        trackStarts: [CGFloat]
    ) -> CGImage {
        let ctx = context(width: size, height: size)
        let centre = CGPoint(x: size / 2, y: size / 2)
        let outer = CGFloat(size) / 2
        let first = leadOutFraction * outer
        let last = leadInFraction * outer

        ctx.setFillColor(gray: smooth, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        ctx.setFillColor(gray: grooves, alpha: 1)
        ctx.addEllipse(in: CGRect(x: centre.x - last, y: centre.y - last, width: last * 2, height: last * 2))
        ctx.addEllipse(in: CGRect(x: centre.x - first, y: centre.y - first, width: first * 2, height: first * 2))
        ctx.fillPath(using: .evenOdd)

        ctx.setLineWidth(max(2, CGFloat(size) / 440))
        ctx.setStrokeColor(gray: smooth, alpha: 1)
        for start in trackStarts {
            let r = last - start * (last - first)
            ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
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

    /// A cover as a round label's image: the centre square of the cover, filling a square of `size` pixels.
    static func coverLabel(_ cover: CGImage, size: Int) -> CGImage {
        let ctx = context(width: size, height: size)
        let scale = CGFloat(size) / CGFloat(min(cover.width, cover.height))
        let width = CGFloat(cover.width) * scale
        let height = CGFloat(cover.height) * scale
        ctx.interpolationQuality = .high
        ctx.draw(cover, in: CGRect(
            x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height
        ))
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

extension TurntableTextures {
    /// A 360° image turned about the upright axis and then tipped about a level one, in degrees. Float pixels, so
    /// lamps brighter than white keep their strength. Everything dimmer than `lampLevel` is darkened, the more the
    /// dimmer it is, so a bright room becomes a dark one with only its lamps left.
    static func turned(_ image: CGImage, turn: Float, tilt: Float, lampLevel: Float, width: Int = 1024) -> CGImage {
        let height = width / 2
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        func canvas() -> CGContext {
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 32, bytesPerRow: width * 16,
                space: space, bitmapInfo: info
            )!
        }
        let source = canvas()
        source.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let result = canvas()
        let from = source.data!.bindMemory(to: SIMD4<Float>.self, capacity: width * height)
        let to = result.data!.bindMemory(to: SIMD4<Float>.self, capacity: width * height)
        // Each pixel of the result looks back along the rotation to where it came from.
        let back = (simd_quatf(angle: tilt * .pi / 180, axis: [1, 0, 0])
            * simd_quatf(angle: turn * .pi / 180, axis: [0, 1, 0])).inverse
        for y in 0..<height {
            let latitude = (0.5 - (Float(y) + 0.5) / Float(height)) * .pi
            for x in 0..<width {
                let longitude = ((Float(x) + 0.5) / Float(width) - 0.5) * 2 * .pi
                let direction = back.act([cos(latitude) * sin(longitude), sin(latitude), cos(latitude) * cos(longitude)])
                let u = atan2(direction.x, direction.z) / (2 * .pi) + 0.5
                let v = 0.5 - asin(max(-1, min(1, direction.y))) / .pi
                let column = min(width - 1, max(0, Int(u * Float(width))))
                let row = min(height - 1, max(0, Int(v * Float(height))))
                let pixel = from[row * width + column]
                let brightness = max(0, (pixel.x + pixel.y + pixel.z) / 3)
                let kept = min(1, brightness / lampLevel)
                to[y * width + x] = SIMD4(pixel.x * kept * kept, pixel.y * kept * kept, pixel.z * kept * kept, 1)
            }
        }
        return result.makeImage()!
    }
}
