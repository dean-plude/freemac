/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSWindow and NSPanel. Each window draws its views into a
 * backing image of its own, with Core Graphics; when there is a display,
 * the window is also a GTK toplevel holding one drawing area, which shows
 * that image and turns GTK's input into NSEvents. The compositor decorates
 * the window, so a window's frame is its content rectangle. Wayland doesn't
 * let a program place its own windows, so a window's position on screen is
 * only what the program last set. */
#import "AInternal.h"

NSNotificationName const NSWindowWillCloseNotification = @"NSWindowWillCloseNotification";
NSNotificationName const NSWindowDidResizeNotification = @"NSWindowDidResizeNotification";
NSNotificationName const NSWindowDidChangeBackingPropertiesNotification = @"NSWindowDidChangeBackingPropertiesNotification";
NSString *const NSBackingPropertyOldScaleFactorKey = @"NSBackingPropertyOldScaleFactorKey";
NSString *const NSBackingPropertyOldColorSpaceKey = @"NSBackingPropertyOldColorSpaceKey";
NSNotificationName const NSWindowDidMoveNotification = @"NSWindowDidMoveNotification";
NSNotificationName const NSWindowDidBecomeKeyNotification = @"NSWindowDidBecomeKeyNotification";
NSNotificationName const NSWindowDidResignKeyNotification = @"NSWindowDidResignKeyNotification";
NSNotificationName const NSWindowDidBecomeMainNotification = @"NSWindowDidBecomeMainNotification";
NSNotificationName const NSWindowDidResignMainNotification = @"NSWindowDidResignMainNotification";
NSNotificationName const NSWindowDidMiniaturizeNotification = @"NSWindowDidMiniaturizeNotification";
NSNotificationName const NSWindowDidDeminiaturizeNotification = @"NSWindowDidDeminiaturizeNotification";

static NSMutableArray *all_windows;
static NSInteger next_number = 1;
static NSWindow *key_window, *main_window;

NSArray *AAllWindows(void) { return all_windows ?: @[]; }

/* The base view a window's content view sits in is the window itself; this
 * view fills the window with its background colour under the content. */
@implementation NSWindow {
    NSRect _frame;
    NSWindowStyleMask _style;
    NSString *_title;
    NSView *_contentView;
    id _delegate;
    NSInteger _number;
    BOOL _visible, _released, _acceptsMoved, _needsDisplay, _miniaturized, _zoomed, _closing, _opaque, _shadow;
    BOOL _autoKeyLoop, _movable, _transparentTitle;
    NSInteger _titleVisibility;
    NSColor *_background;
    NSResponder *_first;              /* not retained */
    NSView *_initialFirst;            /* not retained */
    NSSize _minSize, _maxSize;
    NSWindowLevel _level;
    CGFloat _alpha;
    NSString *_autosaveName;
    NSWindowController *_windowController;      /* not retained */
    NSViewController *_contentViewController;
    BOOL _edited;
    NSView *_mouseView[3];            /* retained while a button is down */
    NSEvent *_current;
    /* drawing and GTK */
    cairo_surface_t *_backing;
    CGContextRef _ctx;
    CGFloat _scale;
    int _backingW, _backingH;
    GtkWidget *_gtk, *_area;
    NSMutableSet *_keysDown;
    NSInteger _lastButton, _clicks;
    NSTimeInterval _lastClickTime;
    NSPoint _lastClickPoint;
    NSArray *_draggedTypes;
    BOOL _dropsWanted, _dropsOn;
}

/* Drag and drop (NSDragging.m): the window's own types, whose drops go to
 * its delegate, and the GTK drop target, set up once anything in the
 * window takes drops. */
/* Backing coordinates: points times the scale, the window's pixels. */
- (NSRect)convertRectToBacking:(NSRect)r
{
    CGFloat s = [self backingScaleFactor];
    return NSMakeRect(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s);
}
- (NSRect)convertRectFromBacking:(NSRect)r
{
    CGFloat s = [self backingScaleFactor];
    return NSMakeRect(r.origin.x / s, r.origin.y / s, r.size.width / s, r.size.height / s);
}
- (NSPoint)convertPointToBacking:(NSPoint)p
{
    CGFloat s = [self backingScaleFactor];
    return NSMakePoint(p.x * s, p.y * s);
}
- (NSPoint)convertPointFromBacking:(NSPoint)p
{
    CGFloat s = [self backingScaleFactor];
    return NSMakePoint(p.x / s, p.y / s);
}
/* Out to whole pixels (or in, or to the nearest, as the options say). */
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)options
{
    NSRect b = [self convertRectToBacking:r];
    CGFloat x0 = NSMinX(b), y0 = NSMinY(b), x1 = NSMaxX(b), y1 = NSMaxY(b);
    x0 = options & NSAlignMinXInward ? ceil(x0) : options & NSAlignMinXNearest ? round(x0) : floor(x0);
    y0 = options & NSAlignMinYInward ? ceil(y0) : options & NSAlignMinYNearest ? round(y0) : floor(y0);
    x1 = options & NSAlignMaxXInward ? floor(x1) : options & NSAlignMaxXNearest ? round(x1) : ceil(x1);
    y1 = options & NSAlignMaxYInward ? floor(y1) : options & NSAlignMaxYNearest ? round(y1) : ceil(y1);
    return [self convertRectFromBacking:NSMakeRect(x0, y0, x1 - x0, y1 - y0)];
}

