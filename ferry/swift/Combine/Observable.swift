// SPDX-License-Identifier: GPL-3.0-or-later
//
// ObservableObject and @Published (freemac 1.230), which SwiftUI's views
// follow, and Foundation's publishers: notifications, key-value observing
// and timers. Written for Ferry from Apple's documentation.

import Foundation

// ---- ObservableObject ------------------------------------------------------------------

/// Tells whoever follows an object that it is about to change.
public final class ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    private let subject = PassthroughSubject<Void, Never>()

    public init() {}

    public func send() { subject.send(()) }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Void, S.Failure == Never {
        subject.receive(subscriber: subscriber)
    }
}

/// An object that says when it is about to change.
public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher where ObjectWillChangePublisher.Failure == Never
    var objectWillChange: ObjectWillChangePublisher { get }
}

private final class _WeakPublisher {
    weak var object: AnyObject?
    let publisher = ObservableObjectPublisher()
    init(_ o: AnyObject) { object = o }
}

private let _publishersLock = NSLock()
nonisolated(unsafe) private var _publishers: [ObjectIdentifier: _WeakPublisher] = [:]

extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    /// One publisher for each object, made the first time it is asked for
    /// (Apple's keeps it in the object's @Published properties; Ferry's
    /// keeps it beside the object, for as long as the object lives).
    public var objectWillChange: ObservableObjectPublisher {
        let id = ObjectIdentifier(self)
        _publishersLock.lock()
        defer { _publishersLock.unlock() }
        if let p = _publishers[id], p.object === self { return p.publisher }
        if _publishers.count > 256 { _publishers = _publishers.filter { $0.value.object != nil } }
        let p = _WeakPublisher(self)
        _publishers[id] = p
        return p.publisher
    }
}

/// Sends an object's objectWillChange, when it is the usual kind.
public func _sendObjectWillChange(_ object: AnyObject) {
    guard let o = object as? any ObservableObject else { return }
    _send(o)
}

private func _send<O: ObservableObject>(_ o: O) {
    (o.objectWillChange as? ObservableObjectPublisher)?.send()
}

// ---- @Published ------------------------------------------------------------------------

/// A property of an observable object that says when it changes, and
/// publishes each new value.
@propertyWrapper
public struct Published<Value> {
    /// The value lives in its subject, which sends each new one on.
    final class Storage {
        let subject: CurrentValueSubject<Value, Never>
        init(_ v: Value) { subject = CurrentValueSubject(v) }
    }
    let storage: Storage

    public init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    public init(initialValue: Value) { storage = Storage(initialValue) }

    @available(*, unavailable, message: "@Published is only for properties of classes")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    /// The values the property takes, from the one it has now.
    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        let subject: CurrentValueSubject<Value, Never>
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
            subject.receive(subscriber: subscriber)
        }
    }

    public var projectedValue: Publisher {
        get { Publisher(subject: storage.subject) }
        set {}
    }

    public static subscript<Owner: AnyObject>(
        _enclosingInstance object: Owner,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Owner, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Owner, Published<Value>>
    ) -> Value {
        get { object[keyPath: storageKeyPath].storage.subject.value }
        set {
            _sendObjectWillChange(object)
            object[keyPath: storageKeyPath].storage.subject.send(newValue)
        }
    }
}

extension Publisher where Failure == Never {
    /// Keeps a @Published property set to each value, for as long as the
    /// property's object lives.
    public func assign(to published: inout Published<Output>.Publisher) {
        let target = published.subject
        _AssignKeeper.keep(sink { [weak target] v in target?.send(v) }, for: target)
    }
}

enum _AssignKeeper {
    nonisolated(unsafe) static var kept: [ObjectIdentifier: (AnyObject?, [AnyCancellable])] = [:]
    static func keep(_ c: AnyCancellable, for owner: AnyObject) {
        kept = kept.filter { $0.value.0 != nil }
        var entry = kept[ObjectIdentifier(owner)] ?? (owner, [])
        entry.1.append(c)
        kept[ObjectIdentifier(owner)] = entry
    }
}

// ---- Foundation's publishers -----------------------------------------------------------

/// A block called with each notification.
final class _NotificationTarget: NSObject {
    let action: (Notification) -> Void
    init(_ action: @escaping (Notification) -> Void) { self.action = action }
    @objc func fire(_ n: Notification) { action(n) }
}

