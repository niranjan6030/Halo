import Foundation
import IOKit.ps

/// Reports plugging in or unplugging the charger, and low battery as it drops
/// past 20% and 10%.
@MainActor
final class BatteryMonitor {
    enum Event {
        case charging(percent: Int)
        case unplugged(percent: Int)
        case low(percent: Int)
        case lowPowerMode(on: Bool)
    }

    var onEvent: ((Event) -> Void)?

    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?
    private var lastPercent: Int?
    private var powerStateObserver: NSObjectProtocol?
    private var lastLowPowerMode = false

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update() }
        }, context)?.takeRetainedValue() else { return }

        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        let state = read()
        lastOnAC = state?.onAC
        lastPercent = state?.percent

        lastLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            MainActor.assumeIsolated {
                // The notification can repeat without the mode actually changing.
                guard let self else { return }
                // Plugging in often flips Low Power Mode first; catch the power change
                // here too, in case its own notification is late.
                self.update()
                guard self.lastLowPowerMode != enabled else { return }
                self.lastLowPowerMode = enabled
                self.onEvent?(.lowPowerMode(on: enabled))
            }
        }
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        source = nil
        if let powerStateObserver { NotificationCenter.default.removeObserver(powerStateObserver) }
        powerStateObserver = nil
    }

    struct Snapshot: Equatable {
        var percent: Int
        var onAC: Bool
        var isCharging: Bool
        /// Minutes until empty (or until full while charging), when macOS knows.
        var minutesRemaining: Int?
    }

    /// The full picture, for the island's battery card.
    func snapshot() -> Snapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = (isCharging ? description[kIOPSTimeToFullChargeKey] : description[kIOPSTimeToEmptyKey]) as? Int
            return Snapshot(percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                            onAC: onAC, isCharging: isCharging,
                            minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil)
        }
        return nil
    }

    private func read() -> (onAC: Bool, percent: Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (onAC, Int((Double(current) / Double(maximum) * 100).rounded()))
        }
        return nil
    }

    private func update() {
        guard let state = read() else { return }
        defer {
            lastOnAC = state.onAC
            lastPercent = state.percent
        }
        if let lastOnAC, lastOnAC != state.onAC {
            onEvent?(state.onAC ? .charging(percent: state.percent) : .unplugged(percent: state.percent))
            return
        }
        if !state.onAC, let lastPercent {
            for threshold in [20, 10] where lastPercent > threshold && state.percent <= threshold {
                onEvent?(.low(percent: state.percent))
                return
            }
        }
    }
}
