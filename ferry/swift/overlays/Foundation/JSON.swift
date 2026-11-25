// SPDX-License-Identifier: GPL-3.0-or-later
//
// JSONEncoder and JSONDecoder (freemac 1.230): Codable values to JSON
// text and back, with the strategies Apple's documentation describes for
// dates (deferred to Date, seconds or milliseconds since 1970, ISO 8601, a
// DateFormatter, custom), data (Base64, deferred, custom), keys (as they
// are, or snake_case) and non-finite numbers, and the output formats
// (pretty-printed, sorted keys, slashes unescaped). The JSON is read and
// written here in Swift. Written for Ferry.

// ---- the JSON values -------------------------------------------------------------------

internal indirect enum _JSONValue {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([_JSONValue])
    case object([String], [String: _JSONValue]) // the keys in order, and their values

    var kindName: String {
        switch self {
        case .null: return "null"
        case .bool: return "a boolean"
        case .number: return "a number"
        case .string: return "a string"
        case .array: return "an array"
        case .object: return "a dictionary"
        }
    }
}

// what an encoder is filling: a value, or a container still open
internal final class _JSONObjectBox {
    var keys: [String] = []
    var values: [String: _JSONSlot] = [:]
    func slot(_ key: String) -> _JSONSlot {
        if let s = values[key] { return s }
        let s = _JSONSlot()
        keys.append(key)
        values[key] = s
        return s
    }
}
internal final class _JSONArrayBox { var items: [_JSONSlot] = [] }
internal final class _JSONSlot {
    enum Content { case value(_JSONValue), object(_JSONObjectBox), array(_JSONArrayBox) }
    var content: Content?
    init(_ c: Content? = nil) { content = c }

    func materialize() -> _JSONValue {
        switch content {
        case .none: return .object([], [:])
        case .value(let v): return v
        case .array(let a): return .array(a.items.map { $0.materialize() })
        case .object(let o):
            var d: [String: _JSONValue] = [:]
            for k in o.keys { d[k] = o.values[k]!.materialize() }
            return .object(o.keys, d)
        }
    }
}

internal struct _JSONKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init(intValue: Int) { stringValue = "Index \(intValue)"; self.intValue = intValue }
    init(index: Int) { self.init(intValue: index) }
    static let `super` = _JSONKey(stringValue: "super")
}

internal func _snakeCase(_ key: String) -> String {
    // "someURLValue" -> "some_url_value": a word starts at a capital after a
    // small letter, or at the last capital of a run followed by a small one
    guard !key.isEmpty else { return key }
    let chars = Array(key)
    var words: [String] = []
    var current = ""
    for (i, c) in chars.enumerated() {
        if c.isUppercase && !current.isEmpty {
            let prevUpper = chars[i - 1].isUppercase
            let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
            if !prevUpper || nextLower {
                words.append(current)
                current = ""
            }
        }
        current.append(c)
    }
    words.append(current)
    return words.map { $0.lowercased() }.joined(separator: "_")
}

internal func _camelCase(_ key: String) -> String {
    guard key.contains("_") else { return key }
    let lead = key.prefix { $0 == "_" }
    let trail = String(key.reversed().prefix { $0 == "_" })
    let core = key.dropFirst(lead.count).dropLast(trail.count)
    let parts = core.split(separator: "_", omittingEmptySubsequences: true)
    guard let first = parts.first else { return key }
    let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
    return String(lead) + first.lowercased() + rest.joined() + trail
}

// ---- JSONEncoder -----------------------------------------------------------------------

