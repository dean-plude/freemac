// Swift's concurrency library, built for Ferry (freemac 1.230): tasks,
// async/await, actors, task groups, Task.sleep, @MainActor and the main
// queue running the main actor's work.
import Foundation

actor Counter {
    private var value = 0
    func add(_ n: Int) -> Int {
        value += n
        return value
    }
    var current: Int { value }
}

@MainActor final class Model {
    var log: [String] = []
    func note(_ s: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        log.append(s)
    }
}

func square(_ n: Int) async -> Int {
    await Task.yield()
    return n * n
}

struct Oops: Error {}

func fails() async throws -> Int { throw Oops() }

@MainActor func run() async {
    let model = Model()
    model.note("start")
    print("on the main thread:", Thread.isMainThread)

    // a detached task's result
    let t = Task.detached { await square(7) }
    print("detached:", await t.value)

    // an actor, from many tasks
    let counter = Counter()
    await withTaskGroup(of: Void.self) { group in
        for i in 1...100 { group.addTask { _ = await counter.add(i) } }
    }
    print("actor total:", await counter.current)

    // a task group's results
    let squares = await withTaskGroup(of: Int.self) { group -> [Int] in
        for i in 1...5 { group.addTask { await square(i) } }
        var all: [Int] = []
        for await s in group { all.append(s) }
        return all.sorted()
    }
    print("squares:", squares)

    // errors through await
    do { _ = try await fails() } catch { print("threw:", error is Oops) }

    // sleeping, and back on the main actor after it
    let start = DispatchTime.now()
    try? await Task.sleep(nanoseconds: 50_000_000)
    let slept = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    print("slept at least 50 ms:", slept >= 0.045, "and back on the main thread:", Thread.isMainThread)

    // cancellation
    let long = Task { () -> Bool in
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return Task.isCancelled
    }
    long.cancel()
    print("cancelled task saw it:", await long.value)

    // the main queue's work and the main actor's are the same
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { model.note("from the main queue") }
            c.resume()
        }
    }
    // an unstructured task inherits the main actor
    await Task { model.note("from a task") }.value
    model.note("end")
    print("log:", model.log)
    exit(0)
}

Task { await run() }
dispatchMain()
