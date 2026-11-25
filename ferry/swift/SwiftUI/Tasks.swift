// SPDX-License-Identifier: GPL-3.0-or-later
//
// Work a view starts and what it listens to (freemac 1.230), with the
// names Apple's SwiftUI documentation gives them: task, which runs an
// async action while the view is there and cancels it when the view goes
// (or, with an id, when the id changes); onReceive, which listens to a
// Combine publisher for as long as the view is there; the alignment
// guides, taken (views line up as their stack's alignment says);
// LabeledContent; the environment's locale; and #Preview, Xcode's canvas,
// which expands to nothing (sdk/ferry-swift-macros). Written for Ferry.

import AppKit
import Combine

/// What a view keeps of work it started: cancelled with the view's state.
final class _ViewWork {
    var task: Task<Void, Never>?
    var id: AnyHashable?
    var cancellable: AnyCancellable?
    deinit { task?.cancel() }

    /// How many views' tasks are running (kept on the main thread), which
    /// the test driver waits for before it shows the windows.
    static var running = 0

    func start(_ priority: TaskPriority, _ action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        _ViewWork.running += 1
        task = Task(priority: priority) {
            await action()
            DispatchQueue.main.async { _ViewWork.running -= 1 }
        }
    }
}

extension Slot {
    func work(_ key: Int) -> _ViewWork {
        if let w = values[key] as? _ViewWork { return w }
        let w = _ViewWork()
        values[key] = w
        return w
    }
}

extension View {
    /// Runs an async action when the view appears, and cancels it when the view goes.
    public func task(priority: TaskPriority = .userInitiated,
                     _ action: @escaping @Sendable () async -> Void) -> some View {
        _wrap { n, cx in
            let work = cx.host.slot(cx.path).work(-3)
            cx.host.visited.insert(cx.path)
            if work.task == nil {
                cx.host.appearHandlers.append { work.start(priority, action) }
            }
            return n
        }
    }

    /// Runs an async action when the view appears and again, after
    /// cancelling the last run, each time the id differs.
    public func task<T: Equatable & Hashable>(id value: T, priority: TaskPriority = .userInitiated,
                                              _ action: @escaping @Sendable () async -> Void) -> some View {
        _wrap { n, cx in
            let work = cx.host.slot(cx.path).work(-3)
            cx.host.visited.insert(cx.path)
            let id = AnyHashable(value)
            if work.task == nil || work.id != id {
                work.id = id
                cx.host.appearHandlers.append { work.start(priority, action) }
            }
            return n
        }
    }

    /// Calls the action with each value the publisher sends while the view is there.
    public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View
        where P.Failure == Never {
        _wrap { n, cx in
            let work = cx.host.slot(cx.path).work(-4)
            cx.host.visited.insert(cx.path)
            if work.cancellable == nil {
                work.cancellable = publisher.sink { action($0) }
            }
            return n
        }
    }

    /// Where the view sits against its stack's other views, by a guide of
    /// the stack's alignment; taken, and the view lines up as the stack's
    /// alignment says.
    public func alignmentGuide(_ g: HorizontalAlignment,
                               computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View { self }
    public func alignmentGuide(_ g: VerticalAlignment,
                               computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View { self }
}

/// A label beside what it labels: a value, or a control.
public struct LabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label
            Spacer(minLength: 8)
            content
        }
    }
}

extension LabeledContent where Label == Text {
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.label = Text(title)
        self.content = content()
    }
}

extension LabeledContent where Label == Text, Content == Text {
    public init(_ title: String, value: String) {
        self.label = Text(title)
        self.content = Text(value)
    }
}

private struct LocaleKey: EnvironmentKey { static let defaultValue: Locale = NSLocale.current }

extension EnvironmentValues {
    /// The locale views format and look up their words for.
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
}

/// A preview for Xcode's canvas, which has nothing to show on freemac: it
/// expands to nothing.
@freestanding(declaration)
public macro Preview(_ name: String? = nil, body: @escaping @MainActor () -> any View) =
    #externalMacro(module: "FerrySwiftMacros", type: "PreviewMacro")

@freestanding(declaration)
public macro Preview(_ name: String? = nil, body: @escaping @MainActor () -> NSView) =
    #externalMacro(module: "FerrySwiftMacros", type: "PreviewMacro")
