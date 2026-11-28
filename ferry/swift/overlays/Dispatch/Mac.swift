// SPDX-License-Identifier: GPL-3.0-or-later
//
// Dispatch as an app built on a Mac calls it (freemac 1.260). There, Swift
// sees a queue as the Objective-C class OS_dispatch_queue (named
// DispatchQueue), and the Dispatch overlay adds its methods to that class,
// so an app built there calls OS_dispatch_queue's "main" and "async". Ferry's
// own DispatchQueue is a Swift class wrapping the same object; these
// additions, with the Mac's names and shapes, hand the work to it. Written
// for Ferry from Apple's documentation of Dispatch.

extension OS_dispatch_queue {
    @inline(__always) var _queue: DispatchQueue { DispatchQueue(__wrapping: self) }

    public static var main: OS_dispatch_queue {
        unsafeBitCast(_ferry_dispatch_main_queue(), to: OS_dispatch_queue.self)
    }

    public class func global(qos: DispatchQoS.QoSClass = .default) -> OS_dispatch_queue {
        unsafeBitCast(DispatchQueue.global(qos: qos).__object, to: OS_dispatch_queue.self)
    }

    public func async(group: OS_dispatch_group? = nil, qos: DispatchQoS = .unspecified,
                      flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
        _queue.async(group: group.map { DispatchGroup(__wrapping: $0) }, qos: qos, flags: flags) { work() }
    }

    public func async(execute item: DispatchWorkItem) { _queue.async(execute: item) }

    public func asyncAfter(deadline: DispatchTime, qos: DispatchQoS = .unspecified,
                           flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
        _queue.asyncAfter(deadline: deadline, qos: qos, flags: flags) { work() }
    }

    public func asyncAfter(wallDeadline: DispatchWallTime, qos: DispatchQoS = .unspecified,
                           flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
        _queue.asyncAfter(wallDeadline: wallDeadline, qos: qos, flags: flags) { work() }
    }

    public func asyncAfter(deadline: DispatchTime, execute item: DispatchWorkItem) {
        _queue.asyncAfter(deadline: deadline, execute: item)
    }

    public var label: String { _queue.label }

    // ---- freemac 1.262, for IINA

    /// How a new queue's work runs: one at a time unless concurrent.
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        public static let concurrent = Attributes(rawValue: 1 << 1)
        public static let initiallyInactive = Attributes(rawValue: 1 << 2)
    }

    /// When work on a queue drains its autorelease pool.
    public enum AutoreleaseFrequency: Sendable {
        case inherit, workItem, never
    }

    /// A new queue.
    public convenience init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [],
                            autoreleaseFrequency: AutoreleaseFrequency = .inherit, target: OS_dispatch_queue? = nil) {
        var a: DispatchQueue.Attributes = []
        if attributes.contains(.concurrent) { a.insert(.concurrent) }
        if attributes.contains(.initiallyInactive) { a.insert(.initiallyInactive) }
        let q = DispatchQueue(label: label, qos: qos, attributes: a,
                              target: target.map { DispatchQueue(__wrapping: $0) })
        self.init(__ferryQueue: q.__object)
    }

    public func sync(execute block: () -> Void) { _queue.sync(execute: block) }

    // A Mac's sync(execute:) that gives back the work's result. Declared
    // under another name, as Swift won't take it beside the one above in an
    // extension of an Objective-C class, and given the Mac's symbol.
    @_silgen_name("$sSo17OS_dispatch_queueC8DispatchE4sync7executexxyKXE_tKlF")
    public func __syncReturning<T>(execute work: () throws -> T) rethrows -> T {
        try _queue.sync(flags: [], execute: work)
    }

    public func sync<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T {
        try _queue.sync(flags: flags, execute: work)
    }

    public func sync(execute item: DispatchWorkItem) { _queue.sync(execute: item) }
}

extension OS_dispatch_group {
    public func enter() { dispatch_group_enter(self) }
    public func leave() { dispatch_group_leave(self) }
    public func wait() { _ = dispatch_group_wait(self, ~0) }
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        dispatch_group_wait(self, timeout.rawValue) == 0 ? .success : .timedOut
    }
}

extension OS_dispatch_semaphore {
    public func wait() { _ = dispatch_semaphore_wait(self, ~0) }
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        dispatch_semaphore_wait(self, timeout.rawValue) == 0 ? .success : .timedOut
    }
    public func signal() -> Int { dispatch_semaphore_signal(self) }
}

// ---- freemac 1.271, for Stats: sources as a Mac's Dispatch shows them.
// There, makeTimerSource gives an OS_dispatch_source_timer (an Objective-C
// protocol), and a source's methods are added to its protocols. The object
// underneath is the same dispatch source Ferry's DispatchSource wraps.

