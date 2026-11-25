// SPDX-License-Identifier: GPL-3.0-or-later
//
// Swift's standard library on Ferry: printing, arrays, sorting, dictionaries.

print("Hello from Swift on Ferry")
let xs = [3, 1, 2].sorted()
print(xs, xs.map { $0 * 2 }.reduce(0, +))
var d: [String: Int] = ["a": 1]
d["b"] = 2
print(d.keys.sorted(), "\(1.5 * 2)")
