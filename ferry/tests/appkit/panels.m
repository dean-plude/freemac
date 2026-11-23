/* SPDX-License-Identifier: GPL-3.0-or-later
 * Open and Save panels (M7), with no display: a panel answers Cancel, or
 * with the paths in FERRY_PANEL_ANSWER, so what the panel does with an
 * answer can be checked: which files an Open panel may choose (by type,
 * file or folder, one or several, and what its delegate allows), the
 * extension a Save panel adds, the directory it remembers, and completion
 * handlers called after the begin call returns. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>
#include <unistd.h>

@interface Picky : NSObject <NSOpenSavePanelDelegate>
@end
@implementation Picky
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url { return ![[url lastPathComponent] hasPrefix:@"secret"]; }
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)error
{
    return ![[url lastPathComponent] hasPrefix:@"refused"];
}
@end

static const char *result(NSModalResponse r) { return r == NSModalResponseOK ? "OK" : "Cancel"; }

static void paths(NSArray *urls)
{
    for (NSURL *u in urls)
        printf(" %s", [[[u path] lastPathComponent] UTF8String]);
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-panels"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:dir error:NULL];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"folder"] withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        for (NSString *name in @[ @"a.txt", @"b.png", @"c.TXT", @"secret.txt" ])
            [@"x" writeToFile:[dir stringByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding
                        error:NULL];
        NSString *(^at)(NSArray *) = ^(NSArray *names) {
            NSMutableArray *full = [NSMutableArray array];
            for (NSString *n in names)
                [full addObject:[dir stringByAppendingPathComponent:n]];
            return [full componentsJoinedByString:@"\n"];
        };

        /* no answer: Cancel */
        unsetenv("FERRY_PANEL_ANSWER");
        NSOpenPanel *open = [NSOpenPanel openPanel];
        printf("defaults: files %d, folders %d, several %d\n", open.canChooseFiles, open.canChooseDirectories,
               open.allowsMultipleSelection);
        printf("no answer: %s, %lu URLs\n", result([open runModal]), (unsigned long)[[open URLs] count]);

        /* one file, then several */
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"a.txt", @"b.png" ]) UTF8String], 1);
        printf("one file: %s,", result([open runModal]));
        paths([open URLs]);
        open.allowsMultipleSelection = YES;
        printf("several: %s,", result([open runModal]));
        paths([open URLs]);
        printf("directory remembered: %s\n", [[[open directoryURL] path] isEqualToString:dir] ? "yes" : "no");

        /* by type: an extension and a type identifier, either case */
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"a.txt", @"b.png", @"c.TXT" ]) UTF8String], 1);
        open.allowedFileTypes = @[ @"public.plain-text" ];
        printf("plain text only: %s,", result([open runModal]));
        paths([open URLs]);
        open.allowedFileTypes = @[ @"png" ];
        printf("png only: %s,", result([open runModal]));
        paths([open URLs]);
        open.allowedFileTypes = nil;

        /* folders */
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"folder" ]) UTF8String], 1);
        printf("a folder when choosing files: %s\n", result([open runModal]));
        open.canChooseDirectories = YES;
        open.canChooseFiles = NO;
        printf("a folder when choosing folders: %s,", result([open runModal]));
        paths([open URLs]);
        open.canChooseFiles = YES;
        open.canChooseDirectories = NO;

        /* a file that isn't there, and the delegate */
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"missing.txt" ]) UTF8String], 1);
        printf("a missing file: %s\n", result([open runModal]));
        Picky *picky = [[Picky alloc] init];
        open.delegate = picky;
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"secret.txt", @"a.txt" ]) UTF8String], 1);
        printf("with the delegate: %s,", result([open runModal]));
        paths([open URLs]);
        printf("filenames:");
        for (NSString *p in [open filenames])
            printf(" %s", [[p lastPathComponent] UTF8String]);
        printf("\n");

        /* saving */
        NSSavePanel *save = [NSSavePanel savePanel];
        save.allowedFileTypes = @[ @"txt" ];
        save.nameFieldStringValue = @"Untitled";
        printf("save defaults: create folders %d, name %s\n", save.canCreateDirectories,
               [save.nameFieldStringValue UTF8String]);
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"notes" ]) UTF8String], 1);
        printf("save as notes: %s, %s, name now %s\n", result([save runModal]), [[[save URL] lastPathComponent] UTF8String],
               [save.nameFieldStringValue UTF8String]);
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"notes.TXT" ]) UTF8String], 1);
        printf("save as notes.TXT: %s, ", result([save runModal]));
        printf("%s\n", [[[save URL] lastPathComponent] UTF8String]);
        save.delegate = picky;
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"refused.txt" ]) UTF8String], 1);
        printf("refused by the delegate: %s\n", result([save runModal]));

        /* completion handlers run after the begin call returns */
        setenv("FERRY_PANEL_ANSWER", [at(@[ @"b.png" ]) UTF8String], 1);
        NSOpenPanel *later = [NSOpenPanel openPanel];
        __block BOOL done = NO;
        [later beginWithCompletionHandler:^(NSModalResponse r) {
            printf("handler: %s,", result(r));
            paths([later URLs]);
            done = YES;
        }];
        printf("begin returned; handler ran yet: %s\n", done ? "yes" : "no");
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [[NSSavePanel savePanel] beginSheetModalForWindow:w completionHandler:^(NSModalResponse r) {
            printf("sheet handler: %s\n", result(r));
        }];
        while (!done)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        [fm removeItemAtPath:dir error:NULL];
    }
    return 0;
}
