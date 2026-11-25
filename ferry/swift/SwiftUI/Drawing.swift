// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shapes, views layered over and under others, GeometryReader, alerts and
// sheets (freemac 1.230), with the names Apple's SwiftUI documentation
// gives them; Ferry's own code. A shape fills the room it is offered and is
// drawn with AppKit's Bézier paths, filled with its colour (the foreground
// colour, or the text colour, when none is given) or stroked. An overlay or
// a background is offered the size of the view it is on and placed by its
// alignment. A GeometryReader takes the room it is offered and builds its
// content with that size; when the size changes, the bodies run again. An
// alert is an NSAlert, as a sheet on the view's window (or on its own when
// the view is in none), with the buttons of its actions; a sheet is a
// window of its own shown as a sheet on the view's window.

import AppKit

// ---- paths and shapes

/// The outline of a shape: lines, rectangles, ellipses and rounded
/// rectangles, in the coordinates of the room the shape is given.
public struct Path {
    enum Element {
        case move(CGPoint), line(CGPoint), close
        case rect(CGRect), ellipse(CGRect), rounded(CGRect, CGFloat)
        case quad(CGPoint, CGPoint), curve(CGPoint, CGPoint, CGPoint)
    }
    var elements: [Element] = []

    public init() {}
    public init(_ rect: CGRect) { elements = [.rect(rect)] }
    public init(ellipseIn rect: CGRect) { elements = [.ellipse(rect)] }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        elements = [.rounded(rect, cornerRadius)]
    }
    public init(_ build: (inout Path) -> Void) { build(&self) }

    public mutating func move(to p: CGPoint) { elements.append(.move(p)) }
    public mutating func addLine(to p: CGPoint) { elements.append(.line(p)) }
    public mutating func addLines(_ ps: [CGPoint]) {
        guard let first = ps.first else { return }
        move(to: first)
        for p in ps.dropFirst() { addLine(to: p) }
    }
    public mutating func addQuadCurve(to p: CGPoint, control: CGPoint) { elements.append(.quad(p, control)) }
    public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append(.curve(p, control1, control2))
    }
    public mutating func addRect(_ r: CGRect) { elements.append(.rect(r)) }
    public mutating func addEllipse(in r: CGRect) { elements.append(.ellipse(r)) }
    public mutating func addRoundedRect(in r: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        elements.append(.rounded(r, min(cornerSize.width, cornerSize.height)))
    }
    public mutating func closeSubpath() { elements.append(.close) }

    var bezier: NSBezierPath {
        let b = NSBezierPath()
        var last = CGPoint.zero
        for e in elements {
            switch e {
            case .move(let p): b.move(to: p); last = p
            case .line(let p): b.line(to: p); last = p
            case .close: b.close()
            case .rect(let r): b.appendRect(r)
            case .ellipse(let r): b.appendOval(in: r)
            case .rounded(let r, let c): b.appendRoundedRect(r, xRadius: c, yRadius: c)
            case .quad(let p, let c):
                // a quadratic curve as the cubic one it is
                let c1 = CGPoint(x: last.x + 2 / 3 * (c.x - last.x), y: last.y + 2 / 3 * (c.y - last.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
                b.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                last = p
            case .curve(let p, let c1, let c2): b.curve(to: p, controlPoint1: c1, controlPoint2: c2); last = p
            }
        }
        return b
    }
}

public enum RoundedCornerStyle: Hashable, Sendable { case circular, continuous }

/// Something a shape is filled or stroked with: a colour here.
public protocol ShapeStyle {}
extension Color: ShapeStyle {}

/// How a stroke is drawn.
public struct StrokeStyle: Hashable {
    public var lineWidth: CGFloat
    public init(lineWidth: CGFloat = 1) { self.lineWidth = lineWidth }
}

/// A view that is an outline, drawn in the room it is given.
public protocol Shape: View {
    func path(in rect: CGRect) -> Path
}

extension Shape {
    public var body: _ShapeView { _ShapeView(path: { self.path(in: $0) }) }
    public func fill<S: ShapeStyle>(_ style: S) -> _ShapeView { body.fill(style) }
    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> _ShapeView { body.stroke(style, lineWidth: lineWidth) }
    public func stroke<S: ShapeStyle>(_ style: S, style stroke: StrokeStyle) -> _ShapeView {
        body.stroke(style, lineWidth: stroke.lineWidth)
    }
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> _ShapeView {
        body.stroke(style, lineWidth: lineWidth, inset: true)
    }
}

/// A shape as it is drawn: its path, and what fills or strokes it.
public struct _ShapeView: View, _PrimitiveView {
    public typealias Body = Never
    let path: (CGRect) -> Path
    var fillColor: Color?
    var strokeColor: Color?
    var lineWidth: CGFloat = 1
    var inset = false

    public func fill<S: ShapeStyle>(_ style: S) -> _ShapeView {
        var s = self
        s.fillColor = style as? Color
        s.strokeColor = nil
        return s
    }
    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> _ShapeView {
        stroke(style, lineWidth: lineWidth, inset: false)
    }
    func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat, inset: Bool) -> _ShapeView {
        var s = self
        s.strokeColor = (style as? Color) ?? Color.primary
        s.fillColor = nil
        s.lineWidth = lineWidth
        s.inset = inset
        return s
    }

    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.shape(ShapeSpec(path: path, fill: fillColor, stroke: strokeColor, lineWidth: lineWidth, inset: inset)))
    }
}

