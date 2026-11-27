// SPDX-License-Identifier: GPL-3.0-or-later
//
// Foundation's value types that stand for an Objective-C object, as Swift
// code built on a Mac sees them (freemac 1.262, for IINA): CharacterSet,
// IndexSet, IndexPath, URLRequest, AffineTransform and URLResourceValues.
// Each holds the Objective-C object it bridges to, and a change makes a new
// one, so copies change alone. Written for Ferry from Apple's documentation
// of these types.

/// A value type that bridges to an Objective-C class.
public protocol ReferenceConvertible: _ObjectiveCBridgeable, CustomStringConvertible, CustomDebugStringConvertible,
                                      Hashable {
    associatedtype ReferenceType: NSObject, NSCopying
}

// ---- CharacterSet

public struct CharacterSet: ReferenceConvertible, SetAlgebra, @unchecked Sendable {
    public typealias ReferenceType = NSCharacterSet
    public typealias Element = Unicode.Scalar

    internal var _set: NSCharacterSet

    internal init(_ns set: NSCharacterSet) { _set = set.copy() as! NSCharacterSet }

    public init() { _set = NSCharacterSet(charactersIn: "") }

    public init(charactersIn string: __shared String) { _set = NSCharacterSet(charactersIn: string) }

    public init(charactersIn range: Range<Unicode.Scalar>) {
        let lo = Int(range.lowerBound.value), hi = Int(range.upperBound.value)
        _set = NSCharacterSet(range: NSRange(location: lo, length: hi - lo))
    }

    public init(charactersIn range: ClosedRange<Unicode.Scalar>) {
        let lo = Int(range.lowerBound.value), hi = Int(range.upperBound.value)
        _set = NSCharacterSet(range: NSRange(location: lo, length: hi - lo + 1))
    }

    public init(bitmapRepresentation data: __shared Data) { _set = NSCharacterSet(bitmapRepresentation: data) }

    private mutating func _mutate(_ body: (NSMutableCharacterSet) -> Void) {
        let m = _set.mutableCopy() as! NSMutableCharacterSet
        body(m)
        _set = m.copy() as! NSCharacterSet
    }

    public static var controlCharacters: CharacterSet { _cs(NSCharacterSet.control) }
    public static var whitespaces: CharacterSet { _cs(NSCharacterSet.whitespace) }
    public static var whitespacesAndNewlines: CharacterSet {
        _cs(NSCharacterSet.whitespaceAndNewline)
    }
    public static var newlines: CharacterSet { _cs(NSCharacterSet.newline) }
    public static var decimalDigits: CharacterSet { _cs(NSCharacterSet.decimalDigit) }
    public static var letters: CharacterSet { _cs(NSCharacterSet.letter) }
    public static var lowercaseLetters: CharacterSet { _cs(NSCharacterSet.lowercaseLetter) }
    public static var uppercaseLetters: CharacterSet { _cs(NSCharacterSet.uppercaseLetter) }
    public static var alphanumerics: CharacterSet { _cs(NSCharacterSet.alphanumeric) }
    public static var punctuationCharacters: CharacterSet { _cs(NSCharacterSet.punctuation) }
    public static var symbols: CharacterSet { _cs(NSCharacterSet.symbol) }
    public static var illegalCharacters: CharacterSet { _cs(NSCharacterSet.illegal) }
    public static var capitalizedLetters: CharacterSet {
        _cs(NSCharacterSet.capitalizedLetter)
    }
    public static var nonBaseCharacters: CharacterSet { _cs(NSCharacterSet.nonBase) }
    public static var decomposables: CharacterSet { _cs(NSCharacterSet.decomposable) }
    public static var urlUserAllowed: CharacterSet { _cs(NSCharacterSet.urlUserAllowed) }
    public static var urlPasswordAllowed: CharacterSet {
        _cs(NSCharacterSet.urlPasswordAllowed)
    }
    public static var urlHostAllowed: CharacterSet { _cs(NSCharacterSet.urlHostAllowed) }
    public static var urlPathAllowed: CharacterSet { _cs(NSCharacterSet.urlPathAllowed) }
    public static var urlQueryAllowed: CharacterSet { _cs(NSCharacterSet.urlQueryAllowed) }
    public static var urlFragmentAllowed: CharacterSet {
        _cs(NSCharacterSet.urlFragmentAllowed)
    }

    public var bitmapRepresentation: Data { _set.bitmapRepresentation }

