import HaloCore
import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The animated bars that show audio is live, tinted with the artwork colour.
struct WaveformView: View {
    let color: Color
    let isPlaying: Bool

    private let phases: [Double] = [0, 1.7, 0.8, 2.6]
    private let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: geometry.size.width * 0.12) {
                    ForEach(phases.indices, id: \.self) { index in
                        let wave = (sin(time * speeds[index] + phases[index]) + sin(time * speeds[index] * 0.53 + phases[index] * 2)) / 2
                        let level = isPlaying ? 0.35 + 0.65 * abs(wave) : 0.18
                        Capsule()
                            .fill(color)
                            .frame(height: max(2, geometry.size.height * level))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isPlaying)
    }
}

enum Clock {
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Time counting up from a start date, refreshed live.
struct ElapsedText: View {
    let since: Date
    let size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(Clock.elapsed(context.date.timeIntervalSince(since)))
                .font(.system(size: size, weight: weight).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

struct PrivacyDots: View {
    @ObservedObject var privacy: PrivacyMonitor

    var body: some View {
        HStack(spacing: 4) {
            if privacy.cameraInUse {
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
            if privacy.microphoneInUse {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
        }
    }
}

/// A pulsing red dot, for anything recording.
struct RecordingDot: View {
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: size, height: size)
            .opacity(pulse ? 0.45 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// A round button in the expanded island: Liquid Glass when enabled, a soft
/// translucent disc otherwise.
struct IslandButton: View {
    let systemName: String
    var size: CGFloat = 18
    var diameter: CGFloat = 36
    var foreground: Color = .white
    /// nil draws the button bare (the transport controls), glass or tint otherwise.
    var tint: Color? = .white
    var label: String? = nil
    let action: () -> Void

    @ObservedObject private var settings = IslandSettings.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background { background }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .help(label ?? "")
        .accessibilityLabel(label ?? systemName)
    }

    @ViewBuilder
    private var background: some View {
        if let tint {
            if settings.liquidGlass, !RenderMode.isSnapshot, #available(macOS 26.0, *) {
                Circle()
                    .fill(tint == .white ? Color.clear : tint.opacity(0.35))
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                Circle().fill(tint == .white ? Color.white.opacity(isHovered ? 0.22 : 0.14) : tint.opacity(isHovered ? 0.45 : 0.3))
            }
        } else {
            Circle().fill(Color.white.opacity(isHovered ? 0.12 : 0))
        }
    }
}

/// A capsule-shaped text button with the same glass treatment.
struct IslandPill: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Color? = nil
    var height: CGFloat = 30
    var expand = false
    let action: () -> Void

    @ObservedObject private var settings = IslandSettings.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(prominent == nil ? Color.white : Color.black)
            .padding(.horizontal, 14)
            .frame(maxWidth: expand ? .infinity : nil)
            .frame(height: height)
            .background { background }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var background: some View {
        if let prominent {
            Capsule().fill(prominent.opacity(isHovered ? 0.85 : 1))
        } else if settings.liquidGlass, !RenderMode.isSnapshot, #available(macOS 26.0, *) {
            Capsule().fill(Color.clear).glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule().fill(Color.white.opacity(isHovered ? 0.22 : 0.14))
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Horizontal level bar used by the volume and brightness HUDs.
struct LevelBar: View {
    let level: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, level)) * geometry.size.width)
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: level)
    }
}

struct BatteryRing: View {
    let percent: Int
    var color: Color = .green

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.system(size: 8, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(width: 22, height: 22)
    }
}

/// Liquid Glass for a card inside the island, or a soft translucent panel when glass
/// is off. `interactive` gives clickable cards the glass press-and-light response.
struct GlassCard<S: Shape>: ViewModifier {
    let shape: S
    var interactive = false
    /// Colours the glass, the way Control Center tints an active module.
    var tint: Color?
    @ObservedObject private var settings = IslandSettings.shared

    func body(content: Content) -> some View {
        if settings.liquidGlass, !RenderMode.isSnapshot, #available(macOS 26.0, *) {
            content
                // macOS draws glass tints very faintly over dark backgrounds, so the colour
                // goes underneath as a gradient and the glass sits on top of it.
                .background {
                    if let tint {
                        shape.fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .glassEffect(glass, in: shape)
                // A faint light along the top edge separates glass from the glass behind it.
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.16), .clear],
                                                     startPoint: .top, endPoint: .center), lineWidth: 0.8))
        } else {
            content.background(shape.fill(tint.map { $0.opacity(0.55) } ?? Color.white.opacity(0.1)))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                           interactive: interactive, tint: tint))
    }

    func glassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: Capsule(), interactive: interactive, tint: tint))
    }

    func glassCircle(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: Circle(), interactive: interactive, tint: tint))
    }
}

/// Groups nearby glass cards so they render and blend as one, as Apple recommends.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *), !RenderMode.isSnapshot {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// ImageRenderer can't draw Liquid Glass or drop targets (it paints a placeholder),
/// so `Island --snapshots` renders the non-glass look instead.
enum RenderMode {
    static var isSnapshot = false
}

/// App icon for a bundle ID, if the app is installed.
func appIcon(for bundleID: String?) -> NSImage? {
    guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

func appName(for bundleID: String?) -> String {
    guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "App" }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

// MARK: Motion

/// Content that settles in a beat after the island opens: it rises a few points and
/// fades up, one row after another. No blur: animating blur on every row is what made
/// page changes stutter.
private struct Appearing: ViewModifier {
    let delay: Double
    @State private var shown = RenderMode.isSnapshot

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                withAnimation(.smooth(duration: 0.32).delay(delay * 0.6)) { shown = true }
            }
    }
}

extension View {
    func appearing(delay: Double = 0) -> some View {
        modifier(Appearing(delay: delay))
    }
}

/// Moving between pages the way the Dynamic Island changes activities: the old page
/// fades and shrinks a touch while the island reshapes, and the new one grows into place
/// from a short nudge in the direction of travel. Only opacity, scale and offset move,
/// which the GPU animates for free.
struct PageSlide: ViewModifier {
    let offset: CGFloat
    let progress: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset * (1 - progress))
            .opacity(progress)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
    }
}

extension AnyTransition {
    /// `step` is +1 moving to the next page, -1 to the previous one.
    static func page(step: Int) -> AnyTransition {
        let distance: CGFloat = 18 * CGFloat(step)
        return .asymmetric(
            insertion: .modifier(active: PageSlide(offset: distance, progress: 0), identity: PageSlide(offset: distance, progress: 1))
                .animation(.smooth(duration: 0.34).delay(0.06)),
            removal: .modifier(active: PageSlide(offset: -distance, progress: 0), identity: PageSlide(offset: -distance, progress: 1))
                .animation(.easeOut(duration: 0.12))
        )
    }
}

/// A compact icon or label popping into the island: it swells from small and blurred
/// with a little overshoot, as iPhone's compact views do.
private struct PopIn: ViewModifier {
    let delay: Double
    @State private var shown = RenderMode.isSnapshot

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.4)
            .blur(radius: shown ? 0 : 5)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func popIn(delay: Double = 0.08) -> some View {
        modifier(PopIn(delay: delay))
    }
}
