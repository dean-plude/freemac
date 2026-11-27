// SPDX-License-Identifier: GPL-3.0-or-later
//
// A few more of the Swift additions a Mac's Foundation makes (freemac
// 1.262, for IINA): for-in over NSArray and NSOrderedSet, NSLog with Swift
// arguments, NSString's and NSMutableString's formats, and undo with a
// closure. Written for Ferry from Apple's documentation of them.

/// Steps through anything that supports fast enumeration (NSArray,
/// NSOrderedSet, NSSet...), a batch of objects at a time.
public struct NSFastEnumerationIterator: IteratorProtocol {
    public typealias Element = Any

    internal let enumerable: NSFastEnumeration
    internal var state = NSFastEnumerationState()
    internal var buffer: [AnyObject?] = Array(repeating: nil, count: 16)
    internal var batch: [Any] = []
    internal var index = 0
    internal var done = false

    public init(_ enumerable: NSFastEnumeration) { self.enumerable = enumerable }

    public mutating func next() -> Any? {
        if index < batch.count {
            index += 1
            return batch[index - 1]
        }
        if done { return nil }
        let n = buffer.withUnsafeMutableBufferPointer { b in
            enumerable.countByEnumerating(with: &state, objects: AutoreleasingUnsafeMutablePointer(b.baseAddress!),
                                          count: b.count)
        }
        if n == 0 {
            done = true
            return nil
        }
        batch = []
        if let items = state.itemsPtr {
            for i in 0..<n { batch.append(items[i] as Any) }
        }
        index = 1
        return batch[0]
    }
}

extension NSArray: Sequence {
    public func makeIterator() -> NSFastEnumerationIterator { NSFastEnumerationIterator(self) }
}

extension NSOrderedSet: Sequence {
    public func makeIterator() -> NSFastEnumerationIterator { NSFastEnumerationIterator(self) }
}

/// Writes a formatted message to the system log, as NSLog does.
public func NSLog(_ format: String, _ args: CVarArg...) {
    withVaList(args) { NSLogv(format, $0) }
}

extension NSString {
    public convenience init(format: __shared NSString, _ args: CVarArg...) {
        let s = withVaList(args) { NSString(format: format as String, arguments: $0) as String }
        self.init(string: s)
    }
}

extension NSMutableString {
    public func appendFormat(_ format: NSString, _ args: CVarArg...) {
        append(withVaList(args) { NSString(format: format as String, arguments: $0) as String })
    }
}

public typealias UndoManager = NSUndoManager

extension NSUndoManager {
    /// Undo by calling the handler with the target.
    public func registerUndo<TargetType: AnyObject>(withTarget target: TargetType,
                                                    handler: @escaping (TargetType) -> Void) {
        let t: Any = target
        registerUndo(withTarget: t, handler: { (x: Any) in handler(x as! TargetType) })
    }
}

/// CFString's encoding numbers that Swift code built on a Mac reads from
/// Foundation.
public var kCFStringEncodingASCII: UInt32 { 0x0600 }
