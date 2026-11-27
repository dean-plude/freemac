// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's AppKit overlay (freemac 1.230): what AppKit's Swift side adds
// to the Objective-C framework, so Swift apps' code reads as it does on a
// Mac. Written for Ferry from Apple's public documentation of the Swift
// names; the values are AppKit's own constants, as Ferry's headers give
// them.
@_exported import AppKit
import Foundation

// MARK: - modal responses

extension NSApplication.ModalResponse {
    public static var OK: NSApplication.ModalResponse { .init(rawValue: 1) }
    public static var cancel: NSApplication.ModalResponse { .init(rawValue: 0) }
    public static var stop: NSApplication.ModalResponse { .init(rawValue: -1000) }
    public static var abort: NSApplication.ModalResponse { .init(rawValue: -1001) }
    public static var `continue`: NSApplication.ModalResponse { .init(rawValue: -1002) }
    public static var alertFirstButtonReturn: NSApplication.ModalResponse { .init(rawValue: 1000) }
    public static var alertSecondButtonReturn: NSApplication.ModalResponse { .init(rawValue: 1001) }
    public static var alertThirdButtonReturn: NSApplication.ModalResponse { .init(rawValue: 1002) }
}

// MARK: - status items

extension NSStatusItem {
    /// A status item as wide as what it shows.
    public static var variableLength: CGFloat { -1 }
    /// A status item as wide as the menu bar is high.
    public static var squareLength: CGFloat { -2 }
}

// MARK: - control states as numbers

extension NSControl.StateValue: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSNumber { NSNumber(value: rawValue) }
    public static func _forceBridgeFromObjectiveC(_ n: NSNumber, result: inout NSControl.StateValue?) {
        result = NSControl.StateValue(rawValue: Int(n.intValue))
    }
    public static func _conditionallyBridgeFromObjectiveC(_ n: NSNumber, result: inout NSControl.StateValue?) -> Bool {
        result = NSControl.StateValue(rawValue: Int(n.intValue))
        return result != nil
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ n: NSNumber?) -> NSControl.StateValue {
        NSControl.StateValue(rawValue: Int(n?.intValue ?? 0)) ?? .off
    }
}

// MARK: - names that are strings

extension NSImage.Name: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}
extension NSSound.Name: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}
extension NSUserInterfaceItemIdentifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}
extension NSToolbar.Identifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}
extension NSToolbarItem.Identifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

// MARK: - attributed-string keys

extension NSAttributedString.Key: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

// MARK: - keys with no character of their own

extension NSEvent {
    /// A key that types no character of its own: an arrow, a function key,
    /// delete, tab and the like, named by the character AppKit gives it.
    public struct SpecialKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public init(_ rawValue: Int) { self.rawValue = rawValue }

        public var unicodeScalar: Unicode.Scalar { Unicode.Scalar(UInt32(rawValue)) ?? " " }
        /// F1 through F35.
        public var isFunctionKey: Bool { (0xF704...0xF726).contains(rawValue) }

