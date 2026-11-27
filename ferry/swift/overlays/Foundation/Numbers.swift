// SPDX-License-Identifier: GPL-3.0-or-later
//
// Swift's numbers and Bool as NSNumber and back (freemac 1.227), for Ferry's
// Foundation overlay: an Int put in an NSArray or passed as "id" becomes an
// NSNumber, and an NSNumber taken out as an Int is read with -integerValue.
// Taking one out as another type reads it as that type. Written for Ferry.

extension Int: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(integer: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int?) {
        result = x.integerValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int?) -> Bool {
        result = x.integerValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int {
        source?.integerValue ?? 0
    }
}

extension UInt: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(unsignedInteger: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt?) {
        result = x.uintValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt?) -> Bool {
        result = x.uintValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt {
        source?.uintValue ?? 0
    }
}

extension Int8: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(char: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int8?) {
        result = x.charValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int8?) -> Bool {
        result = x.charValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int8 {
        source?.charValue ?? 0
    }
}

extension UInt8: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(unsignedChar: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt8?) {
        result = x.unsignedCharValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt8?) -> Bool {
        result = x.unsignedCharValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt8 {
        source?.unsignedCharValue ?? 0
    }
}

extension Int16: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(short: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int16?) {
        result = x.shortValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int16?) -> Bool {
        result = x.shortValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int16 {
        source?.shortValue ?? 0
    }
}

extension UInt16: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(unsignedShort: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt16?) {
        result = x.unsignedShortValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt16?) -> Bool {
        result = x.unsignedShortValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt16 {
        source?.unsignedShortValue ?? 0
    }
}

extension Int32: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(int: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int32?) {
        result = x.intValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int32?) -> Bool {
        result = x.intValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int32 {
        source?.intValue ?? 0
    }
}

extension UInt32: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(unsignedInt: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt32?) {
        result = x.unsignedIntValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt32?) -> Bool {
        result = x.unsignedIntValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt32 {
        source?.unsignedIntValue ?? 0
    }
}

extension Int64: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(longLong: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int64?) {
        result = x.longLongValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int64?) -> Bool {
        result = x.longLongValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int64 {
        source?.longLongValue ?? 0
    }
}

extension UInt64: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(unsignedLongLong: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt64?) {
        result = x.unsignedLongLongValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt64?) -> Bool {
        result = x.unsignedLongLongValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt64 {
        source?.unsignedLongLongValue ?? 0
    }
}

extension Float: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(float: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Float?) {
        result = x.floatValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Float?) -> Bool {
        result = x.floatValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Float {
        source?.floatValue ?? 0
    }
}

extension Double: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(double: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Double?) {
        result = x.doubleValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Double?) -> Bool {
        result = x.doubleValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Double {
        source?.doubleValue ?? 0
    }
}

extension Bool: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(bool: self) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Bool?) {
        result = x.boolValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Bool?) -> Bool {
        result = x.boolValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Bool {
        source?.boolValue ?? false
    }
}

extension CGFloat: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(double: Double(self)) }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout CGFloat?) {
        result = CGFloat(x.doubleValue)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout CGFloat?) -> Bool {
        result = CGFloat(x.doubleValue)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> CGFloat {
        CGFloat(source?.doubleValue ?? 0)
    }
}

// An NSNumber as a dictionary key or set member hashes as the Swift number
// it holds, so that a key bridged from Objective-C finds a Swift Int.
extension NSNumber: _HasCustomAnyHashableRepresentation {
    public func _toCustomAnyHashable() -> AnyHashable? {
        let d = doubleValue
        if d == Double(integerValue) { return AnyHashable(integerValue) }
        return AnyHashable(d)
    }
}

extension NSNumber: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    public required convenience init(integerLiteral value: Int) { self.init(integer: value) }
    public required convenience init(floatLiteral value: Double) { self.init(double: value) }
    public required convenience init(booleanLiteral value: Bool) { self.init(bool: value) }
}

extension NSNumber {
    public convenience init(value: Int) { self.init(integer: value) }
    public convenience init(value: UInt) { self.init(unsignedInteger: value) }
    public convenience init(value: Int32) { self.init(int: value) }
    public convenience init(value: Int64) { self.init(longLong: value) }
    public convenience init(value: UInt64) { self.init(unsignedLongLong: value) }
    public convenience init(value: Double) { self.init(double: value) }
    public convenience init(value: Float) { self.init(float: value) }
    public convenience init(value: Bool) { self.init(bool: value) }
    public convenience init(value: CGFloat) { self.init(double: Double(value)) }
}

// ---- init(truncating:), as a Mac's Foundation has it (freemac 1.260) -----------------

extension Int { public init(truncating number: __shared NSNumber) { self = number.integerValue } }
extension UInt { public init(truncating number: __shared NSNumber) { self = UInt(truncatingIfNeeded: number.unsignedLongLongValue) } }
extension Int8 { public init(truncating number: __shared NSNumber) { self = Int8(truncatingIfNeeded: number.longLongValue) } }
extension Int16 { public init(truncating number: __shared NSNumber) { self = Int16(truncatingIfNeeded: number.longLongValue) } }
extension Int32 { public init(truncating number: __shared NSNumber) { self = Int32(truncatingIfNeeded: number.longLongValue) } }
extension Int64 { public init(truncating number: __shared NSNumber) { self = Int64(number.longLongValue) } }
extension UInt8 { public init(truncating number: __shared NSNumber) { self = UInt8(truncatingIfNeeded: number.unsignedLongLongValue) } }
extension UInt16 { public init(truncating number: __shared NSNumber) { self = UInt16(truncatingIfNeeded: number.unsignedLongLongValue) } }
extension UInt32 { public init(truncating number: __shared NSNumber) { self = UInt32(truncatingIfNeeded: number.unsignedLongLongValue) } }
extension UInt64 { public init(truncating number: __shared NSNumber) { self = UInt64(number.unsignedLongLongValue) } }
extension Double { public init(truncating number: __shared NSNumber) { self = number.doubleValue } }
extension Float { public init(truncating number: __shared NSNumber) { self = Float(number.doubleValue) } }
extension Bool { public init(truncating number: __shared NSNumber) { self = number.boolValue } }
