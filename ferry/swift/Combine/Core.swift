// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Combine (freemac 1.230): publishers, subscribers and
// subscriptions as Apple's documentation of the framework describes them,
// with the subjects, the common operators, schedulers on Dispatch queues
// and run loops, and ObservableObject and @Published, which SwiftUI's
// views follow. Written for Ferry. It is small: values are delivered as
// they come, a subscriber's demand is kept by the subjects and passed
// along by the operators, and nothing here is thread-safe beyond what a
// lock around each subject gives.

import Foundation

// ---- the protocols ---------------------------------------------------------------------

/// An identifier for a subscriber, unique for as long as it lives.
public struct CombineIdentifier: Hashable, CustomStringConvertible, Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var next: UInt64 = 0
    private let value: UInt64

    public init() {
        CombineIdentifier.lock.lock()
        CombineIdentifier.next += 1
        value = CombineIdentifier.next
        CombineIdentifier.lock.unlock()
    }

    public init(_ obj: AnyObject) { value = UInt64(UInt(bitPattern: ObjectIdentifier(obj).hashValue)) }

    public var description: String { "0x\(String(value, radix: 16))" }
}

public protocol CustomCombineIdentifierConvertible {
    var combineIdentifier: CombineIdentifier { get }
}

extension CustomCombineIdentifierConvertible where Self: AnyObject {
    public var combineIdentifier: CombineIdentifier { CombineIdentifier(self) }
}

/// Something whose work can be stopped.
public protocol Cancellable {
    func cancel()
}

/// What a publisher gives a subscriber, through which it asks for values.
public protocol Subscription: Cancellable, CustomCombineIdentifierConvertible {
    func request(_ demand: Subscribers.Demand)
}

/// What receives a publisher's values and its completion.
public protocol Subscriber<Input, Failure>: CustomCombineIdentifierConvertible {
    associatedtype Input
    associatedtype Failure: Error
    func receive(subscription: Subscription)
    func receive(_ input: Input) -> Subscribers.Demand
    func receive(completion: Subscribers.Completion<Failure>)
}

/// Something that sends values, then perhaps a completion, to its subscribers.
public protocol Publisher<Output, Failure> {
    associatedtype Output
    associatedtype Failure: Error
    func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure
}

extension Publisher {
    public func subscribe<S: Subscriber>(_ subscriber: S) where S.Input == Output, S.Failure == Failure {
        receive(subscriber: subscriber)
    }
}

/// A publisher one can send values through.
public protocol Subject<Output, Failure>: AnyObject, Publisher {
    func send(_ value: Output)
    func send(completion: Subscribers.Completion<Failure>)
    func send(subscription: Subscription)
}

extension Subject where Output == Void {
    public func send() { send(()) }
}

public enum Subscribers {}
public enum Publishers {}

extension Subscribers {
    /// How a publisher's sending ends.
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }

    /// How many more values a subscriber wants.
    public struct Demand: Equatable, Comparable, Hashable, Sendable, CustomStringConvertible {
        @usableFromInline let rawValue: UInt
        init(rawValue: UInt) { self.rawValue = rawValue }

        public static let unlimited = Demand(rawValue: .max)
        public static let none = Demand(rawValue: 0)
        public static func max(_ value: Int) -> Demand {
            precondition(value >= 0, "a demand can't be negative")
            return Demand(rawValue: UInt(value))
        }

        public var max: Int? { self == .unlimited ? nil : Int(rawValue) }
        public var description: String { self == .unlimited ? "unlimited" : "max(\(rawValue))" }

        public static func + (a: Demand, b: Demand) -> Demand {
            if a == .unlimited || b == .unlimited { return .unlimited }
            let (s, o) = a.rawValue.addingReportingOverflow(b.rawValue)
            return o || s == .max ? .unlimited : Demand(rawValue: s)
        }
        public static func + (a: Demand, b: Int) -> Demand { b < 0 ? a - .max(-b) : a + .max(b) }
        public static func += (a: inout Demand, b: Demand) { a = a + b }
        public static func += (a: inout Demand, b: Int) { a = a + b }
        public static func - (a: Demand, b: Demand) -> Demand {
            if a == .unlimited { return .unlimited }
            if b == .unlimited { return .none }
            return Demand(rawValue: a.rawValue > b.rawValue ? a.rawValue - b.rawValue : 0)
        }
        public static func - (a: Demand, b: Int) -> Demand { b < 0 ? a + .max(-b) : a - .max(b) }
        public static func -= (a: inout Demand, b: Demand) { a = a - b }
        public static func -= (a: inout Demand, b: Int) { a = a - b }
        public static func < (a: Demand, b: Demand) -> Bool { a.rawValue < b.rawValue }
        public static func > (a: Demand, b: Int) -> Bool { a.rawValue > UInt(Swift.max(b, 0)) || (b < 0) }
        public static func == (a: Demand, b: Int) -> Bool { b >= 0 && a.rawValue == UInt(b) }
    }
}

