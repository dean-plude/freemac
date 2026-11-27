// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for CoreFoundation (freemac 1.260). On a Mac every
// Core Foundation type Swift sees (CFString, AXUIElement and the rest)
// conforms to _CFObject, which makes it Hashable with CFHash and CFEqual;
// an app built there calls those through this module. Written for Ferry
// from what Apple documents of Core Foundation's equality and hashing.

@_exported import CoreFoundation

public protocol _CFObject: AnyObject, Hashable {}

extension _CFObject {
    @inline(__always) var _cfRef: CFTypeRef { self }

    public var hashValue: Int { Int(bitPattern: UInt(CFHash(_cfRef))) }

    public func hash(into hasher: inout Hasher) { hasher.combine(hashValue) }

    public static func == (left: Self, right: Self) -> Bool {
        left === right || CFEqual(left._cfRef, right._cfRef)
    }
}
