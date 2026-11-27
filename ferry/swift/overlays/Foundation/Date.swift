// SPDX-License-Identifier: GPL-3.0-or-later
//
// Date, URL and UUID (freemac 1.230), the values Swift code on a Mac sees
// in place of NSDate, NSURL and NSUUID (the API notes name them as those
// classes' Swift types, so Objective-C methods take and return them).
// Date is a number of seconds since the reference date (the first instant
// of 2001, UTC); URL holds an NSURL, which never changes; UUID holds its
// sixteen bytes. Each is Hashable, Codable and Sendable. Written for Ferry
// from Apple's documentation of the types.

// ---- Date ---------------------------------------------------------------------------

public struct Date: Hashable, Comparable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Seconds from the reference date, 2001-01-01 00:00:00 UTC.
    public var timeIntervalSinceReferenceDate: TimeInterval

    /// Seconds from 1970 to the reference date.
    public static let timeIntervalBetween1970AndReferenceDate: TimeInterval = 978_307_200

    public init(timeIntervalSinceReferenceDate t: TimeInterval) { timeIntervalSinceReferenceDate = t }

    /// Now.
    public init() { timeIntervalSinceReferenceDate = Date._now() }

    public init(timeIntervalSinceNow t: TimeInterval) { self.init(timeIntervalSinceReferenceDate: Date._now() + t) }

    public init(timeIntervalSince1970 t: TimeInterval) {
        self.init(timeIntervalSinceReferenceDate: t - Date.timeIntervalBetween1970AndReferenceDate)
    }

    public init(timeInterval t: TimeInterval, since date: Date) {
        self.init(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate + t)
    }

    public static var now: Date { Date() }
    public static let distantFuture = Date(timeIntervalSinceReferenceDate: 63_113_904_000)
    public static let distantPast = Date(timeIntervalSinceReferenceDate: -63_114_076_800)

    public var timeIntervalSince1970: TimeInterval {
        timeIntervalSinceReferenceDate + Date.timeIntervalBetween1970AndReferenceDate
    }

    public var timeIntervalSinceNow: TimeInterval { timeIntervalSinceReferenceDate - Date._now() }

    public func timeIntervalSince(_ other: Date) -> TimeInterval {
        timeIntervalSinceReferenceDate - other.timeIntervalSinceReferenceDate
    }

    public func addingTimeInterval(_ t: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate + t)
    }

    public mutating func addTimeInterval(_ t: TimeInterval) { timeIntervalSinceReferenceDate += t }

    public func advanced(by t: TimeInterval) -> Date { addingTimeInterval(t) }
    public func distance(to other: Date) -> TimeInterval { other.timeIntervalSince(self) }

    public func compare(_ other: Date) -> ComparisonResult {
        self < other ? .orderedAscending : self > other ? .orderedDescending : .orderedSame
    }

    public static func < (a: Date, b: Date) -> Bool { a.timeIntervalSinceReferenceDate < b.timeIntervalSinceReferenceDate }
    public static func + (d: Date, t: TimeInterval) -> Date { d.addingTimeInterval(t) }
    public static func - (d: Date, t: TimeInterval) -> Date { d.addingTimeInterval(-t) }
    public static func += (d: inout Date, t: TimeInterval) { d.addTimeInterval(t) }
    public static func -= (d: inout Date, t: TimeInterval) { d.addTimeInterval(-t) }

    /// The date as NSDate shows it (UTC, "2026-11-25 12:00:00 +0000").
    public var description: String { (_toNS().description as String?) ?? "\(timeIntervalSinceReferenceDate)" }
    public var debugDescription: String { description }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(timeIntervalSinceReferenceDate: try c.decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(timeIntervalSinceReferenceDate)
    }

    internal static func _now() -> TimeInterval {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9 - timeIntervalBetween1970AndReferenceDate
    }

    internal func _toNS() -> NSDate { NSDate(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate) }
}

extension Date: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDate { _toNS() }
    public static func _forceBridgeFromObjectiveC(_ x: NSDate, result: inout Date?) {
        result = Date(timeIntervalSinceReferenceDate: x.timeIntervalSinceReferenceDate)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSDate, result: inout Date?) -> Bool {
        _forceBridgeFromObjectiveC(x, result: &result)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDate?) -> Date {
        Date(timeIntervalSinceReferenceDate: source?.timeIntervalSinceReferenceDate ?? 0)
    }
}

/// A span of time from a start date.
public struct DateInterval: Hashable, Comparable, Sendable, Codable {
    public var start: Date
    public var duration: TimeInterval
    public var end: Date { start + duration }

    public init() { start = Date(); duration = 0 }
    public init(start: Date, duration: TimeInterval) { self.start = start; self.duration = duration }
    public init(start: Date, end: Date) { self.start = start; duration = end.timeIntervalSince(start) }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }

    public static func < (a: DateInterval, b: DateInterval) -> Bool {
        a.start != b.start ? a.start < b.start : a.duration < b.duration
    }
}

