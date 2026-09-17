// Renders the promo's kinetic title cards to ProRes-quality H.264 clips, frame by frame.
// Usage: swift titles.swift <outDir>
import AppKit
import SwiftUI

let fps = 60.0
let size = CGSize(width: 1920, height: 1080)

func ease(_ x: Double) -> Double { // easeOutExpo-ish, Apple-like settle
    let c = min(1, max(0, x))
    return c == 1 ? 1 : 1 - pow(2, -10 * c)
}
func easeInOut(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
}

let brand = LinearGradient(colors: [Color(red: 0.49, green: 0.42, blue: 1.0), Color(red: 0.93, green: 0.36, blue: 0.75),
                                    Color(red: 1.0, green: 0.62, blue: 0.32)], startPoint: .leading, endPoint: .trailing)

/// One word rising into place.
struct Word: View {
    let text: String
    let t: Double       // seconds since this word's cue
    let size: CGFloat
    var gradient = false
    var weight: Font.Weight = .bold

    var body: some View {
        let p = ease(t / 0.9)
        let label = Text(text).font(.system(size: size, weight: weight, design: .default)).kerning(-size * 0.025)
        Group {
            if gradient { label.foregroundStyle(brand) } else { label.foregroundStyle(.white) }
        }
        .opacity(min(1, max(0, t / 0.35)))
        .offset(y: (1 - p) * size * 0.45)
        .scaleEffect(0.96 + 0.04 * p)
    }
}

/// Fades everything out at the end of a card.
func outro(_ t: Double, _ duration: Double) -> Double {
    1 - easeInOut((t - (duration - 0.35)) / 0.35)
}

struct Card: View {
    let lines: [[(String, Bool)]]
    let t: Double
    let duration: Double
    var size: CGFloat = 132
    var stagger = 0.12
    var lineGap = 0.45

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: size * 0.05) {
                ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, words in
                    HStack(spacing: size * 0.24) {
                        ForEach(Array(words.enumerated()), id: \.offset) { wordIndex, word in
                            Word(text: word.0, t: t - Double(lineIndex) * lineGap - Double(wordIndex) * stagger,
                                 size: size, gradient: word.1)
                        }
                    }
                }
            }
            .opacity(outro(t, duration))
        }
        .frame(width: size_w, height: size_h)
    }
    var size_w: CGFloat { 1920 }
    var size_h: CGFloat { 1080 }
}

/// Feature names flashing one after another, Apple-montage style.
struct Montage: View {
    let words: [String]
    let t: Double
    let duration: Double

    var body: some View {
        let each = (duration - 0.2) / Double(words.count)
        let index = min(words.count - 1, Int(t / each))
        let local = t - Double(index) * each
        ZStack {
            Color.black
            Text(words[index])
                .font(.system(size: 170, weight: .bold))
                .kerning(-4)
                .foregroundStyle(index % 2 == 0 ? AnyShapeStyle(Color.white) : AnyShapeStyle(brand))
                .scaleEffect(1.12 - 0.12 * ease(local / 0.35))
                .opacity(min(1, local / 0.08) * (index == words.count - 1 ? outro(t, duration) : 1))
        }
        .frame(width: 1920, height: 1080)
    }
}

struct EndCard: View {
    let t: Double
    let duration: Double

