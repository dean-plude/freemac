/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: drag and drop into Ferry's windows (M7), written from
 * Apple's public NSDraggingDestination and NSDraggingInfo documentation.
 * GTK tells the window where a drag from another app is and, once asked,
 * what it carries (files, as a URI list, or text). That goes on the drag
 * pasteboard, and the view under the pointer that registered one of its
 * types (or the window, for its delegate) is sent draggingEntered:,
 * draggingUpdated:, draggingExited:, and on a drop prepareForDragOperation:,
 * performDragOperation: and concludeDragOperation:.
 *
 * Drags within the app (freemac 1.220, Ferry 0.44.0): a dragging session
 * (beginDraggingSessionWithItems:event:source:, the older
 * dragImage:at:offset:event:pasteboard:source:slideBack:, and the rows of a
 * table or outline view) puts its items on the drag pasteboard and then
 * follows the mouse: the window hands the session each drag and the button
 * going up (ADragSessionTakes), the session finds the app's window under
 * the pointer and goes through the same steps as a drag from another app,
 * with the source as draggingSource, and the source hears where it began,
 * moved and ended, and with what operation. Option asks to copy, Control to
 * link, Command for the generic operation, unless the source ignores the
 * modifier keys. Dragging out of the app's windows into other apps, and a
 * picture following the pointer, are not done yet. Built without ARC. */
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
    id _source;     /* a drag from within the app: its source, retained */
}
@end

@implementation AFDraggingInfo
- (void)dealloc
{
    [_window release];
    [_pasteboard release];
    [_source release];
    [super dealloc];
}
- (NSWindow *)draggingDestinationWindow { return _window; }
- (NSDragOperation)draggingSourceOperationMask { return _mask; }
- (NSPoint)draggingLocation { return _location; }
- (NSPoint)draggedImageLocation { return _location; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id)draggingSource { return _source; } /* nil from another app */
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
static id local_source;            /* the source of a drag from within the app, while it moves */
static NSDragOperation last_op;    /* what the destination last said, within the mask */

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
        current->_source = [local_source retain];
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
    last_op = op;
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

/* ---- drags within the app ------------------------------------------------------------- */

@implementation NSDraggingItem {
    id _item;
    NSRect _frame;
    id _contents;
    NSArray *(^_provider)(void);
}
- (instancetype)initWithPasteboardWriter:(id<NSPasteboardWriting>)writer
{
    if ((self = [super init]))
        _item = [writer retain];
    return self;
}
- (void)dealloc
{
    [_item release];
    [_contents release];
    [_provider release];
    [super dealloc];
}
- (id)item { return _item; }
- (NSRect)draggingFrame { return _frame; }
- (void)setDraggingFrame:(NSRect)f { _frame = f; }
- (void)setDraggingFrame:(NSRect)f contents:(id)contents
{
    _frame = f;
    [contents retain];
    [_contents release];
    _contents = contents;
}
- (NSArray *(^)(void))imageComponentsProvider { return _provider; }
- (void)setImageComponentsProvider:(NSArray *(^)(void))p
{
    p = [p copy];
    [_provider release];
    _provider = p;
}
- (NSArray *)imageComponents { return _provider ? _provider() : @[]; }
@end

@implementation NSDraggingSession {
@public
    NSPasteboard *_pasteboard;
    NSArray *_items;
    id _source;               /* retained while the drag lasts */
    BOOL _old;                /* an older source (draggedImage:...) */
    NSImage *_image;
    NSInteger _sequence;
    NSPoint _location;        /* on the screen */
    NSDraggingFormation _formation;
    BOOL _animates;
    NSInteger _leader;
    NSWindow *_over;          /* the window under the pointer, retained */
    NSDragOperation _op;
}
- (void)dealloc
{
    [_pasteboard release];
    [_items release];
    [_source release];
    [_image release];
    [_over release];
    [super dealloc];
}
- (NSDraggingFormation)draggingFormation { return _formation; }
- (void)setDraggingFormation:(NSDraggingFormation)f { _formation = f; }
- (BOOL)animatesToStartingPositionsOnCancelOrFail { return _animates; }
- (void)setAnimatesToStartingPositionsOnCancelOrFail:(BOOL)f { _animates = f; }
- (NSInteger)draggingLeaderIndex { return _leader; }
- (void)setDraggingLeaderIndex:(NSInteger)i { _leader = i; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (NSInteger)draggingSequenceNumber { return _sequence; }
- (NSPoint)draggingLocation { return _location; }
- (void)enumerateDraggingItemsWithOptions:(NSUInteger)options forView:(NSView *)view classes:(NSArray *)classes
                            searchOptions:(NSDictionary *)search
                               usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))block
{
    BOOL stop = NO;
    for (NSInteger i = 0; i < (NSInteger)[_items count] && !stop; i++)
        block([_items objectAtIndex:i], i, &stop);
}
@end

