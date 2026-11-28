// SPDX-License-Identifier: GPL-3.0-or-later
//
// Calendar, DateComponents, Measurement and POSIXError as the structs Swift
// sees on a Mac (freemac 1.271, for Stats). An app built there reaches them
// in Foundation's Swift library by those names, so they are structs, with
// the members Apple's documentation gives them, each bridged to its NS
// class where it has one. Written for Ferry from Apple's documentation.

// ---- Calendar ----------------------------------------------------------------------

public struct Calendar: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias ReferenceType = NSCalendar
    nonisolated(unsafe) internal var _ns: NSCalendar

    internal init(_ns c: NSCalendar) { _ns = c }

    public enum Identifier: Hashable, Sendable, CustomDebugStringConvertible {
        case gregorian, buddhist, chinese, coptic, ethiopicAmeteMihret, ethiopicAmeteAlem, hebrew, iso8601
        case indian, islamic, islamicCivil, japanese, persian, republicOfChina, islamicTabular, islamicUmmAlQura

        internal var _name: String {
            switch self {
            case .gregorian: return NSCalendarIdentifierGregorian
            case .buddhist: return NSCalendarIdentifierBuddhist
            case .chinese: return NSCalendarIdentifierChinese
            case .coptic: return NSCalendarIdentifierCoptic
            case .ethiopicAmeteMihret: return NSCalendarIdentifierEthiopicAmeteMihret
            case .ethiopicAmeteAlem: return NSCalendarIdentifierEthiopicAmeteAlem
            case .hebrew: return NSCalendarIdentifierHebrew
            case .iso8601: return NSCalendarIdentifierISO8601
            case .indian: return NSCalendarIdentifierIndian
            case .islamic: return NSCalendarIdentifierIslamic
            case .islamicCivil: return NSCalendarIdentifierIslamicCivil
            case .japanese: return NSCalendarIdentifierJapanese
            case .persian: return NSCalendarIdentifierPersian
            case .republicOfChina: return NSCalendarIdentifierRepublicOfChina
            case .islamicTabular: return NSCalendarIdentifierIslamicTabular
            case .islamicUmmAlQura: return NSCalendarIdentifierIslamicUmmAlQura
            }
        }

        internal static let _all: [Identifier] = [.gregorian, .buddhist, .chinese, .coptic, .ethiopicAmeteMihret,
            .ethiopicAmeteAlem, .hebrew, .iso8601, .indian, .islamic, .islamicCivil, .japanese, .persian,
            .republicOfChina, .islamicTabular, .islamicUmmAlQura]

        public var debugDescription: String { _name }
    }

    public enum Component: Hashable, Sendable {
        case era, year, month, day, hour, minute, second, weekday, weekdayOrdinal, quarter
        case weekOfMonth, weekOfYear, yearForWeekOfYear, nanosecond, calendar, timeZone, isLeapMonth, dayOfYear

        internal var _unit: NSCalendar.Unit {
            switch self {
            case .era: return .era
            case .year: return .year
            case .month: return .month
            case .day: return .day
            case .hour: return .hour
            case .minute: return .minute
            case .second: return .second
            case .weekday: return .weekday
            case .weekdayOrdinal: return .weekdayOrdinal
            case .quarter: return .quarter
            case .weekOfMonth: return .weekOfMonth
            case .weekOfYear: return .weekOfYear
            case .yearForWeekOfYear: return .yearForWeekOfYear
            case .nanosecond: return .nanosecond
            case .calendar: return .calendar
            case .timeZone: return .timeZone
            case .isLeapMonth: return .month
            case .dayOfYear: return .dayOfYear
            }
        }
    }

    internal static func _units(_ set: Set<Component>) -> NSCalendar.Unit {
        var u: NSCalendar.Unit = []
        for c in set { u.insert(c._unit) }
        return u
    }

    public init(identifier: __shared Identifier) {
        _ns = NSCalendar(calendarIdentifier: identifier._name) ?? NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
    }

    public static var current: Calendar { NSCalendar.current }
    public static var autoupdatingCurrent: Calendar { NSCalendar.autoupdatingCurrent }

    private mutating func _mutate(_ change: (NSCalendar) -> Void) {
        let c = _ns.copy() as! NSCalendar
        change(c)
        _ns = c
    }

    public var identifier: Identifier {
        let name = _ns.calendarIdentifier
        return Identifier._all.first { $0._name == name } ?? .gregorian
    }

    public var locale: Locale? {
        get { _ns.locale }
        set { _mutate { $0.locale = newValue } }
    }

    public var timeZone: TimeZone {
        get { _ns.timeZone ?? TimeZone.current }
        set { _mutate { $0.timeZone = newValue } }
    }

    public var firstWeekday: Int {
        get { Int(_ns.firstWeekday) }
        set { _mutate { $0.firstWeekday = newValue } }
    }

    public var minimumDaysInFirstWeek: Int {
        get { Int(_ns.minimumDaysInFirstWeek) }
        set { _mutate { $0.minimumDaysInFirstWeek = newValue } }
    }

    private func _strings(_ a: [Any]?) -> [String] { (a ?? []).compactMap { $0 as? String } }

    public var eraSymbols: [String] { _strings(_ns.eraSymbols) }
    public var longEraSymbols: [String] { _strings(_ns.longEraSymbols) }
    public var monthSymbols: [String] { _strings(_ns.monthSymbols) }
    public var shortMonthSymbols: [String] { _strings(_ns.shortMonthSymbols) }
    public var veryShortMonthSymbols: [String] { _strings(_ns.veryShortMonthSymbols) }
    public var standaloneMonthSymbols: [String] { _strings(_ns.standaloneMonthSymbols) }
    public var shortStandaloneMonthSymbols: [String] { _strings(_ns.shortStandaloneMonthSymbols) }
    public var veryShortStandaloneMonthSymbols: [String] { _strings(_ns.veryShortStandaloneMonthSymbols) }
    public var weekdaySymbols: [String] { _strings(_ns.weekdaySymbols) }
    public var shortWeekdaySymbols: [String] { _strings(_ns.shortWeekdaySymbols) }
    public var veryShortWeekdaySymbols: [String] { _strings(_ns.veryShortWeekdaySymbols) }
    public var standaloneWeekdaySymbols: [String] { _strings(_ns.standaloneWeekdaySymbols) }
    public var shortStandaloneWeekdaySymbols: [String] { _strings(_ns.shortStandaloneWeekdaySymbols) }
    public var veryShortStandaloneWeekdaySymbols: [String] { _strings(_ns.veryShortStandaloneWeekdaySymbols) }
    public var quarterSymbols: [String] { _strings(_ns.quarterSymbols) }
    public var shortQuarterSymbols: [String] { _strings(_ns.shortQuarterSymbols) }
    public var amSymbol: String { _ns.amSymbol ?? "AM" }
    public var pmSymbol: String { _ns.pmSymbol ?? "PM" }

    private static func _range(_ r: NSRange) -> Range<Int>? {
        r.location == NSNotFound ? nil : r.location ..< r.location + r.length
    }

    public func minimumRange(of component: Component) -> Range<Int>? {
        Calendar._range(_ns.minimumRange(of: component._unit))
    }

    public func maximumRange(of component: Component) -> Range<Int>? {
        Calendar._range(_ns.maximumRange(of: component._unit))
    }

    public func range(of smaller: Component, in larger: Component, for date: Date) -> Range<Int>? {
        Calendar._range(_ns.range(of: smaller._unit, in: larger._unit, for: date))
    }

    public func ordinality(of smaller: Component, in larger: Component, for date: Date) -> Int? {
        let n = _ns.ordinality(of: smaller._unit, in: larger._unit, for: date)
        return n == NSNotFound ? nil : n
    }

    public func dateInterval(of component: Component, start: inout Date, interval: inout TimeInterval, for date: Date) -> Bool {
        guard let i = dateInterval(of: component, for: date) else { return false }
        start = i.start
        interval = i.duration
        return true
    }

    public func dateInterval(of component: Component, for date: Date) -> DateInterval? {
        var start: NSDate?
        var interval: TimeInterval = 0
        guard _ns.range(of: component._unit, start: &start, interval: &interval, for: date), let start else { return nil }
        return DateInterval(start: start as Date, duration: interval)
    }

    public func dateComponents(_ components: Set<Component>, from date: Date) -> DateComponents {
        var c = _ns.components(Calendar._units(components), from: date) ?? DateComponents()
        if components.contains(.calendar) { c.calendar = self }
        if components.contains(.timeZone) { c.timeZone = timeZone }
        return c
    }

    public func dateComponents(in timeZone: TimeZone, from date: Date) -> DateComponents {
        _ns.components(in: timeZone, from: date) ?? DateComponents()
    }

    public func dateComponents(_ components: Set<Component>, from start: Date, to end: Date) -> DateComponents {
        _ns.components(Calendar._units(components), from: start, to: end, options: []) ?? DateComponents()
    }

    public func dateComponents(_ components: Set<Component>, from start: DateComponents, to end: DateComponents) -> DateComponents {
        _ns.components(Calendar._units(components), from: start, to: end, options: []) ?? DateComponents()
    }

    public func component(_ component: Component, from date: Date) -> Int {
        _ns.component(component._unit, from: date)
    }

    public func date(from components: DateComponents) -> Date? { _ns.date(from: components) }

    public func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool = false) -> Date? {
        _ns.date(byAdding: components, to: date, options: wrappingComponents ? .wrapComponents : [])
    }

    public func date(byAdding component: Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date? {
        _ns.date(byAdding: component._unit, value: value, to: date, options: wrappingComponents ? .wrapComponents : [])
    }

    public func startOfDay(for date: Date) -> Date { _ns.startOfDay(for: date) }

    public func isDateInToday(_ date: Date) -> Bool { _ns.isDate(inToday: date) }
    public func isDateInYesterday(_ date: Date) -> Bool { _ns.isDate(inYesterday: date) }
    public func isDateInTomorrow(_ date: Date) -> Bool { _ns.isDate(inTomorrow: date) }
    public func isDateInWeekend(_ date: Date) -> Bool { _ns.isDate(inWeekend: date) }
    public func isDate(_ date1: Date, inSameDayAs date2: Date) -> Bool { _ns.isDate(date1, inSameDayAs: date2) }

    public func isDate(_ date1: Date, equalTo date2: Date, toGranularity component: Component) -> Bool {
        _ns.isDate(date1, equalTo: date2, toUnitGranularity: component._unit)
    }

    public func compare(_ date1: Date, to date2: Date, toGranularity component: Component) -> ComparisonResult {
        _ns.compare(date1, to: date2, toUnitGranularity: component._unit)
    }

    public func date(bySettingHour hour: Int, minute: Int, second: Int, of date: Date) -> Date? {
        _ns.date(bySettingHour: hour, minute: minute, second: second, of: date, options: [])
    }

    public func date(bySetting component: Component, value: Int, of date: Date) -> Date? {
        _ns.date(bySettingUnit: component._unit, value: value, of: date, options: [])
    }

    public static func == (a: Calendar, b: Calendar) -> Bool {
        a._ns.calendarIdentifier == b._ns.calendarIdentifier && a.timeZone == b.timeZone
            && a.firstWeekday == b.firstWeekday && a.minimumDaysInFirstWeek == b.minimumDaysInFirstWeek
            && a.locale?.identifier == b.locale?.identifier
    }

    public func hash(into h: inout Hasher) {
        h.combine(_ns.calendarIdentifier)
        h.combine(timeZone)
    }

    public var description: String { "\(identifier._name) (\(timeZone.identifier))" }
    public var debugDescription: String { description }
}

