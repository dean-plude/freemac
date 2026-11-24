// SPDX-License-Identifier: GPL-3.0-or-later
// std::thread, std::mutex, std::condition_variable and the classes built on
// them, on Ferry's pthreads with the Mac's layouts: many threads, counted
// exactly, so a lost lock shows as a wrong total.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <future>
#include <mutex>
#include <queue>
#include <shared_mutex>
#include <stdexcept>
#include <system_error>
#include <thread>
#include <vector>

static std::mutex m;
static long counter;

static void add(int n)
{
    for (int i = 0; i < n; i++) {
        std::lock_guard<std::mutex> g(m);
        counter++;
    }
}

int main()
{
    // mutex
    std::vector<std::thread> ts;
    for (int i = 0; i < 8; i++)
        ts.emplace_back(add, 20000);
    for (auto &t : ts)
        t.join();
    std::printf("mutex counter %ld\n", counter);

    // condition variable: a queue with one producer and three consumers
    std::mutex qm;
    std::condition_variable cv;
    std::queue<int> q;
    bool done = false;
    long total = 0;
    std::vector<std::thread> consumers;
    for (int c = 0; c < 3; c++)
        consumers.emplace_back([&] {
            long mine = 0;
            for (;;) {
                std::unique_lock<std::mutex> lk(qm);
                cv.wait(lk, [&] { return !q.empty() || done; });
                if (q.empty())
                    break;
                mine += q.front();
                q.pop();
            }
            std::lock_guard<std::mutex> g(qm);
            total += mine;
        });
    for (int i = 1; i <= 10000; i++) {
        {
            std::lock_guard<std::mutex> g(qm);
            q.push(i);
        }
        cv.notify_one();
    }
    {
        std::lock_guard<std::mutex> g(qm);
        done = true;
    }
    cv.notify_all();
    for (auto &t : consumers)
        t.join();
    std::printf("condition_variable total %ld\n", total);

    // a wait that times out, and one that doesn't
    {
        std::unique_lock<std::mutex> lk(qm);
        auto r = cv.wait_for(lk, std::chrono::milliseconds(20));
        std::printf("wait_for %s\n", r == std::cv_status::timeout ? "timeout" : "woken");
        bool flag = false;
        std::thread waker([&] {
            std::lock_guard<std::mutex> g(qm);
            flag = true;
            cv.notify_all();
        });
        bool got = cv.wait_until(lk, std::chrono::steady_clock::now() + std::chrono::seconds(30), [&] { return flag; });
        lk.unlock();
        waker.join();
        std::printf("wait_until %s\n", got ? "woken" : "timeout");
    }

    // recursive and timed mutexes
    std::recursive_mutex rm;
    rm.lock();
    rm.lock();
    bool other = true;
    std::thread([&] { other = rm.try_lock(); }).join();
    rm.unlock();
    rm.unlock();
    std::printf("recursive_mutex held elsewhere %s\n", other ? "yes" : "no");
    std::timed_mutex tm;
    tm.lock();
    bool timed = true;
    std::thread([&] { timed = tm.try_lock_for(std::chrono::milliseconds(20)); }).join();
    tm.unlock();
    std::printf("timed_mutex try_lock_for %s, then %s\n", timed ? "got it" : "timed out", tm.try_lock() ? "got it" : "no");
    tm.unlock();
    std::recursive_timed_mutex rtm;
    rtm.lock();
    bool again = rtm.try_lock_for(std::chrono::milliseconds(5));
    rtm.unlock();
    rtm.unlock();
    std::printf("recursive_timed_mutex again %s\n", again ? "yes" : "no");

    // readers and writers
    std::shared_mutex sm;
    long shared_value = 0;
    std::atomic<long> reads{0};
    std::vector<std::thread> rw;
    for (int i = 0; i < 4; i++)
        rw.emplace_back([&] {
            for (int k = 0; k < 2000; k++) {
                std::unique_lock<std::shared_mutex> w(sm);
                shared_value++;
            }
        });
    for (int i = 0; i < 4; i++)
        rw.emplace_back([&] {
            for (int k = 0; k < 2000; k++) {
                std::shared_lock<std::shared_mutex> r(sm);
                if (shared_value >= 0)
                    reads++;
            }
        });
    for (auto &t : rw)
        t.join();
    std::printf("shared_mutex writes %ld reads %ld\n", shared_value, reads.load());
    std::shared_timed_mutex stm;
    stm.lock_shared();
    bool can_write = stm.try_lock();
    bool can_read = stm.try_lock_shared();
    stm.unlock_shared();
    stm.unlock_shared();
    std::printf("shared_timed_mutex write while read %s, read while read %s\n", can_write ? "yes" : "no",
                can_read ? "yes" : "no");

    // call_once, futures, async
    std::once_flag once;
    std::atomic<int> calls{0};
    std::vector<std::thread> oncers;
    for (int i = 0; i < 4; i++)
        oncers.emplace_back([&] { std::call_once(once, [&] { calls++; }); });
    for (auto &t : oncers)
        t.join();
    std::printf("call_once %d\n", calls.load());
    std::promise<int> pi;
    std::future<int> fi = pi.get_future();
    std::thread([&] { pi.set_value(42); }).join();
    std::printf("promise<int> %d\n", fi.get());
    std::promise<void> pv;
    std::future<void> fv = pv.get_future();
    std::thread setter([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        pv.set_value();
    });
    fv.wait();
    setter.join();
    std::printf("promise<void> ready\n");
    auto fa = std::async(std::launch::async, [] { return 6 * 7; });
    auto fd = std::async(std::launch::deferred, [] { return std::string("deferred"); });
    std::printf("async %d %s\n", fa.get(), fd.get().c_str());
    auto fe = std::async(std::launch::async, []() -> int { throw std::runtime_error("from a thread"); });
    try {
        fe.get();
    } catch (const std::exception &e) {
        std::printf("async exception: %s\n", e.what());
    }
    std::promise<void> broken;
    std::future<void> fb = broken.get_future();
    { std::promise<void> gone = std::move(broken); }
    try {
        fb.get();
    } catch (const std::future_error &e) {
        std::printf("broken promise: %s\n", e.code() == std::future_errc::broken_promise ? "yes" : "other");
    }
    try {
        pv.set_value();
    } catch (const std::future_error &e) {
        std::printf("set twice: %s\n",
                    e.code() == std::future_errc::promise_already_satisfied ? "already satisfied" : "other");
    }
    std::shared_future<void> sf = std::async(std::launch::async, [] {}).share();
    std::shared_future<void> sf2;
    sf2 = sf;
    sf2.wait();
    std::printf("shared_future valid %d\n", sf2.valid());

    // thread ids, hardware concurrency, errors
    std::thread::id main_id = std::this_thread::get_id();
    bool same = true;
    std::thread([&] { same = std::this_thread::get_id() == main_id; }).join();
    std::printf("ids differ %s, hardware_concurrency %s\n", same ? "no" : "yes",
                std::thread::hardware_concurrency() > 0 ? "known" : "unknown");
    std::thread never;
    try {
        never.join();
    } catch (const std::system_error &e) {
        std::printf("join of no thread: %s\n", e.code() == std::errc::invalid_argument ? "invalid argument" : "other");
    }
    std::thread detached([] {});
    detached.detach();
    std::printf("detached joinable %d\n", detached.joinable());
    return 0;
}