static NSDraggingSession *session; /* the drag within the app now under way */

/* What the source allows, narrowed by the modifier keys held. */
static NSDragOperation session_mask(NSDraggingSession *s, NSEventModifierFlags flags)
{
    id src = s->_source;
    NSDragOperation mask;
    BOOL ignore;
    if (s->_old) {
        mask = [src respondsToSelector:@selector(draggingSourceOperationMaskForLocal:)]
                   ? [src draggingSourceOperationMaskForLocal:YES]
                   : NSDragOperationEvery;
        ignore = [src respondsToSelector:@selector(ignoreModifierKeysWhileDragging)] &&
                 [src ignoreModifierKeysWhileDragging];
    } else {
        mask = [src draggingSession:s sourceOperationMaskForDraggingContext:NSDraggingContextWithinApplication];
        ignore = [src respondsToSelector:@selector(ignoreModifierKeysForDraggingSession:)] &&
                 [src ignoreModifierKeysForDraggingSession:s];
    }
    if (!ignore) {
        NSDragOperation want = 0;
        if (flags & NSEventModifierFlagOption)
            want = NSDragOperationCopy;
        else if (flags & NSEventModifierFlagControl)
            want = NSDragOperationLink;
        else if (flags & NSEventModifierFlagCommand)
            want = NSDragOperationGeneric;
        if (want)
            mask &= want;
    }
    return mask;
}

/* The app's window at a point on the screen: the one the drag is from
 * first, then the key window, then any other on screen. */
static NSWindow *window_at(NSPoint screen, NSWindow *from)
{
    NSMutableArray *order = [NSMutableArray array];
    if (from)
        [order addObject:from];
    NSWindow *key = AKeyWindow();
    if (key && key != from)
        [order addObject:key];
    for (NSWindow *w in AAllWindows())
        if (w != from && w != key)
            [order addObject:w];
    for (NSWindow *w in order)
        if ([w isVisible] && ![w isMiniaturized] && NSPointInRect(screen, [w frame]))
            return w;
    return nil;
}

/* The one operation a drop did, of those the destination said. */
static NSDragOperation one_operation(NSDragOperation op)
{
    static const NSDragOperation order[] = {NSDragOperationCopy, NSDragOperationMove, NSDragOperationLink,
                                            NSDragOperationGeneric, NSDragOperationPrivate, NSDragOperationDelete};
    for (unsigned i = 0; i < sizeof order / sizeof *order; i++)
        if (op & order[i])
            return order[i];
    return NSDragOperationNone;
}

static NSPoint screen_point(NSEvent *e)
{
    NSWindow *w = [e window];
    NSPoint p = [e locationInWindow];
    return w ? [w convertPointToScreen:p] : p;
}

/* Moves the drag to where the event is; YES at the button going up, with
 * the drop done. */
static void session_move(NSDraggingSession *s, NSEvent *e, BOOL drop)
{
    NSPoint screen = screen_point(e);
    s->_location = screen;
    NSWindow *w = window_at(screen, [e window]);
    NSDragOperation mask = session_mask(s, [e modifierFlags]);
    if (w != s->_over) {
        [s->_over _dragExit];
        [w retain];
        [s->_over release];
        s->_over = w;
    }
    if (!w) {
        s->_op = NSDragOperationNone;
        return;
    }
    NSPoint at = NSMakePoint(screen.x - [w frame].origin.x, screen.y - [w frame].origin.y);
    local_source = s->_source;
    if (drop) {
        BOOL done = [w _dragDropAt:at pasteboard:s->_pasteboard operations:mask];
        s->_op = done ? one_operation(last_op) : NSDragOperationNone;
        [s->_over release];
        s->_over = nil;
    } else {
        s->_op = [w _dragUpdateAt:at pasteboard:s->_pasteboard operations:mask];
    }
    local_source = nil;
}

