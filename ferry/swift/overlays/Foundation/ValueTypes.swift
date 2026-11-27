// SPDX-License-Identifier: GPL-3.0-or-later
//
// Notification, Locale, TimeZone, URLQueryItem and URLComponents as the
// structs Swift sees on a Mac, each bridged to its NS class (freemac
// 1.260). An app compiled on a Mac reaches these through Foundation's
// Swift library by their names (Foundation.Notification and so on), so
// they have to be structs of those names, with the members Apple's
// documentation gives them, for a downloaded app to run. Each keeps the NS
// object it stands for; changing a copy makes a new one, so copies stay
// apart as values do. Written for Ferry from Apple's documentation.

// ---- Notification ----------------------------------------------------------------

public struct Notification: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias Name = NSNotification.Name
    public typealias ReferenceType = NSNotification

    public var name: Name
    public var object: Any?
    public var userInfo: [AnyHashable: Any]?

    public init(name: __shared Name, object: __shared Any? = nil, userInfo: __shared [AnyHashable: Any]? = nil) {
        self.name = name
        self.object = object
        self.userInfo = userInfo
    }

    // An app built with an older SDK passes init(name:object:userInfo:)
    // its arguments owned, not shared: Notification._ownedInit below.

    public static func == (a: Notification, b: Notification) -> Bool {
        guard a.name == b.name else { return false }
        switch (a.object, b.object) {
        case (nil, nil): break
        case let (x?, y?): if (x as AnyObject) !== (y as AnyObject) { return false }
        default: return false
        }
        return (a.userInfo == nil) == (b.userInfo == nil)
    }

    public func hash(into h: inout Hasher) { h.combine(name) }

    public var description: String {
        "name = \(name.rawValue), object = \(object.map { "\($0)" } ?? "nil"), userInfo = \(userInfo.map { "\($0)" } ?? "nil")"
    }
    public var debugDescription: String { description }
}

extension Notification: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNotification {
        NSNotification(name: name, object: object, userInfo: userInfo)
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSNotification, result: inout Notification?) {
        result = Notification(_ns: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNotification, result: inout Notification?) -> Bool {
        result = Notification(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNotification?) -> Notification {
        guard let source else { return Notification(name: Name(rawValue: "")) }
        return Notification(_ns: source)
    }
    internal init(_ns n: NSNotification) {
        self.init(name: n.name, object: n.object, userInfo: n.userInfo)
    }
}

// ---- Locale ----------------------------------------------------------------------

public struct Locale: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias ReferenceType = NSLocale
    nonisolated(unsafe) internal var _ns: NSLocale

    internal init(_ns l: NSLocale) { _ns = l }

    public init(identifier: String) { _ns = NSLocale(localeIdentifier: identifier) }

    public static var current: Locale { NSLocale.current }
    public static var autoupdatingCurrent: Locale { NSLocale.autoupdatingCurrent }
    public static var preferredLanguages: [String] { (NSLocale.preferredLanguages() as? [String]) ?? ["en"] }
    public static var availableIdentifiers: [String] { (NSLocale.availableLocaleIdentifiers() as? [String]) ?? [] }

    public var identifier: String { _ns.localeIdentifier }
    public var languageCode: String? { _ns.languageCode }
    public var regionCode: String? { _ns.regionCode ?? _ns.countryCode }
    public var scriptCode: String? { _ns.scriptCode }
    public var variantCode: String? { _ns.variantCode }
    public var decimalSeparator: String? { _ns.decimalSeparator }
    public var groupingSeparator: String? { _ns.groupingSeparator }
    public var usesMetricSystem: Bool { _ns.usesMetricSystem }
    public var currencyCode: String? { _ns.currencyCode }
    public var currencySymbol: String? { _ns.currencySymbol }

    public func localizedString(forIdentifier identifier: String) -> String? {
        _ns.displayName(forKey: NSLocaleIdentifier, value: identifier)
    }
    public func localizedString(forLanguageCode code: String) -> String? {
        _ns.displayName(forKey: NSLocaleLanguageCode, value: code)
    }
    public func localizedString(forRegionCode code: String) -> String? {
        _ns.displayName(forKey: NSLocaleCountryCode, value: code)
    }

    public static func == (a: Locale, b: Locale) -> Bool { a.identifier == b.identifier }
    public func hash(into h: inout Hasher) { h.combine(identifier) }
    public var description: String { "\(identifier) (fixed)" }
    public var debugDescription: String { description }
}

