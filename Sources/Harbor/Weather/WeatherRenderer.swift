import AppKit
import HarborCore
import Metal
import QuartzCore

/// Draws weather sprites into a transparent Metal layer: one instanced draw call per frame.
@MainActor
final class WeatherRenderer {
    private struct Shared {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }

    // Compiled once and shared by every screen's layer.
    private static let shared: Shared? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "weatherVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "weatherFragment")
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return Shared(device: device, queue: queue, pipeline: pipeline)
    }()

    let layer = CAMetalLayer()
    private var buffer: MTLBuffer?
    private var drewSomething = true

    init?() {
        guard let shared = Self.shared else { return nil }
        layer.device = shared.device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        // Two drawables are enough at 30 fps and keep memory down on big screens.
        layer.maximumDrawableCount = 2
        layer.presentsWithTransaction = false
    }

    func resize(points: CGSize, scale: CGFloat) {
        layer.contentsScale = scale
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        if layer.drawableSize != pixels { layer.drawableSize = pixels }
    }

    /// Draws `sprites` over a cleared frame. An empty frame after an empty frame is skipped entirely.
    func draw(_ sprites: [WeatherSprite], viewport: CGSize) {
        guard let shared = Self.shared else { return }
        if sprites.isEmpty, !drewSomething { return }
        drewSomething = !sprites.isEmpty
        let bytes = max(1, sprites.count) * MemoryLayout<WeatherSprite>.stride
        if (buffer?.length ?? 0) < bytes {
            buffer = shared.device.makeBuffer(length: bytes * 2, options: .storageModeShared)
        }
        guard let buffer, let drawable = layer.nextDrawable(),
              let commands = shared.queue.makeCommandBuffer() else { return }
        sprites.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        if !sprites.isEmpty {
            var view = SIMD2<Float>(Float(viewport.width), Float(viewport.height))
            encoder.setRenderPipelineState(shared.pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&view, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: sprites.count)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Sprite { float4 rect; float4 color; float4 params; };
    struct Out {
        float4 position [[position]];
        float2 uv;
        float2 half_size;
        float4 color;
        float4 params;
    };

    vertex Out weatherVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                             const device Sprite *sprites [[buffer(0)]], constant float2 &view [[buffer(1)]]) {
        const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, -1), float2(1, 1), float2(-1, 1) };
        Sprite s = sprites[iid];
        float2 c = corners[vid];
        float2 local = c * s.rect.zw;
        float a = s.params.x;
        float2 turned = float2(local.x * cos(a) - local.y * sin(a), local.x * sin(a) + local.y * cos(a));
        float2 p = (s.rect.xy + turned) / view * 2.0 - 1.0;
        Out o;
        o.position = float4(p, 0, 1);
        o.uv = c;
        o.half_size = s.rect.zw;
        o.color = s.color;
        o.params = s.params;
        return o;
    }

    // Edge coverage for a signed distance measured in uv units.
    static float cover(float d) {
        float w = max(fwidth(d), 1e-4);
        return clamp(0.5 - d / w, 0.0, 1.0);
    }

    fragment float4 weatherFragment(Out in [[stage_in]]) {
        int shape = int(in.params.y + 0.5);
        float2 uv = in.uv;
        float r = length(uv);
        float3 rgb = in.color.rgb;
        float alpha = 0;
        switch (shape) {
        case 0: { // disc
            alpha = cover(r - 1.0);
            rgb = mix(rgb, float3(0.55, 0.6, 0.7), in.params.z * smoothstep(0.45, 1.0, r));
            break;
        }
        case 1: { // glow
            float g = max(0.0, 1.0 - r);
            alpha = g * g * 0.8 + smoothstep(0.25, 0.1, r) * 0.6;
            rgb = mix(rgb, float3(1.0), smoothstep(0.3, 0.0, r) * 0.6);
            break;
        }
        case 2: { // leaf: an almond with a midrib
            float edge = abs(uv.y) - (1.0 - uv.x * uv.x) * 0.95;
            alpha = cover(edge);
            rgb *= 1.0 - 0.35 * smoothstep(0.12, 0.0, abs(uv.y)) * step(-0.9, uv.x);
            rgb *= 0.85 + 0.15 * (uv.y * 0.5 + 0.5);
            break;
        }
        case 3: { // petal with a notch at the tip
            float body = length(float2(uv.x, uv.y * 1.05)) - 1.0;
            float notch = 0.32 - length(uv - float2(1.05, 0.0));
            alpha = cover(max(body, notch));
            rgb = mix(rgb * 1.04, rgb * 0.88, uv.x * 0.5 + 0.5);
            break;
        }
        case 4: { // shaded snowball
            alpha = cover(r - 1.0);
            float3 n = float3(uv, sqrt(max(0.0, 1.0 - r * r)));
            float light = clamp(dot(n, normalize(float3(-0.45, 0.6, 0.65))), 0.0, 1.0);
            rgb = mix(float3(0.70, 0.76, 0.88), rgb, 0.35 + 0.65 * light);
            rgb = mix(rgb, float3(0.55, 0.6, 0.72), smoothstep(0.82, 1.0, r) * 0.6);
            break;
        }
        case 5: { // pile segment
            float t = mix(in.params.z, in.params.w, uv.x * 0.5 + 0.5);
            float fy = uv.y * 0.5 + 0.5;
            float heightPts = in.half_size.y * 2.0;
            float below = (t - fy) * heightPts;
            alpha = cover(-below / heightPts * 2.0);
            // A soft rim along the top so white snow still reads over white windows.
            rgb = mix(rgb, rgb * float3(0.66, 0.72, 0.82), smoothstep(1.4, 0.0, below) * 0.55);
            rgb *= mix(0.86, 1.0, clamp(fy / max(t, 1e-3), 0.0, 1.0));
            break;
        }
        case 6: { // bubble: a thin iridescent film with a highlight
            float ring = smoothstep(0.78, 0.97, r) * cover(r - 1.0);
            float3 film = 0.6 + 0.4 * cos(6.2831 * (uv.x * 0.4 + uv.y * 0.3 + float3(0.0, 0.33, 0.67)));
            float spot = smoothstep(0.28, 0.0, length(uv - float2(-0.38, 0.4)));
            alpha = ring * 0.75 + cover(r - 1.0) * 0.06 + spot * 0.8;
            rgb = mix(film, float3(1.0), spot);
            break;
        }
        case 7: { // rect
            float2 edge = abs(uv) - 1.0;
            alpha = cover(max(edge.x, edge.y));
            break;
        }
        case 8: { // triangle pointing +x
            alpha = cover(abs(uv.y) - (1.0 - uv.x) * 0.5);
            rgb *= 0.9 + 0.1 * uv.y;
            break;
        }
        case 9: { // dandelion seed: a fluffy head on a short stalk
            float head = smoothstep(1.0, 0.35, r) * 0.55;
            float rays = pow(abs(cos(atan2(uv.y, uv.x) * 6.0)), 6.0) * smoothstep(1.0, 0.5, r) * 0.5;
            float core = smoothstep(0.22, 0.12, r);
            alpha = max(head * 0.6 + rays, core);
            rgb = mix(rgb, float3(0.55, 0.45, 0.3), core);
            break;
        }
        }
        alpha *= in.color.a;
        return float4(rgb * alpha, alpha);
    }
    """
}