extension Calendar: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSCalendar { _ns.copy() as! NSCalendar }
    public static func _forceBridgeFromObjectiveC(_ x: NSCalendar, result: inout Calendar?) {
        result = Calendar(_ns: x.copy() as! NSCalendar)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSCalendar, result: inout Calendar?) -> Bool {
        _forceBridgeFromObjectiveC(x, result: &result)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSCalendar?) -> Calendar {
        guard let source else { return Calendar(identifier: .gregorian) }
        return Calendar(_ns: source.copy() as! NSCalendar)
    }
}

// ---- DateComponents ----------------------------------------------------------------

public struct DateComponents: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias ReferenceType = NSDateComponents

    public var calendar: Calendar?
    public var timeZone: TimeZone?
    public var era: Int?
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?
    public var second: Int?
    public var nanosecond: Int?
    public var weekday: Int?
    public var weekdayOrdinal: Int?
    public var quarter: Int?
    public var weekOfMonth: Int?
    public var weekOfYear: Int?
    public var yearForWeekOfYear: Int?
    public var dayOfYear: Int?
    public var isLeapMonth: Bool?

    public init(calendar: Calendar? = nil, timeZone: TimeZone? = nil, era: Int? = nil, year: Int? = nil,
                month: Int? = nil, day: Int? = nil, hour: Int? = nil, minute: Int? = nil, second: Int? = nil,
                nanosecond: Int? = nil, weekday: Int? = nil, weekdayOrdinal: Int? = nil, quarter: Int? = nil,
                weekOfMonth: Int? = nil, weekOfYear: Int? = nil, yearForWeekOfYear: Int? = nil) {
        self.calendar = calendar
        self.timeZone = timeZone
        self.era = era
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.nanosecond = nanosecond
        self.weekday = weekday
        self.weekdayOrdinal = weekdayOrdinal
        self.quarter = quarter
        self.weekOfMonth = weekOfMonth
        self.weekOfYear = weekOfYear
        self.yearForWeekOfYear = yearForWeekOfYear
    }

    public var date: Date? {
        guard var cal = calendar else { return nil }
        if let timeZone { cal.timeZone = timeZone }
        return cal.date(from: self)
    }

    public var isValidDate: Bool { date != nil }

    public func isValidDate(in calendar: Calendar) -> Bool {
        var c = self
        c.calendar = calendar
        return c.isValidDate
    }

    public func value(for component: Calendar.Component) -> Int? {
        switch component {
        case .era: return era
        case .year: return year
        case .month: return month
        case .day: return day
        case .hour: return hour
        case .minute: return minute
        case .second: return second
        case .nanosecond: return nanosecond
        case .weekday: return weekday
        case .weekdayOrdinal: return weekdayOrdinal
        case .quarter: return quarter
        case .weekOfMonth: return weekOfMonth
        case .weekOfYear: return weekOfYear
        case .yearForWeekOfYear: return yearForWeekOfYear
        case .dayOfYear: return dayOfYear
        case .isLeapMonth: return isLeapMonth.map { $0 ? 1 : 0 }
        case .calendar, .timeZone: return nil
        }
    }

    public mutating func setValue(_ value: Int?, for component: Calendar.Component) {
        switch component {
        case .era: era = value
        case .year: year = value
        case .month: month = value
        case .day: day = value
        case .hour: hour = value
        case .minute: minute = value
        case .second: second = value
        case .nanosecond: nanosecond = value
        case .weekday: weekday = value
        case .weekdayOrdinal: weekdayOrdinal = value
        case .quarter: quarter = value
        case .weekOfMonth: weekOfMonth = value
        case .weekOfYear: weekOfYear = value
        case .yearForWeekOfYear: yearForWeekOfYear = value
        case .dayOfYear: dayOfYear = value
        case .isLeapMonth: isLeapMonth = value.map { $0 != 0 }
        case .calendar, .timeZone: break
        }
    }

    internal static let _fields: [Calendar.Component] = [.era, .year, .month, .day, .hour, .minute, .second,
        .nanosecond, .weekday, .weekdayOrdinal, .quarter, .weekOfMonth, .weekOfYear, .yearForWeekOfYear, .dayOfYear]

    public var description: String {
        var parts: [String] = []
        for f in DateComponents._fields {
            if let v = value(for: f) { parts.append("\(f): \(v)") }
        }
        if let isLeapMonth { parts.append("isLeapMonth: \(isLeapMonth)") }
        return parts.joined(separator: " ")
    }
    public var debugDescription: String { description }
}

