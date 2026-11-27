// SPDX-License-Identifier: GPL-3.0-or-later
//
// The NSString methods Swift code calls on its own strings (freemac
// 1.227): String(format:), splitting, trimming, replacing, case-blind
// comparison and the like, each passed to NSString. Apple's Foundation
// gives String most of NSString's methods; these are the ones Swift Mac
// apps use most, written for Ferry from Apple's documentation of them.
// (Ferry's headers don't say which results may be nil, so Swift sees
// them as implicitly unwrapped; a nil here would be Foundation's error.)

extension String {
    /// A string made like -[NSString stringWithFormat:].
    public init(format: __shared String, _ arguments: CVarArg...) {
        self = String(format: format, arguments: arguments)
    }

    public init(format: __shared String, arguments: __shared [CVarArg]) {
        self = withVaList(arguments) { NSString(format: format, arguments: $0) as String }
    }

    /// The string an NSString holds.
    public init(_ cocoaString: NSString) { self = cocoaString as String }

    /// A string made from a format in the user's language, such as one
    /// NSLocalizedString found (numbers are written as in C here).
    public static func localizedStringWithFormat(_ format: String, _ arguments: CVarArg...) -> String {
        String(format: format, arguments: arguments)
    }

    /// The string of so many UTF-16 code units.
    public init(utf16CodeUnits: UnsafePointer<unichar>, count: Int) {
        self = String(decoding: UnsafeBufferPointer(start: utf16CodeUnits, count: count), as: UTF16.self)
    }

    public init?(utf8String: UnsafePointer<CChar>) {
        guard let s = NSString(utf8String: utf8String) else { return nil }
        self = s as String
    }
}

/// A Swift string passed to a C-style format (%@) as the NSString it
/// bridges to, which lives until the autorelease pool drains (freemac 1.230).
extension String {
    fileprivate var leftPadded: String { count < 2 ? "0" + self : self }
}

extension String: CVarArg {
    public var _cVarArgEncoding: [Int] { (self as NSString)._cVarArgEncoding }
}

extension StringProtocol {
    private var nsSelf: NSString { String(self) as NSString }

    public func components<T: StringProtocol>(separatedBy separator: T) -> [String] {
        nsSelf.components(separatedBy: String(separator)) ?? []
    }

    public func components(separatedBy separator: CharacterSet) -> [String] {
        String(self).split(omittingEmptySubsequences: false) { c in
            c.unicodeScalars.count == 1 && separator.contains(c.unicodeScalars.first!)
        }.map(String.init)
    }

    // ---- what a Mac's Foundation adds (freemac 1.262, IINA)

    private func _nsRange(_ r: Range<String.Index>?) -> NSRange {
        let s = String(self)
        guard let r else { return NSRange(location: 0, length: s.utf16.count) }
        return NSRange(location: s.utf16.distance(from: s.startIndex, to: r.lowerBound),
                       length: s.utf16.distance(from: r.lowerBound, to: r.upperBound))
    }

    private func _range(_ r: NSRange) -> Range<String.Index>? {
        guard r.location != NSNotFound else { return nil }
        let s = String(self)
        guard let lo = s.utf16.index(s.startIndex, offsetBy: r.location, limitedBy: s.endIndex),
              let hi = s.utf16.index(lo, offsetBy: r.length, limitedBy: s.endIndex) else { return nil }
        return lo..<hi
    }

    /// Each line, with a flag the body sets to stop.
    public func enumerateLines(invoking body: @escaping (_ line: String, _ stop: inout Bool) -> Void) {
        var stop = false
        var line = ""
        var afterCR = false
        for c in String(self).unicodeScalars {
            if afterCR {
                afterCR = false
                if c == "\n" { continue }
            }
            switch c {
            case "\n", "\r", "\u{2028}", "\u{2029}", "\u{85}":
                body(line, &stop)
                if stop { return }
                line = ""
                afterCR = c == "\r"
            default:
                line.unicodeScalars.append(c)
            }
        }
        if !line.isEmpty { body(line, &stop) }
    }

