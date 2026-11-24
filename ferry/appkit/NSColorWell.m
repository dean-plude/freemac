/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: colour wells (NSColorWell) and the colour panel
 * (NSColorPanel), written from Apple's public API documentation.
 *
 * A colour well is drawn Ferry's way: a white rounded box with the colour
 * in it (over a black and white diagonal when it isn't opaque), its
 * border the accent colour while it is active. A click makes it active,
 * which opens the shared colour panel on its colour; a click on an active
 * well puts it out again. Only one well is active at a time unless the
 * click held Shift (activate: with NO).
 *
 * The shared colour panel is this system's colour chooser (GTK's), shown
 * as a dialog of its own that doesn't block the app. When the user picks
 * a colour there, the panel takes it, every active well takes it and
 * sends its action, the panel's own target gets its action, changeColor:
 * goes to the first responder (NSApp's sendAction: with no target, as on a
 * Mac) and NSColorPanelColorDidChangeNotification is posted. Closing the
 * panel puts out the active wells. Setting the panel's colour in code
 * changes only what it shows.
 *
 * With no display there is no chooser: the colour in FERRY_COLOR_ANSWER
 * ("red green blue [alpha]", each 0 to 1) is picked a moment after the
 * panel is shown, if it is set, as FERRY_PANEL_ANSWER answers Open panels.
 *
 * A nib's colour well keeps its colour under "NSColor" and its border
 * under "NSIsBordered", the names given in developers' descriptions of the
 * format; no Apple code was read. */
#import "AInternal.h"

NSNotificationName const NSColorPanelColorDidChangeNotification = @"NSColorPanelColorDidChangeNotification";

@interface NSColorWell (FerryColorPanel)
- (void)_panelPicked:(NSColor *)color;
- (void)_panelClosed;
@end

/* The active wells, not retained: a well leaves the list when it is put
 * out or goes away. */
static NSMutableArray *active_wells(void)
{
    static NSMutableArray *wells;
    if (!wells)
        wells = [[NSMutableArray alloc] init];
    return wells;
}

/* ---- NSColorPanel --------------------------------------------------------------------- */

static NSColorPanel *shared_panel;
static NSColorPanelOptions picker_mask = NSColorPanelAllModesMask;
static NSColorPanelMode picker_mode = NSColorPanelModeWheel;

@implementation NSColorPanel {
    NSColor *_color;
    BOOL _showsAlpha, _continuous, _shown;
    NSColorPanelMode _mode;
    id _target;
    SEL _action;
    NSView *_accessory;
    GtkWidget *_chooser;
}