- (void)registerForDraggedTypes:(NSArray *)types
{
    [_draggedTypes release];
    _draggedTypes = [types copy];
    [self _enableDrops];
}
- (void)unregisterDraggedTypes
{
    [_draggedTypes release];
    _draggedTypes = nil;
}
- (NSArray *)_registeredDraggedTypes { return _draggedTypes ?: @[]; }
- (void)_enableDrops
{
    _dropsWanted = YES;
    if (_area && !_dropsOn) {
        _dropsOn = YES;
        ADragAttach(self, _area);
    }
}

+ (NSRect)frameRectForContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style { return rect; }
+ (NSRect)contentRectForFrameRect:(NSRect)rect styleMask:(NSWindowStyleMask)style { return rect; }
- (NSRect)frameRectForContentRect:(NSRect)rect { return rect; }
- (NSRect)contentRectForFrameRect:(NSRect)rect { return rect; }

- (instancetype)init
{
    return [self initWithContentRect:NSMakeRect(0, 0, 480, 270) styleMask:NSWindowStyleMaskTitled
                             backing:NSBackingStoreBuffered defer:YES];
}

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)defer
{
    if (!(self = [super init]))
        return nil;
    _frame = rect;
    _style = style;
    _title = @"";
    _number = next_number++;
    _released = ![self isKindOfClass:[NSPanel class]];
    _opaque = _shadow = _autoKeyLoop = YES;
    _alpha = 1;
    _minSize = NSMakeSize(1, 1);
    _maxSize = NSMakeSize(3.40282347e+38, 3.40282347e+38);   /* FLT_MAX, as on a Mac */
    _keysDown = [[NSMutableSet alloc] init];
    if (!all_windows)
        all_windows = [[NSMutableArray alloc] init];
    [all_windows addObject:self];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, rect.size.width, rect.size.height)];
    [self setContentView:content];
    [content release];
    return self;
}

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)defer screen:(NSScreen *)screen
{
    return [self initWithContentRect:rect styleMask:style backing:backing defer:defer];
}

- (void)_destroyGtk
{
    if (_gtk) {
        GtkWidget *w = _gtk;
        _gtk = _area = NULL;
        _dropsOn = NO;
        gtk_widget_destroy(w);
    }
}

- (void)dealloc
{
    [self _destroyGtk];
    [_draggedTypes release];
    [_contentView _setWindow:nil];
    [_contentView setNextResponder:nil];
    [_contentView release];
    [_title release];
    [_background release];
    [_autosaveName release];
    [_keysDown release];
    for (int i = 0; i < 3; i++)
        [_mouseView[i] release];
    CGContextRelease(_ctx);
    if (_backing)
        cairo_surface_destroy(_backing);
    if (key_window == self)
        key_window = nil;
    if (main_window == self)
        main_window = nil;
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> windowNumber=%ld title=%@", [self class], self, (long)_number, _title];
}

/* ---- properties ------------------------------------------------------------------ */

- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)title
{
    [_title release];
    _title = [title ?: @"" copy];
    if (_gtk)
        gtk_window_set_title(_gtk, [_title UTF8String]);
}
- (void)setTitleWithRepresentedFilename:(NSString *)path { [self setTitle:[path lastPathComponent]]; }
- (NSView *)contentView { return _contentView; }
- (void)setContentView:(NSView *)view
{
    if (view == _contentView)
        return;
    [view retain];
    [view removeFromSuperview];
    [_contentView _setWindow:nil];
    [_contentView setNextResponder:nil];
    [_contentView release];
    _contentView = view;
    [_contentView setFrame:NSMakeRect(0, 0, _frame.size.width, _frame.size.height)];
    [_contentView setNextResponder:self];
    [_contentView _setWindow:self];
    [self _noteNeedsDisplay];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSRect)frame { return _frame; }
