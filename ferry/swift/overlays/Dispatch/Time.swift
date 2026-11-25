// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for Dispatch (freemac 1.230): times and time
// intervals. Written for Ferry from Apple's public Dispatch documentation;
// how it works underneath is Ferry's own, over the C calls of Ferry's
// libdispatch (src/objc/dispatch.c), whose clock is the monotonic one.

@_exported import Dispatch
import Darwin

/// A point in time on the system's clock, which doesn't run while the
/// computer sleeps.
public struct DispatchTime: Comparable, Hashable, Sendable {
    public let rawValue: dispatch_time_t

    public init(rawValue: dispatch_time_t) { self.rawValue = rawValue }

    /// The time now.
    public static func now() -> DispatchTime { DispatchTime(rawValue: dispatch_time(0, 0)) }

    /// A time that never comes.
    public static let distantFuture = DispatchTime(rawValue: ~0)

    /// A time this many nanoseconds after the system started.
    public init(uptimeNanoseconds: UInt64) {
        rawValue = uptimeNanoseconds == 0 ? 1 : uptimeNanoseconds
    }

    /// Nanoseconds since the system started.
    public var uptimeNanoseconds: UInt64 {
        rawValue == ~0 ? UInt64.max : rawValue == 0 ? DispatchTime.now().rawValue : rawValue
    }

    public static func < (a: DispatchTime, b: DispatchTime) -> Bool { a.uptimeNanoseconds < b.uptimeNanoseconds }
    public static func == (a: DispatchTime, b: DispatchTime) -> Bool { a.rawValue == b.rawValue }

    /// The nanoseconds from this time to another.
    public func distance(to other: DispatchTime) -> DispatchTimeInterval {
        .nanoseconds(Int(Int64(bitPattern: other.uptimeNanoseconds &- uptimeNanoseconds)))
    }

    public func advanced(by n: DispatchTimeInterval) -> DispatchTime { self + n }
}

/// A point in time on the wall clock, which goes on while the computer sleeps.
public struct DispatchWallTime: Comparable, Hashable, Sendable {
    public let rawValue: dispatch_time_t

    public init(rawValue: dispatch_time_t) { self.rawValue = rawValue }

    public static func now() -> DispatchWallTime { DispatchWallTime(rawValue: dispatch_walltime(nil, 0)) }

    public static let distantFuture = DispatchWallTime(rawValue: ~0)

    public init(timespec: timespec) {
        var t = timespec
        rawValue = dispatch_walltime(&t, 0)
    }

    public static func < (a: DispatchWallTime, b: DispatchWallTime) -> Bool {
        // wall times are kept as negative numbers of nanoseconds
        if a.rawValue == ~0 { return false }
        if b.rawValue == ~0 { return true }
        return Int64(bitPattern: a.rawValue) > Int64(bitPattern: b.rawValue)
    }
}

/// An amount of time, in the unit it was given in.
public enum DispatchTimeInterval: Equatable, Sendable {
    case seconds(Int)
    case milliseconds(Int)
    case microseconds(Int)
    case nanoseconds(Int)
    case never

    /// The interval in nanoseconds, or Int64.max for never.
    var nanoseconds: Int64 {
        switch self {
        case .seconds(let n): return Int64(n).multipliedReportingOverflow(by: 1_000_000_000).overflow ? .max : Int64(n) * 1_000_000_000
        case .milliseconds(let n): return Int64(n).multipliedReportingOverflow(by: 1_000_000).overflow ? .max : Int64(n) * 1_000_000
        case .microseconds(let n): return Int64(n).multipliedReportingOverflow(by: 1_000).overflow ? .max : Int64(n) * 1_000
        case .nanoseconds(let n): return Int64(n)
        case .never: return .max
        }
    }

    public static func == (a: DispatchTimeInterval, b: DispatchTimeInterval) -> Bool {
        switch (a, b) {
        case (.never, .never): return true
        case (.never, _), (_, .never): return false
        default: return a.nanoseconds == b.nanoseconds
        }
    }
}

private func nanos(_ seconds: Double) -> Int64 {
    let n = seconds * 1_000_000_000
    if n >= Double(Int64.max) { return .max }
    if n <= Double(Int64.min) { return .min }
    return Int64(n)
}

private func later(_ raw: dispatch_time_t, _ delta: Int64) -> dispatch_time_t {
    if raw == ~0 || delta == .max { return ~0 }
    return dispatch_time(raw, delta)
}

public func + (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
    DispatchTime(rawValue: later(time.rawValue, interval.nanoseconds))
}
public func - (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
    interval == .never ? DispatchTime(rawValue: 0) : DispatchTime(rawValue: later(time.rawValue, -interval.nanoseconds))
}
public func + (time: DispatchTime, seconds: Double) -> DispatchTime {
    DispatchTime(rawValue: later(time.rawValue, nanos(seconds)))
}
public func - (time: DispatchTime, seconds: Double) -> DispatchTime {
    DispatchTime(rawValue: later(time.rawValue, -nanos(seconds)))
}
public func + (time: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime {
    DispatchWallTime(rawValue: later(time.rawValue, interval.nanoseconds))
}
public func - (time: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime {
    DispatchWallTime(rawValue: later(time.rawValue, -interval.nanoseconds))
}
public func + (time: DispatchWallTime, seconds: Double) -> DispatchWallTime {
    DispatchWallTime(rawValue: later(time.rawValue, nanos(seconds)))
}
public func - (time: DispatchWallTime, seconds: Double) -> DispatchWallTime {
    DispatchWallTime(rawValue: later(time.rawValue, -nanos(seconds)))
}

/// Whether a wait ended because what it waited for came, or because time ran out.
public enum DispatchTimeoutResult: Sendable {
    case success
    case timedOut
}