extension Subscribers.Completion: Equatable where Failure: Equatable {}
extension Subscribers.Completion: Hashable where Failure: Hashable {}

/// A subscription that does nothing, for publishers that send nothing.
public enum Subscriptions {
    public static let empty: Subscription = _EmptySubscription()
}

private final class _EmptySubscription: Subscription {
    func request(_ demand: Subscribers.Demand) {}
    func cancel() {}
}

// ---- AnyCancellable --------------------------------------------------------------------

/// Cancels its work when it is cancelled or let go.
public final class AnyCancellable: Cancellable, Hashable {
    private var onCancel: (() -> Void)?

    public init(_ cancel: @escaping () -> Void) { onCancel = cancel }
    public init<C: Cancellable>(_ canceller: C) { onCancel = canceller.cancel }

    public func cancel() {
        let f = onCancel
        onCancel = nil
        f?()
    }

    deinit { cancel() }

    public static func == (a: AnyCancellable, b: AnyCancellable) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    public func store<C: RangeReplaceableCollection>(in collection: inout C) where C.Element == AnyCancellable {
        collection.append(self)
    }

    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
}

extension Cancellable {
    public func store<C: RangeReplaceableCollection>(in collection: inout C) where C.Element == AnyCancellable {
        AnyCancellable(self).store(in: &collection)
    }
    public func store(in set: inout Set<AnyCancellable>) { AnyCancellable(self).store(in: &set) }
}

// ---- the subjects ----------------------------------------------------------------------

/// One subscriber's place at a subject: its demand, and whether it is still there.
final class _SubjectConduit<Output, Failure: Error>: Subscription {
    weak var subject: _SubjectBase<Output, Failure>?
    var downstream: AnySubscriber<Output, Failure>?
    var demand: Subscribers.Demand = .none
    let lock = NSRecursiveLock()

    init(_ subject: _SubjectBase<Output, Failure>, _ s: AnySubscriber<Output, Failure>) {
        self.subject = subject
        downstream = s
    }

    func request(_ d: Subscribers.Demand) {
        lock.lock()
        demand += d
        lock.unlock()
        subject?.demanded(self)
    }

    func offer(_ v: Output) -> Bool {
        lock.lock()
        guard let s = downstream, demand > 0 else { lock.unlock(); return false }
        demand -= 1
        lock.unlock()
        let more = s.receive(v)
        lock.lock()
        demand += more
        lock.unlock()
        return true
    }

    func finish(_ c: Subscribers.Completion<Failure>) {
        lock.lock()
        let s = downstream
        downstream = nil
        lock.unlock()
        s?.receive(completion: c)
    }

    func cancel() {
        lock.lock()
        downstream = nil
        lock.unlock()
        subject?.remove(self)
    }
}

