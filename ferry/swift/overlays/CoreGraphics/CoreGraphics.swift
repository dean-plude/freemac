// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for CoreGraphics (freemac 1.227): CGFloat (in
// CGFloat.swift, from swift-corelibs-foundation) and what Swift code
// expects of the geometry types: .zero, CGRect(x:y:width:height:), the
// min/mid/max edges, insetting and containment, and equality. Written for
// Ferry from Apple's public documentation of these members; not Apple's
// overlay.

@_exported import CoreGraphics

extension CGPoint {
    public static var zero: CGPoint { CGPoint(x: 0, y: 0) }
    public init(x: Int, y: Int) { self.init(x: CGFloat(x), y: CGFloat(y)) }
    public init(x: Double, y: Double) { self.init(x: CGFloat(x), y: CGFloat(y)) }
}

extension CGPoint: Equatable {
    public static func == (a: CGPoint, b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }
}

extension CGPoint: CustomDebugStringConvertible {
    public var debugDescription: String { "(\(x), \(y))" }
}

extension CGSize {
    public static var zero: CGSize { CGSize(width: 0, height: 0) }
    public init(width: Int, height: Int) { self.init(width: CGFloat(width), height: CGFloat(height)) }
    public init(width: Double, height: Double) { self.init(width: CGFloat(width), height: CGFloat(height)) }
}

extension CGSize: Equatable {
    public static func == (a: CGSize, b: CGSize) -> Bool { a.width == b.width && a.height == b.height }
}

extension CGSize: CustomDebugStringConvertible {
    public var debugDescription: String { "(\(width), \(height))" }
}

extension CGVector {
    public static var zero: CGVector { CGVector(dx: 0, dy: 0) }
}

extension CGRect {
    public static var zero: CGRect { CGRect(origin: .zero, size: .zero) }
    public static var null: CGRect { CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0) }

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    /// The rectangle with a positive width and height.
    public var standardized: CGRect {
        var r = self
        if r.size.width < 0 { r.origin.x += r.size.width; r.size.width = -r.size.width }
        if r.size.height < 0 { r.origin.y += r.size.height; r.size.height = -r.size.height }
        return r
    }

    public var width: CGFloat { abs(size.width) }
    public var height: CGFloat { abs(size.height) }
    public var minX: CGFloat { standardized.origin.x }
    public var minY: CGFloat { standardized.origin.y }
    public var maxX: CGFloat { standardized.origin.x + width }
    public var maxY: CGFloat { standardized.origin.y + height }
    public var midX: CGFloat { minX + width / 2 }
    public var midY: CGFloat { minY + height / 2 }
    public var isNull: Bool { origin.x.isInfinite || origin.y.isInfinite }
    public var isEmpty: Bool { isNull || size.width == 0 || size.height == 0 }

    public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        let r = standardized
        let out = CGRect(x: r.origin.x + dx, y: r.origin.y + dy,
                         width: r.size.width - 2 * dx, height: r.size.height - 2 * dy)
        return out.size.width < 0 || out.size.height < 0 ? .null : out
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: origin.x + dx, y: origin.y + dy, width: size.width, height: size.height)
    }

    public func contains(_ p: CGPoint) -> Bool {
        !isNull && p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func intersects(_ r: CGRect) -> Bool { !intersection(r).isEmpty }

    public func intersection(_ r: CGRect) -> CGRect {
        if isNull || r.isNull { return .null }
        let x0 = Swift.max(minX, r.minX), y0 = Swift.max(minY, r.minY)
        let x1 = Swift.min(maxX, r.maxX), y1 = Swift.min(maxY, r.maxY)
        return x1 < x0 || y1 < y0 ? .null : CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func union(_ r: CGRect) -> CGRect {
        if isNull { return r }
        if r.isNull { return self }
        let x0 = Swift.min(minX, r.minX), y0 = Swift.min(minY, r.minY)
        return CGRect(x: x0, y: y0, width: Swift.max(maxX, r.maxX) - x0, height: Swift.max(maxY, r.maxY) - y0)
    }
}

extension CGRect: Equatable {
    public static func == (a: CGRect, b: CGRect) -> Bool { a.origin == b.origin && a.size == b.size }
}

extension CGRect: CustomDebugStringConvertible {
    public var debugDescription: String { "(\(origin.x), \(origin.y), \(size.width), \(size.height))" }
}

extension CGAffineTransform {
    public static var identity: CGAffineTransform { CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
}

// MARK: - dictionaries (freemac 1.260)

extension CGRect {
    /// The rectangle a dictionary made by dictionaryRepresentation holds.
    public init?(dictionaryRepresentation dict: CFDictionary) {
        var r = CGRect(x: 0, y: 0, width: 0, height: 0)
        guard CGRectMakeWithDictionaryRepresentation(dict, &r) else { return nil }
        self = r
    }
}
