import Foundation
import Network

/// Reports connecting to and losing the network. macOS marks an iPhone's
/// Personal Hotspot as an expensive path, which is how it is told apart from Wi-Fi.
@MainActor
final class NetworkMonitor {
    enum Event: Equatable {
        case wifi
        case hotspot
        case ethernet
        case offline
    }

    var onEvent: ((Event) -> Void)?

    private var monitor: NWPathMonitor?
    private var last: Event?
    private var pending: DispatchWorkItem?
    /// The first path update after starting describes the current network — not news.
    private var hasBaseline = false

    func start() {
        guard monitor == nil else { return }
        hasBaseline = false
        last = nil
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let event = Self.event(for: path)
            DispatchQueue.main.async { self?.receive(event) }
        }
        monitor.start(queue: DispatchQueue(label: "island.network"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        pending?.cancel()
        pending = nil
    }

    private nonisolated static func event(for path: NWPath) -> Event {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.wifi) { return path.isExpensive ? .hotspot : .wifi }
        return path.isExpensive ? .hotspot : .wifi
    }

    private func receive(_ event: Event) {
        guard monitor != nil else { return }
        guard hasBaseline else {
            hasBaseline = true
            last = event
            return
        }
        guard event != last else { return }

        // Switching networks passes briefly through "offline"; wait for it to settle
        // so a hop from one Wi-Fi to another doesn't flash "No Connection".
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.last != event else { return }
            self.last = event
            self.onEvent?(event)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (event == .offline ? 2.5 : 0.8), execute: work)
    }
}
