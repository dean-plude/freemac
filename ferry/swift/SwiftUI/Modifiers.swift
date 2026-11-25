// SPDX-License-Identifier: GPL-3.0-or-later
//
// View modifiers (freemac 1.227), with the names Apple's SwiftUI
// documentation gives them. A modifier wraps its view: it changes what the
// view inherits (font, color, whether it is enabled), or puts a node around
// the view's node (padding, a frame, a background). The styles Ferry draws
// one way only are taken and have no effect.

import AppKit

/// Wraps a view's node, or what it inherits.
struct _Modified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    var environment: ((inout EnvironmentValues) -> Void)? = nil
    var wrap: ((RNode, ResolveContext) -> RNode)? = nil

    func _resolve(_ cx: ResolveContext) -> RNode {
        if let environment { environment(&cx.environment) }
        let inner = cx.resolve(content, at: 0)
        return wrap?(inner, cx) ?? inner
    }
}

extension View {
    func _environment(_ f: @escaping (inout EnvironmentValues) -> Void) -> _Modified<Self> {
        _Modified(content: self, environment: f)
    }
    func _wrap(_ f: @escaping (RNode, ResolveContext) -> RNode) -> _Modified<Self> {
        _Modified(content: self, wrap: f)
    }
}

/// A change made to a view, written as a type of its own.
public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @ViewBuilder @MainActor func body(content: Content) -> Body
}

/// The view a ViewModifier is given to change.
public struct _ViewModifier_Content<Modifier: ViewModifier>: View, _PrimitiveView {
    public typealias Body = Never
    let view: any View
    func _resolve(_ cx: ResolveContext) -> RNode { cx.resolve(view, at: 0) }
}

/// A view with a modifier applied.
public struct ModifiedContent<Content: View, Modifier: ViewModifier>: View, _PrimitiveView {
    public typealias Body = Never
    public var content: Content
    public var modifier: Modifier
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
    func _resolve(_ cx: ResolveContext) -> RNode {
        cx.attachProperties(of: modifier)
        // Views are resolved on the main thread, where the main actor runs.
        let body: @MainActor () -> RNode = {
            cx.resolve(modifier.body(content: _ViewModifier_Content(view: content)), at: 0)
        }
        return unsafeBitCast(body, to: (() -> RNode).self)()
    }
}

extension View {
    public func modifier<M: ViewModifier>(_ m: M) -> ModifiedContent<Self, M> {
        ModifiedContent(content: self, modifier: m)
    }
}

// ---- layout

extension View {
    public func padding(_ length: CGFloat) -> some View { padding(.all, length) }

    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let l = length ?? 16
        let e = NSEdgeInsets(top: edges.contains(.top) ? l : 0, left: edges.contains(.leading) ? l : 0,
                             bottom: edges.contains(.bottom) ? l : 0, right: edges.contains(.trailing) ? l : 0)
        return _wrap { n, _ in RNode(.padding(e), children: [n]) }
    }

    public func padding(_ insets: EdgeInsets) -> some View {
        let e = NSEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
        return _wrap { n, _ in RNode(.padding(e), children: [n]) }
    }

    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        _wrap { n, _ in
            RNode(.frame(width: width, height: height, minWidth: nil, maxWidth: nil,
                         minHeight: nil, maxHeight: nil, alignment: alignment), children: [n])
        }
    }

    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        _wrap { n, _ in
            RNode(.frame(width: nil, height: nil, minWidth: minWidth, maxWidth: maxWidth,
                         minHeight: minHeight, maxHeight: maxHeight, alignment: alignment), children: [n])
        }
    }

    public func fixedSize() -> some View { self }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View { self }
    public func layoutPriority(_ p: Double) -> some View { self }
}

// ---- what views inherit

extension View {
    public func font(_ font: Font?) -> some View { _environment { $0.font = font } }
    public func foregroundColor(_ color: Color?) -> some View { _environment { $0.foreground = color } }
    public func foregroundStyle(_ color: Color) -> some View { _environment { $0.foreground = color } }
    public func disabled(_ disabled: Bool) -> some View { _environment { if disabled { $0.isEnabled = false } } }
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        _environment { $0[keyPath: keyPath] = value }
    }
    public func environmentObject<O: ObservableObject>(_ object: O) -> some View {
        _environment { $0.objects[ObjectIdentifier(O.self)] = object }
    }
    public func tint(_ color: Color?) -> some View { self }
    public func accentColor(_ color: Color?) -> some View { self }
}

// ---- drawing

extension View {
    public func background(_ color: Color) -> some View {
        _wrap { n, _ in RNode(.background(color), children: [n]) }
    }
    public func opacity(_ o: Double) -> some View { self }
    public func cornerRadius(_ r: CGFloat) -> some View { self }
    public func shadow(radius: CGFloat) -> some View { self }
    public func lineLimit(_ n: Int?) -> some View { self }
    public func multilineTextAlignment(_ a: Any?) -> some View { self }
}

