// SPDX-License-Identifier: GPL-3.0-or-later
//
// Combine's schedulers (freemac 1.230): where and when values are
// delivered. DispatchQueue, RunLoop, OperationQueue and ImmediateScheduler
// are schedulers, and receive(on:), debounce, delay and Timer's publisher
// use them. Written for Ferry from Apple's documentation.

import Foundation

/// Somewhere work can be run, now or later.
public protocol Scheduler {
    associatedtype SchedulerTimeType: Strideable where SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
    associatedtype SchedulerOptions
    var now: SchedulerTimeType { get }
    var minimumTolerance: SchedulerTimeType.Stride { get }
    func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                  _ action: @escaping () -> Void)
}

extension Scheduler {
    public func schedule(_ action: @escaping () -> Void) { schedule(options: nil, action) }
    public func schedule(after date: SchedulerTimeType, _ action: @escaping () -> Void) {
        schedule(after: date, tolerance: minimumTolerance, options: nil, action)
    }
}

/// A length of time a scheduler understands.
public protocol SchedulerTimeIntervalConvertible {
    static func seconds(_ s: Int) -> Self
    static func seconds(_ s: Double) -> Self
    static func milliseconds(_ ms: Int) -> Self
    static func microseconds(_ us: Int) -> Self
    static func nanoseconds(_ ns: Int) -> Self
}

// ---- DispatchQueue ---------------------------------------------------------------------

extension DispatchQueue: Scheduler {
    public struct SchedulerTimeType: Strideable, Hashable, Sendable {
        public var dispatchTime: DispatchTime
        public init(_ time: DispatchTime) { dispatchTime = time }

        public func distance(to other: SchedulerTimeType) -> Stride {
            Stride(.nanoseconds(Int(Int64(bitPattern: other.dispatchTime.uptimeNanoseconds &- dispatchTime.uptimeNanoseconds))))
        }
        public func advanced(by n: Stride) -> SchedulerTimeType { SchedulerTimeType(dispatchTime + .nanoseconds(n.magnitude)) }

        public static func == (a: SchedulerTimeType, b: SchedulerTimeType) -> Bool { a.dispatchTime == b.dispatchTime }
        public func hash(into h: inout Hasher) { h.combine(dispatchTime.rawValue) }

        public struct Stride: SchedulerTimeIntervalConvertible, Comparable, SignedNumeric, ExpressibleByFloatLiteral, Hashable, Sendable {
            /// In nanoseconds.
            public var magnitude: Int
            public init(_ interval: DispatchTimeInterval) {
                switch interval {
                case .seconds(let s): magnitude = s * 1_000_000_000
                case .milliseconds(let ms): magnitude = ms * 1_000_000
                case .microseconds(let us): magnitude = us * 1000
                case .nanoseconds(let ns): magnitude = ns
                case .never: magnitude = .max
                @unknown default: magnitude = .max
                }
            }
            public init(floatLiteral value: Double) { magnitude = Int(value * 1e9) }
            public init(integerLiteral value: Int) { magnitude = value * 1_000_000_000 }
            public init?<T: BinaryInteger>(exactly source: T) {
                guard let v = Int(exactly: source) else { return nil }
                magnitude = v * 1_000_000_000
            }
            public var timeInterval: DispatchTimeInterval { .nanoseconds(magnitude) }

            public static func seconds(_ s: Int) -> Stride { Stride(.seconds(s)) }
            public static func seconds(_ s: Double) -> Stride { Stride(floatLiteral: s) }
            public static func milliseconds(_ ms: Int) -> Stride { Stride(.milliseconds(ms)) }
            public static func microseconds(_ us: Int) -> Stride { Stride(.microseconds(us)) }
            public static func nanoseconds(_ ns: Int) -> Stride { Stride(.nanoseconds(ns)) }

