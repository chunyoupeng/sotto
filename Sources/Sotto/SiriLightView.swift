import AppKit
import Metal
import QuartzCore

/// Metal port of openless's SiriGL — Apple's new-Siri "pure light" capsule
/// (shaders originally from github.com/aaaa-zhen/siri-glsl, MIT), translated
/// from GLSL to MSL and compiled from source at runtime (no .metallib in the
/// build, so SwiftPM and the Makefile app bundle both stay untouched).
///
/// Two effects live in one layer / one render pass:
/// - **wave**: a spectral sound wave across the stage — 4 spectral samples of
///   chromatic dispersion + Lorentzian glow lines. Amplitude follows the real
///   mic level; on `phase = .orb` the wave squeezes from both ends into a
///   breathing dot at the center (recording → thinking transition).
/// - **orb**: 6 metaballs smooth-min blended into a slowly turning fluid ring
///   (the "thinking" icon). It enters gathered at the center — visually the
///   same dot the wave collapsed into — then unfolds; `merging` pulls the six
///   dots back into one circle for the "done" send-off.
///
/// All CPU-side easing (attack/release level smoothing, resolved convergence,
/// gather lifecycle, speed ramps, crossfades) is ported from SiriGL.tsx's
/// frame loop so the choreography matches openless beat for beat.
final class SiriLightView: NSView {
    enum Phase { case wave, orb }

    /// Raw mic RMS 0..1; mapped psychoacoustically before hitting the shader.
    func setLevel(_ raw: Float) { rawLevel = max(0, min(1, raw)) }

    /// Wave ⇄ orb choreography. Wave→orb: the wave converges to a dot, fades,
    /// and the orb blooms out of it. Orb→wave (new session): immediate swap.
    func setPhase(_ p: Phase) {
        guard p != phase else { return }
        phase = p
        if p == .orb {
            // Transitions are choreographed on the wall clock (`realTime`), not
            // `shaderTime`: thinking runs the shader at 1.5×, and driving the
            // crossfade with the sped-up clock desynchronized it from the
            // wave's real-time collapse (ring dispersed while the wave was
            // still expanded — the two visibly overlapped).
            orbStart = realTime
            waveFadeStart = realTime
            gather = 1
        } else {
            warmProgress = 0  // wave re-enters with its unfold animation
        }
    }

    /// >1 speeds the orb's turning (thinking); ramps continuously, no jumps.
    var speedTarget: Float = 1
    /// True pulls the six orb dots into one center circle (done/cancelled).
    var merging = false

    /// Per-mode tint over the light. `nil` keeps the full spectral rainbow
    /// (dictation); a color pushes both wave and orb toward that hue so
    /// translate/QA sessions are recognizable at a glance. Eased in the frame
    /// loop, so a mid-session mode upgrade (dictation → translate chord)
    /// fades rather than snaps.
    func setTint(_ color: NSColor?) {
        if let c = color?.usingColorSpace(.deviceRGB) {
            var t = SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
            // Normalize so the brightest channel is 1 — tinting must recolor
            // the light, not dim it.
            t /= max(t.max(), 0.001)
            tintTarget = t
            tintMixTarget = 0.85
        } else {
            tintMixTarget = 0
        }
    }

    private var tintTarget = SIMD3<Float>(1, 1, 1)
    private var tintMixTarget: Float = 0
    private var smoothTint = SIMD3<Float>(1, 1, 1)
    private var smoothTintMix: Float = 0

    /// Full reset for a fresh session (panel about to be shown).
    func restart() {
        phase = .wave
        rawLevel = 0
        smoothLevel = 0
        warmProgress = 0
        smoothResolved = Self.warmingResolved
        speedTarget = 1
        smoothSpeed = 1
        merging = false
        gather = 1
        // The mode tint is set just before show(); snap to it so a new session
        // never opens fading from the previous session's color.
        smoothTint = tintTarget
        smoothTintMix = tintMixTarget
    }

    var isAnimating = false {
        didSet {
            guard isAnimating != oldValue else { return }
            if isAnimating { link?.isPaused = false } else { link?.isPaused = true }
        }
    }

