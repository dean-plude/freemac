/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSCursor, written from Apple's public documentation.
 * The standard cursors are GTK's named cursors (the CSS cursor names),
 * one shared object each; a cursor made from an image is drawn into a
 * Cairo surface the first time it is shown. Setting a cursor makes it the
 * current one and shows it on every window that has a display; push and
 * pop keep a stack of them, and hiding shows GTK's blank cursor until the
 * cursor is shown again (or, after setHiddenUntilMouseMoves:, until the
 * mouse next moves). With no display, cursors are only kept. Built without
 * ARC. */
#import "AInternal.h"

@implementation NSCursor {
    NSImage *_image;
    NSPoint _hotSpot;
    const char *_name;          /* a standard cursor's name, or NULL */
    GdkCursor *_gdk;
    BOOL _onEntered, _onExited;
}

static NSCursor *current;
static NSMutableArray *stack;
static int hidden;
static BOOL hidden_until_moved;

static NSCursor *standard(NSCursor **slot, const char *name)
{
    if (!*slot) {
        NSCursor *c = [[NSCursor alloc] init];
        c->_name = name;
        c->_hotSpot = NSMakePoint(0, 0);
        *slot = c;
    }
    return *slot;
}
#define STANDARD(sel, name)                                                                                     \
    +(NSCursor *)sel                                                                                            \
    {                                                                                                           \
        static NSCursor *c;                                                                                     \
        return standard(&c, name);                                                                              \
    }
STANDARD(arrowCursor, "default")
STANDARD(IBeamCursor, "text")
STANDARD(IBeamCursorForVerticalLayout, "vertical-text")
STANDARD(pointingHandCursor, "pointer")
STANDARD(closedHandCursor, "grabbing")
STANDARD(openHandCursor, "grab")
STANDARD(resizeLeftCursor, "w-resize")
STANDARD(resizeRightCursor, "e-resize")
STANDARD(resizeLeftRightCursor, "col-resize")
STANDARD(resizeUpCursor, "n-resize")
STANDARD(resizeDownCursor, "s-resize")
STANDARD(resizeUpDownCursor, "row-resize")
STANDARD(crosshairCursor, "crosshair")
STANDARD(disappearingItemCursor, "default")
STANDARD(operationNotAllowedCursor, "not-allowed")
STANDARD(dragLinkCursor, "alias")
STANDARD(dragCopyCursor, "copy")
STANDARD(contextualMenuCursor, "context-menu")
#undef STANDARD

+ (NSCursor *)currentCursor { return current ?: [self arrowCursor]; }
+ (NSCursor *)currentSystemCursor { return [self currentCursor]; }

- (instancetype)initWithImage:(NSImage *)image hotSpot:(NSPoint)hotSpot
{
    if ((self = [super init])) {
        _image = [image retain];
        _hotSpot = hotSpot;
    }
    return self;
}
- (instancetype)initWithImage:(NSImage *)image foregroundColorHint:(NSColor *)fg
          backgroundColorHint:(NSColor *)bg hotSpot:(NSPoint)hotSpot
{
    return [self initWithImage:image hotSpot:hotSpot];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSImage *image = [coder decodeObjectForKey:@"NSImage"];
    NSPoint hot = [coder containsValueForKey:@"NSHotSpot"] ? [coder decodePointForKey:@"NSHotSpot"] : NSZeroPoint;
    return [self initWithImage:[image isKindOfClass:[NSImage class]] ? image : nil hotSpot:hot];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_image)
        [coder encodeObject:_image forKey:@"NSImage"];
    [coder encodePoint:_hotSpot forKey:@"NSHotSpot"];
}
- (void)dealloc
{
    [_image release];
    if (_gdk)
        g_object_unref(_gdk);
    [super dealloc];
}