struct ShapeSpec {
    let path: (CGRect) -> Path
    let fill: Color?
    let stroke: Color?
    let lineWidth: CGFloat
    let inset: Bool
}

public struct Rectangle: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path { Path(rect) }
}

public struct RoundedRectangle: Shape {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
        self.style = style
    }
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = cornerSize
        self.style = style
    }
    public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(cornerSize.width, cornerSize.height))
    }
}

public struct Circle: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height)
        return Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
    }
}

public struct Ellipse: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
}

public struct Capsule: Shape {
    public init(style: RoundedCornerStyle = .continuous) {}
    public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    }
}

/// Draws a shape node.
final class ShapeView: NSView {
    var spec: ShapeSpec? { didSet { needsDisplay = true } }
    var defaultColor = NSColor.labelColor { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let spec else { return }
        if let stroke = spec.stroke {
            let r = spec.inset ? bounds.insetBy(dx: spec.lineWidth / 2, dy: spec.lineWidth / 2) : bounds
            let b = spec.path(r).bezier
            b.lineWidth = spec.lineWidth
            stroke.nsColor.setStroke()
            b.stroke()
        } else {
            (spec.fill?.nsColor ?? defaultColor).setFill()
            spec.path(bounds).bezier.fill()
        }
    }
}

// ---- overlays and backgrounds

extension View {
    /// A view drawn behind this one, offered its size and placed by the alignment.
    public func background<B: View>(_ view: B, alignment: Alignment = .center) -> some View {
        _wrap { n, cx in
            if let c = view as? Color { return RNode(.background(c), children: [n]) }
            let b = cx.child("background").resolve(view)
            return RNode(.layered(primary: 1, alignment: alignment), children: [b, n])
        }
    }
    public func background<B: View>(alignment: Alignment = .center, @ViewBuilder _ content: () -> B) -> some View {
        background(content(), alignment: alignment)
    }
    /// A view drawn over this one, offered its size and placed by the alignment.
    public func overlay<O: View>(_ view: O, alignment: Alignment = .center) -> some View {
        _wrap { n, cx in
            let o = cx.child("overlay").resolve(view)
            return RNode(.layered(primary: 0, alignment: alignment), children: [n, o])
        }
    }
    public func overlay<O: View>(alignment: Alignment = .center, @ViewBuilder _ content: () -> O) -> some View {
        overlay(content(), alignment: alignment)
    }
}

// ---- GeometryReader

/// The size a GeometryReader was given.
public struct GeometryProxy {
    public let size: CGSize
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }
    public func frame(in space: CoordinateSpace) -> CGRect { CGRect(origin: .zero, size: size) }
}

/// Where a frame is measured from; a GeometryReader's own room here.
public enum CoordinateSpace: Hashable {
    case global, local
    case named(AnyHashable)
}

final class _GeometryBox {
    var size = CGSize.zero
}

/// A view built from the size it is given, which takes all the room it is offered.
public struct GeometryReader<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }

    func _resolve(_ cx: ResolveContext) -> RNode {
        let slot = cx.host.slot(cx.path)
        cx.host.visited.insert(cx.path)
        let box = (slot.values[-5] as? _GeometryBox) ?? _GeometryBox()
        slot.values[-5] = box
        let inner = cx.resolve(content(GeometryProxy(size: box.size)), at: 0)
        let host = cx.host
        return RNode(.geometry({ [weak host] size in
            if size != box.size {
                box.size = size
                host?.invalidate()
            }
        }), children: [inner])
    }
}

// ---- alerts and sheets

/// What a view keeps of an alert or a sheet it shows.
final class _Presented {
    var alert: NSAlert?
    var sheet: NSWindow?
    weak var parent: NSWindow?
}

