// SPDX-License-Identifier: GPL-3.0-or-later
//
// Layout (freemac 1.227), Ferry's own, after the rules Apple's SwiftUI
// documentation gives: a parent proposes a size (or none, asking for the
// child's ideal size), the child picks its size, and the parent places it.
// Stacks give their fixed children what they ask for and share the rest
// among the children that can grow (spacers, colors, text fields across,
// frames with an infinite maximum).

import AppKit

struct Proposal {
    var width: CGFloat?
    var height: CGFloat?
    init(_ w: CGFloat?, _ h: CGFloat?) { width = w; height = h }
    subscript(_ a: Axis2) -> CGFloat? { a == .horizontal ? width : height }
    static func along(_ a: Axis2, _ main: CGFloat?, _ cross: CGFloat?) -> Proposal {
        a == .horizontal ? Proposal(main, cross) : Proposal(cross, main)
    }
}

extension CGSize {
    subscript(_ a: Axis2) -> CGFloat { a == .horizontal ? width : height }
    static func along(_ a: Axis2, _ main: CGFloat, _ cross: CGFloat) -> CGSize {
        a == .horizontal ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main)
    }
}

private extension Axis2 {
    var other: Axis2 { self == .horizontal ? .vertical : .horizontal }
}

private var parentAxes: [ObjectIdentifier: Axis2] = [:]

enum Layout {
    static let defaultSpacing: CGFloat = 8

    static func parentAxis(_ n: RNode) -> Axis2 { parentAxes[ObjectIdentifier(n)] ?? .vertical }

    /// The size an AppKit control asks for.
    static func natural(_ v: NSView?) -> CGSize {
        guard let v else { return .zero }
        var s = v.fittingSize
        if s.width <= 0 || s.height <= 0 {
            let i = v.intrinsicContentSize
            if i.width > 0 && i.height > 0 { s = i }
        }
        if s.width <= 0 || s.height <= 0 {
            (v as? NSControl)?.sizeToFit()
            s = v.frame.size
        }
        return CGSize(width: ceil(max(s.width, 0)), height: ceil(max(s.height, 0)))
    }

    /// Whether a node takes more room along an axis when there is more.
    static func flexible(_ n: RNode, _ a: Axis2) -> Bool {
        switch n.kind {
        case .spacer: return a == parentAxis(n)
        case .color, .scroll: return true
        case .hosted:
            // an AppKit view with no size of its own takes the room it's given
            let i = n.view?.intrinsicContentSize ?? .zero
            return (a == .horizontal ? i.width : i.height) <= 0
        case .textField, .slider, .progress: return a == .horizontal
        case .divider: return a != parentAxis(n)
        case .frame(let w, let h, _, let maxW, _, let maxH, _):
            let fixed = a == .horizontal ? w : h
            let maxV = a == .horizontal ? maxW : maxH
            if fixed != nil { return false }
            if let m = maxV { return m == .infinity }
            return n.children.contains { flexible($0, a) }
        case .stack(let axis, _, _):
            let kids = n.children.flatMap { $0.flattened }
            for k in kids { parentAxes[ObjectIdentifier(k)] = axis }
            return kids.contains { flexible($0, a) }
        case .group, .zstack, .padding, .background, .section:
            return n.children.contains { flexible($0, a) }
        default: return false
        }
    }