// ---- behaviour

extension View {
    /// Runs once, after the view is first shown.
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        _wrap { n, cx in
            let slot = cx.host.slot(cx.path)
            cx.host.visited.insert(cx.path)
            if !slot.appeared, let action {
                slot.appeared = true
                cx.host.appearHandlers.append(action)
            }
            return n
        }
    }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { self }

    /// Runs when a value is seen to differ from the last pass.
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        _wrap { n, cx in
            let slot = cx.host.slot(cx.path)
            cx.host.visited.insert(cx.path)
            if let old = slot.values[-1] as? V, old != value {
                cx.host.appearHandlers.append { action(value) }
            }
            slot.values[-1] = value as AnyObject
            return n
        }
    }

    public func help(_ text: String) -> some View { _wrap { n, _ in n.help = text; return n } }
    public func tag<T: Hashable>(_ tag: T) -> some View { _wrap { n, _ in n.tag = AnyHashable(tag); return n } }
    public func id<T: Hashable>(_ id: T) -> some View { self }

    public func navigationTitle(_ title: String) -> some View {
        _wrap { n, cx in cx.host.title = title; return n }
    }
    public func navigationTitle(_ title: Text) -> some View { navigationTitle(title.string) }

    /// A button's keyboard shortcut is its key equivalent (freemac 1.231),
    /// so .defaultAction (Return) makes it the window's default button,
    /// drawn in the accent colour, as on a Mac.
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command,
                                 localization: KeyboardShortcut.Localization) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers, localization: localization))
    }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        _wrap { n, _ in _markShortcut(n, shortcut); return n }
    }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        _wrap { n, _ in
            if let shortcut { _markShortcut(n, shortcut) }
            return n
        }
    }
    public func labelsHidden() -> some View { self }
    /// The switch style shows a switch after the label (freemac 1.231);
    /// the others a checkbox.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        _environment { $0[_ToggleStyleKey.self] = style is SwitchToggleStyle ? "switch" : "" }
    }
    /// Plain, borderless and link buttons show their label's views with no
    /// bezel (freemac 1.231); the others are push buttons.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        let name = style is PlainButtonStyle ? "plain" : style is BorderlessButtonStyle ? "borderless"
            : style is LinkButtonStyle ? "link" : style is BorderedProminentButtonStyle ? "prominent" : ""
        return _environment { $0[_ButtonStyleKey.self] = name }
    }
    /// The segmented style shows a picker as a segmented control; the
    /// others as a pop-up button.
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        _environment { $0[_PickerStyleKey.self] = style is SegmentedPickerStyle ? "segmented" : "" }
    }
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View { self }
    public func listStyle<S: ListStyle>(_ style: S) -> some View { self }
    public func controlSize(_ size: ControlSize) -> some View { _environment { $0[_ControlSizeKey.self] = size } }
}

/// The first button in a node takes a keyboard shortcut.
@discardableResult
func _markShortcut(_ n: RNode, _ shortcut: KeyboardShortcut) -> Bool {
    switch n.kind {
    case .button, .clickArea:
        n.keyEquivalent = String(shortcut.key.character)
        n.keyModifiers = shortcut.modifiers.nsFlags
        return true
    default:
        return n.children.contains { _markShortcut($0, shortcut) }
    }
}

public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    public let character: Character
    public init(_ c: Character) { character = c }
    public init(extendedGraphemeClusterLiteral c: Character) { character = c }
    public static let `return` = KeyEquivalent("\r")
    public static let escape = KeyEquivalent("\u{1b}")
    public static let delete = KeyEquivalent("\u{8}")
    public static let deleteForward = KeyEquivalent("\u{F728}")
    public static let space = KeyEquivalent(" ")
    public static let tab = KeyEquivalent("\t")
    public static let clear = KeyEquivalent("\u{F739}")
    public static let upArrow = KeyEquivalent("\u{F700}")
    public static let downArrow = KeyEquivalent("\u{F701}")
    public static let leftArrow = KeyEquivalent("\u{F702}")
    public static let rightArrow = KeyEquivalent("\u{F703}")
    public static let home = KeyEquivalent("\u{F729}")
    public static let end = KeyEquivalent("\u{F72B}")
    public static let pageUp = KeyEquivalent("\u{F72C}")
    public static let pageDown = KeyEquivalent("\u{F72D}")
}

/// The modifier keys, with the bits Apple's SwiftUI gives them (freemac 1.230).
public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let capsLock = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let control = EventModifiers(rawValue: 1 << 2)
    public static let option = EventModifiers(rawValue: 1 << 3)
    public static let command = EventModifiers(rawValue: 1 << 4)
    public static let numericPad = EventModifiers(rawValue: 1 << 5)
    public static let all = EventModifiers(rawValue: 0x7F)
}