- (NSSize)_contentSize { return _frame.size; }
- (NSWindowStyleMask)styleMask { return _style; }
- (void)setStyleMask:(NSWindowStyleMask)style
{
    _style = style;
    if (_gtk) {
        gtk_window_set_resizable(_gtk, (style & NSWindowStyleMaskResizable) != 0);
        gtk_window_set_decorated(_gtk, style != NSWindowStyleMaskBorderless);
    }
}
- (NSInteger)windowNumber { return _number; }
- (BOOL)isVisible { return _visible; }
- (BOOL)isKeyWindow { return key_window == self; }
- (BOOL)isMainWindow { return main_window == self; }
- (BOOL)isMiniaturized { return _miniaturized; }
- (BOOL)isZoomed { return _zoomed; }
- (BOOL)canBecomeKeyWindow { return (_style & NSWindowStyleMaskTitled) || [self isKindOfClass:[NSPanel class]]; }
- (BOOL)canBecomeMainWindow { return [self canBecomeKeyWindow] && ![self isKindOfClass:[NSPanel class]]; }
- (BOOL)isReleasedWhenClosed { return _released; }
- (void)setReleasedWhenClosed:(BOOL)flag { _released = flag; }
- (NSColor *)backgroundColor { return _background ?: [NSColor windowBackgroundColor]; }
- (void)setBackgroundColor:(NSColor *)color
{
    [_background release];
    _background = [color retain];
    [self _noteNeedsDisplay];
}
- (NSResponder *)firstResponder { return _first ?: self; }
- (NSView *)initialFirstResponder { return _initialFirst; }
- (void)setInitialFirstResponder:(NSView *)view { _initialFirst = view; }
- (BOOL)acceptsMouseMovedEvents { return _acceptsMoved; }
- (void)setAcceptsMouseMovedEvents:(BOOL)flag { _acceptsMoved = flag; }
- (BOOL)_wantsMouseMoved { return _acceptsMoved; }
- (BOOL)autorecalculatesKeyViewLoop { return _autoKeyLoop; }
- (void)setAutorecalculatesKeyViewLoop:(BOOL)flag { _autoKeyLoop = flag; }
- (NSSize)minSize { return _minSize; }
- (void)setMinSize:(NSSize)size
{
    _minSize = size;
    if (_area)
        gtk_widget_set_size_request(_area, (int)size.width, (int)size.height);
}
- (NSSize)maxSize { return _maxSize; }
- (void)setMaxSize:(NSSize)size { _maxSize = size; }
- (NSSize)contentMinSize { return _minSize; }
- (void)setContentMinSize:(NSSize)size { [self setMinSize:size]; }
- (NSSize)contentMaxSize { return _maxSize; }
- (void)setContentMaxSize:(NSSize)size { _maxSize = size; }
- (NSWindowLevel)level { return _level; }
- (void)setLevel:(NSWindowLevel)level { _level = level; }
- (BOOL)isOpaque { return _opaque; }
- (void)setOpaque:(BOOL)flag { _opaque = flag; }
- (BOOL)hasShadow { return _shadow; }
- (void)setHasShadow:(BOOL)flag { _shadow = flag; }
- (CGFloat)alphaValue { return _alpha; }
- (void)setAlphaValue:(CGFloat)alpha { _alpha = alpha; }
- (BOOL)isMovableByWindowBackground { return _movable; }
- (void)setMovableByWindowBackground:(BOOL)flag { _movable = flag; }
- (BOOL)viewsNeedDisplay { return _needsDisplay; }
- (void)setViewsNeedDisplay:(BOOL)flag
{
    if (flag)
        [self _noteNeedsDisplay];
    else
        _needsDisplay = NO;
}
- (CGFloat)backingScaleFactor { return _scale > 0 ? _scale : AScreenScale(); }
- (NSScreen *)screen { return [NSScreen mainScreen]; }
- (NSString *)frameAutosaveName { return _autosaveName; }
- (BOOL)setFrameAutosaveName:(NSString *)name
{
    [_autosaveName release];
    _autosaveName = [name copy];
    return YES;
}
- (BOOL)setFrameUsingName:(NSString *)name { return NO; }

/* ---- controllers ---- */
- (NSWindowController *)windowController { return _windowController; }
- (void)setWindowController:(NSWindowController *)wc { [wc setWindow:self]; }
- (NSWindowController *)_windowController { return _windowController; }
- (void)_setWindowController:(NSWindowController *)wc { _windowController = wc; }
- (NSViewController *)contentViewController { return _contentViewController; }
- (void)setContentViewController:(NSViewController *)vc
{
    if (vc == _contentViewController)
        return;
    [vc retain];
    [_contentViewController release];
    _contentViewController = vc;
    NSView *view = [vc view];
    if (view) {
        NSSize size = [view frame].size;
        if (size.width > 0 && size.height > 0)
            [self setContentSize:size];
        [self setContentView:view];
    }
    if ([vc title] && ![[self title] length])
        [self setTitle:[vc title]];
}
+ (instancetype)windowWithContentViewController:(NSViewController *)vc
{
    NSView *view = [vc view];
    NSRect r = NSMakeRect(0, 0, view ? [view frame].size.width : 480, view ? [view frame].size.height : 270);
    NSWindow *w = [[[self alloc] initWithContentRect:r
                                           styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                             backing:NSBackingStoreBuffered
                                               defer:NO] autorelease];
    [w setReleasedWhenClosed:NO];
    [w setContentViewController:vc];
    [w center];
    return w;
}
- (BOOL)isDocumentEdited { return _edited; }
- (void)setDocumentEdited:(BOOL)f { _edited = f; }
- (BOOL)titlebarAppearsTransparent { return _transparentTitle; }
- (void)setTitlebarAppearsTransparent:(BOOL)flag { _transparentTitle = flag; }
- (NSInteger)titleVisibility { return _titleVisibility; }
- (void)setTitleVisibility:(NSInteger)v { _titleVisibility = v; }
- (NSGraphicsContext *)graphicsContext
{
    return _ctx ? [NSGraphicsContext graphicsContextWithCGContext:_ctx flipped:NO] : nil;
}
- (NSEvent *)currentEvent { return _current; }
- (void)setDefaultButtonCell:(id)cell { AWarnOnce("-[NSWindow setDefaultButtonCell:] (give the button the key equivalent \\r)"); }
- (void)update {}
- (void)invalidateShadow {}

/* ---- size and place --------------------------------------------------------------- */