extension Locale: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSLocale { _ns }
    public static func _forceBridgeFromObjectiveC(_ x: NSLocale, result: inout Locale?) { result = Locale(_ns: x) }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSLocale, result: inout Locale?) -> Bool {
        result = Locale(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSLocale?) -> Locale {
        source.map { Locale(_ns: $0) } ?? NSLocale.current
    }
}

// ---- TimeZone --------------------------------------------------------------------

public struct TimeZone: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias ReferenceType = NSTimeZone
    nonisolated(unsafe) internal var _ns: NSTimeZone

    internal init(_ns z: NSTimeZone) { _ns = z }

    public init?(identifier: __shared String) {
        guard let z = NSTimeZone(name: identifier) else { return nil }
        _ns = z
    }
    public init?(secondsFromGMT seconds: Int) {
        guard abs(seconds) <= 18 * 3600, let z = NSTimeZone(forSecondsFromGMT: seconds) else { return nil }
        _ns = z
    }
    public init?(abbreviation: __shared String) {
        guard let z = NSTimeZone(abbreviation: abbreviation) else { return nil }
        _ns = z
    }

    public static var current: TimeZone { NSTimeZone.local() ?? NSTimeZone.default }
    public static var autoupdatingCurrent: TimeZone { current }
    public static var gmt: TimeZone { TimeZone(_ns: NSTimeZone(forSecondsFromGMT: 0)) }
    public static var knownTimeZoneIdentifiers: [String] { (NSTimeZone.knownTimeZoneNames() as? [String]) ?? [] }

    public var identifier: String { _ns.name }
    public func secondsFromGMT(for date: Date = Date()) -> Int { _ns.secondsFromGMT(for: date) }
    public func abbreviation(for date: Date = Date()) -> String? { _ns.abbreviation(for: date) }
    public func isDaylightSavingTime(for date: Date = Date()) -> Bool { _ns.isDaylightSavingTime(for: date) }
    public func daylightSavingTimeOffset(for date: Date = Date()) -> TimeInterval {
        _ns.daylightSavingTimeOffset(for: date)
    }
    public func nextDaylightSavingTimeTransition(after date: Date) -> Date? {
        _ns.nextDaylightSavingTimeTransition(after: date)
    }
    public var nextDaylightSavingTimeTransition: Date? { nextDaylightSavingTimeTransition(after: Date()) }

    public static func == (a: TimeZone, b: TimeZone) -> Bool { a.identifier == b.identifier }
    public func hash(into h: inout Hasher) { h.combine(identifier) }
    public var description: String { identifier }
    public var debugDescription: String { identifier }
}

extension TimeZone: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSTimeZone { _ns }
    public static func _forceBridgeFromObjectiveC(_ x: NSTimeZone, result: inout TimeZone?) {
        result = TimeZone(_ns: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSTimeZone, result: inout TimeZone?) -> Bool {
        result = TimeZone(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSTimeZone?) -> TimeZone {
        source.map { TimeZone(_ns: $0) } ?? .current
    }
}

// ---- URLQueryItem and URLComponents ----------------------------------------------

public struct URLQueryItem: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias ReferenceType = NSURLQueryItem
    public var name: String
    public var value: String?

    public init(name: __shared String, value: __shared String?) {
        self.name = name
        self.value = value
    }

    public var description: String { value.map { "\(name)=\($0)" } ?? name }
    public var debugDescription: String { description }
}

extension URLQueryItem: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURLQueryItem { NSURLQueryItem(name: name, value: value) }
    public static func _forceBridgeFromObjectiveC(_ x: NSURLQueryItem, result: inout URLQueryItem?) {
        result = URLQueryItem(name: x.name ?? "", value: x.value)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSURLQueryItem, result: inout URLQueryItem?) -> Bool {
        result = URLQueryItem(name: x.name ?? "", value: x.value)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLQueryItem?) -> URLQueryItem {
        URLQueryItem(name: source?.name ?? "", value: source?.value)
    }
}

