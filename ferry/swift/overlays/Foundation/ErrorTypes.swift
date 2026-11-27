// SPDX-License-Identifier: GPL-3.0-or-later
//
// Swift's error types for NSError's domains, as Swift code built on a Mac
// uses them (freemac 1.262, for IINA): CocoaError and URLError, the
// protocols they and an app's own errors conform to (CustomNSError,
// LocalizedError), and the protocols that tie an error code to its error.
// Written for Ferry from Apple's documentation of these types and of how
// Swift errors become NSErrors.

/// An error that says which NSError it is: its domain, code and user info.
public protocol CustomNSError: Error {
    static var errorDomain: String { get }
    var errorCode: Int { get }
    var errorUserInfo: [String: Any] { get }
}

extension CustomNSError {
    public static var errorDomain: String { String(reflecting: self) }
    public var errorCode: Int { _getDefaultErrorCode(self) }
    public var errorUserInfo: [String: Any] { [:] }
}

extension Error where Self: CustomNSError {
    public var _domain: String { Self.errorDomain }
    public var _code: Int { errorCode }
}

/// An error that describes itself for people to read.
public protocol LocalizedError: Error {
    var errorDescription: String? { get }
    var failureReason: String? { get }
    var recoverySuggestion: String? { get }
    var helpAnchor: String? { get }
}

extension LocalizedError {
    public var errorDescription: String? { nil }
    public var failureReason: String? { nil }
    public var recoverySuggestion: String? { nil }
    public var helpAnchor: String? { nil }
}

/// An error that can be made from an NSError, which Swift's runtime uses
/// when an NSError is caught as that error.
public protocol _ObjectiveCBridgeableError: Error {
    init?(_bridgedNSError: __shared NSError)
}

/// An error code of an error type that keeps the NSError it was made from.
public protocol _ErrorCodeProtocol: Equatable {
    associatedtype _ErrorType: _BridgedStoredNSError where _ErrorType.Code == Self
}

extension _ErrorCodeProtocol {
    /// Lets "catch CocoaError.fileNoSuchFile" match an error of that code.
    public static func ~= (match: Self, error: Error) -> Bool {
        guard let e = error as? Self._ErrorType else { return false }
        return match == e.code
    }
}

/// An error type that keeps the NSError it was made from (CocoaError,
/// URLError and the like).
public protocol _BridgedStoredNSError: CustomNSError, _ObjectiveCBridgeableError, Hashable {
    associatedtype Code: _ErrorCodeProtocol, RawRepresentable where Code.RawValue: FixedWidthInteger
    var _nsError: NSError { get }
    init(_nsError error: NSError)
}

extension _BridgedStoredNSError {
    public var code: Code { Code(rawValue: Code.RawValue(truncatingIfNeeded: _nsError.code))! }

    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.init(_nsError: NSError(domain: Self.errorDomain, code: Int(truncatingIfNeeded: code.rawValue),
                                    userInfo: userInfo)!)
    }

    public init?(_bridgedNSError error: NSError) {
        guard error.domain.map({ String($0) }) == Self.errorDomain else { return nil }
        self.init(_nsError: error)
    }

    public var errorCode: Int { _nsError.code }

    public var errorUserInfo: [String: Any] {
        var out: [String: Any] = [:]
        if let info = _nsError.userInfo as? [String: Any] { out = info }
        return out
    }

    public var userInfo: [String: Any] { errorUserInfo }

    public func _getEmbeddedNSError() -> AnyObject? { _nsError }

    public static func == (a: Self, b: Self) -> Bool { a._nsError.isEqual(b._nsError) }

    public func hash(into h: inout Hasher) { h.combine(_nsError.hash) }
}

// ---- CocoaError

/// An error of Foundation's own domain, NSCocoaErrorDomain.
public struct CocoaError: _BridgedStoredNSError {
    public let _nsError: NSError

    public init(_nsError error: NSError) { _nsError = error }

    public static var errorDomain: String { String(NSCocoaErrorDomain) }

