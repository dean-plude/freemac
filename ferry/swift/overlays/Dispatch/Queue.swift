// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for Dispatch (freemac 1.230): queues, work items,
// groups and semaphores, with the names and shapes Apple's Dispatch
// documentation gives them. Written for Ferry. Each Swift object holds the
// dispatch object of Ferry's libdispatch it stands for; handed to
// Objective-C (as an "id"), it becomes that object again.

import Darwin

/// What queues, groups, semaphores and sources have in common.
open class DispatchObject {
    /// The libdispatch object, an Objective-C object in Ferry.
    public let __object: NSObject

    init(_ object: NSObject) { __object = object }

    public func suspend() { dispatch_suspend(__object) }
    public func resume() { dispatch_resume(__object) }
    public func activate() { dispatch_activate(__object) }

    public func setTarget(queue: DispatchQueue?) {
        dispatch_set_target_queue(__object, queue?.__object)
    }
}

/// Handed to Objective-C as an "id", a queue, group, semaphore or source
/// becomes the libdispatch object again, and an object from Objective-C
/// can be taken as one.
public protocol _DispatchBridged: DispatchObject, _ObjectiveCBridgeable where _ObjectiveCType == NSObject {
    init(__wrapping object: NSObject)
}

extension _DispatchBridged {
    public func _bridgeToObjectiveC() -> NSObject { __object }
    public static func _forceBridgeFromObjectiveC(_ x: NSObject, result: inout Self?) {
        result = Self(__wrapping: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSObject, result: inout Self?) -> Bool {
        result = Self(__wrapping: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ x: NSObject?) -> Self { Self(__wrapping: x!) }
}

/// Quality of service: how urgent work is. Ferry runs every class of work
/// on the same pool of threads; the class is kept for those who ask.
public struct DispatchQoS: Equatable, Sendable {
    public let qosClass: QoSClass
    public let relativePriority: Int

    public enum QoSClass: Sendable {
        case background, utility, `default`, userInitiated, userInteractive, unspecified

        public var rawValue: qos_class_t {
            switch self {
            case .background: return qos_class_t(0x09)
            case .utility: return qos_class_t(0x11)
            case .default: return qos_class_t(0x15)
            case .userInitiated: return qos_class_t(0x19)
            case .userInteractive: return qos_class_t(0x21)
            case .unspecified: return qos_class_t(0)
            }
        }

        public init?(rawValue: qos_class_t) {
            switch rawValue {
            case 0x09: self = .background
            case 0x11: self = .utility
            case 0x15: self = .default
            case 0x19: self = .userInitiated
            case 0x21: self = .userInteractive
            case 0: self = .unspecified
            default: return nil
            }
        }
    }

    public init(qosClass: QoSClass, relativePriority: Int) {
        self.qosClass = qosClass
        self.relativePriority = relativePriority
    }

    public static let background = DispatchQoS(qosClass: .background, relativePriority: 0)
    public static let utility = DispatchQoS(qosClass: .utility, relativePriority: 0)
    public static let `default` = DispatchQoS(qosClass: .default, relativePriority: 0)
    public static let userInitiated = DispatchQoS(qosClass: .userInitiated, relativePriority: 0)
    public static let userInteractive = DispatchQoS(qosClass: .userInteractive, relativePriority: 0)
    public static let unspecified = DispatchQoS(qosClass: .unspecified, relativePriority: 0)
}

public typealias qos_class_t = UInt32

/// Options for a work item.
public struct DispatchWorkItemFlags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let barrier = DispatchWorkItemFlags(rawValue: 0x1)
    public static let detached = DispatchWorkItemFlags(rawValue: 0x2)
    public static let assignCurrentContext = DispatchWorkItemFlags(rawValue: 0x4)
    public static let noQoS = DispatchWorkItemFlags(rawValue: 0x8)
    public static let inheritQoS = DispatchWorkItemFlags(rawValue: 0x10)
    public static let enforceQoS = DispatchWorkItemFlags(rawValue: 0x20)
}

/// Work to do, which can be run, waited for, told about or cancelled.
public final class DispatchWorkItem {
    let work: () -> Void
    let flags: DispatchWorkItemFlags
    private let done = dispatch_group_create()!
    private var notified: [(DispatchQueue, () -> Void)] = []
    private var lock = pthread_mutex_t()
    private var started = false
    public private(set) var isCancelled = false

    public init(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], block: @escaping () -> Void) {
        work = block
        self.flags = flags
        pthread_mutex_init(&lock, nil)
        dispatch_group_enter(done)
    }

    deinit {
        if !started { dispatch_group_leave(done) }
        pthread_mutex_destroy(&lock)
    }

    /// Runs the work now, on this thread, unless it was cancelled.
    public func perform() {
        pthread_mutex_lock(&lock)
        let first = !started
        started = true
        let cancelled = isCancelled
        pthread_mutex_unlock(&lock)
        if !cancelled { work() }
        if first { finish() }
    }

