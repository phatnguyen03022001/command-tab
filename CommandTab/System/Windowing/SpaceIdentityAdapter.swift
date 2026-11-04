import ColorSync
import CoreFoundation
import CoreGraphics
import Darwin
import Foundation

enum SpaceIdentityAdapter {
    static let symbolNames = [
        "CGSMainConnectionID",
        "CGSManagedDisplayGetCurrentSpace",
        "CGSCopySpacesForWindows"
    ]

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CurrentSpaceFunction = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpacesForWindowsFunction = @convention(c) (
        Int32,
        Int32,
        CFArray
    ) -> Unmanaged<CFArray>?

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY | RTLD_LOCAL
    )

    private static let mainConnection: MainConnectionFunction? = resolve(
        "CGSMainConnectionID",
        as: MainConnectionFunction.self
    )

    private static let currentSpace: CurrentSpaceFunction? = resolve(
        "CGSManagedDisplayGetCurrentSpace",
        as: CurrentSpaceFunction.self
    )

    private static let spacesForWindows: SpacesForWindowsFunction? = resolve(
        "CGSCopySpacesForWindows",
        as: SpacesForWindowsFunction.self
    )

    static var isAvailable: Bool {
        mainConnection != nil && currentSpace != nil && spacesForWindows != nil
    }

    static func currentSpaceByDisplay(
        displayIDs: [CGDirectDisplayID]
    ) -> [CGDirectDisplayID: UInt64]? {
        guard let mainConnection, let currentSpace else { return nil }
        let connectionID = mainConnection()
        var result: [CGDirectDisplayID: UInt64] = [:]
        result.reserveCapacity(displayIDs.count)

        for displayID in displayIDs {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
                  let displayString = CFUUIDCreateString(nil, uuid) else {
                return nil
            }
            let spaceID = currentSpace(connectionID, displayString)
            guard spaceID != 0 else { return nil }
            result[displayID] = spaceID
        }
        return result
    }

    static func spaceIDs(for windowID: CGWindowID) -> [UInt64]? {
        guard let mainConnection, let spacesForWindows else { return nil }
        let connectionID = mainConnection()
        let input = [NSNumber(value: windowID)] as CFArray
        guard let copied = spacesForWindows(connectionID, 7, input)?.takeRetainedValue(),
              let values = copied as? [NSNumber] else {
            return nil
        }
        return Array(Set(values.map(\.uint64Value))).sorted()
    }

    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}