/// What the subjects share: their subscribers and their completion.
public class _SubjectBase<Output, Failure: Error> {
    var conduits: [_SubjectConduit<Output, Failure>] = []
    var completion: Subscribers.Completion<Failure>?
    var upstream: [Subscription] = []
    let lock = NSRecursiveLock()

    func attach<S: Subscriber>(_ subscriber: S) where S.Input == Output, S.Failure == Failure {
        lock.lock()
        if let c = completion {
            lock.unlock()
            subscriber.receive(subscription: Subscriptions.empty)
            subscriber.receive(completion: c)
            return
        }
        let conduit = _SubjectConduit(self, AnySubscriber(subscriber))
        conduits.append(conduit)
        lock.unlock()
        subscriber.receive(subscription: conduit)
    }

    func demanded(_ c: _SubjectConduit<Output, Failure>) {}

    func remove(_ c: _SubjectConduit<Output, Failure>) {
        lock.lock()
        conduits.removeAll { $0 === c }
        lock.unlock()
    }

    func broadcast(_ v: Output) {
        lock.lock()
        let all = conduits
        lock.unlock()
        for c in all { _ = c.offer(v) }
    }

    public func send(completion c: Subscribers.Completion<Failure>) {
        lock.lock()
        guard completion == nil else { lock.unlock(); return }
        completion = c
        let all = conduits
        conduits = []
        lock.unlock()
        for x in all { x.finish(c) }
    }

    public func send(subscription: Subscription) {
        lock.lock()
        upstream.append(subscription)
        lock.unlock()
        subscription.request(.unlimited)
    }
}

/// A subject that passes on what is sent while subscribers are there.
public final class PassthroughSubject<Output, Failure: Error>: _SubjectBase<Output, Failure>, Subject {
    public override init() {}

    public func send(_ value: Output) { broadcast(value) }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        attach(subscriber)
    }
}

/// A subject that holds a value, sends it to each new subscriber, and
/// sends each new one.
public final class CurrentValueSubject<Output, Failure: Error>: _SubjectBase<Output, Failure>, Subject {
    private var current: Output

    public init(_ value: Output) { current = value }

    public var value: Output {
        get {
            lock.lock()
            defer { lock.unlock() }
            return current
        }
        set { send(newValue) }
    }

    public func send(_ value: Output) {
        lock.lock()
        current = value
        lock.unlock()
        broadcast(value)
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        attach(subscriber)
    }

    // a subscriber's first demand gets the value held
    private var greeted = Set<ObjectIdentifier>()
    override func demanded(_ c: _SubjectConduit<Output, Failure>) {
        lock.lock()
        let first = greeted.insert(ObjectIdentifier(c)).inserted
        let v = current
        lock.unlock()
        if first { _ = c.offer(v) }
    }

    override func remove(_ c: _SubjectConduit<Output, Failure>) {
        lock.lock()
        greeted.remove(ObjectIdentifier(c))
        lock.unlock()
        super.remove(c)
    }
}

// ---- type erasure ----------------------------------------------------------------------

/// Any subscriber of an input and failure.
public struct AnySubscriber<Input, Failure: Error>: Subscriber, CustomStringConvertible {
    public let combineIdentifier: CombineIdentifier
    private let onSubscription: (Subscription) -> Void
    private let onInput: (Input) -> Subscribers.Demand
    private let onCompletion: (Subscribers.Completion<Failure>) -> Void

    public init<S: Subscriber>(_ s: S) where S.Input == Input, S.Failure == Failure {
        if let any = s as? AnySubscriber<Input, Failure> {
            self = any
            return
        }
        combineIdentifier = s.combineIdentifier
        onSubscription = s.receive(subscription:)
        onInput = s.receive(_:)
        onCompletion = s.receive(completion:)
    }