    public var inverted: CharacterSet { _set.inverted ?? CharacterSet() }

    public func contains(_ member: Unicode.Scalar) -> Bool { _set.longCharacterIsMember(member.value) }

    public func hasMember(inPlane plane: UInt8) -> Bool { _set.hasMember(inPlane: plane) }

    public func isSuperset(of other: CharacterSet) -> Bool { _set.isSuperset(of: other) }

    public mutating func insert(charactersIn range: Range<Unicode.Scalar>) {
        formUnion(CharacterSet(charactersIn: range))
    }

    public mutating func insert(charactersIn range: ClosedRange<Unicode.Scalar>) {
        formUnion(CharacterSet(charactersIn: range))
    }

    public mutating func remove(charactersIn range: Range<Unicode.Scalar>) {
        subtract(CharacterSet(charactersIn: range))
    }

    public mutating func remove(charactersIn range: ClosedRange<Unicode.Scalar>) {
        subtract(CharacterSet(charactersIn: range))
    }

    public mutating func insert(charactersIn string: String) { _mutate { $0.addCharacters(in: string) } }

    public mutating func remove(charactersIn string: String) { _mutate { $0.removeCharacters(in: string) } }

    public mutating func invert() { _mutate { $0.invert() } }

    @discardableResult
    public mutating func insert(_ character: Unicode.Scalar) -> (inserted: Bool, memberAfterInsert: Unicode.Scalar) {
        let had = contains(character)
        if !had { insert(charactersIn: character...character) }
        return (!had, character)
    }

    @discardableResult
    public mutating func update(with character: Unicode.Scalar) -> Unicode.Scalar? {
        let had = contains(character)
        insert(charactersIn: character...character)
        return had ? character : nil
    }

    @discardableResult
    public mutating func remove(_ character: Unicode.Scalar) -> Unicode.Scalar? {
        guard contains(character) else { return nil }
        remove(charactersIn: character...character)
        return character
    }

    public func union(_ other: CharacterSet) -> CharacterSet {
        var r = self
        r.formUnion(other)
        return r
    }

    public mutating func formUnion(_ other: CharacterSet) { _mutate { $0.formUnion(with: other) } }

    public func intersection(_ other: CharacterSet) -> CharacterSet {
        var r = self
        r.formIntersection(other)
        return r
    }

    public mutating func formIntersection(_ other: CharacterSet) { _mutate { $0.formIntersection(with: other) } }

    public func subtracting(_ other: CharacterSet) -> CharacterSet { intersection(other.inverted) }

    public mutating func subtract(_ other: CharacterSet) { formIntersection(other.inverted) }

    public func symmetricDifference(_ other: CharacterSet) -> CharacterSet {
        union(other).subtracting(intersection(other))
    }

    public mutating func formSymmetricDifference(_ other: CharacterSet) { self = symmetricDifference(other) }

    public var isEmpty: Bool { _set.bitmapRepresentation.allSatisfy { $0 == 0 } }

    public static func == (a: CharacterSet, b: CharacterSet) -> Bool { a._set.isEqual(b._set) }

    public func hash(into h: inout Hasher) { h.combine(_set.bitmapRepresentation) }

