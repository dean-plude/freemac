// SPDX-License-Identifier: GPL-3.0-or-later
//
// State, bindings, observable objects and the environment (freemac 1.227),
// written for Ferry from Apple's SwiftUI documentation.
//
// A view is a value made again each time its parent's body runs, so what a
// @State holds can't live in it. Each property wrapper here holds a small
// object; before a view's body runs, Ferry finds those objects with Mirror
// and points each at the storage kept for that place in the tree (a Slot),
// made the first time with the value the view started with. Changing it
// marks the window's content as needing its bodies run again.

import AppKit

/// What a property wrapper in a view needs before its body runs.
public protocol DynamicProperty {
    mutating func update()
}

extension DynamicProperty {
    public mutating func update() {}
}

/// Attached to the storage for its place in the tree; internal to Ferry.
protocol _AttachableProperty {
    func _attach(to slot: Slot, key: Int, cx: ResolveContext)
}

/// Where something a property wrapper keeps lives, and who to tell when it changes.
final class Slot {
    var values: [Int: AnyObject] = [:]
    var tokens: [Int: AnyObject] = [:]
    var appeared = false
}

/// Somewhere a value lives: a @State's storage, or a binding's.
final class StateLocation<Value> {
    var value: Value
    var onChange: [() -> Void] = []
    init(_ value: Value) { self.value = value }
    func set(_ v: Value) {
        value = v
        for f in onChange { f() }
    }
}

final class StateBox<Value> {
    var location: StateLocation<Value>
    init(_ v: Value) { location = StateLocation(v) }
}

/// A value a view owns and changes, kept while the view stays in place.
@propertyWrapper
public struct State<Value>: DynamicProperty, _AttachableProperty {
    let box: StateBox<Value>

    public init(wrappedValue value: Value) { box = StateBox(value) }
    public init(initialValue value: Value) { box = StateBox(value) }

    public var wrappedValue: Value {
        get { box.location.value }
        nonmutating set { box.location.set(newValue) }
    }

    public var projectedValue: Binding<Value> {
        let loc = box.location
        return Binding(get: { loc.value }, set: { loc.set($0) })
    }

    func _attach(to slot: Slot, key: Int, cx: ResolveContext) {
        if let kept = slot.values[key] as? StateLocation<Value> {
            box.location = kept
        } else {
            slot.values[key] = box.location
            let host = cx.host
            box.location.onChange.append { [weak host] in host?.invalidate() }
        }
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() { self.init(wrappedValue: nil) }
}

/// Reads and writes a value that lives somewhere else.
@propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
    let getter: () -> Value
    let setter: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }

    public var projectedValue: Binding<Value> { self }

    public init(projectedValue: Binding<Value>) { self = projectedValue }

    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> Binding<T> {
        let g = getter, s = setter
        return Binding<T>(get: { g()[keyPath: keyPath] },
                          set: { var v = g(); v[keyPath: keyPath] = $0; s(v) })
    }
}

// ---- observable objects ------------------------------------------------------------

/// What tells the views reading an object that it is about to change. Apple's
/// is Combine's; Ferry has no Combine yet, so this one only sends.
public final class ObservableObjectPublisher {
    var observers: [ObjectIdentifier: () -> Void] = [:]
    public init() {}
    public func send() {
        for f in Array(observers.values) { f() }
    }
    func observe(_ owner: AnyObject, _ f: @escaping () -> Void) { observers[ObjectIdentifier(owner)] = f }
    func remove(_ owner: AnyObject) { observers[ObjectIdentifier(owner)] = nil }
}

/// An object whose changes views follow.
public protocol ObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
}

private final class WeakPublisher {
    weak var object: AnyObject?
    let publisher = ObservableObjectPublisher()
    init(_ o: AnyObject) { object = o }
}
private var publishers: [ObjectIdentifier: WeakPublisher] = [:]

extension ObservableObject {
    /// One publisher for each object, made when first asked for.
    public var objectWillChange: ObservableObjectPublisher {
        let id = ObjectIdentifier(self)
        if let p = publishers[id], p.object === self { return p.publisher }
        if publishers.count > 64 { publishers = publishers.filter { $0.value.object != nil } }
        let p = WeakPublisher(self)
        publishers[id] = p
        return p.publisher
    }
}

/// A property of an observable object that tells its views when it changes.
@propertyWrapper
public struct Published<Value> {
    var stored: Value

    public init(wrappedValue: Value) { stored = wrappedValue }
    public init(initialValue: Value) { stored = initialValue }

    @available(*, unavailable, message: "@Published is only for properties of classes")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    public static subscript<Owner: AnyObject>(
        _enclosingInstance object: Owner,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Owner, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Owner, Published<Value>>
    ) -> Value {
        get { object[keyPath: storageKeyPath].stored }
        set {
            if let o = object as? any ObservableObject { o.objectWillChange.send() }
            object[keyPath: storageKeyPath].stored = newValue
        }
    }
}

/// Follow an observable object's changes in a view.
private final class Follower {}

