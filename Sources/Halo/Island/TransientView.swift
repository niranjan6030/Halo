import SwiftUI

struct TransientView: View {
    let event: TransientEvent
    @ObservedObject var model: IslandModel
    let layout: IslandLayout

    var body: some View {
        let notch = model.notchSize
        let side = (layout.size.width - notch.width) / 2 - layout.topRadius
        switch event {
        case let .volume(level, muted):
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                Image(systemName: volumeSymbol(level: level, muted: muted))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            } trailing: {
                LevelBar(level: muted ? 0 : Double(level), color: muted ? .gray : .white)
                    .padding(.horizontal, 12)
            }

        case let .brightness(level):
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                Image(systemName: level < 0.35 ? "sun.min.fill" : "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            } trailing: {
                LevelBar(level: Double(level))
                    .padding(.horizontal, 12)
            }

        case let .capsLock(on):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: on ? "capslock.fill" : "capslock", tint: on ? .green : .white.opacity(0.7),
                       title: "Caps Lock") {
                AlertValue(text: on ? "On" : "Off", tint: on ? .green : .white, opacity: on ? 1 : 0.6)
            }

        case let .charging(percent):
            PowerStrip(percent: percent, charging: true, notch: notch, side: side, topRadius: layout.topRadius)

        case let .unplugged(percent):
            PowerStrip(percent: percent, charging: false, notch: notch, side: side, topRadius: layout.topRadius)

        case let .lowPowerMode(on):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: "leaf.fill", tint: on ? .yellow : .white.opacity(0.7),
                       level: model.batterySnapshot().map { Double($0.percent) / 100 },
                       title: "Low Power") {
                AlertValue(text: on ? "On" : "Off", tint: on ? .yellow : .white, opacity: on ? 1 : 0.6)
            }

        case let .bluetoothConnected(device):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: device.symbol,
                       tint: device.batterySummary.map { $0 <= 20 ? Color.red : Color.green } ?? .white,
                       level: device.batterySummary.map { Double($0) / 100 },
                       title: device.name) {
                if let battery = device.batterySummary {
                    AlertValue(text: "\(battery)%", tint: battery <= 20 ? .red : .green, opacity: 1)
                } else {
                    AlertValue(text: "Connected", opacity: 0.7)
                }
            }

        case let .bluetoothDisconnected(device):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: device.symbol, tint: .white.opacity(0.5),
                       title: device.name, titleOpacity: 0.6) {
                AlertValue(text: "Disconnected", opacity: 0.55)
            }

        case let .audioOutput(output):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: output.symbol, tint: output.symbol == "airplayaudio" ? .blue : .white,
                       title: "Playing on") {
                AlertValue(text: output.name, opacity: 0.85)
            }

        case let .network(state):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: networkSymbol(state),
                       tint: state == .offline ? .red : (state == .hotspot ? .green : .white),
                       title: networkTitle(state)) {
                AlertValue(text: networkText(state), tint: state == .offline ? .red : .white,
                           opacity: state == .offline ? 1 : 0.7)
            }

        case let .lowBattery(percent):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: "bolt.slash.fill", tint: .red, level: Double(percent) / 100,
                       title: "Low Battery") {
                AlertValue(text: "\(percent)%", tint: .red, opacity: 1)
            }

        case let .download(download):
            // Click to show the file in Finder.
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                HStack(spacing: 7) {
                    Image(nsImage: download.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .popIn(delay: 0.1)
                        .onDrag {
                            model.isDraggingOut = true
                            return NSItemProvider(contentsOf: download.url) ?? NSItemProvider()
                        }
                    Text(download.isAirDrop ? "AirDrop" : "Downloaded")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(download.isAirDrop ? Color.blue : Color.white.opacity(0.92))
                        .lineLimit(1)
                        .alertSettle(delay: 0.14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            } trailing: {
                AlertValue(text: download.name, opacity: 0.75)
                    .truncationMode(.middle)
                    .alertSettle(delay: 0.2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
            }

        case let .screenshot(item):
            // Drag the thumbnail into any app; click to open the clipboard.
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                HStack(spacing: 7) {
                    ClipboardThumbnail(item: item, size: 22)
                        .popIn(delay: 0.1)
                        .onDrag {
                            model.isDraggingOut = true
                            return ClipboardDrag.provider(for: item)
                        }
                        .help("Drag into any app")
                    Text("Screenshot")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                        .alertSettle(delay: 0.14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
            } trailing: {
                AlertValue(text: "Drag it anywhere", opacity: 0.6)
                    .alertSettle(delay: 0.2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
            }

        case .dropTarget:
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: "tray.and.arrow.down.fill", tint: .accentColor, title: "Drop to keep") {
                AlertValue(text: "Clipboard", opacity: 0.6)
            }

        case let .success(text):
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                SuccessGlyph(size: notch.height - 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
            } trailing: {
                Text(text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
            }

        case let .eventStarting(title, color):
            AlertStrip(notch: notch, side: side, topRadius: layout.topRadius,
                       symbol: "calendar", tint: color, title: title) {
                AlertValue(text: "Now", tint: color, opacity: 1)
            }

        case let .copied(item):
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                HStack(spacing: 7) {
                    ClipboardThumbnail(item: item, size: 18)
                        .popIn(delay: 0.1)
                    Text("Copied")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                        .alertSettle(delay: 0.14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            } trailing: {
                AlertBadge(symbol: "checkmark", tint: .green, level: nil)
                    .frame(width: 17, height: 17)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }

        case let .message(text, symbol):
            CompactStrip(notch: notch, side: side, topRadius: layout.topRadius) {
                AlertBadge(symbol: symbol, tint: symbol.hasPrefix("exclamationmark") ? .orange : .white, level: nil)
                    .frame(width: 17, height: 17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            } trailing: {
                Text(text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .alertSettle(delay: 0.16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
            }
        }
    }

    private func volumeSymbol(level: Float, muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func networkSymbol(_ state: NetworkMonitor.Event) -> String {
        switch state {
        case .wifi: return "wifi"
        case .hotspot: return "personalhotspot"
        case .ethernet: return "cable.connector.horizontal"
        case .offline: return "wifi.slash"
        }
    }

    private func networkTitle(_ state: NetworkMonitor.Event) -> String {
        switch state {
        case .wifi: return "Wi-Fi"
        case .hotspot: return "Hotspot"
        case .ethernet: return "Ethernet"
        case .offline: return "Offline"
        }
    }

    private func networkText(_ state: NetworkMonitor.Event) -> String {
        switch state {
        case .wifi: return "Connected"
        case .hotspot: return "Connected"
        case .ethernet: return "Connected"
        case .offline: return "No Internet"
        }
    }
}
