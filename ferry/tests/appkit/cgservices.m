/* SPDX-License-Identifier: GPL-3.0-or-later
 * Quartz Window Services and Quartz Event Services as ShiftIt, MacPass,
 * Flycut and Sequel Pro use them (freemac 1.220, Ferry 0.44.0), against
 * the stand-in Wayfire (tests/tools/fake_wayfire.py): the app's own windows
 * always, other apps' only once the user allows the app to control other
 * windows (fake_asker.sh answering Allow), most recently focused first,
 * with Accessibility's bounds; the list's options; numbers and their
 * descriptions; a picture of the app's own window and of nothing else;
 * Command-V and arrow keys (Flycut) and typed text (MacPass) as Strata's
 * key presses, text only with the English (US) layout; mouse events and
 * event taps never; an event posted to the app itself; the events' own
 * fields; and nothing posted once Dials turns it off again. */
#import <Cocoa/Cocoa.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include "wayfire_fake.h"

static NSUInteger log_seen;

/* The stand-in Wayfire's lines since the last look. */
static void show_log(const char *label)
{
    NSArray *log = fake_call(@"fake/log", nil)[@"log"];
    printf("%s:", label);
    if ([log count] == log_seen)
        printf(" nothing");
    printf("\n");
    for (NSUInteger i = log_seen; i < [log count]; i++)
        printf("  wayfire: %s\n", [log[i] UTF8String]);
    log_seen = [log count];
}

static void show_list(const char *label, CFArrayRef list)
{
    NSArray *a = (__bridge NSArray *)list;
    printf("%s: %lu\n", label, (unsigned long)[a count]);
    for (NSDictionary *d in a) {
        CGRect r = CGRectZero;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)d[(__bridge id)kCGWindowBounds], &r);
        unsigned number = [d[(__bridge id)kCGWindowNumber] unsignedIntValue];
        int pid = [d[(__bridge id)kCGWindowOwnerPID] intValue];
        char who[32];
        if (pid == getpid())
            snprintf(who, sizeof who, "me");
        else
            snprintf(who, sizeof who, "%d", pid);
        char num[32];
        if (number & 0x40000000)
            snprintf(num, sizeof num, "view %u", number & 0x3fffffff);
        else
            snprintf(num, sizeof num, "own %u", number);
        printf("  %s \"%s\" of %s (%s), layer %d, at %.0f,%.0f size %.0fx%.0f, on screen %d, alpha %.1f\n", num,
               [d[(__bridge id)kCGWindowName] UTF8String], [d[(__bridge id)kCGWindowOwnerName] UTF8String], who,
               [d[(__bridge id)kCGWindowLayer] intValue], r.origin.x, r.origin.y, r.size.width, r.size.height,
               [d[(__bridge id)kCGWindowIsOnscreen] boolValue], [d[(__bridge id)kCGWindowAlpha] doubleValue]);
    }
    CFRelease(list);
}

static CGWindowID number_of(NSString *title)
{
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    CGWindowID n = 0;
    for (NSDictionary *d in (__bridge NSArray *)list)
        if ([d[(__bridge id)kCGWindowName] isEqual:title])
            n = [d[(__bridge id)kCGWindowNumber] unsignedIntValue];
    CFRelease(list);
    return n;
}

/* Flycut's fakeKey: the key with Command, down then up, at the HID tap. */
static void fake_key(CGKeyCode key, BOOL command)
{
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef down = CGEventCreateKeyboardEvent(source, key, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, key, false);
    if (command) {
        CGEventSetFlags(down, kCGEventFlagMaskCommand | 0x000008);
        CGEventSetFlags(up, kCGEventFlagMaskCommand | 0x000008);
    }
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    CFRelease(source);
}

