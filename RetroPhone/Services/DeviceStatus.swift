import UIKit
import Network
import Observation

/// Real device battery state (UIDevice). Values come straight from iOS; nothing is faked.
@Observable
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    enum State: Equatable { case unknown, unplugged, charging, full }

    /// 0...1, or nil when iOS reports an unknown level (e.g. Simulator).
    private(set) var level: Double?
    private(set) var state: State = .unknown

    var isCharging: Bool { state == .charging || state == .full }
    var percent: Int? { level.map { Int(($0 * 100).rounded()) } }

    private var observers: [NSObjectProtocol] = []

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        let nc = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                     UIApplication.didBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        let device = UIDevice.current
        level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        switch device.batteryState {
        case .unplugged: state = .unplugged
        case .charging: state = .charging
        case .full: state = .full
        default: state = .unknown
        }
    }
}

/// Network reachability via NWPathMonitor. We can only know the interface type
/// (Wi-Fi / cellular / wired) — carrier name and signal strength are not available
/// through public API, so they are never shown.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    enum Kind: Equatable { case none, wifi, cellular, wired, other }
    private(set) var kind: Kind = .other
    private(set) var isConstrained = false
    var isOnline: Bool { kind != .none }

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let kind: Kind
            if path.status != .satisfied { kind = .none }
            else if path.usesInterfaceType(.wifi) { kind = .wifi }
            else if path.usesInterfaceType(.cellular) { kind = .cellular }
            else if path.usesInterfaceType(.wiredEthernet) { kind = .wired }
            else { kind = .other }
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.kind = kind
                self?.isConstrained = constrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "RetroPhone.network"))
    }
}

/// Minute-aligned clock so views that show the time don't re-render every frame.
@Observable
final class ClockTicker {
    static let shared = ClockTicker()
    private(set) var now = Date()
    private var timer: Timer?

    private init() {
        schedule()
        NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date(); self?.schedule() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date(); self?.schedule() }
        }
    }

    private func schedule() {
        timer?.invalidate()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0),
                                             matchingPolicy: .nextTime) ?? Date().addingTimeInterval(60)
        let t = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

enum RetroFormat {
    static func time(_ date: Date, seconds: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Localizer.shared.language.locale
        let h24 = SettingsStore.shared.value.use24HourClock
        if Localizer.shared.language == .ko && !h24 {
            f.dateFormat = seconds ? "a h:mm:ss" : "a h:mm"
        } else {
            f.dateFormat = h24 ? (seconds ? "HH:mm:ss" : "H:mm") : (seconds ? "h:mm:ss" : "h:mm")
        }
        return f.string(from: date)
    }

    /// Big lock-screen time: no AM/PM marker (iOS 4 style).
    static func lockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = SettingsStore.shared.value.use24HourClock ? "H:mm" : "h:mm"
        return f.string(from: date)
    }

    static func lockDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Localizer.shared.language.locale
        f.setLocalizedDateFormatFromTemplate(Localizer.shared.language == .ko ? "MMMMdEEEE" : "EEEEMMMMd")
        return f.string(from: date)
    }

    static func date(_ date: Date, template: String) -> String {
        let f = DateFormatter()
        f.locale = Localizer.shared.language.locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }
}
