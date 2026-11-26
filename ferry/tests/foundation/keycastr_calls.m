/* SPDX-License-Identifier: GPL-3.0-or-later
 * What KeyCastr, its Sparkle and ShortcutRecorder, and MacDown's frameworks
 * call in Foundation, CoreFoundation, the C library, ServiceManagement,
 * Security and SystemConfiguration (freemac 1.224, Ferry 0.48.0): the
 * CoreFoundation notification centers, Mach ports (none), os_trace and
 * os_activity, an XPC connection that never connects, data searches
 * backwards and anchored, bookmarks, plists read from URLs, Markdown (not
 * read), defaults suites, the launchd calls (all refused), authorization
 * rights, the console user, renamex_np, O_NOFOLLOW_ANY, futimes and a bundle's folders. Run in a
 * home of the test's own. */
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ServiceManagement/ServiceManagement.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <os/trace.h>
#include <os/activity.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/time.h>

@protocol FerryHelper
- (void)ping:(NSString *)what reply:(void (^)(NSString *answer))reply;
- (int)count;
@end

static int local_calls, darwin_calls;
static void on_local(CFNotificationCenterRef c, void *observer, CFNotificationName name, const void *object,
                     CFDictionaryRef info)
{
    local_calls++;
    printf("  local: %s, observer %s, user info %s\n", [(__bridge NSString *)name UTF8String], (const char *)observer,
           [[(__bridge NSDictionary *)info description] UTF8String]);
}
static void on_darwin(CFNotificationCenterRef c, void *observer, CFNotificationName name, const void *object,
                      CFDictionaryRef info)
{
    darwin_calls++;
    printf("  darwin: %s, object %s, user info %s\n", [(__bridge NSString *)name UTF8String], object ? "set" : "NULL",
           info ? "set" : "NULL");
}

static NSString *range_text(NSRange r)
{
    return r.location == NSNotFound ? @"not found" : [NSString stringWithFormat:@"%lu+%lu", r.location, r.length];
}

