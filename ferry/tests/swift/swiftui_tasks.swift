// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI (freemac 1.230): .task and .task(id:), .onReceive with
// a Combine subject, a ViewModifier of one's own, LabeledContent,
// alignmentGuide, keyboard shortcuts with their localization, the locale in
// the environment, and #Preview, which builds nothing. Run with
// FERRY_SWIFTUI_CLICK naming the buttons to press.

import Combine
import SwiftUI

let ticks = PassthroughSubject<Int, Never>()

struct Boxed: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(4)
    }
}

struct ContentView: View {
    @Environment(\.locale) private var locale
    @State private var started = "no"
    @State private var round = 0
    @State private var rounds = "none"
    @State private var received = 0

    var body: some View {
        VStack(alignment: .leading) {
            Text("Started: \(started)")
                .task { started = "yes" }
            Text("Rounds: \(rounds)")
                .task(id: round) { rounds = rounds == "none" ? "\(round)" : rounds + ",\(round)" }
            Text("Received: \(received)")
                .onReceive(ticks) { received += $0 }
            LabeledContent("Locale", value: locale.identifier.isEmpty ? "none" : "set")
            Text("Guided")
                .alignmentGuide(.leading) { d in d[.leading] }
                .modifier(Boxed())
            Button("Next") {
                round += 1
                ticks.send(10)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift], localization: .withoutMirroring)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

@main
struct TasksApp: App {
    var body: some Scene {
        WindowGroup("Tasks") {
            ContentView()
        }
    }
}