    public init(receiveSubscription: ((Subscription) -> Void)? = nil,
                receiveValue: ((Input) -> Subscribers.Demand)? = nil,
                receiveCompletion: ((Subscribers.Completion<Failure>) -> Void)? = nil) {
        combineIdentifier = CombineIdentifier()
        onSubscription = receiveSubscription ?? { _ in }
        onInput = receiveValue ?? { _ in .none }
        onCompletion = receiveCompletion ?? { _ in }
    }

    public var description: String { "Anonymous AnySubscriber" }
    public func receive(subscription: Subscription) { onSubscription(subscription) }
    public func receive(_ value: Input) -> Subscribers.Demand { onInput(value) }
    public func receive(completion: Subscribers.Completion<Failure>) { onCompletion(completion) }
}

/// Any publisher of an output and failure.
public struct AnyPublisher<Output, Failure: Error>: Publisher, CustomStringConvertible {
    private let subscribe: (AnySubscriber<Output, Failure>) -> Void

    public init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
        if let any = publisher as? AnyPublisher<Output, Failure> {
            self = any
            return
        }
        subscribe = { publisher.receive(subscriber: $0) }
    }

    public var description: String { "AnyPublisher" }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        subscribe(AnySubscriber(subscriber))
    }
}

extension Publisher {
    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher(self) }
}

// ---- the subscribers that end a chain --------------------------------------------------

extension Subscribers {
    /// Calls closures with each value and with the completion; asks for all.
    public final class Sink<Input, Failure: Error>: Subscriber, Cancellable, CustomStringConvertible {
        public let receiveValue: (Input) -> Void
        public let receiveCompletion: (Subscribers.Completion<Failure>) -> Void
        private var subscription: Subscription?
        private let lock = NSLock()

        public init(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                    receiveValue: @escaping (Input) -> Void) {
            self.receiveCompletion = receiveCompletion
            self.receiveValue = receiveValue
        }

        public var description: String { "Sink" }

        public func receive(subscription s: Subscription) {
            lock.lock()
            guard subscription == nil else { lock.unlock(); s.cancel(); return }
            subscription = s
            lock.unlock()
            s.request(.unlimited)
        }

        public func receive(_ value: Input) -> Subscribers.Demand {
            receiveValue(value)
            return .none
        }

        public func receive(completion: Subscribers.Completion<Failure>) {
            receiveCompletion(completion)
            lock.lock()
            subscription = nil
            lock.unlock()
        }

        public func cancel() {
            lock.lock()
            let s = subscription
            subscription = nil
            lock.unlock()
            s?.cancel()
        }
    }

    /// Writes each value to a property of an object.
    public final class Assign<Root, Input>: Subscriber, Cancellable, CustomStringConvertible {
        public typealias Failure = Never
        public private(set) var object: Root?
        public let keyPath: ReferenceWritableKeyPath<Root, Input>
        private var subscription: Subscription?

        public init(object: Root, keyPath: ReferenceWritableKeyPath<Root, Input>) {
            self.object = object
            self.keyPath = keyPath
        }

        public var description: String { "Assign" }

        public func receive(subscription s: Subscription) {
            guard subscription == nil else { s.cancel(); return }
            subscription = s
            s.request(.unlimited)
        }

        public func receive(_ value: Input) -> Subscribers.Demand {
            object?[keyPath: keyPath] = value
            return .none
        }

        public func receive(completion: Subscribers.Completion<Never>) {
            object = nil
            subscription = nil
        }

        public func cancel() {
            subscription?.cancel()
            subscription = nil
            object = nil
        }
    }
}

extension Publisher {
    public func sink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                     receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        let s = Subscribers.Sink<Output, Failure>(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
        subscribe(s)
        return AnyCancellable(s)
    }
}

extension Publisher where Failure == Never {
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        sink(receiveCompletion: { _ in }, receiveValue: receiveValue)
    }

    public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Output>, on object: Root) -> AnyCancellable {
        let s = Subscribers.Assign(object: object, keyPath: keyPath)
        subscribe(s)
        return AnyCancellable(s)
    }
}
