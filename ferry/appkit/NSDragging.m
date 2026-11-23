/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: drag and drop into Ferry's windows (M7), written from
 * Apple's public NSDraggingDestination and NSDraggingInfo documentation.
 * GTK tells the window where a drag from another app is and, once asked,
 * what it carries (files, as a URI list, or text). That goes on the drag
 * pasteboard, and the view under the pointer that registered one of its
 * types (or the window, for its delegate) is sent draggingEntered:,
 * draggingUpdated:, draggingExited:, and on a drop prepareForDragOperation:,
 * performDragOperation: and concludeDragOperation:. Dragging out of a Ferry
 * window is not done yet. Built without ARC. */
#import "AInternal.h"
#include <dispatch/dispatch.h>

/* ---- what the destination is told ------------------------------------------------------ */

@interface AFDraggingInfo : NSObject <NSDraggingInfo> {
@public
    NSWindow *_window;
    NSPoint _location;
    NSPasteboard *_pasteboard;
    NSDragOperation _mask;
    NSInteger _sequence;
    NSDraggingFormation _formation;
    BOOL _animates;
    NSInteger _validItems;
}
@end

@implementation AFDraggingInfo
- (void)dealloc
{
    [_window release];
    [_pasteboard release];
    [super dealloc];
}
- (NSWindow *)draggingDestinationWindow { return _window; }
- (NSDragOperation)draggingSourceOperationMask { return _mask; }
- (NSPoint)draggingLocation { return _location; }
- (NSPoint)draggedImageLocation { return _location; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id)draggingSource { return nil; } /* always from another app */
- (NSInteger)draggingSequenceNumber { return _sequence; }
- (NSDraggingFormation)draggingFormation { return _formation; }
- (void)setDraggingFormation:(NSDraggingFormation)f { _formation = f; }
- (BOOL)animatesToDestination { return _animates; }
- (void)setAnimatesToDestination:(BOOL)f { _animates = f; }
- (NSInteger)numberOfValidItemsForDrop { return _validItems; }
- (void)setNumberOfValidItemsForDrop:(NSInteger)n { _validItems = n; }
- (void)slideDraggedImageTo:(NSPoint)point {}
- (void)enumerateDraggingItemsWithOptions:(NSUInteger)options forView:(NSView *)view classes:(NSArray *)classes
                            searchOptions:(NSDictionary *)search usingBlock:(void (^)(id, NSInteger, BOOL *))block
{
    NSArray *objects = [_pasteboard readObjectsForClasses:classes options:search];
    BOOL stop = NO;
    for (NSInteger i = 0; i < (NSInteger)[objects count] && !stop; i++)
        block([objects objectAtIndex:i], i, &stop);
}
@end

/* The one drag in progress: Ferry's windows take one at a time. */
static AFDraggingInfo *current;
static id target;                  /* the destination now under the pointer, retained */
static NSDragOperation entered_op; /* what it said in draggingEntered: */
static NSInteger sequence;

static BOOL types_match(NSArray *wanted, NSArray *have)
{
    for (NSString *t in wanted)
        if ([have containsObject:t])
            return YES;
    return NO;
}

@implementation NSWindow (FerryDragging)

/* The view under the point that takes one of the pasteboard's types, or the
 * window itself (for its delegate) if it registered one. */
- (id)_dragTargetAt:(NSPoint)point types:(NSArray *)types
{
    for (NSView *v = [[self contentView] hitTest:point]; v; v = [v superview])
        if (types_match([v registeredDraggedTypes], types))
            return v;
    if (types_match([self _registeredDraggedTypes], types))
        return self;
    return nil;
}

