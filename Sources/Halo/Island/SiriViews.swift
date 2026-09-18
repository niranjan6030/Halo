import SwiftUI

/// Siri's colours: the pink, violet, blue and orange of the Apple Intelligence glow.
enum SiriColors {
    static let all: [Color] = [
        Color(red: 0.99, green: 0.33, blue: 0.62),
        Color(red: 0.62, green: 0.36, blue: 1.0),
        Color(red: 0.25, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.58, blue: 0.29),
        Color(red: 0.99, green: 0.33, blue: 0.62),
    ]
}

/// A living Siri orb: soft coloured light that swirls and breathes, faster while listening.
struct SiriOrb: View {
    var size: CGFloat
    var listening = true

    var body: some View {
        TimelineView(.animation) { context in
            let speed: Double = listening ? 1.6 : 0.8
            OrbFrame(size: size, t: context.date.timeIntervalSinceReferenceDate * speed, listening: listening)
        }
        .frame(width: size, height: size)
    }
}

private struct OrbFrame: View {
    let size: CGFloat
    let t: Double
    let listening: Bool

    var body: some View {
        let pulse: CGFloat = 1 + CGFloat(listening ? 0.05 : 0.02) * CGFloat(sin(t * 3))
        ZStack {
            base
            ForEach(0..<3, id: \.self) { index in blob(index) }
            core
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .scaleEffect(pulse)
    }

    private var base: some View {
        Circle()
            .fill(AngularGradient(colors: SiriColors.all, center: .center, angle: .radians(t * 1.3)))
            .blur(radius: size * 0.12)
    }

    private func blob(_ index: Int) -> some View {
        let phase: Double = t * (1.1 + Double(index) * 0.35) + Double(index) * 2.1
        let dx: CGFloat = CGFloat(cos(phase)) * size * 0.16
        let dy: CGFloat = CGFloat(sin(phase * 1.2)) * size * 0.16
        return Circle()
            .fill(SiriColors.all[index + 1].opacity(0.9))
            .frame(width: size * 0.55, height: size * 0.55)
            .offset(x: dx, y: dy)
            .blur(radius: size * 0.12)
    }

    private var core: some View {
        let scale: CGFloat = 0.7 + 0.12 * CGFloat(sin(t * 2.4))
        return Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.45), .white.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size * 0.22))
            .scaleEffect(scale)
            .blendMode(.plusLighter)
    }
}

/// Siri's waveform: soft rounded bars in Siri's colours, moving like speech.
struct SiriWave: View {
    var listening: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    bar(index, t: t)
                }
            }
        }
        .frame(width: 22, height: 16)
    }

    private func bar(_ index: Int, t: Double) -> some View {
        let wave: Double = abs(sin(t * (3.2 + Double(index) * 0.7) + Double(index)))
        let level: Double = listening ? 0.35 + 0.65 * wave : 0.25
        let colors = [SiriColors.all[index % 4], SiriColors.all[(index + 1) % 4]]
        return Capsule()
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: 2.6, height: max(3, 14 * CGFloat(level)))
    }
}

/// A single continuous microphone wave, drawn as one flowing ribbon rather than a row
/// of bars — closer to how Siri's own waveform actually reads on iPhone and Mac: no
/// discrete segments at all, just a soft shape whose outline undulates smoothly, filled
/// with a moving colour gradient and layered with glow for depth. Used on both sides of
/// the notch (the physical camera cutout means the two halves can never share pixels),
/// each seeded so they read as one wave continuing across the gap, not two unrelated
/// animations.
struct SiriMicWave: View {
    var listening: Bool
    var phaseOffset: Double = 0
    var mirrored: Bool = false

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    ribbon(w: w, h: h, t: t, spread: 1.15)
                        .blur(radius: h * 0.22)
                        .opacity(listening ? 1 : 0.55)
                    ribbon(w: w, h: h, t: t, spread: 0.8)
                        .blur(radius: h * 0.07)
                    ribbon(w: w, h: h, t: t, spread: 0.45)
                        .blur(radius: 0.5)
                        .blendMode(.plusLighter)
                }
            }
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        }
    }

    /// One filled waveform shape: a smooth top edge and a mirrored bottom edge, so it
    /// reads as a solid ribbon of varying thickness rather than a stroked line.
    private func ribbon(w: CGFloat, h: CGFloat, t: Double, spread: CGFloat) -> some View {
        let samples = 28
        let midY = h / 2
        let amp = amplitude(t: t)

        var top = Path()
        var bottom: [CGPoint] = []
        for i in 0...samples {
            let x = w * CGFloat(i) / CGFloat(samples)
            let n = Double(i) / Double(samples)
            // Envelope tapers to the edges so the ribbon feels like one continuous
            // gesture rather than a hard-edged rectangle of noise.
            let edgeTaper = sin(n * .pi)
            let y1 = sin(t * 2.6 + n * 6.2 + phaseOffset) * 0.6
            let y2 = sin(t * 4.1 + n * 3.1 + phaseOffset * 1.3) * 0.4
            let y3 = sin(t * 1.7 + n * 9.8 + phaseOffset * 0.7) * 0.3
            let ripple = abs(y1 * 0.5 + y2 * 0.3 + y3 * 0.2)
            let thickness = (0.55 + amp * (0.7 + ripple)) * edgeTaper * spread
            let yTop = midY - thickness * h * 0.5
            let yBottom = midY + thickness * h * 0.5
            if i == 0 { top.move(to: CGPoint(x: x, y: yTop)) } else { top.addLine(to: CGPoint(x: x, y: yTop)) }
            bottom.append(CGPoint(x: x, y: yBottom))
        }
        for p in bottom.reversed() { top.addLine(to: p) }
        top.closeSubpath()

        // A linear sweep along the ribbon's own length, not an angular one: an angular
        // gradient on a thin shape only ever shows a narrow slice of the wheel at a
        // time, which rendered as a flat single hue instead of the intended blend.
        let shift = CGFloat((t * 0.15 + phaseOffset).truncatingRemainder(dividingBy: 1))
        return top
            .fill(LinearGradient(colors: SiriColors.all + SiriColors.all, startPoint: UnitPoint(x: -1 + shift, y: 0.5),
                                 endPoint: UnitPoint(x: 1 + shift, y: 0.5)))
    }

    /// One slow envelope shared by the whole ribbon (not per-sample) so the wave swells
    /// and eases as a single gesture instead of many independent points jittering.
    private func amplitude(t: Double) -> Double {
        let slow = sin(t * 1.3 + phaseOffset)
        let med = sin(t * 0.7 + phaseOffset * 1.6)
        let envelope = (slow * 0.55 + med * 0.45 + 1) / 2 // 0...1
        return listening ? 0.45 + 0.55 * envelope : 0.3 + 0.15 * envelope
    }
}

