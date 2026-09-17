import SwiftUI

/// The island outline: flush with the top of the screen, flaring outward where it
/// meets the menu bar (like the notch itself), with rounded bottom corners.
///
/// `neckWidth` is the width where the island meets the top of the screen, and it
/// animates on its own spring. While it lags behind the body the island pours out
/// of the notch through a narrow neck — the genie effect — and while collapsing
/// the neck closes first, so the island is drawn back into the notch.
struct IslandShape: Shape {
    var neckWidth: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(neckWidth, AnimatablePair(topRadius, bottomRadius)) }
        set {
            neckWidth = newValue.first
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        guard width > 1, height > 1 else { return Path() }

        let top = max(0, min(topRadius, width / 4, height / 2))
        let bottom = max(0, min(bottomRadius, (width - top * 2) / 2, height - top))
        // How far the neck sits inside the body on each side. It goes negative while
        // a wide card collapses: the top briefly overhangs as it is pulled in.
        let inset = min((width - min(neckWidth, width * 1.6)) / 2, width / 2 - top - 1)
        let sideBottom = height - bottom
        let bend = (sideBottom - top) * 0.55

        var path = Path()
        // Left flare into the menu bar.
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + inset + top, y: rect.minY))
        // Left side: a smooth S from the neck out to the full body width.
        path.addCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + sideBottom),
                      control1: CGPoint(x: rect.minX + inset + top, y: rect.minY + top + bend),
                      control2: CGPoint(x: rect.minX + top, y: rect.minY + sideBottom - bend))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.minY + sideBottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - inset - top, y: rect.minY + top),
                      control1: CGPoint(x: rect.maxX - top, y: rect.minY + sideBottom - bend),
                      control2: CGPoint(x: rect.maxX - inset - top, y: rect.minY + top + bend))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: rect.minY),
                          control: CGPoint(x: rect.maxX - inset - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Content arriving in the island comes in with it: it fades up from slightly
/// small and soft, quickly enough that the island is never an empty black box.
struct IslandContentTransition: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        // Like iPhone: content blooms out of the island's middle as it grows, sharpening
        // from a soft blur, and melts back into it on the way out.
        content
            .opacity(min(1, progress * progress * 1.8))
            .blur(radius: (1 - progress) * 8)
            .scaleEffect(x: 0.84 + 0.16 * progress, y: 0.7 + 0.3 * progress, anchor: .top)
            .offset(y: (progress - 1) * 6)
    }
}

extension AnyTransition {
    static var island: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandContentTransition(progress: 0),
                                 identity: IslandContentTransition(progress: 1))
                .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.04)),
            removal: .modifier(active: IslandContentTransition(progress: 0),
                               identity: IslandContentTransition(progress: 1))
                .animation(.easeIn(duration: 0.12))
        )
    }
}

/// The island's body. Around the notch it is pure black, exactly like the notch
/// itself; as a card it becomes dark Liquid Glass, fading to solid black at the top
/// so it still flows out of the notch. Both looks are always present and cross-fade
/// by `cardAmount`, so the island is never swapped for a new view mid-animation.
struct IslandSurface: View {
    let shape: IslandShape
    let cardAmount: Double
    let glass: Bool
    let notchHeight: CGFloat

    var body: some View {
        let usesGlass = glass && !RenderMode.isSnapshot
        ZStack {
            if usesGlass, #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(Color.black.opacity(0.52)), in: shape)
                    .opacity(cardAmount)
                shape
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: min(0.45, notchHeight / 190)),
                            .init(color: .black.opacity(0.35), location: min(0.8, (notchHeight + 46) / 190)),
                            .init(color: .black.opacity(0.18), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom))
                    .opacity(cardAmount)
                shape
                    .stroke(LinearGradient(colors: [.clear, .white.opacity(0.14)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    .opacity(cardAmount)
                shape
                    .fill(Color.black)
                    .opacity(1 - cardAmount)
            } else {
                shape.fill(Color.black)
            }
        }
    }
}