    static func size(_ n: RNode, _ p: Proposal) -> CGSize {
        switch n.kind {
        case .empty: return .zero
        case .group:
            return stackSize(n.children.flatMap { $0.flattened }, .vertical, defaultSpacing, p).size
        case .text, .button, .toggle, .image, .stepper, .picker:
            return natural(n.view)
        case .hosted:
            let i = n.view?.intrinsicContentSize ?? .zero
            return CGSize(width: i.width > 0 ? i.width : p.width ?? 100, height: i.height > 0 ? i.height : p.height ?? 100)
        case .textField:
            return CGSize(width: max(p.width ?? 160, 40), height: max(natural(n.view).height, 22))
        case .slider:
            return CGSize(width: max(p.width ?? 160, 40), height: max(natural(n.view).height, 21))
        case .progress:
            return CGSize(width: max(p.width ?? 160, 40), height: 16)
        case .spacer(let min):
            let m = min ?? defaultSpacing
            return parentAxis(n) == .horizontal ? CGSize(width: max(p.width ?? m, m), height: 0)
                                                : CGSize(width: 0, height: max(p.height ?? m, m))
        case .divider:
            return parentAxis(n) == .vertical ? CGSize(width: p.width ?? 1, height: 1)
                                              : CGSize(width: 1, height: p.height ?? 1)
        case .color:
            return CGSize(width: p.width ?? 10, height: p.height ?? 10)
        case .stack(let axis, let spacing, _):
            return stackSize(n.children.flatMap { $0.flattened }, axis, spacing, p).size
        case .zstack:
            var s = CGSize.zero
            for c in n.children.flatMap({ $0.flattened }) {
                let cs = size(c, p)
                s = CGSize(width: max(s.width, cs.width), height: max(s.height, cs.height))
            }
            return s
        case .scroll:
            let content = stackSize(n.children.flatMap { $0.flattened }, .vertical, 0, Proposal(p.width, nil)).size
            return CGSize(width: p.width ?? content.width, height: p.height ?? min(content.height, 400))
        case .padding(let e):
            let inner = Proposal(p.width.map { max(0, $0 - e.left - e.right) }, p.height.map { max(0, $0 - e.top - e.bottom) })
            let c = childSize(n, inner)
            return CGSize(width: c.width + e.left + e.right, height: c.height + e.top + e.bottom)
        case .frame(let w, let h, let minW, let maxW, let minH, let maxH, _):
            func dim(_ fixed: CGFloat?, _ lo: CGFloat?, _ hi: CGFloat?, _ proposed: CGFloat?, _ child: () -> CGFloat) -> CGFloat {
                if let fixed { return fixed }
                var v: CGFloat
                if hi == .infinity, let proposed { v = proposed } else { v = child() }
                if let proposed, hi != nil, hi != .infinity { v = min(max(v, proposed), hi!) }
                if let lo { v = max(v, lo) }
                if let hi, hi != .infinity { v = min(v, hi) }
                return v
            }
            let pw = w ?? (maxW == .infinity ? p.width : p.width.map { min($0, maxW ?? $0) })
            let ph = h ?? (maxH == .infinity ? p.height : p.height.map { min($0, maxH ?? $0) })
            let c = childSize(n, Proposal(pw, ph))
            return CGSize(width: dim(w, minW, maxW, p.width) { c.width },
                          height: dim(h, minH, maxH, p.height) { c.height })
        case .background:
            return childSize(n, p)
        case .section(let header):
            var s = stackSize(n.children.flatMap { $0.flattened }, .vertical, 6, p).size
            if header != nil {
                let h = natural(n.view)
                s = CGSize(width: max(s.width, h.width), height: s.height + h.height + 4)
            }
            return s
        case .menu:
            return .zero
        }
    }

    private static func childSize(_ n: RNode, _ p: Proposal) -> CGSize {
        let kids = n.children.flatMap { $0.flattened }
        if kids.count == 1 { return size(kids[0], p) }
        return stackSize(kids, .vertical, defaultSpacing, p).size
    }

    /// Each child's size along a stack, and the stack's.
    static func stackSize(_ kids: [RNode], _ axis: Axis2, _ spacing: CGFloat, _ p: Proposal) -> (size: CGSize, sizes: [CGSize]) {
        for k in kids { parentAxes[ObjectIdentifier(k)] = axis }
        if kids.isEmpty { return (.zero, []) }
        let cross = p[axis.other]
        var sizes = [CGSize](repeating: .zero, count: kids.count)
        var fixed: CGFloat = 0
        var flex: [Int] = []
        for (i, k) in kids.enumerated() {
            if flexible(k, axis) {
                flex.append(i)
            } else {
                sizes[i] = size(k, Proposal.along(axis, p[axis], cross))
                fixed += sizes[i][axis]
            }
        }
        let gaps = spacing * CGFloat(kids.count - 1)
        if let main = p[axis] {
            var left = max(0, main - fixed - gaps)
            var rest = flex.count
            for i in flex {
                let share = left / CGFloat(rest)
                sizes[i] = size(kids[i], Proposal.along(axis, share, cross))
                left -= sizes[i][axis]
                rest -= 1
            }
        } else {
            for i in flex { sizes[i] = size(kids[i], Proposal.along(axis, nil, cross)) }
        }
        let mainTotal = sizes.reduce(0) { $0 + $1[axis] } + gaps
        var crossTotal = sizes.reduce(0) { max($0, $1[axis.other]) }
        if let cross, kids.contains(where: { flexible($0, axis.other) }) { crossTotal = max(crossTotal, cross) }
        return (CGSize.along(axis, mainTotal, crossTotal), sizes)
    }