/* The window passes the messages on to its delegate. */
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info
{
    id d = [self delegate];
    return [d respondsToSelector:_cmd] ? [d draggingEntered:info] : NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info
{
    id d = [self delegate];
    return [d respondsToSelector:_cmd] ? [d draggingUpdated:info] : entered_op;
}
- (void)draggingExited:(id<NSDraggingInfo>)info
{
    id d = [self delegate];
    if ([d respondsToSelector:_cmd])
        [d draggingExited:info];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info
{
    id d = [self delegate];
    return [d respondsToSelector:_cmd] ? [d prepareForDragOperation:info] : YES;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    id d = [self delegate];
    return [d respondsToSelector:_cmd] ? [d performDragOperation:info] : NO;
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)info
{
    id d = [self delegate];
    if ([d respondsToSelector:_cmd])
        [d concludeDragOperation:info];
}

static void leave_target(void)
{
    if (target && [target respondsToSelector:@selector(draggingExited:)])
        [target draggingExited:current];
    [target release];
    target = nil;
    entered_op = NSDragOperationNone;
}

static void end_drag(void)
{
    [current release];
    current = nil;
}

- (NSDragOperation)_dragUpdateAt:(NSPoint)point pasteboard:(NSPasteboard *)pb operations:(NSDragOperation)mask
{
    if (current && current->_window != self) {
        leave_target();
        end_drag();
    }
    if (!current) {
        current = [[AFDraggingInfo alloc] init];
        current->_window = [self retain];
        current->_pasteboard = [pb retain];
        current->_sequence = ++sequence;
        current->_animates = YES;
    }
    current->_location = point;
    current->_mask = mask;
    id now = [self _dragTargetAt:point types:[pb types]];
    if (now != target) {
        leave_target();
        target = [now retain];
        if ([target respondsToSelector:@selector(draggingEntered:)])
            entered_op = [target draggingEntered:current];
        else
            entered_op = NSDragOperationNone;
        return entered_op & mask;
    }
    if (!target)
        return NSDragOperationNone;
    NSDragOperation op = [target respondsToSelector:@selector(draggingUpdated:)] ? [target draggingUpdated:current]
                                                                                  : entered_op;
    return op & mask;
}

- (void)_dragExit
{
    leave_target();
    end_drag();
}

- (BOOL)_dragDropAt:(NSPoint)point pasteboard:(NSPasteboard *)pb operations:(NSDragOperation)mask
{
    NSDragOperation op = [self _dragUpdateAt:point pasteboard:pb operations:mask];
    BOOL done = NO;
    if (op == NSDragOperationNone || !target) {
        leave_target();
    } else {
        id t = [[target retain] autorelease];
        [target release];
        target = nil;
        BOOL ready = [t respondsToSelector:@selector(prepareForDragOperation:)] ? [t prepareForDragOperation:current]
                                                                                : YES;
        if (ready && [t respondsToSelector:@selector(performDragOperation:)])
            done = [t performDragOperation:current];
        if (done && [t respondsToSelector:@selector(concludeDragOperation:)])
            [t concludeDragOperation:current];
        if ([t respondsToSelector:@selector(draggingEnded:)])
            [t draggingEnded:current];
    }
    end_drag();
    return done;
}
@end

/* ---- GTK's side ------------------------------------------------------------------------ */

static NSWindow *gtk_window;       /* the window GTK's current drag is over, retained */
static GdkDragContext *gtk_context;
static BOOL have_data, asked_for_data, drop_waiting, left;
static NSPoint gtk_point;
static uint32_t drop_time;

static NSDragOperation mask_from_gdk(int actions)
{
    NSDragOperation m = 0;
    if (actions & (GDK_ACTION_COPY | GDK_ACTION_DEFAULT))
        m |= NSDragOperationCopy | NSDragOperationGeneric;
    if (actions & GDK_ACTION_MOVE)
        m |= NSDragOperationMove;
    if (actions & GDK_ACTION_LINK)
        m |= NSDragOperationLink;
    return m;
}

static int gdk_from_op(NSDragOperation op, int allowed)
{
    if ((op & (NSDragOperationCopy | NSDragOperationGeneric)) && (allowed & GDK_ACTION_COPY))
        return GDK_ACTION_COPY;
    if ((op & NSDragOperationMove) && (allowed & GDK_ACTION_MOVE))
        return GDK_ACTION_MOVE;
    if ((op & NSDragOperationLink) && (allowed & GDK_ACTION_LINK))
        return GDK_ACTION_LINK;
    if ((op & NSDragOperationGeneric) && (allowed & GDK_ACTION_MOVE))
        return GDK_ACTION_MOVE;
    return 0;
}

static NSPoint drop_point(NSWindow *w, int x, int y) { return NSMakePoint(x, [w _contentSize].height - y); }

static void forget_gtk_drag(void)
{
    [gtk_window release];
    gtk_window = nil;
    gtk_context = NULL;
    have_data = asked_for_data = drop_waiting = left = NO;
}

static void start_gtk_drag(NSWindow *w, GdkDragContext *ctx)
{
    if (gtk_context == ctx && gtk_window == w)
        return;
    if (gtk_window)
        [gtk_window _dragExit];
    forget_gtk_drag();
    gtk_window = [w retain];
    gtk_context = ctx;
}

static NSPasteboard *drag_pasteboard(void) { return [NSPasteboard pasteboardWithName:NSPasteboardNameDrag]; }

static void finish_drop(GtkWidget *widget, GdkDragContext *ctx, uint32_t time)
{
    BOOL ok = [gtk_window _dragDropAt:gtk_point pasteboard:drag_pasteboard()
                           operations:mask_from_gdk(gdk_drag_context_get_actions(ctx))];
    gtk_drag_finish(ctx, ok, 0, time);
    forget_gtk_drag();
}

static int on_drag_motion(GtkWidget *widget, GdkDragContext *ctx, int x, int y, uint32_t time, void *data)
{
    @autoreleasepool {
        NSWindow *w = data;
        start_gtk_drag(w, ctx);
        left = NO;
        gtk_point = drop_point(w, x, y);
        if (!have_data) {
            if (!asked_for_data) {
                GdkAtom what = gtk_drag_dest_find_target(widget, ctx, NULL);
                if (!what) {
                    gdk_drag_status(ctx, 0, time);
                    return 0;
                }
                asked_for_data = YES;
                gtk_drag_get_data(widget, ctx, what, time);
            }
            gdk_drag_status(ctx, 0, time);
            return 1;
        }
        int allowed = gdk_drag_context_get_actions(ctx);
        NSDragOperation op = [w _dragUpdateAt:gtk_point pasteboard:drag_pasteboard() operations:mask_from_gdk(allowed)];
        gdk_drag_status(ctx, gdk_from_op(op, allowed), time);
        return 1;
    }
}

static void on_drag_data(GtkWidget *widget, GdkDragContext *ctx, int x, int y, GtkSelectionData *sel,
                         unsigned info, uint32_t time, void *data)
{
    @autoreleasepool {
        NSWindow *w = data;
        start_gtk_drag(w, ctx);
        NSPasteboard *pb = drag_pasteboard();
        [pb clearContents];
        NSMutableArray *objects = [NSMutableArray array];
        char **uris = gtk_selection_data_get_uris(sel);
        for (char **u = uris; u && *u; u++) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:*u]];
            if (url)
                [objects addObject:url];
        }
        if (uris)
            g_strfreev(uris);
        if (![objects count]) {
            unsigned char *text = gtk_selection_data_get_text(sel);
            if (text) {
                [objects addObject:[NSString stringWithUTF8String:(char *)text]];
                g_free(text);
            }
        }
        [pb writeObjects:objects];
        have_data = YES;
        if (drop_waiting) {
            finish_drop(widget, ctx, drop_time);
            return;
        }
        int allowed = gdk_drag_context_get_actions(ctx);
        NSDragOperation op = [w _dragUpdateAt:gtk_point pasteboard:pb operations:mask_from_gdk(allowed)];
        gdk_drag_status(ctx, gdk_from_op(op, allowed), time);
    }
}