- (void)_post:(NSNotificationName)name selector:(SEL)sel
{
    NSNotification *n = [NSNotification notificationWithName:name object:self];
    if ([_delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

/* The content size changed (asked for, or the compositor resized us). */
- (void)_resizedTo:(NSSize)size
{
    if (NSEqualSizes(size, _frame.size))
        return;
    _frame.size = size;
    [_contentView setFrameSize:size];
    [self _noteNeedsDisplay];
    [self _post:NSWindowDidResizeNotification selector:@selector(windowDidResize:)];
}

- (void)setFrame:(NSRect)frame display:(BOOL)display
{
    if ([_delegate respondsToSelector:@selector(windowWillResize:toSize:)] && !NSEqualSizes(frame.size, _frame.size))
        frame.size = [_delegate windowWillResize:self toSize:frame.size];
    frame.size.width = fmax(frame.size.width, 1);
    frame.size.height = fmax(frame.size.height, 1);
    BOOL moved = !NSEqualPoints(frame.origin, _frame.origin);
    _frame.origin = frame.origin;
    if (_gtk && !NSEqualSizes(frame.size, _frame.size))
        gtk_window_resize(_gtk, (int)frame.size.width, (int)frame.size.height);
    [self _resizedTo:frame.size];
    if (moved)
        [self _post:NSWindowDidMoveNotification selector:@selector(windowDidMove:)];
    if (display)
        [self displayIfNeeded];
}
- (void)setFrame:(NSRect)frame display:(BOOL)display animate:(BOOL)animate { [self setFrame:frame display:display]; }
- (void)setFrameOrigin:(NSPoint)origin { [self setFrame:(NSRect){origin, _frame.size} display:NO]; }
- (void)setFrameTopLeftPoint:(NSPoint)p { [self setFrameOrigin:NSMakePoint(p.x, p.y - _frame.size.height)]; }
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)p
{
    if (p.x == 0 && p.y == 0)
        p = NSMakePoint(_frame.origin.x, NSMaxY(_frame));
    [self setFrameTopLeftPoint:p];
    return NSMakePoint(p.x + 20, p.y - 20);
}
- (void)setContentSize:(NSSize)size { [self setFrame:(NSRect){_frame.origin, size} display:YES]; }
- (void)center
{
    NSRect screen = AScreenFrame(YES);
    [self setFrameOrigin:NSMakePoint(floor(NSMidX(screen) - _frame.size.width / 2),
                                     floor(screen.origin.y + (screen.size.height - _frame.size.height) * 2 / 3))];
}

- (NSRect)convertRectToScreen:(NSRect)r { return NSOffsetRect(r, _frame.origin.x, _frame.origin.y); }
- (NSRect)convertRectFromScreen:(NSRect)r { return NSOffsetRect(r, -_frame.origin.x, -_frame.origin.y); }
- (NSPoint)convertPointToScreen:(NSPoint)p { return NSMakePoint(p.x + _frame.origin.x, p.y + _frame.origin.y); }
- (NSPoint)convertPointFromScreen:(NSPoint)p { return NSMakePoint(p.x - _frame.origin.x, p.y - _frame.origin.y); }
- (NSPoint)mouseLocationOutsideOfEventStream { return [self convertPointFromScreen:[NSEvent mouseLocation]]; }

/* ---- drawing ----------------------------------------------------------------------- */

- (void)_noteNeedsDisplay
{
    _needsDisplay = YES;
    if (_area)
        gtk_widget_queue_draw(_area);
}

- (void)_ensureBacking
{
    CGFloat scale = _area ? gtk_widget_get_scale_factor(_area) : 1;
    if (scale < 1)
        scale = 1;
    int w = (int)ceil(_frame.size.width), h = (int)ceil(_frame.size.height);
    if (_backing && w == _backingW && h == _backingH && scale == _scale)
        return;
    CGContextRelease(_ctx);
    if (_backing)
        cairo_surface_destroy(_backing);
    _backingW = w;
    _backingH = h;
    CGFloat old = _scale;
    _scale = scale;
    if (old > 0 && old != scale) {
        /* moved to a screen of another scale (or the screen's scale changed) */
        [_contentView _backingPropertiesChanged];
        NSNotification *n = [NSNotification notificationWithName:NSWindowDidChangeBackingPropertiesNotification
                                                          object:self
                                                        userInfo:@{NSBackingPropertyOldScaleFactorKey : @(old)}];
        if ([_delegate respondsToSelector:@selector(windowDidChangeBackingProperties:)])
            [_delegate windowDidChangeBackingProperties:n];
        [[NSNotificationCenter defaultCenter] postNotification:n];
    }
    _backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)(w * scale), (int)(h * scale));
    cairo_surface_set_device_scale(_backing, scale, scale);
    _ctx = GContextCreateWithSurface(_backing, h);
    _needsDisplay = YES;
}

- (void)display
{
    [self _ensureBacking];
    _needsDisplay = NO;
    CGContextRef ctx = _ctx;
    NSRect all = NSMakeRect(0, 0, _frame.size.width, _frame.size.height);
    CGContextSaveGState(ctx);
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGFloat c[4];
    AColorRGBA([self backgroundColor], c);
    CGContextSetRGBFillColor(ctx, c[0], c[1], c[2], _opaque ? 1 : c[3]);
    CGContextFillRect(ctx, all);
    CGContextRestoreGState(ctx);
    [_contentView _drawInContext:ctx dirty:all screen:YES];
    CGContextFlush(ctx);
    if (_area)
        gtk_widget_queue_draw(_area);
}

- (void)displayIfNeeded
{
    if (_needsDisplay || [_contentView _needsDisplayAnywhere] || !_backing)
        [self display];
}

/* ---- ordering, key and main ---------------------------------------------------------- */

static int on_draw(GtkWidget *w, cairo_t *cr, void *data);
static int on_button(GtkWidget *w, GdkEvent *e, void *data);
static int on_motion(GtkWidget *w, GdkEvent *e, void *data);
static int on_scroll(GtkWidget *w, GdkEvent *e, void *data);
static int on_key(GtkWidget *w, GdkEvent *e, void *data);
static int on_delete(GtkWidget *w, GdkEvent *e, void *data);
static int on_focus_in(GtkWidget *w, GdkEvent *e, void *data);
static int on_focus_out(GtkWidget *w, GdkEvent *e, void *data);
static void on_size(GtkWidget *w, GdkRectangle *r, void *data);

static void connect(GtkWidget *w, const char *signal, void *handler, NSWindow *window)
{
    g_signal_connect_data(w, signal, (GCallback)handler, window, NULL, 0);
}

