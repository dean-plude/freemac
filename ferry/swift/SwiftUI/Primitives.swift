// SPDX-License-Identifier: GPL-3.0-or-later
//
// The views Ferry's SwiftUI draws itself (freemac 1.227), with the names
// and initializers Apple's SwiftUI documentation gives them. Each one turns
// into an RNode (Render.swift), which becomes an AppKit control.

import AppKit

// ---- fonts, colors, alignment -----------------------------------------------------------

/// A font, by its role or its size.
public struct Font: Hashable, Sendable {
    public enum Weight: Hashable, Sendable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
        var value: CGFloat {
            switch self {
            case .ultraLight: return -0.8
            case .thin: return -0.6
            case .light: return -0.4
            case .regular: return 0
            case .medium: return 0.23
            case .semibold: return 0.3
            case .bold: return 0.4
            case .heavy: return 0.56
            case .black: return 0.62
            }
        }
    }
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public enum TextStyle: Hashable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    }

    var size: CGFloat
    var weight: Weight
    var design: Design = .default

    // The point sizes macOS's text styles are documented with.
    public static let largeTitle = Font(size: 26, weight: .regular)
    public static let title = Font(size: 22, weight: .regular)
    public static let title2 = Font(size: 17, weight: .regular)
    public static let title3 = Font(size: 15, weight: .regular)
    public static let headline = Font(size: 13, weight: .bold)
    public static let subheadline = Font(size: 11, weight: .regular)
    public static let body = Font(size: 13, weight: .regular)
    public static let callout = Font(size: 12, weight: .regular)
    public static let footnote = Font(size: 10, weight: .regular)
    public static let caption = Font(size: 10, weight: .regular)
    public static let caption2 = Font(size: 10, weight: .regular)

    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        Font(size: size, weight: weight, design: design)
    }
    public static func system(_ style: TextStyle, design: Design = .default) -> Font {
        var f: Font
        switch style {
        case .largeTitle: f = .largeTitle
        case .title: f = .title
        case .title2: f = .title2
        case .title3: f = .title3
        case .headline: f = .headline
        case .subheadline: f = .subheadline
        case .body: f = .body
        case .callout: f = .callout
        case .footnote: f = .footnote
        case .caption: f = .caption
        case .caption2: f = .caption2
        }
        f.design = design
        return f
    }
    public static func custom(_ name: String, size: CGFloat) -> Font { Font(size: size, weight: .regular) }

    public func weight(_ w: Weight) -> Font { var f = self; f.weight = w; return f }
    public func bold() -> Font { weight(.bold) }
    public func monospaced() -> Font { var f = self; f.design = .monospaced; return f }
    public func monospacedDigit() -> Font { self }
    public func italic() -> Font { self }

    var nsFont: NSFont {
        if design == .monospaced, let f = NSFont.userFixedPitchFont(ofSize: size) { return f }
        if weight == .regular { return NSFont.systemFont(ofSize: size) }
        if weight == .bold { return NSFont.boldSystemFont(ofSize: size) }
        return NSFont.systemFont(ofSize: size, weight: weight.value)
    }
}