open class JSONEncoder {
    public struct OutputFormatting: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let prettyPrinted = OutputFormatting(rawValue: 1 << 0)
        public static let sortedKeys = OutputFormatting(rawValue: 1 << 1)
        public static let withoutEscapingSlashes = OutputFormatting(rawValue: 1 << 3)
    }

    public enum DateEncodingStrategy {
        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970
        case iso8601
        case formatted(DateFormatter)
        case custom((Date, Encoder) throws -> Void)
    }

    public enum DataEncodingStrategy {
        case deferredToData
        case base64
        case custom((Data, Encoder) throws -> Void)
    }

    public enum NonConformingFloatEncodingStrategy {
        case `throw`
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    public enum KeyEncodingStrategy {
        case useDefaultKeys
        case convertToSnakeCase
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
    }

    open var outputFormatting: OutputFormatting = []
    open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
    open var dataEncodingStrategy: DataEncodingStrategy = .base64
    open var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw
    open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    open func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = _JSONEncoderImpl(owner: self, slot: _JSONSlot(), codingPath: [])
        try enc.box(value, into: enc.slot)
        var out = ""
        _JSONWriter(format: outputFormatting).write(enc.slot.materialize(), into: &out, depth: 0)
        return Data(out.utf8)
    }
}

internal struct _JSONWriter {
    let format: JSONEncoder.OutputFormatting

    func write(_ v: _JSONValue, into out: inout String, depth: Int) {
        let pretty = format.contains(.prettyPrinted)
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): string(s, into: &out)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                if pretty { out += "\n" + String(repeating: "  ", count: depth + 1) }
                write(item, into: &out, depth: depth + 1)
            }
            if pretty { out += "\n" + String(repeating: "  ", count: depth) }
            out += "]"
        case .object(let keys, let values):
            if keys.isEmpty { out += "{}"; return }
            out += "{"
            let order = format.contains(.sortedKeys) ? keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } : keys
            for (i, k) in order.enumerated() {
                if i > 0 { out += "," }
                if pretty { out += "\n" + String(repeating: "  ", count: depth + 1) }
                string(k, into: &out)
                out += pretty ? " : " : ":"
                write(values[k]!, into: &out, depth: depth + 1)
            }
            if pretty { out += "\n" + String(repeating: "  ", count: depth) }
            out += "}"
        }
    }

    func string(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "/": out += format.contains(.withoutEscapingSlashes) ? "/" : "\\/"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}

internal final class _JSONEncoderImpl: Encoder {
    let owner: JSONEncoder
    let slot: _JSONSlot
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { owner.userInfo }

