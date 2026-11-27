/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSComboButton (freemac 1.264, for HandBrake's toolbar), written from
 * Apple's public AppKit documentation. The button is drawn as Ferry's
 * pop-up buttons are: a white rounded bezel, its image and title on the
 * left, and in the split style a thin line and a down chevron at the
 * right end. A click on the main part sends the action; a click on the
 * chevron, or a press held half a second in the unified style, opens the
 * menu under the button. */
#import "AInternal.h"
#import <AppKit/AppKitNewer.h>

#define ARROW_WIDTH 18.0

@implementation NSComboButton {
    NSString *_title;
    NSImage *_image;
    NSImageScaling _imageScaling;
    NSMenu *_comboMenu;
    NSComboButtonStyle _style;
    BOOL _pressedMain, _pressedArrow;
}

+ (instancetype)comboButtonWithTitle:(NSString *)title image:(NSImage *)image menu:(NSMenu *)menu
                              target:(id)target action:(SEL)action
{
    NSComboButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 60, 24)] autorelease];
    b.title = title ?: @"";
    b.image = image;
    b.menu = menu;
    [b setTarget:target];
    [b setAction:action];
    [b setTranslatesAutoresizingMaskIntoConstraints:NO];
    [b setFrameSize:[b intrinsicContentSize]];
    return b;
}
+ (instancetype)comboButtonWithTitle:(NSString *)title menu:(NSMenu *)menu target:(id)target action:(SEL)action
{
    return [self comboButtonWithTitle:title image:nil menu:menu target:target action:action];
}
+ (instancetype)comboButtonWithImage:(NSImage *)image menu:(NSMenu *)menu target:(id)target action:(SEL)action
{
    return [self comboButtonWithTitle:@"" image:image menu:menu target:target action:action];
}

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _title = @"";
        _imageScaling = NSImageScaleProportionallyDown;
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_image release];
    [_comboMenu release];
    [super dealloc];
}

- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t
{
    [_title autorelease];
    _title = [(t ?: @"") copy];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)i
{
    [_image autorelease];
    _image = [i retain];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}
