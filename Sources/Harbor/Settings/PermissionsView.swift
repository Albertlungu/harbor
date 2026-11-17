import AppKit
import CoreBluetooth
import HarborCore
import SwiftUI

/// The macOS privacy permissions Harbor uses, with live status checks that never prompt.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility, screenRecording, automation, bluetooth
    var id: String { rawValue }

    enum Status { case allowed, denied, notAsked }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .automation: "Automation (Finder)"
        case .bluetooth: "Bluetooth"
        }
    }

    var use: String {
        switch self {
        case .accessibility: "Bringing back a specific window, minimizing, stepping through windows, and keeping windows off docks."
        case .screenRecording: "Window preview thumbnails."
        case .automation: "Emptying the Trash from the Trash widget."
        case .bluetooth: "Battery levels in the Bluetooth Battery widget."
        }
    }

    var missing: String {
        switch self {
        case .accessibility: "Clicking an app just switches to it."
        case .screenRecording: "Previews show a list of window titles instead."
        case .automation: "The Trash widget opens the Trash in Finder to empty it there."
        case .bluetooth: "The widget can't show accessory batteries."
        }
    }

    private var pane: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        case .bluetooth: "Privacy_Bluetooth"
        }
    }

    @MainActor var status: Status {
        switch self {
        case .accessibility:
            return WindowControl.isTrusted ? .allowed : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .allowed : .denied
        case .automation:
            return switch Self.finderAutomation(ask: false) {
            case noErr: .allowed
            case OSStatus(errAEEventNotPermitted): .denied
            default: .notAsked
            }
        case .bluetooth:
            return switch CBManager.authorization {
            case .allowedAlways: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        }
    }

    /// Shows the macOS prompt where one exists; macOS shows each prompt only once, so later
    /// requests fall through to the matching System Settings pane.
    @MainActor func request() {
        switch self {
        case .accessibility:
            WindowControl.requestTrust()
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings() }
        case .automation:
            // Blocks until the person answers, so it runs off the main thread.
            Task.detached { _ = Permission.finderAutomation(ask: true) }
        case .bluetooth:
            if CBManager.authorization == .notDetermined {
                BluetoothPrompt.shared.ask()
            } else {
                openSettings()
            }
        }
    }

    /// The privacy service name `tccutil` knows, for permissions a stale entry can block.
    var tccService: String? {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "ScreenCapture"
        case .automation, .bluetooth: nil
        }
    }

    /// An entry left by an earlier build with a different signature can show as on in System
    /// Settings while macOS still refuses this build. Removing Harbor's entry and asking again
    /// replaces it with one for this build.
    @MainActor func resetAndAsk() {
        guard let service = tccService, let bundleID = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", service, bundleID]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return }
        task.waitUntilExit()
        request()
    }

    @MainActor func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Bluetooth only matters once a Bluetooth widget is on a dock.
    @MainActor static func relevant(for model: AppModel) -> [Permission] {
        let bluetooth = model.store.docks.contains { $0.items.contains { $0.widget?.kind == .bluetoothBattery } }
        return allCases.filter { $0 != .bluetooth || bluetooth }
    }

    nonisolated private static func finderAutomation(ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bundleID = "com.apple.finder"
        let created = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }
}

/// Holds the Bluetooth manager whose creation makes macOS ask for Bluetooth access.
@MainActor
private final class BluetoothPrompt: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothPrompt()
    private var manager: CBCentralManager?

    func ask() { manager = CBCentralManager(delegate: self, queue: nil) }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}

/// Decides when the Permissions window opens by itself at launch.
@MainActor
enum PermissionsGate {
    private static let buildKey = "permissionsBuildSeen"
    private static let grantedKey = "permissionsGranted"

    /// Opens on the first launch of a new build, or when a permission that was allowed before has
    /// gone missing, which is what happens when macOS stops matching a grant to a rebuilt app.
    static func shouldShow(model: AppModel) -> Bool {
        // Unbundled development runs have no build number and share these defaults with the real app.
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, Bundle.main.bundleURL.pathExtension == "app"
        else { return false }
        let defaults = UserDefaults.standard
        let granted = Set(Permission.relevant(for: model).filter { $0.status == .allowed }.map(\.rawValue))
        let before = Set(defaults.stringArray(forKey: grantedKey) ?? [])
        let lost = !before.subtracting(granted).isEmpty
        let newBuild = defaults.string(forKey: buildKey) != build
        defaults.set(build, forKey: buildKey)
        defaults.set(Array(granted), forKey: grantedKey)
        return newBuild || lost
    }

    /// Remembers what is allowed now, so a later loss can be noticed.
    static func record(model: AppModel) {
        let granted = Permission.relevant(for: model).filter { $0.status == .allowed }.map(\.rawValue)
        UserDefaults.standard.set(granted, forKey: grantedKey)
    }
}

/// Every permission Harbor uses, with live status and a way to grant each one.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model
    var showsIntro = false

    var body: some View {
        // Status can change in System Settings at any moment, so it is re-read every second.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Form {
                if showsIntro {
                    Section {
                        Text("Harbor was installed or updated. macOS sometimes forgets permissions after an update, so here is where each one stands.")
                            .font(.callout)
                    }
                }
                Section {
                    ForEach(Permission.relevant(for: model)) { row($0) }
                }
                Section {
                    Text("Checks happen on this Mac and nothing is sent anywhere. If a permission shows Allowed in System Settings but Not allowed here, use Reset and Ask Again, or turn it off and on again there.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }
            .formStyle(.grouped)
        }
        .onDisappear { PermissionsGate.record(model: model) }
    }

    private func row(_ permission: Permission) -> some View {
        let status = permission.status
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack {
                Text(permission.title).font(.headline)
                Spacer()
                Label(statusText(status), systemImage: status == .allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(status == .allowed ? Tokens.success : Tokens.textMuted)
            }
            Text("Used for: \(permission.use)").font(.callout)
            Text("Without it: \(permission.missing)").font(.caption).foregroundStyle(Tokens.textMuted)
            if status != .allowed, permission.tccService != nil {
                Text("If Harbor already shows as on in System Settings, macOS is holding on to an entry from an earlier build. Reset and Ask Again removes it so you can allow this one.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
            }
            HStack {
                if status != .allowed { Button("Grant") { permission.request() } }
                if status != .allowed, permission.tccService != nil {
                    Button("Reset and Ask Again") { permission.resetAndAsk() }
                }
                Button("Open System Settings") { permission.openSettings() }
            }
        }
        .padding(.vertical, Tokens.Space.xs)
    }

    private func statusText(_ status: Permission.Status) -> String {
        switch status {
        case .allowed: "Allowed"
        case .denied: "Not allowed"
        case .notAsked: "Not asked yet"
        }
    }
}
