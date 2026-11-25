// SPDX-License-Identifier: GPL-3.0-or-later
//
// Apps, scenes and hosting views (freemac 1.227), with the names Apple's
// SwiftUI documentation gives them: an App's body lists its scenes (a
// WindowGroup or Window, Settings, a MenuBarExtra), and its main() runs
// them with NSApplication, each window's content in a hosting view.
//
// For tests and for trying apps, FERRY_SWIFTUI_DUMP=1 prints each window's
// views once they are laid out, and FERRY_SWIFTUI_CLICK="A,B,..." then
// presses the buttons and checkboxes with those titles in turn, printing
// the views again after each, and quits (unless FERRY_SWIFTUI_STAY is set).

import AppKit

// ---- hosting views ---------------------------------------------------------------------

/// An AppKit view showing SwiftUI views; what NSHostingView is made of.
public class _HostingViewBase: NSView {
    let core: HostCore

    init(root: @escaping () -> any View) {
        core = HostCore(root: root)
        super.init(frame: NSMakeRect(0, 0, 100, 100))
        core.container = self
        core.onUpdate = { [unowned self] in self.fitWindow() }
    }

    /// A window's content grows to hold what its views now need.
    func fitWindow() {
        guard let w = window, w.contentView === self else { return }
        let want = core.fittingSize(nil)
        let have = bounds.size
        if want.width > have.width || want.height > have.height {
            w.setContentSize(NSMakeSize(max(want.width, have.width), max(want.height, have.height)))
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    public override func resizeSubviews(withOldSize old: NSSize) {
        if core.tree == nil { core.update() } else { core.layout() }
    }

    public override func viewDidMoveToWindow() {
        if core.tree == nil { core.update() }
    }

    /// The size the content would like.
    public var idealSize: NSSize {
        if core.tree == nil { core.update() }
        return core.fittingSize(nil)
    }
}

/// An AppKit view showing a SwiftUI view.
public class NSHostingView<Content: View>: _HostingViewBase {
    public var rootView: Content { didSet { core.invalidate() } }
    public init(rootView: Content) {
        self.rootView = rootView
        super.init(root: { EmptyView() })
        core.root = { [unowned self] in self.rootView }
    }
}

/// A view controller whose view shows a SwiftUI view.
public class NSHostingController<Content: View>: NSViewController {
    public var rootView: Content
    public init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public override func loadView() {
        let v = _HostingViewBase(root: { [unowned self] in self.rootView })
        v.frameSize = v.idealSize
        view = v
    }
}

// ---- scenes ----------------------------------------------------------------------------

/// What a scene asks the app to show.
final class SceneSpec {
    enum Kind { case window, settings, menuBarExtra(menu: Bool) }
    var kind: Kind
    var title: String
    var image: String?
    var content: () -> any View
    var size: CGSize?
    var menus: [(String, () -> any View)] = []
    init(_ kind: Kind, title: String, image: String? = nil, content: @escaping () -> any View) {
        self.kind = kind
        self.title = title
        self.image = image
        self.content = content
    }
}

/// Part of an app's user interface: a window, its settings, a menu bar item.
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
}

extension Never: Scene {}

protocol _PrimitiveScene {
    func _specs() -> [SceneSpec]
}

extension Scene where Body == Never {
    public var body: Never { fatalError("\(Self.self) is shown by Ferry; it has no body") }
}

func specs(_ scene: any Scene) -> [SceneSpec] {
    if let p = scene as? _PrimitiveScene { return p._specs() }
    return specsOfBody(scene)
}

private func specsOfBody<S: Scene>(_ scene: S) -> [SceneSpec] { specs(scene.body) }

public struct _TupleScene: Scene, _PrimitiveScene {
    public typealias Body = Never
    let scenes: [any Scene]
    func _specs() -> [SceneSpec] { scenes.flatMap { specs($0) } }
}

@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<S: Scene>(_ s: S) -> S { s }
    public static func buildBlock<S0: Scene, S1: Scene>(_ s0: S0, _ s1: S1) -> _TupleScene {
        _TupleScene(scenes: [s0, s1])
    }
    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene>(_ s0: S0, _ s1: S1, _ s2: S2) -> _TupleScene {
        _TupleScene(scenes: [s0, s1, s2])
    }
    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene, S3: Scene>(_ s0: S0, _ s1: S1, _ s2: S2, _ s3: S3) -> _TupleScene {
        _TupleScene(scenes: [s0, s1, s2, s3])
    }
    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene, S3: Scene, S4: Scene>(_ s0: S0, _ s1: S1, _ s2: S2, _ s3: S3, _ s4: S4) -> _TupleScene {
        _TupleScene(scenes: [s0, s1, s2, s3, s4])
    }
}

