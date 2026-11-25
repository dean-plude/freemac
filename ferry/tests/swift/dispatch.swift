// Ferry's Dispatch overlay (freemac 1.230): queues, groups, semaphores,
// work items, times and timer sources, as TomatoBar's timer uses them.
import Foundation

let serial = DispatchQueue(label: "test.serial")
print("label:", serial.label)
var order: [Int] = []
let group = DispatchGroup()
for i in 1...5 {
    serial.async(group: group) { order.append(i) }
}
group.wait()
print("serial order:", order)

let answer = serial.sync { 6 * 7 }
print("sync returned:", answer)

enum Oops: Error { case bad }
do {
    _ = try serial.sync { () throws -> Int in throw Oops.bad }
} catch {
    print("sync threw:", error)
}

let concurrent = DispatchQueue(label: "test.concurrent", qos: .userInitiated, attributes: .concurrent)
let lock = NSLock()
var total = 0
let g2 = DispatchGroup()
for i in 1...100 {
    concurrent.async(group: g2) { lock.lock(); total += i; lock.unlock() }
}
print("group:", g2.wait(timeout: .now() + 5) == .success ? "done" : "timed out", total)

var squares = [Int](repeating: 0, count: 10)
squares.withUnsafeMutableBufferPointer { buf in
    DispatchQueue.concurrentPerform(iterations: 10) { buf[$0] = $0 * $0 }
}
print("concurrentPerform:", squares)

let sema = DispatchSemaphore(value: 0)
DispatchQueue.global(qos: .utility).async { sema.signal() }
print("semaphore:", sema.wait(timeout: .now() + .seconds(5)) == .success ? "signalled" : "timed out")
print("semaphore again:", sema.wait(timeout: .now() + .milliseconds(50)) == .timedOut ? "timed out" : "signalled")

let item = DispatchWorkItem { print("never printed") }
item.cancel()
serial.async(execute: item)
let item2 = DispatchWorkItem { print("work item ran") }
serial.async(execute: item2)
item2.wait()
print("cancelled:", item.isCancelled)

let t0 = DispatchTime.now()
let t1 = t0 + 1.5
print("time ordered:", t0 < t1, (t1 - .milliseconds(1500)) == t0)
print("intervals equal:", DispatchTimeInterval.seconds(2) == .milliseconds(2000))

// a timer on a queue of its own, as TomatoBar's, whose ticks go to the main queue
var ticks = 0
let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue(label: "Timer"))
timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .never)
timer.setEventHandler {
    DispatchQueue.main.async {
        ticks += 1
        if ticks == 3 {
            print("timer ticked 3 times on the main thread:", pthread_main_np() != 0)
            timer.cancel()
        }
    }
}
timer.setCancelHandler {
    DispatchQueue.main.async {
        print("timer cancelled:", timer.isCancelled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            print("after: ticks", ticks)
            exit(0)
        }
    }
}
timer.resume()
dispatchPrecondition(condition: .onQueue(.main))
dispatchMain()
