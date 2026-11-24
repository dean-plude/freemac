/* SPDX-License-Identifier: GPL-3.0-or-later
 * A document printed to PDF (freemac 1.NEXT, Ferry 0.NEXT): an NSDocument
 * subclass makes its print operation in printOperationWithSettings:error:,
 * from its own print info, and printDocumentWithSettings: runs it with
 * the settings given (saving to a file) and calls the delegate back.
 * Print… (printDocument:) goes through the print panel, answered from the
 * environment; Page Setup… (runPageLayout:) changes the document's own
 * print info only, after asking shouldChangePrintInfo:; and the print
 * info is kept when the document is archived with it. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

extern NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);

@interface Lines : NSView
@property (copy) NSArray *lines;
@end
@implementation Lines
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty
{
    NSDictionary *attrs = @{NSFontAttributeName : [NSFont userFontOfSize:12]};
    for (NSUInteger i = 0; i < [self.lines count]; i++)
        [self.lines[i] drawAtPoint:NSMakePoint(10, 10 + 300 * i) withAttributes:attrs];
}
@end

@interface Note : NSDocument
@property (copy) NSArray *lines;
@property BOOL refuseLayout;
@property NSDictionary *settingsAsked;
@end
@implementation Note
- (NSString *)displayName { return @"Shopping"; }
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)settings error:(NSError **)error
{
    self.settingsAsked = settings;
    Lines *view = [[Lines alloc] initWithFrame:NSMakeRect(0, 0, 400, 300 * [self.lines count] - 250)];
    view.lines = self.lines;
    NSPrintInfo *info = [self printInfo];
    [[info dictionary] addEntriesFromDictionary:settings];
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:view printInfo:info];
    [op setJobTitle:[self displayName]];
    return op;
}
- (BOOL)shouldChangePrintInfo:(NSPrintInfo *)info { return !self.refuseLayout; }
- (void)document:(NSDocument *)doc didPrint:(BOOL)ok contextInfo:(void *)context
{
    printf("did print: %d, context %s\n", ok, (const char *)context);
}
- (void)document:(NSDocument *)doc didRunPageLayout:(BOOL)accepted contextInfo:(void *)context
{
    printf("did run page layout: accepted %d\n", accepted);
}
@end

static void report(const char *what, NSString *path)
{
    NSData *pdf = [NSData dataWithContentsOfFile:path];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
    CGPDFDocumentRef doc = CGPDFDocumentCreateWithProvider(provider);
    size_t n = doc ? CGPDFDocumentGetNumberOfPages(doc) : 0;
    printf("%s: %zu pages\n", what, n);
    for (size_t i = 1; i <= n; i++) {
        CGRect box = CGPDFPageGetBoxRect(CGPDFDocumentGetPage(doc, i), kCGPDFMediaBox);
        NSString *text = [FerryPDFPageText(pdf, i - 1)
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        printf("  page %zu, %gx%g: %s\n", i, box.size.width, box.size.height,
               [[text stringByReplacingOccurrencesOfString:@"\n" withString:@" / "] UTF8String]);
    }
    CGPDFDocumentRelease(doc);
    CGDataProviderRelease(provider);
}

int main(void)
{
    @autoreleasepool {
        unsetenv("LC_ALL");
        setenv("LC_PAPER", "en_US.UTF-8", 1);
        unsetenv("FERRY_PRINT_ANSWER");
        unsetenv("FERRY_PAGE_LAYOUT_ANSWER");
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-print-document"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        Note *doc = [[Note alloc] init];
        doc.lines = @[ @"Apples", @"Bread", @"Cheese", @"Dates" ];

        /* the settings say where the pages go */
        NSString *path = [dir stringByAppendingPathComponent:@"settings.pdf"];
        NSDictionary *settings = @{
            NSPrintJobDisposition : NSPrintSaveJob,
            NSPrintJobSavingURL : [NSURL fileURLWithPath:path],
        };
        NSError *error = nil;
        NSPrintOperation *op = [doc printOperationWithSettings:settings error:&error];
        printf("operation %d, job title %s, its print info a copy of the document's %d\n", op != nil,
               [[op jobTitle] UTF8String],
               [op printInfo] != [doc printInfo] &&
                   [[[op printInfo] dictionary] objectForKey:NSPrintJobSavingURL] != nil);
        [op setShowsPrintPanel:NO];
        printf("ran %d\n", [op runOperation]);
        report("from printOperationWithSettings:error:", path);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        [doc printDocumentWithSettings:settings showPrintPanel:NO delegate:doc
                      didPrintSelector:@selector(document:didPrint:contextInfo:) contextInfo:"note"];
        printf("settings passed on: %d\n", [doc.settingsAsked isEqual:settings]);
        report("printDocumentWithSettings:", path);

        /* Page Setup changes the document's print info, not the shared one */
        setenv("FERRY_PAGE_LAYOUT_ANSWER", "ok paper=iso-a5 landscape", 1);
        [doc runModalPageLayoutWithPrintInfo:[[doc printInfo] copy] delegate:doc
                              didRunSelector:@selector(document:didRunPageLayout:contextInfo:) contextInfo:NULL];
        NSSize size = [[doc printInfo] paperSize];
        printf("document paper %s %gx%g, shared paper %s\n", [[[doc printInfo] paperName] UTF8String], size.width,
               size.height, [[[NSPrintInfo sharedPrintInfo] paperName] UTF8String]);
        doc.refuseLayout = YES;
        setenv("FERRY_PAGE_LAYOUT_ANSWER", "ok paper=na-legal", 1);
        [doc runPageLayout:nil];
        printf("refused by shouldChangePrintInfo: paper %s\n", [[[doc printInfo] paperName] UTF8String]);
        setenv("FERRY_PAGE_LAYOUT_ANSWER", "cancel paper=na-legal", 1);
        doc.refuseLayout = NO;
        [doc runPageLayout:nil];
        printf("cancelled: paper %s\n", [[[doc printInfo] paperName] UTF8String]);

        /* Print… through the panel, on the new paper */
        NSString *printed = [dir stringByAppendingPathComponent:@"print.pdf"];
        setenv("FERRY_PRINT_ANSWER", [[@"ok file=" stringByAppendingString:printed] UTF8String], 1);
        [doc printDocument:nil];
        report("Print…", printed);
        setenv("FERRY_PRINT_ANSWER", "cancel", 1);
        [[NSFileManager defaultManager] removeItemAtPath:printed error:NULL];
        [doc printDocument:nil];
        printf("cancelled Print…: file %d\n", [[NSFileManager defaultManager] fileExistsAtPath:printed]);

        /* the print info archived, as a document keeps it */
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:[doc printInfo] requiringSecureCoding:NO
                                                                error:NULL];
        NSPrintInfo *back = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
        [doc setPrintInfo:back];
        printf("kept: %s %s\n", [[[doc printInfo] paperName] UTF8String],
               [[doc printInfo] orientation] == NSPaperOrientationLandscape ? "landscape" : "portrait");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    return 0;
}