    init(owner: JSONEncoder, slot: _JSONSlot, codingPath: [CodingKey]) {
        self.owner = owner
        self.slot = slot
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let box: _JSONObjectBox
        if case .object(let o)? = slot.content { box = o } else {
            box = _JSONObjectBox()
            slot.content = .object(box)
        }
        return KeyedEncodingContainer(_JSONKeyedEncoder<Key>(enc: self, box: box, codingPath: codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let box: _JSONArrayBox
        if case .array(let a)? = slot.content { box = a } else {
            box = _JSONArrayBox()
            slot.content = .array(box)
        }
        return _JSONUnkeyedEncoder(enc: self, box: box, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer { _JSONSingleEncoder(enc: self, codingPath: codingPath) }

    func key(_ k: CodingKey, path: [CodingKey]) -> String {
        switch owner.keyEncodingStrategy {
        case .useDefaultKeys: return k.stringValue
        case .convertToSnakeCase: return _snakeCase(k.stringValue)
        case .custom(let f): return f(path + [k]).stringValue
        }
    }

    func number<T: BinaryFloatingPoint & LosslessStringConvertible>(_ v: T, path: [CodingKey]) throws -> _JSONValue {
        if v.isFinite {
            var s = v.description
            if s.hasSuffix(".0") { s.removeLast(2) }
            return .number(s)
        }
        guard case .convertToString(let pos, let neg, let nan) = owner.nonConformingFloatEncodingStrategy else {
            throw EncodingError.invalidValue(v, .init(codingPath: path, debugDescription:
                "Unable to encode \(T.self).\(v) directly in JSON. Use JSONEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."))
        }
        return .string(v.isNaN ? nan : v > 0 ? pos : neg)
    }

    /// Encodes a value of any kind into a slot, with the strategies for the
    /// kinds that have one.
    func box<T: Encodable>(_ value: T, into slot: _JSONSlot) throws {
        let path = codingPath
        switch value {
        case let v as Bool: slot.content = .value(.bool(v)); return
        case let v as String: slot.content = .value(.string(v)); return
        case let v as Double: slot.content = .value(try number(v, path: path)); return
        case let v as Float: slot.content = .value(try number(v, path: path)); return
        case let v as URL: slot.content = .value(.string(v.absoluteString)); return
        case let v as Date:
            switch owner.dateEncodingStrategy {
            case .deferredToDate: break
            case .secondsSince1970: slot.content = .value(try number(v.timeIntervalSince1970, path: path)); return
            case .millisecondsSince1970: slot.content = .value(try number(v.timeIntervalSince1970 * 1000, path: path)); return
            case .iso8601:
                let f = NSISO8601DateFormatter()
                slot.content = .value(.string(f.string(from: v) ?? ""))
                return
            case .formatted(let f): slot.content = .value(.string(f.string(from: v) ?? "")); return
            case .custom(let f):
                let sub = _JSONEncoderImpl(owner: owner, slot: slot, codingPath: path)
                try f(v, sub)
                if slot.content == nil { slot.content = .object(_JSONObjectBox()) }
                return
            }
        case let v as Data:
            switch owner.dataEncodingStrategy {
            case .deferredToData: break
            case .base64: slot.content = .value(.string(v.base64EncodedString())); return
            case .custom(let f):
                let sub = _JSONEncoderImpl(owner: owner, slot: slot, codingPath: path)
                try f(v, sub)
                if slot.content == nil { slot.content = .object(_JSONObjectBox()) }
                return
            }
        default: break
        }
        if let n = _JSONEncoderImpl.integer(value) { slot.content = .value(.number(n)); return }
        let sub = _JSONEncoderImpl(owner: owner, slot: slot, codingPath: path)
        try value.encode(to: sub)
        if slot.content == nil { slot.content = .object(_JSONObjectBox()) }
    }

    static func integer(_ v: Any) -> String? {
        switch v {
        case let i as Int: return String(i)
        case let i as Int8: return String(i)
        case let i as Int16: return String(i)
        case let i as Int32: return String(i)
        case let i as Int64: return String(i)
        case let i as UInt: return String(i)
        case let i as UInt8: return String(i)
        case let i as UInt16: return String(i)
        case let i as UInt32: return String(i)
        case let i as UInt64: return String(i)
        default: return nil
        }
    }

    func child(_ slot: _JSONSlot, _ key: CodingKey) -> _JSONEncoderImpl {
        _JSONEncoderImpl(owner: owner, slot: slot, codingPath: codingPath + [key])
    }
}

internal struct _JSONKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let enc: _JSONEncoderImpl
    let box: _JSONObjectBox
    var codingPath: [CodingKey]

    private func put<T: Encodable>(_ v: T, _ key: Key) throws {
        let slot = box.slot(enc.key(key, path: codingPath))
        try enc.child(slot, key).box(v, into: slot)
    }

    mutating func encodeNil(forKey key: Key) throws { box.slot(enc.key(key, path: codingPath)).content = .value(.null) }

    mutating func encode(_ v: Bool, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: String, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Double, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Float, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Int, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Int8, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Int16, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Int32, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: Int64, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: UInt, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: UInt8, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: UInt16, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: UInt32, forKey key: Key) throws { try put(v, key) }
    mutating func encode(_ v: UInt64, forKey key: Key) throws { try put(v, key) }
    mutating func encode<T: Encodable>(_ v: T, forKey key: Key) throws { try put(v, key) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let slot = box.slot(enc.key(key, path: codingPath))
        return enc.child(slot, key).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let slot = box.slot(enc.key(key, path: codingPath))
        return enc.child(slot, key).unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder { enc.child(box.slot("super"), _JSONKey.super) }
    mutating func superEncoder(forKey key: Key) -> Encoder { enc.child(box.slot(enc.key(key, path: codingPath)), key) }
}

internal struct _JSONUnkeyedEncoder: UnkeyedEncodingContainer {
    let enc: _JSONEncoderImpl
    let box: _JSONArrayBox
    var codingPath: [CodingKey]
    var count: Int { box.items.count }

    private func next() -> (_JSONSlot, _JSONKey) {
        let slot = _JSONSlot()
        box.items.append(slot)
        return (slot, _JSONKey(index: box.items.count - 1))
    }

    private func put<T: Encodable>(_ v: T) throws {
        let (slot, key) = next()
        try enc.child(slot, key).box(v, into: slot)
    }

    mutating func encodeNil() throws { next().0.content = .value(.null) }

    mutating func encode(_ v: Bool) throws { try put(v) }
    mutating func encode(_ v: String) throws { try put(v) }
    mutating func encode(_ v: Double) throws { try put(v) }
    mutating func encode(_ v: Float) throws { try put(v) }
    mutating func encode(_ v: Int) throws { try put(v) }
    mutating func encode(_ v: Int8) throws { try put(v) }
    mutating func encode(_ v: Int16) throws { try put(v) }
    mutating func encode(_ v: Int32) throws { try put(v) }
    mutating func encode(_ v: Int64) throws { try put(v) }
    mutating func encode(_ v: UInt) throws { try put(v) }
    mutating func encode(_ v: UInt8) throws { try put(v) }
    mutating func encode(_ v: UInt16) throws { try put(v) }
    mutating func encode(_ v: UInt32) throws { try put(v) }
    mutating func encode(_ v: UInt64) throws { try put(v) }
    mutating func encode<T: Encodable>(_ v: T) throws { try put(v) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let (slot, key) = next()
        return enc.child(slot, key).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let (slot, key) = next()
        return enc.child(slot, key).unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        let (slot, key) = next()
        return enc.child(slot, key)
    }
}

internal struct _JSONSingleEncoder: SingleValueEncodingContainer {
    let enc: _JSONEncoderImpl
    var codingPath: [CodingKey]

    mutating func encodeNil() throws { enc.slot.content = .value(.null) }

    mutating func encode(_ v: Bool) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: String) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Double) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Float) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Int) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Int8) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Int16) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Int32) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: Int64) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: UInt) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: UInt8) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: UInt16) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: UInt32) throws { try enc.box(v, into: enc.slot) }
    mutating func encode(_ v: UInt64) throws { try enc.box(v, into: enc.slot) }
    mutating func encode<T: Encodable>(_ v: T) throws { try enc.box(v, into: enc.slot) }
}

