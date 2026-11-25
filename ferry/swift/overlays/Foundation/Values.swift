// SPDX-License-Identifier: GPL-3.0-or-later
//
// Foundation's value types (freemac 1.227). On a Mac, Swift sees Date,
// URL, Data, Notification and the like as structs of their own, each
// bridged to its NS class. Ferry's overlay doesn't have those structs yet:
// each name is the NS class itself, so code that only makes one, passes it
// along and reads its properties compiles and runs as it would on a Mac,
// while code that relies on value semantics (copying on change, ==, <)
// doesn't compile yet. Written for Ferry.

public typealias Notification = NSNotification
public typealias Date = NSDate
public typealias URL = NSURL
public typealias Data = NSData
public typealias UUID = NSUUID
public typealias Locale = NSLocale
public typealias IndexSet = NSIndexSet
public typealias ProcessInfo = NSProcessInfo
public typealias UserDefaults = NSUserDefaults
public typealias Bundle = NSBundle
public typealias FileManager = NSFileManager
public typealias NotificationCenter = NSNotificationCenter
public typealias Timer = NSTimer
public typealias RunLoop = NSRunLoop

extension NSNotification {
    /// A notification's name, as Swift spells NSNotificationName.
    public typealias Name = NSString
}

extension NSDate {
    /// The date now.
    public static var now: NSDate { NSDate() }
}

extension NSDictionary {
    /// The object for a key of any kind, a Swift string included, as
    /// Apple's overlay gives NSDictionary.
    public subscript(key: Any) -> Any? { object(forKey: key) }
}
