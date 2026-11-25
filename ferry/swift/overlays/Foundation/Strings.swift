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
    public init(format: String, _ arguments: CVarArg...) {
        self = String(format: format, arguments: arguments)
    }

    public init(format: String, arguments: [CVarArg]) {
        self = withVaList(arguments) { NSString(format: format, arguments: $0) as String }
    }

    /// The string an NSString holds.
    public init(_ cocoaString: NSString) { self = cocoaString as String }

    public init?(utf8String: UnsafePointer<CChar>) {
        guard let s = NSString(utf8String: utf8String) else { return nil }
        self = s as String
    }
}

extension StringProtocol {
    private var nsSelf: NSString { String(self) as NSString }

    public func components(separatedBy separator: String) -> [String] {
        nsSelf.components(separatedBy: separator) ?? []
    }

    public func components(separatedBy separator: CharacterSet) -> [String] {
        String(self).split(omittingEmptySubsequences: false) { c in
            c.utf16.count == 1 && separator.characterIsMember(c.utf16.first!)
        }.map(String.init)
    }

    public func trimmingCharacters(in set: CharacterSet) -> String {
        nsSelf.trimmingCharacters(in: set) ?? String(self)
    }

    public func replacingOccurrences<T: StringProtocol, U: StringProtocol>(of target: T, with replacement: U) -> String {
        nsSelf.replacingOccurrences(of: String(target), with: String(replacement)) ?? String(self)
    }

    public func caseInsensitiveCompare<T: StringProtocol>(_ other: T) -> ComparisonResult {
        nsSelf.caseInsensitiveCompare(String(other))
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

/// Characters to trim or split at, as NSCharacterSet holds them.
public typealias CharacterSet = NSCharacterSet

extension NSCharacterSet {
    public static var whitespaces: NSCharacterSet { NSCharacterSet.whitespace() }
    public static var whitespacesAndNewlines: NSCharacterSet { NSCharacterSet.whitespaceAndNewline() }
    public static var newlines: NSCharacterSet { NSCharacterSet.newline() }
    public static var decimalDigits: NSCharacterSet { NSCharacterSet.decimalDigit() }
    public static var letters: NSCharacterSet { NSCharacterSet.letter() }
    public static var alphanumerics: NSCharacterSet { NSCharacterSet.alphanumeric() }
    public static var punctuationCharacters: NSCharacterSet { NSCharacterSet.punctuation() }
}

/// A length of time, in seconds.
public typealias TimeInterval = Double

/// The string a bundle's strings files give for a key, or the key itself.
public func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main,
                              value: String = "", comment: String) -> String {
    bundle.localizedString(forKey: key, value: value, table: tableName).map { String($0) } ?? key
}