- (void)_makeGtk
{
    if (_gtk || !ADisplayAvailable())
        return;
    _gtk = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(_gtk, [_title UTF8String]);
    gtk_window_set_default_size(_gtk, (int)_frame.size.width, (int)_frame.size.height);
    gtk_window_set_resizable(_gtk, (_style & NSWindowStyleMaskResizable) != 0);
    gtk_window_set_decorated(_gtk, _style != NSWindowStyleMaskBorderless);
    gtk_window_set_deletable(_gtk, (_style & NSWindowStyleMaskClosable) != 0);
    _area = gtk_drawing_area_new();
    if (_style & NSWindowStyleMaskResizable)
        gtk_widget_set_size_request(_area, (int)fmax(_minSize.width, 1), (int)fmax(_minSize.height, 1));
    else
        gtk_widget_set_size_request(_area, (int)_frame.size.width, (int)_frame.size.height);
    gtk_widget_add_events(_area, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
                                     GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_ENTER_NOTIFY_MASK |
                                     GDK_LEAVE_NOTIFY_MASK);
    gtk_widget_set_can_focus(_area, 1);
    gtk_container_add(_gtk, _area);
    connect(_area, "draw", on_draw, self);
    connect(_area, "button-press-event", on_button, self);
    connect(_area, "button-release-event", on_button, self);
    connect(_area, "motion-notify-event", on_motion, self);
    connect(_area, "scroll-event", on_scroll, self);
    connect(_area, "size-allocate", on_size, self);
    connect(_gtk, "key-press-event", on_key, self);
    connect(_gtk, "key-release-event", on_key, self);
    connect(_gtk, "delete-event", on_delete, self);
    connect(_gtk, "focus-in-event", on_focus_in, self);
    connect(_gtk, "focus-out-event", on_focus_out, self);
    if (_dropsWanted)
        [self _enableDrops];
    gtk_widget_show_all(_gtk);
    gtk_widget_grab_focus(_area);
}

- (void)orderFront:(id)sender
{
    if (_closing)
        return;
    BOOL was = _visible;
    _visible = YES;
    if (!was) {
        if (!_first && _initialFirst)
            [self makeFirstResponder:_initialFirst];
        [self _noteNeedsDisplay];
    }
    [self _makeGtk];
    if (_gtk)
        gtk_window_present(_gtk);
}
- (void)orderFrontRegardless { [self orderFront:nil]; }
- (void)orderBack:(id)sender { [self orderFront:sender]; }
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other
{
    if (place == NSWindowOut)
        [self orderOut:nil];
    else
        [self orderFront:nil];
}
- (void)orderOut:(id)sender
{
    if (!_visible)
        return;
    _visible = NO;
    if (_gtk)
        gtk_widget_hide(_gtk);
    if (key_window == self)
        [self resignKeyWindow];
    if (main_window == self)
        [self resignMainWindow];
}

- (void)makeKeyAndOrderFront:(id)sender
{
    [self orderFront:sender];
    [self makeKeyWindow];
    if ([self canBecomeMainWindow])
        [self makeMainWindow];
}

- (void)makeKeyWindow
{
    if (key_window == self || ![self canBecomeKeyWindow])
        return;
    [key_window resignKeyWindow];
    key_window = self;
    [self becomeKeyWindow];
}
- (void)makeMainWindow
{
    if (main_window == self || ![self canBecomeMainWindow])
        return;
    [main_window resignMainWindow];
    main_window = self;
    [self becomeMainWindow];
}
- (void)becomeKeyWindow
{
    if (!_first) {
        if (_initialFirst)
            [self makeFirstResponder:_initialFirst];
    }
    [self _noteNeedsDisplay];
    [self _post:NSWindowDidBecomeKeyNotification selector:@selector(windowDidBecomeKey:)];
}
- (void)resignKeyWindow
{
    if (key_window == self)
        key_window = nil;
    [self _noteNeedsDisplay];
    [self _post:NSWindowDidResignKeyNotification selector:@selector(windowDidResignKey:)];
}
- (void)becomeMainWindow { [self _post:NSWindowDidBecomeMainNotification selector:@selector(windowDidBecomeMain:)]; }
- (void)resignMainWindow
{
    if (main_window == self)
        main_window = nil;
    [self _post:NSWindowDidResignMainNotification selector:@selector(windowDidResignMain:)];
}

- (void)performClose:(id)sender
{
    if (!(_style & NSWindowStyleMaskClosable)) {
        NSBeep();
        return;
    }
    if ([_delegate respondsToSelector:@selector(windowShouldClose:)] && ![_delegate windowShouldClose:self])
        return;
    [self close];
}

- (void)close
{
    if (_closing)
        return;
    _closing = YES;
    [self retain];
    [self _post:NSWindowWillCloseNotification selector:@selector(windowWillClose:)];
    [self orderOut:nil];
    [self _destroyGtk];
    [all_windows removeObjectIdenticalTo:self];
    AWindowDidClose(self);
    if (_released)
        [self autorelease];
    [self release];
}

- (void)miniaturize:(id)sender
{
    _miniaturized = YES;
    if (_gtk)
        gtk_window_iconify(_gtk);
    [self _post:NSWindowDidMiniaturizeNotification selector:@selector(windowDidMiniaturize:)];
}
- (void)deminiaturize:(id)sender
{
    _miniaturized = NO;
    if (_gtk)
        gtk_window_deiconify(_gtk);
    [self _post:NSWindowDidDeminiaturizeNotification selector:@selector(windowDidDeminiaturize:)];
}
- (void)performMiniaturize:(id)sender { [self miniaturize:sender]; }
- (void)zoom:(id)sender
{
    _zoomed = !_zoomed;
    if (_gtk) {
        if (_zoomed)
            gtk_window_maximize(_gtk);
        else
            gtk_window_unmaximize(_gtk);
    }
}
- (void)performZoom:(id)sender { [self zoom:sender]; }
- (void)toggleFullScreen:(id)sender { [self zoom:sender]; }

