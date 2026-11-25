// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's SwiftUI (freemac 1.230): shapes filled and stroked, an overlay
// and a background placed by their alignment, a GeometryReader building
// its content from the size it was given, an alert with its actions and a
// sheet that dismisses itself, and a segmented picker. Run with
// FERRY_SWIFTUI_CLICK naming the buttons to press.

import SwiftUI

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct SheetView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Text("In the sheet")
            Button("Done") { dismiss() }
        }
        .padding()
    }
}

struct ContentView: View {
    @State private var asking = false
    @State private var sheet = false
    @State private var answer = "none"
    @State private var mode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color.red).frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 4).stroke(Color.blue, lineWidth: 2).frame(width: 40, height: 20)
                Capsule().frame(width: 30, height: 12)
                Triangle().fill(Color.green).frame(width: 20, height: 20)
            }
            Text("Badge")
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow))
                .overlay(Text("3").font(.caption), alignment: .topTrailing)
            GeometryReader { proxy in
                Text("Room: \(Int(proxy.size.width))x\(Int(proxy.size.height))")
            }
            .frame(width: 180, height: 30)
            Picker("", selection: $mode) {
                Text("Work").tag(0)
                Text("Rest").tag(1)
            }
            .pickerStyle(.segmented)
            Text("Answer: \(answer)")
            HStack {
                Button("Ask") { asking = true }
                Button("Sheet") { sheet = true }
            }
        }
        .padding()
        .alert("Start a break?", isPresented: $asking) {
            Button("Later") { answer = "later" }
            Button("Now") { answer = "now" }
        } message: {
            Text("Your work interval is over.")
        }
        .sheet(isPresented: $sheet, onDismiss: { answer = "sheet closed" }) {
            SheetView()
        }
    }
}

@main
struct DrawingApp: App {
    var body: some Scene {
        WindowGroup("Drawing") {
            ContentView()
        }
    }
}
