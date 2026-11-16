import Foundation

public enum SnapshotReason: String, Codable, CaseIterable, Sendable {
    case daily, beforeImport, beforeUpgrade, replacedByRestore

    public var title: String {
        switch self {
        case .daily: "Daily backup"
        case .beforeImport: "Saved before an import"
        case .beforeUpgrade: "Saved before an upgrade"
        case .replacedByRestore: "Replaced by a restore"
        }
    }
}

public struct Snapshot: Hashable, Identifiable, Sendable {
    public var url: URL
    public var date: Date
    public var reason: SnapshotReason
    public var id: URL { url }
}

public enum ConfigError: Error, Equatable, LocalizedError {
    case newerVersion(Int)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .newerVersion(let v): "This backup was made by a newer version of Harbor (format \(v))."
        case .unreadable: "The file isn't a Harbor backup or is damaged."
        }
    }
}

/// Reads and writes the configuration and its snapshots in one directory.
public struct ConfigFile: Sendable {
    public let directory: URL
    public var maxDailySnapshots = 7

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor", isDirectory: true)
    }

    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    public var iconsDirectory: URL { directory.appendingPathComponent("Icons", isDirectory: true) }
    public var shelfDirectory: URL { directory.appendingPathComponent("Shelf", isDirectory: true) }

    public static func decode(_ data: Data) throws -> Config {
        guard var config = try? JSONDecoder.harbor.decode(Config.self, from: data) else {
            throw ConfigError.unreadable
        }
        if config.schemaVersion > Config.currentSchemaVersion {
            throw ConfigError.newerVersion(config.schemaVersion)
        }
        migrate(&config)
        return config
    }

    /// Brings configs written by older builds up to date.
    static func migrate(_ config: inout Config) {
        if config.schemaVersion < 2 {
            // Version 2 added scrolling through window previews. Older configs only ever stored
            // the previous default, so they move to the new one rather than keep a stale choice.
            config.settings.scrollGestures = true
            config.settings.scrollAction = .browsePreviews
        }
        config.schemaVersion = Config.currentSchemaVersion
    }

    public static func encode(_ config: Config) throws -> Data {
        try JSONEncoder.harbor.encode(config)
    }

    /// Loads the configuration. A missing file gives an empty config; a damaged one
    /// falls back to the newest snapshot that still decodes.
    public func load() -> (config: Config, recovered: Bool) {
        guard let data = try? Data(contentsOf: configURL) else { return (Config(), false) }
        if let config = try? Self.decode(data) { return (config, false) }
        for snapshot in snapshots() {
            if let data = try? Data(contentsOf: snapshot.url), let config = try? Self.decode(data) {
                return (config, true)
            }
        }
        return (Config(), true)
    }

    public func save(_ config: Config, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: configURL.path), !hasDailySnapshot(on: now) {
            try snapshotCurrent(reason: .daily, now: now)
        }
        try Self.encode(config).write(to: configURL, options: .atomic)
    }

    // MARK: Snapshots

    public func snapshots() -> [Snapshot] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap(Self.parseSnapshot).sorted { $0.date > $1.date }
    }

    /// Copies the current config into Backups with a reason tag.
    @discardableResult
    public func snapshotCurrent(reason: SnapshotReason, now: Date = Date()) throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        let url = backupsDirectory.appendingPathComponent("\(stamp)-\(reason.rawValue).json")
        try FileManager.default.copyItem(at: configURL, to: url)
        if reason == .daily { pruneDailies() }
        return Snapshot(url: url, date: now, reason: reason)
    }

    /// Replaces the live config with a snapshot, keeping the replaced state as its own snapshot.
    public func restore(_ snapshot: Snapshot, now: Date = Date()) throws -> Config {
        let config = try Self.decode(Data(contentsOf: snapshot.url))
        try snapshotCurrent(reason: .replacedByRestore, now: now)
        try Self.encode(config).write(to: configURL, options: .atomic)
        return config
    }

    func hasDailySnapshot(on date: Date) -> Bool {
        let cal = Calendar.current
        return snapshots().contains { $0.reason == .daily && cal.isDate($0.date, inSameDayAs: date) }
    }

    private func pruneDailies() {
        let dailies = snapshots().filter { $0.reason == .daily }
        for old in dailies.dropFirst(maxDailySnapshots) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    static func parseSnapshot(_ url: URL) -> Snapshot? {
        guard url.pathExtension == "json" else { return nil }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let ms = Double(parts[0]),
              let reason = SnapshotReason(rawValue: String(parts[1])) else { return nil }
        return Snapshot(url: url, date: Date(timeIntervalSince1970: ms / 1000), reason: reason)
    }
}

extension JSONEncoder {
    static var harbor: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var harbor: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
