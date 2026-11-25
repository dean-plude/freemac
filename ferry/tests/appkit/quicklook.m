/* SPDX-License-Identifier: GPL-3.0-or-later
 * Quick Look (freemac 1.222, Ferry 0.46.0): the shared preview panel
 * finding its controller in the main window's responder chain and telling
 * it when it's done, as MacPass's and Sequel Pro's controllers expect;
 * its data source's items, each shown as the file's icon, name and size
 * over a picture, the start of a text file, or a larger icon; the arrow
 * keys moving between them, the delegate having the keys first, and
 * Escape putting the panel away; a preview view of one's own; thumbnails;
 * the generator keys; and QCView, which can't run a composition. Run with
 * no display, in a home of its own. */
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

static NSString *dir;

static void describe(NSView *view, int depth)
{
    for (NSView *v in [view subviews]) {
        printf("%*s%s", depth * 2, "", [NSStringFromClass([v class]) UTF8String]);
        if ([v isKindOfClass:[NSTextField class]])
            printf(" \"%s\"", [[(NSTextField *)v stringValue] UTF8String]);
        else if ([v isKindOfClass:[NSImageView class]]) {
            NSImage *image = [(NSImageView *)v image];
            printf(" %s, %gx%g", image ? "an image" : "no image", NSWidth([v frame]), NSHeight([v frame]));
            if (image && NSWidth([v frame]) > 100)
                printf(", picture %gx%g", [image size].width, [image size].height);
        } else if ([v isKindOfClass:[NSScrollView class]]) {
            NSTextView *tv = [(NSScrollView *)v documentView];
            NSString *s = [[tv string] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
            printf(" text \"%s\", editable %d", [s UTF8String], [tv isEditable]);
            printf("\n");
            continue;
        }
        printf("\n");
        describe(v, depth + 1);
    }
}

@interface Controller : NSView <QLPreviewPanelDataSource, QLPreviewPanelDelegate>
@property NSArray *items;
@property BOOL swallowNextKey;
@end
@implementation Controller
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel
{
    printf("asked to control\n");
    return YES;
}
- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel
{
    printf("begins: controller is me %d\n", [panel currentController] == self);
    panel.dataSource = self;
    panel.delegate = self;
}
- (void)endPreviewPanelControl:(QLPreviewPanel *)panel
{
    printf("ends\n");
    panel.dataSource = nil;
    panel.delegate = nil;
}
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel { return [self.items count]; }
- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index
{
    return self.items[index];
}
- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event
{
    if (!self.swallowNextKey)
        return NO;
    self.swallowNextKey = NO;
    printf("the delegate had the key\n");
    return YES;
}
@end

/* an item with a title of its own */
@interface Titled : NSObject <QLPreviewItem>
@end
@implementation Titled
- (NSURL *)previewItemURL { return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"notes.txt"]]; }
- (NSString *)previewItemTitle { return @"My notes"; }
@end

static void key(QLPreviewPanel *panel, unichar ch)
{
    NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                              windowNumber:[panel windowNumber] context:nil
                                characters:[NSString stringWithCharacters:&ch length:1]
               charactersIgnoringModifiers:[NSString stringWithCharacters:&ch length:1] isARepeat:NO keyCode:0];
    [panel sendEvent:e];
}