/// A window, of the app's main kind.
public struct WindowGroup<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let title: String
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { title = ""; self.content = content }
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    public init(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    public init(id: String, @ViewBuilder content: @escaping () -> Content) { title = ""; self.content = content }
    func _specs() -> [SceneSpec] { [SceneSpec(.window, title: title, content: content)] }
}

/// One window, of its own kind.
public struct Window<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let title: String
    let content: () -> Content
    public init(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    func _specs() -> [SceneSpec] { [SceneSpec(.window, title: title, content: content)] }
}

/// The app's settings window, opened from its menu.
public struct Settings<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    func _specs() -> [SceneSpec] { [SceneSpec(.settings, title: "Settings", content: content)] }
}

public enum MenuBarExtraStyleKind { case menu, window }
public protocol MenuBarExtraStyle { var _kind: MenuBarExtraStyleKind { get } }
public struct PullDownMenuBarExtraStyle: MenuBarExtraStyle { public var _kind: MenuBarExtraStyleKind { .menu } }
public struct WindowMenuBarExtraStyle: MenuBarExtraStyle { public var _kind: MenuBarExtraStyleKind { .window } }
extension MenuBarExtraStyle where Self == PullDownMenuBarExtraStyle { public static var menu: Self { .init() } }
extension MenuBarExtraStyle where Self == WindowMenuBarExtraStyle { public static var window: Self { .init() } }
extension MenuBarExtraStyle where Self == PullDownMenuBarExtraStyle { public static var automatic: Self { .init() } }

/// An item in the menu bar, with a menu or a small window of views.
public struct MenuBarExtra<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let title: String
    let image: String?
    let content: () -> Content
    public init(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        image = systemImage
        self.content = content
    }
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        image = nil
        self.content = content
    }
    public init(_ title: String, systemImage: String, isInserted: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, systemImage: systemImage, content: content)
    }
    func _specs() -> [SceneSpec] { [SceneSpec(.menuBarExtra(menu: true), title: title, image: image, content: content)] }
}

/// A scene with something about it changed.
public struct _ModifiedScene<Base: Scene>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let base: Base
    let change: (SceneSpec) -> Void
    func _specs() -> [SceneSpec] {
        let s = specs(base)
        s.forEach(change)
        return s
    }
}

public struct WindowResizability { public static let automatic = WindowResizability(); public static let contentSize = WindowResizability(); public static let contentMinSize = WindowResizability() }
public protocol WindowStyle {}
public struct DefaultWindowStyle: WindowStyle { public init() {} }
public struct HiddenTitleBarWindowStyle: WindowStyle { public init() {} }
public struct TitleBarWindowStyle: WindowStyle { public init() {} }
extension WindowStyle where Self == DefaultWindowStyle { public static var automatic: Self { .init() } }
extension WindowStyle where Self == HiddenTitleBarWindowStyle { public static var hiddenTitleBar: Self { .init() } }
extension WindowStyle where Self == TitleBarWindowStyle { public static var titleBar: Self { .init() } }

extension Scene {
    public func menuBarExtraStyle<S: MenuBarExtraStyle>(_ style: S) -> _ModifiedScene<Self> {
        _ModifiedScene(base: self) { s in
            if case .menuBarExtra = s.kind { s.kind = .menuBarExtra(menu: style._kind == .menu) }
        }
    }
    public func defaultSize(width: CGFloat, height: CGFloat) -> _ModifiedScene<Self> {
        _ModifiedScene(base: self) { $0.size = CGSize(width: width, height: height) }
    }
    public func windowResizability(_ r: WindowResizability) -> _ModifiedScene<Self> { _ModifiedScene(base: self) { _ in } }
    public func windowStyle<S: WindowStyle>(_ style: S) -> _ModifiedScene<Self> { _ModifiedScene(base: self) { _ in } }
    public func commands<C: Commands>(@CommandsBuilder content: () -> C) -> _ModifiedScene<Self> {
        let menus = commandMenus(content())
        return _ModifiedScene(base: self) { $0.menus += menus }
    }
}

