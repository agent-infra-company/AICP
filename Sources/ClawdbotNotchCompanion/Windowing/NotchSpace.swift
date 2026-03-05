import AppKit

/// Manages a private CGS compositing space at maximum z-order.
/// Windows inserted into this space render above all system UI
/// including the menu bar background in the notch area.
///
/// Uses private CoreGraphics Server APIs via dlopen/dlsym.
@MainActor
final class NotchSpace {
    static let shared = NotchSpace()

    private let connection: Int32
    private let space: Int32

    private init() {
        let handle = dlopen(nil, RTLD_NOW)

        typealias F_CGSDefaultConnection = @convention(c) () -> Int32
        typealias F_CGSSpaceCreate = @convention(c) (Int32, Int32, UnsafeRawPointer?) -> Int32
        typealias F_CGSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias F_CGSShowSpaces = @convention(c) (Int32, CFArray) -> Int32

        let _CGSDefaultConnection = unsafeBitCast(
            dlsym(handle, "_CGSDefaultConnection"),
            to: F_CGSDefaultConnection.self
        )
        let CGSSpaceCreate = unsafeBitCast(
            dlsym(handle, "CGSSpaceCreate"),
            to: F_CGSSpaceCreate.self
        )
        let CGSSpaceSetAbsoluteLevel = unsafeBitCast(
            dlsym(handle, "CGSSpaceSetAbsoluteLevel"),
            to: F_CGSSpaceSetAbsoluteLevel.self
        )
        let CGSShowSpaces = unsafeBitCast(
            dlsym(handle, "CGSShowSpaces"),
            to: F_CGSShowSpaces.self
        )

        connection = _CGSDefaultConnection()
        space = CGSSpaceCreate(connection, 0x1, nil)
        _ = CGSSpaceSetAbsoluteLevel(connection, space, Int32.max)
        _ = CGSShowSpaces(connection, [space] as CFArray)
    }

    func addWindow(_ window: NSWindow) {
        let handle = dlopen(nil, RTLD_NOW)

        typealias F_CGSAddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
        let CGSAddWindowsToSpaces = unsafeBitCast(
            dlsym(handle, "CGSAddWindowsToSpaces"),
            to: F_CGSAddWindowsToSpaces.self
        )
        CGSAddWindowsToSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    func removeWindow(_ window: NSWindow) {
        let handle = dlopen(nil, RTLD_NOW)

        typealias F_CGSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
        let CGSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handle, "CGSRemoveWindowsFromSpaces"),
            to: F_CGSRemoveWindowsFromSpaces.self
        )
        CGSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
