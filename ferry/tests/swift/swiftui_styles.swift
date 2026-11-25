// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI controls by style (freemac 1.231): a full-width default
// button in the large size, plain buttons whose labels are several views,
// with their keyboard shortcuts, a Stepper with its arrows, a Toggle in the
// switch style, and a segmented Picker filling its width. Run with
// FERRY_SWIFTUI_CLICK pressing each in turn.

import SwiftUI

enum Tab: String, CaseIterable {
    case one = "One", two = "Two", three = "Three"
}

struct ContentView: View {
    @State private var count = 0
    @State private var minutes = 25
    @State private var on = false
    @State private var tab = Tab.one
    @State private var said = "nothing"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                count += 1
            } label: {
                Text("Start \(count)").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Stepper(value: $minutes, in: 1...60) {
                Text("Minutes: \(minutes)")
            }
            Toggle(isOn: $on) {
                Text("Stop after break").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)

            Button {
                said = "about"
            } label: {
                Text("About")
                Spacer()
                Text("⌘ A").foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("a")

            Text("Tab \(tab.rawValue), switch \(on ? "on" : "off"), said \(said)")
        }
        .padding(12)
        .frame(width: 240)
    }
}

@main
struct StylesApp: App {
    var body: some Scene {
        WindowGroup("Styles") {
            ContentView()
        }
    }
}
