// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI: a counter with @State, Text, Button, VStack, HStack and
// Toggle. Run with FERRY_SWIFTUI_CLICK naming the buttons to press.

import SwiftUI

struct ContentView: View {
    @State private var count = 0
    @State private var doubled = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Count: \(doubled ? count * 2 : count)")
                .font(.title)
            HStack {
                Button("-") { count -= 1 }
                Button("+") { count += 1 }
            }
            Toggle("Doubled", isOn: $doubled)
        }
        .padding()
    }
}

@main
struct CounterApp: App {
    var body: some Scene {
        WindowGroup("Counter") {
            ContentView()
        }
    }
}
