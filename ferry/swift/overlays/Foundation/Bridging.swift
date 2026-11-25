// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for Foundation (freemac 1.227): how Swift's
// String, Array, Dictionary and Set and its numbers become Foundation's
// NSString, NSArray, NSDictionary, NSSet and NSNumber and back, which the
// compiler does wherever Swift code meets an Objective-C method that takes
// or returns one. Swift's standard library does the work (its strings and
// collections can stand in for the NS classes, and wrap NS objects); this
// file is the _ObjectiveCBridgeable conformances that connect the two, as
// Swift's documentation of that protocol describes. Written for Ferry; not
// Apple's overlay.

@_spi(Foundation) import Swift
@_exported import Darwin
@_exported import Dispatch
@_exported import ObjectiveC
@_exported import Foundation
@_exported import CoreGraphics

// ---- String and NSString -------------------------------------------------------

extension String: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSString {
        unsafeBitCast(_bridgeToObjectiveCImpl(), to: NSString.self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSString, result: inout String?) {
        result = String(_cocoaString: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSString, result: inout String?) -> Bool {
        result = String(_cocoaString: x)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> String {
        // nil has always stood for the empty string here
        guard let source else { return "" }
        return String(_cocoaString: source)
    }
}

extension Substring: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSString { String(self)._bridgeToObjectiveC() }
    public static func _forceBridgeFromObjectiveC(_ x: NSString, result: inout Substring?) {
        result = Substring(String(_cocoaString: x))
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSString, result: inout Substring?) -> Bool {
        result = Substring(String(_cocoaString: x))
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> Substring {
        Substring(String._unconditionallyBridgeFromObjectiveC(source))
    }
}

extension NSString: ExpressibleByStringLiteral {
    public required convenience init(stringLiteral value: StaticString) {
        let s = value.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
        self.init(string: s)
    }
}

extension NSString: _HasCustomAnyHashableRepresentation {
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(String._unconditionallyBridgeFromObjectiveC(self))
    }
}

// ---- Array and NSArray -----------------------------------------------------------

extension Array: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSArray {
        unsafeBitCast(_bridgeToObjectiveCImpl(), to: NSArray.self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSArray, result: inout Array?) {
        if !_conditionallyBridgeFromObjectiveC(source, result: &result) {
            fatalError("NSArray holds an element that isn't a \(Element.self)")
        }
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSArray, result: inout Array?) -> Bool {
        if _isBridgedVerbatimToObjectiveC(Element.self) {
            // a copy, in case it is mutable; then Swift wraps it as it is
            let copy: AnyObject = source.copy() as AnyObject
            let a = Array<AnyObject>(_immutableCocoaArray: copy)
            guard let typed = a as? [Element] else { return false }
            result = typed
            return true
        }
        var out: [Element] = []
        out.reserveCapacity(source.count)
        for i in 0..<source.count {
            guard let e = source.object(at: i) as? Element else { return false }
            out.append(e)
        }
        result = out
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSArray?) -> Array {
        guard let source else { return [] }
        var result: Array?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}

// ---- Dictionary and NSDictionary --------------------------------------------------

extension Dictionary: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDictionary {
        unsafeBitCast(_bridgeToObjectiveCImpl(), to: NSDictionary.self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSDictionary, result: inout Dictionary?) {
        if !_conditionallyBridgeFromObjectiveC(source, result: &result) {
            fatalError("NSDictionary holds an entry that isn't a \(Key.self): \(Value.self)")
        }
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSDictionary, result: inout Dictionary?) -> Bool {
        var out: [Key: Value] = [:]
        out.reserveCapacity(source.count)
        for k in source.allKeys ?? [] {
            guard let key = k as? Key, let v = source.object(forKey: k), let value = v as? Value else { return false }
            out[key] = value
        }
        result = out
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDictionary?) -> Dictionary {
        guard let source else { return [:] }
        var result: Dictionary?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}

/// print() and string interpolation show an object as its -description
/// (here, where NSString is a String).
extension NSObject: CustomStringConvertible, CustomDebugStringConvertible {}

// ---- AnyHashable ------------------------------------------------------------------

// The keys of an NSDictionary that says nothing of its keys' class, which
// Swift sees as [AnyHashable: Any]; without this the compiler can't say
// what such a method returns in C terms. An object as it is, and the
// object Swift wraps anything else in.
extension AnyHashable: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSObject {
        unsafeBitCast(base as AnyObject, to: NSObject.self)
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSObject, result: inout AnyHashable?) {
        result = AnyHashable(x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSObject, result: inout AnyHashable?) -> Bool {
        result = AnyHashable(x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSObject?) -> AnyHashable {
        AnyHashable(source!)
    }
}

// ---- Set and NSSet -----------------------------------------------------------------

extension Set: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSSet {
        unsafeBitCast(_bridgeToObjectiveCImpl(), to: NSSet.self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSSet, result: inout Set?) {
        if !_conditionallyBridgeFromObjectiveC(source, result: &result) {
            fatalError("NSSet holds an element that isn't a \(Element.self)")
        }
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSSet, result: inout Set?) -> Bool {
        var out = Set<Element>()
        for e in source.allObjects ?? [] {
            guard let x = e as? Element else { return false }
            out.insert(x)
        }
        result = out
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSSet?) -> Set {
        guard let source else { return [] }
        var result: Set?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}
