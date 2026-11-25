// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for the Objective-C runtime (freemac 1.227): what
// Swift's compiler expects to find in a module named ObjectiveC when Swift
// code uses Objective-C classes. The compiler maps the C type BOOL to
// ObjCBool and SEL to Selector, and converts BOOL to Bool and back with
// the two functions below; NSObject gets Swift's equality, hashing and
// printing from -isEqual:, -hash and -description. Written for Ferry from
// Swift's public documentation of these types; not Apple's overlay.

@_exported import ObjectiveC // the Objective-C runtime's own headers (Ferry SDK)

// ---- BOOL --------------------------------------------------------------------

/// The Objective-C BOOL type: a signed char on an Intel Mac.
@frozen
public struct ObjCBool: ExpressibleByBooleanLiteral, Sendable {
    @usableFromInline var _value: Int8

    @_transparent public init(_ value: Bool) { _value = value ? 1 : 0 }
    @_transparent public init(booleanLiteral value: Bool) { self.init(value) }

    /// The value as a Swift Bool.
    @_transparent public var boolValue: Bool { _value != 0 }
}

extension ObjCBool: CustomReflectable {
    public var customMirror: Mirror { Mirror(reflecting: boolValue) }
}

extension ObjCBool: CustomStringConvertible {
    public var description: String { boolValue.description }
}

@_transparent
public func _convertBoolToObjCBool(_ x: Bool) -> ObjCBool { ObjCBool(x) }

@_transparent
public func _convertObjCBoolToBool(_ x: ObjCBool) -> Bool { x.boolValue }

// ---- SEL -----------------------------------------------------------------------

/// An Objective-C selector. Ferry's runtime uniques selectors by name, so a
/// selector is the address of its registered name.
@frozen
public struct Selector: ExpressibleByStringLiteral, @unchecked Sendable {
    @usableFromInline var ptr: OpaquePointer

    /// The selector named `str`, registered with the runtime.
    public init(_ str: String) {
        self = str.withCString { sel_registerName($0)! }
    }

    public init(stringLiteral value: String) { self.init(value) }
    public init(unicodeScalarLiteral value: String) { self.init(value) }
    public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
}

extension Selector: Equatable, Hashable {
    public static func == (lhs: Selector, rhs: Selector) -> Bool { sel_isEqual(lhs, rhs) }
    public func hash(into hasher: inout Hasher) { hasher.combine(ptr) }
}

extension Selector: CustomStringConvertible {
    public var description: String { String(cString: sel_getName(self)) }
}

extension String {
    /// The selector's name.
    public init(_sel: Selector) { self = String(cString: sel_getName(_sel)) }
}

extension Selector: CustomReflectable {
    public var customMirror: Mirror { Mirror(reflecting: description) }
}

// ---- NSZone ---------------------------------------------------------------------

/// Zones are a relic: every allocation comes from the one heap.
@frozen
public struct NSZone {
    public var pointer: OpaquePointer
}

// ---- NSObject -----------------------------------------------------------------

extension NSObject: Equatable, Hashable {
    /// Two objects are equal when the first's -isEqual: says so.
    public static func == (lhs: NSObject, rhs: NSObject) -> Bool { lhs.isEqual(rhs) }

    /// -hash, as Objective-C collections use it.
    public func hash(into hasher: inout Hasher) { hasher.combine(self.hash) }
}

extension NSObject: CVarArg {
    public var _cVarArgEncoding: [Int] {
        _autorelease(self)
        return _encodeBitsAsWords(self)
    }
}

/// Objects passed to C's variadic calls (NSLog's %@) must outlive the call.
@inline(never)
internal func _autorelease(_ x: AnyObject) {
    _ = Unmanaged.passRetained(x).autorelease()
}

// ---- autorelease pools -------------------------------------------------------------

@_silgen_name("objc_autoreleasePoolPush")
internal func __pushAutoreleasePool() -> OpaquePointer

@_silgen_name("objc_autoreleasePoolPop")
internal func __popAutoreleasePool(_ pool: OpaquePointer)

/// Runs `body` inside an autorelease pool, as Objective-C's @autoreleasepool.
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    let pool = __pushAutoreleasePool()
    defer { __popAutoreleasePool(pool) }
    return try body()
}