@propertyWrapper @dynamicMemberLookup
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty, _AttachableProperty {
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public init(initialValue: ObjectType) { self.wrappedValue = initialValue }

    public var projectedValue: ObservedObject<ObjectType> { self }

    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
        let o = wrappedValue
        return Binding(get: { o[keyPath: keyPath] }, set: { o[keyPath: keyPath] = $0 })
    }

    func _attach(to slot: Slot, key: Int, cx: ResolveContext) {
        follow(wrappedValue, slot: slot, key: key, cx: cx)
    }
}

func follow(_ object: any ObservableObject, slot: Slot, key: Int, cx: ResolveContext) {
    if let kept = slot.tokens[key] as? (AnyObject, Follower), kept.0 === object { return }
    let token = Follower()
    let host = cx.host
    object.objectWillChange.observe(token) { [weak host] in host?.invalidate() }
    slot.tokens[key] = (object, token) as AnyObject
    slot.values[-key - 1] = token
}

final class ObjectBox<O> {
    var object: O?
    let make: () -> O
    init(_ make: @escaping () -> O) { self.make = make }
}

/// An observable object a view makes once and keeps.
@propertyWrapper @dynamicMemberLookup
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty, _AttachableProperty {
    let box: ObjectBox<ObjectType>

    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { box = ObjectBox(thunk) }

    public var wrappedValue: ObjectType {
        if let o = box.object { return o }
        let o = box.make()
        box.object = o
        return o
    }

    public var projectedValue: ObservedObject<ObjectType> { ObservedObject(wrappedValue: wrappedValue) }

    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
        projectedValue[dynamicMember: keyPath]
    }

    func _attach(to slot: Slot, key: Int, cx: ResolveContext) {
        if let kept = slot.values[key] as? ObjectBox<ObjectType> {
            box.object = kept.wrappedObject
        } else {
            slot.values[key] = box
        }
        follow(wrappedValue, slot: slot, key: key, cx: cx)
    }
}

extension ObjectBox {
    var wrappedObject: O {
        if let o = object { return o }
        let o = make()
        object = o
        return o
    }
}

// ---- the environment ----------------------------------------------------------------

/// A value views inherit from the views around them.
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// The values a view inherits.
public struct EnvironmentValues {
    var values: [ObjectIdentifier: Any] = [:]
    var objects: [ObjectIdentifier: AnyObject] = [:]
    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }
}

public enum ColorScheme: Hashable, Sendable { case light, dark }

private struct ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }
private struct IsEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct FontKey: EnvironmentKey { static let defaultValue: Font? = nil }
private struct ForegroundKey: EnvironmentKey { static let defaultValue: Color? = nil }
private struct DismissKey: EnvironmentKey { static let defaultValue = DismissAction(close: {}) }

extension EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
    public var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }
    var foreground: Color? {
        get { self[ForegroundKey.self] }
        set { self[ForegroundKey.self] = newValue }
    }
    public var dismiss: DismissAction {
        get { self[DismissKey.self] }
        set { self[DismissKey.self] = newValue }
    }
}

/// Closes the window a view is in.
public struct DismissAction {
    let close: () -> Void
    public func callAsFunction() { close() }
}

final class EnvironmentBox {
    var values = EnvironmentValues()
}

/// Reads a value from the environment.
@propertyWrapper
public struct Environment<Value>: DynamicProperty, _AttachableProperty {
    let keyPath: KeyPath<EnvironmentValues, Value>
    let box = EnvironmentBox()

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }

    public var wrappedValue: Value { box.values[keyPath: keyPath] }

    func _attach(to slot: Slot, key: Int, cx: ResolveContext) { box.values = cx.environment }
}

final class EnvironmentObjectBox<O> {
    var object: O?
}

/// An observable object put in the environment by a view around this one.
@propertyWrapper @dynamicMemberLookup
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty, _AttachableProperty {
    let box = EnvironmentObjectBox<ObjectType>()
    public init() {}

    public var wrappedValue: ObjectType {
        guard let o = box.object else {
            fatalError("No ObservableObject of type \(ObjectType.self) found; a view around this one should give it with .environmentObject")
        }
        return o
    }

    public var projectedValue: ObservedObject<ObjectType> { ObservedObject(wrappedValue: wrappedValue) }

    public subscript<T>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> {
        projectedValue[dynamicMember: keyPath]
    }

    func _attach(to slot: Slot, key: Int, cx: ResolveContext) {
        box.object = cx.environment.objects[ObjectIdentifier(ObjectType.self)] as? ObjectType
        if let o = box.object { follow(o, slot: slot, key: key, cx: cx) }
    }
}

/// A value saved in the user's defaults, under a key.
@propertyWrapper
public struct AppStorage<Value>: DynamicProperty, _AttachableProperty {
    let state: State<Value>
    let key: String

    public init(wrappedValue: Value, _ key: String) {
        self.key = key
        let saved = NSUserDefaults.standard.object(forKey: key)
        state = State(wrappedValue: (saved as? Value) ?? wrappedValue)
    }

    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set {
            state.wrappedValue = newValue
            NSUserDefaults.standard.set(newValue as AnyObject, forKey: key)
        }
    }

    public var projectedValue: Binding<Value> {
        let s = self
        return Binding(get: { s.wrappedValue }, set: { s.wrappedValue = $0 })
    }

    func _attach(to slot: Slot, key k: Int, cx: ResolveContext) { state._attach(to: slot, key: k, cx: cx) }
}