public struct KeyboardShortcut: Hashable, Sendable {
    public let key: KeyEquivalent
    public let modifiers: EventModifiers
    public let localization: Localization
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
        self.localization = .automatic
    }
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: Localization) {
        self.key = key
        self.modifiers = modifiers
        self.localization = localization
    }
    /// Whether a shortcut moves to other keys on other keyboard layouts;
    /// kept only, as Ferry's shortcuts stay where they are.
    public struct Localization: Hashable, Sendable {
        let kind: Int
        public static let automatic = Localization(kind: 0)
        public static let withoutMirroring = Localization(kind: 1)
        public static let custom = Localization(kind: 2)
    }
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])
}

public enum ControlSize: Hashable, Sendable { case mini, small, regular, large, extraLarge }
struct _ControlSizeKey: EnvironmentKey { static let defaultValue = ControlSize.regular }
struct _ButtonStyleKey: EnvironmentKey { static let defaultValue = "" }
struct _ToggleStyleKey: EnvironmentKey { static let defaultValue = "" }

extension EventModifiers {
    /// AppKit's flags for these keys.
    var nsFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.shift) { f.insert(.shift) }
        if contains(.control) { f.insert(.control) }
        if contains(.option) { f.insert(.option) }
        if contains(.command) { f.insert(.command) }
        if contains(.capsLock) { f.insert(.capsLock) }
        if contains(.numericPad) { f.insert(.numericPad) }
        return f
    }
}

// The styles Ferry accepts by name, and draws one way.

public protocol ToggleStyle {}
public struct DefaultToggleStyle: ToggleStyle { public init() {} }
extension ToggleStyle where Self == DefaultToggleStyle { public static var automatic: DefaultToggleStyle { .init() } }
public struct SwitchToggleStyle: ToggleStyle { public init() {} }
extension ToggleStyle where Self == SwitchToggleStyle { public static var `switch`: SwitchToggleStyle { .init() } }
public struct CheckboxToggleStyle: ToggleStyle { public init() {} }
extension ToggleStyle where Self == CheckboxToggleStyle { public static var checkbox: CheckboxToggleStyle { .init() } }
public struct ButtonToggleStyle: ToggleStyle { public init() {} }
extension ToggleStyle where Self == ButtonToggleStyle { public static var button: ButtonToggleStyle { .init() } }

public protocol ButtonStyle {}
public struct DefaultButtonStyle: ButtonStyle { public init() {} }
extension ButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { .init() } }
public struct BorderedButtonStyle: ButtonStyle { public init() {} }
extension ButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { .init() } }
public struct BorderedProminentButtonStyle: ButtonStyle { public init() {} }
extension ButtonStyle where Self == BorderedProminentButtonStyle { public static var borderedProminent: BorderedProminentButtonStyle { .init() } }
public struct BorderlessButtonStyle: ButtonStyle { public init() {} }
extension ButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { .init() } }
public struct PlainButtonStyle: ButtonStyle { public init() {} }
extension ButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { .init() } }
public struct LinkButtonStyle: ButtonStyle { public init() {} }
extension ButtonStyle where Self == LinkButtonStyle { public static var link: LinkButtonStyle { .init() } }

public protocol PickerStyle {}
struct _PickerStyleKey: EnvironmentKey { static let defaultValue = "" }
public struct DefaultPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { .init() } }
public struct MenuPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { .init() } }
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { .init() } }
public struct RadioGroupPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == RadioGroupPickerStyle { public static var radioGroup: RadioGroupPickerStyle { .init() } }
public struct InlinePickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { .init() } }

public protocol TextFieldStyle {}
public struct DefaultTextFieldStyle: TextFieldStyle { public init() {} }
extension TextFieldStyle where Self == DefaultTextFieldStyle { public static var automatic: DefaultTextFieldStyle { .init() } }
public struct RoundedBorderTextFieldStyle: TextFieldStyle { public init() {} }
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle { public static var roundedBorder: RoundedBorderTextFieldStyle { .init() } }
public struct PlainTextFieldStyle: TextFieldStyle { public init() {} }
extension TextFieldStyle where Self == PlainTextFieldStyle { public static var plain: PlainTextFieldStyle { .init() } }
public struct SquareBorderTextFieldStyle: TextFieldStyle { public init() {} }
extension TextFieldStyle where Self == SquareBorderTextFieldStyle { public static var squareBorder: SquareBorderTextFieldStyle { .init() } }

public protocol ListStyle {}
public struct DefaultListStyle: ListStyle { public init() {} }
extension ListStyle where Self == DefaultListStyle { public static var automatic: DefaultListStyle { .init() } }
public struct SidebarListStyle: ListStyle { public init() {} }
extension ListStyle where Self == SidebarListStyle { public static var sidebar: SidebarListStyle { .init() } }
public struct PlainListStyle: ListStyle { public init() {} }
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { .init() } }
public struct InsetListStyle: ListStyle { public init() {} }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { .init() } }
public struct BorderedListStyle: ListStyle { public init() {} }
extension ListStyle where Self == BorderedListStyle { public static var bordered: BorderedListStyle { .init() } }