static void show(QLPreviewPanel *panel)
{
    printf("item %ld, title \"%s\"\n", (long)[panel currentPreviewItemIndex], [[panel title] UTF8String]);
    describe([panel contentView], 1);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ql"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"folder"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"first line\nsecond line\n" writeToFile:[dir stringByAppendingPathComponent:@"notes.txt"] atomically:NO
                                         encoding:NSUTF8StringEncoding error:NULL];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:80 pixelsHigh:40
                                                                  bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSDeviceRGBColorSpace
                                                                    bytesPerRow:0 bitsPerPixel:0];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:[dir stringByAppendingPathComponent:@"picture.png"] atomically:NO];
        const char bytes[] = {1, 0, 2, 0, 3};
        [[NSData dataWithBytes:bytes length:sizeof bytes] writeToFile:[dir stringByAppendingPathComponent:@"data.bin"]
                                                           atomically:NO];

        printf("no panel yet: %d\n", [QLPreviewPanel sharedPreviewPanelExists]);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                       styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                           defer:NO];
        Controller *c = [[Controller alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        c.items = @[
            [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"notes.txt"]],
            [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"picture.png"]],
            [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"data.bin"]],
            [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"folder"]],
            [Titled new],
        ];
        [window setContentView:c];
        [window makeKeyAndOrderFront:nil];
        [window makeFirstResponder:c];

        QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
        printf("the same panel each time: %d, now there's one: %d, a panel %d, floating %d\n",
               panel == [QLPreviewPanel sharedPreviewPanel], [QLPreviewPanel sharedPreviewPanelExists],
               [panel isKindOfClass:[NSPanel class]], [panel isFloatingPanel]);
        printf("no controller while hidden: %d\n", [panel currentController] == nil);
        [panel makeKeyAndOrderFront:nil];
        printf("visible %d, controller %d\n", [panel isVisible], [panel currentController] == c);
        show(panel);
        key(panel, NSRightArrowFunctionKey);
        show(panel);
        key(panel, NSRightArrowFunctionKey);
        show(panel);
        [panel setCurrentPreviewItemIndex:3];
        show(panel);
        [panel setCurrentPreviewItemIndex:99];
        show(panel);
        key(panel, NSRightArrowFunctionKey);
        printf("past the end: item %ld\n", (long)[panel currentPreviewItemIndex]);
        [panel setCurrentPreviewItemIndex:0];
        key(panel, NSLeftArrowFunctionKey);
        printf("before the start: item %ld\n", (long)[panel currentPreviewItemIndex]);

        /* fewer items: the index stays inside */
        c.items = @[ c.items[0], c.items[1] ];
        [panel setCurrentPreviewItemIndex:1];
        c.items = @[ c.items[0] ];
        [panel reloadData];
        printf("after reloading one item: item %ld, %s\n", (long)[panel currentPreviewItemIndex],
               [[[(NSURL *)[panel currentPreviewItem] path] lastPathComponent] UTF8String]);

        c.swallowNextKey = YES;
        key(panel, 0x1b);
        printf("still visible after the delegate's key: %d\n", [panel isVisible]);
        key(panel, 0x1b);
        printf("Escape put it away: visible %d, controller %d, data source %d\n", [panel isVisible],
               [panel currentController] != nil, panel.dataSource != nil);
        [panel makeKeyAndOrderFront:nil];
        printf("shown again: controller %d\n", [panel currentController] == c);
        [panel close];
        printf("closed: visible %d, still the shared one %d\n", [panel isVisible],
               [QLPreviewPanel sharedPreviewPanel] == panel);

        /* full screen and back */
        NSRect before = [panel frame];
        [panel enterFullScreenMode:nil withOptions:nil];
        printf("full screen %d, ", [panel isInFullScreenMode]);
        [panel exitFullScreenModeWithOptions:nil];
        printf("then not %d, frame back %d\n", ![panel isInFullScreenMode], NSEqualRects(before, [panel frame]));

        /* a view of one's own */
        QLPreviewView *view = [[QLPreviewView alloc] initWithFrame:NSMakeRect(0, 0, 200, 150)
                                                             style:QLPreviewViewStyleCompact];
        view.previewItem = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"notes.txt"]];
        printf("a compact view:\n");
        describe(view, 1);
        printf("closes with its window %d, URL's item is itself %d\n", view.shouldCloseWithWindow,
               [[NSURL fileURLWithPath:dir] previewItemURL] != nil);

        /* thumbnails */
        CGImageRef t = QLThumbnailImageCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:[dir
                                                    stringByAppendingPathComponent:@"picture.png"]],
                                              CGSizeMake(40, 40), NULL);
        printf("thumbnail of the picture: %zux%zu\n", CGImageGetWidth(t), CGImageGetHeight(t));
        CGImageRelease(t);
        t = QLThumbnailImageCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:[dir
                                         stringByAppendingPathComponent:@"picture.png"]],
                                   CGSizeMake(400, 400), NULL);
        printf("never larger: %zux%zu\n", CGImageGetWidth(t), CGImageGetHeight(t));
        CGImageRelease(t);
        t = QLThumbnailImageCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:[dir
                                         stringByAppendingPathComponent:@"notes.txt"]],
                                   CGSizeMake(64, 64), (__bridge CFDictionaryRef) @{
                                       (__bridge NSString *)kQLThumbnailOptionIconModeKey : @YES
                                   });
        printf("an icon: %zux%zu\n", t ? CGImageGetWidth(t) : 0, t ? CGImageGetHeight(t) : 0);
        CGImageRelease(t);
        printf("text without icon mode: %s, a missing file: %s\n",
               QLThumbnailImageCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:[dir
                                            stringByAppendingPathComponent:@"notes.txt"]],
                                      CGSizeMake(64, 64), NULL)
                   ? "an image"
                   : "none",
               QLThumbnailImageCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:@"/no/such/file"],
                                      CGSizeMake(64, 64), NULL)
                   ? "an image"
                   : "none");
        printf("generator keys: %d, no request cancelled: %d\n",
               [(__bridge NSString *)kQLPreviewPropertyMIMETypeKey length] > 0 &&
                   [(__bridge NSString *)kQLPreviewPropertyAttachmentsKey length] > 0,
               !QLPreviewRequestIsCancelled(NULL));

        /* Quartz Composer */
        QCView *qc = [[QCView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        printf("a composition loads: %d, renders: %d, rendering %d, a snapshot %gx%g\n",
               [qc loadCompositionFromFile:@"/no/such.qtz"], [qc startRendering], [qc isRendering],
               [[qc snapshotImage] size].width, [[qc snapshotImage] size].height);
    }
    return 0;
}
