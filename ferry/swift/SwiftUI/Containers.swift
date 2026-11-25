// SPDX-License-Identifier: GPL-3.0-or-later
//
// More containers and the gestures Ferry takes (freemac 1.227), with the
// names Apple's SwiftUI documentation gives them: GroupBox, the lazy stacks
// and grids (laid out at once, as plain stacks and rows), and the gesture
// modifiers, which Ferry accepts and does not act on yet.

import AppKit

/// Views in a box.
public struct GroupBox<Label: View, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    var title: String? = nil
    let content: Content
    func _resolve(_ cx: ResolveContext) -> RNode {
        let box = RNode(.background(Color(white: 0, opacity: 0.05)), children: [
            RNode(.padding(NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)), children: [cx.resolve(content, at: 0)]),
        ])
        guard let title else { return box }
        return RNode(.stack(.vertical, 4, alignment: -1), children: [cx.resolve(Text(title), at: 1), box])
    }
}

extension GroupBox where Label == EmptyView {
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
}

extension GroupBox where Label == Text {
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
}

/// A VStack whose views Apple's SwiftUI makes as they scroll into sight;
/// Ferry makes them all.
public typealias LazyVStack = VStack
/// An HStack whose views are made as they scroll into sight.
public typealias LazyHStack = HStack

/// A column of a grid.
public struct GridItem: Hashable, Sendable {
    public enum Size: Hashable, Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
    public var size: Size
    public var spacing: CGFloat?
    public var alignment: Alignment?
    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

/// Views in rows of as many columns as it is given.
public struct LazyVGrid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: Any? = nil, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func _resolve(_ cx: ResolveContext) -> RNode {
        let cells = cx.resolve(content, at: 0).flattened
        let n = max(1, columns.count)
        var rows: [RNode] = []
        var i = 0
        while i < cells.count {
            let row = Array(cells[i ..< min(i + n, cells.count)]).enumerated().map { c, cell -> RNode in
                if case .fixed(let w) = columns[c].size {
                    return RNode(.frame(width: w, height: nil, minWidth: nil, maxWidth: nil, minHeight: nil,
                                        maxHeight: nil, alignment: .leading), children: [cell])
                }
                return RNode(.frame(width: nil, height: nil, minWidth: nil, maxWidth: .infinity, minHeight: nil,
                                    maxHeight: nil, alignment: Alignment(h: alignment.value, v: 0)), children: [cell])
            }
            rows.append(RNode(.stack(.horizontal, columns.first?.spacing ?? Layout.defaultSpacing, alignment: 0), children: row))
            i += n
        }
        return RNode(.stack(.vertical, spacing ?? Layout.defaultSpacing, alignment: alignment.value), children: rows)
    }
}

/// Views in rows, each a GridRow, their columns lined up (as far as Ferry's
/// stacks line them up).
public struct Grid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.vertical, verticalSpacing ?? Layout.defaultSpacing, alignment: alignment.h), children: [cx.resolve(content, at: 0)])
    }
}

/// A row of a Grid.
public struct GridRow<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) { self.content = content() }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.horizontal, Layout.defaultSpacing, alignment: 0), children: [cx.resolve(content, at: 0)])
    }
}

// ---- gestures: taken, not yet acted on

public protocol Gesture {}

public struct TapGesture: Gesture {
    public init(count: Int = 1) {}
    public func onEnded(_ action: @escaping () -> Void) -> TapGesture { self }
}

public struct LongPressGesture: Gesture {
    public init(minimumDuration: Double = 0.5) {}
    public func onEnded(_ action: @escaping (Bool) -> Void) -> LongPressGesture { self }
}

extension View {
    public func gesture<G: Gesture>(_ gesture: G) -> some View { self }
    public func simultaneousGesture<G: Gesture>(_ gesture: G) -> some View { self }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { self }
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View { self }
    public func contentShape<S>(_ shape: S) -> some View { self }
    public func accessibilityLabel(_ label: String) -> some View { self }
    public func accessibilityLabel(_ label: Text) -> some View { self }
    public func accessibilityIdentifier(_ id: String) -> some View { self }
    public func truncationMode(_ mode: Text.TruncationMode) -> some View { self }
    public func allowsHitTesting(_ enabled: Bool) -> some View { self }
    public func zIndex(_ value: Double) -> some View { self }
}

extension Text {
    public enum TruncationMode: Hashable, Sendable { case head, middle, tail }
}

// ---- focus: kept, not yet given to the views

/// Which view has the keyboard focus. Ferry keeps the value it is given;
/// it doesn't yet move AppKit's focus to match, or follow it.
@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty {
    final class Box { var value: Value; init(_ v: Value) { value = v } }
    let box: Box
    public init() where Value == Bool { box = Box(false) }
    public init<T: Hashable>() where Value == T? { box = Box(nil) }
    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: Binding { Binding(box: box) }

    /// The focus state, passed to the views that may take focus.
    public struct Binding {
        let box: Box
        public var wrappedValue: Value {
            get { box.value }
            nonmutating set { box.value = newValue }
        }
    }
}

extension View {
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View { self }
    public func focused<V: Hashable>(_ binding: FocusState<V>.Binding, equals value: V) -> some View { self }
}