/* ---- the first responder and key views ---------------------------------------------- */

- (BOOL)makeFirstResponder:(NSResponder *)responder
{
    if (responder == self)
        responder = nil;
    if (responder == _first)
        return YES;
    if (_first && ![_first resignFirstResponder])
        return NO;
    NSResponder *old = _first;
    _first = nil;
    if ([old isKindOfClass:[NSView class]])
        [(NSView *)old setNeedsDisplay:YES];
    if (!responder)
        return YES;
    if (![responder acceptsFirstResponder] || ![responder becomeFirstResponder])
        return NO;
    _first = responder;
    if ([responder isKindOfClass:[NSView class]])
        [(NSView *)responder setNeedsDisplay:YES];
    return YES;
}

static void collect_key_views(NSView *view, NSMutableArray *out)
{
    if ([view isHidden])
        return;
    if ([view acceptsFirstResponder])
        [out addObject:view];
    for (NSView *v in [view subviews])
        collect_key_views(v, out);
}

/* Without a key-view loop set by the program, the order is reading order:
 * top to bottom, then left to right, as a Mac works it out. */
- (NSArray *)_keyViewOrder
{
    NSMutableArray *views = [NSMutableArray array];
    collect_key_views(_contentView, views);
    [views sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        NSRect ra = [a convertRect:[a bounds] toView:nil], rb = [b convertRect:[b bounds] toView:nil];
        if (fabs(NSMaxY(ra) - NSMaxY(rb)) > 1)
            return NSMaxY(ra) > NSMaxY(rb) ? NSOrderedAscending : NSOrderedDescending;
        if (ra.origin.x != rb.origin.x)
            return ra.origin.x < rb.origin.x ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    return views;
}

- (NSView *)_keyViewAfter:(NSView *)view forward:(BOOL)forward
{
    if (view) {
        NSView *v = forward ? [view nextValidKeyView] : nil;
        if (!forward)
            for (NSView *p = [view previousKeyView]; p && p != view; p = [p previousKeyView])
                if ([p canBecomeKeyView]) {
                    v = p;
                    break;
                }
        if (v)
            return v;
    }
    NSArray *order = [self _keyViewOrder];
    if (![order count])
        return nil;
    NSUInteger i = view ? [order indexOfObjectIdenticalTo:view] : NSNotFound;
    if (i == NSNotFound)
        return forward ? order[0] : [order lastObject];
    NSUInteger n = [order count];
    return order[forward ? (i + 1) % n : (i + n - 1) % n];
}

- (void)selectKeyViewFollowingView:(NSView *)view
{
    NSView *v = [self _keyViewAfter:view forward:YES];
    if (v)
        [self makeFirstResponder:v];
}
- (void)selectKeyViewPrecedingView:(NSView *)view
{
    NSView *v = [self _keyViewAfter:view forward:NO];
    if (v)
        [self makeFirstResponder:v];
}
- (void)selectNextKeyView:(id)sender
{
    [self selectKeyViewFollowingView:[_first isKindOfClass:[NSView class]] ? (NSView *)_first : nil];
}
- (void)selectPreviousKeyView:(id)sender
{
    [self selectKeyViewPrecedingView:[_first isKindOfClass:[NSView class]] ? (NSView *)_first : nil];
}
- (void)recalculateKeyViewLoop {}

/* ---- events -------------------------------------------------------------------------- */

static int button_index(NSEventType t)
{
    switch (t) {
    case NSEventTypeRightMouseDown:
    case NSEventTypeRightMouseDragged:
    case NSEventTypeRightMouseUp:
        return 1;
    case NSEventTypeOtherMouseDown:
    case NSEventTypeOtherMouseDragged:
    case NSEventTypeOtherMouseUp:
        return 2;
    default:
        return 0;
    }
}

- (void)sendEvent:(NSEvent *)e
{
    if (_closing && [e type] != NSEventTypeApplicationDefined)
        return;
    NSEvent *saved = _current;
    _current = e;
    [self retain];
    NSEventType t = [e type];
    int b = button_index(t);
    switch (t) {
    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown:
    case NSEventTypeOtherMouseDown: {
        if (![self isKeyWindow] && [self canBecomeKeyWindow])
            [self makeKeyAndOrderFront:nil];
        NSView *v = [_contentView hitTest:[e locationInWindow]];
        [_mouseView[b] release];
        _mouseView[b] = [v retain];
        if (!v)
            break;
        if (t == NSEventTypeLeftMouseDown && v != (NSView *)_first && [v acceptsFirstResponder])
            [self makeFirstResponder:v];
        if (t == NSEventTypeLeftMouseDown)
            [v mouseDown:e];
        else if (t == NSEventTypeRightMouseDown)
            [v rightMouseDown:e];
        else
            [v otherMouseDown:e];
        break;
    }
    case NSEventTypeLeftMouseDragged:
        [_mouseView[0] mouseDragged:e];
        break;
    case NSEventTypeRightMouseDragged:
        [_mouseView[1] rightMouseDragged:e];
        break;
    case NSEventTypeOtherMouseDragged:
        [_mouseView[2] otherMouseDragged:e];
        break;
    case NSEventTypeLeftMouseUp:
    case NSEventTypeRightMouseUp:
    case NSEventTypeOtherMouseUp: {
        NSView *v = _mouseView[b];
        _mouseView[b] = nil;
        if (t == NSEventTypeLeftMouseUp)
            [v mouseUp:e];
        else if (t == NSEventTypeRightMouseUp)
            [v rightMouseUp:e];
        else
            [v otherMouseUp:e];
        [v release];
        break;
    }
    case NSEventTypeMouseMoved:
        if (_acceptsMoved)
            [[self firstResponder] mouseMoved:e];
        break;
    case NSEventTypeScrollWheel: {
        NSView *v = [_contentView hitTest:[e locationInWindow]];
        [(v ?: (id)self) scrollWheel:e];
        break;
    }
    case NSEventTypeKeyDown:
        if (([e modifierFlags] & NSEventModifierFlagCommand) && [self performKeyEquivalent:e])
            break;
        [[self firstResponder] keyDown:e];
        break;
    case NSEventTypeKeyUp:
        [[self firstResponder] keyUp:e];
        break;
    case NSEventTypeFlagsChanged:
        [[self firstResponder] flagsChanged:e];
        break;
    default:
        break;
    }
    _current = saved;
    [self release];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event { return [_contentView performKeyEquivalent:event]; }

/* The end of the responder chain for keys: Return and Escape press the
 * window's default and cancel buttons (the ones whose key equivalent is
 * Return or Escape), and Tab moves between key views. */
- (void)keyDown:(NSEvent *)event
{
    NSString *c = [event charactersIgnoringModifiers];
    unichar ch = [c length] ? [c characterAtIndex:0] : 0;
    if (ch == NSCarriageReturnCharacter || ch == NSEnterCharacter || ch == 0x1b) {
        if ([self performKeyEquivalent:event])
            return;
    } else if (ch == NSTabCharacter && !([event modifierFlags] & NSEventModifierFlagShift)) {
        [self selectNextKeyView:nil];
        return;
    } else if (ch == NSBackTabCharacter || ch == NSTabCharacter) {
        [self selectPreviousKeyView:nil];
        return;
    }
    [super keyDown:event];
}

- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart { [NSApp postEvent:event atStart:atStart]; }
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask
{
    return [self nextEventMatchingMask:mask untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES];
}
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)date inMode:(NSRunLoopMode)mode
                           dequeue:(BOOL)dequeue
{
    return [NSApp nextEventMatchingMask:mask untilDate:date inMode:mode dequeue:dequeue];
}

/* ---- GTK's side ------------------------------------------------------------------------ */

static int on_draw(GtkWidget *w, cairo_t *cr, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        int width = gtk_widget_get_allocated_width(w), height = gtk_widget_get_allocated_height(w);
        A_REPORTING([win _resizedTo:NSMakeSize(width, height)]; [win _ensureBacking]; [win displayIfNeeded];)
        if (win->_backing) {
            cairo_set_source_surface(cr, win->_backing, 0, 0);
            cairo_paint(cr);
        }
    }
    return 1;
}