        public static let upArrow = SpecialKey(0xF700)
        public static let downArrow = SpecialKey(0xF701)
        public static let leftArrow = SpecialKey(0xF702)
        public static let rightArrow = SpecialKey(0xF703)
        public static let f1 = SpecialKey(0xF704)
        public static let f2 = SpecialKey(0xF705)
        public static let f3 = SpecialKey(0xF706)
        public static let f4 = SpecialKey(0xF707)
        public static let f5 = SpecialKey(0xF708)
        public static let f6 = SpecialKey(0xF709)
        public static let f7 = SpecialKey(0xF70A)
        public static let f8 = SpecialKey(0xF70B)
        public static let f9 = SpecialKey(0xF70C)
        public static let f10 = SpecialKey(0xF70D)
        public static let f11 = SpecialKey(0xF70E)
        public static let f12 = SpecialKey(0xF70F)
        public static let f13 = SpecialKey(0xF710)
        public static let f14 = SpecialKey(0xF711)
        public static let f15 = SpecialKey(0xF712)
        public static let f16 = SpecialKey(0xF713)
        public static let f17 = SpecialKey(0xF714)
        public static let f18 = SpecialKey(0xF715)
        public static let f19 = SpecialKey(0xF716)
        public static let f20 = SpecialKey(0xF717)
        public static let f21 = SpecialKey(0xF718)
        public static let f22 = SpecialKey(0xF719)
        public static let f23 = SpecialKey(0xF71A)
        public static let f24 = SpecialKey(0xF71B)
        public static let f25 = SpecialKey(0xF71C)
        public static let f26 = SpecialKey(0xF71D)
        public static let f27 = SpecialKey(0xF71E)
        public static let f28 = SpecialKey(0xF71F)
        public static let f29 = SpecialKey(0xF720)
        public static let f30 = SpecialKey(0xF721)
        public static let f31 = SpecialKey(0xF722)
        public static let f32 = SpecialKey(0xF723)
        public static let f33 = SpecialKey(0xF724)
        public static let f34 = SpecialKey(0xF725)
        public static let f35 = SpecialKey(0xF726)
        public static let insert = SpecialKey(0xF727)
        public static let deleteForward = SpecialKey(0xF728)
        public static let home = SpecialKey(0xF729)
        public static let begin = SpecialKey(0xF72A)
        public static let end = SpecialKey(0xF72B)
        public static let pageUp = SpecialKey(0xF72C)
        public static let pageDown = SpecialKey(0xF72D)
        public static let printScreen = SpecialKey(0xF72E)
        public static let scrollLock = SpecialKey(0xF72F)
        public static let pause = SpecialKey(0xF730)
        public static let sysReq = SpecialKey(0xF731)
        public static let `break` = SpecialKey(0xF732)
        public static let reset = SpecialKey(0xF733)
        public static let stop = SpecialKey(0xF734)
        public static let menu = SpecialKey(0xF735)
        public static let user = SpecialKey(0xF736)
        public static let system = SpecialKey(0xF737)
        public static let print = SpecialKey(0xF738)
        public static let clearLine = SpecialKey(0xF739)
        public static let clearDisplay = SpecialKey(0xF73A)
        public static let insertLine = SpecialKey(0xF73B)
        public static let deleteLine = SpecialKey(0xF73C)
        public static let insertCharacter = SpecialKey(0xF73D)
        public static let deleteCharacter = SpecialKey(0xF73E)
        public static let prev = SpecialKey(0xF73F)
        public static let next = SpecialKey(0xF740)
        public static let select = SpecialKey(0xF741)
        public static let execute = SpecialKey(0xF742)
        public static let undo = SpecialKey(0xF743)
        public static let redo = SpecialKey(0xF744)
        public static let find = SpecialKey(0xF745)
        public static let help = SpecialKey(0xF746)
        public static let modeSwitch = SpecialKey(0xF747)
        public static let enter = SpecialKey(0x03)
        public static let backspace = SpecialKey(0x08)
        public static let tab = SpecialKey(0x09)
        public static let newline = SpecialKey(0x0A)
        public static let formFeed = SpecialKey(0x0C)
        public static let carriageReturn = SpecialKey(0x0D)
        public static let backTab = SpecialKey(0x19)
        public static let delete = SpecialKey(0x7F)
        public static let lineSeparator = SpecialKey(0x2028)
        public static let paragraphSeparator = SpecialKey(0x2029)
    }

    /// The special key this key event is for, if it is one.
    public var specialKey: SpecialKey? {
        guard type == .keyDown || type == .keyUp,
              let scalar = charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
        let v = Int(scalar.value)
        switch v {
        case 0x03, 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x19, 0x7F, 0x2028, 0x2029, 0xF700...0xF747:
            return SpecialKey(v)
        default:
            return nil
        }
    }
}

// MARK: - sounds

extension NSSound {
    /// The alert sound, as NSBeep() plays it.
    public static func beep() { NSBeep() }
}

// MARK: - run loop modes

extension NSRunLoop.Mode {
    /// The mode a run loop is in while a control tracks the mouse or a menu
    /// is open. Ferry's run loops don't tell modes apart.
    public static var eventTracking: NSRunLoop.Mode { .init(rawValue: "NSEventTrackingRunLoopMode") }
    /// The mode a run loop is in while a modal panel is up.
    public static var modalPanel: NSRunLoop.Mode { .init(rawValue: "NSModalPanelRunLoopMode") }
}

// MARK: - image literals (freemac 1.260)

extension NSImage {
    /// The image an #imageLiteral (or an image named in an asset catalog)
    /// names, from the app's own resources.
    public convenience init(imageLiteralResourceName name: String) {
        self.init(ferryImageLiteralName: name)
    }
}
