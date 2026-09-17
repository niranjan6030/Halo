import Foundation
import IOBluetooth

struct BluetoothDeviceInfo: Equatable {
    var name: String
    var symbol: String
    /// Battery percentages when the device reports them (AirPods and Beats do).
    var batteryLeft: Int?
    var batteryRight: Int?
    var batterySingle: Int?

    var batterySummary: Int? {
        if let batterySingle { return batterySingle }
        switch (batteryLeft, batteryRight) {
        case let (left?, right?): return min(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        default: return nil
        }
    }
}

/// Reports Bluetooth devices connecting and disconnecting.
@MainActor
final class BluetoothMonitor: NSObject {
    var onConnect: ((BluetoothDeviceInfo) -> Void)?
    var onDisconnect: ((BluetoothDeviceInfo) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Registering reports every already-connected device; those are not news.
    private var quietUntil = Date.distantPast

    func start() {
        guard connectNotification == nil else { return }
        quietUntil = Date().addingTimeInterval(2)
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                           selector: #selector(deviceDisconnected(_:device:)))
        guard Date() > quietUntil else { return }

        // AirPods report battery a moment after the link comes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.connectNotification != nil, device.isConnected() else { return }
            self.onConnect?(Self.info(for: device))
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let address = device.addressString {
            disconnectNotifications.removeValue(forKey: address)?.unregister()
        }
        onDisconnect?(Self.info(for: device))
    }

    private static func info(for device: IOBluetoothDevice) -> BluetoothDeviceInfo {
        let name = device.name ?? "Bluetooth Device"
        return BluetoothDeviceInfo(
            name: name,
            symbol: symbol(for: device, name: name),
            batteryLeft: battery(device, "batteryPercentLeft"),
            batteryRight: battery(device, "batteryPercentRight"),
            batterySingle: battery(device, "batteryPercentSingle")
        )
    }

    /// IOBluetooth exposes these privately; check before asking so a future macOS
    /// without them just shows no battery instead of throwing.
    private static func battery(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let value = device.value(forKey: key) as? NSNumber, value.intValue > 0, value.intValue <= 100 else {
            return nil
        }
        return value.intValue
    }

    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }
        if lowered.contains("keyboard") { return "keyboard" }
        if lowered.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if lowered.contains("mouse") { return "magicmouse" }
        if lowered.contains("controller") || lowered.contains("dualsense") || lowered.contains("xbox") {
            return "gamecontroller"
        }
        switch device.deviceClassMajor {
        case 0x04: return "headphones"          // Audio/Video
        case 0x05: return "keyboard"            // Peripheral
        case 0x02: return "iphone"              // Phone
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
