// SPDX-License-Identifier: GPL-3.0-or-later
//
// Data's parts that Apple's own Foundation builds on NSData (freemac 1.262):
// its NSData bridge, Base64, and reading and writing files. Data itself is
// swift-foundation's (Data.swift), so that it has the layout Swift code
// built on a Mac expects. Written for Ferry from Apple's documentation of
// these methods; the option types are NSData's, as on a Mac.

extension Data {
    /// Data with an NSData's bytes, copied (an NSData never changes, but
    /// Ferry's Data always owns its bytes).
    public init(referencing reference: __shared NSData) {
        let n = reference.length
        if n > 0, let p = reference.bytes {
            self.init(bytes: p, count: n)
        } else {
            self.init()
        }
    }

    // ---- Base64, through NSData's

    public init?(base64Encoded base64String: __shared String, options: Base64DecodingOptions = []) {
        guard let d = NSData(base64EncodedString: base64String, options: Int(options.rawValue)) else { return nil }
        self.init(referencing: d)
    }

    public init?(base64Encoded base64Data: __shared Data, options: Base64DecodingOptions = []) {
        guard let d = NSData(base64EncodedData: base64Data, options: Int(options.rawValue)) else { return nil }
        self.init(referencing: d)
    }

    public func base64EncodedString(options: Base64EncodingOptions = []) -> String {
        _ferryNS().base64EncodedString(withOptions: Int(options.rawValue)) ?? ""
    }

    public func base64EncodedData(options: Base64EncodingOptions = []) -> Data {
        Data(base64EncodedString(options: options).utf8)
    }

    // ---- NSData

    internal func _ferryNS() -> NSData {
        withUnsafeBytes { NSData(bytes: $0.baseAddress, length: $0.count) }
    }

    // ---- files

    internal static func _ferryRead(_ url: URL) throws -> Data {
        guard url.isFileURL else {
            guard let d = NSData(contentsOf: url) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSURLErrorKey: url])
            }
            return Data(referencing: d)
        }
        let path = url.path
        guard let f = fopen(path, "rb") else {
            throw NSError(domain: NSCocoaErrorDomain, code: errno == ENOENT ? NSFileReadNoSuchFileError : NSFileReadNoPermissionError,
                          userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: _posixError()])
        }
        defer { fclose(f) }
        var out = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = chunk.withUnsafeMutableBytes { fread($0.baseAddress, 1, 65536, f) }
            if n == 0 { break }
            chunk.withUnsafeBytes { out.append($0.bindMemory(to: UInt8.self).baseAddress!, count: n) }
        }
        return out
    }

    internal func _ferryWrite(_ url: URL, _ options: WritingOptions) throws {
        let path = url.path
        if options.contains(.withoutOverwriting) && access(path, F_OK) == 0 {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: [NSFilePathErrorKey: path])
        }
        let target = options.contains(.atomic) ? path + ".ferry-tmp-\(getpid())" : path
        guard let f = fopen(target, "wb") else {
            throw NSError(domain: NSCocoaErrorDomain, code: errno == EACCES ? NSFileWriteNoPermissionError : NSFileWriteUnknownError,
                          userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: _posixError()])
        }
        let written = withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, f) }
        let closed = fclose(f)
        guard written == count, closed == 0 else {
            if target != path { unlink(target) }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [NSFilePathErrorKey: path])
        }
        if target != path && rename(target, path) != 0 {
            unlink(target)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSFilePathErrorKey: path])
        }
    }
}

extension Data: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSData { _ferryNS() }
    public static func _forceBridgeFromObjectiveC(_ x: NSData, result: inout Data?) { result = Data(referencing: x) }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSData, result: inout Data?) -> Bool {
        result = Data(referencing: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSData?) -> Data {
        source.map { Data(referencing: $0) } ?? Data()
    }
}

extension Data._Representation {
    /// The bytes as an NSData, for NSData's own searching (a Mac's
    /// Foundation lends its bytes in place; Ferry copies them).
    internal func withInteriorPointerReference<T>(_ work: (NSData) throws -> T) rethrows -> T {
        try withUnsafeBytes { try work(NSData(bytes: $0.baseAddress, length: $0.count)) }
    }
}

extension __DataStorage {
    // How a Mac's Foundation allocates Data's bytes.
    static func allocate(_ size: Int, _ clear: Bool) -> UnsafeMutableRawPointer? {
        clear ? calloc(1, size) : malloc(size)
    }

    static func reallocate(_ ptr: UnsafeMutableRawPointer, _ newSize: Int) -> UnsafeMutableRawPointer? {
        realloc(ptr, newSize)
    }

    /// What Data's inlined code calls on Macs before macOS 14.
    @usableFromInline
    internal func replaceBytes(in range_: NSRange, with replacementBytes: UnsafeRawPointer?, length replacementLength: Int) {
        replaceBytes(in: range_.location ..< range_.location + range_.length, with: replacementBytes,
                     length: replacementLength)
    }
}

/// A Mac's malloc rounds a size up to what it would allocate; here the size
/// is kept.
internal func malloc_good_size(_ size: Int) -> Int { size }

/// The memory page size and copying whole pages, which Data uses for large
/// buffers.
internal enum Platform {
    static let pageSize = Int(sysconf(Int32(_SC_PAGESIZE)))
    static func roundDownToMultipleOfPageSize(_ size: Int) -> Int { size & ~(pageSize - 1) }
    static func roundUpToMultipleOfPageSize(_ size: Int) -> Int { (size + pageSize - 1) & ~(pageSize - 1) }
    static func copyMemoryPages(_ source: UnsafeRawPointer, _ dest: UnsafeMutableRawPointer, _ length: Int) {
        memmove(dest, source, length)
    }
}

/// The C library's last error, as an NSError of the POSIX domain.
internal func _posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)!
}
