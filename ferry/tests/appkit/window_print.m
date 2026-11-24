/* SPDX-License-Identifier: GPL-3.0-or-later
 * Printing on a display (freemac 1.210, Ferry 0.36.0): the print panel
 * and the page layout are GTK's print and page setup dialogs, shown as
 * sheets on the window. FERRY_PRINT_ANSWER and FERRY_PAGE_LAYOUT_ANSWER
 * make each dialog answer itself after a moment, so the test can go
 * through them: Page Setup keeps the paper the print info had, and the
 * print dialog prints to the file the answer names (GTK's Print to File),
 * after which the PDF's pages are counted. The font panel (GTK's font
 * chooser) is shown and closed. Needs a display; run.sh starts a headless
 * Weston for it. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

extern NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);

@interface Tall : NSView
@end
@implementation Tall
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty
{
    [[NSColor whiteColor] setFill];
    NSRectFill(dirty);
    NSDictionary *attrs = @{NSFontAttributeName : [NSFont userFontOfSize:12]};
    for (int i = 0; i < 3; i++)
        [[NSString stringWithFormat:@"Part %d", i + 1] drawAtPoint:NSMakePoint(10, 20 + 700 * i) withAttributes:attrs];
}
@end

@interface Done : NSObject
@property BOOL printed, laidOut, ok;
@end
@implementation Done
- (void)printOperationDidRun:(NSPrintOperation *)op success:(BOOL)success contextInfo:(void *)context
{
    self.printed = YES;
    self.ok = success;
}
- (void)pageLayoutDidEnd:(NSPageLayout *)layout returnCode:(int)code contextInfo:(void *)context
{
    self.laidOut = YES;
    self.ok = code == NSModalResponseOK;
}
@end

static void wait_for(BOOL (^done)(void))
{
    for (int i = 0; i < 300 && !done(); i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

int main(void)
{
    @autoreleasepool {
        unsetenv("LC_ALL");
        setenv("LC_PAPER", "en_US.UTF-8", 1);
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                      defer:NO];
        [w setTitle:@"Printing"];
        [w setReleasedWhenClosed:NO];
        Tall *view = [[Tall alloc] initWithFrame:NSMakeRect(0, 0, 300, 1800)];
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [sv setDocumentView:view];
        [w setContentView:sv];
        [w makeKeyAndOrderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

        /* Page Setup, as a sheet: OK keeps the paper */
        setenv("FERRY_PAGE_LAYOUT_ANSWER", "ok", 1);
        NSPrintInfo *info = [[NSPrintInfo alloc] init];
        [info setPaperName:@"iso-a5"];
        Done *done = [Done new];
        [[NSPageLayout pageLayout] beginSheetWithPrintInfo:info modalForWindow:w delegate:done
                                            didEndSelector:@selector(pageLayoutDidEnd:returnCode:contextInfo:)
                                               contextInfo:NULL];
        printf("page layout: ended at once %d\n", done.laidOut);
        wait_for(^{ return done.laidOut; });
        NSSize size = [info paperSize];
        printf("page layout: ended %d, OK %d, paper %s %gx%g\n", done.laidOut, done.ok,
               [[info paperName] UTF8String], size.width, size.height);

        /* the print dialog, as a sheet, printing to a file */
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-window-print.pdf"];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        setenv("FERRY_PRINT_ANSWER", [[@"ok file=" stringByAppendingString:path] UTF8String], 1);
        NSPrintInfo *letter = [[NSPrintInfo alloc] init];
        [letter setPaperName:@"na-letter"];
        NSPrintOperation *op = [NSPrintOperation printOperationWithView:view printInfo:letter];
        done = [Done new];
        [op runOperationModalForWindow:w delegate:done didRunSelector:@selector(printOperationDidRun:success:contextInfo:)
                           contextInfo:NULL];
        wait_for(^{ return done.printed; });
        NSData *pdf = [NSData dataWithContentsOfFile:path];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
        CGPDFDocumentRef doc = pdf ? CGPDFDocumentCreateWithProvider(provider) : NULL;
        printf("print dialog: ran %d, success %d, %zu pages, disposition %s\n", done.printed, done.ok,
               doc ? CGPDFDocumentGetNumberOfPages(doc) : 0, [[[op printInfo] jobDisposition] UTF8String]);
        for (size_t i = 0; doc && i < CGPDFDocumentGetNumberOfPages(doc); i++)
            printf("  page %zu: %s\n", i + 1,
                   [[FerryPDFPageText(pdf, i) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                       UTF8String]);
        CGPDFDocumentRelease(doc);
        CGDataProviderRelease(provider);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        /* cancelled in the dialog */
        setenv("FERRY_PRINT_ANSWER", "cancel", 1);
        op = [NSPrintOperation printOperationWithView:view printInfo:letter];
        printf("cancelled in the dialog: %d\n", [op runOperation]);

        /* the font panel opens and closes */
        NSFontPanel *panel = [[NSFontManager sharedFontManager] fontPanel:YES];
        [[NSFontManager sharedFontManager] orderFrontFontPanel:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        printf("font panel visible %d\n", [panel isVisible]);
        [panel close];
        printf("font panel visible after closing %d\n", [panel isVisible]);
        [w close];
    }
    return 0;
}