+ (NSColorPanel *)sharedColorPanel
{
    if (!shared_panel)
        shared_panel = [[NSColorPanel alloc] initWithContentRect:NSMakeRect(0, 0, 230, 320)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                                 NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
    return shared_panel;
}
+ (BOOL)sharedColorPanelExists { return shared_panel != nil; }
+ (void)setPickerMask:(NSColorPanelOptions)mask { picker_mask = mask; }
+ (void)setPickerMode:(NSColorPanelMode)mode { picker_mode = mode; }
+ (BOOL)dragColor:(NSColor *)color withEvent:(NSEvent *)event fromView:(NSView *)view { return NO; }

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing
                              defer:(BOOL)defer
{
    if ((self = [super initWithContentRect:rect styleMask:style backing:backing defer:defer])) {
        _color = [[NSColor whiteColor] retain];
        _showsAlpha = NO;
        _continuous = YES;
        _mode = picker_mode;
        [self setTitle:@"Colors"];
    }
    return self;
}
- (void)dealloc
{
    [_color release];
    [_accessory release];
    if (_chooser)
        gtk_widget_destroy(_chooser);
    [super dealloc];
}

- (NSColor *)color { return _color; }
/* Only what the panel shows: nothing is sent. */
- (void)setColor:(NSColor *)color
{
    if (!color)
        return;
    [_color release];
    _color = [color copy];
    if (_chooser) {
        CGFloat c[4];
        AColorRGBA(_color, c);
        GdkRGBA rgba = {c[0], c[1], c[2], c[3]};
        gtk_color_chooser_set_rgba(_chooser, &rgba);
    }
}
- (CGFloat)alpha { return _showsAlpha ? [_color alphaComponent] : 1; }
- (BOOL)showsAlpha { return _showsAlpha; }
- (void)setShowsAlpha:(BOOL)f
{
    _showsAlpha = f;
    if (_chooser)
        gtk_color_chooser_set_use_alpha(_chooser, f);
}
- (NSColorPanelMode)mode { return _mode; }
- (void)setMode:(NSColorPanelMode)m { _mode = m; }
- (BOOL)isContinuous { return _continuous; }
- (void)setContinuous:(BOOL)f { _continuous = f; }
- (NSView *)accessoryView { return _accessory; }
- (void)setAccessoryView:(NSView *)v
{
    [_accessory release];
    _accessory = [v retain];
}
- (void)setTarget:(id)target { _target = target; }
- (void)setAction:(SEL)action { _action = action; }
- (BOOL)isVisible { return _shown; }
- (BOOL)isFloatingPanel { return YES; }

/* The user picked a colour. */
- (void)_picked:(NSColor *)color
{
    [self retain];
    [self setColor:color];
    for (NSColorWell *w in [[active_wells() copy] autorelease])
        [w _panelPicked:_color];
    if (_action)
        [NSApp sendAction:_action to:_target from:self];
    [NSApp sendAction:@selector(changeColor:) to:nil from:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSColorPanelColorDidChangeNotification object:self];
    [self release];
}

static void on_response(GtkWidget *dialog, int response, void *data)
{
    NSColorPanel *panel = data;
    A_REPORTING({
        if (response == GTK_RESPONSE_OK) {
            GdkRGBA c;
            gtk_color_chooser_get_rgba(dialog, &c);
            [panel _picked:[NSColor colorWithSRGBRed:c.red green:c.green blue:c.blue alpha:c.alpha]];
        }
        [panel orderOut:nil];
    })
}
static int on_delete(GtkWidget *dialog, GdkEvent *event, void *data)
{
    A_REPORTING([(NSColorPanel *)data orderOut:nil];)
    return 1;
}

/* No display: the answer the environment gives, if any. */
- (void)_answerFromEnvironment
{
    const char *answer = getenv("FERRY_COLOR_ANSWER");
    if (!_shown || !answer || !*answer)
        return;
    double c[4] = {0, 0, 0, 1};
    int n = sscanf(answer, "%lf %lf %lf %lf", &c[0], &c[1], &c[2], &c[3]);
    if (n >= 3)
        [self _picked:[NSColor colorWithSRGBRed:c[0] green:c[1] blue:c[2] alpha:c[3]]];
    [self orderOut:nil];
}

- (void)orderFront:(id)sender
{
    BOOL was = _shown;
    _shown = YES;
    if (ADisplayAvailable()) {
        if (!_chooser) {
            _chooser = gtk_color_chooser_dialog_new([[self title] UTF8String], NULL);
            g_signal_connect_data(_chooser, "response", (GCallback)on_response, self, NULL, 0);
            g_signal_connect_data(_chooser, "delete-event", (GCallback)on_delete, self, NULL, 0);
        }
        [self setColor:_color];
        gtk_color_chooser_set_use_alpha(_chooser, _showsAlpha);
        gtk_widget_show_all(_chooser);
        gtk_window_present(_chooser);
    } else if (!was) {
        [self performSelector:@selector(_answerFromEnvironment) withObject:nil afterDelay:0];
    }
}
- (void)makeKeyAndOrderFront:(id)sender { [self orderFront:sender]; }
- (void)orderFrontRegardless { [self orderFront:nil]; }
- (void)orderOut:(id)sender
{
    if (!_shown)
        return;
    _shown = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_answerFromEnvironment) object:nil];
    if (_chooser)
        gtk_widget_hide(_chooser);
    for (NSColorWell *w in [[active_wells() copy] autorelease])
        [w _panelClosed];
}
- (void)close { [self orderOut:nil]; }
- (void)performClose:(id)sender { [self orderOut:nil]; }
@end

/* ---- NSColorWell ---------------------------------------------------------------------- */

@implementation NSColorWell {
    NSColor *_color;
    BOOL _bordered, _active, _pressed, _supportsAlpha;
    NSColorWellStyle _style;
}

- (void)_setDefaults
{
    [super _setDefaults];
    _color = [[NSColor whiteColor] retain];
    _bordered = YES;
    _supportsAlpha = YES;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    id color = [coder containsValueForKey:@"NSColor"] ? [coder decodeObjectForKey:@"NSColor"] : nil;
    if ([color isKindOfClass:[NSColor class]])
        [self setColor:color];
    if ([coder containsValueForKey:@"NSIsBordered"])
        _bordered = [coder decodeBoolForKey:@"NSIsBordered"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_color forKey:@"NSColor"];
    [coder encodeBool:_bordered forKey:@"NSIsBordered"];
}
- (void)dealloc
{
    [active_wells() removeObjectIdenticalTo:self];
    [_color release];
    [super dealloc];
}

- (NSColor *)color { return _color; }
- (void)setColor:(NSColor *)color
{
    if (!color)
        return;
    [_color release];
    _color = [color copy];
    [self setNeedsDisplay:YES];
}
- (id)objectValue { return _color; }
- (void)setObjectValue:(id)value
{
    if ([value isKindOfClass:[NSColor class]])
        [self setColor:value];
}
- (BOOL)isBordered { return _bordered; }
- (void)setBordered:(BOOL)f
{
    _bordered = f;
    [self setNeedsDisplay:YES];
}
- (NSColorWellStyle)colorWellStyle { return _style; }
- (void)setColorWellStyle:(NSColorWellStyle)s
{
    _style = s;
    [self setNeedsDisplay:YES];
}
- (BOOL)supportsAlpha { return _supportsAlpha; }
- (void)setSupportsAlpha:(BOOL)f { _supportsAlpha = f; }
- (BOOL)isActive { return _active; }