/// A color, which is also a view that fills its room with it.
public struct Color: View, _PrimitiveView, Hashable, Sendable {
    public typealias Body = Never
    enum Kind: Hashable, Sendable {
        case rgb(Double, Double, Double, Double)
        case named(String)
    }
    let kind: Kind

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        kind = .rgb(red, green, blue, opacity)
    }
    public init(white: Double, opacity: Double = 1) { kind = .rgb(white, white, white, opacity) }
    public init(_ name: String) { kind = .named(name) }
    init(named: String) { kind = .named(named) }

    public static let red = Color(named: "red")
    public static let orange = Color(named: "orange")
    public static let yellow = Color(red: 1, green: 0.8, blue: 0)
    public static let green = Color(named: "green")
    public static let mint = Color(red: 0, green: 0.78, blue: 0.75)
    public static let teal = Color(red: 0.19, green: 0.69, blue: 0.78)
    public static let cyan = Color(red: 0.2, green: 0.68, blue: 0.9)
    public static let blue = Color(named: "blue")
    public static let indigo = Color(red: 0.35, green: 0.34, blue: 0.84)
    public static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)
    public static let pink = Color(red: 1, green: 0.18, blue: 0.33)
    public static let brown = Color(red: 0.64, green: 0.52, blue: 0.37)
    public static let white = Color(white: 1)
    public static let gray = Color(white: 0.56)
    public static let black = Color(white: 0)
    public static let clear = Color(white: 0, opacity: 0)
    public static let primary = Color(named: "label")
    public static let secondary = Color(named: "secondaryLabel")
    public static let accentColor = Color(named: "accent")

    public func opacity(_ o: Double) -> Color {
        if case .rgb(let r, let g, let b, let a) = kind { return Color(red: r, green: g, blue: b, opacity: a * o) }
        return self
    }

    var nsColor: NSColor {
        switch kind {
        case .rgb(let r, let g, let b, let a):
            return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        case .named(let n):
            switch n {
            case "red": return NSColor.systemRed
            case "green": return NSColor.systemGreen
            case "blue": return NSColor.systemBlue
            case "orange": return NSColor.systemOrange
            case "secondaryLabel": return NSColor.secondaryLabel
            case "accent": return NSColor.controlAccent
            default: return NSColor.label
            }
        }
    }

    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.color(self)) }
}

/// Where a view sits in room bigger than it: across and down, -1, 0 or 1.
public struct Alignment: Hashable, Sendable {
    let h: Int, v: Int
    public static let center = Alignment(h: 0, v: 0)
    public static let leading = Alignment(h: -1, v: 0)
    public static let trailing = Alignment(h: 1, v: 0)
    public static let top = Alignment(h: 0, v: -1)
    public static let bottom = Alignment(h: 0, v: 1)
    public static let topLeading = Alignment(h: -1, v: -1)
    public static let topTrailing = Alignment(h: 1, v: -1)
    public static let bottomLeading = Alignment(h: -1, v: 1)
    public static let bottomTrailing = Alignment(h: 1, v: 1)
}

public enum HorizontalAlignment: Hashable, Sendable {
    case leading, center, trailing
    var value: Int { self == .leading ? -1 : self == .center ? 0 : 1 }
}

public enum VerticalAlignment: Hashable, Sendable {
    case top, center, bottom, firstTextBaseline, lastTextBaseline
    var value: Int { switch self { case .top: return -1; case .bottom: return 1; default: return 0 } }
}

public enum Edge: Hashable, Sendable {
    case top, leading, bottom, trailing
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

public struct EdgeInsets: Hashable, Sendable {
    public var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
}

// ---- text and images ---------------------------------------------------------------------

/// Views whose words a button, a toggle or a picker can show as its title.
protocol _TitleView { var _title: String { get } }

func titleOf(_ v: Any) -> String {
    if let t = v as? _TitleView { return t._title }
    if let t = v as? TupleView<(Image, Text)> { return t.value.1._title }
    return ""
}

/// The words of any label view: its texts, in order, worked out where the
/// view is (a button's label may read state).
func titleOf(_ v: any View, in cx: ResolveContext) -> String {
    if let t = v as? _TitleView { return t._title }
    var words: [String] = []
    func walk(_ n: RNode) {
        if case .text(let s) = n.kind, !s.isEmpty { words.append(s) }
        for c in n.children { walk(c) }
    }
    walk(cx.child("label").resolve(v))
    return words.joined(separator: " ")
}

/// Words on the screen.
public struct Text: View, _PrimitiveView, _TitleView {
    public typealias Body = Never
    var string: String
    var font: Font?
    var color: Color?

    public init(_ s: String) { string = s }
    public init<S: StringProtocol>(_ s: S) { string = String(s) }
    public init(verbatim s: String) { string = s }

    var _title: String { string }