// ---- JSONDecoder -----------------------------------------------------------------------

open class JSONDecoder {
    public enum DateDecodingStrategy {
        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970
        case iso8601
        case formatted(DateFormatter)
        case custom((_ decoder: Decoder) throws -> Date)
    }

    public enum DataDecodingStrategy {
        case deferredToData
        case base64
        case custom((_ decoder: Decoder) throws -> Data)
    }

    public enum NonConformingFloatDecodingStrategy {
        case `throw`
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    public enum KeyDecodingStrategy {
        case useDefaultKeys
        case convertFromSnakeCase
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
    }

    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    open var dataDecodingStrategy: DataDecodingStrategy = .base64
    open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
    open var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
    open var userInfo: [CodingUserInfoKey: Any] = [:]
    open var allowsJSON5 = false
    open var assumesTopLevelDictionary = false

    public init() {}

    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var parser = _JSONParser(bytes: Array(data))
        let value: _JSONValue
        do { value = try parser.parseDocument() } catch let e as _JSONParser.Failure {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The given data was not valid JSON.",
                underlyingError: NSError(domain: NSCocoaErrorDomain, code: 3840,
                                         userInfo: [NSLocalizedDescriptionKey: e.message])))
        }
        return try _JSONDecoderImpl(owner: self, value: value, codingPath: []).unbox(type)
    }
}