static void notifications(void)
{
    printf("notification centers\n");
    CFNotificationCenterRef local = CFNotificationCenterGetLocalCenter();
    printf("  the local center is the default center: %s\n",
           (__bridge id)local == [NSNotificationCenter defaultCenter] ? "yes" : "no");
    CFNotificationCenterAddObserver(local, "first", on_local, CFSTR("FerryLocalNote"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterPostNotification(local, CFSTR("FerryLocalNote"), NULL,
                                         (__bridge CFDictionaryRef) @{@"k" : @"v"}, true);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FerryLocalNote" object:nil];
    CFNotificationCenterRemoveObserver(local, "first", CFSTR("FerryLocalNote"), NULL);
    CFNotificationCenterPostNotification(local, CFSTR("FerryLocalNote"), NULL, NULL, true);
    printf("  local calls: %d\n", local_calls);

    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin, "d", on_darwin, CFSTR("org.freemac.ferry.note"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    /* the Darwin center carries the name only */
    CFNotificationCenterPostNotification(darwin, CFSTR("org.freemac.ferry.note"), "object",
                                         (__bridge CFDictionaryRef) @{@"k" : @"v"}, true);
    CFNotificationCenterRemoveEveryObserver(darwin, "d");
    CFNotificationCenterPostNotification(darwin, CFSTR("org.freemac.ferry.note"), NULL, NULL, true);
    printf("  darwin calls: %d\n", darwin_calls);

    CFMachPortContext ctx = {0};
    Boolean freeInfo = false;
    CFMachPortRef port = CFMachPortCreate(NULL, NULL, &ctx, &freeInfo);
    printf("  CFMachPortCreate: %s\n", port ? "a port" : "NULL");
}

static void tracing(void)
{
    printf("os_trace and os_activity\n");
    os_trace("a trace line %d", 1);
    os_trace_debug("a debug line");
    os_trace_error("an error line %s", "here");
    os_activity_t act = os_activity_create("Ferry activity", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT);
    struct os_activity_scope_state_s state;
    os_activity_scope_enter(act, &state);
    os_activity_scope_leave(&state);
    printf("  info enabled %d, debug enabled %d\n", (int)os_trace_info_enabled(), (int)os_trace_debug_enabled());
}

static void xpc(void)
{
    printf("XPC\n");
    NSXPCConnection *c = [[NSXPCConnection alloc] initWithServiceName:@"org.freemac.ferry.Helper"];
    c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(FerryHelper)];
    __block int invalidated = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    c.invalidationHandler = ^{
        invalidated++;
        dispatch_semaphore_signal(sem);
    };
    [c resume];
    __block NSError *seen = nil;
    __block BOOL replied = NO;
    id<FerryHelper> proxy = [c remoteObjectProxyWithErrorHandler:^(NSError *error) {
        seen = error;
        dispatch_semaphore_signal(sem);
    }];
    [proxy ping:@"hello" reply:^(NSString *answer) {
        replied = YES;
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    printf("  async proxy: error %s %ld, reply %s, invalidated %d\n", [[seen domain] UTF8String], (long)[seen code],
           replied ? "yes" : "no", invalidated);
    __block NSError *syncError = nil;
    id<FerryHelper> sync = [c synchronousRemoteObjectProxyWithErrorHandler:^(NSError *error) {
        syncError = error;
    }];
    int n = [sync count];
    printf("  synchronous proxy: returned %d, error %ld (before the call returned), invalidated %d\n", n,
           (long)[syncError code], invalidated);
    [c invalidate];
}

static void data_and_urls(NSString *dir)
{
    printf("data searches\n");
    NSData *d = [@"abcabcab" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ab = [@"ab" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bc = [@"bc" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange all = NSMakeRange(0, [d length]);
    printf("  forwards %s, backwards %s, anchored %s, anchored backwards %s, anchored bc %s\n",
           [range_text([d rangeOfData:ab options:0 range:all]) UTF8String],
           [range_text([d rangeOfData:ab options:NSDataSearchBackwards range:all]) UTF8String],
           [range_text([d rangeOfData:ab options:NSDataSearchAnchored range:all]) UTF8String],
           [range_text([d rangeOfData:ab options:NSDataSearchBackwards | NSDataSearchAnchored range:all]) UTF8String],
           [range_text([d rangeOfData:bc options:NSDataSearchAnchored range:all]) UTF8String]);
    printf("  in 2+4: %s, backwards in 0+5: %s\n",
           [range_text([d rangeOfData:ab options:0 range:NSMakeRange(2, 4)]) UTF8String],
           [range_text([d rangeOfData:ab options:NSDataSearchBackwards range:NSMakeRange(0, 5)]) UTF8String]);

    printf("plists at URLs\n");
    NSURL *plist = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"d.plist"]];
    [@{@"name" : @"Ferry", @"n" : @3} writeToURL:plist atomically:YES];
    [@[ @1, @"two" ] writeToURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"a.plist"]] atomically:YES];
    NSError *err = nil;
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfURL:plist error:&err];
    NSArray *arr = [NSArray arrayWithContentsOfURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"a.plist"]]
                                             error:&err];
    printf("  dictionary %s %s, array %lu items\n", [dict[@"name"] UTF8String], [[dict[@"n"] description] UTF8String],
           (unsigned long)[arr count]);
    err = nil;
    NSDictionary *none = [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:@"/nonexistent/x.plist"]
                                                             error:&err];
    printf("  missing file: %s, error %s %ld\n", none ? "a dictionary" : "nil", [[err domain] UTF8String],
           (long)[err code]);

    printf("bookmarks\n");
    NSString *file = [dir stringByAppendingPathComponent:@"marked.txt"];
    [@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSURL *url = [NSURL fileURLWithPath:file];
    NSData *mark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                 includingResourceValuesForKeys:nil
                                  relativeToURL:nil
                                          error:&err];
    BOOL stale = YES;
    NSURL *back = [NSURL URLByResolvingBookmarkData:mark
                                            options:NSURLBookmarkResolutionWithSecurityScope
                                      relativeToURL:nil
                                bookmarkDataIsStale:&stale
                                              error:&err];
    printf("  resolved to the same file: %s, stale %d, scope started %d\n",
           [[back path] isEqualToString:file] ? "yes" : "no", stale, [back startAccessingSecurityScopedResource]);
    [back stopAccessingSecurityScopedResource];
    [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    err = nil;
    back = [NSURL URLByResolvingBookmarkData:mark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&err];
    printf("  after the file went: %s, error %ld\n", back ? "a URL" : "nil", (long)[err code]);
    err = nil;
    back = [NSURL URLByResolvingBookmarkData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]
                                     options:0
                               relativeToURL:nil
                         bookmarkDataIsStale:&stale
                                       error:&err];
    printf("  junk: %s, error %ld\n", back ? "a URL" : "nil", (long)[err code]);
    id volume = nil;
    [[NSURL fileURLWithPath:dir] getResourceValue:&volume forKey:NSURLVolumeIdentifierKey error:NULL];
    printf("  volume identifier: %s\n", volume ? "set" : "nil");
}

