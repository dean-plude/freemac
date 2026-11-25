// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for Dispatch (freemac 1.230): dispatch sources
// (timers, file descriptors, signals, processes, files and data added by
// the program), with the names Apple's Dispatch documentation gives them.
// Written for Ferry, over Ferry's libdispatch.

import Darwin

public typealias DispatchSourceHandler = @convention(block) () -> Void

/// What every kind of dispatch source can do.
public protocol DispatchSourceProtocol: AnyObject {
    func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: DispatchSourceHandler?)
    func setEventHandler(handler: DispatchWorkItem)
    func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: DispatchSourceHandler?)
    func setCancelHandler(handler: DispatchWorkItem)
    func setRegistrationHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: DispatchSourceHandler?)
    func setRegistrationHandler(handler: DispatchWorkItem)
    func activate()
    func cancel()
    func resume()
    func suspend()
    var handle: UInt { get }
    var mask: UInt { get }
    var data: UInt { get }
    var isCancelled: Bool { get }
}

extension DispatchSourceProtocol {
    public func setEventHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                handler: DispatchSourceHandler?) {
        (self as! DispatchSource).setEvent(handler)
    }
    public func setEventHandler(handler: DispatchWorkItem) {
        (self as! DispatchSource).setEvent { handler.perform() }
    }
    public func setCancelHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                 handler: DispatchSourceHandler?) {
        (self as! DispatchSource).setCancel(handler)
    }
    public func setCancelHandler(handler: DispatchWorkItem) {
        (self as! DispatchSource).setCancel { handler.perform() }
    }
    public func setRegistrationHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                       handler: DispatchSourceHandler?) {
        (self as! DispatchSource).setRegistration(handler)
    }
    public func setRegistrationHandler(handler: DispatchWorkItem) {
        (self as! DispatchSource).setRegistration { handler.perform() }
    }
}

extension DispatchSourceProtocol {
    var __source: NSObject { (self as! DispatchSource).__object }
    public var isCancelled: Bool { dispatch_source_testcancel(__source) != 0 }
    public var handle: UInt { UInt(dispatch_source_get_handle(__source)) }
    public var mask: UInt { dispatch_source_get_mask(__source) }
    public var data: UInt { dispatch_source_get_data(__source) }
}

public protocol DispatchSourceTimer: DispatchSourceProtocol {
    func schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval, leeway: DispatchTimeInterval)
    func schedule(deadline: DispatchTime, repeating interval: Double, leeway: DispatchTimeInterval)
    func schedule(wallDeadline: DispatchWallTime, repeating interval: DispatchTimeInterval, leeway: DispatchTimeInterval)
    func schedule(wallDeadline: DispatchWallTime, repeating interval: Double, leeway: DispatchTimeInterval)
}

extension DispatchSourceTimer {
    public func schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval = .never,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        (self as! DispatchSource).setTimer(deadline.rawValue, interval, leeway)
    }
    public func schedule(deadline: DispatchTime, repeating interval: Double,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        (self as! DispatchSource).setTimer(deadline.rawValue, interval.isInfinite ? .never : .nanoseconds(Int(interval * 1e9)), leeway)
    }
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: DispatchTimeInterval = .never,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        (self as! DispatchSource).setTimer(wallDeadline.rawValue, interval, leeway)
    }
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: Double,
                         leeway: DispatchTimeInterval = .nanoseconds(0)) {
        (self as! DispatchSource).setTimer(wallDeadline.rawValue, interval.isInfinite ? .never : .nanoseconds(Int(interval * 1e9)), leeway)
    }
}

public protocol DispatchSourceRead: DispatchSourceProtocol {}
public protocol DispatchSourceWrite: DispatchSourceProtocol {}
public protocol DispatchSourceSignal: DispatchSourceProtocol {}

public protocol DispatchSourceUserDataAdd: DispatchSourceProtocol {
    func add(data: UInt)
}
public protocol DispatchSourceUserDataOr: DispatchSourceProtocol {
    func or(data: UInt)
}
public protocol DispatchSourceUserDataReplace: DispatchSourceProtocol {
    func replace(data: UInt)
}

public protocol DispatchSourceProcess: DispatchSourceProtocol {
    var pid: pid_t { get }
    var data: DispatchSource.ProcessEvent { get }
    var mask: DispatchSource.ProcessEvent { get }
}

public protocol DispatchSourceFileSystemObject: DispatchSourceProtocol {
    var data: DispatchSource.FileSystemEvent { get }
    var mask: DispatchSource.FileSystemEvent { get }
}

extension DispatchSourceProcess {
    public var pid: pid_t { pid_t(truncatingIfNeeded: dispatch_source_get_handle(__source)) }
    public var data: DispatchSource.ProcessEvent { DispatchSource.ProcessEvent(rawValue: dispatch_source_get_data(__source)) }
    public var mask: DispatchSource.ProcessEvent { DispatchSource.ProcessEvent(rawValue: dispatch_source_get_mask(__source)) }
}

extension DispatchSourceFileSystemObject {
    public var data: DispatchSource.FileSystemEvent {
        DispatchSource.FileSystemEvent(rawValue: dispatch_source_get_data(__source))
    }
    public var mask: DispatchSource.FileSystemEvent {
        DispatchSource.FileSystemEvent(rawValue: dispatch_source_get_mask(__source))
    }
}

