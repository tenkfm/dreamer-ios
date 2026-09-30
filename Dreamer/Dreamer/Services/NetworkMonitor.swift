import Foundation
import Network
import Observation

/// Whether the device has a usable network path. Drives the offline banner and lets the draft
/// queue send as soon as the connection is back.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.braincode.dreamer.io.network-monitor", qos: .utility))
    }

    /// Fixed state for previews and tests.
    init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    deinit {
        monitor.cancel()
    }
}
