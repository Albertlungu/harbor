import Foundation

// MARK: CPU

/// Cumulative CPU tick counters as reported by host_statistics.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }
}

public enum SystemLogic {
    /// Busy share (0...100) between two readings. Counters are cumulative, so a
    /// reading that went backwards (wrap or reset) yields 0 rather than garbage.
    public static func cpuPercent(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.total > previous.total, current.busy >= previous.busy else { return 0 }
        let busy = Double(current.busy - previous.busy)
        let total = Double(current.total - previous.total)
        return min(100, max(0, busy / total * 100))
    }

    /// Used memory share (0...100); compressed pages count as used.
    public static func memoryPercent(active: UInt64, wired: UInt64, compressed: UInt64, physical: UInt64) -> Double {
        guard physical > 0 else { return 0 }
        return min(100, Double(active &+ wired &+ compressed) / Double(physical) * 100)
    }

    // MARK: Thresholds

    public enum Level: Equatable, Sendable { case good, warn, critical }

    /// Usage gauges turn amber at 60 and red at 85; battery is reversed
    /// (red below 20, amber below 40).
    public static func level(for percent: Double, reversed: Bool) -> Level {
        if reversed {
            if percent < 20 { return .critical }
            if percent < 40 { return .warn }
            return .good
        }
        if percent >= 85 { return .critical }
        if percent >= 60 { return .warn }
        return .good
    }

    // MARK: Refresh

    /// Seconds between samples for a refresh preset.
    public static func interval(forRate rate: String) -> TimeInterval {
        switch rate {
        case "fast": 1
        case "relaxed": 5
        case "powerSaver": 10
        default: 2
        }
    }

    // MARK: IPv4

    public struct InterfaceAddress: Equatable, Sendable {
        public var name: String
        public var address: String
        public var isUp: Bool

        public init(name: String, address: String, isUp: Bool = true) {
            self.name = name
            self.address = address
            self.isUp = isUp
        }
    }

    /// Lower ranks are preferred. Wi-Fi/Ethernet (en0 first) beat bridges, which
    /// beat tunnels and other virtual interfaces.
    static func rank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("bridge") { return 2 }
        return 3
    }

    /// Usable IPv4 addresses, primary interface first. Loopback, link-local
    /// and down interfaces are dropped.
    public static func rankIPv4(_ interfaces: [InterfaceAddress]) -> [InterfaceAddress] {
        let usable = interfaces.filter {
            $0.isUp && !$0.name.hasPrefix("lo") && !$0.address.hasPrefix("127.") && !$0.address.hasPrefix("169.254.")
        }
        return usable.enumerated()
            .sorted { (rank($0.element.name), $0.offset) < (rank($1.element.name), $1.offset) }
            .map(\.element)
    }

    // MARK: Battery

    /// "1h 05m" style remaining-time text; nil when the system has no estimate.
    public static func durationText(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
}

// MARK: Bluetooth

public enum BluetoothKind: String, Equatable, Sendable {
    case headphones, keyboard, mouse, trackpad, speaker, gamepad, other
}

public struct BluetoothDevice: Equatable, Identifiable, Sendable {
    public var name: String
    public var address: String
    public var connected: Bool
    public var kind: BluetoothKind
    public var main: Int?
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?

    public var id: String { address.isEmpty ? name : address }

    public init(name: String, address: String, connected: Bool, kind: BluetoothKind,
                main: Int? = nil, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil) {
        self.name = name
        self.address = address
        self.connected = connected
        self.kind = kind
        self.main = main
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
    }

    public var hasBattery: Bool { [main, left, right, caseLevel].contains { $0 != nil } }

    public var isAirPods: Bool { name.localizedCaseInsensitiveContains("airpods") || (left != nil && right != nil) }
}

public struct BluetoothReading: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: BluetoothKind
    public var label: String?
    public var percent: Int?
    public var connected: Bool
}

public enum BluetoothParser {
    /// Parses `system_profiler SPBluetoothDataType -json`. Unknown shapes yield an empty list.
    public static func parse(_ data: Data) -> [BluetoothDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BluetoothDevice] = []
        for section in sections {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                guard let entries = section[key] as? [[String: Any]] else { continue }
                for entry in entries {
                    for (name, value) in entry.sorted(by: { $0.key < $1.key }) {
                        guard let fields = value as? [String: Any] else { continue }
                        devices.append(device(named: name, fields: fields, connected: connected))
                    }
                }
            }
        }
        return devices
    }

    static func device(named name: String, fields: [String: Any], connected: Bool) -> BluetoothDevice {
        BluetoothDevice(
            name: name,
            address: fields["device_address"] as? String ?? "",
            connected: connected,
            kind: kind(minorType: fields["device_minorType"] as? String ?? "", name: name),
            main: percent(fields["device_batteryLevelMain"]),
            left: percent(fields["device_batteryLevelLeft"]),
            right: percent(fields["device_batteryLevelRight"]),
            caseLevel: percent(fields["device_batteryLevelCase"]))
    }

    /// Accepts "85%", "85" or a number.
    static func percent(_ raw: Any?) -> Int? {
        if let n = raw as? Int { return n }
        guard let s = raw as? String else { return nil }
        return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    static func kind(minorType: String, name: String) -> BluetoothKind {
        let hint = (minorType + " " + name).lowercased()
        if hint.contains("keyboard") { return .keyboard }
        if hint.contains("trackpad") { return .trackpad }
        if hint.contains("mouse") { return .mouse }
        if hint.contains("headphone") || hint.contains("headset") || hint.contains("airpods") || hint.contains("buds") { return .headphones }
        if hint.contains("speaker") { return .speaker }
        if hint.contains("gamepad") || hint.contains("controller") || hint.contains("joystick") { return .gamepad }
        return .other
    }

    /// Turns devices into display readings, honouring the widget's settings.
    public static func readings(from devices: [BluetoothDevice], includeOffline: Bool, includeNoBattery: Bool,
                                splitAirPods: Bool, limit: Int) -> [BluetoothReading] {
        var out: [BluetoothReading] = []
        for d in devices where d.connected || includeOffline {
            if !d.hasBattery && !includeNoBattery { continue }
            if splitAirPods && d.isAirPods && (d.left != nil || d.right != nil || d.caseLevel != nil) {
                for (label, value) in [("L", d.left), ("R", d.right), ("Case", d.caseLevel)] {
                    if let value {
                        out.append(BluetoothReading(id: d.id + label, name: d.name, kind: d.kind, label: label, percent: value, connected: d.connected))
                    }
                }
            } else {
                let level = d.main ?? [d.left, d.right].compactMap { $0 }.min() ?? d.caseLevel
                out.append(BluetoothReading(id: d.id, name: d.name, kind: d.kind, label: nil, percent: level, connected: d.connected))
            }
        }
        return Array(out.prefix(max(1, limit)))
    }
}