- (NSImageScaling)imageScaling { return _imageScaling; }
- (void)setImageScaling:(NSImageScaling)s
{
    _imageScaling = s;
    [self setNeedsDisplay:YES];
}
- (NSMenu *)menu { return _comboMenu; }
- (void)setMenu:(NSMenu *)m
{
    [_comboMenu autorelease];
    _comboMenu = [m retain];
}
- (NSComboButtonStyle)style { return _style; }
- (void)setStyle:(NSComboButtonStyle)s
{
    _style = s;
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (NSRect)_bezelRect
{
    NSRect b = [self bounds];
    CGFloat h = fmin(b.size.height - 2, 22);
    return NSMakeRect(b.origin.x + 1, round(NSMidY(b) - h / 2), b.size.width - 2, h);
}
- (CGFloat)_arrowWidth { return _style == NSComboButtonStyleSplit ? ARROW_WIDTH : 14; }
- (BOOL)_inArrow:(NSPoint)p { return p.x >= NSMaxX([self _bezelRect]) - [self _arrowWidth]; }

- (NSSize)intrinsicContentSize
{
    CGFloat w = 10;
    if (_image)
        w += fmin([_image size].width, 18) + ([_title length] ? 4 : 0);
    if ([_title length])
        w += ceil(ALineSize(AAttributed(_title, [self font], nil), NULL, NULL).width);
    w += 8 + [self _arrowWidth];
    return NSMakeSize(fmax(w, 40), 24);
}

/* ---- the mouse ---- */

- (void)_openMenu
{
    if (!_comboMenu)
        return;
    _pressedArrow = YES;
    [self setNeedsDisplay:YES];
    NSRect b = [self _bezelRect];
    NSPoint at = NSMakePoint(NSMinX(b), [self isFlipped] ? NSMaxY(b) + 2 : NSMinY(b) - 2);
    [_comboMenu popUpMenuPositioningItem:nil atLocation:at inView:self];
    _pressedArrow = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if ([self _inArrow:p]) {
        [self _openMenu];
        return;
    }
    _pressedMain = YES;
    [self setNeedsDisplay:YES];
    if (_style == NSComboButtonStyleUnified && _comboMenu) {
        /* held for half a second: the menu instead of the action */
        NSEvent *next = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp
                                           untilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]
                                              inMode:NSEventTrackingRunLoopMode
                                             dequeue:YES];
        if (!next) {
            _pressedMain = NO;
            [self _openMenu];
            return;
        }
        [self mouseUp:next];
    }
}
- (void)mouseDragged:(NSEvent *)event
{
    if (!_pressedMain && ![self isHighlighted])
        return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    BOOL inside = [self mouse:p inRect:[self bounds]] && ![self _inArrow:p];
    if (inside != _pressedMain) {
        _pressedMain = inside;
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseUp:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    BOOL send = _pressedMain && [self mouse:p inRect:[self bounds]] && ![self _inArrow:p];
    _pressedMain = NO;
    [self setNeedsDisplay:YES];
    if (send)
        [self sendAction:[self action] to:[self target]];
}
- (void)performClick:(id)sender
{
    if ([self isEnabled])
        [self sendAction:[self action] to:[self target]];
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

/* ---- drawing ---- */

static void down_chevron(NSRect r, NSColor *color, BOOL flipped)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    CGFloat tip = flipped ? NSMaxY(r) : NSMinY(r), base = flipped ? NSMinY(r) : NSMaxY(r);
    [p moveToPoint:NSMakePoint(NSMinX(r), base)];
    [p lineToPoint:NSMakePoint(NSMidX(r), tip)];
    [p lineToPoint:NSMakePoint(NSMaxX(r), base)];
    [p setLineWidth:1.5];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [color setStroke];
    [p stroke];
}

- (void)drawRect:(NSRect)dirty
{
    BOOL enabled = [self isEnabled], dark = AViewIsDark(self);
    CGFloat dim = enabled ? 1 : 0.45;
    NSRect bezel = [self _bezelRect];
    CGFloat aw = [self _arrowWidth];
    NSRect main = NSMakeRect(bezel.origin.x, bezel.origin.y, bezel.size.width - aw, bezel.size.height);
    NSRect arrow = NSMakeRect(NSMaxX(main), bezel.origin.y, aw, bezel.size.height);
    NSColor *fill = dark ? [NSColor colorWithWhite:1 alpha:0.18] : [NSColor whiteColor];
    NSColor *pressed = dark ? [NSColor colorWithWhite:1 alpha:0.3] : [NSColor colorWithWhite:0.86 alpha:1];
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(cg);
    CGColorRef shadow = CGColorCreateGenericRGB(0, 0, 0, 0.12 * dim);
    CGContextSetShadowWithColor(cg, CGSizeMake(0, -0.5), 1, shadow);
    CGColorRelease(shadow);
    AFillRoundedRect(bezel, 5, [fill colorWithAlphaComponent:[fill alphaComponent] * dim], nil);
    CGContextRestoreGState(cg);
    if (_pressedMain || _pressedArrow) {
        CGContextSaveGState(cg);
        CGContextClipToRect(cg, _pressedArrow ? arrow : main);
        AFillRoundedRect(bezel, 5, [pressed colorWithAlphaComponent:[pressed alphaComponent] * dim], nil);
        CGContextRestoreGState(cg);
    }
    AFillRoundedRect(bezel, 5, nil, [NSColor colorWithWhite:dark ? 1 : 0 alpha:(dark ? 0.12 : 0.16) * dim]);
    NSColor *ink = [NSColor colorWithWhite:dark ? 1 : 0 alpha:(dark ? 0.9 : 0.85) * dim];
    if (_style == NSComboButtonStyleSplit) {
        [[NSColor colorWithWhite:dark ? 1 : 0 alpha:0.15 * dim] setFill];
        NSRectFill(NSMakeRect(NSMinX(arrow), NSMinY(arrow) + 4, 1, arrow.size.height - 8));
    }
    down_chevron(NSMakeRect(NSMidX(arrow) - 3.5, NSMidY(arrow) - 1.75, 7, 3.5), ink, [self isFlipped]);

    /* the image and the title, centred in the main part */
    NSAttributedString *t = [_title length] ? AAttributed(_title, [self font], ink) : nil;
    CGFloat a = 0, d = 0, tw = t ? ALineSize(t, &a, &d).width : 0;
    NSSize is = NSZeroSize;
    if (_image) {
        NSSize s = [_image size];
        CGFloat k = _imageScaling == NSImageScaleNone ? 1 : fmin(1, fmin(18 / fmax(s.width, 1), 16 / fmax(s.height, 1)));
        is = NSMakeSize(s.width * k, s.height * k);
    }
    CGFloat total = is.width + (is.width && tw ? 4 : 0) + tw;
    CGFloat x = round(NSMidX(main) - total / 2 + 2);
    if (_image) {
        NSRect ir = NSMakeRect(x, round(NSMidY(main) - is.height / 2), is.width, is.height);
        [_image _drawInControlRect:ir color:ink fraction:dim];
        x += is.width + 4;
    }
    if (t) {
        CGFloat baseline =
            [self isFlipped] ? ceil(NSMidY(main) + (a + d) / 2 - d) : floor(NSMidY(main) - (a + d) / 2 + d);
        ADrawLine(t, x, baseline);
    }
}
@end