// ---- commands: the app's menus -------------------------------------------------------------

public protocol Commands {}

public struct _TupleCommands: Commands { let items: [any Commands] }
public struct EmptyCommands: Commands { public init() {} }

@resultBuilder
public enum CommandsBuilder {
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<C: Commands>(_ c: C) -> C { c }
    public static func buildBlock(_ cs: any Commands...) -> _TupleCommands { _TupleCommands(items: cs) }
}

/// A menu of the app's own, in the menu bar.
public struct CommandMenu<Content: View>: Commands {
    let name: String
    let content: () -> Content
    public init(_ name: String, @ViewBuilder content: @escaping () -> Content) {
        self.name = name
        self.content = content
    }
}

public enum CommandGroupPlacement { case appInfo, appSettings, appTermination, newItem, saveItem, undoRedo, pasteboard, toolbar, sidebar, help }

/// Items added to one of the standard menus. (Ferry takes them, and does
/// not show them yet.)
public struct CommandGroup<Content: View>: Commands {
    public init(replacing: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {}
    public init(after: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {}
    public init(before: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {}
}

public struct SidebarCommands: Commands { public init() {} }
public struct ToolbarCommands: Commands { public init() {} }

func commandMenus(_ c: any Commands) -> [(String, () -> any View)] {
    if let t = c as? _TupleCommands { return t.items.flatMap { commandMenus($0) } }
    if let m = c as? _CommandMenuItem { return [m._menu] }
    return []
}

protocol _CommandMenuItem { var _menu: (String, () -> any View) { get } }
extension CommandMenu: _CommandMenuItem {
    var _menu: (String, () -> any View) { (name, content) }
}

/// A menu of buttons, shown from a pull-down.
public struct Menu<Label: View, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let title: String
    let content: Content
    func _resolve(_ cx: ResolveContext) -> RNode { RNode(.menu(title), children: [cx.resolve(content, at: 0)]) }
}

extension Menu where Label == Text {
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
}

// ---- menus made from views ---------------------------------------------------------------

/// Fills an AppKit menu from views: buttons become items, toggles items
/// with a check mark, dividers separators, words items that can't be
/// chosen, and a Menu a submenu. The menu is filled again each time it is
/// about to open, and when state its views read changes.
final class MenuBuilder: NSObject, NSMenuDelegate {
    let core: HostCore
    var targets: [ActionTarget] = []
    init(_ content: @escaping () -> any View) { core = HostCore(root: content) }

    func attach(_ menu: NSMenu) {
        menu.delegate = self
        fill(menu)
        core.onInvalidate = { [weak self, weak menu] in Scheduler.shared.later { if let menu { self?.fill(menu) } } }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }

    func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        targets = []
        core.visited = []
        let tree = ResolveContext(host: core, path: "", environment: core.environment).resolve(core.root())
        add(tree, to: menu)
    }

    private func add(_ n: RNode, to menu: NSMenu) {
        switch n.kind {
        case .button(let title, let action):
            menu.addItem(item(title, action))
        case .toggle(let title, let binding):
            let i = item(title) { binding.wrappedValue.toggle() }
            i.state = binding.wrappedValue ? .on : .off
            menu.addItem(i)
        case .divider:
            menu.addItem(NSMenuItem.separator())
        case .text(let s):
            let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        case .menu(let title):
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            for c in n.children { add(c, to: sub) }
            i.submenu = sub
            menu.addItem(i)
        default:
            for c in n.children { add(c, to: menu) }
        }
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let t = ActionTarget()
        t.action = action
        targets.append(t)
        let i = NSMenuItem(title: title, action: #selector(ActionTarget.fire(_:)), keyEquivalent: "")
        i.target = t
        return i
    }
}

// ---- apps ------------------------------------------------------------------------------

/// An app made of scenes.
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
    init()
}

extension App {
    /// Runs the app: what @main calls.
    public static func main() {
        let app = Self()
        AppRunner.run(specs(app.body), name: String(describing: Self.self))
    }
}

/// The app's own NSApplicationDelegate, made once, for
/// @NSApplicationDelegateAdaptor.
var adaptedDelegate: NSObject?

/// Gives a SwiftUI app an NSApplicationDelegate of its own, which hears
/// what the application tells its delegate.
@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType: NSObject & NSApplicationDelegate> {
    public init(_ type: DelegateType.Type = DelegateType.self) {
        if adaptedDelegate == nil { adaptedDelegate = DelegateType() }
    }
    public var wrappedValue: DelegateType { adaptedDelegate as! DelegateType }
}

final class AppRunner: NSObject, NSApplicationDelegate {
    static var current: AppRunner?

