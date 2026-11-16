import Foundation
import Metal
import RealityKit
import simd

/// What the lens is focused on. The scene writes it every frame; the blur reads it while drawing.
final class FocusSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var distance: Float = 1
    private var blur: Float = 0

    /// `distance` is metres from the camera to the sharp plane; `blur` is 0 for none, 1 for the full effect.
    func set(distance: Float, blur: Float) {
        lock.lock()
        self.distance = distance
        self.blur = blur
        lock.unlock()
    }

    var current: (distance: Float, blur: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (distance, blur)
    }
}

/// The compiled blur shader, built once per pixel format. RealityKit copies the effect value, so what must
/// outlive a frame lives here, behind a lock.
private final class BlurPipelines: @unchecked Sendable {
    private let lock = NSLock()
    private var pipelines: [[MTLPixelFormat]: any MTLRenderPipelineState] = [:]
    private var failed: Set<[MTLPixelFormat]> = []

    func pipeline(
        for device: any MTLDevice, target: MTLPixelFormat, depth: MTLPixelFormat, source: String
    ) -> (any MTLRenderPipelineState)? {
        lock.lock()
        defer { lock.unlock() }
        let key = [target, depth]
        if let pipeline = pipelines[key] { return pipeline }
        if failed.contains(key) { return nil }
        let depthFormats: Set<MTLPixelFormat> = [.depth32Float, .depth16Unorm, .depth32Float_stencil8]
        let prefix = depthFormats.contains(depth) ? "#define DEPTH_IS_DEPTH 1\n" : ""
        guard let library = try? device.makeLibrary(source: prefix + source, options: nil) else {
            failed.insert(key)
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "blurVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "blurFragment")
        descriptor.colorAttachments[0].pixelFormat = target
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            failed.insert(key)
            return nil
        }
        pipelines[key] = pipeline
        return pipeline
    }
}

/// A shallow depth of field: what is nearer or further than the focus distance is blurred, more the further off it is.
/// It runs after RealityKit has drawn the frame, on the colour and depth images.
@available(macOS 26.0, *)
struct DepthOfFieldEffect: PostProcessEffect {
    let focus: FocusSettings

    private let pipelines = BlurPipelines()
    #if DEBUG
    private var didLog = false
    #endif

    init(focus: FocusSettings) {
        self.focus = focus
    }

    private struct Uniforms {
        var focusDistance: Float
        var blur: Float
        var p22: Float
        var p32: Float
        var texel: SIMD2<Float>
        var maxRadius: Float
        var padding: Float = 0
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        let source = context.sourceColorTexture
        let depth = context.sourceDepthTexture
        let target = context.targetColorTexture
        #if DEBUG
        if !didLog, CommandLine.arguments.contains("--blur-log") {
            didLog = true
            let line = "blur: colour \(source.pixelFormat.rawValue) \(source.width)x\(source.height), "
                + "depth \(depth.pixelFormat.rawValue) \(depth.width)x\(depth.height), "
                + "target \(target.pixelFormat.rawValue), projection \(context.projection)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        #endif

        guard let pipeline = pipelines.pipeline(
            for: context.device, target: target.pixelFormat, depth: depth.pixelFormat, source: Self.shader
        ) else {
            copy(source, to: target, in: context.commandBuffer)
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let settings = focus.current
        let projection = context.projection
        var uniforms = Uniforms(
            focusDistance: max(settings.distance, 0.01),
            blur: settings.blur,
            p22: projection.columns.2.z,
            p32: projection.columns.3.z,
            texel: [1 / Float(source.width), 1 / Float(source.height)],
            // The widest blur disc, as a share of the image height.
            maxRadius: 0.024 * Float(source.height)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(depth, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func copy(_ source: any MTLTexture, to target: any MTLTexture, in commandBuffer: any MTLCommandBuffer) {
        guard source.pixelFormat == target.pixelFormat, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, to: target)
        blit.endEncoding()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float focusDistance;
        float blur;
        float p22;
        float p32;
        float2 texel;
        float maxRadius;
        float padding;
    };

    struct Varyings {
        float4 position [[position]];
        float2 uv;
    };

    vertex Varyings blurVertex(uint id [[vertex_id]]) {
        Varyings out;
        float2 corner = float2((id << 1) & 2, id & 2);
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(corner.x, 1.0 - corner.y);
        return out;
    }

    #ifdef DEPTH_IS_DEPTH
    typedef depth2d<float> DepthTexture;
    static float readDepth(DepthTexture depth, sampler s, float2 uv) { return depth.sample(s, uv); }
    #else
    typedef texture2d<float> DepthTexture;
    static float readDepth(DepthTexture depth, sampler s, float2 uv) { return depth.sample(s, uv).r; }
    #endif

    // The radius, in pixels, of the blur disc for a point at this depth.
    static float discRadius(float depth, constant Uniforms &u) {
        float distance = abs(u.p32 / (depth + u.p22));
        float off = abs(distance - u.focusDistance) / u.focusDistance;
        return clamp((off - 0.028) * 14.0, 0.0, 1.0) * u.maxRadius * u.blur;
    }

    fragment float4 blurFragment(
        Varyings in,
        texture2d<float> colour [[texture(0)]],
        DepthTexture depth [[texture(1)]],
        constant Uniforms &u [[buffer(0)]]
    ) {
        constexpr sampler smooth(filter::linear, address::clamp_to_edge);
        constexpr sampler nearest(filter::nearest, address::clamp_to_edge);

        float4 sharp = colour.sample(smooth, in.uv);
        if (u.blur < 0.004) { return sharp; }
        float radius = discRadius(readDepth(depth, nearest, in.uv), u);
        if (radius < 0.5) { return sharp; }

        // Gather over a disc on a golden-angle spiral. A sample only counts if its own blur reaches this pixel,
        // so sharp things do not smear into the blur around them.
        // The spiral is turned by a different amount at each pixel, which hides its pattern.
        const int taps = 48;
        float turn = fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715)))) * 6.2831853;
        float4 sum = sharp;
        float weight = 1.0;
        for (int i = 0; i < taps; i++) {
            float r = sqrt((float(i) + 0.5) / float(taps)) * radius;
            float a = float(i) * 2.39996323 + turn;
            float2 uv = in.uv + float2(cos(a), sin(a)) * r * u.texel;
            float reach = discRadius(readDepth(depth, nearest, uv), u);
            float w = clamp(reach - r + 1.0, 0.0, 1.0);
            sum += colour.sample(smooth, uv) * w;
            weight += w;
        }
        return sum / weight;
    }
    """
}
