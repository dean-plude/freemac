// SPDX-License-Identifier: GPL-3.0-or-later
//
// An AppKit program written in Swift: a delegate, a window, a button's
// target and action.

import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var clicks = 0
    var label: NSTextField!

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSMakeRect(0, 0, 320, 200),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Swift on Ferry"
        let button = NSButton(frame: NSMakeRect(20, 20, 120, 30))
        button.title = "Click"
        button.target = self
        button.action = #selector(clicked(_:))
        label = NSTextField(labelWithString: "no clicks")
        label.frame = NSMakeRect(20, 80, 200, 20)
        window.contentView?.addSubview(button)
        window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil)
        print("window:", window.title, window.isVisible)
        button.performClick(nil)
        button.performClick(nil)
        NSApp.terminate(nil)
    }

    @objc func clicked(_ sender: NSButton) {
        clicks += 1
        label.stringValue = "\(clicks) clicks"
        print("clicked", sender.title, "->", label.stringValue)
    }

    func applicationWillTerminate(_ n: Notification) { print("terminating") }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
