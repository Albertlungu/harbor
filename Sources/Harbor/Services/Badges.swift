import AppKit
import ApplicationServices
import Observation

/// Notification badge strings, read from the native Dock's Accessibility tree.
/// Polls only while a dock shows badges and Accessibility is granted.
@MainActor
@Observable
final class Badges {
    private(set) var byPath: [String: String] = [:]
    private(set) var byName: [String: String] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var reading = false

    struct Entry: Sendable {
        let title: String
        let label: String
        let path: String?
    }

    /// Starts or stops the 2 s poll depending on whether anything needs it.
    func setNeeded(_ needed: Bool) {
        let wanted = needed && AXIsProcessTrusted()
        if wanted, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            poll()
        } else if !wanted, timer != nil {
            timer?.invalidate()
            timer = nil
            if !byPath.isEmpty || !byName.isEmpty { byPath = [:]; byName = [:] }
        }
    }

    private func poll() {
        guard !reading else { return }
        reading = true
        // The Dock can be slow to answer; keep the main thread out of it.
        Task { @MainActor [weak self] in
            let entries = await Task.detached(priority: .utility) { Self.readEntries() }.value
            guard let self else { return }
            self.reading = false
            var paths: [String: String] = [:]
            var names: [String: String] = [:]
            for entry in entries {
                if let path = entry.path { paths[RunningApps.normalize(path)] = entry.label }
                names[entry.title.lowercased()] = entry.label
            }
            if paths != self.byPath { self.byPath = paths }
            if names != self.byName { self.byName = names }
        }
    }

    nonisolated private static func readEntries() -> [Entry] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var result: [Entry] = []
        for list in children(of: app) where string(list, kAXRoleAttribute) == (kAXListRole as String) {
            for item in children(of: list) where string(item, kAXRoleAttribute) == "AXDockItem" {
                guard let label = string(item, "AXStatusLabel"), !label.isEmpty else { continue }
                var path: String?
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &value) == .success,
                   let url = value as? URL, url.isFileURL { path = url.path }
                result.append(Entry(title: string(item, kAXTitleAttribute) ?? "", label: label, path: path))
            }
        }
        return result
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: Lookup

    /// The text to draw for an app, or nil when it has no badge or its badge is turned off.
    func text(forPath path: String, name: String, bundleID: String?, behavior: BadgeRules) -> String? {
        let normalized = RunningApps.normalize(path)
        let disabled = behavior.disabled.map { $0.lowercased() }
        if disabled.contains(normalized.lowercased()) || disabled.contains(name.lowercased())
            || bundleID.map({ disabled.contains($0.lowercased()) }) == true { return nil }
        guard let label = byPath[normalized] ?? byName[name.lowercased()] else { return nil }
        if !behavior.fullNumber, let number = Int(label.filter(\.isNumber)), label.allSatisfy({ $0.isNumber || $0 == "," }),
           number > 99 { return "99+" }
        return label
    }
}

struct BadgeRules {
    let disabled: [String]
    let fullNumber: Bool
}
