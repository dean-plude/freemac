// SPDX-License-Identifier: GPL-3.0-or-later
// Objective-C++ under ARC: C++ objects inside Objective-C objects (built
// and destroyed by .cxx_construct and .cxx_destruct), Objective-C objects
// inside C++ containers, blocks that capture C++ objects, and exceptions of
// either language passing through frames of the other.
#import <Foundation/Foundation.h>

#include <cstdio>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

static int alive;

struct Tracked {
    std::string name;
    explicit Tracked(std::string n = "default") : name(std::move(n)) { alive++; }
    Tracked(const Tracked &o) : name(o.name + "'") { alive++; }
    ~Tracked() { alive--; }
};

@interface Holder : NSObject {
@public
    Tracked tracked;
    std::vector<int> numbers;
    std::map<std::string, NSString *> names;
}
- (int)sum;
@end

@implementation Holder
- (int)sum
{
    int s = 0;
    for (int n : numbers)
        s += n;
    return s;
}
@end

struct Logger {
    const char *what;
    explicit Logger(const char *w) : what(w) {}
    ~Logger() { std::printf("  destroyed %s\n", what); }
};

__attribute__((noinline)) static void cxx_frame_raising_objc()
{
    Logger l("C++ object in a frame an NSException passes");
    [NSException raise:@"FerryTest" format:@"raised %d", 7];
}

__attribute__((noinline)) static void objc_frame_passing_cxx()
{
    @try {
        throw std::runtime_error("C++ exception through @finally");
    } @finally {
        std::printf("  @finally ran\n");
    }
}

int main()
{
    @autoreleasepool {
        // C++ members of an Objective-C object
        @autoreleasepool {
            Holder *h = [Holder new];
            std::printf("constructed: name %s, alive %d\n", h->tracked.name.c_str(), alive);
            h->numbers = {1, 2, 3, 4};
            h->names["greeting"] = [NSString stringWithFormat:@"hello %d", 1];
            std::printf("sum %d, greeting %s\n", [h sum], [h->names["greeting"] UTF8String]);
            h = nil;
        }
        std::printf("after release: alive %d\n", alive);

        // Objective-C objects in C++ containers
        std::vector<NSString *> strings;
        for (int i = 0; i < 3; i++)
            strings.push_back([NSString stringWithFormat:@"item%d", i]);
        NSString *joined = [@[strings[0], strings[1], strings[2]] componentsJoinedByString:@","];
        std::printf("vector of NSString: %s\n", [joined UTF8String]);

        // blocks capturing C++ objects
        {
            Tracked t("captured");
            int (^block)(int) = ^(int x) { return (int)t.name.size() + x; };
            int (^copied)(int) = [block copy];
            std::printf("block %d, copy %d, alive %d\n", block(1), copied(2), alive);
            copied = nil;
            block = nil;
        }
        std::printf("after blocks: alive %d\n", alive);

        // an NSException through a C++ frame, caught by @catch
        @try {
            cxx_frame_raising_objc();
        } @catch (NSException *e) {
            std::printf("@catch %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        }

        // a C++ exception through an Objective-C frame, caught by catch
        try {
            objc_frame_passing_cxx();
        } catch (const std::exception &e) {
            std::printf("catch: %s\n", e.what());
        }

        // @catch (NSException *) lets a C++ exception go on; catch (...) takes either
        try {
            @try {
                throw 5;
            } @catch (NSException *e) {
                std::printf("wrong: @catch NSException took a C++ exception\n");
            }
        } catch (int n) {
            std::printf("C++ exception past @catch (NSException *): %d\n", n);
        }
        @try {
            try {
                [NSException raise:@"Inner" format:@"through catch (...)"];
            } catch (...) {
                std::printf("catch (...) took an NSException, rethrowing\n");
                throw;
            }
        } @catch (NSException *e) {
            std::printf("@catch after rethrow: %s\n", [[e reason] UTF8String]);
        }
        try {
            @try {
                throw std::logic_error("for @catch (...)");
            } @catch (...) {
                std::printf("@catch (...) took a C++ exception, rethrowing\n");
                @throw;
            }
        } catch (const std::logic_error &e) {
            std::printf("catch after @throw: %s\n", e.what());
        }
        @try {
            @throw [NSException exceptionWithName:@"Plain" reason:@"Objective-C only" userInfo:nil];
        } @catch (NSException *e) {
            std::printf("plain @try: %s\n", [[e reason] UTF8String]);
        } @finally {
            std::printf("plain @finally\n");
        }
    }
    std::printf("alive at the end %d\n", alive);
    return 0;
}
