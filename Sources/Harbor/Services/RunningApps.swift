import AppKit
import Observation

struct RunningApp: Identifiable, Equatable {
    let pid: pid_t
    let bundleURL: URL?
    let bundleID: String?
    let name: String
    var isActive: Bool
    var isHidden: Bool
    /// Standardized once when the list is read: standardizing touches the disk, and docks look apps
    /// up by path for every icon they draw.
    let path: String?
    var id: pid_t { pid }

    init(pid: pid_t, bundleURL: URL?, bundleID: String?, name: String, isActive: Bool, isHidden: Bool) {
        self.pid = pid
        self.bundleURL = bundleURL
        self.bundleID = bundleID
        self.name = name
        self.isActive = isActive
        self.isHidden = isHidden
        path = bundleURL?.standardizedFileURL.path
    }
}

/// Tracks regular (Dock-visible) running applications.
@MainActor
@Observable
final class RunningApps {
    private(set) var apps: [RunningApp] = []
    /// Apps launched from a dock that have not finished launching; they bounce.
    private(set) var launchingPaths: Set<String> = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Whether each process is Dock-visible. Right after an app switch every `NSRunningApplication`
    /// property read is a synchronous call to LaunchServices, so the list is read off the main thread
    /// and `activationPolicy` is only asked again for an app that launches or comes forward.
    @ObservationIgnored private var regular: [pid_t: Bool] = [:]
    /// Drops a read that a newer one has overtaken.
    @ObservationIgnored private var generation = 0

    init() {
        apply(Self.read(cached: [:], recheck: nil))
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let changed = name == NSWorkspace.didLaunchApplicationNotification
                    || name == NSWorkspace.didActivateApplicationNotification
                let app = changed ? note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication : nil
                MainActor.assumeIsolated { self?.refresh(recheck: app) }
            })
        }
    }

    func refresh(recheck: NSRunningApplication? = nil) {
        generation += 1
        let current = generation
        let cached = regular
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.read(cached: cached, recheck: recheck)
            }.value
            guard let self, current == self.generation else { return }
            self.apply(result)
        }
    }

    private func apply(_ result: (regular: [pid_t: Bool], apps: [RunningApp])) {
        regular = result.regular
        // Every dock rebuilds when this changes, so an identical list is not written back.
        if result.apps != apps { apps = result.apps }
        let launching = launchingPaths.filter { app(atPath: $0) == nil }
        if launching != launchingPaths { launchingPaths = launching }
    }

    /// `isTerminated` is skipped: it is another LaunchServices round trip per app, the list already
    /// drops apps that quit, and their terminate notification reads it again.
    private nonisolated static func read(cached: [pid_t: Bool], recheck: NSRunningApplication?)
        -> (regular: [pid_t: Bool], apps: [RunningApp]) {
        let skip = recheck?.processIdentifier
        var known: [pid_t: Bool] = [:]
        var apps: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            let isRegular = (pid == skip ? nil : cached[pid]) ?? (app.activationPolicy == .regular)
            known[pid] = isRegular
            guard isRegular else { continue }
            apps.append(RunningApp(pid: pid, bundleURL: app.bundleURL, bundleID: app.bundleIdentifier,
                                   name: app.localizedName ?? "App", isActive: app.isActive, isHidden: app.isHidden))
        }
        return (known, apps)
    }

    func app(atPath path: String) -> RunningApp? {
        let target = Self.normalize(path)
        return apps.first { $0.path == target }
    }

    func isRunning(path: String) -> Bool { app(atPath: path) != nil }

    func markLaunching(_ path: String) {
        let p = Self.normalize(path)
        launchingPaths.insert(p)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            self.launchingPaths.remove(p)
        }
    }

    func isLaunching(path: String) -> Bool { launchingPaths.contains(Self.normalize(path)) }

    static func normalize(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
}