static void on_size(GtkWidget *w, GdkRectangle *r, void *data)
{
    @autoreleasepool {
        A_REPORTING([(NSWindow *)data _resizedTo:NSMakeSize(r->width, r->height)];)
    }
}

static NSPoint location(NSWindow *win, const GdkEvent *e, unsigned *state)
{
    double x = 0, y = 0;
    gdk_event_get_coords(e, &x, &y);
    if (state)
        gdk_event_get_state(e, state);
    NSPoint p = NSMakePoint(x, win->_frame.size.height - y);
    return p;
}

static NSUInteger buttons_from(unsigned state)
{
    NSUInteger b = 0;
    if (state & GDK_BUTTON1_MASK)
        b |= 1;
    if (state & GDK_BUTTON3_MASK)
        b |= 2;
    if (state & GDK_BUTTON2_MASK)
        b |= 4;
    return b;
}

static int on_button(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        int type = gdk_event_get_event_type(e);
        if (type == GDK_2BUTTON_PRESS || type == GDK_3BUTTON_PRESS)
            return 1;   /* counted below from the single presses */
        unsigned state = 0, button = 1;
        NSPoint p = location(win, e, &state);
        gdk_event_get_button(e, &button);
        NSInteger b = button == 1 ? 0 : button == 3 ? 1 : 2;
        BOOL down = type == GDK_BUTTON_PRESS;
        NSEventModifierFlags flags = AModifiersFromGdk(state);
        if (down) {
            NSTimeInterval t = gdk_event_get_time(e) / 1000.0;
            if (b == win->_lastButton && t - win->_lastClickTime <= [NSEvent doubleClickInterval] &&
                fabs(p.x - win->_lastClickPoint.x) <= 4 && fabs(p.y - win->_lastClickPoint.y) <= 4)
                win->_clicks++;
            else
                win->_clicks = 1;
            win->_lastButton = b;
            win->_lastClickTime = t;
            win->_lastClickPoint = p;
        }
        static const NSEventType types[2][3] = {
            {NSEventTypeLeftMouseUp, NSEventTypeRightMouseUp, NSEventTypeOtherMouseUp},
            {NSEventTypeLeftMouseDown, NSEventTypeRightMouseDown, NSEventTypeOtherMouseDown},
        };
        NSUInteger pressed = buttons_from(state);
        NSUInteger bit = b == 0 ? 1 : b == 1 ? 2 : 4;
        pressed = down ? pressed | bit : pressed & ~bit;
        ASetMouseLocation([win convertPointToScreen:p], pressed);
        ASetCurrentModifiers(flags);
        AEnqueueEvent(AMouseEvent(types[down][b], p, flags, win, win->_clicks, button - 1));
    }
    return 1;
}

