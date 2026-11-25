// SPDX-License-Identifier: GPL-3.0-or-later
//
// Swift's Foundation on Ferry's: strings, arrays, dictionaries and numbers
// to and from their NS classes, NSString's methods, an NSObject subclass,
// and Swift's own strings (not only literals) as NSDictionary keys.

import Foundation

let s: NSString = "hello" as NSString
print(s.length, s.uppercase!)
let parts = "a,b,c".components(separatedBy: ",")
print(parts, parts.count)
let arr: NSArray = [1, 2, 3] as NSArray
print(arr.count, (arr.object(at: 1) as! NSNumber).intValue)
let back = arr as! [Int]
print(back.map { $0 * 10 })
let d: NSDictionary = ["x": 1, "y": 2] as NSDictionary
let sd = d as! [String: Int]
print(sd.keys.sorted(), sd["y"]!)
print(String(format: "%d-%@-%.2f", 42, "str" as NSString, 3.14159))
let n = NSNumber(value: 7)
print(n.intValue + 1, n.boolValue)
let t = "  trim me  ".trimmingCharacters(in: .whitespaces)
print("[\(t)]")
print("Hello World".replacingOccurrences(of: "World", with: "Ferry"))
let ns2: NSString = NSString(string: "café")
print(String(ns2) == "café", (ns2 as String).count)
class Thing: NSObject {
    var v = 3
    override var description: String { "Thing(\(v))" }
}
let th = Thing()
print(th, th.description, th.isEqual(th))
let objs: [AnyObject] = [th, "x" as NSString]
let nsa = objs as NSArray
print(nsa.count)

// dynamic keys: Swift's own string objects, hashed as NSString hashes
let key = String(repeating: "k", count: 3) + "ey"
let table = NSMutableDictionary()
table.setObject(1 as NSNumber, forKey: "kkkey" as NSString)
print((table.object(forKey: key) as? NSNumber)?.intValue ?? -1)
print((key as NSString).hash == ("kkkey" as NSString).hash)
let wide = String(repeating: "\u{e9}", count: 2) + "t\u{e9}"
print((wide as NSString).hash == ("\u{e9}\u{e9}t\u{e9}" as NSString).hash)
