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
