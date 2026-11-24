/* SPDX-License-Identifier: GPL-3.0-or-later
 * The Accessibility API as a window manager such as Spectacle or ShiftIt
 * uses it (freemac 1.215, Ferry 0.41.0), against the stand-in Wayfire
 * (tests/tools/fake_wayfire.py): nothing until the user allows it, asked
 * once through freemac-allow-control (here fake_asker.sh, which answers
 * Allow); then the focused app and window, their titles, a window's place
 * and size from the main display's top left, moving and resizing it (and
 * onto another display) through window-rules/configure-view, minimizing and
 * raising; AXValues; NSScreen's frames from Wayfire's outputs; and turning
 * it off again, as Dials does. */
#import <Cocoa/Cocoa.h>
#include <ApplicationServices/ApplicationServices.h>
#include "wayfire_fake.h"

static NSString *str(CFTypeRef v)
{
    return v && [(__bridge id)v isKindOfClass:[NSString class]] ? (__bridge NSString *)v : @"(none)";
}

static CFTypeRef copy(AXUIElementRef e, CFStringRef attr, AXError *err)
{
    CFTypeRef v = NULL;
    *err = AXUIElementCopyAttributeValue(e, attr, &v);
    return v;
}

static void show_window(const char *label, AXUIElementRef w)
{
    AXError e1, e2, e3, e4;
    CFTypeRef title = copy(w, kAXTitleAttribute, &e1), sub = copy(w, kAXSubroleAttribute, &e2);
    CFTypeRef pos = copy(w, kAXPositionAttribute, &e3), size = copy(w, kAXSizeAttribute, &e4);
    CGPoint p = {0, 0};
    CGSize s = {0, 0};
    AXValueGetValue(pos, kAXValueTypeCGPoint, &p);
    AXValueGetValue(size, kAXValueTypeCGSize, &s);
    printf("%s: \"%s\" %s at %.0f,%.0f size %.0fx%.0f (%d %d %d %d)\n", label, [str(title) UTF8String],
           [str(sub) UTF8String], p.x, p.y, s.width, s.height, e1, e2, e3, e4);
    if (title) CFRelease(title);
    if (sub) CFRelease(sub);
    if (pos) CFRelease(pos);
    if (size) CFRelease(size);
}

static AXError set_point(AXUIElementRef w, CFStringRef attr, CGPoint p)
{
    AXValueRef v = AXValueCreate(kAXValueTypeCGPoint, &p);
    AXError r = AXUIElementSetAttributeValue(w, attr, v);
    CFRelease(v);
    return r;
}

static AXError set_size(AXUIElementRef w, CGSize s)
{
    AXValueRef v = AXValueCreate(kAXValueTypeCGSize, &s);
    AXError r = AXUIElementSetAttributeValue(w, kAXSizeAttribute, v);
    CFRelease(v);
    return r;
}

