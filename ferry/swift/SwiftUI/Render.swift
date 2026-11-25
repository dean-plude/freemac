// SPDX-License-Identifier: GPL-3.0-or-later
//
// How Ferry's SwiftUI draws (freemac 1.227); Ferry's own design.
//
//   1. resolve: the root view's body is run, and its body's body, down to
//      the views Ferry draws itself (Text, Button, the stacks...), which
//      make a tree of RNodes. Each view's place in the tree is its path
//      (the type of each view on the way down and its index among its
//      siblings, or its ForEach identifier), and a Slot kept for each path
//      holds its @State and the like from one pass to the next.
//   2. reconcile: each node that is an AppKit control gets the NSView kept
//      for its path, made the first time, and is brought up to date.
//   3. layout: sizes are worked out in Swift, in the way Apple's
//      documentation describes SwiftUI's: a parent proposes a size, a child
//      chooses its own, and stacks share what is left among the children
//      that can grow. The views then get their frames, in a flipped
//      hosting view.
//
// Any change of state runs all three again, soon after (coalesced).

import AppKit

// ---- the resolved tree -----------------------------------------------------------------

enum Axis2 { case horizontal, vertical }

final class RNode {
    enum Kind {
        case empty, group
        case text(String)
        case button(String, () -> Void)
        case toggle(String, Binding<Bool>)
        case textField(String, Binding<String>, secure: Bool)
        case slider(Binding<Double>, ClosedRange<Double>)
        case stepper(String, () -> Void, () -> Void)
        case picker(String, [String], Int, (Int) -> Void)
        case progress(Double?)
        case spacer(CGFloat?)
        case divider
        case color(Color)
        case image(String)
        case stack(Axis2, CGFloat, alignment: Int)    // alignment: -1 leading/top, 0 center, 1 trailing/bottom
        case zstack
        case scroll
        case padding(NSEdgeInsets)
        case frame(width: CGFloat?, height: CGFloat?, minWidth: CGFloat?, maxWidth: CGFloat?,
                   minHeight: CGFloat?, maxHeight: CGFloat?, alignment: Alignment)
        case background(Color)
        case section(String?)
        case menu(String)
        case hosted(make: () -> NSView, update: (NSView) -> Void)   // an NSViewRepresentable's view
    }

    var kind: Kind
    var children: [RNode]
    var path = ""
    var font: Font?
    var foreground: Color?
    var enabled = true
    var help: String?
    var tag: AnyHashable?
    var view: NSView?

    init(_ kind: Kind, children: [RNode] = []) {
        self.kind = kind
        self.children = children
    }

    /// The first words in the node, as a picker's choice shows them.
    var firstText: String? {
        if case .text(let s) = kind { return s }
        for c in children { if let s = c.firstText { return s } }
        return nil
    }

    /// The node, its groups opened: what a stack lays out one by one.
    var flattened: [RNode] {
        switch kind {
        case .group: return children.flatMap { $0.flattened }
        case .empty: return []
        default: return [self]
        }
    }
}

// ---- resolving -------------------------------------------------------------------------

/// Where in the tree a view is being resolved, and what it inherits.
final class ResolveContext {
    unowned let host: HostCore
    let path: String
    var environment: EnvironmentValues

    init(host: HostCore, path: String, environment: EnvironmentValues) {
        self.host = host
        self.path = path
        self.environment = environment
    }

    func child(_ component: String) -> ResolveContext {
        ResolveContext(host: host, path: path + "/" + component, environment: environment)
    }

    func resolve(_ view: any View, at index: Int) -> RNode {
        child("\(index)").resolve(view)
    }

    func resolve(_ view: any View, key: AnyHashable) -> RNode {
        child("#\(key.hashValue)").resolve(view)
    }

    /// The node for a view, here.
    func resolve(_ view: any View) -> RNode {
        let cx = child(String(describing: type(of: view)))
        let node: RNode
        if let p = view as? _PrimitiveView {
            node = p._resolve(cx)
        } else if let r = view as? any NSViewRepresentable {
            node = r._hostedNode(cx)
        } else {
            cx.attachProperties(of: view)
            node = cx.resolveBody(of: view)
        }
        if node.path.isEmpty { node.path = cx.path }
        if node.font == nil { node.font = environment.font }
        if node.foreground == nil { node.foreground = environment.foreground }
        if !environment.isEnabled { node.enabled = false }
        return node
    }

    private func resolveBody<V: View>(of view: V) -> RNode {
        resolve(view.body)
    }