internal struct _JSONParser {
    struct Failure: Error { let message: String }
    let bytes: [UInt8]
    var i = 0
    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> _JSONValue {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }
        let v = try value()
        skip()
        guard i == bytes.count else { throw Failure(message: "Garbage at end around character \(i).") }
        return v
    }

    mutating func skip() {
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09 { i += 1 }
    }

    mutating func value() throws -> _JSONValue {
        skip()
        guard i < bytes.count else { throw Failure(message: "Unexpected end of file.") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try word("true"); return .bool(true)
        case UInt8(ascii: "f"): try word("false"); return .bool(false)
        case UInt8(ascii: "n"): try word("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
        default: throw Failure(message: "Invalid value around character \(i).")
        }
    }

    mutating func word(_ w: String) throws {
        let u = Array(w.utf8)
        guard i + u.count <= bytes.count, Array(bytes[i..<(i + u.count)]) == u else {
            throw Failure(message: "Invalid value around character \(i).")
        }
        i += u.count
    }

    mutating func digits() -> Int {
        let s = i
        while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 { i += 1 }
        return i - s
    }

    mutating func number() throws -> _JSONValue {
        let start = i
        if bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard digits() > 0 else { throw Failure(message: "Invalid number around character \(start).") }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            i += 1
            guard digits() > 0 else { throw Failure(message: "Invalid number around character \(start).") }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard digits() > 0 else { throw Failure(message: "Invalid number around character \(start).") }
        }
        return .number(String(decoding: bytes[start..<i], as: UTF8.self))
    }

    mutating func string() throws -> String {
        i += 1
        var out: [UInt8] = []
        while true {
            guard i < bytes.count else { throw Failure(message: "Unterminated string.") }
            let c = bytes[i]
            i += 1
            if c == UInt8(ascii: "\"") { break }
            if c != UInt8(ascii: "\\") { out.append(c); continue }
            guard i < bytes.count else { throw Failure(message: "Unterminated string.") }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
            case UInt8(ascii: "b"): out.append(8)
            case UInt8(ascii: "f"): out.append(12)
            case UInt8(ascii: "n"): out.append(10)
            case UInt8(ascii: "r"): out.append(13)
            case UInt8(ascii: "t"): out.append(9)
            case UInt8(ascii: "u"):
                var code = try hex4()
                if code >= 0xD800 && code < 0xDC00 {
                    guard i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") else {
                        throw Failure(message: "Unpaired surrogate around character \(i).")
                    }
                    i += 2
                    let low = try hex4()
                    guard low >= 0xDC00 && low < 0xE000 else { throw Failure(message: "Unpaired surrogate around character \(i).") }
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                }
                guard let u = Unicode.Scalar(code) else { throw Failure(message: "Invalid escape around character \(i).") }
                out.append(contentsOf: Array(String(Character(u)).utf8))
            default: throw Failure(message: "Invalid escape around character \(i).")
            }
        }
        guard let s = String(bytes: out, encoding: .utf8) else { throw Failure(message: "Invalid UTF-8 in a string.") }
        return s
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16) else {
            throw Failure(message: "Invalid escape around character \(i).")
        }
        i += 4
        return v
    }

    mutating func array() throws -> _JSONValue {
        i += 1
        var items: [_JSONValue] = []
        skip()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            items.append(try value())
            skip()
            guard i < bytes.count else { throw Failure(message: "Unexpected end of file in an array.") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw Failure(message: "Badly formed array around character \(i).")
        }
    }

    mutating func object() throws -> _JSONValue {
        i += 1
        var keys: [String] = []
        var values: [String: _JSONValue] = [:]
        skip()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(keys, values) }
        while true {
            skip()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw Failure(message: "No string key in object around character \(i).") }
            let k = try string()
            skip()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw Failure(message: "No value for key in object around character \(i).") }
            i += 1
            let v = try value()
            if values[k] == nil { keys.append(k) }
            values[k] = v
            skip()
            guard i < bytes.count else { throw Failure(message: "Unexpected end of file in an object.") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(keys, values) }
            throw Failure(message: "Badly formed object around character \(i).")
        }
    }
}

internal final class _JSONDecoderImpl: Decoder {
    let owner: JSONDecoder
    let value: _JSONValue
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { owner.userInfo }

    init(owner: JSONDecoder, value: _JSONValue, codingPath: [CodingKey]) {
        self.owner = owner
        self.value = value
        self.codingPath = codingPath
    }

