import AppKit

/// Which displays are showing a fullscreen app's Space right now.
///
/// Matching a window against the screen size misses fullscreen apps when the menu bar stays visible, because
/// the window then stops below it. The window server knows the Space's type directly; window managers such as
/// yabai read it the same way. Safe off the main thread: it uses Quartz display bounds, not NSScreen.
enum FullscreenSpaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    /// The window server's type for a Space that holds a fullscreen app.
    private static let fullscreenType: Int32 = 4

    private struct API: @unchecked Sendable {
        let connection: Int32
        let currentSpace: CurrentSpace
        let spaceType: SpaceType
    }

    // Private symbols can vanish in a future macOS; when they do this reports nothing and the size check remains.
    private static let api: API? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let current = dlsym(handle, "SLSManagedDisplayGetCurrentSpace"),
              let type = dlsym(handle, "SLSSpaceGetType") else { return nil }
        return API(connection: unsafeBitCast(main, to: MainConnection.self)(),
                   currentSpace: unsafeBitCast(current, to: CurrentSpace.self),
                   spaceType: unsafeBitCast(type, to: SpaceType.self))
    }()

    /// Frames, in AppKit coordinates, of displays whose current Space is a fullscreen app.
    static func frames() -> [CGRect] {
        guard let api else { return [] }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return displays.compactMap { display in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
                  let string = CFUUIDCreateString(nil, uuid) else { return nil }
            let space = api.currentSpace(api.connection, string)
            guard space != 0, api.spaceType(api.connection, space) == fullscreenType else { return nil }
            let bounds = CGDisplayBounds(display)
            return CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        }
    }
}