// ---- URL ----------------------------------------------------------------------------

public struct URL: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    // an NSURL never changes, so copies may share one
    nonisolated(unsafe) internal var _url: NSURL

    internal init(_ns url: NSURL) { _url = url }

    public init?(string: __shared String) {
        guard !string.isEmpty, let u = NSURL(string: string) else { return nil }
        _url = u
    }

    public init?(string: __shared String, relativeTo base: __shared URL?) {
        guard !string.isEmpty else { return nil }
        let made: NSURL?
        if let base { made = NSURL(string: string, relativeTo: base) } else { made = NSURL(string: string) }
        guard let u = made else { return nil }
        _url = u
    }



    public init(fileURLWithPath path: String, relativeTo base: URL?) {
        if path.hasPrefix("/") || base == nil { self.init(fileURLWithPath: path) }
        else { self.init(fileURLWithPath: base!.path + "/" + path) }
    }

    /// A file URL from a path, as macOS 13's URL(filePath:) makes one.
    public init(filePath path: String, directoryHint: DirectoryHint = .inferFromPath) {
        switch directoryHint {
        case .isDirectory: self.init(fileURLWithPath: path, isDirectory: true)
        case .notDirectory: self.init(fileURLWithPath: path, isDirectory: false)
        default: self.init(fileURLWithPath: path)
        }
    }

    public enum DirectoryHint: Sendable { case isDirectory, notDirectory, checkFileSystem, inferFromPath }

    public var absoluteString: String { _url.absoluteString ?? "" }
    public var relativeString: String { _url.relativeString ?? "" }
    public var absoluteURL: URL { _url.absolute ?? self }
    public var baseURL: URL? { _url.base }
    public var scheme: String? { _url.scheme }
    public var host: String? { _url.host }
    public func host(percentEncoded: Bool = true) -> String? { host }
    public var port: Int? {
        guard let p: NSNumber = _url.port else { return nil }
        return p.integerValue
    }
    public var user: String? { _url.user }
    public var password: String? { _url.password }
    public var path: String { _url.path ?? "" }
    public func path(percentEncoded: Bool = true) -> String { path }
    public var relativePath: String { path }
    public var query: String? { _url.query }
    public var fragment: String? { _url.fragment }
    public var lastPathComponent: String { _url.lastPathComponent ?? "" }
    public var pathExtension: String { _url.pathExtension ?? "" }
    public var pathComponents: [String] { _url.pathComponents ?? [] }
    public var isFileURL: Bool { _url.isFileURL }
    public var hasDirectoryPath: Bool { _url.hasDirectoryPath }
    public var standardized: URL { _url.standardizingPath ?? self }
    public var standardizedFileURL: URL { isFileURL ? standardized : self }

    public func withUnsafeFileSystemRepresentation<R>(_ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R {
        try path.withCString { try body($0) }
    }

    public func appendingPathComponent(_ c: String) -> URL { _url.appendingPathComponent(c) ?? self }
    public func appendingPathComponent(_ c: String, isDirectory: Bool) -> URL {
        _url.appendingPathComponent(c, isDirectory: isDirectory) ?? self
    }
    public func appending(path c: String, directoryHint: DirectoryHint = .inferFromPath) -> URL {
        switch directoryHint {
        case .isDirectory: return appendingPathComponent(c, isDirectory: true)
        case .notDirectory: return appendingPathComponent(c, isDirectory: false)
        default: return appendingPathComponent(c)
        }
    }
    public func appending(component c: String, directoryHint: DirectoryHint = .inferFromPath) -> URL {
        appending(path: c, directoryHint: directoryHint)
    }
    public func appendingPathExtension(_ e: String) -> URL { _url.appendingPathExtension(e) ?? self }
    public func deletingLastPathComponent() -> URL { _url.deletingLastPathComponent ?? self }
    public func deletingPathExtension() -> URL { _url.deletingPathExtension ?? self }

    public mutating func appendPathComponent(_ c: String) { self = appendingPathComponent(c) }
    public mutating func appendPathComponent(_ c: String, isDirectory: Bool) {
        self = appendingPathComponent(c, isDirectory: isDirectory)
    }
    public mutating func append(path c: String, directoryHint: DirectoryHint = .inferFromPath) {
        self = appending(path: c, directoryHint: directoryHint)
    }
    public mutating func appendPathExtension(_ e: String) { self = appendingPathExtension(e) }
    public mutating func deleteLastPathComponent() { self = deletingLastPathComponent() }
    public mutating func deletePathExtension() { self = deletingPathExtension() }
    public mutating func standardize() { self = standardized }

    /// The file or folder's own URL: true when it is there.
    public func checkResourceIsReachable() throws -> Bool {
        guard isFileURL else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError, userInfo: [NSURLErrorKey: _url])
        }
        guard access(path, F_OK) == 0 else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: path])
        }
        return true
    }

    public static func == (a: URL, b: URL) -> Bool { a.absoluteString == b.absoluteString }
    public func hash(into h: inout Hasher) { h.combine(absoluteString) }

    public var description: String { absoluteString }
    public var debugDescription: String { absoluteString }

    public init(from decoder: Decoder) throws {
        // as Apple's URL encodes itself: a relative string, and a base when it has one
        if let keyed = try? decoder.container(keyedBy: _CodingKeys.self), keyed.contains(.relative) {
            let rel = try keyed.decode(String.self, forKey: .relative)
            let base = try keyed.decodeIfPresent(URL.self, forKey: .base)
            guard let u = URL(string: rel, relativeTo: base) else {
                throw DecodingError.dataCorruptedError(forKey: .relative, in: keyed, debugDescription: "not a URL")
            }
            self = u
            return
        }
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let u = URL(string: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a URL: \(s)")
        }
        self = u
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: _CodingKeys.self)
        try c.encode(relativeString, forKey: .relative)
        if let baseURL { try c.encode(baseURL, forKey: .base) }
    }

    private enum _CodingKeys: String, CodingKey { case base, relative }
}

