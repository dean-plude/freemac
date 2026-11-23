/* SPDX-License-Identifier: GPL-3.0-or-later
 * Drag and drop into a window (M7), with no display: the steps GTK's drop
 * signals take are called directly (they are Ferry's own private methods,
 * declared below), with files or text on the drag pasteboard. Checks which
 * view is the destination (the one under the pointer that registered a
 * type on the pasteboard, or the window for its delegate), the order of
 * the messages, the operation the destination chooses, and the drop. */
#import <Cocoa/Cocoa.h>

@interface NSWindow (FerryDragTesting)
- (NSDragOperation)_dragUpdateAt:(NSPoint)point pasteboard:(NSPasteboard *)pb operations:(NSDragOperation)mask;
- (void)_dragExit;
- (BOOL)_dragDropAt:(NSPoint)point pasteboard:(NSPasteboard *)pb operations:(NSDragOperation)mask;
@end

static NSMutableArray *log_;
static void note(NSString *s) { [log_ addObject:s]; }
static void show(const char *what)
{
    printf("%s: %s\n", what, [[log_ componentsJoinedByString:@", "] UTF8String]);
    [log_ removeAllObjects];
}

@interface DropView : NSView
@property (copy) NSString *name;
@property NSDragOperation answer;
@property (copy) NSArray *dropped;
@end
@implementation DropView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info
{
    note([NSString stringWithFormat:@"%@ entered at %.0f,%.0f", self.name, [info draggingLocation].x,
                                    [info draggingLocation].y]);
    return self.answer;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info
{
    note([NSString stringWithFormat:@"%@ updated", self.name]);
    return self.answer;
}
- (void)draggingExited:(id<NSDraggingInfo>)info { note([NSString stringWithFormat:@"%@ exited", self.name]); }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info
{
    note([NSString stringWithFormat:@"%@ prepare", self.name]);
    return YES;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    NSPasteboard *pb = [info draggingPasteboard];
    self.dropped = [pb readObjectsForClasses:@[ [NSURL class], [NSString class] ]
                                     options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
    note([NSString stringWithFormat:@"%@ perform (%lu)", self.name, (unsigned long)[self.dropped count]]);
    return YES;
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)info { note([NSString stringWithFormat:@"%@ conclude", self.name]); }
@end

/* A view with only draggingEntered: (Mac apps often skip the rest) */
@interface Plain : NSView
@end
@implementation Plain
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { note(@"plain entered"); return NSDragOperationCopy; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    note([NSString stringWithFormat:@"plain perform: %@", [[info draggingPasteboard] stringForType:NSPasteboardTypeString]]);
    return YES;
}
@end

@interface WindowDelegate : NSObject <NSWindowDelegate, NSDraggingDestination>
@end
@implementation WindowDelegate
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { note(@"delegate entered"); return NSDragOperationLink; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { note(@"delegate perform"); return YES; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        log_ = [NSMutableArray array];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        DropView *files = [[DropView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        files.name = @"files";
        files.answer = NSDragOperationCopy;
        [files registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
        DropView *inner = [[DropView alloc] initWithFrame:NSMakeRect(50, 50, 50, 50)];
        inner.name = @"inner"; /* registers nothing: drops go to the view around it */
        [files addSubview:inner];
        Plain *text = [[Plain alloc] initWithFrame:NSMakeRect(200, 0, 200, 200)];
        [text registerForDraggedTypes:@[ NSPasteboardTypeString ]];
        [[w contentView] addSubview:files];
        [[w contentView] addSubview:text];
        printf("registered: %s\n", [[[files registeredDraggedTypes] componentsJoinedByString:@","] UTF8String]);

        NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
        NSDragOperation any = NSDragOperationCopy | NSDragOperationGeneric | NSDragOperationMove | NSDragOperationLink;

        /* files dragged across: over the files view, inside it, out to the text view (file URLs carry
         * their paths as text too, so it takes them), then dropped back on the files view */
        [pb clearContents];
        [pb writeObjects:@[ [NSURL fileURLWithPath:@"/tmp/a.txt"], [NSURL fileURLWithPath:@"/tmp/b.png"] ]];
        NSDragOperation op = [w _dragUpdateAt:NSMakePoint(10, 10) pasteboard:pb operations:any];
        printf("over files: operation %lu\n", (unsigned long)op);
        [w _dragUpdateAt:NSMakePoint(70, 70) pasteboard:pb operations:any];
        op = [w _dragUpdateAt:NSMakePoint(300, 10) pasteboard:pb operations:any];
        printf("over the text view: operation %lu\n", (unsigned long)op);
        BOOL ok = [w _dragDropAt:NSMakePoint(20, 30) pasteboard:pb operations:any];
        show("files");
        printf("dropped: %s;", ok ? "yes" : "no");
        for (NSURL *u in files.dropped)
            printf(" %s", [[u path] UTF8String]);
        printf("\n");

        /* the destination wants Move but the source allows only Copy: no drop */
        files.answer = NSDragOperationMove;
        op = [w _dragUpdateAt:NSMakePoint(10, 10) pasteboard:pb operations:NSDragOperationCopy];
        ok = [w _dragDropAt:NSMakePoint(10, 10) pasteboard:pb operations:NSDragOperationCopy];
        show("move refused");
        printf("operation %lu, dropped: %s\n", (unsigned long)op, ok ? "yes" : "no");
        files.answer = NSDragOperationCopy;

        /* a drag that leaves the window */
        [w _dragUpdateAt:NSMakePoint(10, 10) pasteboard:pb operations:any];
        [w _dragExit];
        show("left");

        /* text, on the view that takes text */
        [pb clearContents];
        [pb writeObjects:@[ @"some words" ]];
        ok = [w _dragDropAt:NSMakePoint(250, 100) pasteboard:pb operations:any];
        show("text");
        printf("dropped: %s\n", ok ? "yes" : "no");
        printf("text over the files view: operation %lu\n",
               (unsigned long)[w _dragUpdateAt:NSMakePoint(10, 10) pasteboard:pb operations:any]);
        [w _dragExit];

        /* the window registered: its delegate gets drops nobody else takes */
        WindowDelegate *wd = [[WindowDelegate alloc] init];
        w.delegate = wd;
        [w registerForDraggedTypes:@[ NSPasteboardTypeString ]];
        [text unregisterDraggedTypes];
        ok = [w _dragDropAt:NSMakePoint(250, 100) pasteboard:pb operations:any];
        show("window");
        printf("dropped: %s\n", ok ? "yes" : "no");
    }
    return 0;
}
