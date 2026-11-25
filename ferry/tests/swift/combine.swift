// Ferry's Combine (freemac 1.230): subjects, sinks and the usual
// operators; @Published and ObservableObject, as LaunchAtLogin and
// SwiftUI's views use them; receive(on:), notifications, key-value
// observing and Timer's publisher on the run loop.
import Foundation
import Combine

var bag = Set<AnyCancellable>()

// ---- subjects and operators
let numbers = PassthroughSubject<Int, Never>()
var got: [String] = []
numbers.map { $0 * 10 }.filter { $0 != 20 }.removeDuplicates().sink(receiveCompletion: { _ in got.append("done") },
                                                                     receiveValue: { got.append(String($0)) }).store(in: &bag)
for n in [1, 2, 3, 3, 4] { numbers.send(n) }
numbers.send(completion: .finished)
numbers.send(5)
print("map/filter/removeDuplicates:", got)

let current = CurrentValueSubject<String, Never>("a")
var seen: [String] = []
let c1 = current.sink { seen.append($0) }
current.send("b")
current.value = "c"
c1.cancel()
current.send("d")
print("current value:", seen, current.value)

print("just:", Just(7).map { $0 + 1 }.collectFirst() ?? -1)
var merged: [Int] = []
let p1 = PassthroughSubject<Int, Never>(), p2 = PassthroughSubject<Int, Never>()
p1.merge(with: p2).sink { merged.append($0) }.store(in: &bag)
p1.send(1); p2.send(2); p1.send(3)
print("merge:", merged)

var latest: [String] = []
p1.combineLatest(p2).sink { latest.append("\($0.0)-\($0.1)") }.store(in: &bag)
p1.send(10); p2.send(20); p1.send(11)
print("combineLatest:", latest)

enum Oops: Error { case bad }
let failing = PassthroughSubject<Int, Oops>()
var outcome = ""
failing.replaceError(with: -1).sink(receiveCompletion: { _ in outcome += " finished" }, receiveValue: { outcome += "\($0)" })
    .store(in: &bag)
failing.send(completion: .failure(.bad))
print("replaceError:", outcome)

var dropped: [Int] = []
[1, 2, 3, 4].publisher.dropFirst(2).sink { dropped.append($0) }.store(in: &bag)
print("dropFirst:", dropped)

let erased: AnyPublisher<Int, Never> = numbers.eraseToAnyPublisher()
_ = erased

// ---- ObservableObject and @Published
final class Settings: ObservableObject {
    @Published var isEnabled = false
    @Published var name = "x"
}
let settings = Settings()
var willChange = 0
settings.objectWillChange.sink { willChange += 1 }.store(in: &bag)
var enabled: [Bool] = []
settings.$isEnabled.sink { enabled.append($0) }.store(in: &bag)
settings.isEnabled = true
settings.name = "y"
settings.isEnabled = false
print("willChange:", willChange, "published values:", enabled, settings.name)

final class Mirror: ObservableObject { @Published var copy = false }
let mirror = Mirror()
settings.$isEnabled.assign(to: &mirror.$copy)
settings.isEnabled = true
print("assign(to: &$copy):", mirror.copy)

final class Box: NSObject { @objc dynamic var level = 0 }
let box = Box()
var kept: [Int] = []
_ = Just(5).assign(to: \.level, on: box)
print("assign(to:on:):", box.level)

// ---- notifications and key-value observing
let center = NotificationCenter.default
var names: [String] = []
let testName = Notification.Name("FerryCombineTest")
let note = center.publisher(for: testName).sink { names.append($0.name.rawValue) }
center.post(name: testName, object: nil)
note.cancel()
center.post(name: testName, object: nil)
print("notifications:", names)

box.publisher(for: \.level).sink { kept.append($0) }.store(in: &bag)
box.level = 9
print("key-value observing:", kept)

// ---- schedulers and timers, on the main run loop
var order: [String] = []
let later = PassthroughSubject<Int, Never>()
later.receive(on: DispatchQueue.main).sink { order.append("main \($0)") }.store(in: &bag)
later.send(1)
order.append("sent")
var ticks = 0
let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { _ in
    ticks += 1
    if ticks == 3 {
        print("receive(on:):", order)
        print("timer ticks:", ticks)
        exit(0)
    }
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
print("timer didn't fire:", ticks, timer)

extension Publisher where Failure == Never {
    func collectFirst() -> Output? {
        var out: Output?
        _ = sink { if out == nil { out = $0 } }
        return out
    }
}
