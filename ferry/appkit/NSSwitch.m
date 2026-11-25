/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSSwitch (freemac 1.231), written from Apple's public
 * API documentation. A switch is on or off; a click, or Space with the
 * keyboard, turns it the other way and sends the action. Ferry draws it
 * its own way: a pill, filled with the accent colour when on and grey when
 * off, with a white knob at the end it is turned to. SwiftUI's switch
 * toggle style shows one. */
#import "AInternal.h"

@implementation NSSwitch {
    NSControlStateValue _state;
    BOOL _pressed;
}

- (NSControlStateValue)state { return _state; }
- (void)setState:(NSControlStateValue)state
{
    state = state == NSControlStateValueOff ? NSControlStateValueOff : NSControlStateValueOn;
    if (state == _state)
        return;
    _state = state;
    [self setNeedsDisplay:YES];
}
- (id)objectValue { return @(_state); }
- (void)setObjectValue:(id)value { [self setState:[value integerValue]]; }
- (NSInteger)integerValue { return _state; }
- (void)setIntegerValue:(NSInteger)v { [self setState:v]; }
- (int)intValue { return (int)_state; }
- (void)setIntValue:(int)v { [self setState:v]; }
- (double)doubleValue { return _state; }
- (void)setDoubleValue:(double)v { [self setState:v != 0]; }
- (BOOL)acceptsFirstResponder { return [self isEnabled]; }
- (NSString *)accessibilityRole { return NSAccessibilityCheckBoxRole; }

- (void)_toggle
{
    [self setState:_state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn];
    ABindingsPush(self, NO);
    [self sendAction:[self action] to:[self target]];
}
- (void)performClick:(id)sender
{
    if ([self isEnabled])
        [self _toggle];
}
- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    _pressed = YES;
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)event
{
    if (!_pressed)
        return;
    _pressed = NO;
    if (NSPointInRect([self convertPoint:[event locationInWindow] fromView:nil], [self bounds]))
        [self _toggle];
    else
        [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent *)event
{
    if ([self isEnabled] && [[event charactersIgnoringModifiers] isEqualToString:@" "])
        [self _toggle];
    else
        [super keyDown:event];
}

/* ---- drawing ---- */

- (NSSize)intrinsicContentSize
{
    switch ([self controlSize]) {
    case NSControlSizeMini: return NSMakeSize(26, 15);
    case NSControlSizeSmall: return NSMakeSize(32, 18);
    default: return NSMakeSize(38, 22);
    }
}
- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    NSSize want = [self intrinsicContentSize];
    CGFloat h = fmin(b.size.height, want.height), w = fmin(b.size.width, fmax(want.width, h * 1.7));
    NSRect pill = NSMakeRect(round(NSMidX(b) - w / 2), round(NSMidY(b) - h / 2), w, h);
    CGFloat dim = [self isEnabled] ? 1 : 0.45;
    BOOL on = _state == NSControlStateValueOn;
    NSColor *track = on ? [NSColor controlAccentColor] : [NSColor colorWithWhite:0.82 alpha:1];
    if (_pressed)
        track = [track shadowWithLevel:0.15];
    AFillRoundedRect(pill, h / 2, [track colorWithAlphaComponent:dim], [NSColor colorWithWhite:0 alpha:0.12 * dim]);
    CGFloat d = h - 4;
    NSRect knob = NSMakeRect(on ? NSMaxX(pill) - 2 - d : NSMinX(pill) + 2, NSMinY(pill) + 2, d, d);
    AFillRoundedRect(knob, d / 2, [NSColor colorWithWhite:1 alpha:dim], [NSColor colorWithWhite:0 alpha:0.18 * dim]);
    if ([[self window] firstResponder] == self && [[self window] isKeyWindow])
        AFillRoundedRect(NSInsetRect(pill, -2.5, -2.5), h / 2 + 2.5, nil, [NSColor keyboardFocusIndicatorColor]);
}
@end
