// Renders the promo's kinetic title cards to ProRes-quality H.264 clips, frame by frame.
// Usage: swift titles.swift <outDir>
import AppKit
import SwiftUI

let fps = 60.0
let size = CGSize(width: 1920, height: 1080)

// MARK: Easing

func ease(_ x: Double) -> Double { // easeOutExpo-ish, Apple-like settle
    let c = min(1, max(0, x))
    return c == 1 ? 1 : 1 - pow(2, -10 * c)
}
func easeInOut(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
}
/// A slight overshoot-and-settle, the spring feel Apple's own kinetic type uses —
/// noticeably livelier than a plain ease-out with no bounce at all.
func easeOutBack(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    let s = 1.70158
    let c2 = c - 1
    return c2 * c2 * ((s + 1) * c2 + s) + 1
}

let brand = LinearGradient(colors: [Color(red: 0.49, green: 0.42, blue: 1.0), Color(red: 0.93, green: 0.36, blue: 0.75),
                                    Color(red: 1.0, green: 0.62, blue: 0.32)], startPoint: .leading, endPoint: .trailing)
/// Same hues used for Halo's own Siri glow — reused here so the film and the app feel
/// like one family, not a generic gradient bolted on top.
let auroraColors: [Color] = [
    Color(red: 0.99, green: 0.33, blue: 0.62), Color(red: 0.62, green: 0.36, blue: 1.0),
    Color(red: 0.25, green: 0.62, blue: 1.0), Color(red: 1.0, green: 0.58, blue: 0.29),
]

// MARK: Animated background

/// A slow, living backdrop — soft blurred colour blobs drifting on independent sine
/// paths over a near-black base, instead of a flat `Color.black`. `seed` offsets each
/// scene's motion so consecutive cards don't all breathe in lockstep, and `bias` tints
/// which hue leads, so a card can lean warm or cool without a whole new system.
struct AnimatedBackground: View {
    let t: Double
    var seed: Double = 0
    var bias: Int = 0
    var intensity: Double = 1

    var body: some View {
        let w: CGFloat = 1920, h: CGFloat = 1080
        ZStack {
            Color(red: 0.03, green: 0.025, blue: 0.045)
            ForEach(0..<4, id: \.self) { i in
                let c = auroraColors[(i + bias) % auroraColors.count]
                let phase = t * (0.09 + Double(i) * 0.035) + seed + Double(i) * 1.7
                let x = w * (0.5 + 0.34 * CGFloat(cos(phase)))
                let y = h * (0.5 + 0.34 * CGFloat(sin(phase * 0.8)))
                let scale = 1 + 0.12 * CGFloat(sin(t * 0.15 + Double(i)))
                Circle()
                    .fill(c)
                    .frame(width: 620, height: 620)
                    .scaleEffect(scale)
                    .position(x: x, y: y)
                    .blur(radius: 180)
                    .opacity(0.5 * intensity)
                    .blendMode(.screen)
            }
            // Vignette keeps the centre — where the type sits — the darkest, cleanest
            // part of the frame, so the glow reads as depth rather than clutter.
            RadialGradient(colors: [.clear, Color(red: 0.02, green: 0.015, blue: 0.03).opacity(0.9)],
                          center: .center, startRadius: 260, endRadius: 900)
            // A whisper of grain keeps large blurred fields from banding on export.
            Noise(opacity: 0.025)
        }
        .frame(width: w, height: h)
        .clipped()
    }
}

/// Cheap per-pixel-ish grain via layered low-opacity ellipses would be slow to render
/// 60x/scene; a single static noise pattern redrawn each frame at a fixed seed is
/// indistinguishable once compressed, and costs nothing extra to compute.
struct Noise: View {
    let opacity: Double
    var body: some View {
        Canvas { context, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<900 {
                let x = CGFloat.random(in: 0..<size.width, using: &rng)
                let y = CGFloat.random(in: 0..<size.height, using: &rng)
                let s = CGFloat.random(in: 0.5...1.4, using: &rng)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                            with: .color(.white.opacity(opacity)))
            }
        }
    }
}

