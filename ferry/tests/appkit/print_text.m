/* SPDX-License-Identifier: GPL-3.0-or-later
 * A text view printed across pages (freemac 1.210, Ferry 0.36.0): eighty
 * numbered lines in a text view the width of the page, printed on US
 * Letter. Every line comes out once, whole and in order, each page ends
 * on a line's edge (the text view moves the page's bottom up rather than
 * cut a line in two), and the selection isn't printed. Then the same text
 * at a larger size on A5, fitted to the page's width, through the view's
 * print: action with the panel answered, and a rich text with a bold run,
 * whose words all print. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

extern NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);

/* The numbers of the lines ("Line 12 ...") Poppler reads on each page. */
static void report(const char *what, NSString *path, int expected)
{
    NSData *pdf = [NSData dataWithContentsOfFile:path];
    NSMutableArray *all = [NSMutableArray array];
    BOOL whole = YES;
    NSUInteger pages = 0;
    for (NSUInteger i = 0;; i++) {
        NSString *text = FerryPDFPageText(pdf, i);
        if (!text)
            break;
        pages++;
        int first = -1, last = -1;
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (![line hasPrefix:@"Line "])
                continue;
            int n = [[line substringFromIndex:5] intValue];
            if (![line hasSuffix:@"end"])
                whole = NO;
            if (first < 0)
                first = n;
            last = n;
            [all addObject:@(n)];
        }
        printf("  page %lu: lines %d to %d\n", (unsigned long)i + 1, first, last);
    }
    BOOL inOrder = (int)[all count] == expected;
    for (int i = 0; inOrder && i < expected; i++)
        inOrder = [all[i] intValue] == i + 1;
    printf("%s: %lu pages, every line once and in order %d, whole %d\n", what, (unsigned long)pages, inOrder, whole);
}

int main(void)
{
    @autoreleasepool {
        unsetenv("LC_ALL");
        setenv("LC_PAPER", "en_US.UTF-8", 1);
        unsetenv("FERRY_PRINT_ANSWER");
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-print-text"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        NSMutableString *s = [NSMutableString string];
        for (int i = 1; i <= 80; i++)
            [s appendFormat:@"Line %d of the text that runs across pages, to the end\n", i];
        [s deleteCharactersInRange:NSMakeRange([s length] - 1, 1)];
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 468, 100)];
        [tv setString:s];
        [tv setFont:[NSFont userFontOfSize:12]];
        [tv sizeToFit];
        [tv setSelectedRange:NSMakeRange(0, 200)];
        printf("text view %g wide, taller than a page %d\n", [tv frame].size.width, [tv frame].size.height > 612);

        NSString *path = [dir stringByAppendingPathComponent:@"letter.pdf"];
        NSPrintInfo *info = [[NSPrintInfo alloc] init];
        [info setPaperName:@"na-letter"];
        [info setJobDisposition:NSPrintSaveJob];
        [[info dictionary] setObject:[NSURL fileURLWithPath:path] forKey:NSPrintJobSavingURL];
        NSPrintOperation *op = [NSPrintOperation printOperationWithView:tv printInfo:info];
        [op setShowsPrintPanel:NO];
        printf("printed %d\n", [op runOperation]);
        report("letter", path, 80);
        /* with nothing on the page where the selection was drawn, the
         * page's corner is white */
        NSData *pdf = [NSData dataWithContentsOfFile:path];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
        CGPDFDocumentRef doc = CGPDFDocumentCreateWithProvider(provider);
        CGPDFPageRef page = CGPDFDocumentGetPage(doc, 1);
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:612 pixelsHigh:792
                                                                     bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:32];
        NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        CGContextRef cg = [gc CGContext];
        CGContextSetRGBFillColor(cg, 1, 1, 1, 1);
        CGContextFillRect(cg, CGRectMake(0, 0, 612, 792));
        CGContextDrawPDFPage(cg, page);
        CGContextFlush(cg);
        int coloured = 0;
        for (int y = 90; y < 300; y++)
            for (int x = 72; x < 540; x++) {
                NSColor *c = [rep colorAtX:x y:y];
                if (fabs([c redComponent] - [c blueComponent]) > 0.1)
                    coloured++;
            }
        printf("selection printed: %d\n", coloured > 50);
        CGPDFDocumentRelease(doc);
        CGDataProviderRelease(provider);

        /* larger, on A5, through print: and the print panel */
        [tv setFont:[NSFont userFontOfSize:16]];
        [tv sizeToFit];
        NSString *a5 = [dir stringByAppendingPathComponent:@"a5.pdf"];
        NSPrintInfo *shared = [NSPrintInfo sharedPrintInfo];
        [shared setPaperName:@"iso-a5"];
        [shared setLeftMargin:36];
        [shared setRightMargin:36];
        [shared setTopMargin:36];
        [shared setBottomMargin:36];
        [shared setHorizontalPagination:NSFitPagination]; /* as TextEdit does */
        setenv("FERRY_PRINT_ANSWER", [[@"ok file=" stringByAppendingString:a5] UTF8String], 1);
        [tv print:nil];
        report("A5 at 16 points", a5, 80);

        /* a rich text: a bold word and a red one */
        NSTextView *rich = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 50)];
        NSMutableAttributedString *a = [[NSMutableAttributedString alloc]
            initWithString:@"Plain, then bold, then red."
                attributes:@{NSFontAttributeName : [NSFont userFontOfSize:14]}];
        [a addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:14] range:NSMakeRange(12, 4)];
        [a addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(23, 3)];
        [[rich textStorage] setAttributedString:a];
        NSData *data = [rich dataWithPDFInsideRect:[rich bounds]];
        printf("rich text: %s\n", [[FerryPDFPageText(data, 0)
                                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                       UTF8String]);
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    return 0;
}