/// The buttons in an alert's actions: their titles and what they do.
private func buttons(in n: RNode) -> [(String, () -> Void)] {
    if case .button(let title, let action) = n.kind { return [(title, action)] }
    return n.children.flatMap { buttons(in: $0) }
}

extension View {
    /// An alert with a title, the buttons of its actions (OK when there
    /// are none) and a message, shown while isPresented is true.
    public func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A,
                                        @ViewBuilder message: () -> M) -> some View {
        let actionsView = actions(), messageView = message()
        return _wrap { n, cx in
            let shown = cx.host.slot(cx.path).presented(-6)
            cx.host.visited.insert(cx.path)
            let wanted = isPresented.wrappedValue
            if wanted && shown.alert == nil {
                let found = buttons(in: cx.child("actions").resolve(actionsView))
                let text = cx.child("message").resolve(messageView).firstText ?? ""
                let host = cx.host
                cx.host.appearHandlers.append {
                    let alert = NSAlert()
                    alert.messageText = title
                    alert.informativeText = text
                    let all = found.isEmpty ? [("OK", {})] : found
                    for (t, _) in all { alert.addButton(withTitle: t) }
                    shown.alert = alert
                    let done: (NSApplication.ModalResponse) -> Void = { response in
                        let i = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                        shown.alert = nil
                        isPresented.wrappedValue = false
                        if i >= 0 && i < all.count { all[i].1() }
                    }
                    if let w = host.container?.window {
                        shown.parent = w
                        alert.beginSheetModal(for: w, completionHandler: done)
                    } else {
                        done(alert.runModal())
                    }
                }
            } else if !wanted, let alert = shown.alert {
                shown.alert = nil
                if let w = shown.parent, let sheet = alert.window as NSWindow? { w.endSheet(sheet) }
            }
            return n
        }
    }
    public func alert<A: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        alert(title, isPresented: isPresented, actions: actions, message: { EmptyView() })
    }
    public func alert<A: View, M: View>(_ title: LocalizedStringKey, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A,
                                        @ViewBuilder message: () -> M) -> some View {
        alert(title.resolved(table: nil, bundle: Bundle.main), isPresented: isPresented, actions: actions, message: message)
    }
    public func alert<A: View>(_ title: LocalizedStringKey, isPresented: Binding<Bool>,
                               @ViewBuilder actions: () -> A) -> some View {
        alert(title.resolved(table: nil, bundle: Bundle.main), isPresented: isPresented, actions: actions,
              message: { EmptyView() })
    }
    public func alert<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A,
                                        @ViewBuilder message: () -> M) -> some View {
        alert(title.string, isPresented: isPresented, actions: actions, message: message)
    }

    /// A sheet showing the content, on the view's window, while isPresented
    /// is true; the content's dismiss action sets it false.
    public func sheet<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> C) -> some View {
        _wrap { n, cx in
            let shown = cx.host.slot(cx.path).presented(-7)
            cx.host.visited.insert(cx.path)
            let wanted = isPresented.wrappedValue
            let host = cx.host
            if wanted && shown.sheet == nil {
                cx.host.appearHandlers.append {
                    guard shown.sheet == nil else { return }
                    let view = _HostingViewBase(root: { content() })
                    view.core.environment.dismiss = DismissAction(close: { isPresented.wrappedValue = false })
                    let size = view.idealSize
                    let w = NSWindow(contentRect: NSMakeRect(0, 0, max(size.width, 120), max(size.height, 40)),
                                     styleMask: [.titled], backing: .buffered, defer: false)
                    w.isReleasedWhenClosed = false
                    w.contentView = view
                    shown.sheet = w
                    if let parent = host.container?.window {
                        shown.parent = parent
                        parent.beginSheet(w, completionHandler: nil)
                    } else {
                        w.makeKeyAndOrderFront(nil)
                    }
                }
            } else if !wanted, let w = shown.sheet {
                shown.sheet = nil
                cx.host.appearHandlers.append {
                    if let parent = shown.parent { parent.endSheet(w) } else { w.orderOut(nil) }
                    onDismiss?()
                }
            }
            return n
        }
    }

    /// A sheet for an item, while the item is there.
    public func sheet<Item: Identifiable, C: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                    @ViewBuilder content: @escaping (Item) -> C) -> some View {
        let presented = Binding<Bool>(get: { item.wrappedValue != nil },
                                      set: { if !$0 { item.wrappedValue = nil } })
        return sheet(isPresented: presented, onDismiss: onDismiss) {
            if let i = item.wrappedValue { content(i) }
        }
    }
}

extension Slot {
    func presented(_ key: Int) -> _Presented {
        if let p = values[key] as? _Presented { return p }
        let p = _Presented()
        values[key] = p
        return p
    }
}