public struct URLComponents: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias ReferenceType = NSURLComponents
    nonisolated(unsafe) internal var _ns: NSURLComponents

    internal init(_ns c: NSURLComponents) { _ns = c }

    public init() { _ns = NSURLComponents() }
    public init?(url: __shared URL, resolvingAgainstBaseURL resolve: Bool) {
        guard let c = NSURLComponents(url: url, resolvingAgainstBaseURL: resolve) else { return nil }
        _ns = c
    }
    public init?(string: __shared String) {
        guard let c = NSURLComponents(string: string) else { return nil }
        _ns = c
    }

    // a change goes to a copy of its own
    private mutating func _change(_ f: (NSURLComponents) -> Void) {
        let c = _ns.copy() as! NSURLComponents
        f(c)
        _ns = c
    }

    public var url: URL? { _ns.url }
    public func url(relativeTo base: URL?) -> URL? {
        guard let base else { return _ns.url }
        return _ns.string.flatMap { URL(string: $0, relativeTo: base) }
    }
    public var string: String? { _ns.string }

    public var scheme: String? { get { _ns.scheme } set { _change { $0.scheme = newValue } } }
    public var user: String? { get { _ns.user } set { _change { $0.user = newValue } } }
    public var password: String? { get { _ns.password } set { _change { $0.password = newValue } } }
    public var host: String? { get { _ns.host } set { _change { $0.host = newValue } } }
    public var port: Int? {
        get { _ns.port.map { $0.integerValue } }
        set { _change { $0.port = newValue.map { NSNumber(value: $0) } } }
    }
    public var path: String { get { _ns.path ?? "" } set { _change { $0.path = newValue } } }
    public var query: String? { get { _ns.query } set { _change { $0.query = newValue } } }
    public var fragment: String? { get { _ns.fragment } set { _change { $0.fragment = newValue } } }
    public var percentEncodedUser: String? {
        get { _ns.percentEncodedUser } set { _change { $0.percentEncodedUser = newValue } }
    }
    public var percentEncodedPassword: String? {
        get { _ns.percentEncodedPassword } set { _change { $0.percentEncodedPassword = newValue } }
    }
    public var percentEncodedHost: String? {
        get { _ns.percentEncodedHost } set { _change { $0.percentEncodedHost = newValue } }
    }
    public var percentEncodedPath: String {
        get { _ns.percentEncodedPath ?? "" } set { _change { $0.percentEncodedPath = newValue } }
    }
    public var percentEncodedQuery: String? {
        get { _ns.percentEncodedQuery } set { _change { $0.percentEncodedQuery = newValue } }
    }
    public var percentEncodedFragment: String? {
        get { _ns.percentEncodedFragment } set { _change { $0.percentEncodedFragment = newValue } }
    }
    public var queryItems: [URLQueryItem]? {
        get { (_ns.queryItems as? [NSURLQueryItem])?.map { URLQueryItem._unconditionallyBridgeFromObjectiveC($0) } }
        set { _change { $0.queryItems = newValue } }
    }
    public var percentEncodedQueryItems: [URLQueryItem]? {
        get {
            (_ns.percentEncodedQueryItems as? [NSURLQueryItem])?.map {
                URLQueryItem._unconditionallyBridgeFromObjectiveC($0)
            }
        }
        set { _change { $0.percentEncodedQueryItems = newValue } }
    }

    public static func == (a: URLComponents, b: URLComponents) -> Bool { a.string == b.string }
    public func hash(into h: inout Hasher) { h.combine(string) }
    public var description: String { string ?? "" }
    public var debugDescription: String { description }
}

extension URLComponents: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURLComponents { _ns }
    public static func _forceBridgeFromObjectiveC(_ x: NSURLComponents, result: inout URLComponents?) {
        result = URLComponents(_ns: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSURLComponents, result: inout URLComponents?) -> Bool {
        result = URLComponents(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLComponents?) -> URLComponents {
        URLComponents(_ns: source ?? NSURLComponents())
    }
}

/// Notification(name:object:userInfo:) as an app built with an older Mac SDK
/// calls it, with its arguments owned (freemac 1.262, IINA).
@_silgen_name("$s10Foundation12NotificationV4name6object8userInfoACSo18NSNotificationNamea_ypSgSDys11AnyHashableVypGSgtcfC")
public func _ferryNotificationOwnedInit(name: __owned Notification.Name, object: __owned Any?,
                                        userInfo: __owned [AnyHashable: Any]?) -> Notification {
    Notification(name: name, object: object, userInfo: userInfo)
}
