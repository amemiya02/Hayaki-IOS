import Foundation

enum TemplateFullscreen: Hashable {
    case standard
    case buttonsAndMenu
    case buttonsOnly
    case hidden

    var showsTopBar: Bool { self == .standard }
    var showsActions: Bool { self == .standard || self == .buttonsAndMenu }
    var showsAnswer: Bool { self != .hidden }
}

struct TemplateToast: Decodable {
    let text: String
    let shortLength: Bool

    var decodedText: String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }
}

#if os(iOS)
import Network

@MainActor
final class TemplateNetworkStatus {
    private var monitor: NWPathMonitor?
    private var current: Bool?
    private var waiting: [CheckedContinuation<Bool, Never>] = []

    func isMetered() async -> Bool {
        if let current { return current }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if monitor == nil {
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { [weak self] path in
                    let metered = path.isExpensive
                    Task { @MainActor in
                        self?.current = metered
                        self?.waiting.forEach { $0.resume(returning: metered) }
                        self?.waiting.removeAll()
                    }
                }
                self.monitor = monitor
                monitor.start(queue: DispatchQueue(label: "Hayaki template network status", qos: .utility))
            }
        }
    }

    deinit { monitor?.cancel() }
}
#endif
