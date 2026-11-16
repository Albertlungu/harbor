import AppKit
import Observation

struct RunningApp: Identifiable, Equatable {
    let pid: pid_t
    let bundleURL: URL?
    let bundleID: String?
    let name: String
    var isActive: Bool
    var isHidden: Bool
    var id: pid_t { pid }

    var path: String? { bundleURL?.standardizedFileURL.path }
}

/// Tracks regular (Dock-visible) running applications.
@MainActor
@Observable
final class RunningApps {
    private(set) var apps: [RunningApp] = []
    /// Apps launched from a dock that have not finished launching; they bounce.
    private(set) var launchingPaths: Set<String> = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map {
                RunningApp(pid: $0.processIdentifier, bundleURL: $0.bundleURL, bundleID: $0.bundleIdentifier,
                           name: $0.localizedName ?? "App", isActive: $0.isActive, isHidden: $0.isHidden)
            }
        launchingPaths = launchingPaths.filter { app(atPath: $0) == nil }
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