            public static func < (a: Stride, b: Stride) -> Bool { a.magnitude < b.magnitude }
            public static func + (a: Stride, b: Stride) -> Stride { .nanoseconds(a.magnitude + b.magnitude) }
            public static func - (a: Stride, b: Stride) -> Stride { .nanoseconds(a.magnitude - b.magnitude) }
            public static func * (a: Stride, b: Stride) -> Stride { .nanoseconds(a.magnitude * b.magnitude / 1_000_000_000) }
            public static func += (a: inout Stride, b: Stride) { a = a + b }
            public static func -= (a: inout Stride, b: Stride) { a = a - b }
            public static func *= (a: inout Stride, b: Stride) { a = a * b }
        }
    }

    public struct SchedulerOptions {
        public var qos: DispatchQoS = .unspecified
        public var flags: DispatchWorkItemFlags = []
        public var group: DispatchGroup?
        public init(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], group: DispatchGroup? = nil) {
            self.qos = qos
            self.flags = flags
            self.group = group
        }
    }

    public var now: SchedulerTimeType { SchedulerTimeType(.now()) }
    public var minimumTolerance: SchedulerTimeType.Stride { .nanoseconds(0) }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        async(group: options?.group, flags: options?.flags ?? [], execute: action)
    }

    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        asyncAfter(deadline: date.dispatchTime, execute: action)
    }
}

// ---- RunLoop and OperationQueue --------------------------------------------------------

/// The time a run loop or operation queue schedules by: a date.
public struct _DateSchedulerTime: Strideable, Hashable, Sendable {
    public var date: Date
    public init(_ date: Date) { self.date = date }
    public func distance(to other: _DateSchedulerTime) -> Stride { Stride(other.date.timeIntervalSince(date)) }
    public func advanced(by n: Stride) -> _DateSchedulerTime { _DateSchedulerTime(date + n.timeInterval) }

    public struct Stride: SchedulerTimeIntervalConvertible, Comparable, SignedNumeric, ExpressibleByFloatLiteral, Hashable, Sendable {
        public var magnitude: TimeInterval
        public var timeInterval: TimeInterval { magnitude }
        public init(_ t: TimeInterval) { magnitude = t }
        public init(floatLiteral value: Double) { magnitude = value }
        public init(integerLiteral value: Int) { magnitude = Double(value) }
        public init?<T: BinaryInteger>(exactly source: T) {
            guard let v = Double(exactly: source) else { return nil }
            magnitude = v
        }
        public static func seconds(_ s: Int) -> Stride { Stride(Double(s)) }
        public static func seconds(_ s: Double) -> Stride { Stride(s) }
        public static func milliseconds(_ ms: Int) -> Stride { Stride(Double(ms) / 1e3) }
        public static func microseconds(_ us: Int) -> Stride { Stride(Double(us) / 1e6) }
        public static func nanoseconds(_ ns: Int) -> Stride { Stride(Double(ns) / 1e9) }
        public static func < (a: Stride, b: Stride) -> Bool { a.magnitude < b.magnitude }
        public static func + (a: Stride, b: Stride) -> Stride { Stride(a.magnitude + b.magnitude) }
        public static func - (a: Stride, b: Stride) -> Stride { Stride(a.magnitude - b.magnitude) }
        public static func * (a: Stride, b: Stride) -> Stride { Stride(a.magnitude * b.magnitude) }
        public static func += (a: inout Stride, b: Stride) { a = a + b }
        public static func -= (a: inout Stride, b: Stride) { a = a - b }
        public static func *= (a: inout Stride, b: Stride) { a = a * b }
    }
}

/// A block a timer runs once.
final class _TimerTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ t: NSTimer) { action() }
}

extension NSRunLoop: Scheduler {
    public typealias SchedulerTimeType = _DateSchedulerTime
    public struct SchedulerOptions {}

    public var now: SchedulerTimeType { _DateSchedulerTime(Date()) }
    public var minimumTolerance: SchedulerTimeType.Stride { 0 }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        schedule(after: now, tolerance: minimumTolerance, options: options, action)
    }

    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        let target = _TimerTarget(action)
        let t = NSTimer(fire: date.date, interval: 0, target: target, selector: #selector(_TimerTarget.fire(_:)),
                        userInfo: nil, repeats: false)
        add(t, forMode: .common)
    }
}

