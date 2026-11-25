// SPDX-License-Identifier: GPL-3.0-or-later
//
// Errors (freemac 1.227): NSError and CFError as Swift errors, and the two
// conversions the compiler calls for an Objective-C method that reports an
// NSError through its last argument, which Swift sees as one that throws.
// A Swift error passed to Objective-C becomes an NSError made by Swift's
// runtime, which finds the CFError conformance below by its name. Written
// for Ferry from Swift's documentation of error bridging.

extension NSError: Error {
    public var _domain: String { domain ?? "" }
    public var _code: Int { code }
    public var _userInfo: AnyObject? { userInfo as NSDictionary }
}

extension CFError: Error {
    public var _domain: String { String._unconditionallyBridgeFromObjectiveC(CFErrorGetDomain(self) as NSString?) }
    public var _code: Int { CFErrorGetCode(self) }
    public var _userInfo: AnyObject? { CFErrorCopyUserInfo(self) as AnyObject? }
}

/// What a method that failed without saying why throws.
public struct _GenericObjCError: Error, CustomStringConvertible {
    public var description: String { "an Objective-C method failed without giving an error" }
}

public func _convertNSErrorToError(_ error: NSError?) -> Error {
    error ?? _GenericObjCError()
}

public func _convertErrorToNSError(_ error: Error) -> NSError {
    unsafeDowncast(_bridgeErrorToNSError(error), to: NSError.self)
}

/// The user info Foundation gives an error that brings none of its own;
/// Swift's runtime asks for it by name.
public func _getErrorDefaultUserInfo<T: Error>(_ error: T) -> AnyObject? {
    nil
}

extension Error {
    /// The error's message, as NSError's -localizedDescription gives it.
    public var localizedDescription: String {
        let d: String? = (self as NSError).localizedDescription
        return d ?? ""
    }
}
