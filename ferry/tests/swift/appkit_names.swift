// AppKit's and Foundation's Swift names (freemac 1.230): the nested types
// and members Swift code spells, as KeyboardShortcuts and TomatoBar spell
// them; key-value observing with key paths.
import AppKit
import Carbon
import ObjectiveC

let flags: NSEvent.ModifierFlags = [.command, .shift]
print("modifiers", flags.contains(.command), flags.contains(.option))
let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
print("mask", mask.contains(.keyDown), mask.contains(.keyUp))
let style: NSWindow.StyleMask = [.titled, .closable]
print("style", style.contains(.titled), style.contains(.resizable))
print("policy", NSApplication.ActivationPolicy.accessory.rawValue)
print("responses", NSApplication.ModalResponse.OK.rawValue, NSApplication.ModalResponse.cancel.rawValue,
      NSApplication.ModalResponse.alertSecondButtonReturn.rawValue)
print("lengths", NSStatusItem.variableLength, NSStatusItem.squareLength)
let edge: NSRectEdge = .maxY
print("edge", edge == .maxY, edge == .minY)
let image: NSImage.Name = "tomato"
print("image name", image.rawValue)
print("weight", NSFont.Weight.bold.rawValue > NSFont.Weight.regular.rawValue)
let label = NSColor.labelColor, red = NSColor.red, systemRed = NSColor.systemRed
print("colors", label !== red, red !== systemRed, NSColor.windowBackgroundColor.alphaComponent)
print("policy enum", objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC.rawValue,
      objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN.rawValue)

// keys with no character of their own
func key(_ chars: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                     context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                     keyCode: 0)!
}
print("special", key("\t").specialKey == .tab, key("a").specialKey == nil,
      key("\u{F704}").specialKey?.isFunctionKey ?? false, key("\u{7F}").specialKey == .delete)

// attributed strings take the keys' short names
let text = NSAttributedString(string: "Pomodoro", attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                              .foregroundColor: NSColor.red])!
let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
print("attributed", text.length, font?.pointSize ?? 0, NSAttributedString.Key.font.rawValue)

// an event monitor's handler can drop the event
let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    event.specialKey == .tab ? nil : event
}
print("monitor", monitor != nil)
NSEvent.removeMonitor(monitor!)

// key-value observing with a key path
final class Timer2: NSObject {
    @objc dynamic var seconds = 0
}
let t = Timer2()
var seen: [Int] = []
let observation = t.observe(\.seconds, options: [.new]) { _, change in seen.append(change.newValue ?? -1) }
t.seconds = 25
t.seconds = 5
observation.invalidate()
t.seconds = 99
print("observed", seen)

// notification names are Notification.Name, nested in their classes
print("notes", NSWindow.didBecomeKeyNotification.rawValue, NSApplication.didFinishLaunchingNotification.rawValue)
let ping = Notification.Name("FerryPing")
var pinged = 0
let token = NotificationCenter.default.addObserver(forName: ping, object: nil, queue: nil) { note in
    if note.name == ping { pinged += 1 }
}
NotificationCenter.default.post(name: ping, object: nil)
NotificationCenter.default.removeObserver(token)
NotificationCenter.default.post(name: ping, object: nil)
print("pinged", pinged)

// Swift strings in C formats, and strings from UTF-16
print(String(format: "%@ has %d", "Tomato", 25), String.localizedStringWithFormat("used by %@", "Quit"))
let units: [unichar] = [0x50, 0x6F, 0x6D]
print(units.withUnsafeBufferPointer { String(utf16CodeUnits: $0.baseAddress!, count: 3) })
print("locale", NSLocale(identifier: "en_US").identifier)
print("modes", RunLoop.Mode.eventTracking.rawValue != RunLoop.Mode.default.rawValue)

// menus' items, and Carbon's key event constants
let menu = NSMenu(title: "Tomato")
menu.items = [NSMenuItem(title: "Start", action: nil, keyEquivalent: "s")]
print("menu", menu.items.count, menu.items[0].title, menu.items[0].keyEquivalent)
print("carbon", kEventRawKeyDown, kEventParamKeyCode == 0x6B636F64, UInt32(kEventClassKeyboard) == 0x6B657962)

// responders are the main actor's, as on a Mac, so a closure in a view's
// method may use what is the main actor's; and a few more Swift names
final class Recorder: NSView {
    @MainActor var taken: Bool { true }
    func check() -> Bool {
        let f = { self.taken }
        return f()
    }
}
print("main actor", Recorder(frame: .zero).check())
print("apple events", NSAppleEventManager.shared() === NSAppleEventManager.shared())
let popover = NSPopover()
let window = NSWindow(contentRect: NSMakeRect(0, 0, 100, 100), styleMask: [.titled], backing: .buffered, defer: false)
window.makeKey()
NSApplication.shared.activate(ignoringOtherApps: true)
print("popover", popover.isShown, type(of: popover.show(relativeTo:of:preferredEdge:)) != Void.self)

// Hex Fiend's names: a colour by its type, a predicate from a format, a
// state as an Objective-C number, and a window controller with its own
// init() and a nib name that is a plain String
print("colour", NSColor.red.usingType(.componentBased) != nil, NSColor.red.usingType(.catalog) == nil)
let predicate = NSPredicate(format: "$b > 3")
print("predicate", predicate.evaluate(with: nil, substitutionVariables: ["b": 4]))
let states: [NSNumber] = [NSControl.StateValue.on as NSNumber, NSControl.StateValue.off as NSNumber]
print("states", states.map { $0.intValue })
final class Chooser: NSWindowController {
    override var windowNibName: String { "Chooser" }
    init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError() }
}
print("controller", Chooser().windowNibName)