extension OS_dispatch_queue {
    public static func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? { DispatchQueue.getSpecific(key: key) }
    public func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) { _queue.setSpecific(key: key, value: value) }
    public func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? { _queue.getSpecific(key: key) }
}

extension OS_dispatch_source {
    public struct TimerFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let strict = TimerFlags(rawValue: 1)
    }

    public struct MemoryPressureEvent: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = MemoryPressureEvent(rawValue: 0x1)
        public static let warning = MemoryPressureEvent(rawValue: 0x2)
        public static let critical = MemoryPressureEvent(rawValue: 0x4)
        public static let all: MemoryPressureEvent = [.normal, .warning, .critical]
    }

    public class func makeTimerSource(flags: TimerFlags = [], queue: OS_dispatch_queue? = nil) -> OS_dispatch_source_timer {
        let q: NSObject = queue ?? unsafeBitCast(DispatchQueue.global().__object, to: OS_dispatch_queue.self)
        let s = dispatch_source_create(_ferry_dispatch_source_type(0), 0, flags.rawValue, q)!
        return unsafeBitCast(s, to: OS_dispatch_source_timer.self)
    }

    /// Ferry never feels memory pressure, so this source never fires.
    public class func makeMemoryPressureSource(eventMask: MemoryPressureEvent,
                                               queue: OS_dispatch_queue? = nil) -> OS_dispatch_source_memorypressure {
        let q: NSObject = queue ?? unsafeBitCast(DispatchQueue.global().__object, to: OS_dispatch_queue.self)
        let s = dispatch_source_create(_ferry_dispatch_source_type(1), 0, 0, q)!
        return unsafeBitCast(s, to: OS_dispatch_source_memorypressure.self)
    }
}

extension OS_dispatch_sourceProtocol {
    @inline(__always) var _object: NSObject { unsafeBitCast(self, to: NSObject.self) }

    public func setEventHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                handler: (@convention(block) () -> Void)?) {
        dispatch_source_set_event_handler(_object, handler ?? {})
    }
    public func setEventHandler(handler: DispatchWorkItem) {
        dispatch_source_set_event_handler(_object) { handler.perform() }
    }
    public func setCancelHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                 handler: (@convention(block) () -> Void)?) {
        dispatch_source_set_cancel_handler(_object, handler ?? {})
    }
    public func setCancelHandler(handler: DispatchWorkItem) {
        dispatch_source_set_cancel_handler(_object) { handler.perform() }
    }
    public func setRegistrationHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                       handler: (@convention(block) () -> Void)?) {
        if let handler { dispatch_async(_ferry_dispatch_main_queue(), handler) }
    }
    public func activate() { dispatch_resume(_object) }
    public func cancel() { dispatch_source_cancel(_object) }
    public func resume() { dispatch_resume(_object) }
    public func suspend() { dispatch_suspend(_object) }
    public var handle: UInt { UInt(dispatch_source_get_handle(_object)) }
    public var mask: UInt { dispatch_source_get_mask(_object) }
    public var data: UInt { dispatch_source_get_data(_object) }
    public var isCancelled: Bool { dispatch_source_testcancel(_object) != 0 }
}

extension OS_dispatch_source_timer {
    private func _set(_ start: dispatch_time_t, _ interval: DispatchTimeInterval, _ leeway: DispatchTimeInterval) {
        let every: UInt64 = interval == .never ? ~0 : UInt64(max(0, interval.nanoseconds))
        let slack: UInt64 = leeway == .never ? 0 : UInt64(max(0, leeway.nanoseconds))
        dispatch_source_set_timer(unsafeBitCast(self, to: NSObject.self), start, every, slack)
    }
    private static func _interval(_ seconds: Double) -> DispatchTimeInterval {
        seconds.isInfinite ? .never : .nanoseconds(Int(seconds * 1e9))
    }
    public func schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval = .never,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        _set(deadline.rawValue, interval, leeway)
    }
    public func schedule(deadline: DispatchTime, repeating interval: Double,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        _set(deadline.rawValue, Self._interval(interval), leeway)
    }
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: DispatchTimeInterval = .never,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        _set(wallDeadline.rawValue, interval, leeway)
    }
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: Double,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        _set(wallDeadline.rawValue, Self._interval(interval), leeway)
    }
}

extension OS_dispatch_source_memorypressure {
    public var data: OS_dispatch_source.MemoryPressureEvent {
        .init(rawValue: dispatch_source_get_data(unsafeBitCast(self, to: NSObject.self)))
    }
    public var mask: OS_dispatch_source.MemoryPressureEvent {
        .init(rawValue: dispatch_source_get_mask(unsafeBitCast(self, to: NSObject.self)))
    }
}
