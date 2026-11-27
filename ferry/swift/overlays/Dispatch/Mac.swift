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