    func mismatch<T>(_ type: T.Type, _ v: _JSONValue) -> DecodingError {
        DecodingError.typeMismatch(type, .init(codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(v.kindName) instead."))
    }

    func missing<T>(_ type: T.Type) -> DecodingError {
        DecodingError.valueNotFound(type, .init(codingPath: codingPath, debugDescription: "Expected \(type) value but found null instead."))
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        if case .null = value {
            throw DecodingError.valueNotFound(KeyedDecodingContainer<Key>.self, .init(codingPath: codingPath,
                debugDescription: "Cannot get keyed decoding container -- found null value instead"))
        }
        guard case .object(let keys, let values) = value else { throw mismatch([String: Any].self, value) }
        var map: [String: _JSONValue] = [:]
        var order: [String] = []
        for k in keys {
            let name: String
            switch owner.keyDecodingStrategy {
            case .useDefaultKeys: name = k
            case .convertFromSnakeCase: name = _camelCase(k)
            case .custom(let f): name = f(codingPath + [_JSONKey(stringValue: k)]).stringValue
            }
            if map[name] == nil { order.append(name) }
            map[name] = values[k]
        }
        return KeyedDecodingContainer(_JSONKeyedDecoder<Key>(dec: self, values: map, order: order, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        if case .null = value {
            throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self, .init(codingPath: codingPath,
                debugDescription: "Cannot get unkeyed decoding container -- found null value instead"))
        }
        guard case .array(let items) = value else { throw mismatch([Any].self, value) }
        return _JSONUnkeyedDecoder(dec: self, items: items, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer { _JSONSingleDecoder(dec: self, codingPath: codingPath) }

    func child(_ v: _JSONValue, _ key: CodingKey) -> _JSONDecoderImpl {
        _JSONDecoderImpl(owner: owner, value: v, codingPath: codingPath + [key])
    }

    func float<T: BinaryFloatingPoint & LosslessStringConvertible>(_ type: T.Type) throws -> T {
        switch value {
        case .number(let n):
            guard let d = T(n) else { throw mismatch(type, value) }
            return d
        case .string(let s):
            if case .convertFromString(let pos, let neg, let nan) = owner.nonConformingFloatDecodingStrategy {
                if s == pos { return .infinity }
                if s == neg { return -.infinity }
                if s == nan { return .nan }
            }
            throw mismatch(type, value)
        case .null: throw missing(type)
        default: throw mismatch(type, value)
        }
    }

    func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        switch value {
        case .number(let n):
            if let v = T(n) { return v }
            if let d = Double(n), d.rounded() == d, let v = T(exactly: d) { return v }
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath,
                debugDescription: "Parsed JSON number <\(n)> does not fit in \(type)."))
        case .null: throw missing(type)
        default: throw mismatch(type, value)
        }
    }

    func string() throws -> String {
        switch value {
        case .string(let s): return s
        case .null: throw missing(String.self)
        default: throw mismatch(String.self, value)
        }
    }

    func unbox<T: Decodable>(_ type: T.Type) throws -> T {
        if type == Bool.self {
            switch value {
            case .bool(let b): return b as! T
            case .null: throw missing(type)
            default: throw mismatch(type, value)
            }
        }
        if type == String.self { return try string() as! T }
        if type == Double.self { return try float(Double.self) as! T }
        if type == Float.self { return try float(Float.self) as! T }
        if type == Int.self { return try integer(Int.self) as! T }
        if type == Int8.self { return try integer(Int8.self) as! T }
        if type == Int16.self { return try integer(Int16.self) as! T }
        if type == Int32.self { return try integer(Int32.self) as! T }
        if type == Int64.self { return try integer(Int64.self) as! T }
        if type == UInt.self { return try integer(UInt.self) as! T }
        if type == UInt8.self { return try integer(UInt8.self) as! T }
        if type == UInt16.self { return try integer(UInt16.self) as! T }
        if type == UInt32.self { return try integer(UInt32.self) as! T }
        if type == UInt64.self { return try integer(UInt64.self) as! T }
        if type == URL.self {
            guard let u = URL(string: try string()) else {
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Invalid URL string."))
            }
            return u as! T
        }
        if type == Date.self {
            switch owner.dateDecodingStrategy {
            case .deferredToDate: break
            case .secondsSince1970: return Date(timeIntervalSince1970: try float(Double.self)) as! T
            case .millisecondsSince1970: return Date(timeIntervalSince1970: try float(Double.self) / 1000) as! T
            case .iso8601:
                guard let d = NSISO8601DateFormatter().date(from: try string()) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
                }
                return d as! T
            case .formatted(let f):
                guard let d = f.date(from: try string()) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Date string does not match format expected by formatter."))
                }
                return d as! T
            case .custom(let f): return try f(self) as! T
            }
        }
        if type == Data.self {
            switch owner.dataDecodingStrategy {
            case .deferredToData: break
            case .base64:
                guard let d = Data(base64Encoded: try string()) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Encountered Data is not valid Base64."))
                }
                return d as! T
            case .custom(let f): return try f(self) as! T
            }
        }
        return try T(from: self)
    }
}