// MARK: Kinetic type

enum WordStyle: CaseIterable {
    case rise, slideLeft, slideRight, focusPull
}

/// One word entering with real motion-design variety — not every word doing the same
/// rise-and-fade. `style` picks the entrance shape; all styles share a blur-to-sharp
/// focus pull, since that's the single strongest "Apple" cue (their kinetic type is
/// almost always pulled into focus, not just moved into place).
struct Word: View {
    let text: String
    let t: Double // seconds since this word's own cue
    let size: CGFloat
    var gradient = false
    var weight: Font.Weight = .bold
    var style: WordStyle = .rise

    var body: some View {
        let inDur = 0.62
        let p = easeOutBack(t / inDur)
        let focus = ease(min(1, t / (inDur * 0.75)))
        let blur = (1 - focus) * size * 0.05
        let label = Text(text).font(.system(size: size, weight: weight, design: .default)).kerning(-size * 0.025)
        let breathe = 1 + 0.008 * sin(t * 1.4) // a very slight living drift once settled

        Group {
            if gradient { label.foregroundStyle(brand) } else { label.foregroundStyle(.white) }
        }
        .opacity(min(1, max(0, t / 0.22)))
        .blur(radius: max(0, blur))
        .scaleEffect((0.9 + 0.1 * p) * breathe)
        .offset(offset(p: p, settleScale: size))
    }

    private func offset(p: Double, settleScale: CGFloat) -> CGSize {
        let remaining = 1 - p
        switch style {
        case .rise: return CGSize(width: 0, height: remaining * settleScale * 0.4)
        case .slideLeft: return CGSize(width: -remaining * settleScale * 0.9, height: 0)
        case .slideRight: return CGSize(width: remaining * settleScale * 0.9, height: 0)
        case .focusPull: return CGSize(width: 0, height: remaining * settleScale * 0.12)
        }
    }
}

/// Fades and pulls focus out at the end of a card, mirroring the entrance language
/// instead of a bare opacity cut.
func outro(_ t: Double, _ duration: Double) -> Double {
    1 - easeInOut((t - (duration - 0.4)) / 0.4)
}
func outroBlur(_ t: Double, _ duration: Double, _ size: CGFloat) -> CGFloat {
    CGFloat(easeInOut((t - (duration - 0.4)) / 0.4)) * size * 0.04
}

struct Card: View {
    let lines: [[(String, Bool)]]
    let t: Double
    let duration: Double
    var size: CGFloat = 132
    var stagger = 0.12
    var lineGap = 0.45
    var seed: Double = 0
    var bias: Int = 0

    var body: some View {
        // Alternate word styles across the whole card (not per line) so the eye reads
        // real variety rather than a repeating per-line pattern.
        var flatIndex = 0
        let styleFor: () -> WordStyle = {
            let s: [WordStyle] = [.rise, .focusPull, .slideLeft, .focusPull, .slideRight, .rise]
            defer { flatIndex += 1 }
            return s[flatIndex % s.count]
        }
        ZStack {
            AnimatedBackground(t: t, seed: seed, bias: bias)
            VStack(spacing: size * 0.05) {
                ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, words in
                    HStack(spacing: size * 0.24) {
                        ForEach(Array(words.enumerated()), id: \.offset) { wordIndex, word in
                            Word(text: word.0, t: t - Double(lineIndex) * lineGap - Double(wordIndex) * stagger,
                                 size: size, gradient: word.1, style: styleFor())
                        }
                    }
                }
            }
            .opacity(outro(t, duration))
            .blur(radius: outroBlur(t, duration, size))
        }
        .frame(width: size_w, height: size_h)
    }
    var size_w: CGFloat { 1920 }
    var size_h: CGFloat { 1080 }
}

/// Feature names flashing one after another, Apple-montage style — each pulled into
/// focus and pushed back out, alternating slide direction so it reads as a sequence
/// of quick camera moves rather than a repeating flashcard flip.
struct Montage: View {
    let words: [String]
    let t: Double
    let duration: Double