- (void)activate:(BOOL)exclusive
{
    if (exclusive)
        for (NSColorWell *w in [[active_wells() copy] autorelease])
            if (w != self)
                [w deactivate];
    if (!_active) {
        _active = YES;
        [active_wells() addObject:self];
        [self setNeedsDisplay:YES];
    }
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];
    [panel setShowsAlpha:_supportsAlpha && [panel showsAlpha]];
    [panel setColor:_color];
    [panel orderFront:self];
}
- (void)deactivate
{
    if (!_active)
        return;
    _active = NO;
    [active_wells() removeObjectIdenticalTo:self];
    [self setNeedsDisplay:YES];
}
- (void)takeColorFrom:(id)sender
{
    if ([sender respondsToSelector:@selector(color)])
        [self setColor:[sender color]];
}
- (void)_panelPicked:(NSColor *)color
{
    [self setColor:color];
    ABindingsPush(self, NO);
    [self sendAction:[self action] to:[self target]];
}
- (void)_panelClosed { [self deactivate]; }
- (void)viewWillMoveToWindow:(NSWindow *)window
{
    if (!window)
        [self deactivate];
}

/* ---- the mouse ---- */

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder { return [self isEnabled] && [NSApp isFullKeyboardAccessEnabled]; }
- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    _pressed = YES;
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)event
{
    if (!_pressed && ![self isHighlighted])
        return;
    BOOL inside = NSPointInRect([self convertPoint:[event locationInWindow] fromView:nil], [self bounds]);
    if (inside != _pressed) {
        _pressed = inside;
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseUp:(NSEvent *)event
{
    BOOL inside = NSPointInRect([self convertPoint:[event locationInWindow] fromView:nil], [self bounds]);
    _pressed = NO;
    [self setNeedsDisplay:YES];
    if (!inside || ![self isEnabled])
        return;
    if (_active)
        [self deactivate];
    else
        [self activate:!([event modifierFlags] & NSEventModifierFlagShift)];
}
- (void)keyDown:(NSEvent *)event
{
    NSString *c = [event charactersIgnoringModifiers];
    if ([c isEqualToString:@" "] && [self isEnabled]) {
        if (_active)
            [self deactivate];
        else
            [self activate:YES];
        return;
    }
    [super keyDown:event];
}

/* ---- drawing ---- */

- (NSSize)intrinsicContentSize { return NSMakeSize(44, 23); }
- (void)drawWellInside:(NSRect)rect
{
    CGFloat c[4];
    AColorRGBA(_color, c);
    CGFloat radius = fmin(3, rect.size.height / 2);
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    if (c[3] < 1) {
        /* a colour that isn't opaque: over black and white, cut on the diagonal */
        CGContextSaveGState(cg);
        NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
        [clip addClip];
        [[NSColor whiteColor] setFill];
        NSRectFill(rect);
        NSBezierPath *half = [NSBezierPath bezierPath];
        [half moveToPoint:NSMakePoint(NSMaxX(rect), rect.origin.y)];
        [half lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [half lineToPoint:NSMakePoint(rect.origin.x, NSMaxY(rect))];
        [half closePath];
        [[NSColor blackColor] setFill];
        [half fill];
        CGContextRestoreGState(cg);
    }
    AFillRoundedRect(rect, radius, _color, [NSColor colorWithWhite:0 alpha:0.18]);
}
- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    if (!_bordered || _style == NSColorWellStyleMinimal) {
        [self drawWellInside:NSInsetRect(b, 0.5, 0.5)];
        if (_active)
            AFillRoundedRect(NSInsetRect(b, 1, 1), 3, nil, [NSColor controlAccentColor]);
        return;
    }
    NSRect bezel = NSInsetRect(b, 0.5, 0.5);
    NSColor *face = _pressed ? [NSColor colorWithWhite:0.9 alpha:1] : [NSColor whiteColor];
    AFillRoundedRect(bezel, 5, [face colorWithAlphaComponent:dim],
                     _active ? [NSColor controlAccentColor] : [NSColor colorWithWhite:0 alpha:0.22 * dim]);
    if (_active)
        AFillRoundedRect(NSInsetRect(bezel, 1, 1), 4, nil, [NSColor controlAccentColor]);
    [self drawWellInside:NSInsetRect(b, 4, 4)];
    if ([[self window] firstResponder] == self && [[self window] isKeyWindow])
        AFillRoundedRect(NSInsetRect(bezel, -1.5, -1.5), 6.5, nil, [NSColor keyboardFocusIndicatorColor]);
}
@end
