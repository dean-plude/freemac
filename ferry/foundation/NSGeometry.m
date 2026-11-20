/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: the NSGeometry calls. On a 64-bit Mac NSPoint, NSSize
 * and NSRect are Core Graphics' CGPoint, CGSize and CGRect, so these work on
 * the same structures; they are written here so that Foundation doesn't need
 * Core Graphics. Strings look like a Mac's: "{{0, 0}, {100, 50}}". */
#import "FInternal.h"

F_EXPORT const NSPoint NSZeroPoint = {0, 0};
F_EXPORT const NSSize NSZeroSize = {0, 0};
F_EXPORT const NSRect NSZeroRect = {{0, 0}, {0, 0}};
F_EXPORT const NSEdgeInsets NSEdgeInsetsZero = {0, 0, 0, 0};

BOOL NSEqualPoints(NSPoint a, NSPoint b) { return a.x == b.x && a.y == b.y; }
BOOL NSEqualSizes(NSSize a, NSSize b) { return a.width == b.width && a.height == b.height; }
BOOL NSEqualRects(NSRect a, NSRect b) { return NSEqualPoints(a.origin, b.origin) && NSEqualSizes(a.size, b.size); }
BOOL NSIsEmptyRect(NSRect r) { return !(r.size.width > 0 && r.size.height > 0); }

NSRect NSInsetRect(NSRect r, CGFloat dx, CGFloat dy)
{
    return NSMakeRect(r.origin.x + dx, r.origin.y + dy, r.size.width - 2 * dx, r.size.height - 2 * dy);
}

NSRect NSOffsetRect(NSRect r, CGFloat dx, CGFloat dy)
{
    return NSMakeRect(r.origin.x + dx, r.origin.y + dy, r.size.width, r.size.height);
}

/* The smallest whole-number rectangle that holds r; empty stays empty. */
NSRect NSIntegralRect(NSRect r)
{
    if (NSIsEmptyRect(r))
        return NSZeroRect;
    CGFloat x = floor(NSMinX(r)), y = floor(NSMinY(r));
    return NSMakeRect(x, y, ceil(NSMaxX(r)) - x, ceil(NSMaxY(r)) - y);
}

NSRect NSUnionRect(NSRect a, NSRect b)
{
    if (NSIsEmptyRect(a))
        return NSIsEmptyRect(b) ? NSZeroRect : b;
    if (NSIsEmptyRect(b))
        return a;
    CGFloat x = fmin(NSMinX(a), NSMinX(b)), y = fmin(NSMinY(a), NSMinY(b));
    return NSMakeRect(x, y, fmax(NSMaxX(a), NSMaxX(b)) - x, fmax(NSMaxY(a), NSMaxY(b)) - y);
}

NSRect NSIntersectionRect(NSRect a, NSRect b)
{
    CGFloat x = fmax(NSMinX(a), NSMinX(b)), y = fmax(NSMinY(a), NSMinY(b));
    CGFloat w = fmin(NSMaxX(a), NSMaxX(b)) - x, h = fmin(NSMaxY(a), NSMaxY(b)) - y;
    if (w <= 0 || h <= 0)
        return NSZeroRect;
    return NSMakeRect(x, y, w, h);
}

void NSDivideRect(NSRect r, NSRect *slice, NSRect *remainder, CGFloat amount, NSRectEdge edge)
{
    NSRect s = r, rest = r;
    BOOL horizontal = edge == NSMinXEdge || edge == NSMaxXEdge;
    CGFloat whole = horizontal ? r.size.width : r.size.height;
    if (amount > whole)
        amount = whole;
    if (amount < 0)
        amount = 0;
    if (horizontal) {
        s.size.width = amount;
        rest.size.width = whole - amount;
        if (edge == NSMinXEdge)
            rest.origin.x += amount;
        else
            s.origin.x = NSMaxX(r) - amount;
    } else {
        s.size.height = amount;
        rest.size.height = whole - amount;
        if (edge == NSMinYEdge)
            rest.origin.y += amount;
        else
            s.origin.y = NSMaxY(r) - amount;
    }
    if (slice)
        *slice = s;
    if (remainder)
        *remainder = rest;
}

BOOL NSPointInRect(NSPoint p, NSRect r) { return NSMouseInRect(p, r, YES); }

/* The rectangle's top edge counts in a flipped view, its bottom edge in an
 * unflipped one: the edge nearer the origin, as a pixel would be. */
BOOL NSMouseInRect(NSPoint p, NSRect r, BOOL flipped)
{
    if (NSIsEmptyRect(r) || p.x < NSMinX(r) || p.x >= NSMaxX(r))
        return NO;
    if (flipped)
        return p.y >= NSMinY(r) && p.y < NSMaxY(r);
    return p.y > NSMinY(r) && p.y <= NSMaxY(r);
}

BOOL NSContainsRect(NSRect a, NSRect b)
{
    return !NSIsEmptyRect(b) && NSMinX(b) >= NSMinX(a) && NSMinY(b) >= NSMinY(a) && NSMaxX(b) <= NSMaxX(a) &&
           NSMaxY(b) <= NSMaxY(a);
}

BOOL NSIntersectsRect(NSRect a, NSRect b) { return !NSIsEmptyRect(NSIntersectionRect(a, b)); }

NSString *NSStringFromPoint(NSPoint p) { return [NSString stringWithFormat:@"{%g, %g}", p.x, p.y]; }
NSString *NSStringFromSize(NSSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
NSString *NSStringFromRect(NSRect r)
{
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

/* Reads up to n numbers from a string, skipping anything else, as the Mac
 * calls are forgiving about braces and spaces. */
static int numbers(NSString *s, double *out, int n)
{
    const char *p = [s UTF8String];
    int got = 0;
    while (p && *p && got < n) {
        char *end;
        double v = strtod(p, &end);
        if (end != p) {
            out[got++] = v;
            p = end;
        } else {
            p++;
        }
    }
    return got;
}

NSPoint NSPointFromString(NSString *s)
{
    double v[2] = {0, 0};
    numbers(s, v, 2);
    return NSMakePoint(v[0], v[1]);
}

NSSize NSSizeFromString(NSString *s)
{
    double v[2] = {0, 0};
    numbers(s, v, 2);
    return NSMakeSize(v[0], v[1]);
}

NSRect NSRectFromString(NSString *s)
{
    double v[4] = {0, 0, 0, 0};
    numbers(s, v, 4);
    return NSMakeRect(v[0], v[1], v[2], v[3]);
}
