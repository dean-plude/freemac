// SPDX-License-Identifier: GPL-3.0-or-later
//
// Data (freemac 1.230): a value holding bytes, as Swift code on a Mac
// sees Foundation's NSData. It is a collection of UInt8 with value
// semantics (a copy changes alone), and a slice of it keeps the indices
// it had in the whole, as on a Mac. The bytes live in a Swift array slice;
// passing one to an Objective-C method makes an NSData of them, and an
// NSData coming back is copied into one (the API notes name Data as
// NSData's Swift type). Written for Ferry from Apple's documentation of
// the type.

/// Bytes that can be read in place.
public protocol ContiguousBytes {
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
}

/// A collection of bytes: Data, [UInt8] and the like.
public protocol DataProtocol: RandomAccessCollection where Element == UInt8 {}

/// A collection of bytes that can grow.
public protocol MutableDataProtocol: DataProtocol, MutableCollection, RangeReplaceableCollection {}

extension Array: ContiguousBytes where Element == UInt8 {}
extension ArraySlice: ContiguousBytes where Element == UInt8 {}
extension UnsafeRawBufferPointer: ContiguousBytes {
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try body(self) }
}
extension Array: DataProtocol where Element == UInt8 {}
extension ArraySlice: DataProtocol where Element == UInt8 {}
extension Array: MutableDataProtocol where Element == UInt8 {}
extension ArraySlice: MutableDataProtocol where Element == UInt8 {}
extension UnsafeRawBufferPointer: DataProtocol {}

