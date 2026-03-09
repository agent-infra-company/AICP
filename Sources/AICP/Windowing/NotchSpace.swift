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

    /// Whether private CGS APIs were resolved successfully.
    let isAvailable: Bool

    private init() {
        let handle = dlopen(nil, RTLD_NOW)

        typealias F_CGSDefaultConnection = @convention(c) () -> Int32
        typealias F_CGSSpaceCreate = @convention(c) (Int32, Int32, UnsafeRawPointer?) -> Int32
        typealias F_CGSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias F_CGSShowSpaces = @convention(c) (Int32, CFArray) -> Int32

        guard let pConn = dlsym(handle, "_CGSDefaultConnection"),
              let pCreate = dlsym(handle, "CGSSpaceCreate"),
              let pLevel = dlsym(handle, "CGSSpaceSetAbsoluteLevel"),
              let pShow = dlsym(handle, "CGSShowSpaces") else {
            connection = 0
            space = 0
            isAvailable = false
            return
        }

        let _CGSDefaultConnection = unsafeBitCast(pConn, to: F_CGSDefaultConnection.self)
        let CGSSpaceCreate = unsafeBitCast(pCreate, to: F_CGSSpaceCreate.self)
        let CGSSpaceSetAbsoluteLevel = unsafeBitCast(pLevel, to: F_CGSSpaceSetAbsoluteLevel.self)
        let CGSShowSpaces = unsafeBitCast(pShow, to: F_CGSShowSpaces.self)

        connection = _CGSDefaultConnection()
        space = CGSSpaceCreate(connection, 0x1, nil)
        _ = CGSSpaceSetAbsoluteLevel(connection, space, Int32.max)
        _ = CGSShowSpaces(connection, [space] as CFArray)
        isAvailable = true
    }

    func addWindow(_ window: NSWindow) {
        guard isAvailable else { return }
        let handle = dlopen(nil, RTLD_NOW)

        typealias F_CGSAddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
        guard let ptr = dlsym(handle, "CGSAddWindowsToSpaces") else { return }
        let CGSAddWindowsToSpaces = unsafeBitCast(ptr, to: F_CGSAddWindowsToSpaces.self)
        CGSAddWindowsToSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    func removeWindow(_ window: NSWindow) {
        guard isAvailable else { return }
        let handle = dlopen(nil, RTLD_NOW)

        typealias F_CGSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
        guard let ptr = dlsym(handle, "CGSRemoveWindowsFromSpaces") else { return }
        let CGSRemoveWindowsFromSpaces = unsafeBitCast(ptr, to: F_CGSRemoveWindowsFromSpaces.self)
        CGSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
