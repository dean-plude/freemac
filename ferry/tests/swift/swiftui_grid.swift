// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI: GroupBox, LazyVGrid, a Stepper and a Slider with label
// views, a Button whose label is several views, NSLocalizedString and the
// gesture modifiers Ferry takes without acting on, @FocusState, and an
// AppKit view wrapped by an NSViewRepresentable with a coordinator. Run with
// FERRY_SWIFTUI_CLICK naming the buttons to press.

import SwiftUI

/// An AppKit label, told of each pass; its coordinator counts them.
struct PassLabel: NSViewRepresentable {
    let text: String

    final class Coordinator {
        var passes = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        NSTextField(labelWithString: "")
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.passes += 1
        field.stringValue = "\(text), pass \(context.coordinator.passes)"
    }
}

struct ContentView: View {
    @FocusState private var nameFocused: Bool
    @State private var picked = "none"
    @State private var minutes = 25
    @State private var volume = 0.5

    let names = ["Work", "Short", "Long", "Off"]

    var body: some View {
        VStack(alignment: .leading) {
            GroupBox("Intervals") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        Button(name) { picked = name }
                    }
                }
            }
            Stepper(value: $minutes, in: 1...60) {
                Text("Minutes: \(minutes)")
            }
            Slider(value: $volume, in: 0...1) {
                Text("Volume")
            }
            Button {
                picked = "started"
            } label: {
                HStack {
                    Image(systemName: "play")
                    Text(NSLocalizedString("start.label", value: "Start", comment: "Start label"))
                }
            }
            Text("Picked: \(picked)")
                .onTapGesture { picked = "tapped" }
                .onHover { _ in }
                .focused($nameFocused)
            PassLabel(text: "AppKit: \(picked)")
        }
        .padding()
    }
}

@main
struct GridApp: App {
    var body: some Scene {
        WindowGroup("Grid") {
            ContentView()
        }
    }
}
