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

    public func sync<T>(execute work: () throws -> T) rethrows -> T { try _queue.sync(execute: work) }

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
