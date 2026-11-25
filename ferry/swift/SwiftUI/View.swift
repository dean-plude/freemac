// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI (freemac 1.227): the View protocol and the views that
// only hold other views. Written for Ferry from Apple's public SwiftUI
// documentation, with the shape of the API Apple documents; how it works
// underneath is Ferry's own (Render.swift): a view's body is worked out
// again whenever state it reads changes, the result is turned into a tree
// of plain nodes, and those become AppKit views, kept from one pass to the
// next by where they sit in the tree.

// As Apple's does on a Mac, importing SwiftUI imports AppKit and Foundation.
@_exported import AppKit
@_exported import Foundation
@_exported import Combine

/// A piece of user interface, described by its body.
public protocol View {
    associatedtype Body: View
    // (Apple's is @MainActor; Ferry's Swift has no concurrency library yet,
    // and its views are only ever worked out on the main thread.)
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public typealias Body = Never
    public var body: Never { fatalError("Never has no body") }
}

/// The views that are drawn by Ferry itself rather than by a body.
protocol _PrimitiveView {
    func _resolve(_ cx: ResolveContext) -> RNode
}

extension View where Body == Never {
    /// Views drawn by Ferry itself have no body of their own.
    public var body: Never { fatalError("\(Self.self) is drawn by Ferry; it has no body") }
}

/// A view that shows nothing.
public struct EmptyView: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.empty) }
}

/// Views listed one after another, as a view builder makes them.
public struct TupleView<T>: View, _PrimitiveView {
    public typealias Body = Never
    public var value: T
    let children: [any View]
    init(_ value: T, _ children: [any View]) {
        self.value = value
        self.children = children
    }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.group, children: children.enumerated().map { cx.resolve($1, at: $0) })
    }
}

/// Any view, its type hidden.
public struct AnyView: View, _PrimitiveView {
    public typealias Body = Never
    let view: any View
    public init<V: View>(_ view: V) { self.view = view }
    public init<V: View>(erasing view: V) { self.view = view }
    func _resolve(_ cx: ResolveContext) -> RNode { cx.resolve(view, at: 0) }
}

/// Views grouped without laying them out in a stack of their own.
public struct Group<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.group, children: [cx.resolve(content, at: 0)]) }
}

/// One of two views, as an if-else in a view builder chooses.
public struct _ConditionalContent<TrueContent: View, FalseContent: View>: View, _PrimitiveView {
    public typealias Body = Never
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    func _resolve(_ cx: ResolveContext) -> RNode {
        switch storage {
        case .first(let v): return RNode(.group, children: [cx.resolve(v, at: 0)])
        case .second(let v): return RNode(.group, children: [cx.resolve(v, at: 1)])
        }
    }
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
}

extension Optional: _PrimitiveView where Wrapped: View {
    func _resolve(_ cx: ResolveContext) -> RNode {
        switch self {
        case .some(let v): return RNode(.group, children: [cx.resolve(v, at: 0)])
        case .none: return RNode(.empty)
        }
    }
}

/// Builds a view from the views listed in a closure.
@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> {
        TupleView((c0, c1), [c0, c1])
    }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> {
        TupleView((c0, c1, c2), [c0, c1, c2])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> {
        TupleView((c0, c1, c2, c3), [c0, c1, c2, c3])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> {
        TupleView((c0, c1, c2, c3, c4), [c0, c1, c2, c3, c4])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> {
        TupleView((c0, c1, c2, c3, c4, c5), [c0, c1, c2, c3, c4, c5])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6), [c0, c1, c2, c3, c4, c5, c6])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6, c7), [c0, c1, c2, c3, c4, c5, c6, c7])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8), [c0, c1, c2, c3, c4, c5, c6, c7, c8])
    }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9), [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9])
    }
    public static func buildExpression<C: View>(_ c: C) -> C { c }
    public static func buildIf<C: View>(_ c: C?) -> C? { c }
    public static func buildOptional<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> {
        _ConditionalContent(storage: .first(first))
    }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> {
        _ConditionalContent(storage: .second(second))
    }
    public static func buildLimitedAvailability<C: View>(_ c: C) -> AnyView { AnyView(c) }
}

/// A view for each element of a collection, told apart by an identifier.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public var data: Data
    public var content: (Data.Element) -> Content
    let id: (Data.Element) -> ID

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = { $0[keyPath: id] }
        self.content = content
    }

    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.group, children: data.map { cx.resolve(content($0), key: AnyHashable(id($0))) })
    }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}
