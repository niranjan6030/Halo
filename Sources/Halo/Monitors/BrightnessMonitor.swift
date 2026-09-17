import CoreGraphics
import Foundation

/// Watches — and, for the media keys, sets — the built-in display's brightness.
///
/// macOS has no public brightness notification, so this samples DisplayServices
/// (the framework Control Center itself uses). Auto-brightness drifts slowly while
/// a key press jumps a whole step, so only a real jump is reported.
@MainActor
final class BrightnessMonitor {
    var onChange: ((_ brightness: Float) -> Void)?

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private let getBrightness: GetBrightness? = {
        guard let framework = BrightnessMonitor.framework,
              let symbol = dlsym(framework, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private let setBrightness: SetBrightness? = {
        guard let framework = BrightnessMonitor.framework,
              let symbol = dlsym(framework, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    private var timer: Timer?
    /// Recent samples, used to tell a key press from auto-brightness drift.
    private var samples: [(time: Date, value: Float)] = []
    private var lastReported: Float?
    /// When a jump was last reported. Changes shortly after one are part of the
    /// same key press (or a held key) and are followed without re-checking.
    private var lastJump = Date.distantPast
    private var display: CGDirectDisplayID?

    func start() {
        guard timer == nil, getBrightness != nil else { return }
        samples = []
        display = nil
        lastReported = read()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        samples = []
        lastJump = .distantPast
    }

    // MARK: Control (media keys)

    /// Steps brightness like the keyboard keys do; nil when there is no built-in display.
    func adjust(by step: Float) -> Float? {
        guard let setBrightness, let current = read(), let display else { return nil }
        let steps = (1 / abs(step)).rounded()
        let target = min(1, max(0, ((current * steps).rounded() + (step > 0 ? 1 : -1)) / steps))
        guard setBrightness(display, target) == 0 else { return nil }
        // Our own change is not a "jump" for the monitor to report again.
        lastReported = target
        samples = [(Date(), target)]
        return target
    }

    // MARK: Sampling

    private func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func read() -> Float? {
        guard let getBrightness else { return nil }
        if display == nil { display = builtInDisplay() }
        guard let display else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else {
            // The display went away (lid closed); look it up again next time.
            self.display = nil
            return nil
        }
        return value
    }

    private func sample() {
        guard let value = read() else { return }
        let now = Date()
        samples.append((now, value))
        samples.removeAll { now.timeIntervalSince($0.time) > 0.6 }

        guard let last = lastReported else {
            lastReported = value
            return
        }
        if abs(value - last) < 0.002 { return }

        // One brightness key step is 1/16 (0.0625) and lands within ~0.3 s.
        // Right after a jump, follow every change so a held key tracks smoothly.
        let oldest = samples.first?.value ?? value
        let isJump = abs(value - oldest) >= 0.03
        if isJump { lastJump = now }
        if isJump || now.timeIntervalSince(lastJump) < 1 {
            onChange?(value)
        }
        lastReported = value
    }
}
