import AppKit
import HarborCore
import ScreenCaptureKit

/// Looks at the screen for long horizontal edges, as extra ledges where Accessibility reports none.
/// It takes one small grayscale picture of a display, without Harbor's own windows, only when asked
/// after something changed, and never more often than every two seconds.
@MainActor
final class RoamVisionScanner {
    static let minInterval: TimeInterval = 2
    /// The picture is taken at half the screen's size in points, a quarter of its pixels on a Retina display.
    nonisolated static let scale = 0.5

    /// Ledge rects in AppKit coordinates for one screen, delivered on the main thread.
    var onUpdate: ((_ screenFrame: CGRect, _ rects: [CGRect]) -> Void)?

    private var dirty = true
    private var busy = false
    private var lastCapture = Date.distantPast
    private var content: SCShareableContent?

    /// Screen Recording permission is checked without ever asking for it.
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Something on screen may have moved, so the next chance to look is worth taking.
    func markDirty() { dirty = true }

    /// The list of displays and Harbor's own app goes stale when screens change.
    func screensChanged() {
        content = nil
        dirty = true
    }

    /// Takes a picture of the display at `frame` if one is due. `known` are the ledges already found by
    /// other means, so edges they cover are left out.
    func lookIfDue(frame: CGRect, menuBarHeight: Double, known: [RoamSurface]) {
        guard dirty, !busy, Date().timeIntervalSince(lastCapture) >= Self.minInterval, Self.isAllowed else { return }
        dirty = false
        busy = true
        lastCapture = Date()
        Task {
            let rects = await capture(frame: frame, menuBarHeight: menuBarHeight, known: known)
            busy = false
            if let rects { onUpdate?(frame, rects) }
        }
    }

    private func capture(frame: CGRect, menuBarHeight: Double, known: [RoamSurface]) async -> [CGRect]? {
        do {
            if content == nil { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            guard let content else { return nil }
            let displayID = NSScreen.screens.first { $0.frame == frame }?
                .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let width = Int(frame.width * Self.scale)
            let height = Int(frame.height * Self.scale)
            config.width = width
            config.height = height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return await Task.detached(priority: .utility) {
                guard let gray = Self.grayscale(image, width: width, height: height) else { return [CGRect]() }
                let minRun = Int(RoamVision.minLength * Self.scale)
                let edges = RoamVision.edges(gray: gray, width: width, height: height, minRun: minRun)
                return RoamVision.ledges(edges, imageWidth: width, imageHeight: height, screen: frame,
                                         menuBarHeight: menuBarHeight, known: known)
            }.value
        } catch {
            content = nil
            return nil
        }
    }

    nonisolated private static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