- (NSImage *)image
{
    if (!_image && _name)
        _image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    return _image;
}
- (NSPoint)hotSpot { return _hotSpot; }
- (NSString *)description
{
    return _name ? [NSString stringWithFormat:@"<NSCursor %p: %s>", self, _name]
                 : [NSString stringWithFormat:@"<NSCursor %p: image, hot spot %@>", self, NSStringFromPoint(_hotSpot)];
}

/* GTK's cursor for this one, made once there is a display to make it on. */
static GdkCursor *gdk_for(NSCursor *c)
{
    if (c->_gdk || !ADisplayAvailable())
        return c->_gdk;
    GdkDisplay *d = gdk_display_get_default();
    if (c->_name) {
        c->_gdk = gdk_cursor_new_from_name(d, c->_name);
    } else if (c->_image) {
        NSSize size = [c->_image size];
        int w = (int)ceil(size.width), h = (int)ceil(size.height);
        CGImageRef cg = [c->_image CGImageForProposedRect:NULL context:nil hints:nil];
        if (w > 0 && h > 0 && cg) {
            cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
            CGContextRef ctx = GContextCreateWithSurface(s, h);
            CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
            CGContextRelease(ctx);
            c->_gdk = gdk_cursor_new_from_surface(d, s, c->_hotSpot.x, c->_hotSpot.y);
            cairo_surface_destroy(s);
        }
    }
    if (!c->_gdk)
        c->_gdk = gdk_cursor_new_from_name(d, "default");
    return c->_gdk;
}

void ACursorApply(NSWindow *window)
{
    if (!ADisplayAvailable())
        return;
    GtkWidget *g = [window respondsToSelector:@selector(_gtkWindow)]
                       ? ((GtkWidget * (*)(id, SEL)) objc_msgSend)(window, @selector(_gtkWindow))
                       : NULL;
    GdkWindow *gw = g ? gtk_widget_get_window(g) : NULL;
    if (!gw)
        return;
    static GdkCursor *blank;
    if (hidden > 0 && !blank)
        blank = gdk_cursor_new_from_name(gdk_display_get_default(), "none");
    gdk_window_set_cursor(gw, hidden > 0 ? blank : gdk_for([NSCursor currentCursor]));
}

static void show_everywhere(void)
{
    for (NSWindow *w in AAllWindows())
        if ([w isVisible])
            ACursorApply(w);
}

- (void)set
{
    if (current != self) {
        [current release];
        current = [self retain];
    }
    show_everywhere();
}
- (void)push
{
    if (!stack)
        stack = [[NSMutableArray alloc] init];
    [stack addObject:[NSCursor currentCursor]];
    [self set];
}
- (void)pop { [NSCursor pop]; }
+ (void)pop
{
    if (![stack count])
        return;
    NSCursor *back = [[[stack lastObject] retain] autorelease];
    [stack removeLastObject];
    [back set];
}

+ (void)hide
{
    hidden++;
    show_everywhere();
}
+ (void)unhide
{
    if (hidden > 0)
        hidden--;
    hidden_until_moved = NO;
    show_everywhere();
}
+ (void)setHiddenUntilMouseMoves:(BOOL)flag
{
    if (flag == hidden_until_moved)
        return;
    hidden_until_moved = flag;
    hidden += flag ? 1 : -1;
    show_everywhere();
}
BOOL ACursorMouseMoved(void)
{
    if (!hidden_until_moved)
        return NO;
    hidden_until_moved = NO;
    hidden--;
    show_everywhere();
    return YES;
}

/* The older way: a cursor set as the mouse goes into or out of a tracking
 * rectangle whose owner it is. */
- (BOOL)isSetOnMouseEntered { return _onEntered; }
- (BOOL)isSetOnMouseExited { return _onExited; }
- (void)setOnMouseEntered:(BOOL)flag { _onEntered = flag; }
- (void)setOnMouseExited:(BOOL)flag { _onExited = flag; }
- (void)mouseEntered:(NSEvent *)event
{
    if (_onEntered)
        [self set];
}
- (void)mouseExited:(NSEvent *)event
{
    if (_onExited)
        [self set];
}
@end