static void session_end(NSDraggingSession *s, NSEvent *e)
{
    session = nil;
    A_REPORTING(session_move(s, e, YES);)
    id src = s->_source;
    if (s->_old) {
        if ([src respondsToSelector:@selector(draggedImage:endedAt:operation:)])
            [src draggedImage:s->_image endedAt:s->_location operation:s->_op];
    } else if ([src respondsToSelector:@selector(draggingSession:endedAtPoint:operation:)]) {
        [src draggingSession:s endedAtPoint:s->_location operation:s->_op];
    }
    [s release];
}

BOOL ADragSessionTakes(NSEvent *e)
{
    if (!session)
        return NO;
    NSEventType t = [e type];
    if (t == NSEventTypeLeftMouseUp) {
        session_end(session, e);
        return YES;
    }
    if (t != NSEventTypeLeftMouseDragged)
        return NO;
    NSDraggingSession *s = [[session retain] autorelease];
    A_REPORTING(session_move(s, e, NO);)
    id src = s->_source;
    if (s->_old) {
        if ([src respondsToSelector:@selector(draggedImage:movedTo:)])
            [src draggedImage:s->_image movedTo:s->_location];
    } else if ([src respondsToSelector:@selector(draggingSession:movedToPoint:)]) {
        [src draggingSession:s movedToPoint:s->_location];
    }
    return YES;
}

static NSDraggingSession *start_session(NSPasteboard *pb, NSArray *items, id source, BOOL old, NSImage *image,
                                        NSEvent *e)
{
    if (session) {
        /* one drag at a time: the one before ends where it is */
        session_end(session, e);
    }
    NSDraggingSession *s = [[NSDraggingSession alloc] init];
    s->_pasteboard = [pb retain];
    s->_items = [items copy];
    s->_source = [source retain];
    s->_old = old;
    s->_image = [image retain];
    s->_sequence = ++sequence;
    s->_animates = YES;
    s->_location = screen_point(e);
    session = s;   /* released as it ends */
    if (old) {
        if ([source respondsToSelector:@selector(draggedImage:beganAt:)])
            [source draggedImage:image beganAt:s->_location];
    } else if ([source respondsToSelector:@selector(draggingSession:willBeginAtPoint:)]) {
        [source draggingSession:s willBeginAtPoint:s->_location];
    }
    if (session == s && ([e type] == NSEventTypeLeftMouseDragged || [e type] == NSEventTypeLeftMouseDown))
        A_REPORTING(session_move(s, e, NO);)
    return s;
}

NSDraggingSession *ABeginDragSession(NSPasteboard *pb, NSArray *items, id<NSDraggingSource> source, NSEvent *e)
{
    return start_session(pb, items, source, NO, nil, e);
}

@implementation NSView (NSDraggingSource)
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray *)items event:(NSEvent *)event source:(id)source
{
    NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
    [pb clearContents];
    NSMutableArray *writers = [NSMutableArray array];
    for (NSDraggingItem *item in items)
        if ([item item])
            [writers addObject:[item item]];
    [pb writeObjects:writers];
    return start_session(pb, items, source, NO, nil, event);
}
- (void)dragImage:(NSImage *)image at:(NSPoint)location offset:(NSSize)offset event:(NSEvent *)event
       pasteboard:(NSPasteboard *)pasteboard source:(id)source slideBack:(BOOL)slideBack
{
    start_session(pasteboard ?: [NSPasteboard pasteboardWithName:NSPasteboardNameDrag], @[], source, YES, image,
                  event);
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
    BOOL ok = NO;
    A_REPORTING(ok = [gtk_window _dragDropAt:gtk_point pasteboard:drag_pasteboard()
                                  operations:mask_from_gdk(gdk_drag_context_get_actions(ctx))];)
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
        NSDragOperation op = NSDragOperationNone;
        A_REPORTING(op = [w _dragUpdateAt:gtk_point pasteboard:drag_pasteboard() operations:mask_from_gdk(allowed)];)
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
        NSDragOperation op = NSDragOperationNone;
        A_REPORTING(op = [w _dragUpdateAt:gtk_point pasteboard:pb operations:mask_from_gdk(allowed)];)
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
            A_REPORTING([gtk_window _dragExit];)
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