extension URL: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURL { _url }
    public static func _forceBridgeFromObjectiveC(_ x: NSURL, result: inout URL?) { result = URL(_ns: x) }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSURL, result: inout URL?) -> Bool {
        result = URL(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURL?) -> URL {
        URL(_ns: source ?? NSURL(fileURLWithPath: "/"))
    }
}

extension URL {
    /// The folders a Mac has for each user, as macOS 13's URL gives them.
    public static var homeDirectory: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }
    public static var temporaryDirectory: URL { URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true) }
    public static var applicationSupportDirectory: URL { _userFolder(.applicationSupportDirectory) }
    public static var cachesDirectory: URL { _userFolder(.cachesDirectory) }
    public static var documentsDirectory: URL { _userFolder(.documentDirectory) }
    public static var desktopDirectory: URL { _userFolder(.desktopDirectory) }
    public static var downloadsDirectory: URL { _userFolder(.downloadsDirectory) }
    public static var libraryDirectory: URL { _userFolder(.libraryDirectory) }

    private static func _userFolder(_ d: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: d, in: .userDomainMask).first ?? homeDirectory
    }
}

// ---- UUID ---------------------------------------------------------------------------

public typealias uuid_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

public struct UUID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public private(set) var uuid: uuid_t

    /// A new random UUID (version 4).
    public init() {
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { b[i] = UInt8.random(in: 0...255) }
        b[6] = (b[6] & 0x0f) | 0x40
        b[8] = (b[8] & 0x3f) | 0x80
        uuid = UUID._tuple(b)
    }

    public init(uuid: uuid_t) { self.uuid = uuid }

    public init?(uuidString s: String) {
        let hex = Array(s.utf8)
        guard hex.count == 36 else { return nil }
        var b: [UInt8] = []
        var i = 0
        while i < 36 {
            if i == 8 || i == 13 || i == 18 || i == 23 {
                guard hex[i] == UInt8(ascii: "-") else { return nil }
                i += 1
                continue
            }
            guard let hi = UUID._nibble(hex[i]), let lo = UUID._nibble(hex[i + 1]) else { return nil }
            b.append(hi << 4 | lo)
            i += 2
        }
        uuid = UUID._tuple(b)
    }

    public var uuidString: String {
        let digits = Array("0123456789ABCDEF".utf8)
        var out: [UInt8] = []
        for (i, byte) in _bytes.enumerated() {
            if i == 4 || i == 6 || i == 8 || i == 10 { out.append(UInt8(ascii: "-")) }
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 15)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    public var description: String { uuidString }
    public var debugDescription: String { uuidString }

    internal var _bytes: [UInt8] { withUnsafeBytes(of: uuid) { Array($0) } }

    public static func == (a: UUID, b: UUID) -> Bool { a._bytes == b._bytes }
    public static func < (a: UUID, b: UUID) -> Bool { a._bytes.lexicographicallyPrecedes(b._bytes) }
    public func hash(into h: inout Hasher) { h.combine(_bytes) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let u = UUID(uuidString: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a UUID: \(s)")
        }
        self = u
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(uuidString)
    }

    private static func _nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    private static func _tuple(_ b: [UInt8]) -> uuid_t {
        (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }
}

extension UUID: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSUUID {
        _bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) }
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSUUID, result: inout UUID?) {
        var b = [UInt8](repeating: 0, count: 16)
        b.withUnsafeMutableBufferPointer { x.getBytes($0.baseAddress) }
        result = UUID(uuid: UUID._tuple(b))
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSUUID, result: inout UUID?) -> Bool {
        _forceBridgeFromObjectiveC(x, result: &result)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSUUID?) -> UUID {
        guard let source else { return UUID() }
        var result: UUID?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}
