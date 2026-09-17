import SwiftUI

/// The island's "done" animation, after Face ID on iPhone: the four corners of the
/// face frame spin in, close into a ring, and a checkmark draws itself.
struct SuccessGlyph: View {
    var size: CGFloat
    var color: Color = .green
    @State private var trigger = false

    private struct Frame {
        var corners: Double = 1
        var cornerScale: Double = 0.7
        var rotation: Double = -30
        var ring: Double = 0
        var check: Double = 0
        var pop: Double = 1
    }

    var body: some View {
        ZStack {
            FaceCorners()
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
            Circle()
                .trim(from: 0, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
            CheckShape()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: Frame(), trigger: trigger) { content, frame in
            ZStack {
                FaceCorners()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                    .scaleEffect(frame.cornerScale)
                    .rotationEffect(.degrees(frame.rotation))
                    .opacity(frame.corners)
                Circle()
                    .trim(from: 0, to: frame.ring)
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CheckShape()
                    .trim(from: 0, to: frame.check)
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
            .scaleEffect(frame.pop)
        } keyframes: { _ in
            // The frame spins in and settles…
            KeyframeTrack(\.rotation) {
                SpringKeyframe(0, duration: 0.42, spring: .snappy)
            }
            KeyframeTrack(\.cornerScale) {
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                LinearKeyframe(1, duration: 0.12)
                CubicKeyframe(0.55, duration: 0.18)
            }
            KeyframeTrack(\.corners) {
                LinearKeyframe(1, duration: 0.42)
                CubicKeyframe(0, duration: 0.16)
            }
            // …closes into a ring…
            KeyframeTrack(\.ring) {
                LinearKeyframe(0, duration: 0.4)
                CubicKeyframe(1, duration: 0.26)
            }
            // …and the checkmark draws, with a small pop at the end.
            KeyframeTrack(\.check) {
                LinearKeyframe(0, duration: 0.58)
                CubicKeyframe(1, duration: 0.24)
            }
            KeyframeTrack(\.pop) {
                LinearKeyframe(1, duration: 0.78)
                SpringKeyframe(1.12, duration: 0.1, spring: .bouncy)
                SpringKeyframe(1, duration: 0.2, spring: .smooth)
            }
        }
        .onAppear { trigger.toggle() }
    }
}

/// The four rounded corners of the Face ID frame.
struct FaceCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.08
        let box = rect.insetBy(dx: inset, dy: inset)
        let arm = box.width * 0.3
        let radius = box.width * 0.18
        var path = Path()
        // Top left
        path.move(to: CGPoint(x: box.minX, y: box.minY + arm))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addQuadCurve(to: CGPoint(x: box.minX + radius, y: box.minY), control: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX + arm, y: box.minY))
        // Top right
        path.move(to: CGPoint(x: box.maxX - arm, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + radius), control: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + arm))
        // Bottom right
        path.move(to: CGPoint(x: box.maxX, y: box.maxY - arm))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: box.maxX - radius, y: box.maxY), control: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX - arm, y: box.maxY))
        // Bottom left
        path.move(to: CGPoint(x: box.minX + arm, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - radius), control: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY - arm))
        return path
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.67))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
        return path
    }
}
