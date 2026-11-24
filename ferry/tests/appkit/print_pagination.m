/* SPDX-License-Identifier: GPL-3.0-or-later
 * Pagination (freemac 1.NEXT, Ferry 0.NEXT): a view wider and taller than
 * the page, printed with automatic pagination (tiled, row by row from the
 * top), fit pagination (shrunk onto one page), and clip pagination (one
 * page, cut off); a view that isn't flipped; a view that moves each
 * page's bottom edge (adjustPageHeightNew:) so a band isn't cut; a view
 * that knows its own pages (knowsPageRange: and rectForPage:); and a range
 * of pages printed in reverse order. Each page's rect, where it is put on
 * the paper, and the text Poppler reads on it are shown. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

extern NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);

/* A grid of labelled cells, 100 by 100 points: "r1c1", "r1c2"... from the top. */
@interface Grid : NSView
@property BOOL flip, bands;
@property (strong) NSMutableArray *log;
@end
@implementation Grid
- (BOOL)isFlipped { return self.flip; }
- (void)drawRect:(NSRect)dirty
{
    NSDictionary *attrs = @{NSFontAttributeName : [NSFont userFontOfSize:10]};
    NSRect b = [self bounds];
    int rows = (int)(b.size.height / 100), cols = (int)(b.size.width / 100);
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++) {
            CGFloat y = self.flip ? 100 * r + 40 : b.size.height - 100 * r - 60;
            [[NSString stringWithFormat:@"r%dc%d", r + 1, c + 1] drawAtPoint:NSMakePoint(100 * c + 30, y)
                                                              withAttributes:attrs];
        }
}
/* bands 100 points tall, from 30 points down, that a page shouldn't cut */
- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)top bottom:(CGFloat)bottom limit:(CGFloat)limit
{
    if (!self.bands)
        return;
    CGFloat edge = floor((bottom - 30) / 100) * 100 + 30;
    [self.log addObject:[NSString stringWithFormat:@"adjust %g-%g limit %g -> %g", top, bottom, limit, edge]];
    if (edge >= limit)
        *newBottom = edge;
}
- (void)beginPageInRect:(NSRect)rect atPlacement:(NSPoint)location
{
    [self.log addObject:[NSString stringWithFormat:@"page %ld: %g %g %g %g at %g %g",
                                                   (long)[[NSPrintOperation currentOperation] currentPage],
                                                   rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
                                                   location.x, location.y]];
    [super beginPageInRect:rect atPlacement:location];
}
@end

/* Its own pages: two of them, each a 200 by 150 rect, numbered from 5. */
@interface Paged : Grid
@end
@implementation Paged
- (BOOL)knowsPageRange:(NSRangePointer)range
{
    *range = NSMakeRange(5, 2);
    return YES;
}
- (NSRect)rectForPage:(NSInteger)page { return NSMakeRect(0, (page - 5) * 200, 200, 150); }
@end

static NSString *dir;

static void print_view(const char *what, Grid *view, void (^setup)(NSPrintInfo *, NSPrintOperation **))
{
    view.log = [NSMutableArray array];
    NSString *path = [dir stringByAppendingPathComponent:@"out.pdf"];
    NSPrintInfo *info = [[NSPrintInfo alloc] init];
    [info setPaperName:@"na-letter"];
    [info setLeftMargin:56];
    [info setRightMargin:56];
    [info setTopMargin:96];
    [info setBottomMargin:96];
    [info setJobDisposition:NSPrintSaveJob];
    [[info dictionary] setObject:[NSURL fileURLWithPath:path] forKey:NSPrintJobSavingURL];
    NSPrintOperation *op = nil;
    if (setup)
        setup(info, &op);
    op = [NSPrintOperation printOperationWithView:view printInfo:info];
    [op setShowsPrintPanel:NO];
    BOOL ok = [op runOperation];
    NSData *pdf = [NSData dataWithContentsOfFile:path];
    printf("%s: printed %d\n", what, ok);
    for (NSString *line in view.log)
        printf("  %s\n", [line UTF8String]);
    for (NSUInteger i = 0;; i++) {
        NSString *text = FerryPDFPageText(pdf, i);
        if (!text)
            break;
        NSArray *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableArray *kept = [NSMutableArray array];
        for (NSString *p in parts)
            if ([p length])
                [kept addObject:p];
        printf("  sheet %lu: %s\n", (unsigned long)i + 1, [[kept componentsJoinedByString:@" "] UTF8String]);
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

int main(void)
{
    @autoreleasepool {
        unsetenv("LC_ALL");
        setenv("LC_PAPER", "en_US.UTF-8", 1);
        unsetenv("FERRY_PRINT_ANSWER");
        [NSApplication sharedApplication];
        dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-print-pagination"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        /* 700 by 900 points, on a page of 500 by 600 */
        Grid *grid = [[Grid alloc] initWithFrame:NSMakeRect(0, 0, 700, 900)];
        grid.flip = YES;
        print_view("automatic both ways", grid, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [info setHorizontalPagination:NSAutoPagination];
        });
        print_view("automatic down, clipped across (the default)", grid, nil);
        print_view("fit across", grid, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [info setHorizontalPagination:NSFitPagination];
        });
        print_view("fit both ways", grid, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [info setHorizontalPagination:NSFitPagination];
          [info setVerticalPagination:NSFitPagination];
        });
        print_view("clipped both ways", grid, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [info setVerticalPagination:NSClipPagination];
        });
        print_view("scaled to 125%", grid, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [info setScalingFactor:1.25];
        });

        Grid *up = [[Grid alloc] initWithFrame:NSMakeRect(0, 0, 300, 900)];
        print_view("not flipped", up, nil);

        Grid *bands = [[Grid alloc] initWithFrame:NSMakeRect(0, 0, 300, 900)];
        bands.flip = YES;
        bands.bands = YES;
        print_view("pages that end between bands", bands, nil);

        Paged *paged = [[Paged alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
        paged.flip = YES;
        print_view("its own pages", paged, nil);
        print_view("page 6 alone", paged, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [[info dictionary] setObject:@NO forKey:NSPrintAllPages];
          [[info dictionary] setObject:@6 forKey:NSPrintFirstPage];
          [[info dictionary] setObject:@6 forKey:NSPrintLastPage];
        });
        print_view("pages 2 to 3 of 4, in reverse", grid, ^(NSPrintInfo *info, NSPrintOperation **op) {
          [info setHorizontalPagination:NSAutoPagination];
          [[info dictionary] setObject:@NO forKey:NSPrintAllPages];
          [[info dictionary] setObject:@2 forKey:NSPrintFirstPage];
          [[info dictionary] setObject:@3 forKey:NSPrintLastPage];
          [[info dictionary] setObject:@YES forKey:NSPrintReversePageOrder];
        });
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    return 0;
}
