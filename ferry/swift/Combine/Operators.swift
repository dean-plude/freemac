// SPDX-License-Identifier: GPL-3.0-or-later
//
// Combine's simple publishers (Just, Empty, Fail, Future, Deferred) and its
// common operators (freemac 1.230). Most operators hand the upstream
// subscription to their subscriber as it is and change only the values on
// the way, asking for one more when they drop one. Written for Ferry.

import Foundation

// ---- simple publishers -----------------------------------------------------------------

/// Sends one value, then finishes.
public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public let output: Output
    public init(_ output: Output) { self.output = output }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
        subscriber.receive(subscription: _OneShot(subscriber, output))
    }
}

private final class _OneShot<S: Subscriber>: Subscription {
    var subscriber: S?
    let value: S.Input
    init(_ s: S, _ v: S.Input) { subscriber = s; value = v }
    func request(_ demand: Subscribers.Demand) {
        guard demand > 0, let s = subscriber else { return }
        subscriber = nil
        _ = s.receive(value)
        s.receive(completion: .finished)
    }
    func cancel() { subscriber = nil }
}

/// Sends nothing; finishes at once unless told not to.
public struct Empty<Output, Failure: Error>: Publisher {
    public let completeImmediately: Bool
    public init(completeImmediately: Bool = true) { self.completeImmediately = completeImmediately }
    public init(completeImmediately: Bool = true, outputType: Output.Type, failureType: Failure.Type) {
        self.completeImmediately = completeImmediately
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        subscriber.receive(subscription: Subscriptions.empty)
        if completeImmediately { subscriber.receive(completion: .finished) }
    }
}

/// Fails at once with an error.
public struct Fail<Output, Failure: Error>: Publisher {
    public let error: Failure
    public init(error: Failure) { self.error = error }
    public init(outputType: Output.Type, failure: Failure) { error = failure }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        subscriber.receive(subscription: Subscriptions.empty)
        subscriber.receive(completion: .failure(error))
    }
}


extension Publishers {
    /// Sends each element of a sequence, as far as asked, then finishes.
    public struct Sequence<Elements: Swift.Sequence, Failure: Error>: Publisher {
        public typealias Output = Elements.Element
        public let sequence: Elements
        public init(sequence: Elements) { self.sequence = sequence }

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            subscriber.receive(subscription: _Elements(subscriber, sequence.makeIterator()))
        }
    }
}

private final class _Elements<S: Subscriber, I: IteratorProtocol>: Subscription where I.Element == S.Input {
    var subscriber: S?
    var iterator: I
    var pending = Subscribers.Demand.none
    var busy = false
    init(_ s: S, _ i: I) { subscriber = s; iterator = i }
    func request(_ demand: Subscribers.Demand) {
        pending += demand
        guard !busy else { return }
        busy = true
        defer { busy = false }
        while pending > 0, let s = subscriber {
            guard let v = iterator.next() else {
                subscriber = nil
                s.receive(completion: .finished)
                return
            }
            pending -= 1
            pending += s.receive(v)
        }
    }
    func cancel() { subscriber = nil }
}

extension Sequence {
    public var publisher: Publishers.Sequence<Self, Never> { Publishers.Sequence(sequence: self) }
}

/// Makes its publisher only when subscribed to.
public struct Deferred<DeferredPublisher: Publisher>: Publisher {
    public typealias Output = DeferredPublisher.Output
    public typealias Failure = DeferredPublisher.Failure
    public let createPublisher: () -> DeferredPublisher
    public init(createPublisher: @escaping () -> DeferredPublisher) { self.createPublisher = createPublisher }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        createPublisher().receive(subscriber: subscriber)
    }
}

/// Runs its work once, and sends the one result it promises.
public final class Future<Output, Failure: Error>: Publisher {
    public typealias Promise = (Result<Output, Failure>) -> Void
    private let subject = PassthroughSubject<Output, Failure>()
    private var result: Result<Output, Failure>?
    private let lock = NSRecursiveLock()

    public init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void) {
        attemptToFulfill { [self] r in
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = r
            lock.unlock()
            switch r {
            case .success(let v):
                subject.send(v)
                subject.send(completion: .finished)
            case .failure(let e):
                subject.send(completion: .failure(e))
            }
        }
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        lock.lock()
        let r = result
        lock.unlock()
        switch r {
        case .success(let v)?: Just(v).setFailureType(to: Failure.self).receive(subscriber: subscriber)
        case .failure(let e)?: Fail(error: e).receive(subscriber: subscriber)
        case nil: subject.receive(subscriber: subscriber)
        }
    }
}