    var body: some View {
        let each = (duration - 0.2) / Double(words.count)
        let index = min(words.count - 1, Int(t / each))
        let local = t - Double(index) * each
        let inDur = 0.3
        let p = ease(min(1, local / inDur))
        let dir: CGFloat = index % 2 == 0 ? 1 : -1
        ZStack {
            AnimatedBackground(t: t, seed: 4.2, bias: 1, intensity: 1.15)
            Text(words[index])
                .font(.system(size: 170, weight: .bold))
                .kerning(-4)
                .foregroundStyle(index % 2 == 0 ? AnyShapeStyle(Color.white) : AnyShapeStyle(brand))
                .blur(radius: (1 - p) * 10)
                .scaleEffect(1.12 - 0.12 * p)
                .offset(x: (1 - p) * dir * 60)
                .opacity(min(1, local / 0.1) * (index == words.count - 1 ? outro(t, duration) : 1))
        }
        .frame(width: 1920, height: 1080)
    }
}

struct EndCard: View {
    let t: Double
    let duration: Double

    var body: some View {
        ZStack {
            AnimatedBackground(t: t, seed: 8.1, bias: 2, intensity: 1.2)
            // The notch, with the halo glowing out of it.
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 360 * ease(t / 0.8), height: 64)
                    .overlay(Capsule().stroke(brand, lineWidth: 3).opacity(ease(t / 0.8)))
                    .shadow(color: Color(red: 0.8, green: 0.4, blue: 1).opacity(0.7 * ease((t - 0.3) / 1)), radius: 40)
                    .padding(.bottom, 70)
                Word(text: "Halo", t: t - 0.35, size: 190, gradient: true, style: .focusPull)
                Word(text: "A Dynamic Island for your Mac.", t: t - 0.85, size: 54, weight: .semibold, style: .rise)
                    .padding(.top, 10)
                Word(text: "Free & open source  ·  macOS", t: t - 1.3, size: 30, weight: .medium, style: .rise)
                    .opacity(0.6)
                    .padding(.top, 30)
            }
        }
        .frame(width: 1920, height: 1080)
    }
}

struct Scene {
    let name: String
    let duration: Double
    let view: (Double) -> AnyView
}

