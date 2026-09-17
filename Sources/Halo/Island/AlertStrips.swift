import SwiftUI

/// The small alerts, all built the way the charging strip is: a badge that springs in
/// on the left with a brief glow (a ring that sweeps to a level when there is one), a
/// title that settles in beside it, and a value on the right.
struct AlertStrip<Trailing: View>: View {
    let notch: CGSize
    let side: CGFloat
    let topRadius: CGFloat
    let symbol: String
    var tint: Color = .white
    /// 0…1 draws a ring around the symbol that sweeps to this level.
    var level: Double? = nil
    let title: String
    var titleOpacity: Double = 0.92
    @ViewBuilder var trailing: Trailing

    var body: some View {
        CompactStrip(notch: notch, side: side, topRadius: topRadius) {
            HStack(spacing: 7) {
                AlertBadge(symbol: symbol, tint: tint, level: level)
                    .frame(width: 17, height: 17)
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(titleOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .alertSettle(delay: 0.14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        } trailing: {
            trailing
                .alertSettle(delay: 0.2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 6)
        }
    }
}

/// A small value on the right of an alert strip.
struct AlertValue: View {
    let text: String
    var tint: Color = .white
    var opacity: Double = 0.9

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular).monospacedDigit())
            .foregroundStyle(tint.opacity(opacity))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct AlertBadge: View {
    let symbol: String
    let tint: Color
    let level: Double?

    @State private var shown = RenderMode.isSnapshot
    @State private var sweep: Double = RenderMode.isSnapshot ? 1 : 0
    @State private var glow = false

    var body: some View {
        ZStack {
            if let level {
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: sweep * max(0.04, min(1, level)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 3.5)
                    .opacity(glow ? 0.75 : 0)
                Circle()
                    .trim(from: 0, to: sweep * max(0.04, min(1, level)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(tint)
                    .scaleEffect(shown ? 1 : 0.2)
                    .opacity(shown ? 1 : 0)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(glow ? 0.7 : 0), radius: glow ? 5 : 0)
                    .scaleEffect(shown ? 1 : 0.3)
                    .blur(radius: shown ? 0 : 3)
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            guard !RenderMode.isSnapshot else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.1)) { sweep = 1 }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.58).delay(0.12)) { shown = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeInOut(duration: 0.8)) { glow = false }
            }
        }
    }
}

private struct AlertSettle: ViewModifier {
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

extension View {
    func alertSettle(delay: Double) -> some View {
        modifier(AlertSettle(delay: delay))
    }
}
