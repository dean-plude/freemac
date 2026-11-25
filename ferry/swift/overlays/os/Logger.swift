// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for os (freemac 1.230): Logger and its messages,
// OSLog and os_log(_:log:type:_:), over the os_log of Ferry's runtime
// (src/objc/oslog.c), which writes to this system's log. A Mac keeps a
// message's arguments apart from its text so that private ones can be
// redacted when the log is read; this log is the user's own, so a message
// is made into text when it is logged, and the privacy given to each value
// is accepted and not acted on. Written for Ferry from Apple's
// documentation of the os module.

@_exported import os
import Foundation

/// How important a message is.
public struct OSLogType: Equatable, RawRepresentable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }

    public static let `default` = OSLogType(0x00)
    public static let info = OSLogType(0x01)
    public static let debug = OSLogType(0x02)
    public static let error = OSLogType(0x10)
    public static let fault = OSLogType(0x11)
}

/// A log of a subsystem's messages, in one of its categories.
public final class OSLog: @unchecked Sendable {
    /// None for the disabled log.
    let log: os_log_t?

    init(_ log: os_log_t?) { self.log = log }

    public convenience init(subsystem: String, category: String) {
        self.init(os_log_create(subsystem, category))
    }

    /// The log of no subsystem in particular.
    public static let `default` = OSLog(os_log_create("", ""))
    /// A log that keeps nothing.
    public static let disabled = OSLog(nil)

    public func isEnabled(type: OSLogType) -> Bool { log.map { os_log_type_enabled($0, type.rawValue) } ?? false }
}

/// Logs a message given as a printf-style format, as C's os_log does.
public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = nil, log: OSLog = .default,
                   type: OSLogType = .default, _ args: CVarArg...) {
    message.withUTF8Buffer { buf in
        let format = String(decoding: buf, as: UTF8.self)
        guard let l = log.log else { return }
        withVaList(args) { ferry_os_logv(l, type.rawValue, format, $0) }
    }
}

public func os_log(_ type: OSLogType, dso: UnsafeRawPointer? = nil, log: OSLog = .default,
                   _ message: StaticString, _ args: CVarArg...) {
    message.withUTF8Buffer { buf in
        let format = String(decoding: buf, as: UTF8.self)
        guard let l = log.log else { return }
        withVaList(args) { ferry_os_logv(l, type.rawValue, format, $0) }
    }
}

// ---- Logger ----------------------------------------------------------------------------

/// Who may read a value in a message, on a Mac.
public struct OSLogPrivacy: Equatable, Sendable {
    let kind: Int
    public static let auto = OSLogPrivacy(kind: 0)
    public static let `public` = OSLogPrivacy(kind: 1)
    public static let `private` = OSLogPrivacy(kind: 2)
    public static let sensitive = OSLogPrivacy(kind: 3)
    public enum Mask: Equatable, Sendable { case hash, none }
    public static func auto(mask: Mask) -> OSLogPrivacy { .auto }
    public static func `private`(mask: Mask) -> OSLogPrivacy { .private }
    public static func sensitive(mask: Mask) -> OSLogPrivacy { .sensitive }
}

/// How a number is written in a message.
public struct OSLogIntegerFormatting: Sendable {
    let radix: Int
    let uppercase: Bool
    let prefix: Bool
    public static let decimal = OSLogIntegerFormatting(radix: 10, uppercase: false, prefix: false)
    public static let hex = OSLogIntegerFormatting(radix: 16, uppercase: false, prefix: false)
    public static let octal = OSLogIntegerFormatting(radix: 8, uppercase: false, prefix: false)
    public static func decimal(explicitPositiveSign: Bool = false, minDigits: Int = 0) -> OSLogIntegerFormatting { .decimal }
    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false,
                           minDigits: Int = 0) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 16, uppercase: uppercase, prefix: includePrefix)
    }
    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false,
                             minDigits: Int = 0) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 8, uppercase: false, prefix: includePrefix)
    }

    func string<T: BinaryInteger>(_ n: T) -> String {
        var s = String(n, radix: radix, uppercase: uppercase)
        if prefix { s = (radix == 16 ? "0x" : "0") + s }
        return s
    }
}

/// How a floating-point number is written in a message.
public struct OSLogFloatFormatting: Sendable {
    let precision: Int?
    public static let fixed = OSLogFloatFormatting(precision: 6)
    public static func fixed(precision: @autoclosure () -> Int, explicitPositiveSign: Bool = false,
                             uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(precision: precision())
    }
    public static let exponential = OSLogFloatFormatting(precision: nil)
    public static let hybrid = OSLogFloatFormatting(precision: nil)
}

