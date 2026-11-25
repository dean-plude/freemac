// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Swift half of an app written in both languages, as Hex Fiend and
// Gas Mask are: classes marked @objc, which mixed.m uses through the header
// ferry-swiftc writes for them (Mixed-Swift.h).

import Foundation

@objc(FGreeter) public final class Greeter: NSObject {
    @objc public var name: String = "world"
    @objc public private(set) var names: [String] = []

    @objc public static func shared() -> Greeter { Greeter() }

    @objc public func greeting() -> String {
        names.append(name)
        return "Hello, \(name), from Swift"
    }

    @objc(countOfLettersIn:) public func countOfLetters(in s: String) -> Int {
        s.filter { $0.isLetter }.count
    }
}

/// A Swift class whose description, as NSObject's -description, the
/// Objective-C half prints with %@.
@objc(FPoint) public final class Point: NSObject {
    @objc public let x: Int, y: Int
    @objc public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
    public override var description: String { "(\(x), \(y))" }
}