    public struct Code: RawRepresentable, Hashable, _ErrorCodeProtocol, Sendable {
        public typealias _ErrorType = CocoaError
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static var fileNoSuchFile: Code { Code(rawValue: 4) }
        public static var fileLocking: Code { Code(rawValue: 255) }
        public static var fileReadUnknown: Code { Code(rawValue: 256) }
        public static var fileReadNoPermission: Code { Code(rawValue: 257) }
        public static var fileReadInvalidFileName: Code { Code(rawValue: 258) }
        public static var fileReadCorruptFile: Code { Code(rawValue: 259) }
        public static var fileReadNoSuchFile: Code { Code(rawValue: 260) }
        public static var fileReadInapplicableStringEncoding: Code { Code(rawValue: 261) }
        public static var fileReadUnsupportedScheme: Code { Code(rawValue: 262) }
        public static var fileReadTooLarge: Code { Code(rawValue: 263) }
        public static var fileReadUnknownStringEncoding: Code { Code(rawValue: 264) }
        public static var fileWriteUnknown: Code { Code(rawValue: 512) }
        public static var fileWriteNoPermission: Code { Code(rawValue: 513) }
        public static var fileWriteInvalidFileName: Code { Code(rawValue: 514) }
        public static var fileWriteFileExists: Code { Code(rawValue: 516) }
        public static var fileWriteInapplicableStringEncoding: Code { Code(rawValue: 517) }
        public static var fileWriteUnsupportedScheme: Code { Code(rawValue: 518) }
        public static var fileWriteOutOfSpace: Code { Code(rawValue: 640) }
        public static var fileWriteVolumeReadOnly: Code { Code(rawValue: 642) }
        public static var keyValueValidation: Code { Code(rawValue: 1024) }
        public static var formatting: Code { Code(rawValue: 2048) }
        public static var userCancelled: Code { Code(rawValue: 3072) }
        public static var featureUnsupported: Code { Code(rawValue: 3328) }
        public static var propertyListReadCorrupt: Code { Code(rawValue: 3840) }
        public static var propertyListWriteInvalid: Code { Code(rawValue: 3852) }
        public static var coderReadCorrupt: Code { Code(rawValue: 4864) }
        public static var coderValueNotFound: Code { Code(rawValue: 4865) }
        public static var coderInvalidValue: Code { Code(rawValue: 4866) }
    }

    public static var fileNoSuchFile: Code { .fileNoSuchFile }
    public static var fileLocking: Code { .fileLocking }
    public static var fileReadUnknown: Code { .fileReadUnknown }
    public static var fileReadNoPermission: Code { .fileReadNoPermission }
    public static var fileReadNoSuchFile: Code { .fileReadNoSuchFile }
    public static var fileReadCorruptFile: Code { .fileReadCorruptFile }
    public static var fileReadUnsupportedScheme: Code { .fileReadUnsupportedScheme }
    public static var fileWriteUnknown: Code { .fileWriteUnknown }
    public static var fileWriteNoPermission: Code { .fileWriteNoPermission }
    public static var fileWriteFileExists: Code { .fileWriteFileExists }
    public static var fileWriteUnsupportedScheme: Code { .fileWriteUnsupportedScheme }
    public static var fileWriteOutOfSpace: Code { .fileWriteOutOfSpace }
    public static var userCancelled: Code { .userCancelled }
    public static var featureUnsupported: Code { .featureUnsupported }
    public static var coderReadCorrupt: Code { .coderReadCorrupt }
    public static var coderValueNotFound: Code { .coderValueNotFound }
    public static var coderInvalidValue: Code { .coderInvalidValue }

    public var filePath: String? { _nsError.userInfo?[NSFilePathErrorKey] as? String }
    public var url: URL? { _nsError.userInfo?[NSURLErrorKey] as? URL }
    public var underlying: Error? { _nsError.userInfo?[NSUnderlyingErrorKey] as? NSError }
}

// ---- URLError

/// An error of the URL loading system's domain, NSURLErrorDomain.
public struct URLError: _BridgedStoredNSError {
    public let _nsError: NSError

    public init(_nsError error: NSError) { _nsError = error }

    public static var errorDomain: String { String(NSURLErrorDomain) }

    public struct Code: RawRepresentable, Hashable, _ErrorCodeProtocol, Sendable {
        public typealias _ErrorType = URLError
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static var unknown: Code { Code(rawValue: -1) }
        public static var cancelled: Code { Code(rawValue: -999) }
        public static var badURL: Code { Code(rawValue: -1000) }
        public static var timedOut: Code { Code(rawValue: -1001) }
        public static var unsupportedURL: Code { Code(rawValue: -1002) }
        public static var cannotFindHost: Code { Code(rawValue: -1003) }
        public static var cannotConnectToHost: Code { Code(rawValue: -1004) }
        public static var networkConnectionLost: Code { Code(rawValue: -1005) }
        public static var dnsLookupFailed: Code { Code(rawValue: -1006) }
        public static var badServerResponse: Code { Code(rawValue: -1011) }
        public static var userCancelledAuthentication: Code { Code(rawValue: -1012) }
        public static var notConnectedToInternet: Code { Code(rawValue: -1009) }
        public static var fileDoesNotExist: Code { Code(rawValue: -1100) }
        public static var secureConnectionFailed: Code { Code(rawValue: -1200) }
    }

    public static var unknown: Code { .unknown }
    public static var cancelled: Code { .cancelled }
    public static var badURL: Code { .badURL }
    public static var timedOut: Code { .timedOut }
    public static var unsupportedURL: Code { .unsupportedURL }
    public static var cannotFindHost: Code { .cannotFindHost }
    public static var cannotConnectToHost: Code { .cannotConnectToHost }
    public static var networkConnectionLost: Code { .networkConnectionLost }
    public static var notConnectedToInternet: Code { .notConnectedToInternet }
    public static var badServerResponse: Code { .badServerResponse }
    public static var fileDoesNotExist: Code { .fileDoesNotExist }

    public var failingURL: URL? { _nsError.userInfo?[NSURLErrorFailingURLErrorKey] as? URL }
}