    // MARK: - Internals

    private var phase: Phase = .wave
    private var rawLevel: Float = 0
    private var smoothLevel: Float = 0
    private var smoothResolved: Float = 1
    private var warmProgress: Float = 0
    private var smoothSpeed: Float = 1
    private var gather: Float = 1
    private var shaderTime: Float = 0
    /// Wall-clock seconds since the view was created; drives all transition
    /// choreography so speed changes never warp the crossfade.
    private var realTime: Float = 0
    private var orbStart: Float = 0
    private var waveFadeStart: Float = 0
    private var lastFrame: CFTimeInterval = CACurrentMediaTime()

    /// Collapsed-but-not-a-dot starting shape for the wave's entry unfold.
    private static let warmingResolved: Float = 0.2
    /// Internal render scale (on top of backing scale) — SiriGL's RENDER_SCALE.
    private static let renderScale: CGFloat = 0.75

    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var wavePipeline: MTLRenderPipelineState?
    private var orbPipeline: MTLRenderPipelineState?
    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupMetal()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.pixelFormat = .bgra8Unorm
        l.isOpaque = false
        l.framebufferOnly = true
        return l
    }

    private func setupMetal() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            SottoLog.log("SiriLight", "no Metal device; light effects disabled")
            return
        }
        device = dev
        queue = dev.makeCommandQueue()
        metalLayer?.device = dev
        do {
            let lib = try dev.makeLibrary(source: Self.shaderSource, options: nil)
            wavePipeline = try makePipeline(dev, lib, fragment: "waveFragment")
            orbPipeline = try makePipeline(dev, lib, fragment: "orbFragment")
        } catch {
            SottoLog.log("SiriLight", "shader compile failed: \(error.localizedDescription)")
            return
        }
        let dl = displayLink(target: self, selector: #selector(frameTick))
        dl.add(to: .main, forMode: .common)
        dl.isPaused = true
        link = dl
    }

    private func makePipeline(_ dev: MTLDevice, _ lib: MTLLibrary,
                              fragment: String) throws -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "fullscreenVertex")
        desc.fragmentFunction = lib.makeFunction(name: fragment)
        let att = desc.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        // The shaders emit premultiplied light (rgb ≤ alpha = max component),
        // matching the WebGL premultipliedAlpha:true context.
        att.isBlendingEnabled = true
        att.sourceRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try dev.makeRenderPipelineState(descriptor: desc)
    }

    deinit {
        link?.invalidate()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let ml = metalLayer else { return }
        let scale = (window?.backingScaleFactor ?? 2) * Self.renderScale
        ml.contentsScale = scale
        let size = CGSize(width: max(1, bounds.width * scale),
                          height: max(1, bounds.height * scale))
        if ml.drawableSize != size { ml.drawableSize = size }
    }

    // MARK: - Frame loop (ported from SiriGL.tsx)

    private struct Uniforms {
        var resolution: SIMD2<Float>
        var orbCenter: SIMD2<Float>
        var orbSize: Float
        var time: Float
        var resolved: Float
        var level: Float
        var gather: Float
        var waveOpacity: Float
        var orbOpacity: Float
        var pad: Float = 0
        /// rgb = mode tint, w = tint mix (0 keeps the spectral rainbow).
        var tint: SIMD4<Float>
    }

    /// AudioBars-style psychoacoustic mapping: gate the noise floor,
    /// smoothstep, then pow-lift quiet speech.
    private static func visualVoice(_ raw: Float) -> Float {
        let gate: Float = 0.012, ceiling: Float = 0.34
        let gated = min(1, max(0, (raw - gate) / (ceiling - gate)))
        let eased = gated * gated * (3 - 2 * gated)
        return pow(eased, 0.42)
    }

    private static func easeOut(_ x: Float) -> Float {
        let t = min(1, max(0, x))
        return 1 - (1 - t) * (1 - t)
    }

    @objc private func frameTick() {
        guard let ml = metalLayer, let queue,
              let wavePipeline, let orbPipeline else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, now - lastFrame))
        lastFrame = now

        smoothSpeed += (speedTarget - smoothSpeed) * (1 - exp(-dt * 2.5))
        let tintK = 1 - exp(-dt * 6)
        smoothTint += (tintTarget - smoothTint) * tintK
        smoothTintMix += (tintMixTarget - smoothTintMix) * tintK
        shaderTime += dt * smoothSpeed
        realTime += dt
        let t = shaderTime

        let thinking = phase == .orb
        // Level: real mic while recording; a calm slow breath drives the dot
        // while thinking (the level loses meaning once the wave collapses).
        let target = thinking ? 0.14 + 0.07 * sin(t * 2.2) : Self.visualVoice(rawLevel)
        let attack: Float = target > smoothLevel ? 14 : 5
        smoothLevel += (target - smoothLevel) * (1 - exp(-dt * attack))

        // Entry unfold: the wave starts collapsed and blooms open (~150 ms).
        warmProgress += (1 - warmProgress) * (1 - exp(-dt * 9))
        let targetResolved: Float = thinking
            ? 0
            : Self.warmingResolved + (1 - Self.warmingResolved) * warmProgress
        let resolvedK: Float = thinking ? 2.2 : 9.0
        smoothResolved += (targetResolved - smoothResolved) * (1 - exp(-dt * resolvedK))

        // Orb gather lifecycle: enter fully gathered (catching the wave's dot),
        // hold a beat, unfold into the turning ring; merging snaps back (k=4).
        // The ring may only disperse once the wave has actually collapsed into
        // its dot — never let an open ring share the stage with an open wave.
        if thinking {
            let elapsed = realTime - orbStart
            if merging {
                gather += (1 - gather) * (1 - exp(-dt * 4.0))
            } else if elapsed > 0.3 && smoothResolved < 0.15 {
                gather += (0 - gather) * (1 - exp(-dt * 1.6))
            }
        }

        // Crossfade (CSS transitions in openless): the wave stays visible while
        // it converges, fades once it's a dot (delay .55s, dur .6s); the orb
        // blooms in over it (delay .3s, dur .7s). All on the wall clock.
        let waveOpacity: Float
        let orbOpacity: Float
        if thinking {
            waveOpacity = 1 - Self.easeOut((realTime - waveFadeStart - 0.55) / 0.6)
            orbOpacity = Self.easeOut((realTime - orbStart - 0.3) / 0.7)
        } else {
            waveOpacity = 1
            orbOpacity = 0
        }

        guard let drawable = ml.nextDrawable(),
              let cmd = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let w = Float(drawable.texture.width), h = Float(drawable.texture.height)
        // Orb stage: a centered square, 170pt in openless's 180pt-tall stage.
        let orbPx = min(h * (170.0 / 180.0), w)
        var uni = Uniforms(
            resolution: SIMD2(w, h),
            orbCenter: SIMD2(w / 2, h / 2),
            orbSize: orbPx,
            time: t,
            resolved: smoothResolved,
            level: smoothLevel,
            gather: gather,
            waveOpacity: waveOpacity,
            orbOpacity: orbOpacity,
            tint: SIMD4(smoothTint, smoothTintMix))

        if waveOpacity > 0.001 {
            enc.setRenderPipelineState(wavePipeline)
            enc.setFragmentBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if thinking && orbOpacity > 0.001 {
            enc.setRenderPipelineState(orbPipeline)
            enc.setFragmentBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Shaders (MSL port of SiriGL.tsx's GLSL)

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float2 orbCenter;
        float orbSize;
        float time;
        float resolved;
        float level;
        float gather;
        float waveOpacity;
        float orbOpacity;
        float pad;
        float4 tint;  // rgb = mode tint, w = mix (0 = spectral rainbow)
    };

    // Push the light toward the mode tint while keeping its brightness
    // structure: replace hue with tint scaled by the pixel's peak channel.
    static float3 applyTint(float3 col, float4 tint) {
        float luma = max(col.r, max(col.g, col.b));
        return mix(col, luma * tint.rgb, tint.w);
    }

    struct VSOut { float4 position [[position]]; };

    vertex VSOut fullscreenVertex(uint vid [[vertex_id]]) {
        float2 pts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VSOut o;
        o.position = float4(pts[vid], 0.0, 1.0);
        return o;
    }

    // ---- wave: siriWaveCore — spectral dispersion + Lorentzian glow lines ----

    static float3 spectral4(int s) {
        float x = float(s);
        return clamp(float3(abs(x - 3.0) - 1.0, 2.0 - abs(x - 2.0), 2.0 - abs(x - 4.0)), 0.0, 1.0);
    }

    fragment float4 waveFragment(VSOut in [[stage_in]],
                                 constant Uniforms &u [[buffer(0)]]) {
        const float PI = 3.14159265359;
        const float AMPLITUDE = 0.32, FREQ = 1.1, ABER_FREQ = 1.0, SPEED = 2.4, WAVE_SCALE = 0.6;
        const float ABERRATION = 2.6, THICKNESS = 3.0, INTENSITY = 2.0, FALLOFF = 1.7;
        const float EDGE_MASK = 0.4, EDGE_INSET = 0.0, BAND_FILL = 30000.0, BAND_THICK = 0.08, SOFTNESS = 2.5;
        const float LOW_AMP = 6.0, LOW_INT = 1.5, MID_ABER = 0.8, MID_ABAMP = 0.05, MID_SOFT = 0.4;
        const float HIGH_ABER = 0.5, HIGH_ABAMP = 0.06, UNRES_SCALE = 0.14;

        float2 R = u.resolution;
        // GL's gl_FragCoord is bottom-left origin; flip y to match.
        float2 frag = float2(in.position.x, R.y - in.position.y);
        float aspect = R.x / R.y;
        float2 p = (frag + 0.5) * 2.0 / R - 1.0;
        p.x *= aspect;
        float yScreen = p.y;
        p /= max(WAVE_SCALE, 0.1);
        float t = u.time;
        float dv = clamp(u.level, 0.0, 1.0);
        float low  = clamp(0.45 + 0.45 * sin(t * 0.8) * sin(t * 0.37 + 1.0), 0.0, 1.0) * dv;
        float mid  = clamp(0.40 + 0.40 * sin(t * 1.7 + 2.0) * sin(t * 0.53), 0.0, 1.0) * dv;
        float high = clamp(0.30 + 0.30 * sin(t * 2.9 + 4.0) * sin(t * 0.71 + 2.0), 0.0, 1.0) * dv;
        float res = clamp(u.resolved, 0.0, 1.0);
        float drift = fmod(t, 20.0 * PI) * SPEED;
        // Convergence = "both ends squeeze toward the middle": the wave-space
        // x stretches as res drops, pushing visible ripples into the center.
        float2 pw = p;
        pw.x *= mix(5.0, 1.0, res);
        float xN = pw.x / max(aspect, 1.0);
        float env = cos(PI * 0.5 * min(abs(0.9 * xN), 1.0));
        env *= env;
        float A1 = (AMPLITUDE * mix(0.14, 1.0, dv)) + 0.01 * low * LOW_AMP;
        float A2 = A1 + mid * MID_ABAMP + high * HIGH_ABAMP;
        float AB = (ABERRATION + mid * MID_ABER + high * HIGH_ABER) * res;
        float th = mix(0.1, 0.01 * THICKNESS, res);
        float inten = mix(0.1, 0.01 * (INTENSITY + low * LOW_INT), res);
        float soft = 0.01 * res * max(0.0, SOFTNESS + mid * MID_SOFT);
        float dUnres = max(length(p) - mix(0.14, UNRES_SCALE, res), 0.0);
        float yMain = A1 * env * res * sin(pw.x * FREQ + drift);
        float bandFillTh = max(BAND_THICK, 1e-4);
        float bandAmt = 1e-4 * BAND_FILL * inten;
        float3 num = float3(0.0), den = float3(0.0);
        for (int s = 0; s < 4; s++) {
            float3 hue = mix(float3(1.0), spectral4(s), res);
            den += hue;
            float ab = mix(-AB, AB, float(s) / 3.0);
            float yL = A2 * env * res * sin(pw.x * ABER_FREQ + drift + ab);
            float d = mix(dUnres, abs(p.y - yL), res);
            float lor = mix(1.0 / (1.0 + (0.02 * d) * (0.02 * d)), 1.0, res);
            float line = inten / (sqrt(d * d + soft * soft) + th);
            float lo = min(yMain, yL), hi = max(yMain, yL);
            float dBand = max(0.0, max(p.y - hi, lo - p.y));
            float band = bandAmt / (dBand + bandFillTh);
            num += hue * lor * (line + band);
        }
        float3 col = num / den;
        float dM = mix(dUnres, abs(p.y - yMain), res);
        float lorM = mix(1.0 / (1.0 + (0.02 * dM) * (0.02 * dM)), 1.0, res);
        // Restrained bloom on the collapsed dot: everything pulls inward at the
        // transition, never floods outward to the window edge.
        float boost = (1.0 - res) * (3.0 * low + 1.2);
        col += 0.5 * inten * (lorM + boost) / (sqrt(dM * dM + soft * soft) + th);
        col = pow(max(col, 0.0), float3(1.5));
        float emT = clamp((abs(yScreen) - 1.0 + EDGE_INSET) / (-max(EDGE_MASK, 1e-4)), 0.0, 1.0);
        float em = emT * emT * (3.0 - 2.0 * emT);
        float gauss = exp(-pow(xN * FALLOFF, 2.0));
        col *= em * gauss;
        col *= mix(0.55, 1.0, res);
        col = applyTint(col, u.tint);
        float a = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
        return float4(col, a) * u.waveOpacity;
    }

    // ---- orb: siriFluidDotsCore — 6 metaballs, smooth-min fused, turning ----

    static float hash11(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }
    static float settleWL(float tau, float w, float l) {
        if (tau <= 0.0) return 0.0;
        return 1.0 - exp(-l * tau) * cos(w * tau);
    }
    static float sminf(float a, float b, float k) {
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * k * 0.25;
    }
    static float3 hue2rgb(float h) {
        h = fract(h);
        float r = clamp(abs(h * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        float g = clamp(2.0 - abs(h * 6.0 - 2.0), 0.0, 1.0);
        float b = clamp(2.0 - abs(h * 6.0 - 4.0), 0.0, 1.0);
        return float3(r, g, b);
    }
    static float dotRadius(float fi, float seed, float t) {
        return 0.036 + 0.010 * sin(t * 1.3 + seed * 6.28318530718) + 0.005 * sin(t * 2.4 + fi * 1.3);
    }
    static float dotSD(float2 p, float2 pos, float r, float t, float fi, float shapeDamp) {
        float2 d = p - pos;
        float sq = 0.075 * (0.5 + 0.5 * sin(t * 0.9 + fi * 2.0)) * shapeDamp;
        float ca = cos(t * 0.35 + fi), sa = sin(t * 0.35 + fi);
        d = float2x2(float2(ca, -sa), float2(sa, ca)) * d;  // GLSL mat2(ca,-sa,sa,ca), column-major
        d *= float2(1.0 + sq, 1.0 - sq);
        return length(d) - r;
    }

    static float3 orbScene(float2 p, float t, float uGather) {
        const float TAU = 6.28318530718;
        const int N = 6;
        const float SMOOTH_K = 0.08, INTENSITY = 0.0025, FALLOFF_P = 1.35, FADE_START = 0.02, FADE_END = 0.56;
        const float ABERR = 0.005;
        const float3 SPECTRAL = float3(0.0, 0.5, 1.0) * ABERR;
        const float HUE_SPEED = 0.06, COLOR_K = 0.5, SAT = 0.01, HUE_SPAN = 0.667;
        const float MERGE_PERIOD = 6.0, STAGGER = 0.33, HOLD = 0.0;
        const float W = 4.6, L = 3.2, PIERCE = 0.12, RECOIL = 0.035, REC_LAG = 0.11;
        const float GATHER_R = 0.008, GATHER_DIM = 0.85;

        float k = floor(t / MERGE_PERIOD);
        float uPh = fract(t / MERGE_PERIOD);
        float te = uPh * MERGE_PERIOD;
        float gC = clamp(uGather, 0.0, 1.0);
        float gBright = mix(1.0, GATHER_DIM, gC) * (1.0 + 0.30 * gC);
        float3 total3 = float3(1e5);
        float3 cAcc = float3(0.0);
        float wAcc = 1e-6;
        for (int i = 0; i < N; i++) {
            float fi = float(i);
            float seed = hash11(fi);
            float ang = fi / float(N) * TAU + t * 0.35;
            float2 dir = float2(cos(ang), sin(ang));
            float R = 0.17 + 0.010 * sin(t * 1.0) + 0.007 * sin(t * 1.3 + seed * TAU);
            float pairId = fmod(fi, 3.0);
            float moverLow = fmod(k + pairId, 2.0);
            float isMover = (fi < 2.5) ? step(moverLow, 0.5) : step(0.5, moverLow);
            float goStart = pairId * STAGGER;
            float retStart = 3.0 * STAGGER + HOLD + pairId * STAGGER;
            float m = (settleWL(te - goStart, W, L) - settleWL(te - retStart, W, L)) * isMover;
            float rec = (settleWL(te - goStart - REC_LAG, W, L)
                         - settleWL(te - retStart - REC_LAG, W, L)) * (1.0 - isMover);
            float rSelf = dotRadius(fi, seed, t);
            rSelf = mix(rSelf, 0.036, gC);
            float fj = fmod(fi + 3.0, 6.0);
            float rPart = dotRadius(fj, hash11(fj), t);
            float deep = -(R + RECOIL) - PIERCE * rPart;
            float radial = mix(R, deep, m) + RECOIL * rec;
            radial = mix(radial, GATHER_R, gC);
            float2 pos = radial * dir;
            float sdR = dotSD(p - SPECTRAL.r * dir, pos, rSelf, t, fi, 1.0 - gC);
            float sdG = dotSD(p - SPECTRAL.g * dir, pos, rSelf, t, fi, 1.0 - gC);
            float sdB = dotSD(p - SPECTRAL.b * dir, pos, rSelf, t, fi, 1.0 - gC);
            total3 = float3(sminf(total3.r, sdR, SMOOTH_K),
                            sminf(total3.g, sdG, SMOOTH_K),
                            sminf(total3.b, sdB, SMOOTH_K));
            float hue = fract(fi / float(N) + t * HUE_SPEED) * HUE_SPAN;
            float3 dotCol = mix(float3(1.0), hue2rgb(hue), SAT);
            float wgt = exp(-sdG * COLOR_K);
            cAcc += wgt * dotCol;
            wAcc += wgt;
        }
        float3 sd3 = max(total3, float3(0.0)) + 1e-4;
        float3 core3 = clamp(INTENSITY / pow(sd3, float3(FALLOFF_P)), 0.0, 1.0);
        float3 edge3 = 1.0 - smoothstep(float3(FADE_START), float3(FADE_END), sd3);
        float3 bright = core3 * edge3 * gBright;
        return bright * (cAcc / wAcc);
    }

    fragment float4 orbFragment(VSOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
        float2 frag = float2(in.position.x, u.resolution.y - in.position.y);
        float2 center = float2(u.orbCenter.x, u.resolution.y - u.orbCenter.y);
        float size = max(u.orbSize, 1.0);
        float2 p = (frag - center) * 2.0 / size;
        float t = u.time;
        p /= 1.0 + 0.03 * sin(t * 1.0);
        float3 col = orbScene(p, t, u.gather);
        col *= 1.0 + 0.05 * sin(t * 1.0 + 1.0);
        col = pow(col, float3(1.0 / 1.2));
        col = min(col, float3(1.0));
        col = applyTint(col, u.tint);
        float a = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
        return float4(col, a) * u.orbOpacity;
    }
    """
}