/// Where a value sits in the width given to it.
public struct OSLogStringAlignment: Sendable {
    let width: Int
    let left: Bool
    public static let none = OSLogStringAlignment(width: 0, left: false)
    public static func right(columns: @autoclosure () -> Int) -> OSLogStringAlignment {
        OSLogStringAlignment(width: columns(), left: false)
    }
    public static func left(columns: @autoclosure () -> Int) -> OSLogStringAlignment {
        OSLogStringAlignment(width: columns(), left: true)
    }

    func apply(_ s: String) -> String {
        guard s.count < width else { return s }
        let pad = String(repeating: " ", count: width - s.count)
        return left ? s + pad : pad + s
    }
}

/// A message's text, with the values put into it.
public struct OSLogInterpolation: StringInterpolationProtocol {
    var text = ""
    public init(literalCapacity: Int, interpolationCount: Int) { text.reserveCapacity(literalCapacity) }

    public mutating func appendLiteral(_ literal: String) { text += literal }

    public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> String,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(value())
    }

    public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: @autoclosure @escaping () -> T,
                                                                         align: OSLogStringAlignment = .none,
                                                                         privacy: OSLogPrivacy = .auto) {
        text += align.apply(value().description)
    }

    public mutating func appendInterpolation<T: BinaryInteger>(_ number: @autoclosure @escaping () -> T,
                                                               format: OSLogIntegerFormatting = .decimal,
                                                               align: OSLogStringAlignment = .none,
                                                               privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.string(number()))
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double,
                                             format: OSLogFloatFormatting = .fixed,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        let n = number()
        text += align.apply(format.precision.map { String(format: "%.\($0)f", n) } ?? "\(n)")
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float,
                                             format: OSLogFloatFormatting = .fixed,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInterpolation(Double(number()), format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ boolean: @autoclosure @escaping () -> Bool,
                                             privacy: OSLogPrivacy = .auto) {
        text += boolean() ? "true" : "false"
    }

    public mutating func appendInterpolation(_ object: @autoclosure @escaping () -> NSObject,
                                             privacy: OSLogPrivacy = .auto) {
        text += object().description
    }

    public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Error,
                                             privacy: OSLogPrivacy = .auto) {
        text += String(describing: value())
    }

    public mutating func appendInterpolation<T>(_ value: @autoclosure @escaping () -> T?, privacy: OSLogPrivacy = .auto) {
        text += value().map { String(describing: $0) } ?? "(null)"
    }

    public mutating func appendInterpolation(_ type: Any.Type, privacy: OSLogPrivacy = .auto) {
        text += String(describing: type)
    }
}

/// A message for a Logger: a string literal, with values put into it.
public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    let interpolation: OSLogInterpolation
    public init(stringInterpolation: OSLogInterpolation) { interpolation = stringInterpolation }
    public init(stringLiteral value: String) {
        var i = OSLogInterpolation(literalCapacity: value.utf8.count, interpolationCount: 0)
        i.appendLiteral(value)
        interpolation = i
    }
}

/// Writes a subsystem's messages, in one of its categories, to the log.
public struct Logger: @unchecked Sendable {
    let log: OSLog

    public init(subsystem: String, category: String) { log = OSLog(subsystem: subsystem, category: category) }
    public init(_ log: OSLog) { self.log = log }
    public init() { log = .default }

    public func log(level: OSLogType, _ message: OSLogMessage) {
        guard let l = log.log, log.isEnabled(type: level) else { return }
        ferry_os_log_message(l, level.rawValue, message.interpolation.text)
    }
    public func log(_ message: OSLogMessage) { log(level: .default, message) }
    public func trace(_ message: OSLogMessage) { log(level: .debug, message) }
    public func debug(_ message: OSLogMessage) { log(level: .debug, message) }
    public func info(_ message: OSLogMessage) { log(level: .info, message) }
    public func notice(_ message: OSLogMessage) { log(level: .default, message) }
    public func warning(_ message: OSLogMessage) { log(level: .error, message) }
    public func error(_ message: OSLogMessage) { log(level: .error, message) }
    public func critical(_ message: OSLogMessage) { log(level: .fault, message) }
    public func fault(_ message: OSLogMessage) { log(level: .fault, message) }
}
