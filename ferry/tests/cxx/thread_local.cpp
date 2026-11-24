// SPDX-License-Identifier: GPL-3.0-or-later
// C++ thread_local objects across std::thread: objects with constructors
// and destructors at namespace scope, as class members and inside a
// function, built on each thread when it first uses them and destroyed
// when it ends, the last built first; library types (std::string,
// std::vector) as thread_local; a destructor that reaches another
// thread_local; and the main thread's objects destroyed when main returns,
// before the program's static objects. An object built lazily, inside a
// function, is destroyed before the file's others, which are built
// together on a thread's first use of any of them.
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

static std::mutex log_lock;
static std::string logs[9]; // one per thread: 0 is the main thread

thread_local int who = 0;

static void note(const std::string &what)
{
    std::lock_guard<std::mutex> g(log_lock);
    logs[who] += what;
    logs[who] += ' ';
}

struct Tracker {
    std::string name;
    explicit Tracker(const char *n) : name(n) { note("+" + name); }
    ~Tracker() { note("-" + name); }
};

thread_local Tracker first("first");
thread_local Tracker second("second");
thread_local std::vector<int> numbers;
thread_local std::string words = "start";

struct Holder {
    static thread_local Tracker member;
};
thread_local Tracker Holder::member("member");

static Tracker &local()
{
    static thread_local Tracker inside("local");
    return inside;
}

// Its destructor reads another thread_local, declared (so built) before
// it and so still there.
struct Reader {
    ~Reader() { note("-reader(" + words + ")"); }
};
thread_local Reader reader;

static void work(int n)
{
    who = n;
    (void)&reader; // builds the file's thread_local objects, in their order
    first.name += std::to_string(n);
    for (int i = 0; i < n * 100; i++)
        numbers.push_back(i);
    words += "-" + std::to_string(numbers.size());
    if (n % 2)
        local();
    (void)&second;
    (void)&Holder::member;
}

struct Static {
    ~Static() { std::printf("static object destroyed after them: [%s]\n", logs[0].c_str()); }
};
static Static static_object;

struct MainOnly {
    ~MainOnly()
    {
        if (who == 0)
            std::printf("main thread's thread_local destroyed: %s\n", words.c_str());
    }
};
thread_local MainOnly main_only;

int main()
{
    std::vector<std::thread> ts;
    for (int i = 1; i <= 8; i++)
        ts.emplace_back(work, i);
    for (auto &t : ts)
        t.join();
    for (int i = 1; i <= 8; i++)
        std::printf("thread %d: %s\n", i, logs[i].c_str());
    std::printf("main thread so far: [%s] numbers %zu words %s\n", logs[0].c_str(), numbers.size(),
                words.c_str());
    (void)&main_only;
    words = "main's";
    local().name = "main local";
    std::printf("main returns\n");
    return 0;
}