internal struct _JSONKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dec: _JSONDecoderImpl
    let values: [String: _JSONValue]
    let order: [String]
    var codingPath: [CodingKey]

    var allKeys: [Key] { order.compactMap { Key(stringValue: $0) } }
    func contains(_ key: Key) -> Bool { values[key.stringValue] != nil }

    private func entry(_ key: Key) throws -> _JSONValue {
        guard let v = values[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath,
                debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        return v
    }

    private func get<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
        try dec.child(try entry(key), key).unbox(type)
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if case .null = try entry(key) { return true }
        return false
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try get(type, key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try get(type, key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try get(type, key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try get(type, key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try get(type, key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try get(type, key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try get(type, key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try get(type, key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try get(type, key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try get(type, key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try get(type, key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try get(type, key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try get(type, key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try get(type, key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try get(type, key) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try dec.child(try entry(key), key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try dec.child(try entry(key), key).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder { dec.child(values["super"] ?? .null, _JSONKey.super) }
    func superDecoder(forKey key: Key) throws -> Decoder { dec.child(values[key.stringValue] ?? .null, key) }
}

internal struct _JSONUnkeyedDecoder: UnkeyedDecodingContainer {
    let dec: _JSONDecoderImpl
    let items: [_JSONValue]
    var codingPath: [CodingKey]
    var currentIndex = 0

    init(dec: _JSONDecoderImpl, items: [_JSONValue], codingPath: [CodingKey]) {
        self.dec = dec
        self.items = items
        self.codingPath = codingPath
    }

    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    private mutating func next<T>(_ type: T.Type) throws -> (_JSONValue, _JSONKey) {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [_JSONKey(index: currentIndex)],
                debugDescription: "Unkeyed container is at end."))
        }
        let v = items[currentIndex]
        let k = _JSONKey(index: currentIndex)
        currentIndex += 1
        return (v, k)
    }

    private mutating func get<T: Decodable>(_ type: T.Type) throws -> T {
        let (v, k) = try next(type)
        return try dec.child(v, k).unbox(type)
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { throw DecodingError.valueNotFound(Any?.self, .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end.")) }
        if case .null = items[currentIndex] { currentIndex += 1; return true }
        return false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try get(type) }
    mutating func decode(_ type: String.Type) throws -> String { try get(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try get(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try get(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try get(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try get(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try get(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try get(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try get(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try get(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try get(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try get(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try get(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try get(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try get(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let (v, k) = try next(KeyedDecodingContainer<NestedKey>.self)
        return try dec.child(v, k).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let (v, k) = try next(UnkeyedDecodingContainer.self)
        return try dec.child(v, k).unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        let (v, k) = try next(Decoder.self)
        return dec.child(v, k)
    }
}

internal struct _JSONSingleDecoder: SingleValueDecodingContainer {
    let dec: _JSONDecoderImpl
    var codingPath: [CodingKey]

    func decodeNil() -> Bool {
        if case .null = dec.value { return true }
        return false
    }

    func decode(_ type: Bool.Type) throws -> Bool { try dec.unbox(type) }
    func decode(_ type: String.Type) throws -> String { try dec.unbox(type) }
    func decode(_ type: Double.Type) throws -> Double { try dec.unbox(type) }
    func decode(_ type: Float.Type) throws -> Float { try dec.unbox(type) }
    func decode(_ type: Int.Type) throws -> Int { try dec.unbox(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try dec.unbox(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try dec.unbox(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try dec.unbox(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try dec.unbox(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try dec.unbox(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try dec.unbox(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try dec.unbox(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try dec.unbox(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try dec.unbox(type) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try dec.unbox(type) }
}