extension NSOperationQueue: Scheduler {
    public typealias SchedulerTimeType = _DateSchedulerTime
    public struct SchedulerOptions {}

    public var now: SchedulerTimeType { _DateSchedulerTime(Date()) }
    public var minimumTolerance: SchedulerTimeType.Stride { 0 }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) { addOperation(action) }

    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        let wait = Swift.max(0, date.date.timeIntervalSinceNow)
        DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [weak self] in self?.addOperation(action) }
    }
}

/// Runs work at once, where it is asked for.
public struct ImmediateScheduler: Scheduler {
    public struct SchedulerTimeType: Strideable, Hashable, Sendable {
        public func distance(to other: SchedulerTimeType) -> Stride { 0 }
        public func advanced(by n: Stride) -> SchedulerTimeType { self }
        public typealias Stride = _DateSchedulerTime.Stride
    }
    public typealias SchedulerOptions = Never
    public static let shared = ImmediateScheduler()
    public var now: SchedulerTimeType { SchedulerTimeType() }
    public var minimumTolerance: SchedulerTimeType.Stride { 0 }
    public func schedule(options: Never?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: Never?,
                         _ action: @escaping () -> Void) { action() }
}

// ---- operators with schedulers ---------------------------------------------------------

extension Publishers {
    /// Delivers values and the completion on a scheduler.
    public struct ReceiveOn<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let scheduler: Context
        public let options: Context.SchedulerOptions?

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let sch = scheduler, opts = options
            upstream.subscribe(AnySubscriber<Output, Failure>(
                receiveSubscription: { subscriber.receive(subscription: $0) },
                receiveValue: { v in
                    sch.schedule(options: opts) { _ = subscriber.receive(v) }
                    return .none
                },
                receiveCompletion: { c in sch.schedule(options: opts) { subscriber.receive(completion: c) } }))
        }
    }

    /// Delivers values on a scheduler, after a while.
    public struct Delay<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let interval: Context.SchedulerTimeType.Stride
        public let scheduler: Context

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let sch = scheduler, wait = interval
            upstream.subscribe(AnySubscriber<Output, Failure>(
                receiveSubscription: { subscriber.receive(subscription: $0) },
                receiveValue: { v in
                    sch.schedule(after: sch.now.advanced(by: wait)) { _ = subscriber.receive(v) }
                    return .none
                },
                receiveCompletion: { c in sch.schedule(after: sch.now.advanced(by: wait)) { subscriber.receive(completion: c) } }))
        }
    }

    /// Passes a value on only once no newer one has come for a while.
    public struct Debounce<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let dueTime: Context.SchedulerTimeType.Stride
        public let scheduler: Context

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let sch = scheduler, wait = dueTime
            let generation = _Box(0)
            upstream.subscribe(AnySubscriber<Output, Failure>(
                receiveSubscription: { subscriber.receive(subscription: $0) },
                receiveValue: { v in
                    generation.value += 1
                    let mine = generation.value
                    sch.schedule(after: sch.now.advanced(by: wait)) {
                        if generation.value == mine { _ = subscriber.receive(v) }
                    }
                    return .none
                },
                receiveCompletion: { c in sch.schedule { subscriber.receive(completion: c) } }))
        }
    }
}

extension Publisher {
    public func receive<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.ReceiveOn<Self, S> {
        Publishers.ReceiveOn(upstream: self, scheduler: scheduler, options: options)
    }
    public func delay<S: Scheduler>(for interval: S.SchedulerTimeType.Stride, scheduler: S) -> Publishers.Delay<Self, S> {
        Publishers.Delay(upstream: self, interval: interval, scheduler: scheduler)
    }
    public func debounce<S: Scheduler>(for dueTime: S.SchedulerTimeType.Stride, scheduler: S) -> Publishers.Debounce<Self, S> {
        Publishers.Debounce(upstream: self, dueTime: dueTime, scheduler: scheduler)
    }
}