extension DateComponents: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDateComponents {
        let c = NSDateComponents()
        if let calendar { c.calendar = calendar }
        if let timeZone { c.timeZone = timeZone }
        for f in DateComponents._fields {
            if let v = value(for: f) { c.setValue(v, forComponent: f._unit) }
        }
        if let isLeapMonth { c.isLeapMonth = isLeapMonth }
        return c
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSDateComponents, result: inout DateComponents?) {
        var d = DateComponents()
        d.calendar = x.calendar
        d.timeZone = x.timeZone
        for f in DateComponents._fields {
            let v = x.value(forComponent: f._unit)
            if v != NSDateComponentUndefined { d.setValue(v, for: f) }
        }
        if x.isLeapMonth { d.isLeapMonth = true }
        result = d
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSDateComponents, result: inout DateComponents?) -> Bool {
        _forceBridgeFromObjectiveC(x, result: &result)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDateComponents?) -> DateComponents {
        guard let source else { return DateComponents() }
        var r: DateComponents?
        _forceBridgeFromObjectiveC(source, result: &r)
        return r!
    }
}

// ---- units and Measurement -------------------------------------------------------------

public typealias Unit = NSUnit
public typealias Dimension = NSDimension
public typealias UnitConverter = NSUnitConverter
public typealias UnitConverterLinear = NSUnitConverterLinear
public typealias UnitTemperature = NSUnitTemperature
public typealias UnitInformationStorage = NSUnitInformationStorage
public typealias UnitFrequency = NSUnitFrequency
public typealias UnitPower = NSUnitPower
public typealias UnitElectricPotentialDifference = NSUnitElectricPotentialDifference
public typealias UnitElectricCurrent = NSUnitElectricCurrent
public typealias UnitDuration = NSUnitDuration
public typealias UnitLength = NSUnitLength
public typealias MeasurementFormatter = NSMeasurementFormatter

