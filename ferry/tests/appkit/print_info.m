/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSPrintInfo (freemac 1.210, Ferry 0.36.0): the shared print info's
 * defaults (the paper this system's locale uses, the margins, scaling,
 * pagination and centring), the paper sizes and names, orientation
 * turning the paper, the dictionary behind the properties, a copy that
 * doesn't share changes, archiving with NSCoding, the print panel and
 * page layout answering from the environment with no display, and the
 * printing calls a document now answers to. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

static void show(const char *what, NSPrintInfo *p)
{
    NSSize s = [p paperSize];
    printf("%s: %s (%s) %gx%g, %s, margins %g %g %g %g, scale %g, pagination %ld %ld, centred %d %d\n", what,
           [[p paperName] UTF8String], [[p localizedPaperName] UTF8String], s.width, s.height,
           [p orientation] == NSPaperOrientationLandscape ? "landscape" : "portrait", [p leftMargin], [p rightMargin],
           [p topMargin], [p bottomMargin], [p scalingFactor], (long)[p horizontalPagination],
           (long)[p verticalPagination], [p isHorizontallyCentered], [p isVerticallyCentered]);
}

int main(void)
{
    @autoreleasepool {
        unsetenv("LC_ALL");
        setenv("LC_PAPER", "en_US.UTF-8", 1);
        [NSApplication sharedApplication];
        NSPrintInfo *shared = [NSPrintInfo sharedPrintInfo];
        show("shared", shared);
        printf("same shared one: %d\n", shared == [NSPrintInfo sharedPrintInfo]);
        printf("disposition %s, copies %ld, all pages %d, header and footer %d\n",
               [[shared jobDisposition] UTF8String],
               (long)[[[shared dictionary] objectForKey:NSPrintCopies] integerValue],
               [[[shared dictionary] objectForKey:NSPrintAllPages] boolValue],
               [[[shared dictionary] objectForKey:NSPrintHeaderAndFooter] boolValue]);
        NSRect b = [shared imageablePageBounds];
        printf("imageable %g %g %g %g\n", b.origin.x, b.origin.y, b.size.width, b.size.height);

        /* a print info of its own, from the locale of the moment */
        setenv("LC_PAPER", "de_DE.UTF-8", 1);
        NSPrintInfo *info = [[NSPrintInfo alloc] init];
        show("German locale", info);
        NSSize a5 = [NSPrintInfo sizeForPaperName:@"iso-a5"];
        printf("A5 is %gx%g; an unknown paper is %gx%g\n", a5.width, a5.height,
               [NSPrintInfo sizeForPaperName:@"no-such-paper"].width,
               [NSPrintInfo sizeForPaperName:@"no-such-paper"].height);

        [info setPaperName:@"na-legal"];
        show("legal", info);
        [info setOrientation:NSPaperOrientationLandscape];
        show("landscape", info);
        [info setPaperSize:NSMakeSize(842, 595)];
        show("A4 by size", info);
        [info setPaperSize:NSMakeSize(300, 400)];
        printf("a size of no paper: name %s, %s\n", [info paperName] ? [[info paperName] UTF8String] : "(none)",
               [[info localizedPaperName] UTF8String]);
        [info setPaperName:@"iso-a4"];
        [info setOrientation:NSPaperOrientationPortrait];
        [info setLeftMargin:36];
        [info setTopMargin:18];
        [info setScalingFactor:0.5];
        [info setHorizontalPagination:NSFitPagination];
        [info setVerticallyCentered:NO];
        [info setJobDisposition:NSPrintSaveJob];
        [[info dictionary] setObject:[NSURL fileURLWithPath:@"/tmp/out.pdf"] forKey:NSPrintJobSavingURL];
        [[info dictionary] setObject:@3 forKey:NSPrintCopies];
        show("changed", info);
        printf("dictionary: margin %g, scale %g, pagination %ld\n",
               [[[info dictionary] objectForKey:NSPrintLeftMargin] doubleValue],
               [[[info dictionary] objectForKey:NSPrintScalingFactor] doubleValue],
               (long)[[[info dictionary] objectForKey:NSPrintHorizontalPagination] integerValue]);
        [[info dictionary] setObject:@54 forKey:NSPrintRightMargin];
        printf("set through the dictionary: right margin %g\n", [info rightMargin]);

        /* a copy is its own */
        NSPrintInfo *copy = [info copy];
        [copy setLeftMargin:1];
        printf("copy: left %g, original left %g\n", [copy leftMargin], [info leftMargin]);

        /* archived and back */
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:info requiringSecureCoding:NO error:NULL];
        NSPrintInfo *back = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSPrintInfo class] fromData:archive
                                                                 error:NULL];
        if (!back)
            back = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
        printf("archived: %d bytes\n", [archive length] > 100);
        show("unarchived", back);
        printf("unarchived: %s, copies %ld, saved to %s\n", [[back jobDisposition] UTF8String],
               (long)[[[back dictionary] objectForKey:NSPrintCopies] integerValue],
               [[[[back dictionary] objectForKey:NSPrintJobSavingURL] path] UTF8String]);

        /* the panels with no display: Cancel, or as the environment says */
        unsetenv("FERRY_PRINT_ANSWER");
        NSPrintInfo *asked = [[NSPrintInfo alloc] init];
        printf("print panel, no answer: %ld\n", (long)[[NSPrintPanel printPanel] runModalWithPrintInfo:asked]);
        setenv("FERRY_PRINT_ANSWER", "ok copies=2 pages=2-3 landscape", 1);
        printf("print panel, answered: %ld\n", (long)[[NSPrintPanel printPanel] runModalWithPrintInfo:asked]);
        printf("  copies %ld, all pages %d, pages %ld-%ld, %s\n",
               (long)[[[asked dictionary] objectForKey:NSPrintCopies] integerValue],
               [[[asked dictionary] objectForKey:NSPrintAllPages] boolValue],
               (long)[[[asked dictionary] objectForKey:NSPrintFirstPage] integerValue],
               (long)[[[asked dictionary] objectForKey:NSPrintLastPage] integerValue],
               [asked orientation] == NSPaperOrientationLandscape ? "landscape" : "portrait");
        setenv("FERRY_PRINT_ANSWER", "cancel", 1);
        printf("print panel, cancelled: %ld\n", (long)[[NSPrintPanel printPanel] runModalWithPrintInfo:asked]);
        setenv("FERRY_PAGE_LAYOUT_ANSWER", "ok paper=iso-a5 margins=10,20,30,40 scale=80", 1);
        NSPageLayout *layout = [NSPageLayout pageLayout];
        printf("page layout: %ld\n", (long)[layout runModalWithPrintInfo:asked]);
        show("  laid out", asked);
        printf("  the layout's print info is the one given: %d\n", [layout printInfo] == asked);

        /* a document prints and sets up pages */
        NSDocument *doc = [[NSDocument alloc] init];
        NSMenuItem *print = [[NSMenuItem alloc] initWithTitle:@"Print…" action:@selector(printDocument:)
                                                keyEquivalent:@"p"];
        NSMenuItem *setup = [[NSMenuItem alloc] initWithTitle:@"Page Setup…" action:@selector(runPageLayout:)
                                                keyEquivalent:@"P"];
        printf("document menu: Print… %d, Page Setup… %d\n", [doc validateMenuItem:print], [doc validateMenuItem:setup]);
        printf("document's print info is its own: %d, %s\n", [doc printInfo] != [NSPrintInfo sharedPrintInfo],
               [[[doc printInfo] paperName] UTF8String]);
        setenv("FERRY_PAGE_LAYOUT_ANSWER", "ok paper=iso-a3 landscape", 1);
        [doc runPageLayout:nil];
        show("document after Page Setup", [doc printInfo]);
        NSError *error = nil;
        printf("NSDocument itself: operation %d, error %ld\n", [doc printOperationWithSettings:@{} error:&error] != nil,
               (long)[error code]);
    }
    return 0;
}