/// Siri's real visual signature — not the flat app-icon artwork, but the glass
/// sphere with vibrant ribbons of colour crossing through it and a bright white-hot
/// core where they meet. A still, deliberately composed frame rather than a
/// continuous animation: five moving blurred/blended layers recomposited every
/// frame is what read as laggy, and no amount of GPU flattening reads as smoother
/// than simply not animating. `listening` still cross-fades brightness so it isn't
/// completely inert, but that's a single one-shot transition, not a running clock.
struct SiriLogo: View {
    var size: CGFloat
    var listening = true

    /// Deliberately more saturated than `SiriColors`, which reads soft and pastel
    /// at this scale — the reference is bright, almost neon.
    private static let vivid: [Color] = [
        Color(red: 0.08, green: 0.52, blue: 1.00),
        Color(red: 0.00, green: 0.90, blue: 0.78),
        Color(red: 1.00, green: 0.10, blue: 0.40),
        Color(red: 1.00, green: 0.56, blue: 0.02),
        Color(red: 0.30, green: 0.95, blue: 0.32),
    ]

    /// Fixed per ribbon, chosen once for the best-looking still composition —
    /// an asymmetric crossing pattern, not an evenly spaced pinwheel.
    private static let ribbonAngles: [Double] = [-55, -12, 24, 62, 108]

    var body: some View {
        ZStack {
            // Ambient bleed beyond the sphere's own edge.
            Circle()
                .fill(RadialGradient(colors: [Self.vivid[0].opacity(listening ? 0.3 : 0.15), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.85))
                .blur(radius: size * 0.3)
                .scaleEffect(1.5)

            ZStack {
                ForEach(0..<5, id: \.self) { i in ribbon(i) }
                // Where the ribbons cross — brightened further by the ribbons'
                // own overlap, this guarantees a hot core even when they don't
                // happen to line up.
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(listening ? 0.55 : 0.3), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.2))
                    .blendMode(.screen)
            }
            .frame(width: size, height: size)
            .compositingGroup()
            .drawingGroup()
            .clipShape(Circle())
            .background(Circle().fill(Color.black.opacity(0.55)))
            .overlay(sphereShading)
            .overlay(glassRim)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: listening)
    }

    /// One ribbon of colour, at a fixed angle — see `ribbonAngles`.
    private func ribbon(_ index: Int) -> some View {
        Ellipse()
            .fill(Self.vivid[index % Self.vivid.count])
            .frame(width: size * 1.4, height: size * 0.3)
            .blur(radius: size * 0.06)
            .opacity(listening ? 0.6 : 0.4)
            .rotationEffect(.degrees(Self.ribbonAngles[index]))
            .blendMode(.screen)
    }

    /// Subtle darkening toward the rim so the disc reads as a sphere, not a flat
    /// painted circle.
    private var sphereShading: some View {
        Circle()
            .fill(RadialGradient(colors: [.clear, .black.opacity(0.4)], center: .center,
                                 startRadius: size * 0.3, endRadius: size * 0.5))
    }

    /// A thin bright edge, brightest at top-left as if lit from there — the glass
    /// rim that makes it read as a solid orb instead of a flat gradient disc.
    private var glassRim: some View {
        Circle()
            .strokeBorder(
                AngularGradient(colors: [.white.opacity(0.5), .white.opacity(0.03),
                                         .white.opacity(0.06), .white.opacity(0.28), .white.opacity(0.5)],
                               center: .center, angle: .degrees(-45)),
                lineWidth: max(1, size * 0.03)
            )
            .blendMode(.screen)
    }
}

/// The Apple Intelligence edge light, running around the inside of the island while
/// Siri is up (the island is clipped to its outline, so the light lives within it).
struct SiriGlow: View {
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            GlowFrame(cornerRadius: cornerRadius, t: context.date.timeIntervalSinceReferenceDate)
        }
        .allowsHitTesting(false)
    }
}

private struct GlowFrame: View {
    let cornerRadius: CGFloat
    let t: Double

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius, style: .continuous)
        let gradient = AngularGradient(colors: SiriColors.all, center: .center, angle: .radians(t * 1.1))
        ZStack {
            shape.strokeBorder(gradient, lineWidth: 3.5).blur(radius: 4).opacity(0.75)
            shape.strokeBorder(gradient, lineWidth: 1.2).blur(radius: 0.4).opacity(0.9)
        }
    }
}