extension NSMeasurementFormatter {
    public typealias UnitOptions = NSMeasurementFormatterUnitOptions
}

public struct Measurement<UnitType: Unit>: CustomStringConvertible, CustomDebugStringConvertible {
    public let unit: UnitType
    public var value: Double

    public init(value: Double, unit: UnitType) {
        self.value = value
        self.unit = unit
    }

    public var description: String { "\(value) \(unit.symbol ?? "")" }
    public var debugDescription: String { description }
}

extension Measurement where UnitType: Dimension {
    public func converted(to otherUnit: UnitType) -> Measurement<UnitType> {
        if unit.isEqual(otherUnit) { return Measurement(value: value, unit: otherUnit) }
        let base = unit.converter.baseUnitValue(fromValue: value)
        return Measurement(value: otherUnit.converter.value(fromBaseUnitValue: base), unit: otherUnit)
    }

    public mutating func convert(to otherUnit: UnitType) { self = converted(to: otherUnit) }
}

extension Measurement: Equatable {
    public static func == (a: Measurement, b: Measurement) -> Bool {
        if a.unit.isEqual(b.unit) { return a.value == b.value }
        if let da = a.unit as? Dimension, let db = b.unit as? Dimension, type(of: da) == type(of: db) {
            return da.converter.baseUnitValue(fromValue: a.value) == db.converter.baseUnitValue(fromValue: b.value)
        }
        return false
    }
}