    // what the app's own delegate answers, it answers
    override func responds(to sel: Selector) -> Bool {
        if super.responds(to: sel) { return true }
        return adaptedDelegate?.responds(to: sel) ?? false
    }
    override func forwardingTarget(for sel: Selector) -> Any? {
        if let d = adaptedDelegate, d.responds(to: sel) { return d }
        return super.forwardingTarget(for: sel)
    }
    let scenes: [SceneSpec]
    let name: String
    var windows: [NSWindow] = []
    var settingsWindow: NSWindow?
    var statusItems: [(NSStatusItem, MenuBuilder?)] = []
    var menuBuilders: [MenuBuilder] = []
    var targets: [ActionTarget] = []
    var extraWindows: [NSWindow] = []

    init(_ scenes: [SceneSpec], name: String) {
        self.scenes = scenes
        self.name = name
    }

    static func run(_ scenes: [SceneSpec], name: String) {
        let app = NSApplication.shared
        let runner = AppRunner(scenes, name: name)
        current = runner
        app.delegate = runner
        app.run()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMainMenu()
        for s in scenes {
            switch s.kind {
            case .window:
                if windows.isEmpty { windows.append(window(for: s)) }
            case .menuBarExtra(let menu):
                addStatusItem(s, menu: menu)
            case .settings:
                break
            }
        }
        for w in windows { w.makeKeyAndOrderFront(nil) }
        if let d = adaptedDelegate as? NSApplicationDelegate {
            d.applicationDidFinishLaunching?(n)
        }
        let env = ProcessInfo.processInfo.environment ?? [:]
        if env["FERRY_SWIFTUI_DUMP"] != nil || env["FERRY_SWIFTUI_CLICK"] != nil {
            let clicks = (env["FERRY_SWIFTUI_CLICK"] ?? "").split(separator: ",").map(String.init)
            Scheduler.shared.later { self.drive(clicks) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if let d = adaptedDelegate as? NSApplicationDelegate,
           let answer = d.applicationShouldTerminateAfterLastWindowClosed?(sender) {
            return answer
        }
        // as SwiftUI's: an app with windows of its own only, once they are closed
        return statusItems.isEmpty && adaptedDelegate == nil
            && scenes.contains { if case .window = $0.kind { return true }; return false }
    }

    func window(for s: SceneSpec) -> NSWindow {
        let host = _HostingViewBase(root: s.content)
        let size = s.size ?? host.idealSize
        let w = NSWindow(contentRect: NSMakeRect(0, 0, max(size.width, 120), max(size.height, 40)),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.title = host.core.title ?? (s.title.isEmpty ? name : s.title)
        w.center()
        host.core.onInvalidate = { [weak w, weak host] in
            Scheduler.shared.later { if let t = host?.core.title, let w, w.title != t { w.title = t } }
        }
        return w
    }

    func buildMainMenu() {
        let main = NSMenu(title: "")
        let appItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: name)
        appMenu.addItem(NSMenuItem(title: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        if let settings = scenes.first(where: { if case .settings = $0.kind { return true }; return false }) {
            appMenu.addItem(NSMenuItem.separator())
            let t = ActionTarget()
            t.action = { [unowned self] in self.openSettings(settings) }
            targets.append(t)
            let i = NSMenuItem(title: "Settings\u{2026}", action: #selector(ActionTarget.fire(_:)), keyEquivalent: ",")
            i.target = t
            appMenu.addItem(i)
        }
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        for s in scenes {
            for (title, content) in s.menus {
                let b = MenuBuilder(content)
                menuBuilders.append(b)
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let menu = NSMenu(title: title)
                b.attach(menu)
                item.submenu = menu
                main.addItem(item)
            }
        }
        NSApplication.shared.mainMenu = main
    }

    func openSettings(_ s: SceneSpec) {
        if settingsWindow == nil {
            let w = window(for: s)
            w.title = host(w)?.core.title ?? "Settings"
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func addStatusItem(_ s: SceneSpec, menu: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSVariableStatusItemLength)
        let glyph = s.image.map { Image.glyph($0) } ?? ""
        item.button?.title = glyph.isEmpty ? s.title : glyph
        item.button?.toolTip = s.title
        if menu {
            let b = MenuBuilder(s.content)
            let m = NSMenu(title: s.title)
            b.attach(m)
            item.menu = m
            statusItems.append((item, b))
        } else {
            let t = ActionTarget()
            t.action = { [unowned self] in
                if let w = self.extraWindows.first(where: { $0.title == s.title }) {
                    if w.isVisible { w.orderOut(nil) } else { w.makeKeyAndOrderFront(nil) }
                } else {
                    let w = self.window(for: s)
                    w.title = s.title
                    self.extraWindows.append(w)
                    w.makeKeyAndOrderFront(nil)
                }
            }
            targets.append(t)
            item.button?.target = t
            item.button?.action = #selector(ActionTarget.fire(_:))
            statusItems.append((item, nil))
        }
    }

    func host(_ w: NSWindow) -> _HostingViewBase? { w.contentView as? _HostingViewBase }

    // ---- the test driver

    func drive(_ clicks: [String]) {
        dump()
        guard let first = clicks.first else {
            let env = ProcessInfo.processInfo.environment ?? [:]
            if env["FERRY_SWIFTUI_CLICK"] != nil && env["FERRY_SWIFTUI_STAY"] == nil {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        let rest = Array(clicks.dropFirst())
        if let b = findButton(first) {
            print("click \(first)")
            b.performClick(nil)
        } else if first.hasPrefix("menu:"), click(menuItem: String(first.dropFirst(5))) {
            print("click \(first)")
        } else {
            print("click \(first): no such button")
        }
        // after the pass the click causes
        Scheduler.shared.later { Scheduler.shared.later { self.drive(rest) } }
    }

    func allViews(_ v: NSView) -> [NSView] { [v] + (v is NSBox ? [] : v.subviews.flatMap { allViews($0) }) }

    func findButton(_ title: String) -> NSButton? {
        let ws = windows + extraWindows + (settingsWindow.map { [$0] } ?? [])
        for w in ws {
            guard let c = w.contentView else { continue }
            for v in allViews(c) { if let b = v as? NSButton, b.title == title { return b } }
        }
        return nil
    }

    func click(menuItem title: String) -> Bool {
        func search(_ m: NSMenu?) -> NSMenuItem? {
            guard let m else { return nil }
            for i in m.itemArray {
                if i.title == title { return i }
                if let f = search(i.submenu) { return f }
            }
            return nil
        }
        let menus = [NSApplication.shared.mainMenu] + statusItems.map { $0.0.menu }
        for m in menus {
            if let i = search(m), let t = i.target as? ActionTarget { t.fire(i); return true }
        }
        return false
    }

    func dump() {
        let ws = windows + extraWindows + (settingsWindow.map { [$0] } ?? [])
        for w in ws where w.isVisible {
            print("window \"\(w.title)\" \(Int(w.contentView?.frame.width ?? 0))x\(Int(w.contentView?.frame.height ?? 0))")
            guard let c = w.contentView else { continue }
            for v in allViews(c) where v !== c { print("  " + describe(v)) }
        }
        for (item, builder) in statusItems {
            if let builder, let m = item.menu { builder.menuNeedsUpdate(m) }   // as when it opens
            print("status item \"\(item.button?.title ?? "")\"")
            func show(_ m: NSMenu, _ indent: String) {
                for i in m.itemArray {
                    if i.isSeparatorItem { print(indent + "---"); continue }
                    print(indent + "item \"\(i.title)\"" + (i.state == .on ? " (checked)" : "") + (i.isEnabled ? "" : " (disabled)"))
                    if let s = i.submenu { show(s, indent + "  ") }
                }
            }
            if let m = item.menu { show(m, "  ") }
        }
    }

    func describe(_ v: NSView) -> String {
        let f = v.frame
        let at = "at \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))"
        var s: String
        if let b = v as? NSButton {
            s = "button \"\(b.title)\""
            if b.state == .on { s += " (on)" }
        } else if let t = v as? NSTextField {
            s = (t.isEditable ? "field \"" : "text \"") + t.stringValue + "\""
        } else if let sl = v as? NSSlider {
            s = "slider \(sl.doubleValue)"
        } else {
            s = String(describing: type(of: v))
        }
        if let c = v as? NSControl, !c.isEnabled { s += " (disabled)" }
        return s + " " + at
    }
}
