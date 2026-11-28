// SPDX-License-Identifier: GPL-3.0-or-later
//
// More of Foundation's Swift side (freemac 1.230): String.Encoding and
// strings to and from Data, FileHandle's throwing methods, the nested
// names Swift code gives FileManager's and the formatters' options, and
// UserDefaults' Swift conveniences. Written for Ferry from Apple's
// documentation of them.

// ---- String.Encoding ---------------------------------------------------------------

extension String {
    /// A text encoding, by NSStringEncoding's number.
    public struct Encoding: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let ascii = Encoding(rawValue: 1)
        public static let nextstep = Encoding(rawValue: 2)
        public static let japaneseEUC = Encoding(rawValue: 3)
        public static let utf8 = Encoding(rawValue: 4)
        public static let isoLatin1 = Encoding(rawValue: 5)
        public static let symbol = Encoding(rawValue: 6)
        public static let nonLossyASCII = Encoding(rawValue: 7)
        public static let shiftJIS = Encoding(rawValue: 8)
        public static let isoLatin2 = Encoding(rawValue: 9)
        public static let unicode = Encoding(rawValue: 10)
        public static let windowsCP1251 = Encoding(rawValue: 11)
        public static let windowsCP1252 = Encoding(rawValue: 12)
        public static let windowsCP1253 = Encoding(rawValue: 13)
        public static let windowsCP1254 = Encoding(rawValue: 14)
        public static let windowsCP1250 = Encoding(rawValue: 15)
        public static let iso2022JP = Encoding(rawValue: 21)
        public static let macOSRoman = Encoding(rawValue: 30)
        public static let utf16 = Encoding(rawValue: 10)
        public static let utf16BigEndian = Encoding(rawValue: 0x9000_0100)
        public static let utf16LittleEndian = Encoding(rawValue: 0x9400_0100)
        public static let utf32 = Encoding(rawValue: 0x8c00_0100)
        public static let utf32BigEndian = Encoding(rawValue: 0x9800_0100)
        public static let utf32LittleEndian = Encoding(rawValue: 0x9c00_0100)

        public var description: String { NSString.localizedName(ofStringEncoding: rawValue) ?? "\(rawValue)" }
    }

    public init?(data: __shared Data, encoding: Encoding) {
        if encoding == .utf8 {
            guard let s = String(validatingUTF8Bytes: data) else { return nil }
            self = s
            return
        }
        guard let s = NSString(data: data, encoding: encoding.rawValue) else { return nil }
        self = s as String
    }

    public init?<S: Sequence>(bytes: __shared S, encoding: Encoding) where S.Element == UInt8 {
        self.init(data: Data(bytes), encoding: encoding)
    }

    public init(contentsOfFile path: __shared String, encoding: Encoding) throws {
        let d = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let s = String(data: d, encoding: encoding) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                          userInfo: [NSFilePathErrorKey: path])
        }
        self = s
    }

    public init(contentsOf url: __shared URL, encoding: Encoding) throws {
        try self.init(contentsOfFile: url.path, encoding: encoding)
    }

    /// A file's text, read as UTF-8 (a Mac's Foundation guesses the
    /// encoding; UTF-8 is what nearly every file is in).
    public init(contentsOf url: __shared URL) throws {
        try self.init(contentsOfFile: url.path, encoding: .utf8)
    }

    public init(contentsOfFile path: __shared String) throws {
        try self.init(contentsOfFile: path, encoding: .utf8)
    }

    private init?(validatingUTF8Bytes d: Data) {
        var it = d.makeIterator()
        var out = ""
        var decoder = UTF8()
        loop: while true {
            switch decoder.decode(&it) {
            case .scalarValue(let u): out.unicodeScalars.append(u)
            case .emptyInput: break loop
            case .error: return nil
            }
        }
        self = out
    }
}

// On StringProtocol, as Apple's Foundation has them, so that a Mac app's
// calls reach them by the same names (freemac 1.260).
extension StringProtocol {
    /// The string's bytes in an encoding, or nil when it can't be written in it.
    public func data(using encoding: String.Encoding, allowLossyConversion: Bool = false) -> Data? {
        let s = String(self)
        if encoding == .utf8 { return Data(s.utf8) }
        return (s as NSString).data(usingEncoding: encoding.rawValue, allowLossyConversion: allowLossyConversion)
    }

