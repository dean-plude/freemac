// SPDX-License-Identifier: GPL-3.0-or-later
//
// Foundation's Swift names for its classes (freemac 1.227). On a Mac,
// Swift sees Notification, Locale, IndexSet and the like as structs of
// their own, each bridged to its NS class; Date, Data, URL and UUID are
// such structs here too (Date.swift, Data.swift, freemac 1.230). For the
// rest each name is still the NS class itself, so code that only makes
// one, passes it along and reads its properties compiles and runs as it
// would on a Mac, while code that relies on value semantics (copying on
// change, ==, <) doesn't compile yet. Written for Ferry.

public typealias Notification = NSNotification
public typealias Locale = NSLocale
public typealias IndexSet = NSIndexSet
public typealias ProcessInfo = NSProcessInfo
public typealias UserDefaults = NSUserDefaults
public typealias Bundle = NSBundle
public typealias FileManager = NSFileManager
public typealias NotificationCenter = NSNotificationCenter
public typealias Timer = NSTimer
public typealias RunLoop = NSRunLoop
public typealias Thread = NSThread

extension NSRunLoop.Mode {
    /// The modes by the names Swift code uses (the headers' names, such as
    /// NSRunLoopCommonModes, arrive as .commonModes and the like).
    public static var `default`: NSRunLoop.Mode { .defaultRunLoopMode }
    public static var common: NSRunLoop.Mode { .commonModes }
}

extension NSLocale {
    /// The locale of an identifier such as "en_US".
    public convenience init(identifier: String) { self.init(localeIdentifier: identifier) }
    public var identifier: String { localeIdentifier }
}

extension NSDictionary {
    /// The object for a key of any kind, a Swift string included, as
    /// Apple's overlay gives NSDictionary.
    public subscript(key: Any) -> Any? { object(forKey: key) }
}