/* MacPass's MPKeyTyper: the text on a key event of key 0. */
static void type_text(NSString *text)
{
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    UniChar buf[20];
    NSUInteger n = MIN([text length], (NSUInteger)20);
    [text getCharacters:buf range:NSMakeRange(0, n)];
    CGEventRef down = CGEventCreateKeyboardEvent(source, 0, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, 0, false);
    CGEventKeyboardSetUnicodeString(down, n, buf);
    CGEventKeyboardSetUnicodeString(up, n, buf);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    CFRelease(source);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *mine = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 200, 400, 300)
                                                     styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                         defer:NO];
        [mine setTitle:@"Mine"];
        [mine orderFront:nil];
        NSWindow *hidden = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                       styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                           defer:NO];
        [hidden setTitle:@"Hidden"];
        [hidden setLevel:NSFloatingWindowLevel];

        printf("levels: normal %d floating %d main menu %d status %d pop-up %d screen saver %d\n",
               kCGNormalWindowLevel, kCGFloatingWindowLevel, kCGMainMenuWindowLevel, kCGStatusWindowLevel,
               kCGPopUpMenuWindowLevel, kCGScreenSaverWindowLevel);
        printf("before asking: preflight %d, screen capture %d, listen %d\n", CGPreflightPostEventAccess(),
               CGPreflightScreenCaptureAccess(), CGPreflightListenEventAccess());
        show_list("on screen, not allowed",
                  CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                             kCGNullWindowID));
        show_list("all, not allowed", CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
        fake_key(kVK_ANSI_V, YES);
        type_text(@"no");
        show_log("posted, not allowed");

        printf("asking: %d\n", CGRequestPostEventAccess());
        for (int i = 0; i < 200 && !AXIsProcessTrusted(); i++)
            usleep(50000);
        printf("after the user's answer: preflight %d, screen capture %d, listen %d\n", CGPreflightPostEventAccess(),
               CGRequestScreenCaptureAccess(), CGRequestListenEventAccess());

        show_list("on screen, allowed",
                  CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                             kCGNullWindowID));
        /* the app's own window as the compositor shows it */
        fake_call(@"fake/add-view", @{
            @"id" : @30, @"app-id" : @"appkit_cgservices", @"title" : @"Mine", @"pid" : @(getpid()), @"output" : @2,
            @"geometry" : @{@"x" : @40, @"y" : @50, @"width" : @400, @"height" : @330}, @"focus" : @400
        });
        fake_call(@"fake/add-view", @{
            @"id" : @31, @"app-id" : @"appkit_cgservices", @"title" : @"a surface of its own", @"pid" : @(getpid()),
            @"output" : @2, @"geometry" : @{@"x" : @0, @"y" : @0, @"width" : @10, @"height" : @10}, @"focus" : @500
        });
        show_list("with the app's own window shown", CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));

        CGWindowID web = number_of(@"Web");
        show_list("above the browser", CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenAboveWindow, web));
        show_list("below the browser, and it",
                  CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenBelowWindow | kCGWindowListOptionIncludingWindow,
                                             web));
        show_list("just the browser", CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, web));
        show_list("no such window", CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, 0x3fffffff));

        CFArrayRef numbers = CGWindowListCreate(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
        printf("numbers: %ld, the first is mine %d\n", (long)CFArrayGetCount(numbers),
               (CGWindowID)(uintptr_t)CFArrayGetValueAtIndex(numbers, 0) == (CGWindowID)[mine windowNumber]);
        const void *two[] = {(const void *)(uintptr_t)web, (const void *)(uintptr_t)[hidden windowNumber]};
        CFArrayRef some = CFArrayCreate(NULL, two, 2, NULL);
        show_list("described", CGWindowListCreateDescriptionFromArray(some));
        CFRelease(some);
        CFRelease(numbers);

        /* Sequel Pro's and Flycut's pictures of their own windows */
        CGImageRef own = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
                                                 (CGWindowID)[mine windowNumber], kCGWindowImageBoundsIgnoreFraming);
        CGImageRef other = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, web,
                                                   kCGWindowImageDefault);
        CGImageRef screen = CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly, kCGNullWindowID,
                                                    kCGWindowImageDefault);
        printf("pictures: mine %zux%zu, another app's %s, the screen %s\n", own ? CGImageGetWidth(own) : 0,
               own ? CGImageGetHeight(own) : 0, other ? "taken" : "NULL", screen ? "taken" : "NULL");
        if (own)
            CGImageRelease(own);

        /* Flycut's paste and its arrow keys */
        fake_key(kVK_ANSI_V, YES);
        show_log("Command-V");
        fake_key(kVK_DownArrow, NO);
        fake_key(kVK_UpArrow, NO);
        show_log("down and up arrows");
        fake_key(kVK_Command, NO);
        show_log("Command alone");
        type_text(@"Ab1!");
        show_log("typed Ab1!");
        fake_call(@"fake/layout", @{@"name" : @"German"});
        type_text(@"Ab1!");
        show_log("typed with a German layout");
        fake_call(@"fake/layout", @{@"name" : @"English (US)"});
        type_text(@"café");
        show_log("typed what the layout can't");

        /* the rest of Quartz events */
        CGEventRef click = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(10, 20), kCGMouseButtonLeft);
        CGEventPost(kCGHIDEventTap, click);
        show_log("a click");
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventKeyDown), NULL, NULL);
        uint32_t taps = 9;
        CGGetEventTapList(0, NULL, &taps);
        printf("an event tap %s, taps %u\n", tap ? "made" : "NULL", taps);
        printf("a click: type %u, at %.0f,%.0f, button %lld, clicks %lld\n", CGEventGetType(click),
               CGEventGetLocation(click).x, CGEventGetLocation(click).y,
               CGEventGetIntegerValueField(click, kCGMouseEventButtonNumber),
               CGEventGetIntegerValueField(click, kCGMouseEventClickState));
        CFRelease(click);

        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        CGEventSourceSetUserData(source, 77);
        CGEventRef key = CGEventCreateKeyboardEvent(source, kVK_ANSI_A, true);
        CGEventSetFlags(key, kCGEventFlagMaskShift);
        printf("a key: type %u, code %lld, flags 0x%llx, user data %lld, source state %d, same type %d\n",
               CGEventGetType(key), CGEventGetIntegerValueField(key, kCGKeyboardEventKeycode),
               (unsigned long long)CGEventGetFlags(key), CGEventGetIntegerValueField(key, kCGEventSourceUserData),
               CGEventSourceGetSourceStateID(source), CFGetTypeID(key) == CGEventGetTypeID());
        CGEventRef copy = CGEventCreateCopy(key);
        CGEventSetIntegerValueField(copy, kCGKeyboardEventKeycode, kVK_ANSI_S);
        printf("a copy: code %lld, the first still %lld\n", CGEventGetIntegerValueField(copy, kCGKeyboardEventKeycode),
               CGEventGetIntegerValueField(key, kCGKeyboardEventKeycode));
        CFRelease(copy);

        /* KeyCastr's way from an event to an NSEvent, and back */
        NSEvent *ns = [NSEvent eventWithCGEvent:key];
        printf("as an NSEvent: type %lu, \"%s\" (\"%s\"), key code %u, shift %d\n", (unsigned long)[ns type],
               [[ns characters] UTF8String], [[ns charactersIgnoringModifiers] UTF8String], [ns keyCode],
               ([ns modifierFlags] & NSEventModifierFlagShift) != 0);
        CGEventRef back = [ns CGEvent];
        printf("and back: type %u, code %lld, same each time %d\n", CGEventGetType(back),
               CGEventGetIntegerValueField(back, kCGKeyboardEventKeycode), back == [ns CGEvent]);

        /* posted to the app itself, with no say needed */
        CGEventPostToPid(getpid(), key);
        NSEvent *got = [NSApp nextEventMatchingMask:NSEventMaskKeyDown untilDate:[NSDate dateWithTimeIntervalSinceNow:2]
                                             inMode:NSDefaultRunLoopMode dequeue:YES];
        printf("posted to itself: %s \"%s\"\n", got ? "got" : "nothing", got ? [[got characters] UTF8String] : "");
        CGEventPostToPid(5151, key);
        show_log("posted to an app without the keyboard");
        CGEventPostToPid(4242, key);
        show_log("posted to the app with the keyboard");
        CFRelease(key);
        CFRelease(source);

        /* Dials turns it off again */
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/freemac/window-control.json"];
        NSMutableDictionary *store = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]
                                                                     options:NSJSONReadingMutableContainers error:NULL];
        NSString *app = [store[@"apps"] allKeys].firstObject;
        store[@"apps"][app][@"allowed"] = @NO;
        [[NSJSONSerialization dataWithJSONObject:store options:0 error:NULL] writeToFile:path atomically:YES];
        /* and recording the screen too: CGRequestScreenCaptureAccess above
         * asked without waiting, so wait for that answer before turning it off
         * (else it could land after this, and the list show other windows) */
        NSString *recPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/freemac/screen-recording.json"];
        for (int i = 0; i < 100 && ![[NSFileManager defaultManager] fileExistsAtPath:recPath]; i++)
            usleep(50000);
        NSMutableDictionary *rec = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:recPath]
                                                                   options:NSJSONReadingMutableContainers error:NULL];
        for (NSString *k in [rec[@"apps"] allKeys])
            rec[@"apps"][k][@"allowed"] = @NO;
        if (rec)
            [[NSJSONSerialization dataWithJSONObject:rec options:0 error:NULL] writeToFile:recPath atomically:YES];
        printf("turned off: preflight %d\n", CGPreflightPostEventAccess());
        show_list("on screen, turned off",
                  CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
        fake_key(kVK_ANSI_V, YES);
        show_log("posted, turned off");
    }
    return 0;
}