/// A source of events: a timer, a file descriptor ready to read or write,
/// a signal, a process, a file that changes, or data the program adds.
public final class DispatchSource: DispatchObject, _DispatchBridged, DispatchSourceTimer, DispatchSourceRead,
    DispatchSourceWrite, DispatchSourceSignal, DispatchSourceUserDataAdd, DispatchSourceUserDataOr,
    DispatchSourceUserDataReplace, DispatchSourceProcess, DispatchSourceFileSystemObject, @unchecked Sendable {

    public struct TimerFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let strict = TimerFlags(rawValue: 1)
    }

    public struct ProcessEvent: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let exit = ProcessEvent(rawValue: 0x8000_0000)
        public static let fork = ProcessEvent(rawValue: 0x4000_0000)
        public static let exec = ProcessEvent(rawValue: 0x2000_0000)
        public static let signal = ProcessEvent(rawValue: 0x0800_0000)
        public static let all: ProcessEvent = [.exit, .fork, .exec, .signal]
    }

    public struct FileSystemEvent: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let delete = FileSystemEvent(rawValue: 0x1)
        public static let write = FileSystemEvent(rawValue: 0x2)
        public static let extend = FileSystemEvent(rawValue: 0x4)
        public static let attrib = FileSystemEvent(rawValue: 0x8)
        public static let link = FileSystemEvent(rawValue: 0x10)
        public static let rename = FileSystemEvent(rawValue: 0x20)
        public static let revoke = FileSystemEvent(rawValue: 0x40)
        public static let funlock = FileSystemEvent(rawValue: 0x100)
        public static let all: FileSystemEvent = [.delete, .write, .extend, .attrib, .link, .rename, .revoke]
    }

    public init(__wrapping object: NSObject) { super.init(object) }

    private convenience init(_ type: Int32, _ handle: UInt, _ mask: UInt, _ queue: DispatchQueue?) {
        let q = queue ?? DispatchQueue.global()
        self.init(__wrapping: dispatch_source_create(_ferry_dispatch_source_type(type), handle, mask, q.__object))
    }

    // ---- making sources

    public class func makeTimerSource(flags: TimerFlags = [], queue: DispatchQueue? = nil) -> DispatchSourceTimer {
        DispatchSource(0, 0, flags.rawValue, queue)
    }

    public class func makeReadSource(fileDescriptor: Int32, queue: DispatchQueue? = nil) -> DispatchSourceRead {
        DispatchSource(4, UInt(fileDescriptor), 0, queue)
    }

    public class func makeWriteSource(fileDescriptor: Int32, queue: DispatchQueue? = nil) -> DispatchSourceWrite {
        DispatchSource(5, UInt(fileDescriptor), 0, queue)
    }

    public class func makeSignalSource(signal: Int32, queue: DispatchQueue? = nil) -> DispatchSourceSignal {
        DispatchSource(6, UInt(signal), 0, queue)
    }

    public class func makeProcessSource(identifier: pid_t, eventMask: ProcessEvent,
                                        queue: DispatchQueue? = nil) -> DispatchSourceProcess {
        DispatchSource(7, UInt(identifier), eventMask.rawValue, queue)
    }

    public class func makeFileSystemObjectSource(fileDescriptor: Int32, eventMask: FileSystemEvent,
                                                 queue: DispatchQueue? = nil) -> DispatchSourceFileSystemObject {
        DispatchSource(8, UInt(fileDescriptor), eventMask.rawValue, queue)
    }

    public class func makeUserDataAddSource(queue: DispatchQueue? = nil) -> DispatchSourceUserDataAdd {
        DispatchSource(1, 0, 0, queue)
    }

    public class func makeUserDataOrSource(queue: DispatchQueue? = nil) -> DispatchSourceUserDataOr {
        DispatchSource(2, 0, 0, queue)
    }

    public class func makeUserDataReplaceSource(queue: DispatchQueue? = nil) -> DispatchSourceUserDataReplace {
        DispatchSource(3, 0, 0, queue)
    }

    // ---- what they all do

    func setEvent(_ handler: DispatchSourceHandler?) {
        dispatch_source_set_event_handler(__object, handler ?? {})
    }
    func setCancel(_ handler: DispatchSourceHandler?) {
        dispatch_source_set_cancel_handler(__object, handler ?? {})
    }
    func setRegistration(_ handler: DispatchSourceHandler?) {
        // Ferry's sources are registered as soon as they are resumed
        if let handler { dispatch_async(_ferry_dispatch_main_queue(), handler) }
    }

    func setTimer(_ start: dispatch_time_t, _ interval: DispatchTimeInterval, _ leeway: DispatchTimeInterval) {
        let every: UInt64 = interval == .never ? ~0 : UInt64(max(0, interval.nanoseconds))
        let slack: UInt64 = leeway == .never ? 0 : UInt64(max(0, leeway.nanoseconds))
        dispatch_source_set_timer(__object, start, every, slack)
    }

    public func cancel() { dispatch_source_cancel(__object) }

    public func add(data: UInt) { dispatch_source_merge_data(__object, data) }
    public func or(data: UInt) { dispatch_source_merge_data(__object, data) }
    public func replace(data: UInt) { dispatch_source_merge_data(__object, data) }
}