public struct Data: Hashable, Sendable, RandomAccessCollection, MutableCollection, RangeReplaceableCollection,
                    MutableDataProtocol, ContiguousBytes, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias SubSequence = Data
    public typealias Element = UInt8

    @usableFromInline internal var _bytes: ArraySlice<UInt8>

    internal init(_slice: ArraySlice<UInt8>) { _bytes = _slice }

    public init() { _bytes = [] }

    public init(count: Int) { _bytes = ArraySlice(repeating: 0, count: count) }

    public init(capacity: Int) {
        _bytes = []
        _bytes.reserveCapacity(capacity)
    }

    public init(repeating value: UInt8, count: Int) { _bytes = ArraySlice(repeating: value, count: count) }

    public init(bytes: UnsafeRawPointer, count: Int) {
        _bytes = ArraySlice(UnsafeRawBufferPointer(start: bytes, count: count))
    }

    public init<T>(buffer: UnsafeBufferPointer<T>) {
        _bytes = ArraySlice(UnsafeRawBufferPointer(buffer))
    }

    public init<T>(buffer: UnsafeMutableBufferPointer<T>) {
        _bytes = ArraySlice(UnsafeRawBufferPointer(buffer))
    }

    /// Bytes another owner holds: they are copied, and the deallocator is
    /// then called (Ferry's Data always owns its bytes).
    public init(bytesNoCopy bytes: UnsafeMutableRawPointer, count: Int, deallocator: Deallocator) {
        _bytes = ArraySlice(UnsafeRawBufferPointer(start: bytes, count: count))
        deallocator._free(bytes, count)
    }

    public init<S: Sequence>(_ elements: S) where S.Element == UInt8 { _bytes = ArraySlice(elements) }

    public init(referencing data: NSData) { self = Data._fromNS(data) }

    /// What to do with bytes given to Data(bytesNoCopy:count:deallocator:).
    public enum Deallocator {
        case virtualMemory, unmap, free, none
        case custom((UnsafeMutableRawPointer, Int) -> Void)

        func _free(_ p: UnsafeMutableRawPointer, _ n: Int) {
            switch self {
            case .free: Darwin.free(p)
            case .unmap, .virtualMemory: munmap(p, n)
            case .none: break
            case .custom(let f): f(p, n)
            }
        }
    }

    public typealias SearchOptions = NSDataSearchOptions

    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mappedIfSafe = ReadingOptions(rawValue: 1)
        public static let uncached = ReadingOptions(rawValue: 2)
        public static let alwaysMapped = ReadingOptions(rawValue: 8)
    }

    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let atomic = WritingOptions(rawValue: 1)
        public static let withoutOverwriting = WritingOptions(rawValue: 2)
    }

    public struct Base64EncodingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let lineLength64Characters = Base64EncodingOptions(rawValue: 1 << 0)
        public static let lineLength76Characters = Base64EncodingOptions(rawValue: 1 << 1)
        public static let endLineWithCarriageReturn = Base64EncodingOptions(rawValue: 1 << 4)
        public static let endLineWithLineFeed = Base64EncodingOptions(rawValue: 1 << 5)
    }

    public struct Base64DecodingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let ignoreUnknownCharacters = Base64DecodingOptions(rawValue: 1)
    }

    // ---- the collection

    public var startIndex: Int { _bytes.startIndex }
    public var endIndex: Int { _bytes.endIndex }
    public var count: Int {
        get { _bytes.count }
        set {
            if newValue < _bytes.count { _bytes.removeLast(_bytes.count - newValue) }
            else { _bytes.append(contentsOf: repeatElement(0, count: newValue - _bytes.count)) }
        }
    }
    public var isEmpty: Bool { _bytes.isEmpty }
    public var indices: Range<Int> { _bytes.indices }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position: Int) -> UInt8 {
        get { _bytes[position] }
        set { _bytes[position] = newValue }
    }

    public subscript(bounds: Range<Int>) -> Data {
        get { Data(_slice: _bytes[bounds]) }
        set { _bytes[bounds] = newValue._bytes }
    }

    public subscript<R: RangeExpression>(range: R) -> Data where R.Bound == Int {
        get { self[range.relative(to: self)] }
        set { self[range.relative(to: self)] = newValue }
    }

    public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C)
        where C.Element == UInt8 {
        _bytes.replaceSubrange(subrange, with: newElements)
    }

    public mutating func reserveCapacity(_ n: Int) { _bytes.reserveCapacity(n) }

    public mutating func append(_ other: Data) { _bytes.append(contentsOf: other._bytes) }

    public mutating func append(_ bytes: UnsafePointer<UInt8>, count: Int) {
        _bytes.append(contentsOf: UnsafeBufferPointer(start: bytes, count: count))
    }

    public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == UInt8 {
        _bytes.append(contentsOf: elements)
    }

    public mutating func resetBytes(in range: Range<Int>) {
        for i in range { _bytes[i] = 0 }
    }

    public func subdata(in range: Range<Int>) -> Data { Data(_bytes[range]) }

    public func range(of other: Data, options: SearchOptions = [], in range: Range<Int>? = nil) -> Range<Int>? {
        let r = range ?? indices
        let n = other.count
        guard n > 0, r.count >= n else { return nil }
        let starts = Array(r.lowerBound...(r.upperBound - n))
        let order = options.contains(.backwards) ? starts.reversed() : starts
        for s in order {
            if _bytes[s..<(s + n)].elementsEqual(other._bytes) { return s..<(s + n) }
            if options.contains(.anchored) { break }
        }
        return nil
    }

    public func advanced(by n: Int) -> Data { Data(_bytes.dropFirst(n)) }

    // ---- the bytes in place

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try _bytes.withUnsafeBytes(body)
    }

    public mutating func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try _bytes.withUnsafeMutableBytes(body)
    }

    @available(*, deprecated, message: "use withUnsafeBytes(_: (UnsafeRawBufferPointer) throws -> R)")
    public func withUnsafeBytes<R, T>(_ body: (UnsafePointer<T>) throws -> R) rethrows -> R {
        try _bytes.withUnsafeBytes { try body($0.baseAddress!.assumingMemoryBound(to: T.self)) }
    }

    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
        _bytes.withUnsafeBytes { raw in
            pointer.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: Swift.min(count, raw.count))
        }
    }

    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, from range: Range<Int>) {
        Data(_bytes[range]).copyBytes(to: pointer, count: range.count)
    }

    @discardableResult
    public func copyBytes<T>(to buffer: UnsafeMutableBufferPointer<T>, from range: Range<Int>? = nil) -> Int {
        let r = range ?? indices
        let n = Swift.min(r.count, buffer.count * MemoryLayout<T>.stride)
        let raw = UnsafeMutableRawBufferPointer(buffer)
        for (k, i) in (r.lowerBound..<(r.lowerBound + n)).enumerated() { raw[k] = _bytes[i] }
        return n
    }

    // ---- files

    public init(contentsOf url: URL, options: ReadingOptions = []) throws {
        guard url.isFileURL else {
            guard let d = NSData(contentsOf: url) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSURLErrorKey: url])
            }
            self = Data._fromNS(d)
            return
        }
        let path = url.path
        guard let f = fopen(path, "rb") else {
            throw NSError(domain: NSCocoaErrorDomain, code: errno == ENOENT ? NSFileReadNoSuchFileError : NSFileReadNoPermissionError,
                          userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: _posixError()])
        }
        defer { fclose(f) }
        var out: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = chunk.withUnsafeMutableBytes { fread($0.baseAddress, 1, 65536, f) }
            if n == 0 { break }
            out.append(contentsOf: chunk[0..<n])
        }
        _bytes = ArraySlice(out)
    }

    public func write(to url: URL, options: WritingOptions = []) throws {
        let path = url.path
        if options.contains(.withoutOverwriting) && access(path, F_OK) == 0 {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: [NSFilePathErrorKey: path])
        }
        let target = options.contains(.atomic) ? path + ".ferry-tmp-\(getpid())" : path
        guard let f = fopen(target, "wb") else {
            throw NSError(domain: NSCocoaErrorDomain, code: errno == EACCES ? NSFileWriteNoPermissionError : NSFileWriteUnknownError,
                          userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: _posixError()])
        }
        let written = _bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, f) }
        let closed = fclose(f)
        guard written == _bytes.count, closed == 0 else {
            if target != path { unlink(target) }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [NSFilePathErrorKey: path])
        }
        if target != path && rename(target, path) != 0 {
            unlink(target)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSFilePathErrorKey: path])
        }
    }

    // ---- Base64, through NSData's

    public init?(base64Encoded string: String, options: Base64DecodingOptions = []) {
        guard let d = NSData(base64EncodedString: string, options: Int(options.rawValue)) else { return nil }
        self = Data._fromNS(d)
    }

    public init?(base64Encoded data: Data, options: Base64DecodingOptions = []) {
        guard let d = NSData(base64EncodedData: data, options: Int(options.rawValue)) else { return nil }
        self = Data._fromNS(d)
    }

    public func base64EncodedString(options: Base64EncodingOptions = []) -> String {
        _toNS().base64EncodedString(withOptions: Int(options.rawValue)) ?? ""
    }

    public func base64EncodedData(options: Base64EncodingOptions = []) -> Data {
        Data(base64EncodedString(options: options).utf8)
    }

    // ---- comparing and showing

    public static func == (a: Data, b: Data) -> Bool { a._bytes.elementsEqual(b._bytes) }

    public func hash(into h: inout Hasher) {
        h.combine(count)
        for b in _bytes { h.combine(b) }
    }

    public var description: String { "\(count) bytes" }
    public var debugDescription: String { description }

    public static func + (a: Data, b: Data) -> Data {
        var r = a
        r.append(b)
        return r
    }

    // ---- NSData

    internal func _toNS() -> NSData {
        _bytes.withUnsafeBytes { NSData(bytes: $0.baseAddress, length: $0.count) }
    }

    internal static func _fromNS(_ d: NSData) -> Data {
        let n = d.length
        guard n > 0, let p = d.bytes else { return Data() }
        return Data(bytes: p, count: n)
    }
}

extension Data: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSData { _toNS() }
    public static func _forceBridgeFromObjectiveC(_ x: NSData, result: inout Data?) { result = _fromNS(x) }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSData, result: inout Data?) -> Bool {
        result = _fromNS(x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSData?) -> Data {
        source.map(_fromNS) ?? Data()
    }
}

extension Data: Codable {
    /// Without a coder's own way with bytes (JSONEncoder writes Base64),
    /// the bytes one by one, as Apple's Data encodes itself.
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [UInt8] = []
        while !c.isAtEnd { out.append(try c.decode(UInt8.self)) }
        self.init(out)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for b in _bytes { try c.encode(b) }
    }
}

/// The C library's last error, as an NSError of the POSIX domain.
internal func _posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)!
}
