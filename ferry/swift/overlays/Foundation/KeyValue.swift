// SPDX-License-Identifier: GPL-3.0-or-later
//
// Key-value observing with Swift key paths (freemac 1.230): an object's
// observe(\.property) { object, change in ... }, which keeps observing for
// as long as the observation it returns is kept, and willChangeValue(for:)
// and didChangeValue(for:). The key path must be of @objc properties, whose
// names are the keys the Objective-C methods take. Written for Ferry from
// Apple's documentation.

/// What changed in an observed property.
public struct NSKeyValueObservedChange<Value> {
    public typealias Kind = NSKeyValueChange
    public let kind: Kind
    public let newValue: Value?
    public let oldValue: Value?
    public let indexes: NSIndexSet?
    public let isPrior: Bool
}

/// Watches one property of one object until it is invalidated or let go.
public class NSKeyValueObservation: NSObject {
    private weak var object: NSObject?
    private let key: String
    private let callback: (NSObject, [AnyHashable: Any]) -> Void
    private var observing = false

    init(object: NSObject, key: String, callback: @escaping (NSObject, [AnyHashable: Any]) -> Void) {
        self.object = object
        self.key = key
        self.callback = callback
    }

    func start(_ options: NSKeyValueObservingOptions) {
        observing = true
        object?.addObserver(self, forKeyPath: key, options: options, context: nil)
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [AnyHashable: Any]?,
                                      context: UnsafeMutableRawPointer?) {
        guard let o = object as? NSObject else { return }
        callback(o, change ?? [:])
    }

    /// Stops observing.
    public func invalidate() {
        guard observing else { return }
        observing = false
        object?.removeObserver(self, forKeyPath: key)
    }

    deinit { invalidate() }
}

public protocol _KeyValueCodingAndObserving {}
extension NSObject: _KeyValueCodingAndObserving {}

func _kvcKey<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> String {
    guard let key = keyPath._kvcKeyPathString else {
        fatalError("key-value observing needs a key path of @objc properties")
    }
    return key
}

// On the protocol itself, as on a Mac, so a Mac app's call reaches it by
// the same name (freemac 1.260); only NSObjects take the protocol.
extension _KeyValueCodingAndObserving {
    public func observe<Value>(_ keyPath: KeyPath<Self, Value>, options: NSKeyValueObservingOptions = [],
                               changeHandler: @escaping (Self, NSKeyValueObservedChange<Value>) -> Void)
        -> NSKeyValueObservation {
        let target = self as AnyObject as! NSObject
        let o = NSKeyValueObservation(object: target, key: _kvcKey(keyPath)) { object, change in
            guard let me = object as? Self else { return }
            let raw = change[NSKeyValueChangeKindKey] as? NSNumber
            let kind = raw.flatMap { NSKeyValueChange(rawValue: $0.uintValue) } ?? .setting
            let indexes = change[NSKeyValueChangeIndexesKey] as? NSIndexSet
            let prior = (change[NSKeyValueChangeNotificationIsPriorKey] as? NSNumber)?.boolValue ?? false
            func value(_ k: String) -> Value? {
                guard let v = change[k] else { return nil }
                if v is NSNull { return Optional<Any>.none as? Value }
                return v as? Value
            }
            changeHandler(me, NSKeyValueObservedChange(kind: kind, newValue: value(NSKeyValueChangeNewKey),
                                                       oldValue: value(NSKeyValueChangeOldKey), indexes: indexes,
                                                       isPrior: prior))
        }
        o.start(options)
        return o
    }

}

extension _KeyValueCodingAndObserving where Self: NSObject {
    public func willChangeValue<Value>(for keyPath: KeyPath<Self, Value>) { willChangeValue(forKey: _kvcKey(keyPath)) }
    public func didChangeValue<Value>(for keyPath: KeyPath<Self, Value>) { didChangeValue(forKey: _kvcKey(keyPath)) }
}