    public func font(_ f: Font?) -> Text { var t = self; t.font = f; return t }
    public func bold() -> Text { var t = self; t.font = (t.font ?? .body).bold(); return t }
    public func fontWeight(_ w: Font.Weight?) -> Text { var t = self; t.font = (t.font ?? .body).weight(w ?? .regular); return t }
    public func italic() -> Text { self }
    public func monospacedDigit() -> Text { self }
    public func foregroundColor(_ c: Color?) -> Text { var t = self; t.color = c; return t }

    public static func + (a: Text, b: Text) -> Text {
        var t = a
        t.string += b.string
        return t
    }

    func _resolve(_ cx: ResolveContext) -> RNode {
        let n = RNode(.text(string))
        n.font = font
        n.foreground = color
        return n
    }
}

/// A picture. Ferry has no symbol images of its own, and Apple's may not be
/// used, so a symbol's name stands for one of a few drawn characters, or
/// for nothing.
public struct Image: View, _PrimitiveView, _TitleView {
    public typealias Body = Never
    let name: String
    public init(systemName: String) { name = systemName }
    public init(_ name: String) { self.name = name }

    var _title: String { "" }

    public func resizable() -> Image { self }
    public func renderingMode(_ m: Any?) -> Image { self }
    public func imageScale(_ s: Any?) -> Image { self }

    static func glyph(_ name: String) -> String {
        let map: [String: String] = [
            "plus": "+", "minus": "\u{2212}", "xmark": "\u{2715}", "checkmark": "\u{2713}",
            "star": "\u{2606}", "star.fill": "\u{2605}", "heart": "\u{2661}", "heart.fill": "\u{2665}",
            "gear": "\u{2699}", "gearshape": "\u{2699}", "trash": "\u{2672}", "arrow.left": "\u{2190}",
            "arrow.right": "\u{2192}", "arrow.up": "\u{2191}", "arrow.down": "\u{2193}",
            "chevron.left": "\u{2039}", "chevron.right": "\u{203A}", "circle": "\u{25CB}",
            "circle.fill": "\u{25CF}", "square": "\u{25A1}", "square.fill": "\u{25A0}",
            "info.circle": "\u{24D8}", "exclamationmark.triangle": "\u{26A0}", "magnifyingglass": "\u{2315}",
            "pencil": "\u{270E}", "doc": "\u{25A4}", "folder": "\u{25A3}", "bolt": "\u{26A1}",
            "sun.max": "\u{2600}", "moon": "\u{263E}", "cloud": "\u{2601}", "bell": "\u{237E}",
        ]
        return map[name] ?? ""
    }

    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.image(name)) }
}

/// A title with an icon.
public struct Label<Title: View, Icon: View>: View, _PrimitiveView, _TitleView {
    public typealias Body = Never
    let title: Title
    let icon: Icon
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }
    var _title: String { titleOf(title) }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.horizontal, 4, alignment: 0), children: [cx.resolve(icon, at: 0), cx.resolve(title, at: 1)])
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ title: String, systemImage: String) {
        self.init(title: { Text(title) }, icon: { Image(systemName: systemImage) })
    }
}

// ---- controls ----------------------------------------------------------------------------

/// A push button.
public struct Button<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let label: Label
    let action: () -> Void
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.button(titleOf(label, in: cx), action)) }
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
    public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
}

public struct ButtonRole: Hashable, Sendable {
    let name: String
    public static let destructive = ButtonRole(name: "destructive")
    public static let cancel = ButtonRole(name: "cancel")
}

extension Button where Label == Text {
    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
}

/// A checkbox, on or off.
public struct Toggle<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let label: Label
    let isOn: Binding<Bool>
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
    }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.toggle(titleOf(label, in: cx), isOn)) }
}

extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}

/// A field to type a line into.
public struct TextField<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let placeholder: String
    let text: Binding<String>
    let secure: Bool
    init(_ placeholder: String, text: Binding<String>, secure: Bool) {
        self.placeholder = placeholder
        self.text = text
        self.secure = secure
    }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.textField(placeholder, text, secure: secure)) }
}

