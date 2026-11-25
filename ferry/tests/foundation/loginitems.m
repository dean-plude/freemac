/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0): login items, as Gas Mask,
 * ShiftIt, Spectacle and Flycut set them. run.sh starts this program as
 * Test.app, with a helper in Contents/Library/LoginItems, in a home of its
 * own. The session's shared file list: items inserted first and last, read
 * back in order with their names, IDs and resolved URLs; the autostart
 * entries they are kept in; inserting the same app again moves it; an entry
 * switched off in the desktop's settings drops out; properties; an
 * observer; removing. A list kept only in memory. Then
 * SMLoginItemSetEnabled turning the helper on and off. */
#import <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>
#include <ServiceManagement/ServiceManagement.h>
#include <stdlib.h>

static NSString *home;
static NSString *tilde(NSString *p)
{
    return [p hasPrefix:home] ? [@"~" stringByAppendingString:[p substringFromIndex:[home length]]] : p;
}
static NSString *autostart(void) { return [home stringByAppendingPathComponent:@".config/autostart"]; }

static void list(const char *label, LSSharedFileListRef l)
{
    UInt32 seed = 0;
    NSArray *items = CFBridgingRelease(LSSharedFileListCopySnapshot(l, &seed));
    printf("%s (%lu):", label, (unsigned long)[items count]);
    for (id o in items) {
        LSSharedFileListItemRef it = (__bridge LSSharedFileListItemRef)o;
        NSString *name = CFBridgingRelease(LSSharedFileListItemCopyDisplayName(it));
        CFURLRef url = NULL;
        OSStatus err = LSSharedFileListItemResolve(it, kLSSharedFileListNoUserInteraction, &url, NULL);
        printf(" [%s %s%s]", [name UTF8String], err ? "unresolved" : [tilde([(__bridge NSURL *)url path]) UTF8String],
               LSSharedFileListItemGetID(it) ? "" : " no ID");
        if (url)
            CFRelease(url);
    }
    printf("\n");
}
static LSSharedFileListItemRef find(LSSharedFileListRef l, NSString *path)
{
    UInt32 seed;
    NSArray *items = CFBridgingRelease(LSSharedFileListCopySnapshot(l, &seed));
    for (id o in items) {
        CFURLRef url = NULL;
        if (LSSharedFileListItemResolve((__bridge LSSharedFileListItemRef)o, 0, &url, NULL) == noErr) {
            BOOL same = [[(__bridge NSURL *)url path] isEqualToString:path];
            CFRelease(url);
            if (same)
                return (LSSharedFileListItemRef)CFRetain((__bridge CFTypeRef)o);
        }
    }
    return NULL;
}
static void files(const char *label)
{
    NSArray *f = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:autostart() error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    printf("%s: %s\n", label, [f count] ? [[f componentsJoinedByString:@" "] UTF8String] : "(none)");
}
static NSString *entry(NSString *file)
{
    return [NSString stringWithContentsOfFile:[autostart() stringByAppendingPathComponent:file]
                                     encoding:NSUTF8StringEncoding error:NULL];
}
static NSString *line(NSString *text, NSString *key)
{
    for (NSString *l in [text componentsSeparatedByString:@"\n"])
        if ([l hasPrefix:[key stringByAppendingString:@"="]])
            return [l substringFromIndex:[key length] + 1];
    return nil;
}

static int heard;
static void changed(LSSharedFileListRef l, void *ctx) { heard += (int)(intptr_t)ctx; }

