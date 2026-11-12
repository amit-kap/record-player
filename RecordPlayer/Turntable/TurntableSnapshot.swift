#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import Metal
import RealityKit
import TurntableCore
import UniformTypeIdentifiers

/// Debug only: renders the turntable to a PNG without a window, so the look can be checked from the command line.
///
///     RecordPlayer --snapshot out.png [--size 1280x800] [--inset 296] [--play] [--swing 0.4]
@MainActor
enum TurntableSnapshot {
    /// Renders and returns true when the launch arguments ask for a snapshot.
    static func runIfRequested() async -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 else {
            return false
        }
        var width = 1280
        var height = 800
        if let value = value(after: "--size", in: arguments) {
            let parts = value.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { (width, height) = (parts[0], parts[1]) }
        }
        do {
            try await render(
                to: URL(fileURLWithPath: arguments[flag + 1]),
                width: width,
                height: height,
                inset: value(after: "--inset", in: arguments).flatMap(Double.init) ?? 0,
                play: arguments.contains("--play"),
                swing: value(after: "--swing", in: arguments).flatMap(Float.init)
            )
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
        }
        return true
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }

    static func render(
        to url: URL, width: Int, height: Int, inset: Double, play: Bool, swing: Float?
    ) async throws {
        let model = TurntableModel()
        let scene = try await TurntableScene(geometry: model.geometry, theme: .dark)
        let size = CGSize(width: width, height: height)
        scene.place(camera: TurntableScene.camera(for: size, trailingInset: inset))

        if let swing {
            // Carry the arm to the requested swing and let go.
            let grab = model.geometry.pivot + model.geometry.armDirection(swing: model.geometry.restSwing) * 0.2
            if model.beginDrag(at: grab, currentSwing: model.geometry.restSwing) {
                model.drag(to: model.geometry.pivot + model.geometry.armDirection(swing: swing) * 0.2)
                model.endDrag()
            }
        } else if play {
            model.togglePlay()
        }
        for _ in 0..<300 {
            scene.update(deltaTime: 1.0 / 60, model: model)
        }

        let renderer = try RealityRenderer()
        renderer.entities.append(scene.root)
        renderer.activeCamera = scene.camera

        guard let device = MTLCreateSystemDefaultDevice() else { throw CocoaError(.featureUnsupported) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw CocoaError(.featureUnsupported)
        }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        // A few frames, so shadows and lighting have settled.
        for _ in 0..<3 {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output) { _ in
                        done.resume()
                    }
                } catch {
                    done.resume()
                }
            }
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ),
            let canvas = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { throw CocoaError(.fileWriteUnknown) }

        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let composed = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, composed, nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