    /// Points the view's @State and the like at the storage for this place.
    func attachProperties(of view: Any) {
        let slot = host.slot(path)
        var key = 0
        for child in Mirror(reflecting: view).children {
            key += 1
            if let p = child.value as? _AttachableProperty {
                p._attach(to: slot, key: key, cx: self)
            }
        }
        host.visited.insert(path)
    }
}

// ---- the hosting core: slots, views and passes ------------------------------------------

final class ActionTarget: NSObject {
    var action: () -> Void = {}
    @objc func fire(_ sender: Any?) { action() }
}

/// A hosting view's state between passes.
final class HostCore {
    var root: () -> any View
    var slots: [String: Slot] = [:]
    var visited: Set<String> = []
    var views: [String: NSView] = [:]
    var targets: [String: ActionTarget] = [:]
    var appearHandlers: [() -> Void] = []
    var environment = EnvironmentValues()
    weak var container: NSView?
    var tree: RNode?
    var pending = false
    var updating = false
    var onInvalidate: (() -> Void)?
    var title: String?
    var onUpdate: (() -> Void)?
    static var all: [Weak] = []

    final class Weak { weak var core: HostCore?; init(_ c: HostCore) { core = c } }

    init(root: @escaping () -> any View) {
        self.root = root
        HostCore.all.append(Weak(self))
    }

    func slot(_ path: String) -> Slot {
        if let s = slots[path] { return s }
        let s = Slot()
        slots[path] = s
        return s
    }

    /// State changed: run the bodies again, soon (once for many changes).
    func invalidate() {
        if pending { return }
        pending = true
        Scheduler.shared.later { [weak self] in
            guard let self, self.pending else { return }
            self.update()
        }
        onInvalidate?()
    }

    /// Run the bodies, bring the views up to date and lay them out.
    func update() {
        pending = false
        guard let container, !updating else { return }
        updating = true
        defer { updating = false }
        visited = []
        let cx = ResolveContext(host: self, path: "", environment: environment)
        let tree = cx.resolve(root())
        self.tree = tree
        var used = Set<String>()
        var order: [NSView] = []
        reconcile(tree, used: &used, order: &order)
        for (path, v) in views where !used.contains(path) {
            v.removeFromSuperview()
            views[path] = nil
            targets[path] = nil
        }
        // state kept only for the views still there
        slots = slots.filter { visited.contains($0.key) }
        // the views in the order of the tree, a background before what's on it
        let current: [NSView] = container.subviews ?? []
        if current.count != order.count || zip(current, order).contains(where: { $0 !== $1 }) {
            container.subviews = order
        }
        layout()
        onUpdate?()
        let handlers = appearHandlers
        appearHandlers = []
        for h in handlers { h() }
    }

    /// The size the content would like, given a proposal (nil: its ideal size).
    func fittingSize(_ proposal: CGSize?) -> CGSize {
        if tree == nil, container != nil { update() }
        guard let tree else { return .zero }
        return Layout.size(tree, Proposal(proposal?.width, proposal?.height))
    }

    func layout() {
        guard let container, let tree else { return }
        let bounds = container.bounds
        let size = Layout.size(tree, Proposal(bounds.width, bounds.height))
        let origin = CGPoint(x: max(0, (bounds.width - size.width) / 2), y: max(0, (bounds.height - size.height) / 2))
        Layout.place(tree, CGRect(origin: origin, size: size))
    }

    // ---- views for nodes

    private func view<V: NSView>(_ path: String, _ make: () -> V) -> V {
        if let v = views[path] as? V { return v }
        views[path]?.removeFromSuperview()
        let v = make()
        views[path] = v
        return v
    }

    private func target(_ path: String, _ action: @escaping () -> Void) -> ActionTarget {
        let t = targets[path] ?? ActionTarget()
        t.action = action
        targets[path] = t
        return t
    }