static void show_rect(const char *label, NSRect r)
{
    printf("%s %.0f,%.0f %.0fx%.0f\n", label, r.origin.x, r.origin.y, r.size.width, r.size.height);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        AXUIElementRef sys = AXUIElementCreateSystemWide();
        AXError err;
        CFTypeRef app = copy(sys, kAXFocusedApplicationAttribute, &err);
        printf("before asking: trusted %d, focused app %d %s\n", AXIsProcessTrusted(), err, app ? "set" : "NULL");

        NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
        printf("with the prompt: %d\n", AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts));
        for (int i = 0; i < 200 && !AXIsProcessTrusted(); i++)
            usleep(50000);
        printf("after the user's answer: trusted %d, with options %d\n", AXIsProcessTrusted(),
               AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts));
        NSString *asked = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"asker.log"]
                                                    encoding:NSUTF8StringEncoding error:NULL];
        printf("%s", [asked UTF8String] ?: "never asked\n");

        app = copy(sys, kAXFocusedApplicationAttribute, &err);
        pid_t pid = 0;
        AXError perr = AXUIElementGetPid(app, &pid);
        CFTypeRef role = copy(app, kAXRoleAttribute, &err), title = copy(app, kAXTitleAttribute, &err);
        printf("focused app: pid %d (%d), %s \"%s\", same type %d\n", pid, perr, [str(role) UTF8String],
               [str(title) UTF8String], CFGetTypeID(app) == AXUIElementGetTypeID());
        CFRelease(role);
        CFRelease(title);
        AXUIElementRef win = (AXUIElementRef)copy(app, kAXFocusedWindowAttribute, &err);
        show_window("focused window", win);
        CFTypeRef focusedUI = copy(sys, kAXFocusedUIElementAttribute, &err);
        printf("the focused element is that window %d\n", CFEqual(focusedUI, win));
        CFRelease(focusedUI);

        CFArrayRef windows = (CFArrayRef)copy(app, kAXWindowsAttribute, &err);
        printf("the app's windows: %ld (%d)\n", (long)CFArrayGetCount(windows), err);
        for (CFIndex i = 0; i < CFArrayGetCount(windows); i++)
            show_window("  window", (AXUIElementRef)CFArrayGetValueAtIndex(windows, i));
        AXUIElementRef other = (AXUIElementRef)CFArrayGetValueAtIndex(windows, 1);

        Boolean can = false, cannot = true;
        AXUIElementIsAttributeSettable(win, kAXPositionAttribute, &can);
        AXUIElementIsAttributeSettable(win, kAXTitleAttribute, &cannot);
        printf("position settable %d, title settable %d\n", can, cannot);

        /* Spectacle's left half of the main display: size, position, size */
        NSRect visible = [[NSScreen mainScreen] visibleFrame], full = [[NSScreen mainScreen] frame];
        CGPoint to = {visible.origin.x, NSMaxY(full) - NSMaxY(visible)};
        CGSize half = {floor(visible.size.width / 2), visible.size.height};
        printf("size %d, position %d, size %d\n", set_size(win, half), set_point(win, kAXPositionAttribute, to),
               set_size(win, half));
        show_window("moved", win);
        /* the other window, from the other display onto the main one */
        printf("onto the main display %d\n", set_point(other, kAXPositionAttribute, CGPointMake(100, 100)));
        show_window("moved", other);

        /* another app's window: minimized, then raised */
        AXUIElementRef browser = AXUIElementCreateApplication(5151);
        CFArrayRef bw = (CFArrayRef)copy(browser, kAXWindowsAttribute, &err);
        AXUIElementRef web = (AXUIElementRef)CFArrayGetValueAtIndex(bw, 0);
        show_window("browser window", web);
        printf("minimize %d, raise %d\n", AXUIElementSetAttributeValue(web, kAXMinimizedAttribute, kCFBooleanTrue),
               AXUIElementPerformAction(web, kAXRaiseAction));
        CFTypeRef front = copy(sys, kAXFocusedApplicationAttribute, &err);
        AXUIElementGetPid(front, &pid);
        printf("focused app now pid %d, the browser %d\n", pid, CFEqual(front, browser));
        CFRelease(front);

        /* what doesn't work */
        CFTypeRef none = copy(win, CFSTR("AXNoSuchThing"), &err);
        printf("unknown attribute %d %s\n", err, none ? "set" : "NULL");
        CGSize wrong = {1, 1};
        AXValueRef wv = AXValueCreate(kAXValueTypeCGSize, &wrong);
        CGPoint pt;
        printf("position from a size %d, read as a point %d, type %d\n",
               AXUIElementSetAttributeValue(win, kAXPositionAttribute, wv), AXValueGetValue(wv, kAXValueTypeCGPoint, &pt),
               AXValueGetType(wv));
        CFRelease(wv);
        CGRect rect = {{1, 2}, {3, 4}}, back;
        AXValueRef rv = AXValueCreate(kAXValueTypeCGRect, &rect);
        printf("a rectangle and back %d %.0f %.0f %.0f %.0f, value type %d\n", AXValueGetValue(rv, kAXValueTypeCGRect, &back),
               back.origin.x, back.origin.y, back.size.width, back.size.height, CFGetTypeID(rv) == AXValueGetTypeID());
        CFRelease(rv);

        /* the displays, from Wayfire's outputs */
        NSArray *screens = [NSScreen screens];
        printf("screens %lu, the main one first %d\n", (unsigned long)[screens count],
               [NSScreen mainScreen] == screens[0]);
        for (NSScreen *s in screens) {
            printf("%s (%s): ", [s.localizedName UTF8String], [[s.deviceDescription[@"NSScreenNumber"] description] UTF8String]);
            show_rect("frame", s.frame);
            show_rect("  visible", s.visibleFrame);
        }

        for (NSString *line in fake_call(@"fake/log", nil)[@"log"])
            printf("wayfire: %s\n", [line UTF8String]);

        /* Dials turns it off again */
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/freemac/window-control.json"];
        NSMutableDictionary *store = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]
                                                                     options:NSJSONReadingMutableContainers error:NULL];
        NSString *key = [store[@"apps"] allKeys].firstObject;
        printf("kept for the app: %s, allowed %d\n", [store[@"apps"][key][@"name"] UTF8String],
               [store[@"apps"][key][@"allowed"] boolValue]);
        store[@"apps"][key][@"allowed"] = @NO;
        [[NSJSONSerialization dataWithJSONObject:store options:0 error:NULL] writeToFile:path atomically:YES];
        printf("turned off: trusted %d, move %d\n", AXIsProcessTrusted(), set_point(win, kAXPositionAttribute, to));
        CFRelease(win);
        CFRelease(windows);
        CFRelease(bw);
        CFRelease(browser);
        CFRelease(app);
        CFRelease(sys);
    }
    return 0;
}