/* GTK says the drag left just before it says it dropped, so leaving is
 * only acted on once the event loop turns without a drop. */
static void on_drag_leave(GtkWidget *widget, GdkDragContext *ctx, uint32_t time, void *data)
{
    if (ctx != gtk_context)
        return;
    left = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (left && gtk_context == ctx) {
            [gtk_window _dragExit];
            forget_gtk_drag();
        }
    });
}

static int on_drag_drop(GtkWidget *widget, GdkDragContext *ctx, int x, int y, uint32_t time, void *data)
{
    @autoreleasepool {
        NSWindow *w = data;
        start_gtk_drag(w, ctx);
        left = NO;
        gtk_point = drop_point(w, x, y);
        if (have_data) {
            finish_drop(widget, ctx, time);
        } else {
            drop_waiting = YES;
            drop_time = time;
            if (!asked_for_data) {
                GdkAtom what = gtk_drag_dest_find_target(widget, ctx, NULL);
                if (!what) {
                    gtk_drag_finish(ctx, 0, 0, time);
                    forget_gtk_drag();
                    return 1;
                }
                asked_for_data = YES;
                gtk_drag_get_data(widget, ctx, what, time);
            }
        }
        return 1;
    }
}

void ADragAttach(NSWindow *window, GtkWidget *area)
{
    static GtkTargetEntry targets[] = {
        {"text/uri-list", 0, 1},
        {"UTF8_STRING", 0, 2},
        {"text/plain;charset=utf-8", 0, 2},
        {"text/plain", 0, 2},
    };
    gtk_drag_dest_set(area, 0, targets, 4, GDK_ACTION_COPY | GDK_ACTION_MOVE | GDK_ACTION_LINK);
    g_signal_connect_data(area, "drag-motion", (GCallback)on_drag_motion, window, NULL, 0);
    g_signal_connect_data(area, "drag-leave", (GCallback)on_drag_leave, window, NULL, 0);
    g_signal_connect_data(area, "drag-drop", (GCallback)on_drag_drop, window, NULL, 0);
    g_signal_connect_data(area, "drag-data-received", (GCallback)on_drag_data, window, NULL, 0);
}