extension TextField where Label == Text {
    public init(_ placeholder: String, text: Binding<String>) {
        self.init(placeholder, text: text, secure: false)
    }
    public init(_ placeholder: String, text: Binding<String>, prompt: Text?) {
        self.init(placeholder, text: text, secure: false)
    }
}

/// A field to type a password into, its letters hidden.
public struct SecureField<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let placeholder: String
    let text: Binding<String>
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.textField(placeholder, text, secure: true)) }
}

extension SecureField where Label == Text {
    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
    }
}

/// A slider over a range of numbers.
public struct Slider<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let value: Binding<Double>
    let range: ClosedRange<Double>
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.slider(value, range)) }
}

extension Slider where Label == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in range: ClosedRange<V> = 0...1) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        self.range = Double(range.lowerBound)...Double(range.upperBound)
    }
}

extension Slider {
    /// (A Mac's slider shows its label only in a form; Ferry's not yet.)
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in range: ClosedRange<V> = 0...1,
                                        @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        self.range = Double(range.lowerBound)...Double(range.upperBound)
    }
}

/// Buttons to count a number up and down, beside a label.
public struct Stepper<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let title: String
    var label: Label? = nil
    let up: () -> Void
    let down: () -> Void
    func _resolve(_ cx: ResolveContext) -> RNode {
        let labelNode = label.map { cx.child("label").resolve($0) } ?? cx.child("label").resolve(Text(title))
        let control = RNode(.stepper(title, up, down))
        control.path = cx.path + "/control"
        return RNode(.stack(.horizontal, 6, alignment: 0), children: [labelNode, control])
    }
}

extension Stepper {
    public init<V: Strideable>(value: Binding<V>, in range: ClosedRange<V>, step: V.Stride = 1,
                               @ViewBuilder label: () -> Label) {
        title = ""
        self.label = label()
        up = { if value.wrappedValue.advanced(by: step) <= range.upperBound { value.wrappedValue = value.wrappedValue.advanced(by: step) } }
        down = { if value.wrappedValue.advanced(by: -step) >= range.lowerBound { value.wrappedValue = value.wrappedValue.advanced(by: -step) } }
    }
    public init(@ViewBuilder label: () -> Label, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?) {
        title = ""
        self.label = label()
        up = onIncrement ?? {}
        down = onDecrement ?? {}
    }
}

extension Stepper where Label == Text {
    public init(_ title: String, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?) {
        self.title = title
        up = onIncrement ?? {}
        down = onDecrement ?? {}
    }
    public init<V: Strideable>(_ title: String, value: Binding<V>, in range: ClosedRange<V>, step: V.Stride = 1) {
        self.title = title
        up = { if value.wrappedValue.advanced(by: step) <= range.upperBound { value.wrappedValue = value.wrappedValue.advanced(by: step) } }
        down = { if value.wrappedValue.advanced(by: -step) >= range.lowerBound { value.wrappedValue = value.wrappedValue.advanced(by: -step) } }
    }
    public init<V: Strideable>(_ title: String, value: Binding<V>, step: V.Stride = 1) {
        self.title = title
        up = { value.wrappedValue = value.wrappedValue.advanced(by: step) }
        down = { value.wrappedValue = value.wrappedValue.advanced(by: -step) }
    }
}