// ---- operators that change values on the way -------------------------------------------

/// A subscriber that hands values through a closure: the closure answers
/// the value to pass on, or nil to drop it.
struct _Through<Downstream: Subscriber, Input, Failure: Error>: Subscriber where Downstream.Failure == Failure {
    let downstream: Downstream
    let transform: (Input) -> Downstream.Input?
    let combineIdentifier = CombineIdentifier()

    func receive(subscription: Subscription) { downstream.receive(subscription: subscription) }
    func receive(_ input: Input) -> Subscribers.Demand {
        guard let out = transform(input) else { return .max(1) }
        return downstream.receive(out)
    }
    func receive(completion: Subscribers.Completion<Failure>) { downstream.receive(completion: completion) }
}

extension Publishers {
    public struct Map<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let transform: (Upstream.Output) -> Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let t = transform
            upstream.subscribe(_Through<S, Upstream.Output, Failure>(downstream: subscriber, transform: { t($0) }))
        }
    }

    public struct CompactMap<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let transform: (Upstream.Output) -> Output?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream.subscribe(_Through<S, Upstream.Output, Failure>(downstream: subscriber, transform: transform))
        }
    }

    public struct Filter<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let isIncluded: (Upstream.Output) -> Bool
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let f = isIncluded
            upstream.subscribe(_Through<S, Output, Failure>(downstream: subscriber, transform: { f($0) ? $0 : nil }))
        }
    }

    public struct RemoveDuplicates<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let predicate: (Output, Output) -> Bool
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let last = _Box<Output?>(nil)
            let same = predicate
            upstream.subscribe(_Through<S, Output, Failure>(downstream: subscriber, transform: { v in
                if let l = last.value, same(l, v) { return nil }
                last.value = v
                return v
            }))
        }
    }

    public struct Drop<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let count: Int
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let left = _Box(count)
            upstream.subscribe(_Through<S, Output, Failure>(downstream: subscriber, transform: { v in
                if left.value > 0 { left.value -= 1; return nil }
                return v
            }))
        }
    }

    public struct HandleEvents<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        let onOutput: ((Output) -> Void)?
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let f = onOutput
            upstream.subscribe(_Through<S, Output, Failure>(downstream: subscriber, transform: { f?($0); return $0 }))
        }
    }

    public struct SetFailureType<Upstream: Publisher, Failure: Error>: Publisher where Upstream.Failure == Never {
        public typealias Output = Upstream.Output
        public let upstream: Upstream
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            upstream.subscribe(AnySubscriber<Output, Never>(
                receiveSubscription: { subscriber.receive(subscription: $0) },
                receiveValue: { subscriber.receive($0) },
                receiveCompletion: { _ in subscriber.receive(completion: .finished) }))
        }
    }

    public struct ReplaceError<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Never
        public let upstream: Upstream
        public let output: Output
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
            let out = output
            upstream.subscribe(AnySubscriber<Output, Upstream.Failure>(
                receiveSubscription: { subscriber.receive(subscription: $0) },
                receiveValue: { subscriber.receive($0) },
                receiveCompletion: { c in
                    if case .failure = c { _ = subscriber.receive(out) }
                    subscriber.receive(completion: .finished)
                }))
        }
    }

    public struct MapError<Upstream: Publisher, Failure: Error>: Publisher {
        public typealias Output = Upstream.Output
        public let upstream: Upstream
        public let transform: (Upstream.Failure) -> Failure
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let t = transform
            upstream.subscribe(AnySubscriber<Output, Upstream.Failure>(
                receiveSubscription: { subscriber.receive(subscription: $0) },
                receiveValue: { subscriber.receive($0) },
                receiveCompletion: { c in
                    switch c {
                    case .finished: subscriber.receive(completion: .finished)
                    case .failure(let e): subscriber.receive(completion: .failure(t(e)))
                    }
                }))
        }
    }

    /// The values of two publishers, as they come.
    public struct Merge<A: Publisher, B: Publisher>: Publisher where A.Output == B.Output, A.Failure == B.Failure {
        public typealias Output = A.Output
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let subject = PassthroughSubject<Output, Failure>()
            subject.receive(subscriber: subscriber)
            let left = _Box(2)
            let done: (Subscribers.Completion<Failure>) -> Void = { c in
                left.value -= 1
                if case .failure = c { subject.send(completion: c) } else if left.value == 0 { subject.send(completion: .finished) }
            }
            let keep = _Box<[AnyCancellable]>([])
            keep.value.append(a.sink(receiveCompletion: done, receiveValue: { subject.send($0) }))
            keep.value.append(b.sink(receiveCompletion: done, receiveValue: { subject.send($0) }))
            _CombineKeeper.keep(keep, as: subject)
        }
    }

    /// The latest values of two publishers, once each has sent one.
    public struct CombineLatest<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure {
        public typealias Output = (A.Output, B.Output)
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let subject = PassthroughSubject<Output, Failure>()
            subject.receive(subscriber: subscriber)
            let la = _Box<A.Output?>(nil), lb = _Box<B.Output?>(nil)
            let keep = _Box<[AnyCancellable]>([])
            keep.value.append(a.sink(receiveCompletion: { if case .failure = $0 { subject.send(completion: $0) } },
                                     receiveValue: { v in la.value = v; if let w = lb.value { subject.send((v, w)) } }))
            keep.value.append(b.sink(receiveCompletion: { if case .failure = $0 { subject.send(completion: $0) } },
                                     receiveValue: { w in lb.value = w; if let v = la.value { subject.send((v, w)) } }))
            _CombineKeeper.keep(keep, as: subject)
        }
    }
}

