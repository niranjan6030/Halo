import SwiftUI

// MARK: Power strips

/// The plug-in and unplug alerts: slim, the same height as the notch. A small ring on the
/// left sweeps to the battery level around a bolt (plugging in) or lets its colour settle
/// from green to white as the bolt slips out (unplugging); the percentage counts beside it.
struct PowerStrip: View {
    let percent: Int
    let charging: Bool
    let notch: CGSize
    let side: CGFloat
    let topRadius: CGFloat

    var body: some View {
        CompactStrip(notch: notch, side: side, topRadius: topRadius) {
            HStack(spacing: 7) {
                MiniChargeRing(percent: percent, charging: charging)
                    .frame(width: 17, height: 17)
                Text(charging ? "Charging" : "On Battery")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .shimmer(delay: 0.5, enabled: charging)
                    .settleIn(delay: 0.14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        } trailing: {
            CountingPercent(target: percent, charging: charging)
                .settleIn(delay: 0.2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 6)
        }
    }
}

/// Plugging in: the ring sweeps up to the level in green and the bolt springs in with a
/// brief glow. Unplugging: the ring is already at the level and its green drains to white
/// (red when low) while the bolt shrinks away.
private struct MiniChargeRing: View {
    let percent: Int
    let charging: Bool

    @State private var progress: Double
    @State private var bolt: Bool
    @State private var green: Bool
    @State private var glow = false

    init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
        let snapshot = RenderMode.isSnapshot
        _progress = State(initialValue: snapshot || !charging ? 1 : 0)
        _bolt = State(initialValue: snapshot ? charging : !charging)
        _green = State(initialValue: snapshot ? charging : true)
    }

    private var level: Double { Double(max(4, min(100, percent))) / 100 }
    private static let green = Color(red: 0.2, green: 0.84, blue: 0.35)
    private static let mint = Color(red: 0.55, green: 0.97, blue: 0.62)

    private var tint: Color {
        if green { return Self.green }
        return percent <= 20 ? Color(red: 1, green: 0.27, blue: 0.23) : .white
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: progress * level)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: 3.5)
                .opacity(glow ? 0.8 : 0)
            Circle()
                .trim(from: 0, to: progress * level)
                .stroke(green ? AnyShapeStyle(LinearGradient(colors: [Self.mint, Self.green], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(tint),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(green ? Self.mint : tint)
                .scaleEffect(bolt ? 1 : 0.2)
                .opacity(bolt ? 1 : 0)
        }
        .onAppear(perform: animate)
    }

    private func animate() {
        guard !RenderMode.isSnapshot else { return }
        if charging {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.0).delay(0.12)) { progress = 1 }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.55).delay(0.25)) { bolt = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.45)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.8)) { glow = false }
            }
        } else {
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) { glow = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.25)) { bolt = false }
            withAnimation(.easeInOut(duration: 0.9).delay(0.3)) { green = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.7)) { glow = false }
            }
        }
    }
}

/// The percentage, counting up to the level while charging and settling to it on unplug.
private struct CountingPercent: View {
    let target: Int
    let charging: Bool
    @State private var value: Double

    init(target: Int, charging: Bool) {
        self.target = target
        self.charging = charging
        let start = RenderMode.isSnapshot || !charging ? target : max(0, target - 12)
        _value = State(initialValue: Double(start))
    }

    var body: some View {
        CountingText(value: value, color: charging ? Color(red: 0.35, green: 0.9, blue: 0.48)
                                                   : (target <= 20 ? Color(red: 1, green: 0.3, blue: 0.25) : .white))
            .onAppear {
                guard !RenderMode.isSnapshot, charging else { return }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.0).delay(0.12)) { value = Double(target) }
            }
    }
}

private struct CountingText: View, Animatable {
    var value: Double
    let color: Color
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.5) {
            Text("\(Int(value.rounded()))")
                .font(.system(size: 12.5, weight: .regular).monospacedDigit())
            Text("%")
                .font(.system(size: 10, weight: .regular))
                .opacity(0.75)
        }
        .foregroundStyle(color)
        .animation(.easeInOut(duration: 0.8), value: color)
    }
}

/// Text arriving a beat after the island opens: from a slight blur and a few points in.
private struct SettleIn: ViewModifier {
    let delay: Double
    @State private var shown = RenderMode.isSnapshot

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 3)
            .scaleEffect(shown ? 1 : 0.9)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

/// A single soft band of light passing over text once.
private struct Shimmer: ViewModifier {
    let delay: Double
    let enabled: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.5)
                        .opacity(enabled ? 1 : 0)
                        .offset(x: geometry.size.width * phase)
                        .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                guard enabled, !RenderMode.isSnapshot else { return }
                withAnimation(.easeInOut(duration: 1.0).delay(delay)) { phase = 1.5 }
            }
    }
}

private extension View {
    func shimmer(delay: Double, enabled: Bool) -> some View {
        modifier(Shimmer(delay: delay, enabled: enabled))
    }

    func settleIn(delay: Double) -> some View {
        modifier(SettleIn(delay: delay))
    }
}

