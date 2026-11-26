/* SPDX-License-Identifier: GPL-3.0-or-later
 * Objective-C++ against Cocoa: AppKit's and Foundation's C calls keep C
 * linkage in C++, as on a Mac, so a C++ program finds them (Qt's Mac plugin
 * is such a program), next to the C++ library's own headers. */
#import <Cocoa/Cocoa.h>
#include <cmath>
#include <string>
#include <vector>

int main()
{
    @autoreleasepool {
        std::vector<int> v{1, 2, 3};
        NSRange r = NSIntersectionRange(NSMakeRange(0, 5), NSMakeRange(3, 5));
        printf("range %lu+%lu, mouse in %d, depth %ld bits, vector %zu\n", (unsigned long)r.location,
               (unsigned long)r.length, (int)NSMouseInRect(NSMakePoint(1, 1), NSMakeRect(0, 0, 2, 2), NO),
               (long)NSBitsPerPixelFromDepth(NSWindowDepthTwentyfourBitRGB), v.size());
        std::string s = [[NSString stringWithFormat:@"%.3f", std::sqrt(2.0)] UTF8String];
        NSString *back = [NSString stringWithUTF8String:(s + " ok").c_str()];
        printf("%s, nil is %s\n", [back UTF8String], nil == nullptr ? "nullptr" : "other");
    }
    return 0;
}