/// Keeps a combined publisher's own subscriptions for as long as its subject lives.
enum _CombineKeeper {
    nonisolated(unsafe) static var kept: [ObjectIdentifier: AnyObject] = [:]
    static func keep(_ o: AnyObject, as owner: AnyObject) { kept[ObjectIdentifier(owner)] = o }
}

final class _Box<T> {
    var value: T
    init(_ v: T) { value = v }
}

extension Publisher {
    public func map<T>(_ transform: @escaping (Output) -> T) -> Publishers.Map<Self, T> {
        Publishers.Map(upstream: self, transform: transform)
    }
    public func map<T>(_ keyPath: KeyPath<Output, T>) -> Publishers.Map<Self, T> {
        Publishers.Map(upstream: self, transform: { $0[keyPath: keyPath] })
    }
    public func compactMap<T>(_ transform: @escaping (Output) -> T?) -> Publishers.CompactMap<Self, T> {
        Publishers.CompactMap(upstream: self, transform: transform)
    }
    public func filter(_ isIncluded: @escaping (Output) -> Bool) -> Publishers.Filter<Self> {
        Publishers.Filter(upstream: self, isIncluded: isIncluded)
    }
    public func removeDuplicates(by predicate: @escaping (Output, Output) -> Bool) -> Publishers.RemoveDuplicates<Self> {
        Publishers.RemoveDuplicates(upstream: self, predicate: predicate)
    }
    public func dropFirst(_ count: Int = 1) -> Publishers.Drop<Self> { Publishers.Drop(upstream: self, count: count) }
    public func handleEvents(receiveOutput: ((Output) -> Void)? = nil) -> Publishers.HandleEvents<Self> {
        Publishers.HandleEvents(upstream: self, onOutput: receiveOutput)
    }
    public func replaceError(with output: Output) -> Publishers.ReplaceError<Self> {
        Publishers.ReplaceError(upstream: self, output: output)
    }
    public func mapError<E: Error>(_ transform: @escaping (Failure) -> E) -> Publishers.MapError<Self, E> {
        Publishers.MapError(upstream: self, transform: transform)
    }
    public func merge<P: Publisher>(with other: P) -> Publishers.Merge<Self, P> where P.Output == Output, P.Failure == Failure {
        Publishers.Merge(a: self, b: other)
    }
    public func combineLatest<P: Publisher>(_ other: P) -> Publishers.CombineLatest<Self, P> where P.Failure == Failure {
        Publishers.CombineLatest(a: self, b: other)
    }
}

extension Publisher where Output: Equatable {
    public func removeDuplicates() -> Publishers.RemoveDuplicates<Self> { removeDuplicates(by: ==) }
}

extension Publisher where Failure == Never {
    public func setFailureType<E: Error>(to failureType: E.Type) -> Publishers.SetFailureType<Self, E> {
        Publishers.SetFailureType(upstream: self)
    }
}