static int on_motion(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        unsigned state = 0;
        NSPoint p = location(win, e, &state);
        ASetMouseLocation([win convertPointToScreen:p], buttons_from(state));
        NSEventType type = state & GDK_BUTTON1_MASK   ? NSEventTypeLeftMouseDragged
                           : state & GDK_BUTTON3_MASK ? NSEventTypeRightMouseDragged
                           : state & GDK_BUTTON2_MASK ? NSEventTypeOtherMouseDragged
                                                      : NSEventTypeMouseMoved;
        if (type == NSEventTypeMouseMoved && !win->_acceptsMoved)
            return 1;
        AEnqueueEvent(AMouseEvent(type, p, AModifiersFromGdk(state), win, 0, type == NSEventTypeRightMouseDragged));
    }
    return 1;
}

static int on_scroll(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        unsigned state = 0;
        NSPoint p = location(win, e, &state);
        int direction = GDK_SCROLL_SMOOTH;
        double dx = 0, dy = 0;
        gdk_event_get_scroll_direction(e, &direction);
        BOOL precise = NO;
        if (direction == GDK_SCROLL_SMOOTH) {
            gdk_event_get_scroll_deltas(e, &dx, &dy);
            precise = YES;
        } else {
            dx = direction == GDK_SCROLL_LEFT ? -1 : direction == GDK_SCROLL_RIGHT ? 1 : 0;
            dy = direction == GDK_SCROLL_UP ? -1 : direction == GDK_SCROLL_DOWN ? 1 : 0;
        }
        /* a Mac's deltas are positive scrolling up and left */
        AEnqueueEvent(AScrollEvent(p, AModifiersFromGdk(state), win, -dx, -dy, precise));
    }
    return 1;
}

static unsigned modifier_bit(unsigned keyval)
{
    switch (keyval) {
    case 0xffe1: case 0xffe2: return GDK_SHIFT_MASK;
    case 0xffe3: case 0xffe4: return GDK_CONTROL_MASK;
    case 0xffe5: return GDK_LOCK_MASK;
    case 0xffe9: case 0xffea: return GDK_MOD1_MASK;
    case 0xffe7: case 0xffe8: return GDK_META_MASK;
    case 0xffeb: case 0xffec: return GDK_SUPER_MASK;
    }
    return 0;
}

static int on_key(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        unsigned keyval = 0, state = 0;
        uint16_t hardware = 0;
        gdk_event_get_keyval(e, &keyval);
        gdk_event_get_keycode(e, &hardware);
        gdk_event_get_state(e, &state);
        BOOL down = gdk_event_get_event_type(e) == 8;    /* GDK_KEY_PRESS */
        unsigned short code = AMacKeyCode(hardware);
        unsigned bit = modifier_bit(keyval);
        if (bit) {
            /* GDK's state is from before this key; a Mac reports the new flags */
            unsigned now = down ? state | bit : state & ~bit;
            if (bit == GDK_LOCK_MASK)
                now = state ^ (down ? bit : 0);
            NSEventModifierFlags flags = AModifiersFromGdk(now);
            ASetCurrentModifiers(flags);
            AEnqueueEvent(AKeyEvent(NSEventTypeFlagsChanged, flags, win, @"", @"", NO, code));
            return 1;
        }
        NSNumber *key = @(hardware);
        BOOL repeat = down && [win->_keysDown containsObject:key];
        if (down)
            [win->_keysDown addObject:key];
        else
            [win->_keysDown removeObject:key];
        NSEventModifierFlags flags = AModifiersFromGdk(state);
        ASetCurrentModifiers(flags);
        NSString *chars = ACharactersForKeyval(keyval, state, NO);
        NSString *plain = ACharactersForKeyval(keyval, state, YES);
        if (flags & NSEventModifierFlagCommand)
            plain = [plain lowercaseString];
        if ([chars length] == 1 && [chars characterAtIndex:0] >= 0xF700)
            flags |= NSEventModifierFlagFunction;
        AEnqueueEvent(AKeyEvent(down ? NSEventTypeKeyDown : NSEventTypeKeyUp, flags, win, chars, plain, repeat, code));
    }
    return 1;
}

static int on_delete(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        A_REPORTING([(NSWindow *)data performClose:nil];)
    }
    return 1;   /* AppKit decides; GTK mustn't destroy the window itself */
}

static int on_focus_in(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        A_REPORTING([win makeKeyWindow]; [win makeMainWindow];)
    }
    return 0;
}

static int on_focus_out(GtkWidget *w, GdkEvent *e, void *data)
{
    @autoreleasepool {
        NSWindow *win = data;
        if (key_window == win)
            A_REPORTING([win resignKeyWindow];)
    }
    return 0;
}
@end

NSWindow *AKeyWindow(void) { return key_window; }
NSWindow *AMainWindow(void) { return main_window; }

void AWindowsDisplayIfNeeded(void)
{
    for (NSWindow *w in [[all_windows copy] autorelease])
        if ([w isVisible])
            [w displayIfNeeded];
}

@implementation NSPanel {
    BOOL _floating, _keyOnlyIfNeeded, _worksWhenModal;
}
- (BOOL)isFloatingPanel { return _floating; }
- (void)setFloatingPanel:(BOOL)flag { _floating = flag; }
- (BOOL)becomesKeyOnlyIfNeeded { return _keyOnlyIfNeeded; }
- (void)setBecomesKeyOnlyIfNeeded:(BOOL)flag { _keyOnlyIfNeeded = flag; }
- (BOOL)worksWhenModal { return _worksWhenModal; }
- (void)setWorksWhenModal:(BOOL)flag { _worksWhenModal = flag; }
@end
