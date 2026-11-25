/* SPDX-License-Identifier: GPL-3.0-or-later
 * Modules (freemac 1.222, Ferry 0.46.0): "@import Foundation;" and the
 * like, as KeyCastr's and Flycut's sources begin, built with no -framework
 * flags at all, since each module links its own framework; and "#import
 * <Cocoa/Cocoa.h>" becoming a module import, with a header's macros still
 * reaching the program. Quartz and CoreServices are served from AppKit's
 * and Foundation's files. */
@import Foundation;
@import AppKit;
@import QuartzCore;
@import CoreGraphics;
@import Quartz;
@import CoreServices;
@import JavaScriptCore;
#import <Cocoa/Cocoa.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool {
#if __has_feature(modules)
        printf("modules: on\n");
#else
        printf("modules: off\n");
#endif
        NSString *s = [NSString stringWithFormat:@"%d apps", 9];
        printf("Foundation: %s\n", s.UTF8String);
        NSRect r = NSInsetRect(NSMakeRect(0, 0, 100, 50), 10, 5);
        printf("AppKit: %s, %s\n", NSStringFromRect(r).UTF8String, NSStringFromClass([NSView class]).UTF8String);
        CALayer *layer = [CALayer layer];
        layer.bounds = CGRectMake(0, 0, 4, 3);
        printf("QuartzCore: %.0fx%.0f\n", layer.bounds.size.width, layer.bounds.size.height);
        CGRect u = CGRectUnion(CGRectMake(0, 0, 1, 1), CGRectMake(2, 2, 1, 1));
        printf("CoreGraphics: %.0fx%.0f\n", u.size.width, u.size.height);
        printf("a macro from a module: %d\n", NSAppKitVersionNumber10_10);
        printf("Quartz: %s, CoreServices: %s\n", NSStringFromClass([QLPreviewPanel class]).UTF8String,
               FSEventsGetCurrentEventId() == 0 ? "no events yet" : "events");
        printf("JavaScriptCore: %s, %s\n", NSStringFromClass([JSContext class]).UTF8String,
               kJSTypeObject == 5 ? "its C types" : "?");
    }
    return 0;
}