    public func localizedCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        nsSelf.localizedCompare(String(string))
    }

    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        nsSelf.localizedCaseInsensitiveCompare(String(string))
    }

    public func localizedStandardCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        nsSelf.localizedStandardCompare(String(string))
    }

    public func localizedStandardContains<T: StringProtocol>(_ string: T) -> Bool {
        nsSelf.range(of: String(string), options: [.caseInsensitive, .diacriticInsensitive]).location != NSNotFound
    }

    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [],
                                         range searchRange: Range<String.Index>? = nil,
                                         locale: Locale? = nil) -> Range<String.Index>? {
        _range(nsSelf.range(of: String(aString), options: mask, range: _nsRange(searchRange)))
    }

    public func rangeOfCharacter(from aSet: CharacterSet, options mask: String.CompareOptions = [],
                                 range aRange: Range<String.Index>? = nil) -> Range<String.Index>? {
        _range(nsSelf.rangeOfCharacter(from: aSet, options: mask, range: _nsRange(aRange)))
    }

    public func addingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
        var out = ""
        for b in String(self).utf8 {
            let u = Unicode.Scalar(b)
            if b < 0x80 && allowedCharacters.contains(u) {
                out.unicodeScalars.append(u)
            } else {
                out += "%" + String(b, radix: 16, uppercase: true).leftPadded
            }
        }
        return out
    }

    public var removingPercentEncoding: String? {
        var bytes: [UInt8] = []
        var it = Array(String(self).utf8)[...]
        while let b = it.popFirst() {
            if b == UInt8(ascii: "%") {
                guard it.count >= 2, let v = UInt8(String(decoding: it.prefix(2), as: UTF8.self), radix: 16) else {
                    return nil
                }
                bytes.append(v)
                it = it.dropFirst(2)
            } else {
                bytes.append(b)
            }
        }
        let s = String(decoding: bytes, as: UTF8.self)
        return s.utf8.elementsEqual(bytes) ? s : nil
    }

    public func cString(using encoding: String.Encoding) -> [CChar]? {
        guard let d = String(self).data(using: encoding) else { return nil }
        return d.map { CChar(bitPattern: $0) } + [0]
    }

    public func trimmingCharacters(in set: CharacterSet) -> String {
        nsSelf.trimmingCharacters(in: set) ?? String(self)
    }

    /// With the options and range Apple's Foundation takes (freemac 1.260).
    public func replacingOccurrences<Target: StringProtocol, Replacement: StringProtocol>(
        of target: Target, with replacement: Replacement, options: String.CompareOptions = [],
        range searchRange: Range<String.Index>? = nil
    ) -> String {
        if options.isEmpty && searchRange == nil {
            return nsSelf.replacingOccurrences(of: String(target), with: String(replacement)) ?? String(self)
        }
        let r = searchRange ?? startIndex..<endIndex
        let ns = NSRange(location: utf16.distance(from: startIndex, to: r.lowerBound),
                         length: utf16.distance(from: r.lowerBound, to: r.upperBound))
        return nsSelf.replacingOccurrences(of: String(target), with: String(replacement), options: options,
                                           range: ns) ?? String(self)
    }

    public func caseInsensitiveCompare<T: StringProtocol>(_ other: T) -> ComparisonResult {
        nsSelf.caseInsensitiveCompare(String(other))
    }

    /// Whether the other string is found in this one.
    public func contains<T: StringProtocol>(_ other: T) -> Bool {
        let o = String(other)
        return o.isEmpty || nsSelf.range(of: o).location != NSNotFound
    }

    public func localizedCaseInsensitiveContains<T: StringProtocol>(_ other: T) -> Bool {
        nsSelf.range(of: String(other), options: .caseInsensitive).location != NSNotFound
    }

    public var capitalized: String { nsSelf.capitalized ?? String(self) }

    public func appendingPathComponent(_ s: String) -> String { nsSelf.appendingPathComponent(s) ?? String(self) }
    public var lastPathComponent: String { nsSelf.lastPathComponent ?? "" }
    public var deletingLastPathComponent: String { nsSelf.deletingLastPathComponent ?? "" }
    public var pathExtension: String { nsSelf.pathExtension ?? "" }
    public var expandingTildeInPath: String { nsSelf.expandingTildeInPath ?? String(self) }
}

public typealias ComparisonResult = NSComparisonResult

extension String {
    public typealias CompareOptions = NSStringCompareOptions
}

/// A length of time, in seconds.
public typealias TimeInterval = Double

/// The string a bundle's strings files give for a key, or the key itself.
public func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main,
                              value: String = "", comment: String) -> String {
    bundle.localizedString(forKey: key, value: value, table: tableName).map { String($0) } ?? key
}