extension NSNotificationCenter {
    /// Each notification of a name posted here.
    public struct Publisher: Combine.Publisher {
        public typealias Output = Notification
        public typealias Failure = Never
        public let center: NSNotificationCenter
        public let name: Notification.Name
        public let object: AnyObject?

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Notification, S.Failure == Never {
            let subject = PassthroughSubject<Notification, Never>()
            let target = _NotificationTarget { subject.send($0) }
            center.addObserver(target, selector: #selector(_NotificationTarget.fire(_:)), name: name, object: object)
            let c = center
            subject.receive(subscriber: AnySubscriber<Notification, Never>(
                receiveSubscription: { inner in
                    subscriber.receive(subscription: _Cancelling(inner) { c.removeObserver(target) })
                },
                receiveValue: { subscriber.receive($0) },
                receiveCompletion: { subscriber.receive(completion: $0) }))
        }
    }

    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> Publisher {
        Publisher(center: self, name: name, object: object)
    }
}

/// A subscription that also does something when it is cancelled.
final class _Cancelling: Subscription {
    let inner: Subscription
    var onCancel: (() -> Void)?
    init(_ inner: Subscription, _ onCancel: @escaping () -> Void) {
        self.inner = inner
        self.onCancel = onCancel
    }
    func request(_ demand: Subscribers.Demand) { inner.request(demand) }
    func cancel() {
        inner.cancel()
        let f = onCancel
        onCancel = nil
        f?()
    }
}

/// What a key-value observation calls.
final class _KVOTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [AnyHashable: Any]?,
                               context: UnsafeMutableRawPointer?) {
        action()
    }
}

extension NSObject {
    /// The values of an @objc property, from the one it has now, as
    /// key-value observing reports them.
    public struct KeyValueObservingPublisher<Subject: NSObject, Value>: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        public let object: Subject
        public let keyPath: KeyPath<Subject, Value>

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
            guard let name = keyPath._kvcKeyPathString else {
                fatalError("KeyValueObservingPublisher needs a key path of @objc properties")
            }
            let obj = object, kp = keyPath
            let subject = CurrentValueSubject<Value, Never>(obj[keyPath: kp])
            let target = _KVOTarget { subject.send(obj[keyPath: kp]) }
            obj.addObserver(target, forKeyPath: name, options: [], context: nil)
            subject.receive(subscriber: AnySubscriber<Value, Never>(
                receiveSubscription: { inner in
                    subscriber.receive(subscription: _Cancelling(inner) { obj.removeObserver(target, forKeyPath: name) })
                },
                receiveValue: { subscriber.receive($0) },
                receiveCompletion: { subscriber.receive(completion: $0) }))
        }
    }
}


extension _KeyValueCodingAndObserving where Self: NSObject {
    public func publisher<Value>(for keyPath: KeyPath<Self, Value>,
                                 options: NSKeyValueObservingOptions = [.initial, .new]) -> NSObject.KeyValueObservingPublisher<Self, Value> {
        NSObject.KeyValueObservingPublisher(object: self, keyPath: keyPath)
    }
}

extension NSTimer {
    /// Sends the date each time a timer fires, once connected.
    public final class TimerPublisher: Combine.Publisher {
        public typealias Output = Date
        public typealias Failure = Never
        public let interval: TimeInterval
        public let runLoop: NSRunLoop
        public let mode: NSRunLoop.Mode
        private let subject = PassthroughSubject<Date, Never>()
        private var timer: NSTimer?
        private var target: _TimerTarget?

        init(interval: TimeInterval, runLoop: NSRunLoop, mode: NSRunLoop.Mode) {
            self.interval = interval
            self.runLoop = runLoop
            self.mode = mode
        }

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Date, S.Failure == Never {
            subject.receive(subscriber: subscriber)
        }

        /// Starts the timer; cancelling stops it.
        public func connect() -> Cancellable {
            // The run loop keeps the timer, the timer its target and the
            // target this publisher, until the timer is stopped.
            let subject = self.subject
            let t = _TimerTarget { subject.send(Date()) }
            let timer = NSTimer(timeInterval: interval, target: t, selector: #selector(_TimerTarget.fire(_:)),
                                userInfo: nil, repeats: true)
            runLoop.add(timer, forMode: mode)
            self.timer = timer
            target = t
            return AnyCancellable { [self] in
                self.timer?.invalidate()
                self.timer = nil
            }
        }

        /// Starts the timer when subscribed to, and stops it when that is cancelled.
        public func autoconnect() -> AnyPublisher<Date, Never> {
            let me = self
            return AnyPublisher(_AutoConnect(publisher: me))
        }
    }

    public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: NSRunLoop,
                               in mode: NSRunLoop.Mode, options: NSRunLoop.SchedulerOptions? = nil) -> TimerPublisher {
        TimerPublisher(interval: interval, runLoop: runLoop, mode: mode)
    }
}

struct _AutoConnect: Publisher {
    typealias Output = Date
    typealias Failure = Never
    let publisher: NSTimer.TimerPublisher
    func receive<S: Subscriber>(subscriber: S) where S.Input == Date, S.Failure == Never {
        let connection = publisher.connect()
        publisher.receive(subscriber: AnySubscriber<Date, Never>(
            receiveSubscription: { inner in subscriber.receive(subscription: _Cancelling(inner) { connection.cancel() }) },
            receiveValue: { subscriber.receive($0) },
            receiveCompletion: { subscriber.receive(completion: $0) }))
    }
}
