// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI: an ObservableObject shared by a window, a Settings
// window and a MenuBarExtra; List, ForEach, TextField, Picker, onAppear,
// @AppStorage, Form and Section.

import SwiftUI

final class Store: ObservableObject {
    @Published var items: [Item] = [Item(name: "Apples"), Item(name: "Pears")]
    @Published var mode = "List"
}

struct Item: Identifiable {
    let id = UUIDish.next()
    var name: String
}

enum UUIDish { static var n = 0; static func next() -> Int { n += 1; return n } }

struct Row: View {
    let item: Item
    var body: some View {
        HStack {
            Image(systemName: "star.fill")
            Text(item.name)
            Spacer()
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: Store
    @State private var newName = "Plums"
    @State private var appeared = 0

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(store.items.count) items, mode \(store.mode), appeared \(appeared)")
                .font(.headline)
            List(store.items) { Row(item: $0) }
            HStack {
                TextField("Name", text: $newName)
                Button("Add") { store.items.append(Item(name: newName)) }
            }
            Picker("Mode", selection: $store.mode) {
                Text("List").tag("List")
                Text("Grid").tag("Grid")
            }
            if store.items.count > 2 {
                Text("more than two").foregroundColor(.red)
            }
            Divider()
            Button("Grid") { store.mode = "Grid" }
        }
        .padding()
        .frame(width: 320)
        .onAppear { appeared += 1 }
    }
}

struct SettingsView: View {
    @AppStorage("volume") var volume = 0.5
    var body: some View {
        Form {
            Section("Sound") {
                Slider(value: $volume, in: 0...1)
                Text("volume \(volume)")
            }
        }
    }
}

let store = Store()

@main
struct ModelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .navigationTitle("Groceries")
        }
        Settings {
            SettingsView()
        }
        MenuBarExtra("Groceries", systemImage: "star") {
            Button("Add Figs") { store.items.append(Item(name: "Figs")) }
            Divider()
            Text("\(store.items.count) items")
        }
    }
}
