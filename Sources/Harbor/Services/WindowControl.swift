import AppKit
import ApplicationServices
import HarborCore

/// Window actions on other apps through the Accessibility API. Every call
/// degrades to plain activation when permission is missing.
@MainActor
enum WindowControl {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility pane.
    static func requestTrust() {
        // The constant's value; reading the global directly trips strict concurrency.
        let key = "AXTrustedCheckOptionPrompt"
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    struct Window {
        let element: AXUIElement
        let title: String
        let minimized: Bool
    }

    static func windows(of pid: pid_t) -> [Window] {
        guard isTrusted else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }
        return elements.compactMap { element in
            guard string(element, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) else { return nil }
            return Window(element: element,
                          title: string(element, kAXTitleAttribute) ?? "",
                          minimized: bool(element, kAXMinimizedAttribute) ?? false)
        }
    }

    static func raise(_ window: Window, pid: pid_t) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Presses the window's close button; a window without one is left alone.
    static func close(_ window: Window) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString, &value) == .success,
              let button = value else { return }
        // swiftlint:disable:next force_cast
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    static func minimizeFront(of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value else { return }
        // swiftlint:disable:next force_cast
        AXUIElementSetAttributeValue(window as! AXUIElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    /// Brings the app's back-most window to the front, so repeated clicks walk every window.
    static func cycle(_ pid: pid_t) {
        let list = windows(of: pid).filter { !$0.minimized }
        guard list.count > 1, let last = list.last else {
            if let only = windows(of: pid).first { raise(only, pid: pid) }
            return
        }
        raise(last, pid: pid)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: point, size: size)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}

/// Launching, activating and acting on dock items.
@MainActor
enum ItemActions {
    static func open(_ item: DockItem, dock: Dock, running: RunningApps, settings: AppSettings,
                     browseFolder: (DockItem) -> Void) {
        guard let url = item.url else { return }
        switch item.kind {
        case .app:
            if let app = running.app(atPath: url.path) {
                if app.isActive && !app.isHidden {
                    applyActiveClick(dock.behavior.activeAppClick, pid: app.pid)
                } else {
                    activate(url: url)
                }
            } else {
                running.markLaunching(url.path)
                activate(url: url)
            }
        case .folder:
            let click = item.folder.onClick == .inherit ? settings.folderClick : item.folder.onClick
            if click == .browse { browseFolder(item) } else { openFolder(url, item: item, settings: settings) }
        case .file:
            NSWorkspace.shared.open(url)
        case .widget:
            break
        }
    }

    /// Opens or re-opens an app; for a running app this also restores a closed main window.
    static func activate(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    static func applyActiveClick(_ action: ActiveAppClick, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        switch action {
        case .none: app.activate()
        case .hide: app.hide()
        case .minimize: WindowControl.minimizeFront(of: pid)
        case .cycleWindows: WindowControl.cycle(pid)
        }
    }

    static func openFolder(_ url: URL, item: DockItem, settings: AppSettings) {
        if let appPath = item.folder.openWithApp ?? settings.folderApp {
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: appPath),
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens dropped files with an app.
    static func open(_ files: [URL], withApp app: URL) {
        NSWorkspace.shared.open(files, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Moves dropped files into a folder; never overwrites, a clash gets a numbered name.
    static func move(_ files: [URL], into folder: URL, copy: Bool = false) {
        let fm = FileManager.default
        for file in files {
            let target = uniqueDestination(for: file.lastPathComponent, in: folder)
            if copy { try? fm.copyItem(at: file, to: target) } else { try? fm.moveItem(at: file, to: target) }
        }
    }

    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    static func trash(_ files: [URL]) {
        for file in files { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
    }
}