int main(void)
{
    @autoreleasepool {
        home = [NSString stringWithUTF8String:getenv("HOME")];
        NSString *me = [[NSBundle mainBundle] bundlePath];
        printf("running as %s\n", [tilde(me) UTF8String]);
        NSString *other = [home stringByAppendingPathComponent:@"Apps/Other Thing.app"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[other stringByAppendingPathComponent:@"Contents"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];

        LSSharedFileListRef l = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        LSSharedFileListAddObserver(l, CFRunLoopGetMain(), kCFRunLoopDefaultMode, changed, (void *)1);
        list("at first", l);
        UInt32 seed0 = LSSharedFileListGetSeedValue(l);
        LSSharedFileListItemRef mine = LSSharedFileListInsertItemURL(
            l, kLSSharedFileListItemLast, NULL, NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:me], NULL, NULL);
        NSDictionary *hide = @{(__bridge NSString *)kLSSharedFileListLoginItemHidden : @YES};
        LSSharedFileListItemRef theirs = LSSharedFileListInsertItemURL(
            l, kLSSharedFileListItemBeforeFirst, CFSTR("Other"), NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:other],
            (__bridge CFDictionaryRef)hide, NULL);
        printf("inserted: %s, %s; seed moved on: %s; observer heard %d change(s)\n", mine ? "mine" : "-",
               theirs ? "theirs" : "-", LSSharedFileListGetSeedValue(l) != seed0 ? "yes" : "no", heard);
        list("two items", l);
        files("autostart entries");
        NSString *e = entry(@"ferry-org.freemac.test.loginitems.desktop");
        NSString *exec = line(e, @"Exec");
        printf("entry: name %s, runs ferry %s, with the app %s, starts at login %s\n", [line(e, @"Name") UTF8String],
               [exec hasPrefix:@"\""] && [exec rangeOfString:@"ferry\" "].location != NSNotFound ? "yes" : "no",
               [exec hasSuffix:[NSString stringWithFormat:@"\"%@\"", me]] ? "yes" : "no",
               [line(e, @"X-GNOME-Autostart-enabled") UTF8String]);
        NSString *oe = entry(@"ferry-Other_Thing.desktop");
        printf("the other's entry: name %s, hidden at launch %s\n", [line(oe, @"Name") UTF8String],
               [line(oe, @"X-Ferry-Hide-At-Launch") UTF8String]);
        CFTypeRef hid = LSSharedFileListItemCopyProperty(theirs, kLSSharedFileListLoginItemHidden);
        printf("its property: %s\n", hid == kCFBooleanTrue ? "hidden" : "not hidden");
        if (hid)
            CFRelease(hid);
        UInt32 mineID = LSSharedFileListItemGetID(mine);
        LSSharedFileListItemRef again = find(l, me);
        printf("found again with the same ID: %s\n", again && LSSharedFileListItemGetID(again) == mineID ? "yes" : "no");

        /* The same app again goes where it is put. */
        LSSharedFileListItemRef moved = LSSharedFileListInsertItemURL(
            l, kLSSharedFileListItemBeforeFirst, NULL, NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:me], NULL, NULL);
        list("inserted again first", l);
        CFRelease(moved);

        /* Gone from disk: it no longer resolves. */
        [[NSFileManager defaultManager] moveItemAtPath:other toPath:[other stringByAppendingString:@".moved"] error:NULL];
        CFURLRef u = NULL;
        printf("resolving a moved app: %d\n", (int)LSSharedFileListItemResolve(theirs, 0, &u, NULL));
        CFErrorRef cerr = NULL;
        CFURLRef ru = LSSharedFileListItemCopyResolvedURL(theirs, 0, &cerr);
        printf("copying its URL: %s, error %ld\n", ru ? "a URL" : "none", cerr ? (long)[(__bridge NSError *)cerr code] : 0L);
        if (cerr)
            CFRelease(cerr);
        [[NSFileManager defaultManager] moveItemAtPath:[other stringByAppendingString:@".moved"] toPath:other error:NULL];

        /* Switched off in the desktop's startup settings. */
        NSString *op = [autostart() stringByAppendingPathComponent:@"ferry-Other_Thing.desktop"];
        [[entry(@"ferry-Other_Thing.desktop") stringByAppendingString:@"Hidden=true\n"]
            writeToFile:op atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        list("one switched off", l);
        [[NSFileManager defaultManager] removeItemAtPath:op error:NULL];

        heard = 0;
        OSStatus rm = LSSharedFileListItemRemove(l, mine);
        printf("removed: %d, observer heard %d; removing again: %d\n", (int)rm, heard,
               (int)LSSharedFileListItemRemove(l, mine));
        list("after removing", l);
        files("autostart entries");
        CFRelease(mine);
        CFRelease(theirs);
        CFRelease(again);
        LSSharedFileListRemoveObserver(l, CFRunLoopGetMain(), kCFRunLoopDefaultMode, changed, (void *)1);
        CFRelease(l);

        /* A list in memory. */
        LSSharedFileListRef recent = LSSharedFileListCreate(NULL, kLSSharedFileListRecentDocumentItems, NULL);
        LSSharedFileListItemRef doc = LSSharedFileListInsertItemURL(
            recent, kLSSharedFileListItemLast, CFSTR("Notes"), NULL,
            (__bridge CFURLRef)[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"notes.txt"]], NULL, NULL);
        LSSharedFileListRef recent2 = LSSharedFileListCreate(NULL, kLSSharedFileListRecentDocumentItems, NULL);
        UInt32 s;
        NSArray *r = CFBridgingRelease(LSSharedFileListCopySnapshot(recent2, &s));
        printf("recent documents seen from a second list: %lu\n", (unsigned long)[r count]);
        LSSharedFileListRemoveAllItems(recent);
        r = CFBridgingRelease(LSSharedFileListCopySnapshot(recent2, &s));
        printf("after removing all: %lu\n", (unsigned long)[r count]);
        CFRelease(doc);
        CFRelease(recent);
        CFRelease(recent2);
        files("autostart entries");

        /* ServiceManagement. */
        printf("helper on: %d\n", SMLoginItemSetEnabled(CFSTR("org.freemac.test.helper"), true));
        files("autostart entries");
        NSString *he = entry(@"ferry-login-org.freemac.test.helper.desktop");
        printf("helper entry: name %s, runs the helper %s, kind %s, listed %s\n", [line(he, @"Name") UTF8String],
               [line(he, @"Exec") hasSuffix:@"Contents/Library/LoginItems/Helper.app\""] ? "yes" : "no",
               [line(he, @"X-Ferry-Login-Helper") UTF8String], line(he, @"NoDisplay") ? "no" : "yes");
        l = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        list("not a shared file list item", l);
        CFRelease(l);
        printf("unknown helper on: %d\n", SMLoginItemSetEnabled(CFSTR("org.freemac.test.nobody"), true));
        printf("helper off: %d, off again: %d\n", SMLoginItemSetEnabled(CFSTR("org.freemac.test.helper"), false),
               SMLoginItemSetEnabled(CFSTR("org.freemac.test.helper"), false));
        files("autostart entries");
    }
    return 0;
}