    private func reconcile(_ n: RNode, used: inout Set<String>, order: inout [NSView]) {
        let p = n.path
        var made: NSView?
        switch n.kind {
        case .text(let s):
            let f = view(p) { NSTextField(labelWithString: s) }
            if f.stringValue != s { f.stringValue = s }
            f.font = n.font?.nsFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            f.textColor = n.foreground?.nsColor ?? NSColor.label
            made = f
        case .button(let title, let action):
            let b = view(p) { NSButton(title: title, target: nil, action: nil) }
            if b.title != title { b.title = title }
            let t = target(p, action)
            b.target = t
            b.action = #selector(ActionTarget.fire(_:))
            if let font = n.font { b.font = font.nsFont }
            made = b
        case .toggle(let title, let binding):
            let b = view(p) { NSButton(checkboxWithTitle: title, target: nil, action: nil) }
            if b.title != title { b.title = title }
            b.state = binding.wrappedValue ? .on : .off
            let t = target(p) { [weak b] in binding.wrappedValue = b?.state == NSControl.StateValue.on }
            b.target = t
            b.action = #selector(ActionTarget.fire(_:))
            made = b
        case .textField(let placeholder, let binding, let secure):
            let f = view(p) { secure ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero) }
            f.placeholderString = placeholder
            if f.stringValue != binding.wrappedValue { f.stringValue = binding.wrappedValue }
            let t = target(p) { [weak f] in binding.wrappedValue = f?.stringValue ?? "" }
            f.target = t
            f.action = #selector(ActionTarget.fire(_:))
            made = f
        case .slider(let binding, let range):
            let s = view(p) { NSSlider(frame: .zero) }
            s.minValue = range.lowerBound
            s.maxValue = range.upperBound
            s.doubleValue = binding.wrappedValue
            let t = target(p) { [weak s] in binding.wrappedValue = s?.doubleValue ?? 0 }
            s.target = t
            s.action = #selector(ActionTarget.fire(_:))
            made = s
        case .stepper(let title, let up, let down):
            let b = view(p) { NSSegmentedControl(frame: .zero) }
            b.segmentCount = 2
            b.setLabel("-", forSegment: 0)
            b.setLabel("+", forSegment: 1)
            b.trackingMode = .momentary
            let t = target(p) { [weak b] in if b?.selectedSegment == 1 { up() } else { down() } }
            b.target = t
            b.action = #selector(ActionTarget.fire(_:))
            b.toolTip = title
            made = b
        case .picker(_, let items, let selected, let choose):
            let b = view(p) { NSPopUpButton(frame: .zero, pullsDown: false) }
            let titles = (b.itemTitles as [Any]? ?? []).compactMap { $0 as? String }
            if titles != items {
                b.removeAllItems()
                b.addItems(withTitles: items)
            }
            if selected >= 0 && selected < items.count { b.selectItem(at: selected) }
            let t = target(p) { [weak b] in choose(b?.indexOfSelectedItem ?? -1) }
            b.target = t
            b.action = #selector(ActionTarget.fire(_:))
            made = b
        case .progress(let value):
            let v = view(p) { NSProgressIndicator(frame: .zero) }
            v.isIndeterminate = value == nil
            if let value { v.minValue = 0; v.maxValue = 1; v.doubleValue = value }
            made = v
        case .divider:
            let b = view(p) { NSBox(frame: .zero) }
            b.boxType = .separator
            made = b
        case .color(let c), .background(let c):
            let v = view(p + "@color") { ColorView(frame: .zero) }
            v.color = c.nsColor
            made = v
        case .image(let name):
            let f = view(p) { NSTextField(labelWithString: name) }
            f.stringValue = Image.glyph(name)
            f.font = n.font?.nsFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            f.textColor = n.foreground?.nsColor ?? NSColor.label
            made = f
        case .hosted(let make, let update):
            let v = view(p + "@hosted") { make() }
            update(v)
            made = v
        case .section(let header?):
            let f = view(p + "@header") { NSTextField(labelWithString: header) }
            f.stringValue = header
            f.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            f.textColor = NSColor.secondaryLabel
            made = f
        default:
            break
        }
        if let v = made {
            n.view = v
            used.insert(views.first(where: { $0.value === v })?.key ?? p)
            if let c = v as? NSControl { c.isEnabled = n.enabled }
            if let h = n.help { v.toolTip = h }
            order.append(v)
        }
        for c in n.children { reconcile(c, used: &used, order: &order) }
    }
}

/// A view filled with one color.
final class ColorView: NSView {
    var color: NSColor = NSColor.clear { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        color.set()
        NSRectFill(bounds)
    }
}

/// Runs things soon, on the main thread, after the event being handled.
final class Scheduler: NSObject {
    static let shared = Scheduler()
    private var queue: [() -> Void] = []
    func later(_ f: @escaping () -> Void) {
        queue.append(f)
        if queue.count == 1 {
            perform(#selector(drain), with: nil, afterDelay: 0)
        }
    }
    @objc private func drain() {
        let q = queue
        queue = []
        for f in q { f() }
    }
}