/// A pop-up menu choosing one of its tagged views.
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let title: String
    let selection: Binding<SelectionValue>
    let content: Content

    func _resolve(_ cx: ResolveContext) -> RNode {
        // the choices are the content's views, each with its tag
        let tree = cx.child("choices").resolve(content)
        var titles: [String] = []
        var tags: [AnyHashable] = []
        func walk(_ n: RNode) {
            if let tag = n.tag {
                titles.append(n.firstText ?? "\(tag)")
                tags.append(tag)
                return
            }
            for c in n.children { walk(c) }
        }
        walk(tree)
        let selected = tags.firstIndex(of: AnyHashable(selection.wrappedValue)) ?? -1
        let sel = selection
        let node = RNode(.picker(title, titles, selected, { i in
            if i >= 0 && i < tags.count, let v = tags[i].base as? SelectionValue { sel.wrappedValue = v }
        }))
        if title.isEmpty { return node }
        node.path = cx.path + "/control"
        return RNode(.stack(.horizontal, 6, alignment: 0), children: [cx.child("label").resolve(Text(title)), node])
    }
}

extension Picker where Label == Text {
    public init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.selection = selection
        self.content = content()
    }
}

/// A bar showing how far something has got, or that it is going on.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View, _PrimitiveView {
    public typealias Body = Never
    let value: Double?
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.progress(value)) }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() { value = nil }
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1) {
        self.value = value.map { Double($0) / Double(total) }
    }
    public init<V: BinaryFloatingPoint>(_ title: String, value: V?, total: V = 1) {
        self.value = value.map { Double($0) / Double(total) }
    }
}

/// Room that grows along its stack.
public struct Spacer: View, _PrimitiveView {
    public typealias Body = Never
    let minLength: CGFloat?
    public init(minLength: CGFloat? = nil) { self.minLength = minLength }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.spacer(minLength)) }
}

/// A line between views.
public struct Divider: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.divider) }
}

// ---- stacks and containers ---------------------------------------------------------------

/// Views one above the other.
public struct VStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.vertical, spacing ?? Layout.defaultSpacing, alignment: alignment.value), children: [cx.resolve(content, at: 0)])
    }
}

/// Views side by side.
public struct HStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.horizontal, spacing ?? Layout.defaultSpacing, alignment: alignment.value), children: [cx.resolve(content, at: 0)])
    }
}

/// Views on top of one another.
public struct ZStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) { self.content = content() }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.zstack, children: [cx.resolve(content, at: 0)]) }
}

public enum Axis: Hashable, Sendable {
    case horizontal, vertical
    public struct Set: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

/// Views that can be scrolled. (Ferry lays them out, top-aligned; it does
/// not yet scroll them.)
public struct ScrollView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
    }
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.scroll, children: [cx.resolve(content, at: 0)]) }
}

/// Rows, one under the other, leading-aligned.
public struct List<SelectionValue: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.vertical, 4, alignment: -1), children: [cx.resolve(content, at: 0)])
    }
}

extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
        where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.content = ForEach(data, content: rowContent)
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
        where Content == ForEach<Data, ID, RowContent> {
        self.content = ForEach(data, id: id, content: rowContent)
    }
}

/// Controls for settings, one under the other.
public struct Form<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.padding(NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)), children: [
            RNode(.stack(.vertical, 12, alignment: -1), children: [cx.resolve(content, at: 0)]),
        ])
    }
}

/// Views under a header, in a list or a form.
public struct Section<Parent: View, Content: View, Footer: View>: View, _PrimitiveView {
    public typealias Body = Never
    let header: String?
    let content: Content
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.section(header), children: [cx.resolve(content, at: 0)]) }
}

extension Section where Parent == Text, Footer == EmptyView {
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        header = title
        self.content = content()
    }
    public init(header: Text, @ViewBuilder content: () -> Content) {
        self.header = header.string
        self.content = content()
    }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        header = nil
        self.content = content()
    }
}

/// A view and a size it reads its room with. (Ferry proposes its own room.)
public struct GeometryProxy {
    public let size: CGSize
}

// ---- the views kept from Apple's API that Ferry shows plainly ------------------------------

/// Navigation: Ferry shows the content, without a sidebar or a stack.
public struct NavigationView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    func _resolve(_ cx: ResolveContext) -> RNode {
        RNode(.stack(.horizontal, 0, alignment: -1), children: [cx.resolve(content, at: 0)])
    }
}

public typealias NavigationStack = NavigationView
