// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI in an AppKit program: NSHostingView, a generic
// subclass of NSView, as a window's content, and its rootView changed.

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IONBF, 0)

struct Greeting: View {
    let name: String
    @State private var times = 0
    var body: some View {
        HStack {
            Text("Hello, \(name) (\(times))")
            Button("Again") { times += 1 }
        }
        .padding(10)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let host = NSHostingView(rootView: Greeting(name: "AppKit"))
        print("class:", NSStringFromClass(type(of: host)) ?? "?")
        let size = host.idealSize
        print("ideal:", Int(size.width), Int(size.height))
        window = NSWindow(contentRect: NSMakeRect(0, 0, size.width, size.height),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        let button = host.subviews.compactMap { $0 as? NSButton }.first!
        button.performClick(nil)
        button.performClick(nil)
        perform(#selector(check), with: nil, afterDelay: 0.05)
    }
    @objc func check() {
        for v in window.contentView!.subviews {
            if let t = v as? NSTextField { print("label:", t.stringValue) }
        }
        host2()
        NSApp.terminate(nil)
    }
    func host2() {
        let h = NSHostingView(rootView: Greeting(name: "again"))
        h.rootView = Greeting(name: "changed")
        h.frameSize = h.idealSize
        print("second:", h.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.first ?? "?")
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
