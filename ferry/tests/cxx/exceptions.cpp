// SPDX-License-Identifier: GPL-3.0-or-later
// C++ exceptions in a Mac program, thrown and caught by this system's
// libc++abi: through frame-pointer and frameless functions, destructors on
// the way, through this system's C library (a qsort callback), out of a Mac
// library of the program's own with its typeinfo, rethrown, carried in an
// exception_ptr, nested, and finally std::terminate's handler.
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>
#include <typeinfo>
#include <unistd.h>
#include <vector>

#include "shapes.h"

static std::string trail;

struct Guard {
    const char *name;
    explicit Guard(const char *n) : name(n) {}
    ~Guard() { trail += std::string(name) + ' '; }
};

__attribute__((noinline)) static int deep(int n)
{
    Guard g(n % 2 ? "odd" : "even");
    if (n == 0)
        throw std::out_of_range("bottom reached");
    return deep(n - 1) + 1;
}

// a function with no frame pointer and saved registers
__attribute__((noinline, optnone)) static long frameless(long a, long b, long c)
{
    volatile long x = a * b + c;
    if (x > 100)
        throw x;
    return x;
}

static int compare(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    if (x == 13 || y == 13)
        throw std::string("unlucky number met in qsort");
    return x - y;
}

struct Base1 { virtual ~Base1() {} int one = 1; };
struct Base2 { virtual ~Base2() {} int two = 2; };
struct Both : Base1, Base2 { int both = 3; };

static void terminate_handler()
{
    std::printf("terminate handler: %s\n",
                std::current_exception() ? "with an exception" : "no exception");
    std::fflush(stdout);
    _exit(3);
}

#pragma clang diagnostic ignored "-Wexceptions"
__attribute__((noinline)) static void no_throw() noexcept
{
    throw std::logic_error("out of a noexcept function");
}

int main()
{
    try {
        deep(5);
    } catch (const std::logic_error &e) {
        std::printf("caught logic_error: %s\n", e.what());
    }
    std::printf("destructors: %s\n", trail.c_str());

    try {
        frameless(20, 30, 4);
    } catch (long v) {
        std::printf("caught long %ld\n", v);
    }

    std::vector<int> v{5, 3, 13, 8, 1};
    try {
        std::qsort(v.data(), v.size(), sizeof(int), compare);
    } catch (const std::string &s) {
        std::printf("caught string: %s\n", s.c_str());
    }

    // a library's exceptions and typeinfo
    std::unique_ptr<Shape> sq(make_shape("square", 3));
    const Shape &shape = *sq;
    std::printf("%s area %g, typeid %s, same type %d\n", sq->name().c_str(), sq->area(),
                typeid(shape) == typeid(Square) ? "Square" : "other", typeid(shape) == square_type());
    std::printf("dynamic_cast %s\n", dynamic_cast<Square *>(sq.get()) ? "Square" : "null");
    try {
        make_shape("hexagon", 1);
    } catch (const BadShape &e) {
        std::printf("caught BadShape %d: %s\n", e.code, e.what());
    }
    try {
        check_shape(nullptr);
    } catch (const std::exception &e) {
        std::printf("caught %s: %s\n", dynamic_cast<const std::invalid_argument *>(&e) ? "invalid_argument" : "?",
                    e.what());
    }

    // rethrowing, exception_ptr, nested exceptions
    std::exception_ptr saved;
    try {
        try {
            throw std::runtime_error("first");
        } catch (...) {
            saved = std::current_exception();
            throw;
        }
    } catch (const std::runtime_error &e) {
        std::printf("rethrown: %s\n", e.what());
    }
    try {
        std::rethrow_exception(saved);
    } catch (const std::exception &e) {
        std::printf("from exception_ptr: %s\n", e.what());
    }
    try {
        try {
            throw std::runtime_error("inner");
        } catch (...) {
            std::throw_with_nested(std::logic_error("outer"));
        }
    } catch (const std::logic_error &e) {
        std::printf("nested: %s", e.what());
        try {
            std::rethrow_if_nested(e);
        } catch (const std::runtime_error &inner) {
            std::printf(" <- %s\n", inner.what());
        }
    }

    // catching through a second base, standard exceptions of the library
    try {
        throw Both();
    } catch (const Base2 &b) {
        std::printf("caught Both as Base2: two=%d\n", b.two);
    }
    try {
        Base1 b;
        (void)dynamic_cast<Both &>(b);
    } catch (const std::bad_cast &) {
        std::printf("caught bad_cast\n");
    }
    try {
        std::vector<int> small(2);
        (void)small.at(5);
    } catch (const std::out_of_range &) {
        std::printf("caught out_of_range from at()\n");
    }
    try {
        throw 42;
    } catch (...) {
        std::printf("caught ... with %d uncaught\n", std::uncaught_exceptions());
    }
    struct Counter {
        ~Counter() { std::printf("unwinding, uncaught_exceptions %d\n", std::uncaught_exceptions()); }
    };
    try {
        Counter c;
        throw 1;
    } catch (int) {
    }

    std::set_terminate(terminate_handler);
    no_throw();
    std::printf("not reached\n");
    return 0;
}