    private func finish() {
        dispatch_group_leave(done)
    }

    public func wait() { _ = dispatch_group_wait(done, ~0) }

    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        dispatch_group_wait(done, timeout.rawValue) == 0 ? .success : .timedOut
    }

    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
        dispatch_group_wait(done, wallTimeout.rawValue) == 0 ? .success : .timedOut
    }

    public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue,
                       execute: @escaping () -> Void) {
        dispatch_group_notify(done, queue.__object, execute)
    }

    public func notify(queue: DispatchQueue, execute: DispatchWorkItem) {
        dispatch_group_notify(done, queue.__object) { execute.perform() }
    }

    /// Keeps the work from running, if it hasn't started.
    public func cancel() {
        pthread_mutex_lock(&lock)
        isCancelled = true
        pthread_mutex_unlock(&lock)
    }
}

/// A queue of work, run in order (serial) or side by side (concurrent).
public final class DispatchQueue: DispatchObject, _DispatchBridged, @unchecked Sendable {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        public static let concurrent = Attributes(rawValue: 1 << 1)
        public static let initiallyInactive = Attributes(rawValue: 1 << 2)
    }

    public enum AutoreleaseFrequency: Sendable {
        case inherit, workItem, never
    }

    public enum GlobalQueuePriority: Sendable {
        case high, `default`, low, background
    }

    public init(__wrapping object: NSObject) { super.init(object) }
    init(__queue object: NSObject) { super.init(object) }

    public convenience init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [],
                            autoreleaseFrequency: AutoreleaseFrequency = .inherit, target: DispatchQueue? = nil) {
        var attr: UnsafeMutableRawPointer? = attributes.contains(.concurrent) ? _ferry_dispatch_queue_concurrent() : nil
        if attributes.contains(.initiallyInactive) { attr = dispatch_queue_attr_make_initially_inactive(attr) }
        let q: NSObject
        if let target {
            q = dispatch_queue_create_with_target(label, attr, target.__object)
        } else {
            q = dispatch_queue_create(label, attr)
        }
        self.init(__queue: q)
    }

    /// The queue whose work runs on the main thread, in its run loop.
    public static var main: DispatchQueue { _main }
    private static let _main = DispatchQueue(__queue: _ferry_dispatch_main_queue())

    private static let globals: [DispatchQueue] = [0x21, 0x19, 0x15, 0x11, 0x09].map {
        DispatchQueue(__queue: dispatch_get_global_queue($0, 0))
    }

    /// One of the concurrent queues every program has.
    public static func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue {
        switch qos {
        case .userInteractive: return globals[0]
        case .userInitiated: return globals[1]
        case .default, .unspecified: return globals[2]
        case .utility: return globals[3]
        case .background: return globals[4]
        }
    }

    public static func global(priority: GlobalQueuePriority) -> DispatchQueue {
        switch priority {
        case .high: return global(qos: .userInitiated)
        case .default: return global(qos: .default)
        case .low: return global(qos: .utility)
        case .background: return global(qos: .background)
        }
    }

    public var label: String {
        guard let p = dispatch_queue_get_label(__object) else { return "" }
        return String(cString: p)
    }

    public var qos: DispatchQoS { .unspecified }

    // ---- adding work

    public func async(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                      execute work: @escaping () -> Void) {
        if let group {
            dispatch_group_async(group.__object, __object, work)
        } else if flags.contains(.barrier) {
            dispatch_barrier_async(__object, work)
        } else {
            dispatch_async(__object, work)
        }
    }

    public func async(execute item: DispatchWorkItem) {
        if item.flags.contains(.barrier) {
            dispatch_barrier_async(__object) { item.perform() }
        } else {
            dispatch_async(__object) { item.perform() }
        }
    }

    public func async(group: DispatchGroup, execute item: DispatchWorkItem) {
        dispatch_group_async(group.__object, __object) { item.perform() }
    }

    public func asyncAfter(deadline: DispatchTime, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                           execute work: @escaping () -> Void) {
        dispatch_after(deadline.rawValue, __object, work)
    }

    public func asyncAfter(wallDeadline: DispatchWallTime, qos: DispatchQoS = .unspecified,
                           flags: DispatchWorkItemFlags = [], execute work: @escaping () -> Void) {
        dispatch_after(wallDeadline.rawValue, __object, work)
    }

    public func asyncAfter(deadline: DispatchTime, execute item: DispatchWorkItem) {
        dispatch_after(deadline.rawValue, __object) { item.perform() }
    }

    public func asyncAfter(wallDeadline: DispatchWallTime, execute item: DispatchWorkItem) {
        dispatch_after(wallDeadline.rawValue, __object) { item.perform() }
    }

    public func sync(execute block: () -> Void) {
        withoutActuallyEscaping(block) { b in
            dispatch_sync(__object) { b() }
        }
    }

    public func sync(execute item: DispatchWorkItem) {
        dispatch_sync(__object) { item.perform() }
    }

    public func sync<T>(execute work: () throws -> T) rethrows -> T {
        try sync(flags: [], execute: work)
    }

    public func sync<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T {
        try _rethrowing(work, rescue: { throw $0 }) { w in
            var result: Result<T, Error>?
            if flags.contains(.barrier) {
                dispatch_barrier_sync(__object) { result = Result { try w() } }
            } else {
                dispatch_sync(__object) { result = Result { try w() } }
            }
            return result!
        }
    }

    // A rethrowing function may throw only what its closures throw: the
    // error the work threw is thrown again through rescue.
    private func _rethrowing<T>(_ work: () throws -> T, rescue: (Error) throws -> T,
                                _ run: (() throws -> T) -> Result<T, Error>) rethrows -> T {
        let r = withoutActuallyEscaping(work) { w in run(w) }
        switch r {
        case .success(let v): return v
        case .failure(let e): return try rescue(e)
        }
    }

    /// Runs the work once for each index, side by side where it can.
    public class func concurrentPerform(iterations: Int, execute work: (Int) -> Void) {
        withoutActuallyEscaping(work) { w in
            dispatch_apply(iterations, global().__object) { w($0) }
        }
    }

    // ---- values kept with a queue

    public func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) {
        let k = Unmanaged.passUnretained(key).toOpaque()
        if let value {
            let box = Unmanaged.passRetained(_SpecificBox(value)).toOpaque()
            dispatch_queue_set_specific(__object, k, box) { Unmanaged<AnyObject>.fromOpaque($0!).release() }
        } else {
            dispatch_queue_set_specific(__object, k, nil, nil)
        }
    }

    public func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? {
        let k = Unmanaged.passUnretained(key).toOpaque()
        guard let p = dispatch_queue_get_specific(__object, k) else { return nil }
        return (Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? _SpecificBox<T>)?.value
    }

    public class func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? {
        let k = Unmanaged.passUnretained(key).toOpaque()
        guard let p = dispatch_get_specific(k) else { return nil }
        return (Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? _SpecificBox<T>)?.value
    }
}