    // ---- placing

    static func place(_ n: RNode, _ r: CGRect) {
        switch n.kind {
        case .empty, .menu: return
        case .group:
            placeStack(n.children.flatMap { $0.flattened }, .vertical, defaultSpacing, 0, r)
        case .stack(let axis, let spacing, let alignment):
            placeStack(n.children.flatMap { $0.flattened }, axis, spacing, alignment, r)
        case .zstack:
            for c in n.children.flatMap({ $0.flattened }) {
                let s = size(c, Proposal(r.width, r.height))
                place(c, CGRect(x: r.minX + (r.width - s.width) / 2, y: r.minY + (r.height - s.height) / 2,
                                width: s.width, height: s.height))
            }
        case .scroll:
            placeStack(n.children.flatMap { $0.flattened }, .vertical, 0, -1,
                       CGRect(x: r.minX, y: r.minY, width: r.width,
                              height: stackSize(n.children.flatMap { $0.flattened }, .vertical, 0, Proposal(r.width, nil)).size.height))
        case .padding(let e):
            placeChildren(n, CGRect(x: r.minX + e.left, y: r.minY + e.top,
                                    width: max(0, r.width - e.left - e.right), height: max(0, r.height - e.top - e.bottom)))
        case .frame(_, _, _, _, _, _, let alignment):
            let kids = n.children.flatMap { $0.flattened }
            let s = kids.count == 1 ? size(kids[0], Proposal(r.width, r.height))
                                    : stackSize(kids, .vertical, defaultSpacing, Proposal(r.width, r.height)).size
            let w = min(s.width, r.width), h = min(s.height, r.height)
            let x = r.minX + (r.width - w) * CGFloat(alignment.h + 1) / 2
            let y = r.minY + (r.height - h) * CGFloat(alignment.v + 1) / 2
            placeChildren(n, CGRect(x: x, y: y, width: w, height: h))
        case .background:
            set(n.view, r)
            placeChildren(n, r)
        case .section(let header):
            var top = r.minY
            if header != nil {
                let h = natural(n.view)
                set(n.view, CGRect(x: r.minX, y: top, width: h.width, height: h.height))
                top += h.height + 4
            }
            placeStack(n.children.flatMap { $0.flattened }, .vertical, 6, -1,
                       CGRect(x: r.minX, y: top, width: r.width, height: max(0, r.maxY - top)))
        default:
            set(n.view, r)
        }
    }

    private static func placeChildren(_ n: RNode, _ r: CGRect) {
        let kids = n.children.flatMap { $0.flattened }
        if kids.count == 1 { place(kids[0], r) } else { placeStack(kids, .vertical, defaultSpacing, 0, r) }
    }

    private static func set(_ v: NSView?, _ r: CGRect) {
        guard let v else { return }
        let f = CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
        if v.frame != f { v.frame = f }
    }

    private static func placeStack(_ kids: [RNode], _ axis: Axis2, _ spacing: CGFloat, _ alignment: Int, _ r: CGRect) {
        let (total, sizes) = stackSize(kids, axis, spacing, Proposal(r.width, r.height))
        let crossExtent = max(total[axis.other], r.size[axis.other])
        var pos: CGFloat = axis == .horizontal ? r.minX : r.minY
        // a stack smaller than its room along its axis sits in the middle
        pos += max(0, (r.size[axis] - total[axis]) / 2)
        for (i, k) in kids.enumerated() {
            var s = sizes[i]
            if flexible(k, axis.other) {
                s = CGSize.along(axis, s[axis], crossExtent)
            }
            let crossRoom = crossExtent - s[axis.other]
            let crossStart = (axis == .horizontal ? r.minY : r.minX) + crossRoom * CGFloat(alignment + 1) / 2
            let rect = axis == .horizontal ? CGRect(x: pos, y: crossStart, width: s.width, height: s.height)
                                           : CGRect(x: crossStart, y: pos, width: s.width, height: s.height)
            place(k, rect)
            pos += s[axis] + spacing
        }
    }
}