    public var description: String { _set.description }
    public var debugDescription: String { description }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSCharacterSet { _set }
    public static func _forceBridgeFromObjectiveC(_ x: NSCharacterSet, result: inout CharacterSet?) {
        result = CharacterSet(_ns: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSCharacterSet, result: inout CharacterSet?) -> Bool {
        result = CharacterSet(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSCharacterSet?) -> CharacterSet {
        source.map { CharacterSet(_ns: $0) } ?? CharacterSet()
    }
}

/// A set a class property or method of NSCharacterSet answers (both
/// arrive as CharacterSet).
private func _cs(_ s: CharacterSet) -> CharacterSet { s }
private func _cs(_ f: () -> CharacterSet?) -> CharacterSet { f() ?? CharacterSet() }

// ---- IndexSet

/// A set of integers, kept in order.
public struct IndexSet: ReferenceConvertible, Equatable, BidirectionalCollection, SetAlgebra, @unchecked Sendable {
    public typealias ReferenceType = NSIndexSet
    public typealias Element = Int

    /// A place in an IndexSet: the offset of an integer in its order.
    public struct Index: CustomStringConvertible, Comparable {
        internal var _offset: Int
        internal init(_ offset: Int) { _offset = offset }
        public var description: String { "index \(_offset)" }
        public static func == (a: Index, b: Index) -> Bool { a._offset == b._offset }
        public static func < (a: Index, b: Index) -> Bool { a._offset < b._offset }
    }

    public struct RangeView: RandomAccessCollection, Equatable {
        public typealias Index = Int
        internal var _ranges: [Range<Int>]
        public var startIndex: Int { 0 }
        public var endIndex: Int { _ranges.count }
        public subscript(i: Int) -> Range<Int> { _ranges[i] }
        public func makeIterator() -> IndexingIterator<RangeView> { IndexingIterator(_elements: self) }
    }

    /// The integers, in order, as runs of ranges.
    internal var _ranges: [Range<Int>] = []

    internal init(_ranges r: [Range<Int>]) { _ranges = r }

    public init() {}

    public init(integer: Int) { _ranges = [integer..<integer + 1] }

    public init(integersIn range: Range<Int>) { if !range.isEmpty { _ranges = [range] } }

    public init<R: RangeExpression>(integersIn range: R) where R.Bound == Int {
        self.init(integersIn: range.relative(to: Int.min..<Int.max))
    }

    internal init(_ns set: NSIndexSet) {
        var all: [Range<Int>] = []
        var i = set.firstIndex
        while i != NSNotFound {
            var j = i
            while set.contains(j + 1) { j += 1 }
            all.append(i..<j + 1)
            i = set.indexGreaterThanIndex(j)
        }
        _ranges = all
    }

    // the ranges stay sorted, apart and not touching
    private mutating func _add(_ r: Range<Int>) {
        guard !r.isEmpty else { return }
        var lo = r.lowerBound, hi = r.upperBound
        var kept: [Range<Int>] = []
        var placed = false
        for x in _ranges {
            if x.upperBound < lo {
                kept.append(x)
            } else if x.lowerBound > hi {
                if !placed { kept.append(lo..<hi); placed = true }
                kept.append(x)
            } else {
                lo = Swift.min(lo, x.lowerBound)
                hi = Swift.max(hi, x.upperBound)
            }
        }
        if !placed { kept.append(lo..<hi) }
        _ranges = kept
    }

    private mutating func _drop(_ r: Range<Int>) {
        guard !r.isEmpty else { return }
        var kept: [Range<Int>] = []
        for x in _ranges {
            if x.upperBound <= r.lowerBound || x.lowerBound >= r.upperBound {
                kept.append(x)
                continue
            }
            if x.lowerBound < r.lowerBound { kept.append(x.lowerBound..<r.lowerBound) }
            if x.upperBound > r.upperBound { kept.append(r.upperBound..<x.upperBound) }
        }
        _ranges = kept
    }

    public var count: Int { _ranges.reduce(0) { $0 + $1.count } }

    public var isEmpty: Bool { _ranges.isEmpty }

    public var startIndex: Index { Index(0) }
    public var endIndex: Index { Index(count) }

    public func index(after i: Index) -> Index { Index(i._offset + 1) }
    public func index(before i: Index) -> Index { Index(i._offset - 1) }

    public subscript(index: Index) -> Int {
        var left = index._offset
        for r in _ranges {
            if left < r.count { return r.lowerBound + left }
            left -= r.count
        }
        preconditionFailure("IndexSet index out of range")
    }

    public func makeIterator() -> IndexingIterator<IndexSet> { IndexingIterator(_elements: self) }

    public var first: Int? { _ranges.first?.lowerBound }
    public var last: Int? { _ranges.last.map { $0.upperBound - 1 } }

    public var rangeView: RangeView { RangeView(_ranges: _ranges) }

    public func contains(_ integer: Int) -> Bool { _ranges.contains { $0.contains(integer) } }

    public func contains(integersIn range: Range<Int>) -> Bool {
        range.isEmpty || _ranges.contains { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }
    }

    public func integerGreaterThan(_ integer: Int) -> Int? { first { $0 > integer } }
    public func integerLessThan(_ integer: Int) -> Int? { reversed().first { $0 < integer } }

    @discardableResult
    public mutating func insert(_ integer: Int) -> (inserted: Bool, memberAfterInsert: Int) {
        let had = contains(integer)
        if !had { _add(integer..<integer + 1) }
        return (!had, integer)
    }

    public mutating func insert(integersIn range: Range<Int>) { _add(range) }

    public mutating func insert<R: RangeExpression>(integersIn range: R) where R.Bound == Int {
        _add(range.relative(to: Int.min..<Int.max))
    }

    @discardableResult
    public mutating func update(with integer: Int) -> Int? {
        let had = contains(integer)
        _add(integer..<integer + 1)
        return had ? integer : nil
    }

    @discardableResult
    public mutating func remove(_ integer: Int) -> Int? {
        guard contains(integer) else { return nil }
        _drop(integer..<integer + 1)
        return integer
    }

    public mutating func remove(integersIn range: Range<Int>) { _drop(range) }

    public mutating func removeAll() { _ranges = [] }

    public func union(_ other: IndexSet) -> IndexSet {
        var r = self
        r.formUnion(other)
        return r
    }

    public mutating func formUnion(_ other: IndexSet) { for x in other._ranges { _add(x) } }

    public func intersection(_ other: IndexSet) -> IndexSet { IndexSet(filter { other.contains($0) }) }

    public mutating func formIntersection(_ other: IndexSet) { self = intersection(other) }

    public func subtracting(_ other: IndexSet) -> IndexSet {
        var r = self
        for x in other._ranges { r._drop(x) }
        return r
    }

    public func symmetricDifference(_ other: IndexSet) -> IndexSet {
        union(other).subtracting(intersection(other))
    }

    public mutating func formSymmetricDifference(_ other: IndexSet) { self = symmetricDifference(other) }

    public init<S: Sequence>(_ sequence: S) where S.Element == Int {
        for i in sequence { _add(i..<i + 1) }
    }

    public mutating func shift(startingAt integer: Int, by delta: Int) {
        let below = _ranges.compactMap { r -> Range<Int>? in
            r.lowerBound >= integer ? nil : r.lowerBound..<Swift.min(r.upperBound, integer)
        }
        let above = _ranges.compactMap { r -> Range<Int>? in
            r.upperBound <= integer ? nil : Swift.max(r.lowerBound, integer)..<r.upperBound
        }
        _ranges = below
        for r in above { _add(Swift.max(r.lowerBound + delta, integer)..<Swift.max(r.upperBound + delta, integer)) }
    }

    public static func == (a: IndexSet, b: IndexSet) -> Bool { a._ranges == b._ranges }

    public func hash(into h: inout Hasher) {
        for r in _ranges {
            h.combine(r.lowerBound)
            h.combine(r.upperBound)
        }
    }

    public var description: String { "\(count) indexes" }
    public var debugDescription: String { description }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSIndexSet {
        let m = NSMutableIndexSet()
        for r in _ranges { m.add(in: NSRange(location: r.lowerBound, length: r.count)) }
        return m
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSIndexSet, result: inout IndexSet?) { result = IndexSet(_ns: x) }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSIndexSet, result: inout IndexSet?) -> Bool {
        result = IndexSet(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSIndexSet?) -> IndexSet {
        source.map { IndexSet(_ns: $0) } ?? IndexSet()
    }
}

// ---- IndexPath

/// A list of integers naming a place in a tree, such as a section and an
/// item.
public struct IndexPath: ReferenceConvertible, Equatable, Hashable, MutableCollection, RandomAccessCollection,
                         Comparable, ExpressibleByArrayLiteral, @unchecked Sendable {
    public typealias ReferenceType = NSIndexPath
    public typealias Element = Int
    public typealias Index = Array<Int>.Index
    public typealias Indices = DefaultIndices<IndexPath>

    internal var _indexes: [Int]

    public init() { _indexes = [] }
    public init<S: Sequence>(indexes: S) where S.Element == Int { _indexes = Array(indexes) }
    public init(indexes: [Int]) { _indexes = indexes }
    public init(index: Int) { _indexes = [index] }
    public init(arrayLiteral indexes: Int...) { _indexes = indexes }

    internal init(_ns path: NSIndexPath) {
        _indexes = (0..<path.length).map { path.index(atPosition: $0) }
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { _indexes.count }
    public var count: Int { _indexes.count }
    public subscript(index: Int) -> Int {
        get { _indexes[index] }
        set { _indexes[index] = newValue }
    }
    public subscript(range: Range<Int>) -> IndexPath {
        get { IndexPath(indexes: _indexes[range]) }
        set { _indexes.replaceSubrange(range, with: newValue._indexes) }
    }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
    public func makeIterator() -> IndexingIterator<IndexPath> { IndexingIterator(_elements: self) }

    public func dropLast() -> IndexPath { IndexPath(indexes: _indexes.dropLast()) }
    public mutating func append(_ other: IndexPath) { _indexes += other._indexes }
    public mutating func append(_ other: Int) { _indexes.append(other) }
    public mutating func append(_ other: [Int]) { _indexes += other }
    public func appending(_ other: Int) -> IndexPath { IndexPath(indexes: _indexes + [other]) }
    public func appending(_ other: IndexPath) -> IndexPath { IndexPath(indexes: _indexes + other._indexes) }
    public func appending(_ other: [Int]) -> IndexPath { IndexPath(indexes: _indexes + other) }

    public func compare(_ other: IndexPath) -> ComparisonResult {
        for (a, b) in zip(_indexes, other._indexes) where a != b { return a < b ? .orderedAscending : .orderedDescending }
        return _indexes.count == other._indexes.count ? .orderedSame
            : _indexes.count < other._indexes.count ? .orderedAscending : .orderedDescending
    }

    public static func == (a: IndexPath, b: IndexPath) -> Bool { a._indexes == b._indexes }
    public static func < (a: IndexPath, b: IndexPath) -> Bool { a.compare(b) == .orderedAscending }
    public static func + (a: IndexPath, b: IndexPath) -> IndexPath { a.appending(b) }
    public func hash(into h: inout Hasher) { h.combine(_indexes) }

    public var description: String { _indexes.description }
    public var debugDescription: String { description }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSIndexPath {
        _indexes.withUnsafeBufferPointer { NSIndexPath(indexes: $0.baseAddress, length: $0.count) }
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSIndexPath, result: inout IndexPath?) {
        result = IndexPath(_ns: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSIndexPath, result: inout IndexPath?) -> Bool {
        result = IndexPath(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSIndexPath?) -> IndexPath {
        source.map { IndexPath(_ns: $0) } ?? IndexPath()
    }
}

// ---- URLRequest

/// A request for a URL: where, how and with what.
public struct URLRequest: ReferenceConvertible, Equatable, Hashable, @unchecked Sendable {
    public typealias ReferenceType = NSURLRequest
    public typealias CachePolicy = NSURLRequestCachePolicy
    public typealias NetworkServiceType = NSURLRequestNetworkServiceType

    internal var _request: NSMutableURLRequest

    internal init(_ns request: NSURLRequest) { _request = request.mutableCopy() as! NSMutableURLRequest }

    public init(url: URL, cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0) {
        _request = NSMutableURLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
    }

    private mutating func _mutate(_ body: (NSMutableURLRequest) -> Void) {
        if !isKnownUniquelyReferenced(&_request) { _request = _request.mutableCopy() as! NSMutableURLRequest }
        body(_request)
    }

    public var url: URL? {
        get { _request.url }
        set { _mutate { $0.url = newValue } }
    }

    public var cachePolicy: CachePolicy {
        get { _request.cachePolicy }
        set { _mutate { $0.cachePolicy = newValue } }
    }

    public var timeoutInterval: TimeInterval {
        get { _request.timeoutInterval }
        set { _mutate { $0.timeoutInterval = newValue } }
    }

    public var mainDocumentURL: URL? {
        get { _request.mainDocumentURL }
        set { _mutate { $0.mainDocumentURL = newValue } }
    }

    public var httpMethod: String? {
        get { _request.httpMethod.map { String($0) } }
        set { _mutate { $0.httpMethod = newValue ?? "GET" } }
    }

    public var allHTTPHeaderFields: [String: String]? {
        get { _request.allHTTPHeaderFields as? [String: String] }
        set { _mutate { $0.allHTTPHeaderFields = newValue } }
    }

    public func value(forHTTPHeaderField field: String) -> String? {
        _request.value(forHTTPHeaderField: field).map { String($0) }
    }

    public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
        _mutate { $0.setValue(value, forHTTPHeaderField: field) }
    }

    public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
        _mutate { $0.addValue(value, forHTTPHeaderField: field) }
    }

    public var httpBody: Data? {
        get { _request.httpBody }
        set { _mutate { $0.httpBody = newValue } }
    }

    public var httpShouldHandleCookies: Bool {
        get { _request.httpShouldHandleCookies }
        set { _mutate { $0.httpShouldHandleCookies = newValue } }
    }

    public static func == (a: URLRequest, b: URLRequest) -> Bool { a._request.isEqual(b._request) }
    public func hash(into h: inout Hasher) { h.combine(_request.hash) }

    public var description: String { url?.description ?? "url: nil" }
    public var debugDescription: String { description }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURLRequest { _request.copy() as! NSURLRequest }
    public static func _forceBridgeFromObjectiveC(_ x: NSURLRequest, result: inout URLRequest?) {
        result = URLRequest(_ns: x)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSURLRequest, result: inout URLRequest?) -> Bool {
        result = URLRequest(_ns: x)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLRequest?) -> URLRequest {
        URLRequest(_ns: source!)
    }
}

// ---- AffineTransform

/// A two-dimensional transform: m11 m12 / m21 m22 / tX tY, as AppKit's
/// NSAffineTransform keeps it.
public struct AffineTransform: ReferenceConvertible, Hashable, @unchecked Sendable {
    public typealias ReferenceType = NSAffineTransform

    public var m11: CGFloat, m12: CGFloat, m21: CGFloat, m22: CGFloat, tX: CGFloat, tY: CGFloat

    public init(m11: CGFloat, m12: CGFloat, m21: CGFloat, m22: CGFloat, tX: CGFloat, tY: CGFloat) {
        (self.m11, self.m12, self.m21, self.m22, self.tX, self.tY) = (m11, m12, m21, m22, tX, tY)
    }

    public init() { self.init(m11: 1, m12: 0, m21: 0, m22: 1, tX: 0, tY: 0) }

    public static var identity: AffineTransform { AffineTransform() }

    public init(translationByX x: CGFloat, byY y: CGFloat) { self.init(m11: 1, m12: 0, m21: 0, m22: 1, tX: x, tY: y) }

    public init(scaleByX x: CGFloat, byY y: CGFloat) { self.init(m11: x, m12: 0, m21: 0, m22: y, tX: 0, tY: 0) }

    public init(scale factor: CGFloat) { self.init(scaleByX: factor, byY: factor) }

    public init(rotationByRadians angle: CGFloat) {
        let c: CGFloat = cos(angle), s: CGFloat = sin(angle)
        self.init(m11: c, m12: s, m21: -s, m22: c, tX: 0, tY: 0)
    }

    public init(rotationByDegrees angle: CGFloat) { self.init(rotationByRadians: angle * .pi / 180) }

    /// This transform followed by another.
    public mutating func append(_ t: AffineTransform) {
        self = AffineTransform(m11: m11 * t.m11 + m12 * t.m21, m12: m11 * t.m12 + m12 * t.m22,
                               m21: m21 * t.m11 + m22 * t.m21, m22: m21 * t.m12 + m22 * t.m22,
                               tX: tX * t.m11 + tY * t.m21 + t.tX, tY: tX * t.m12 + tY * t.m22 + t.tY)
    }

    /// Another transform followed by this one.
    public mutating func prepend(_ t: AffineTransform) {
        var r = t
        r.append(self)
        self = r
    }

    public mutating func translate(x: CGFloat, y: CGFloat) { prepend(AffineTransform(translationByX: x, byY: y)) }
    public mutating func scale(_ s: CGFloat) { prepend(AffineTransform(scale: s)) }
    public mutating func scale(x: CGFloat, y: CGFloat) { prepend(AffineTransform(scaleByX: x, byY: y)) }
    public mutating func rotate(byRadians a: CGFloat) { prepend(AffineTransform(rotationByRadians: a)) }
    public mutating func rotate(byDegrees a: CGFloat) { prepend(AffineTransform(rotationByDegrees: a)) }

    public func transform(_ p: CGPoint) -> CGPoint {
        CGPoint(x: m11 * p.x + m21 * p.y + tX, y: m12 * p.x + m22 * p.y + tY)
    }

    public func transform(_ s: CGSize) -> CGSize { CGSize(width: m11 * s.width + m21 * s.height,
                                                          height: m12 * s.width + m22 * s.height) }

    public var description: String { "{m11:\(m11), m12:\(m12), m21:\(m21), m22:\(m22), tX:\(tX), tY:\(tY)}" }
    public var debugDescription: String { description }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSAffineTransform {
        let t = NSAffineTransform()
        t.transformStruct = NSAffineTransformStruct(m11: m11, m12: m12, m21: m21, m22: m22, tX: tX, tY: tY)
        return t
    }
    public static func _forceBridgeFromObjectiveC(_ x: NSAffineTransform, result: inout AffineTransform?) {
        let s = x.transformStruct
        result = AffineTransform(m11: s.m11, m12: s.m12, m21: s.m21, m22: s.m22, tX: s.tX, tY: s.tY)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ x: NSAffineTransform, result: inout AffineTransform?) -> Bool {
        _forceBridgeFromObjectiveC(x, result: &result)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSAffineTransform?) -> AffineTransform {
        var r: AffineTransform?
        if let source { _forceBridgeFromObjectiveC(source, result: &r) }
        return r ?? AffineTransform()
    }
}

// ---- URLResourceValues

/// What URL.resourceValues(forKeys:) found about a file.
public struct URLResourceValues: @unchecked Sendable {
    internal var _values: [URLResourceKey: Any]
    internal var _keysToSet: Set<URLResourceKey> = []

    public init() { _values = [:] }
    internal init(_ values: [URLResourceKey: Any]) { _values = values }

    public var allValues: [URLResourceKey: Any] { _values }

    private func _get<T>(_ key: URLResourceKey) -> T? { _values[key] as? T }

    private func _bool(_ key: URLResourceKey) -> Bool? {
        (_values[key] as? NSNumber)?.boolValue ?? (_values[key] as? Bool)
    }

    private func _int(_ key: URLResourceKey) -> Int? {
        (_values[key] as? NSNumber)?.integerValue ?? (_values[key] as? Int)
    }

    public var name: String? { _get(.nameKey) }
    public var localizedName: String? { _get(.localizedNameKey) }
    public var isRegularFile: Bool? { _bool(.isRegularFileKey) }
    public var isDirectory: Bool? { _bool(.isDirectoryKey) }
    public var isSymbolicLink: Bool? { _bool(.isSymbolicLinkKey) }
    public var isHidden: Bool? { _bool(.isHiddenKey) }
    public var isPackage: Bool? { _bool(.isPackageKey) }
    public var isReadable: Bool? { _bool(.isReadableKey) }
    public var isWritable: Bool? { _bool(.isWritableKey) }
    public var isExecutable: Bool? { _bool(.isExecutableKey) }
    public var creationDate: Date? { _get(.creationDateKey) }
    public var contentAccessDate: Date? { _get(.contentAccessDateKey) }
    public var contentModificationDate: Date? { _get(.contentModificationDateKey) }
    public var fileSize: Int? { _int(.fileSizeKey) }
    public var totalFileSize: Int? { _int(.totalFileSizeKey) }
    public var volumeIsLocal: Bool? { _bool(.volumeIsLocalKey) }
    public var typeIdentifier: String? { _get(.typeIdentifierKey) }
}

extension URL {
    public func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
        var found: [URLResourceKey: Any] = [:]
        for key in keys {
            var value: AnyObject?
            try (_url as NSURL).getResourceValue(&value, forKey: key)
            if let value { found[key] = value }
        }
        return URLResourceValues(found)
    }

    public init(fileURLWithPath path: __shared String) { self.init(_ns: NSURL(fileURLWithPath: path)) }

    public init(fileURLWithPath path: __shared String, isDirectory: Bool) {
        self.init(_ns: NSURL.fileURL(withPath: path, isDirectory: isDirectory) as NSURL)
    }

    public func resolvingSymlinksInPath() -> URL { _url.resolvingSymlinksInPath ?? self }

    public func bookmarkData(options: NSURLBookmarkCreationOptions = [],
                             includingResourceValuesForKeys keys: Set<URLResourceKey>? = nil,
                             relativeTo url: URL? = nil) throws -> Data {
        try _url.bookmarkData(options: options, includingResourceValuesForKeys: keys.map { Array($0) },
                              relativeTo: url)
    }

    public init(resolvingBookmarkData data: __shared Data, options: NSURLBookmarkResolutionOptions = [],
                relativeTo url: __shared URL? = nil, bookmarkDataIsStale: inout Bool) throws {
        var stale: ObjCBool = false
        let u = try NSURL(byResolvingBookmarkData: data, options: options, relativeTo: url, bookmarkDataIsStale: &stale)
        bookmarkDataIsStale = stale.boolValue
        self.init(_ns: u)
    }

    public init(resolvingAliasFileAt url: __shared URL, options: NSURLBookmarkResolutionOptions = []) throws {
        // a freemac computer has no Finder aliases; a symbolic link is what
        // comes closest
        self = url.resolvingSymlinksInPath()
    }
}