extension Measurement {
    internal var _ns: NSMeasurement { NSMeasurement(doubleValue: value, unit: unit) }
}

extension NSMeasurementFormatter {
    public func string<UnitType>(from measurement: Measurement<UnitType>) -> String {
        string(from: measurement._ns)
    }
}

// ---- POSIXError ----------------------------------------------------------------------

/// An error of the POSIX domain: an errno value.
public struct POSIXError: _BridgedStoredNSError {
    public let _nsError: NSError

    public init(_nsError error: NSError) { _nsError = error }

    public static var errorDomain: String { String(NSPOSIXErrorDomain) }

    public typealias Code = POSIXErrorCode
}

extension POSIXErrorCode: _ErrorCodeProtocol {
    public typealias _ErrorType = POSIXError
}

// ---- odds and ends -------------------------------------------------------------------

extension URLResourceValues {
    public var volumeAvailableCapacityForImportantUsage: Int64? {
        (allValues[.volumeAvailableCapacityForImportantUsageKey] as? NSNumber).map { Int64($0.longLongValue) }
    }
    public var volumeAvailableCapacityForOpportunisticUsage: Int64? {
        (allValues[.volumeAvailableCapacityForOpportunisticUsageKey] as? NSNumber).map { Int64($0.longLongValue) }
    }
    public var volumeAvailableCapacity: Int? {
        (allValues[.volumeAvailableCapacityKey] as? NSNumber).map { $0.integerValue }
    }
    public var volumeTotalCapacity: Int? {
        (allValues[.volumeTotalCapacityKey] as? NSNumber).map { $0.integerValue }
    }
}