    public func write<T: StringProtocol>(toFile path: T, atomically: Bool, encoding: String.Encoding) throws {
        let path = String(path)
        guard let d = data(using: encoding) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError,
                          userInfo: [NSFilePathErrorKey: path])
        }
        try d.write(to: URL(fileURLWithPath: path), options: atomically ? .atomic : [])
    }

    public func write(to url: URL, atomically: Bool, encoding: String.Encoding) throws {
        try write(toFile: url.path, atomically: atomically, encoding: encoding)
    }

    public func lengthOfBytes(using encoding: String.Encoding) -> Int {
        String(self).data(using: encoding)?.count ?? 0
    }
}

// ---- FileHandle --------------------------------------------------------------------

public typealias FileHandle = NSFileHandle

extension NSFileHandle {
    /// Moves to the end, and answers where that is.
    @discardableResult
    public func seekToEnd() throws -> UInt64 {
        var offset: UInt64 = 0
        try __seekToEndReturningOffset(&offset)
        return offset
    }

    public func offset() throws -> UInt64 {
        var offset: UInt64 = 0
        try __getOffset(&offset)
        return offset
    }

    public func write<T: DataProtocol>(contentsOf data: T) throws {
        try __write(Data(data))
    }

    public func readToEnd() throws -> Data? {
        let d: Data = try __readDataToEndOfFile()
        return d.isEmpty ? nil : d
    }

    public func read(upToCount count: Int) throws -> Data? {
        let d: Data = try __readData(upToLength: count)
        return d.isEmpty ? nil : d
    }
}

// ---- FileManager -------------------------------------------------------------------

extension NSFileManager {
    public typealias SearchPathDirectory = NSSearchPathDirectory
    public typealias SearchPathDomainMask = NSSearchPathDomainMask
}

// ---- formatters --------------------------------------------------------------------

public typealias Formatter = NSFormatter
public typealias DateFormatter = NSDateFormatter
public typealias NumberFormatter = NSNumberFormatter
public typealias DateComponentsFormatter = NSDateComponentsFormatter
public typealias ISO8601DateFormatter = NSISO8601DateFormatter
public typealias ByteCountFormatter = NSByteCountFormatter
public typealias OperationQueue = NSOperationQueue
public typealias Operation = NSOperation
public typealias Process = NSTask
public typealias Pipe = NSPipe
public typealias JSONSerialization = NSJSONSerialization
public typealias PropertyListSerialization = NSPropertyListSerialization

extension NSDateComponentsFormatter {
    public typealias UnitsStyle = NSDateComponentsFormatterUnitsStyle
    public typealias ZeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehavior
}

extension NSCalendar {
    public typealias Unit = NSCalendarUnit
}

extension NSDateFormatter {
    public typealias Style = NSDateFormatterStyle
}

extension NSNumberFormatter {
    public typealias Style = NSNumberFormatterStyle
}

// ---- UserDefaults ------------------------------------------------------------------

extension NSUserDefaults {
    public func set(_ value: Bool, forKey key: String) { setBool(value, forKey: key) }
    public func set(_ value: Int, forKey key: String) { setInteger(value, forKey: key) }
    public func set(_ value: Double, forKey key: String) { setDouble(value, forKey: key) }
    public func set(_ value: Float, forKey key: String) { setFloat(value, forKey: key) }
    public func set(_ value: URL?, forKey key: String) {
        if let value { set(value.absoluteString, forKey: key) } else { removeObject(forKey: key) }
    }
    public func url(forKey key: String) -> URL? {
        guard let s = string(forKey: key) else { return nil }
        return s.hasPrefix("/") ? URL(fileURLWithPath: s) : URL(string: s)
    }
}

// MARK: - predicates from a format with Swift arguments

extension NSPredicate {
    public convenience init(format predicateFormat: __shared String, _ args: CVarArg...) {
        self.init(format: predicateFormat, arguments: getVaList(args))
    }
}
