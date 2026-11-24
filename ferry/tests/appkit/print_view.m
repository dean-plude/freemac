/* SPDX-License-Identifier: GPL-3.0-or-later
 * A view printed to a PDF file (freemac 1.210, Ferry 0.36.0): a tall
 * view is laid out on several pages of the print info's paper, each page
 * drawn by the view's own drawRect: (not to the screen, with the print
 * operation current), and the file read back with Poppler: the number of
 * pages, their size, and the text on each. Then the same view on A4 in
 * landscape, half size, with a header and footer, a print operation run
 * for a window (after the call returns), and a print job that is
 * cancelled. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

extern NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);

@interface Blocks : NSView
@property int drawn;
@property BOOL toScreen, hadOperation;
@end
@implementation Blocks
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty
{
    self.drawn++;
    self.toScreen = [NSGraphicsContext currentContextDrawingToScreen];
    self.hadOperation = [NSPrintOperation currentOperation] != nil;
    NSDictionary *attrs = @{NSFontAttributeName : [NSFont userFontOfSize:12]};
    for (int i = 0; i < 10; i++) {
        [[NSColor colorWithCalibratedWhite:0.9 alpha:1] setFill];
        NSRectFill(NSMakeRect(10, 30 + 150 * i, 200, 30));
        [[NSString stringWithFormat:@"Block %d", i + 1] drawAtPoint:NSMakePoint(20, 40 + 150 * i)
                                                      withAttributes:attrs];
    }
}
- (NSString *)printJobTitle { return @"Blocks"; }
@end

@interface Ran : NSObject
@property BOOL called, success;
@end
@implementation Ran
- (void)printOperationDidRun:(NSPrintOperation *)op success:(BOOL)success contextInfo:(void *)context
{
    self.called = YES;
    self.success = success;
}
@end

static NSString *words(NSString *s)
{
    NSArray *parts = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *p in parts)
        if ([p length])
            [kept addObject:p];
    return [kept componentsJoinedByString:@" "];
}

static void report(const char *what, NSString *path)
{
    NSData *pdf = [NSData dataWithContentsOfFile:path];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
    CGPDFDocumentRef doc = CGPDFDocumentCreateWithProvider(provider);
    size_t n = doc ? CGPDFDocumentGetNumberOfPages(doc) : 0;
    printf("%s: %zu pages\n", what, n);
    for (size_t i = 1; i <= n; i++) {
        CGRect box = CGPDFPageGetBoxRect(CGPDFDocumentGetPage(doc, i), kCGPDFMediaBox);
        printf("  page %zu, %gx%g: %s\n", i, box.size.width, box.size.height,
               [words(FerryPDFPageText(pdf, i - 1)) UTF8String]);
    }
    CGPDFDocumentRelease(doc);
    CGDataProviderRelease(provider);
}

static NSPrintInfo *saving_to(NSString *path)
{
    NSPrintInfo *info = [[NSPrintInfo sharedPrintInfo] copy];
    [info setJobDisposition:NSPrintSaveJob];
    [[info dictionary] setObject:[NSURL fileURLWithPath:path] forKey:NSPrintJobSavingURL];
    return info;
}

int main(void)
{
    @autoreleasepool {
        unsetenv("LC_ALL");
        setenv("LC_PAPER", "en_US.UTF-8", 1);
        unsetenv("FERRY_PRINT_ANSWER");
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-print-view"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        Blocks *view = [[Blocks alloc] initWithFrame:NSMakeRect(0, 0, 300, 1500)];

        /* US Letter, margins 72 and 90: 612 points of the view a page */
        NSString *letter = [dir stringByAppendingPathComponent:@"letter.pdf"];
        NSPrintOperation *op = [NSPrintOperation printOperationWithView:view printInfo:saving_to(letter)];
        [op setShowsPrintPanel:NO];
        [op setShowsProgressPanel:NO];
        printf("shows the panel %d, copying %d, job title %s\n", [op showsPrintPanel], [op isCopyingOperation],
               [[op jobTitle] UTF8String]);
        BOOL ok = [op runOperation];
        printf("printed %d, pages %lu-%lu, drawn %d times, to the screen %d, operation current %d, current after %d\n",
               ok, (unsigned long)[op pageRange].location, (unsigned long)NSMaxRange([op pageRange]) - 1, view.drawn,
               view.toScreen, view.hadOperation, [NSPrintOperation currentOperation] != nil);
        report("letter", letter);

        /* A4 across, at half size, with the header and footer */
        NSString *a4 = [dir stringByAppendingPathComponent:@"a4.pdf"];
        NSPrintInfo *info = saving_to(a4);
        [info setPaperName:@"iso-a4"];
        [info setOrientation:NSPaperOrientationLandscape];
        [info setScalingFactor:0.5];
        [[info dictionary] setObject:@YES forKey:NSPrintHeaderAndFooter];
        op = [NSPrintOperation printOperationWithView:view printInfo:info];
        [op setShowsPrintPanel:NO];
        [op setJobTitle:@"Half"];
        ok = [op runOperation];
        printf("printed %d\n", ok);
        NSData *pdf = [NSData dataWithContentsOfFile:a4];
        NSString *first = FerryPDFPageText(pdf, 0);
        printf("header %d, footer %d\n", [first containsString:@"Half"], [first containsString:@"Page 1 of 2"]);
        [[info dictionary] setObject:@NO forKey:NSPrintHeaderAndFooter];
        op = [NSPrintOperation printOperationWithView:view printInfo:info];
        [op setShowsPrintPanel:NO];
        [op runOperation];
        report("A4 landscape, half size", a4);

        /* run for a window: after the call returns, then the delegate */
        NSString *later = [dir stringByAppendingPathComponent:@"later.pdf"];
        op = [NSPrintOperation printOperationWithView:view printInfo:saving_to(later)];
        [op setShowsPrintPanel:NO];
        Ran *ran = [Ran new];
        [op runOperationModalForWindow:nil delegate:ran didRunSelector:@selector(printOperationDidRun:success:contextInfo:)
                           contextInfo:NULL];
        printf("run for a window: called at once %d\n", ran.called);
        for (int i = 0; i < 50 && !ran.called; i++)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("then called %d, success %d, file %d\n", ran.called, ran.success,
               [[NSFileManager defaultManager] fileExistsAtPath:later]);

        /* the print panel, answered: pages 2 to 3, to a file of its own */
        NSString *answered = [dir stringByAppendingPathComponent:@"answered.pdf"];
        setenv("FERRY_PRINT_ANSWER", [[@"print pages=2-3 file=" stringByAppendingString:answered] UTF8String], 1);
        op = [NSPrintOperation printOperationWithView:view];
        printf("through the panel: %d\n", [op runOperation]);
        report("pages 2 to 3", answered);
        setenv("FERRY_PRINT_ANSWER", "cancel", 1);
        op = [NSPrintOperation printOperationWithView:view];
        printf("cancelled in the panel: %d\n", [op runOperation]);
        info = saving_to([dir stringByAppendingPathComponent:@"never.pdf"]);
        [info setJobDisposition:NSPrintCancelJob];
        op = [NSPrintOperation printOperationWithView:view printInfo:info];
        [op setShowsPrintPanel:NO];
        printf("a cancelled job: %d, file %d\n", [op runOperation],
               [[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"never.pdf"]]);
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    return 0;
}