let scenes: [Scene] = [
    Scene(name: "t01-meet", duration: 2.6) { t in AnyView(Card(lines: [[("Meet", false), ("Halo.", true)]], t: t, duration: 2.6, size: 170, seed: 0, bias: 0)) },
    Scene(name: "t02-notch", duration: 2.6) { t in AnyView(Card(lines: [[("Your", false), ("notch.", false)], [("Now", false), ("alive.", true)]], t: t, duration: 2.6, seed: 1.1, bias: 1)) },
    Scene(name: "t03-music", duration: 2.2) { t in AnyView(Card(lines: [[("Music,", false), ("right", false), ("where", false), ("you", false), ("look.", true)]], t: t, duration: 2.2, size: 110, stagger: 0.09, seed: 2.3, bias: 2)) },
    Scene(name: "t04-alerts", duration: 2.2) { t in AnyView(Card(lines: [[("Every", false), ("alert.", false)], [("Small.", false), ("Beautiful.", true)]], t: t, duration: 2.2, size: 120, seed: 3.4, bias: 0)) },
    Scene(name: "t05-controls", duration: 2.2) { t in AnyView(Card(lines: [[("Control", false), ("Center.", false)], [("In", false), ("the", false), ("notch.", true)]], t: t, duration: 2.2, size: 120, seed: 4.5, bias: 1)) },
    Scene(name: "t06-drop", duration: 2.4) { t in AnyView(Card(lines: [[("Drop", false), ("an", false), ("image.", false)], [("Lift", false), ("the", false), ("subject.", true)]], t: t, duration: 2.4, size: 120, seed: 5.6, bias: 3)) },
    Scene(name: "t07-focus", duration: 2.0) { t in AnyView(Card(lines: [[("Stay", false), ("in", false), ("the", false), ("zone.", true)]], t: t, duration: 2.0, size: 130, seed: 6.7, bias: 2)) },
    Scene(name: "t08-mac", duration: 2.0) { t in AnyView(Card(lines: [[("Know", false), ("your", false), ("Mac.", true)]], t: t, duration: 2.0, size: 140, seed: 7.8, bias: 0)) },
    Scene(name: "t09-clipboard", duration: 2.4) { t in AnyView(Card(lines: [[("Everything", false), ("you", false), ("copy.", false)], [("One", false), ("shortcut", false), ("away.", true)]], t: t, duration: 2.4, size: 110, seed: 8.9, bias: 1)) },
    Scene(name: "t14-smart-clip", duration: 2.2) { t in AnyView(Card(lines: [[("A", false), ("number,", false), ("an", false), ("address.", false)], [("It", false), ("just", false), ("knows.", true)]], t: t, duration: 2.2, size: 100, stagger: 0.08, seed: 10.1, bias: 3)) },
    Scene(name: "t15-qr", duration: 1.8) { t in AnyView(Card(lines: [[("Scan.", false), ("Copy.", false), ("Done.", true)]], t: t, duration: 1.8, size: 130, seed: 11.2, bias: 2)) },
    Scene(name: "t10-montage", duration: 3.6) { t in AnyView(Montage(words: ["Lyrics.", "Weather.", "Timer.", "Reminders.", "Shortcuts.", "Mirror.", "Focus.", "Wi‑Fi.", "Speed test.", "And more."], t: t, duration: 3.6)) },
    Scene(name: "t12-siri", duration: 2.4) { t in AnyView(Card(lines: [[("Siri.", true)], [("Right", false), ("in", false), ("the", false), ("notch.", false)]], t: t, duration: 2.4, size: 130, seed: 12.3, bias: 1)) },
    Scene(name: "t13-live", duration: 2.2) { t in AnyView(Card(lines: [[("Downloads.", false), ("Live.", true)], [("Rain?", false), ("You'll", false), ("know.", true)]], t: t, duration: 2.2, size: 116, seed: 13.4, bias: 2)) },
    Scene(name: "t16-siri-wave", duration: 2.2) { t in AnyView(Card(lines: [[("Ask.", false), ("It", false), ("listens.", true)]], t: t, duration: 2.2, size: 130, seed: 14.2, bias: 1)) },
    Scene(name: "t17-calendar", duration: 2.2) { t in AnyView(Card(lines: [[("Mark", false), ("it.", false)], [("Halo", false), ("reminds", false), ("you.", true)]], t: t, duration: 2.2, size: 116, seed: 15.6, bias: 0)) },
    Scene(name: "t11-end", duration: 4.5) { t in AnyView(EndCard(t: t, duration: 4.5)) },
]

@MainActor
func render(_ scene: Scene, to directory: URL) throws {
    let url = directory.appendingPathComponent("\(scene.name).mp4")
    let ffmpeg = Process()
    ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    // Rendered at 2x scale (3840x2160 pixels) while the SwiftUI layout below stays at
    // its original 1920x1080 logical points, so fonts/spacing are untouched — same
    // Retina-style trick as a @2x asset, just done by hand since this isn't a window.
    ffmpeg.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "3840x2160", "-r", "60",
                        "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p", url.path]
    let pipe = Pipe()
    ffmpeg.standardInput = pipe
    try ffmpeg.run()
    let frames = Int((scene.duration * fps).rounded())
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    for frame in 0..<frames {
        let t = Double(frame) / fps
        let renderer = ImageRenderer(content: scene.view(t).frame(width: 1920, height: 1080).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { continue }
        var data = Data(count: 3840 * 2160 * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 3840 * 4,
                                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        }
        pipe.fileHandleForWriting.write(data)
    }
    try pipe.fileHandleForWriting.close()
    ffmpeg.waitUntilExit()
    print("rendered \(scene.name) (\(frames) frames)")
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let only = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
MainActor.assumeIsolated {
    for scene in scenes where only == nil || scene.name == only {
        try! render(scene, to: out)
    }
}