static void strings_and_errors(void)
{
    printf("strings and errors\n");
    NSString *s = @"caf\u00e9 \u00e0 la carte";
    printf("  %s / %s / %s\n", [[s localizedUppercaseString] UTF8String], [[@"FERRY Boat" localizedLowercaseString] UTF8String],
           [[@"the ferry boat" localizedCapitalizedString] UTF8String]);
    /* Ferry 0.66: OBS lowercases its names with lowercaseStringWithLocale: */
    NSLocale *en = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    printf("  with a locale: %s / %s / %s; nil: %s\n", [[@"Video Capture Device" lowercaseStringWithLocale:en] UTF8String],
           [[@"mac capture" uppercaseStringWithLocale:en] UTF8String],
           [[@"screen capture" capitalizedStringWithLocale:en] UTF8String],
           [[@"OBS Studio" lowercaseStringWithLocale:nil] UTF8String]);
    printf("  NSMultipleUnderlyingErrorsKey: %s\n", [NSMultipleUnderlyingErrorsKey UTF8String]);
    printf("  NSHomeDirectoryForUser(me) is the home: %s, for no one: %s\n",
           [NSHomeDirectoryForUser(NSUserName()) isEqualToString:NSHomeDirectory()] ? "yes" : "no",
           NSHomeDirectoryForUser(@"no-such-user-here") ? "a folder" : "nil");
    NSError *err = nil;
    NSAttributedString *md = [[NSAttributedString alloc] initWithMarkdownString:@"**bold**" options:nil
                                                                        baseURL:nil
                                                                          error:&err];
    printf("  Markdown: %s, error %ld %s\n", md ? "read" : "nil", (long)[err code],
           [[err localizedDescription] UTF8String]);
    NSPresentationIntent *p = [NSPresentationIntent paragraphIntentWithIdentity:1 nestedInsideIntent:nil];
    printf("  a paragraph intent: kind %ld, identity %ld\n", (long)[p intentKind], (long)[p identity]);
}

static void defaults(void)
{
    printf("defaults suites\n");
    NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:@"org.freemac.ferry.suite"];
    [suite setObject:@"from the suite" forKey:@"FerrySuiteKey"];
    [suite setObject:@"the suite's" forKey:@"FerryBothKey"];
    [suite synchronize];
    NSUserDefaults *mine = [NSUserDefaults standardUserDefaults];
    [mine registerDefaults:@{@"FerrySuiteKey" : @"registered", @"FerryBothKey" : @"registered"}];
    [mine setObject:@"mine" forKey:@"FerryBothKey"];
    printf("  before: %s\n", [[mine stringForKey:@"FerrySuiteKey"] UTF8String]);
    [mine addSuiteNamed:@"org.freemac.ferry.suite"];
    printf("  added: %s, and my own still wins: %s\n", [[mine stringForKey:@"FerrySuiteKey"] UTF8String],
           [[mine stringForKey:@"FerryBothKey"] UTF8String]);
    [mine removeSuiteNamed:@"org.freemac.ferry.suite"];
    printf("  removed: %s\n", [[mine stringForKey:@"FerrySuiteKey"] UTF8String]);
}