    var body: some View {
        ZStack {
            Color.black
            // The notch, with the halo glowing out of it.
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 360 * ease(t / 0.8), height: 64)
                    .overlay(Capsule().stroke(brand, lineWidth: 3).opacity(ease(t / 0.8)))
                    .shadow(color: Color(red: 0.8, green: 0.4, blue: 1).opacity(0.7 * ease((t - 0.3) / 1)), radius: 40)
                    .padding(.bottom, 70)
                Word(text: "Halo", t: t - 0.35, size: 190, gradient: true)
                Word(text: "A Dynamic Island for your Mac.", t: t - 0.85, size: 54, weight: .semibold)
                    .padding(.top, 10)
                Word(text: "Free & open source  ·  macOS", t: t - 1.3, size: 30, weight: .medium)
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
    Scene(name: "t01-meet", duration: 2.6) { t in AnyView(Card(lines: [[("Meet", false), ("Halo.", true)]], t: t, duration: 2.6, size: 170)) },
    Scene(name: "t02-notch", duration: 2.6) { t in AnyView(Card(lines: [[("Your", false), ("notch.", false)], [("Now", false), ("alive.", true)]], t: t, duration: 2.6)) },
    Scene(name: "t03-music", duration: 2.2) { t in AnyView(Card(lines: [[("Music,", false), ("right", false), ("where", false), ("you", false), ("look.", true)]], t: t, duration: 2.2, size: 110, stagger: 0.09)) },
    Scene(name: "t04-alerts", duration: 2.2) { t in AnyView(Card(lines: [[("Every", false), ("alert.", false)], [("Small.", false), ("Beautiful.", true)]], t: t, duration: 2.2, size: 120)) },
    Scene(name: "t05-controls", duration: 2.2) { t in AnyView(Card(lines: [[("Control", false), ("Center.", false)], [("In", false), ("the", false), ("notch.", true)]], t: t, duration: 2.2, size: 120)) },
    Scene(name: "t06-drop", duration: 2.4) { t in AnyView(Card(lines: [[("Drop", false), ("an", false), ("image.", false)], [("Lift", false), ("the", false), ("subject.", true)]], t: t, duration: 2.4, size: 120)) },
    Scene(name: "t07-focus", duration: 2.0) { t in AnyView(Card(lines: [[("Stay", false), ("in", false), ("the", false), ("zone.", true)]], t: t, duration: 2.0, size: 130)) },
    Scene(name: "t08-mac", duration: 2.0) { t in AnyView(Card(lines: [[("Know", false), ("your", false), ("Mac.", true)]], t: t, duration: 2.0, size: 140)) },
    Scene(name: "t09-clipboard", duration: 2.4) { t in AnyView(Card(lines: [[("Everything", false), ("you", false), ("copy.", false)], [("One", false), ("shortcut", false), ("away.", true)]], t: t, duration: 2.4, size: 110)) },
    Scene(name: "t14-smart-clip", duration: 2.2) { t in AnyView(Card(lines: [[("A", false), ("number,", false), ("an", false), ("address.", false)], [("It", false), ("just", false), ("knows.", true)]], t: t, duration: 2.2, size: 100, stagger: 0.08)) },
    Scene(name: "t15-qr", duration: 1.8) { t in AnyView(Card(lines: [[("Scan.", false), ("Copy.", false), ("Done.", true)]], t: t, duration: 1.8, size: 130)) },
    Scene(name: "t10-montage", duration: 3.6) { t in AnyView(Montage(words: ["Lyrics.", "Weather.", "Timer.", "Reminders.", "Shortcuts.", "Mirror.", "Focus.", "Wi‑Fi.", "Speed test.", "And more."], t: t, duration: 3.6)) },
    Scene(name: "t12-siri", duration: 2.4) { t in AnyView(Card(lines: [[("Siri.", true)], [("Right", false), ("in", false), ("the", false), ("notch.", false)]], t: t, duration: 2.4, size: 130)) },
    Scene(name: "t13-live", duration: 2.2) { t in AnyView(Card(lines: [[("Downloads.", false), ("Live.", true)], [("Rain?", false), ("You'll", false), ("know.", true)]], t: t, duration: 2.2, size: 116)) },
    Scene(name: "t11-end", duration: 4.5) { t in AnyView(EndCard(t: t, duration: 4.5)) },
]

@MainActor
func render(_ scene: Scene, to directory: URL) throws {
    let url = directory.appendingPathComponent("\(scene.name).mp4")
    let ffmpeg = Process()
    ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ffmpeg.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "1920x1080", "-r", "60",
                        "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p", url.path]
    let pipe = Pipe()
    ffmpeg.standardInput = pipe
    try ffmpeg.run()
    let frames = Int((scene.duration * fps).rounded())
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    for frame in 0..<frames {
        let t = Double(frame) / fps
        let renderer = ImageRenderer(content: scene.view(t).frame(width: 1920, height: 1080).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.cgImage else { continue }
        var data = Data(count: 1920 * 1080 * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: 1920 * 4,
                                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
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
