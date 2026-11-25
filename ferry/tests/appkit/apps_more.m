/* SPDX-License-Identifier: GPL-3.0-or-later
 * What ShiftIt, Spectacle and Sparkle call in AppKit that this round
 * added (freemac 1.223, Ferry 0.47.0), built without ARC and with no
 * display: Scripting Bridge, which finds no app that Launch Services
 * doesn't know and answers nothing for one it does, telling the delegate;
 * the Touch Bar's classes, never shown; NSWorkspace's file operations
 * (copy, move, link, duplicate, recycle, destroy) and their notification;
 * the Cocoa error codes; and objc_msgSend called with its arguments, as
 * the old dispatch prototypes allow. Its files are in a home of its own. */
#import <Cocoa/Cocoa.h>
#import <ScriptingBridge/ScriptingBridge.h>
#import <objc/message.h>

static const char *yesno(BOOL b) { return b ? "yes" : "no"; }

@interface Listener : NSObject <SBApplicationDelegate, NSTouchBarDelegate> {
@public
    int failures, operations;
    long lastOperation;
}
@end
@implementation Listener
- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error
{
    failures++;
    printf("  delegate: event failed, %s %ld\n", [[error domain] UTF8String], (long)[error code]);
    return nil;
}
- (NSTouchBarItem *)touchBar:(NSTouchBar *)bar makeItemForIdentifier:(NSTouchBarItemIdentifier)ident
{
    if (![ident isEqualToString:@"org.example.made"])
        return nil;
    NSCustomTouchBarItem *item = [[[NSCustomTouchBarItem alloc] initWithIdentifier:ident] autorelease];
    item.customizationLabel = @"Made by the delegate";
    return item;
}
- (void)performed:(NSNotification *)n
{
    operations++;
    lastOperation = [[[n userInfo] objectForKey:@"NSOperationNumber"] longValue];
}
- (NSString *)joined:(NSString *)a with:(NSString *)b { return [NSString stringWithFormat:@"%@+%@", a, b]; }
- (double)half:(double)x { return x / 2; }
@end

/* what a generated scripting header declares for an app: a class with no
 * implementation, which the program only uses as a type */
@interface FinderLike : SBApplication
- (NSString *)name;
- (SBElementArray *)windows;
- (void)setVolume:(NSInteger)v;
@end