static void system_calls(void)
{
    printf("launchd, authorization and the console user\n");
    CFErrorRef err = NULL;
    Boolean ok = SMJobRemove(kSMDomainUserLaunchd, CFSTR("org.freemac.ferry.job"), NULL, true, &err);
    printf("  SMJobRemove: %d, %s %ld\n", ok, [(__bridge NSString *)CFErrorGetDomain(err) UTF8String],
           (long)CFErrorGetCode(err));
    CFRelease(err);
    err = NULL;
    ok = SMJobBless(kSMDomainSystemLaunchd, CFSTR("org.freemac.ferry.helper"), NULL, &err);
    printf("  SMJobBless: %d, %ld\n", ok, (long)CFErrorGetCode(err));
    CFRelease(err);
    CFDictionaryRef job = SMJobCopyDictionary(kSMDomainUserLaunchd, CFSTR("org.freemac.ferry.job"));
    printf("  SMJobCopyDictionary: %s\n", job ? "a job" : "NULL");
    CFDictionaryRef right = NULL;
    printf("  AuthorizationRightGet: %d\n", (int)AuthorizationRightGet("org.freemac.ferry.right", &right));
    uid_t uid = 99;
    gid_t gid = 99;
    CFStringRef user = SCDynamicStoreCopyConsoleUser(NULL, &uid, &gid);
    printf("  console user is this user: %s, uid matches %d, gid matches %d\n",
           [(__bridge NSString *)user isEqualToString:NSUserName()] ? "yes" : "no", uid == getuid(), gid == getgid());
    if (user)
        CFRelease(user);
}

static void files(NSString *dir)
{
    printf("files\n");
    const char *a = [[dir stringByAppendingPathComponent:@"a"] fileSystemRepresentation];
    const char *b = [[dir stringByAppendingPathComponent:@"b"] fileSystemRepresentation];
    [@"A" writeToFile:@(a) atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    [@"B" writeToFile:@(b) atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    int r = renamex_np(a, b, RENAME_SWAP);
    printf("  RENAME_SWAP: %d, a now holds %s\n", r,
           [[NSString stringWithContentsOfFile:@(a) encoding:NSUTF8StringEncoding error:NULL] UTF8String]);
    errno = 0;
    r = renamex_np(a, b, RENAME_EXCL);
    printf("  RENAME_EXCL onto a file: %d, EEXIST %d\n", r, errno == EEXIST);
    NSString *real = [dir stringByAppendingPathComponent:@"real"];
    NSString *link = [dir stringByAppendingPathComponent:@"link"];
    [[NSFileManager defaultManager] createDirectoryAtPath:real withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"x" writeToFile:[real stringByAppendingPathComponent:@"f"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    symlink([real fileSystemRepresentation], [link fileSystemRepresentation]);
    int fd = open([[real stringByAppendingPathComponent:@"f"] fileSystemRepresentation], O_RDONLY | O_NOFOLLOW_ANY);
    printf("  O_NOFOLLOW_ANY with no link: %s\n", fd >= 0 ? "opened" : "refused");
    if (fd >= 0)
        close(fd);
    errno = 0;
    fd = open([[link stringByAppendingPathComponent:@"f"] fileSystemRepresentation], O_RDONLY | O_NOFOLLOW_ANY);
    printf("  O_NOFOLLOW_ANY through a link: %s, ELOOP %d\n", fd >= 0 ? "opened" : "refused", errno == ELOOP);
    if (fd >= 0)
        close(fd);
    fd = open(a, O_RDONLY);
    struct timeval tv[2] = {{1000000000, 250000}, {1200000000, 500000}};
    r = futimes(fd, tv);
    close(fd);
    struct stat st;
    stat(a, &st);
    printf("  futimes: %d, modified %ld\n", r, (long)st.st_mtime);
    tv[1].tv_sec = 1300000000;
    r = utimes(b, tv);
    stat(b, &st);
    printf("  utimes: %d, modified %ld\n", r, (long)st.st_mtime);
}

static void bundles(void)
{
    printf("bundles\n");
    NSBundle *m = [NSBundle mainBundle];
    printf("  frameworks folder ends %s, shared support ends %s\n",
           [[[m privateFrameworksPath] lastPathComponent] UTF8String],
           [[[m sharedSupportPath] lastPathComponent] UTF8String]);
    printf("  a missing helper: %s\n", [m pathForAuxiliaryExecutable:@"no-such-helper"] ? "found" : "nil");
    printf("  an unknown identifier: %s\n",
           [NSBundle bundleWithIdentifier:@"org.freemac.ferry.nothing"] ? "a bundle" : "nil");
    printf("  allBundles starts with the main bundle: %s\n", [[NSBundle allBundles] firstObject] == m ? "yes" : "no");
}

int main(void)
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-keycastr-calls"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        notifications();
        tracing();
        xpc();
        data_and_urls(dir);
        strings_and_errors();
        defaults();
        system_calls();
        files(dir);
        bundles();
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    return 0;
}
