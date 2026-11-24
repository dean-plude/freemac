/* SPDX-License-Identifier: GPL-3.0-or-later
 * A view's drawing as PDF and EPS data (freemac 1.210, Ferry 0.36.0):
 * dataWithPDFInsideRect: makes one page the size of the rect, holding the
 * view's drawing inside the rect (and none outside it) and its subviews';
 * PDFOperationWithView:insideRect:toData: and toPath: never show the
 * print panel, even when one is asked for; writePDFInsideRect:toPasteboard:
 * puts the PDF on a pasteboard; a window's dataWithPDFInsideRect: draws
 * its content view; and dataWithEPSInsideRect: is Encapsulated
 * PostScript. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

extern NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);

@interface Words : NSView
@end
@implementation Words
- (void)drawRect:(NSRect)dirty
{
    NSDictionary *attrs = @{NSFontAttributeName : [NSFont userFontOfSize:14]};
    [@"Lower" drawAtPoint:NSMakePoint(20, 20) withAttributes:attrs];
    [@"Upper" drawAtPoint:NSMakePoint(20, 150) withAttributes:attrs];
    [@"Right" drawAtPoint:NSMakePoint(250, 20) withAttributes:attrs];
}
@end

static NSString *trimmed(NSString *s)
{
    NSArray *parts = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *p in parts)
        if ([p length])
            [kept addObject:p];
    return [kept componentsJoinedByString:@" "];
}

static void describe(const char *what, NSData *pdf)
{
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
    CGPDFDocumentRef doc = CGPDFDocumentCreateWithProvider(provider);
    size_t n = doc ? CGPDFDocumentGetNumberOfPages(doc) : 0;
    CGRect box = n ? CGPDFPageGetBoxRect(CGPDFDocumentGetPage(doc, 1), kCGPDFMediaBox) : CGRectZero;
    printf("%s: PDF %d, %zu page, %gx%g: %s\n", what, [pdf length] > 4 && !memcmp([pdf bytes], "%PDF", 4), n,
           box.size.width, box.size.height, [trimmed(FerryPDFPageText(pdf, 0)) UTF8String]);
    CGPDFDocumentRelease(doc);
    CGDataProviderRelease(provider);
}

int main(void)
{
    @autoreleasepool {
        unsetenv("FERRY_PRINT_ANSWER");
        [NSApplication sharedApplication];
        Words *view = [[Words alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
        NSTextField *label = [NSTextField labelWithString:@"Subview"];
        [label setFrame:NSMakeRect(250, 150, 120, 24)];
        [view addSubview:label];

        describe("whole view", [view dataWithPDFInsideRect:[view bounds]]);
        describe("lower left", [view dataWithPDFInsideRect:NSMakeRect(0, 0, 200, 100)]);
        describe("upper half", [view dataWithPDFInsideRect:NSMakeRect(0, 100, 400, 100)]);

        /* a PDF operation shows no panel, even when asked to */
        NSMutableData *data = [NSMutableData data];
        NSPrintOperation *op = [NSPrintOperation PDFOperationWithView:view insideRect:NSMakeRect(200, 0, 200, 200)
                                                               toData:data];
        printf("PDF operation: copying %d, shows the panel %d\n", [op isCopyingOperation], [op showsPrintPanel]);
        [op setShowsPrintPanel:YES];
        setenv("FERRY_PRINT_ANSWER", "cancel", 1);
        printf("ran %d\n", [op runOperation]);
        describe("right half", data);
        unsetenv("FERRY_PRINT_ANSWER");

        /* to a file, on pages of a print info */
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-pdfdata.pdf"];
        NSPrintInfo *info = [[NSPrintInfo alloc] init];
        [info setPaperName:@"iso-a5"];
        op = [NSPrintOperation PDFOperationWithView:view insideRect:[view bounds] toPath:path printInfo:info];
        printf("to a file: %d\n", [op runOperation]);
        describe("on A5", [NSData dataWithContentsOfFile:path]);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        /* on a pasteboard */
        NSPasteboard *pb = [NSPasteboard pasteboardWithUniqueName];
        [view writePDFInsideRect:NSMakeRect(0, 0, 200, 100) toPasteboard:pb];
        printf("pasteboard types: %s\n", [[[pb types] componentsJoinedByString:@" "] UTF8String]);
        describe("from the pasteboard", [pb dataForType:NSPasteboardTypePDF]);
        [pb releaseGlobally];

        /* a window's content */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                      defer:YES];
        [w setReleasedWhenClosed:NO];
        [w setContentView:view];
        describe("window", [w dataWithPDFInsideRect:NSMakeRect(0, 0, 400, 200)]);

        /* EPS */
        NSData *eps = [view dataWithEPSInsideRect:NSMakeRect(0, 0, 200, 100)];
        NSString *head = [[NSString alloc] initWithData:[eps subdataWithRange:NSMakeRange(0, 23)]
                                               encoding:NSASCIIStringEncoding];
        NSString *all = [[NSString alloc] initWithData:eps encoding:NSISOLatin1StringEncoding];
        NSRange bbox = [all rangeOfString:@"%%BoundingBox: "];
        double x0 = -1, y0 = -1, x1 = -1, y1 = -1;
        if (bbox.location != NSNotFound)
            sscanf([[all substringFromIndex:NSMaxRange(bbox)] UTF8String], "%lf %lf %lf %lf", &x0, &y0, &x1, &y1);
        printf("EPS: %s, the drawing's bounding box inside the rect %d\n", [head UTF8String],
               x0 >= 0 && y0 >= 0 && x1 > x0 && y1 > y0 && x1 <= 200 && y1 <= 100);
    }
    return 0;
}
