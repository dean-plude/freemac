// SPDX-License-Identifier: GPL-3.0-or-later
//
// An AppKit view inside Ferry's SwiftUI (freemac 1.227), as Apple's
// NSViewRepresentable documentation describes: the view is made once for
// its place in the tree, by makeNSView, told of every new pass by
// updateNSView, and keeps one coordinator (makeCoordinator) for as long as
// it stays. Written for Ferry.

import AppKit

/// A view that wraps an AppKit view.
public protocol NSViewRepresentable: View where Body == Never {
    associatedtype NSViewType: NSView
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>

    func makeNSView(context: Context) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: Context)
    func makeCoordinator() -> Coordinator
    static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
}

extension NSViewRepresentable where Coordinator == Void {
    public func makeCoordinator() {}
}

extension NSViewRepresentable {
    public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}
}

/// What makeNSView and updateNSView are told: the coordinator, and the
/// environment the view is in.
public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public var environment: EnvironmentValues
}

final class _CoordinatorBox<C> {
    let value: C
    init(_ value: C) { self.value = value }
}

extension NSViewRepresentable {
    /// The node for the wrapped view; its coordinator lives in the place's slot.
    func _hostedNode(_ cx: ResolveContext) -> RNode {
        let slot = cx.host.slot(cx.path)
        let box: _CoordinatorBox<Coordinator>
        if let b = slot.values[-2] as? _CoordinatorBox<Coordinator> {
            box = b
        } else {
            box = _CoordinatorBox(makeCoordinator())
            slot.values[-2] = box
        }
        cx.host.visited.insert(cx.path)
        let context = NSViewRepresentableContext<Self>(coordinator: box.value, environment: cx.environment)
        return RNode(.hosted(make: { self.makeNSView(context: context) },
                             update: { v in
                                 if let v = v as? NSViewType { self.updateNSView(v, context: context) }
                             }))
    }
}