static BOOL exists(NSString *p) { return [[NSFileManager defaultManager] fileExistsAtPath:p]; }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Listener *l = [[Listener alloc] init];

        /* Scripting Bridge */
        printf("an app Launch Services doesn't know: %s\n",
               yesno([SBApplication applicationWithBundleIdentifier:@"com.example.NotInstalled"] == nil));
        printf("by URL to no bundle: %s\n",
               yesno([SBApplication applicationWithURL:[NSURL fileURLWithPath:@"/nonexistent/App.app"]] == nil));
        FinderLike *me = (FinderLike *)[SBApplication applicationWithProcessIdentifier:getpid()];
        printf("by our own process: %s, %s, running %s, timeout %ld\n", yesno(me != nil), [[me className] UTF8String],
               yesno([me isRunning]), [me timeout]);
        [me setDelegate:l];
        printf("its name: %s\n", [me name] ? [[me name] UTF8String] : "nil");
        SBElementArray *windows = [me windows];
        printf("its windows: %lu, by name %s, get %lu\n", (unsigned long)[windows count],
               yesno([windows objectWithName:@"Front"] == nil), (unsigned long)[[windows get] count]);
        [me setVolume:3];
        printf("lastError: %s %ld, failures told %d\n", [[[me lastError] domain] UTF8String],
               (long)[[me lastError] code], l->failures);
        SBObject *prop = [me propertyWithCode:'pnam'];
        printf("a property's get: %s\n", [prop get] ? "something" : "nil");
        printf("class for a scripting class: %s\n", yesno([me classForScriptingClass:@"window"] == Nil));

        /* the Touch Bar */
        NSTouchBar *bar = [[[NSTouchBar alloc] init] autorelease];
        bar.delegate = l;
        bar.customizationIdentifier = @"org.example.bar";
        NSCustomTouchBarItem *tmpl = [[[NSCustomTouchBarItem alloc] initWithIdentifier:@"org.example.template"] autorelease];
        bar.templateItems = [NSSet setWithObject:tmpl];
        bar.defaultItemIdentifiers = @[ @"org.example.template", @"org.example.made", NSTouchBarItemIdentifierFlexibleSpace ];
        printf("touch bar: %lu items, visible %s, template item %s, made \"%s\", unknown %s\n",
               (unsigned long)[[bar itemIdentifiers] count], yesno([bar isVisible]),
               yesno([bar itemForIdentifier:@"org.example.template"] == tmpl),
               [[[bar itemForIdentifier:@"org.example.made"] customizationLabel] UTF8String],
               yesno([bar itemForIdentifier:@"org.example.unknown"] == nil));

        /* NSWorkspace's file operations */
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        [[ws notificationCenter] addObserver:l selector:@selector(performed:)
                                        name:NSWorkspaceDidPerformFileOperationNotification object:nil];
        NSString *home = NSHomeDirectory();
        NSString *a = [home stringByAppendingPathComponent:@"a"], *b = [home stringByAppendingPathComponent:@"b"];
        [[NSFileManager defaultManager] createDirectoryAtPath:a withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:b withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"one" writeToFile:[a stringByAppendingPathComponent:@"one.txt"] atomically:NO encoding:NSUTF8StringEncoding
                      error:NULL];
        [@"two" writeToFile:[a stringByAppendingPathComponent:@"two.txt"] atomically:NO encoding:NSUTF8StringEncoding
                      error:NULL];
        NSInteger tag = -1;
        BOOL ok = [ws performFileOperation:NSWorkspaceCopyOperation source:a destination:b
                                     files:@[ @"one.txt", @"two.txt" ] tag:&tag];
        printf("copy: %s tag %ld, in b %s %s, notified %d (operation %ld)\n", yesno(ok), (long)tag,
               yesno(exists([b stringByAppendingPathComponent:@"one.txt"])),
               yesno(exists([b stringByAppendingPathComponent:@"two.txt"])), l->operations, l->lastOperation);
        ok = [ws performFileOperation:NSWorkspaceMoveOperation source:b destination:a files:@[ @"two.txt" ] tag:&tag];
        printf("move onto a file that's there: %s\n", yesno(ok));
        ok = [ws performFileOperation:NSWorkspaceDuplicateOperation source:a destination:@"" files:@[ @"one.txt" ]
                                  tag:&tag];
        printf("duplicate: %s, \"one copy.txt\" %s\n", yesno(ok), yesno(exists([a stringByAppendingPathComponent:@"one copy.txt"])));
        ok = [ws performFileOperation:NSWorkspaceDuplicateOperation source:a destination:@"" files:@[ @"one.txt" ]
                                  tag:&tag];
        printf("again: \"one copy 2.txt\" %s\n", yesno(exists([a stringByAppendingPathComponent:@"one copy 2.txt"])));
        ok = [ws performFileOperation:NSWorkspaceLinkOperation source:a destination:b files:@[ @"two.txt" ] tag:&tag];
        printf("link into b over its copy: %s\n", yesno(ok));
        ok = [ws performFileOperation:NSWorkspaceDestroyOperation source:b destination:@"" files:@[ @"one.txt" ] tag:&tag];
        printf("destroy: %s, gone %s\n", yesno(ok), yesno(!exists([b stringByAppendingPathComponent:@"one.txt"])));
        ok = [ws performFileOperation:NSWorkspaceRecycleOperation source:a destination:@"" files:@[ @"one copy 2.txt" ]
                                  tag:&tag];
        printf("recycle: %s, gone %s\n", yesno(ok), yesno(!exists([a stringByAppendingPathComponent:@"one copy 2.txt"])));
        ok = [ws performFileOperation:NSWorkspaceCompressOperation source:a destination:@"" files:@[ @"one.txt" ] tag:&tag];
        printf("compress: %s, notified %d times\n", yesno(ok), l->operations);
        __block BOOL called = NO;
        __block NSUInteger made = 0;
        [ws duplicateURLs:@[ [NSURL fileURLWithPath:[a stringByAppendingPathComponent:@"two.txt"]] ]
            completionHandler:^(NSDictionary *urls, NSError *error) {
                called = YES;
                made = [urls count];
            }];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!called && [until timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("duplicateURLs: called %s, %lu made, \"two copy.txt\" %s\n", yesno(called), (unsigned long)made,
               yesno(exists([a stringByAppendingPathComponent:@"two copy.txt"])));

        /* the Cocoa error codes */
        printf("errors: locking %ld, too large %ld, out of space %ld, unsupported scheme %ld, unmount %ld\n",
               (long)NSFileLockingError, (long)NSFileReadTooLargeError, (long)NSFileWriteOutOfSpaceError,
               (long)NSFileWriteUnsupportedSchemeError, (long)NSFileManagerUnmountUnknownError);

        /* objc_msgSend with its arguments, as the old prototypes declare it */
        NSString *joined = objc_msgSend(l, @selector(joined:with:), @"left", @"right");
        double half = ((double (*)(id, SEL, double))objc_msgSend)(l, @selector(half:), 5.0);
        printf("objc_msgSend: %s, %.1f, %s\n", [joined UTF8String], half,
               [objc_msgSend(@"abc", @selector(uppercaseString)) UTF8String]);

        [[ws notificationCenter] removeObserver:l];
        [l release];
    }
    return 0;
}