extension URL {
    /// Ferry's file URLs keep no cached resource values, so there is nothing to forget.
    public mutating func removeAllCachedResourceValues() {}
    public mutating func removeCachedResourceValue(forKey key: URLResourceKey) {}
}

extension Date {
    public static func > (a: Date, b: Date) -> Bool { b < a }
    public static func <= (a: Date, b: Date) -> Bool { !(b < a) }
    public static func >= (a: Date, b: Date) -> Bool { !(a < b) }
}

/// The value Foundation's searches give when they find nothing.
public var NSNotFound: Int { Int.max }

extension String {
    /// The string a C string in the given encoding holds, or nil if it isn't valid in it.
    public init?(cString: UnsafePointer<CChar>, encoding enc: String.Encoding) {
        guard let s = NSString(cString: cString, encoding: enc.rawValue) else { return nil }
        self = s as String
    }
}

extension NSRange {
    /// The UTF-16 range in a string of a range of its indices.
    public init<R: RangeExpression, S: StringProtocol>(_ region: R, in target: S) where R.Bound == String.Index {
        let s = String(target)
        let r = region.relative(to: s)
        self.init(location: s.utf16.distance(from: s.startIndex, to: r.lowerBound),
                  length: s.utf16.distance(from: r.lowerBound, to: r.upperBound))
    }
}

extension Range where Bound == String.Index {
    /// The indices in a string of a UTF-16 range in it, or nil if the range doesn't fit.
    public init?(_ range: NSRange, in string: __shared String) {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location + range.length <= string.utf16.count,
              let lo = string.utf16.index(string.utf16.startIndex, offsetBy: range.location, limitedBy: string.utf16.endIndex),
              let hi = string.utf16.index(lo, offsetBy: range.length, limitedBy: string.utf16.endIndex),
              let l = lo.samePosition(in: string), let h = hi.samePosition(in: string) else { return nil }
        self = l ..< h
    }
}

public typealias URLSession = NSURLSession
public typealias URLSessionConfiguration = NSURLSessionConfiguration
public typealias URLSessionTask = NSURLSessionTask
public typealias URLSessionDataTask = NSURLSessionDataTask
public typealias URLSessionDownloadTask = NSURLSessionDownloadTask
public typealias URLSessionUploadTask = NSURLSessionUploadTask
public typealias URLSessionDelegate = NSURLSessionDelegate
public typealias URLSessionTaskDelegate = NSURLSessionTaskDelegate
public typealias URLSessionDataDelegate = NSURLSessionDataDelegate
public typealias URLResponse = NSURLResponse
public typealias HTTPURLResponse = NSHTTPURLResponse
public typealias URLCache = NSURLCache
public typealias URLCredential = NSURLCredential
public typealias HTTPCookie = NSHTTPCookie
public typealias HTTPCookieStorage = NSHTTPCookieStorage

extension NSURLSession {
    /// The data and response a request brings back, once it has finished.
    public func data(for request: URLRequest, delegate: (any NSURLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = self.dataTask(with: request) { data, response, error in
                if let error {
                    k.resume(throwing: error)
                } else {
                    k.resume(returning: (data ?? Data(), response ?? URLResponse()))
                }
            }
            task?.resume()
        }
    }

    /// The data and response a URL brings back, once it has finished.
    public func data(from url: URL, delegate: (any NSURLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), delegate: delegate)
    }
}