/// A key for a value kept with a queue.
public final class DispatchSpecificKey<T> {
    public init() {}
}

final class _SpecificBox<T> {
    let value: T
    init(_ v: T) { value = v }
}

/// Work that can be waited for as a whole.
public final class DispatchGroup: DispatchObject, _DispatchBridged, @unchecked Sendable {
    public init(__wrapping object: NSObject) { super.init(object) }

    public init() { super.init(dispatch_group_create()) }

    public func enter() { dispatch_group_enter(__object) }
    public func leave() { dispatch_group_leave(__object) }

    public func wait() { _ = dispatch_group_wait(__object, ~0) }

    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        dispatch_group_wait(__object, timeout.rawValue) == 0 ? .success : .timedOut
    }

    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
        dispatch_group_wait(__object, wallTimeout.rawValue) == 0 ? .success : .timedOut
    }

    public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue,
                       execute work: @escaping () -> Void) {
        dispatch_group_notify(__object, queue.__object, work)
    }

    public func notify(queue: DispatchQueue, work: DispatchWorkItem) {
        dispatch_group_notify(__object, queue.__object) { work.perform() }
    }
}

/// A count that threads wait on and signal.
public final class DispatchSemaphore: DispatchObject, _DispatchBridged, @unchecked Sendable {
    public init(__wrapping object: NSObject) { super.init(object) }

    public init(value: Int) { super.init(dispatch_semaphore_create(value)) }

    public func wait() { _ = dispatch_semaphore_wait(__object, ~0) }

    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        dispatch_semaphore_wait(__object, timeout.rawValue) == 0 ? .success : .timedOut
    }

    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
        dispatch_semaphore_wait(__object, wallTimeout.rawValue) == 0 ? .success : .timedOut
    }

    @discardableResult
    public func signal() -> Int { dispatch_semaphore_signal(__object) }
}

/// What dispatchPrecondition checks.
public enum DispatchPredicate {
    case onQueue(DispatchQueue)
    case onQueueAsBarrier(DispatchQueue)
    case notOnQueue(DispatchQueue)
}

/// Stops the program if the code isn't running where it should: on the
/// queue (directly, or on a queue that targets it), or not on it.
public func dispatchPrecondition(condition: @autoclosure () -> DispatchPredicate) {
    switch condition() {
    case .onQueue(let q): dispatch_assert_queue(q.__object)
    case .onQueueAsBarrier(let q): dispatch_assert_queue_barrier(q.__object)
    case .notOnQueue(let q): dispatch_assert_queue_not(q.__object)
    }
}

/// Runs the work the main queue is given, for ever, as a program's last
/// call when it has nothing but queued work to do.
public func dispatchMain() -> Never {
    dispatch_main()
}
