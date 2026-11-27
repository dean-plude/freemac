/* SPDX-License-Identifier: GPL-3.0-or-later
 * The parts of HIToolbox (Carbon) that wxWidgets' Cocoa port still calls,
 * for Audacity (freemac 1.263, Ferry 0.86.0), served from AppKit's file as
 * the rest of Carbon is. Written from Apple's public documentation of each
 * call (HIShape, HITheme, Appearance Manager metrics, Event Loop).
 *
 * - HIShape: an area made of rectangles, which wxWidgets uses for every
 *   region (clipping, repainting, window shapes). A shape keeps a list of
 *   rectangles that don't overlap; union, intersection, difference and
 *   exclusive-or work on that list, and the shape can be walked rectangle by
 *   rectangle or added to a drawing context as a path.
 * - HITheme drawing: buttons, check boxes, radio buttons, disclosure
 *   triangles, list headers, frames, focus rings, pane splitters and tracks,
 *   drawn with Core Graphics in freemac's own light look rather than Aqua's
 *   artwork, which only a Mac has.
 * - GetThemeMetric: the sizes Aqua's controls have, as documented.
 * - GetCurrentEventLoop and GetCFRunLoopFromEventLoop: the main run loop.
 * - SetSystemUIMode: accepted (the menu bar and Dock stay as they are). */
#import "AInternal.h"
#include <math.h>

typedef int32_t HIOSStatus;
enum { kHINoErr = 0, kHIParamErr = -50 };

/* ---- HIShape ------------------------------------------------------------------- */

@interface FerryHIShape : NSObject <NSCopying> {
@public
    CGRect *rects;
    size_t count, cap;
    BOOL mutableShape;
}
@end

@implementation FerryHIShape
- (void)dealloc
{
    free(rects);
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    FerryHIShape *c = [[FerryHIShape alloc] init];
    if (count) {
        c->rects = malloc(count * sizeof *rects);
        memcpy(c->rects, rects, count * sizeof *rects);
        c->count = c->cap = count;
    }
    return c;
}
- (NSString *)description { return [NSString stringWithFormat:@"<HIShape: %zu rectangles>", count]; }
@end

static FerryHIShape *SH(const void *s) { return (FerryHIShape *)s; }

static void push(FerryHIShape *s, CGRect r)
{
    if (r.size.width <= 0 || r.size.height <= 0)
        return;
    if (s->count == s->cap) {
        s->cap = s->cap ? s->cap * 2 : 8;
        s->rects = realloc(s->rects, s->cap * sizeof *s->rects);
    }
    s->rects[s->count++] = r;
}

static void clear(FerryHIShape *s) { s->count = 0; }

static CGRect normal(CGRect r) { return CGRectStandardize(r); }

/* a minus b, as up to four rectangles, added to out */
static void subtract_rect(CGRect a, CGRect b, FerryHIShape *out)
{
    CGRect i = CGRectIntersection(a, b);
    if (CGRectIsNull(i) || i.size.width <= 0 || i.size.height <= 0) {
        push(out, a);
        return;
    }
    CGFloat ax0 = CGRectGetMinX(a), ax1 = CGRectGetMaxX(a), ay0 = CGRectGetMinY(a), ay1 = CGRectGetMaxY(a);
    CGFloat ix0 = CGRectGetMinX(i), ix1 = CGRectGetMaxX(i), iy0 = CGRectGetMinY(i), iy1 = CGRectGetMaxY(i);
    push(out, CGRectMake(ax0, ay0, ax1 - ax0, iy0 - ay0));          /* the band before */
    push(out, CGRectMake(ax0, iy1, ax1 - ax0, ay1 - iy1));          /* the band after */
    push(out, CGRectMake(ax0, iy0, ix0 - ax0, iy1 - iy0));          /* left of it */
    push(out, CGRectMake(ix1, iy0, ax1 - ix1, iy1 - iy0));          /* right of it */
}

/* rectangles of a not in b */
static void difference_into(const FerryHIShape *a, const FerryHIShape *b, FerryHIShape *out)
{
    FerryHIShape *cur = [a copy];
    for (size_t j = 0; j < b->count; j++) {
        FerryHIShape *next = [[FerryHIShape alloc] init];
        for (size_t k = 0; k < cur->count; k++)
            subtract_rect(cur->rects[k], b->rects[j], next);
        [cur release];
        cur = next;
    }
    clear(out);
    for (size_t k = 0; k < cur->count; k++)
        push(out, cur->rects[k]);
    [cur release];
}

static void intersection_into(const FerryHIShape *a, const FerryHIShape *b, FerryHIShape *out)
{
    FerryHIShape *tmp = [[FerryHIShape alloc] init];
    for (size_t i = 0; i < a->count; i++)
        for (size_t j = 0; j < b->count; j++)
            push(tmp, CGRectIntersection(a->rects[i], b->rects[j]));
    clear(out);
    for (size_t k = 0; k < tmp->count; k++)
        push(out, tmp->rects[k]);
    [tmp release];
}

/* Joins rectangles that share a whole edge, so shapes built a piece at a
 * time stay small. */
static void coalesce(FerryHIShape *s)
{
    BOOL merged = YES;
    while (merged && s->count > 1) {
        merged = NO;
        for (size_t i = 0; i < s->count && !merged; i++)
            for (size_t j = i + 1; j < s->count && !merged; j++) {
                CGRect a = s->rects[i], b = s->rects[j], m = CGRectNull;
                if (a.origin.y == b.origin.y && a.size.height == b.size.height &&
                    (CGRectGetMaxX(a) == b.origin.x || CGRectGetMaxX(b) == a.origin.x))
                    m = CGRectUnion(a, b);
                else if (a.origin.x == b.origin.x && a.size.width == b.size.width &&
                         (CGRectGetMaxY(a) == b.origin.y || CGRectGetMaxY(b) == a.origin.y))
                    m = CGRectUnion(a, b);
                if (!CGRectIsNull(m)) {
                    s->rects[i] = m;
                    s->rects[j] = s->rects[--s->count];
                    merged = YES;
                }
            }
    }
}

static void union_into(const FerryHIShape *a, const FerryHIShape *b, FerryHIShape *out)
{
    FerryHIShape *extra = [[FerryHIShape alloc] init];
    difference_into(b, a, extra);
    FerryHIShape *tmp = [a copy];
    for (size_t k = 0; k < extra->count; k++)
        push(tmp, extra->rects[k]);
    coalesce(tmp);
    clear(out);
    for (size_t k = 0; k < tmp->count; k++)
        push(out, tmp->rects[k]);
    [tmp release];
    [extra release];
}

static void xor_into(const FerryHIShape *a, const FerryHIShape *b, FerryHIShape *out)
{
    FerryHIShape *ab = [[FerryHIShape alloc] init], *ba = [[FerryHIShape alloc] init];
    difference_into(a, b, ab);
    difference_into(b, a, ba);
    for (size_t k = 0; k < ba->count; k++)
        push(ab, ba->rects[k]);
    coalesce(ab);
    clear(out);
    for (size_t k = 0; k < ab->count; k++)
        push(out, ab->rects[k]);
    [ab release];
    [ba release];
}

static FerryHIShape *empty_shape(BOOL isMutable)
{
    FerryHIShape *s = [[FerryHIShape alloc] init];
    s->mutableShape = isMutable;
    return s;
}

CFTypeID HIShapeGetTypeID(void) { return (CFTypeID)(uintptr_t)[FerryHIShape class]; }
const void *HIShapeCreateEmpty(void) { return empty_shape(NO); }
void *HIShapeCreateMutable(void) { return empty_shape(YES); }

const void *HIShapeCreateWithRect(const CGRect *r)
{
    FerryHIShape *s = empty_shape(NO);
    if (r)
        push(s, normal(*r));
    return s;
}

void *HIShapeCreateMutableWithRect(const CGRect *r)
{
    FerryHIShape *s = (FerryHIShape *)HIShapeCreateWithRect(r);
    s->mutableShape = YES;
    return s;
}

const void *HIShapeCreateCopy(const void *shape)
{
    FerryHIShape *s = shape ? [SH(shape) copy] : empty_shape(NO);
    s->mutableShape = NO;
    return s;
}

void *HIShapeCreateMutableCopy(const void *shape)
{
    FerryHIShape *s = shape ? [SH(shape) copy] : empty_shape(YES);
    s->mutableShape = YES;
    return s;
}

static const FerryHIShape *or_empty(const void *s)
{
    static FerryHIShape *none;
    if (!none)
        none = empty_shape(NO);
    return s ? SH(s) : none;
}

const void *HIShapeCreateIntersection(const void *a, const void *b)
{
    FerryHIShape *s = empty_shape(NO);
    intersection_into(or_empty(a), or_empty(b), s);
    return s;
}
const void *HIShapeCreateDifference(const void *a, const void *b)
{
    FerryHIShape *s = empty_shape(NO);
    difference_into(or_empty(a), or_empty(b), s);
    return s;
}
const void *HIShapeCreateUnion(const void *a, const void *b)
{
    FerryHIShape *s = empty_shape(NO);
    union_into(or_empty(a), or_empty(b), s);
    return s;
}
const void *HIShapeCreateXor(const void *a, const void *b)
{
    FerryHIShape *s = empty_shape(NO);
    xor_into(or_empty(a), or_empty(b), s);
    return s;
}

HIOSStatus HIShapeIntersect(const void *a, const void *b, void *out)
{
    if (!out)
        return kHIParamErr;
    intersection_into(or_empty(a), or_empty(b), SH(out));
    return kHINoErr;
}
HIOSStatus HIShapeDifference(const void *a, const void *b, void *out)
{
    if (!out)
        return kHIParamErr;
    difference_into(or_empty(a), or_empty(b), SH(out));
    return kHINoErr;
}
HIOSStatus HIShapeUnion(const void *a, const void *b, void *out)
{
    if (!out)
        return kHIParamErr;
    union_into(or_empty(a), or_empty(b), SH(out));
    return kHINoErr;
}
HIOSStatus HIShapeXor(const void *a, const void *b, void *out)
{
    if (!out)
        return kHIParamErr;
    xor_into(or_empty(a), or_empty(b), SH(out));
    return kHINoErr;
}

HIOSStatus HIShapeUnionWithRect(void *shape, const CGRect *r)
{
    if (!shape || !r)
        return kHIParamErr;
    FerryHIShape *one = (FerryHIShape *)HIShapeCreateWithRect(r);
    union_into(SH(shape), one, SH(shape));
    [one release];
    return kHINoErr;
}

HIOSStatus HIShapeSetEmpty(void *shape)
{
    if (!shape)
        return kHIParamErr;
    clear(SH(shape));
    return kHINoErr;
}

HIOSStatus HIShapeSetWithShape(void *dst, const void *src)
{
    if (!dst)
        return kHIParamErr;
    if (dst == src)
        return kHINoErr;
    clear(SH(dst));
    const FerryHIShape *s = or_empty(src);
    for (size_t k = 0; k < s->count; k++)
        push(SH(dst), s->rects[k]);
    return kHINoErr;
}

HIOSStatus HIShapeOffset(void *shape, CGFloat dx, CGFloat dy)
{
    if (!shape)
        return kHIParamErr;
    for (size_t k = 0; k < SH(shape)->count; k++)
        SH(shape)->rects[k] = CGRectOffset(SH(shape)->rects[k], dx, dy);
    return kHINoErr;
}

HIOSStatus HIShapeInset(void *shape, CGFloat dx, CGFloat dy)
{
    if (!shape)
        return kHIParamErr;
    /* each rectangle inset; right for the rectangles wxWidgets insets */
    FerryHIShape *s = SH(shape);
    size_t n = s->count;
    CGRect *old = malloc(n * sizeof *old);
    memcpy(old, s->rects, n * sizeof *old);
    clear(s);
    for (size_t k = 0; k < n; k++)
        push(s, CGRectInset(old[k], dx, dy));
    free(old);
    return kHINoErr;
}

Boolean HIShapeIsEmpty(const void *shape) { return !shape || SH(shape)->count == 0; }

Boolean HIShapeIsRectangular(const void *shape)
{
    if (!shape)
        return true;
    FerryHIShape *s = SH(shape);
    coalesce(s);
    return s->count <= 1;
}

CGRect *HIShapeGetBounds(const void *shape, CGRect *out)
{
    if (!out)
        return NULL;
    CGRect b = CGRectNull;
    if (shape)
        for (size_t k = 0; k < SH(shape)->count; k++)
            b = CGRectUnion(b, SH(shape)->rects[k]);
    *out = CGRectIsNull(b) ? CGRectZero : b;
    return out;
}

Boolean HIShapeContainsPoint(const void *shape, const CGPoint *p)
{
    if (!shape || !p)
        return false;
    for (size_t k = 0; k < SH(shape)->count; k++)
        if (CGRectContainsPoint(SH(shape)->rects[k], *p))
            return true;
    return false;
}

Boolean HIShapeIntersectsRect(const void *shape, const CGRect *r)
{
    if (!shape || !r)
        return false;
    for (size_t k = 0; k < SH(shape)->count; k++)
        if (CGRectIntersectsRect(SH(shape)->rects[k], *r))
            return true;
    return false;
}

HIOSStatus HIShapeReplacePathInCGContext(const void *shape, CGContextRef ctx)
{
    if (!ctx)
        return kHIParamErr;
    CGContextBeginPath(ctx);
    if (shape && SH(shape)->count)
        CGContextAddRects(ctx, SH(shape)->rects, SH(shape)->count);
    return kHINoErr;
}

/* the walk's messages and orders */
enum { kHIShapeEnumerateInit = 1, kHIShapeEnumerateRect = 2, kHIShapeEnumerateTerminate = 3 };
enum { kHIShapeParseFromTop = 0, kHIShapeParseFromBottom = 1 << 0, kHIShapeParseFromLeft = 0,
       kHIShapeParseFromRight = 1 << 1 };
typedef HIOSStatus (*HIShapeEnumerateProc)(int message, const void *shape, const CGRect *rect, void *refcon);

static OptionBits walk_order;
static int by_order(const void *pa, const void *pb)
{
    const CGRect *a = pa, *b = pb;
    CGFloat dy = a->origin.y - b->origin.y, dx = a->origin.x - b->origin.x;
    if (walk_order & kHIShapeParseFromBottom)
        dy = -dy;
    if (walk_order & kHIShapeParseFromRight)
        dx = -dx;
    if (dy)
        return dy < 0 ? -1 : 1;
    return dx < 0 ? -1 : dx > 0;
}

HIOSStatus HIShapeEnumerate(const void *shape, OptionBits options, HIShapeEnumerateProc proc, void *refcon)
{
    if (!proc)
        return kHIParamErr;
    const FerryHIShape *s = or_empty(shape);
    size_t n = s->count;
    CGRect *sorted = malloc((n ? n : 1) * sizeof *sorted);
    if (n)
        memcpy(sorted, s->rects, n * sizeof *sorted);
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    walk_order = options;
    qsort(sorted, n, sizeof *sorted, by_order);
    pthread_mutex_unlock(&lock);
    HIOSStatus rc = proc(kHIShapeEnumerateInit, shape, NULL, refcon);
    for (size_t k = 0; k < n && rc == kHINoErr; k++)
        rc = proc(kHIShapeEnumerateRect, shape, &sorted[k], refcon);
    proc(kHIShapeEnumerateTerminate, shape, NULL, refcon);
    free(sorted);
    return rc;
}

/* ---- HITheme drawing ------------------------------------------------------------- */

enum { kThemeStateInactive = 0, kThemeStateActive = 1, kThemeStatePressed = 2, kThemeStateUnavailable = 7,
       kThemeStateUnavailableInactive = 8 };
enum { kThemeButtonOff = 0, kThemeButtonOn = 1, kThemeButtonMixed = 2 };
enum {
    kThemePushButton = 0, kThemeCheckBox = 1, kThemeRadioButton = 2, kThemeBevelButton = 3, kThemeArrowButton = 4,
    kThemePopupButton = 5, kThemeDisclosureButton = 6, kThemeIncDecButton = 7, kThemeSmallBevelButton = 8,
    kThemeLargeBevelButton = 9, kThemeListHeaderButton = 10, kThemeRoundButton = 11, kThemeLargeRoundButton = 12,
    kThemeSmallCheckBox = 13, kThemeSmallRadioButton = 14, kThemeRoundedBevelButton = 15, kThemeComboBox = 16,
    kThemeComboBoxSmall = 17, kThemeComboBoxMini = 18, kThemeMiniCheckBox = 19, kThemeMiniRadioButton = 20,
    kThemeIncDecButtonSmall = 21, kThemeIncDecButtonMini = 22, kThemeArrowButtonSmall = 23,
    kThemeArrowButtonMini = 24, kThemePushButtonNormal = 25, kThemePushButtonSmall = 26, kThemePushButtonMini = 27,
    kThemePopupButtonNormal = 28, kThemePopupButtonSmall = 29, kThemePopupButtonMini = 30,
    kThemeBevelButtonInset = 31, kThemeRoundButtonHelp = 32,
};
enum { kThemeDisclosureRight = 0, kThemeDisclosureDown = 1, kThemeDisclosureLeft = 2 };
enum { kThemeAdornmentFocus = 1 << 2, kThemeAdornmentDefault = 1 << 0, kThemeAdornmentHeaderButtonSortUp = 1 << 5,
       kThemeAdornmentArrowDownArrow = 1 << 7, kThemeAdornmentArrowUpArrow = 1 << 6 };

/* The button's description, laid out as HITheme documents it. */
typedef struct {
    uint32_t version;
    uint32_t state;
    uint16_t kind;
    uint16_t value;
    uint16_t adornment;
    /* the animation's start and current time follow; not used here */
} FerryThemeButtonDrawInfo;

typedef struct {
    uint32_t version;
    uint32_t state;
    uint16_t kind; /* kHIThemeFrameTextFieldSquare 0, ListBox 1 */
    uint8_t isFocused;
} FerryThemeFrameDrawInfo;

typedef struct {
    uint32_t version;
    uint32_t state;
    uint32_t kind; /* ThemeBackgroundKind */
} FerryThemeBackgroundDrawInfo;

static CGColorRef rgb(CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
    return [[NSColor colorWithSRGBRed:r green:g blue:b alpha:a] CGColor];
}

static BOOL dark_look(void)
{
    NSString *name = [[NSApp effectiveAppearance] bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
    ]];
    return [name isEqualToString:NSAppearanceNameDarkAqua];
}

static CGColorRef accent(void) { return [[NSColor controlAccentColor] CGColor]; }
static CGColorRef face(BOOL pressed)
{
    if (dark_look())
        return pressed ? rgb(0.42, 0.42, 0.44, 1) : rgb(0.36, 0.36, 0.38, 1);
    return pressed ? rgb(0.86, 0.86, 0.87, 1) : rgb(1, 1, 1, 1);
}
static CGColorRef edge(void) { return dark_look() ? rgb(0.5, 0.5, 0.52, 1) : rgb(0.70, 0.70, 0.72, 1); }
static CGColorRef ink(BOOL enabled)
{
    if (dark_look())
        return enabled ? rgb(0.92, 0.92, 0.92, 1) : rgb(0.55, 0.55, 0.55, 1);
    return enabled ? rgb(0.15, 0.15, 0.16, 1) : rgb(0.6, 0.6, 0.6, 1);
}

static void round_rect(CGContextRef c, CGRect r, CGFloat radius)
{
    CGPathRef p = CGPathCreateWithRoundedRect(r, MIN(radius, r.size.width / 2), MIN(radius, r.size.height / 2),
                                              NULL);
    CGContextAddPath(c, p);
    CGPathRelease(p);
}

static void filled_box(CGContextRef c, CGRect r, CGFloat radius, CGColorRef fill, CGColorRef stroke)
{
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, fill);
    round_rect(c, r, radius);
    CGContextFillPath(c);
    if (stroke) {
        CGContextSetStrokeColorWithColor(c, stroke);
        CGContextSetLineWidth(c, 1);
        round_rect(c, CGRectInset(r, 0.5, 0.5), radius);
        CGContextStrokePath(c);
    }
    CGContextRestoreGState(c);
}

/* a triangle pointing right (0), down (1), left (2) or up (3), filling r */
static void triangle(CGContextRef c, CGRect r, int way, CGColorRef color)
{
    CGFloat s = MIN(r.size.width, r.size.height) * 0.5;
    CGFloat cx = CGRectGetMidX(r), cy = CGRectGetMidY(r);
    CGPoint p[3];
    switch (way) {
    case 0: p[0] = CGPointMake(cx - s / 2, cy - s / 2); p[1] = CGPointMake(cx + s / 2, cy); p[2] = CGPointMake(cx - s / 2, cy + s / 2); break;
    case 2: p[0] = CGPointMake(cx + s / 2, cy - s / 2); p[1] = CGPointMake(cx - s / 2, cy); p[2] = CGPointMake(cx + s / 2, cy + s / 2); break;
    case 1: p[0] = CGPointMake(cx - s / 2, cy - s / 3); p[1] = CGPointMake(cx + s / 2, cy - s / 3); p[2] = CGPointMake(cx, cy + s / 2); break;
    default: p[0] = CGPointMake(cx - s / 2, cy + s / 3); p[1] = CGPointMake(cx + s / 2, cy + s / 3); p[2] = CGPointMake(cx, cy - s / 2); break;
    }
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, color);
    CGContextAddLines(c, p, 3);
    CGContextClosePath(c);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
}

static BOOL flipped(CGContextRef c)
{
    /* HITheme draws into a context whose y axis runs down (an HIView's);
     * a disclosure triangle pointing down needs to know */
    CGAffineTransform t = CGContextGetCTM(c);
    return t.d < 0;
}

HIOSStatus HIThemeDrawButton(const CGRect *bounds, const void *info, CGContextRef c, uint32_t orientation,
                             CGRect *labelRect)
{
    if (!bounds || !info || !c)
        return kHIParamErr;
    const FerryThemeButtonDrawInfo *d = info;
    CGRect r = CGRectStandardize(*bounds);
    BOOL pressed = d->state == kThemeStatePressed;
    BOOL enabled = d->state != kThemeStateUnavailable && d->state != kThemeStateUnavailableInactive &&
                   d->state != kThemeStateInactive;
    if (labelRect)
        *labelRect = CGRectInset(r, 4, 2);
    switch (d->kind) {
    case kThemeCheckBox:
    case kThemeSmallCheckBox:
    case kThemeMiniCheckBox: {
        CGFloat s = MIN(MIN(r.size.width, r.size.height), d->kind == kThemeCheckBox ? 14 : 12);
        CGRect box = CGRectMake(CGRectGetMinX(r) + 1, CGRectGetMidY(r) - s / 2, s, s);
        BOOL on = d->value != kThemeButtonOff;
        filled_box(c, box, 3, on ? accent() : face(pressed), on ? NULL : edge());
        if (on) {
            CGContextSaveGState(c);
            CGContextSetStrokeColorWithColor(c, rgb(1, 1, 1, 1));
            CGContextSetLineWidth(c, 1.8);
            CGContextSetLineCap(c, kCGLineCapRound);
            BOOL up = flipped(c);
            CGFloat x = box.origin.x, y = box.origin.y;
            if (d->value == kThemeButtonMixed) {
                CGContextMoveToPoint(c, x + s * 0.25, y + s / 2);
                CGContextAddLineToPoint(c, x + s * 0.75, y + s / 2);
            } else {
                CGFloat y1 = up ? 0.52 : 0.48, y2 = up ? 0.75 : 0.25, y3 = up ? 0.28 : 0.72;
                CGContextMoveToPoint(c, x + s * 0.24, y + s * y1);
                CGContextAddLineToPoint(c, x + s * 0.42, y + s * y2);
                CGContextAddLineToPoint(c, x + s * 0.78, y + s * y3);
            }
            CGContextStrokePath(c);
            CGContextRestoreGState(c);
        }
        if (labelRect)
            *labelRect = CGRectMake(CGRectGetMaxX(box) + 4, r.origin.y, MAX(0, CGRectGetMaxX(r) - CGRectGetMaxX(box) - 4),
                                    r.size.height);
        break;
    }
    case kThemeRadioButton:
    case kThemeSmallRadioButton:
    case kThemeMiniRadioButton: {
        CGFloat s = MIN(MIN(r.size.width, r.size.height), d->kind == kThemeRadioButton ? 14 : 12);
        CGRect dot = CGRectMake(CGRectGetMinX(r) + 1, CGRectGetMidY(r) - s / 2, s, s);
        BOOL on = d->value != kThemeButtonOff;
        filled_box(c, dot, s / 2, on ? accent() : face(pressed), on ? NULL : edge());
        if (on)
            filled_box(c, CGRectInset(dot, s * 0.32, s * 0.32), s, rgb(1, 1, 1, 1), NULL);
        break;
    }
    case kThemeDisclosureButton: {
        int way = d->value == kThemeDisclosureDown ? (flipped(c) ? 1 : 3)
                  : d->value == kThemeDisclosureLeft ? 2 : 0;
        triangle(c, r, way, ink(enabled));
        break;
    }
    case kThemeArrowButton:
    case kThemeArrowButtonSmall:
    case kThemeArrowButtonMini: {
        filled_box(c, r, 4, face(pressed), edge());
        BOOL down = !(d->adornment & kThemeAdornmentArrowUpArrow);
        triangle(c, CGRectInset(r, r.size.width * 0.2, r.size.height * 0.2), down == flipped(c) ? 1 : 3, ink(enabled));
        break;
    }
    case kThemeListHeaderButton: {
        CGContextSaveGState(c);
        CGContextSetFillColorWithColor(c, face(pressed));
        CGContextFillRect(c, r);
        CGContextSetStrokeColorWithColor(c, edge());
        CGContextSetLineWidth(c, 1);
        CGContextMoveToPoint(c, CGRectGetMaxX(r) - 0.5, CGRectGetMinY(r) + 3);
        CGContextAddLineToPoint(c, CGRectGetMaxX(r) - 0.5, CGRectGetMaxY(r) - 3);
        CGFloat bottom = flipped(c) ? CGRectGetMaxY(r) - 0.5 : CGRectGetMinY(r) + 0.5;
        CGContextMoveToPoint(c, CGRectGetMinX(r), bottom);
        CGContextAddLineToPoint(c, CGRectGetMaxX(r), bottom);
        CGContextStrokePath(c);
        CGContextRestoreGState(c);
        if (d->value == kThemeButtonOn) {
            CGRect a = CGRectMake(CGRectGetMaxX(r) - 16, CGRectGetMidY(r) - 4, 8, 8);
            BOOL up = (d->adornment & kThemeAdornmentHeaderButtonSortUp) != 0;
            triangle(c, a, up == flipped(c) ? 3 : 1, ink(enabled));
        }
        break;
    }
    case kThemeComboBox:
    case kThemeComboBoxSmall:
    case kThemeComboBoxMini:
    case kThemePopupButton:
    case kThemePopupButtonNormal:
    case kThemePopupButtonSmall:
    case kThemePopupButtonMini: {
        filled_box(c, CGRectInset(r, 0.5, 1), 5, face(pressed), edge());
        CGFloat w = MIN(18, r.size.width / 3);
        CGRect arrow = CGRectMake(CGRectGetMaxX(r) - w - 1, r.origin.y + 2, w, r.size.height - 4);
        filled_box(c, arrow, 4, accent(), NULL);
        triangle(c, CGRectInset(arrow, w * 0.25, arrow.size.height * 0.25), flipped(c) ? 1 : 3, rgb(1, 1, 1, 1));
        if (labelRect)
            *labelRect = CGRectMake(r.origin.x + 8, r.origin.y, MAX(0, r.size.width - w - 12), r.size.height);
        break;
    }
    default: { /* push, bevel and round buttons */
        BOOL isDefault = (d->adornment & kThemeAdornmentDefault) != 0;
        CGRect b = CGRectInset(r, 0.5, 1);
        CGFloat radius = d->kind == kThemeRoundButton || d->kind == kThemeLargeRoundButton ? b.size.height / 2 : 5;
        if (isDefault && enabled)
            filled_box(c, b, radius, accent(), NULL);
        else
            filled_box(c, b, radius, face(pressed), edge());
        break;
    }
    }
    if (d->adornment & kThemeAdornmentFocus) {
        CGContextSaveGState(c);
        CGContextSetStrokeColorWithColor(c, CGColorCreateCopyWithAlpha(accent(), 0.5));
        CGContextSetLineWidth(c, 2.5);
        round_rect(c, CGRectInset(r, -1, -1), 6);
        CGContextStrokePath(c);
        CGContextRestoreGState(c);
    }
    return kHINoErr;
}

HIOSStatus HIThemeDrawFrame(const CGRect *bounds, const void *info, CGContextRef c, uint32_t orientation)
{
    if (!bounds || !c)
        return kHIParamErr;
    const FerryThemeFrameDrawInfo *d = info;
    CGRect r = CGRectInset(CGRectStandardize(*bounds), 0.5, 0.5);
    CGContextSaveGState(c);
    CGContextSetStrokeColorWithColor(c, d && d->isFocused ? accent() : edge());
    CGContextSetLineWidth(c, 1);
    CGContextStrokeRect(c, r);
    CGContextRestoreGState(c);
    return kHINoErr;
}

HIOSStatus HIThemeDrawFocusRect(const CGRect *bounds, Boolean hasFocus, CGContextRef c, uint32_t orientation)
{
    if (!bounds || !c)
        return kHIParamErr;
    if (!hasFocus)
        return kHINoErr;
    CGContextSaveGState(c);
    CGContextSetStrokeColorWithColor(c, CGColorCreateCopyWithAlpha(accent(), 0.55));
    CGContextSetLineWidth(c, 3);
    round_rect(c, CGRectInset(CGRectStandardize(*bounds), -1.5, -1.5), 4);
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
    return kHINoErr;
}

HIOSStatus HIThemeBeginFocus(CGContextRef c, uint32_t kind, OptionBits flags) { return kHINoErr; }
HIOSStatus HIThemeEndFocus(CGContextRef c) { return kHINoErr; }

HIOSStatus HIThemeDrawBackground(const CGRect *bounds, const void *info, CGContextRef c, uint32_t orientation)
{
    if (!bounds || !c)
        return kHIParamErr;
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, [[NSColor windowBackgroundColor] CGColor]);
    CGContextFillRect(c, CGRectStandardize(*bounds));
    CGContextRestoreGState(c);
    return kHINoErr;
}

/* a splitter between panes: a hairline, or a small grip in a thick one */
HIOSStatus HIThemeDrawPaneSplitter(const CGRect *bounds, const void *info, CGContextRef c, uint32_t orientation)
{
    if (!bounds || !c)
        return kHIParamErr;
    CGRect r = CGRectStandardize(*bounds);
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, [[NSColor windowBackgroundColor] CGColor]);
    CGContextFillRect(c, r);
    CGContextSetFillColorWithColor(c, edge());
    if (r.size.width > r.size.height)
        CGContextFillRect(c, CGRectMake(r.origin.x, CGRectGetMidY(r) - 0.5, r.size.width, 1));
    else
        CGContextFillRect(c, CGRectMake(CGRectGetMidX(r) - 0.5, r.origin.y, 1, r.size.height));
    CGContextRestoreGState(c);
    return kHINoErr;
}

/* A track (slider, progress bar or scroll bar), described as HITheme
 * documents it: its kind, bounds, range and value come first. */
typedef struct {
    uint32_t version;
    uint16_t kind; /* ThemeTrackKind: kThemeMediumScrollBar 0, SmallScrollBar 1, MediumSlider 2,
                    * MediumProgressBar 3, MediumIndeterminateBar 4, Relevance 5, SmallSlider 6,
                    * LargeProgressBar 7, LargeIndeterminateBar 8, MiniScrollBar 9, MiniSlider 10,
                    * MiniProgressBar 11, MiniIndeterminateBar 12 */
    CGRect bounds;
    int32_t min, max, value;
    uint32_t reserved;
    uint16_t attributes; /* kThemeTrackHorizontal 1 */
    uint8_t enableState;
    uint8_t filler1;
} FerryThemeTrackDrawInfo;

HIOSStatus HIThemeDrawTrack(const void *info, const CGRect *ghost, CGContextRef c, uint32_t orientation)
{
    if (!info || !c)
        return kHIParamErr;
    const FerryThemeTrackDrawInfo *d = info;
    CGRect r = CGRectStandardize(d->bounds);
    BOOL horizontal = (d->attributes & 1) != 0;
    double span = (double)d->max - d->min, frac = span > 0 ? ((double)d->value - d->min) / span : 0;
    frac = frac < 0 ? 0 : frac > 1 ? 1 : frac;
    BOOL progress = d->kind == 3 || d->kind == 7 || d->kind == 11 || d->kind == 4 || d->kind == 8 || d->kind == 12;
    BOOL slider = d->kind == 2 || d->kind == 6 || d->kind == 10;
    CGContextSaveGState(c);
    if (progress || slider) {
        CGFloat thick = slider ? 4 : MIN(horizontal ? r.size.height : r.size.width, 6);
        CGRect groove = horizontal ? CGRectMake(r.origin.x, CGRectGetMidY(r) - thick / 2, r.size.width, thick)
                                   : CGRectMake(CGRectGetMidX(r) - thick / 2, r.origin.y, thick, r.size.height);
        filled_box(c, groove, thick / 2, dark_look() ? rgb(0.3, 0.3, 0.32, 1) : rgb(0.85, 0.85, 0.86, 1), NULL);
        CGRect done = groove;
        if (horizontal)
            done.size.width *= frac;
        else {
            done.size.height *= frac;
            if (!flipped(c))
                done.origin.y = CGRectGetMaxY(groove) - done.size.height;
        }
        filled_box(c, done, thick / 2, accent(), NULL);
        if (slider) {
            CGFloat k = 14;
            CGPoint at = horizontal ? CGPointMake(r.origin.x + frac * (r.size.width - k) + k / 2, CGRectGetMidY(r))
                                    : CGPointMake(CGRectGetMidX(r), r.origin.y + (1 - frac) * (r.size.height - k) + k / 2);
            filled_box(c, CGRectMake(at.x - k / 2, at.y - k / 2, k, k), k / 2, face(NO), edge());
        }
    } else {
        /* a scroll bar: its knob, sized by the visible part when it was given */
        CGContextSetFillColorWithColor(c, dark_look() ? rgb(0.2, 0.2, 0.2, 1) : rgb(0.97, 0.97, 0.97, 1));
        CGContextFillRect(c, r);
        CGFloat len = (horizontal ? r.size.width : r.size.height) * 0.25;
        CGFloat pos = frac * ((horizontal ? r.size.width : r.size.height) - len);
        CGRect knob = horizontal ? CGRectMake(r.origin.x + pos, r.origin.y + 3, len, r.size.height - 6)
                                 : CGRectMake(r.origin.x + 3, r.origin.y + pos, r.size.width - 6, len);
        filled_box(c, knob, 3, rgb(0.5, 0.5, 0.5, 0.6), NULL);
    }
    CGContextRestoreGState(c);
    return kHINoErr;
}

/* ThemeBrush colors: the documented brushes that wxWidgets asks for */
HIOSStatus HIThemeBrushCreateCGColor(int16_t brush, CGColorRef *out)
{
    if (!out)
        return kHIParamErr;
    NSColor *color;
    switch (brush) {
    case 1: /* kThemeBrushDialogBackgroundActive */
    case 2:
    case 15: /* kThemeBrushDocumentWindowBackground */
    case 52: /* kThemeBrushModelessDialogBackgroundActive */
    case 53:
        color = [NSColor windowBackgroundColor];
        break;
    case 3: /* kThemeBrushAlertBackgroundActive */
    case 4:
        color = [NSColor windowBackgroundColor];
        break;
    case 5: /* kThemeBrushFocusHighlight */
    case -3: /* kThemeBrushPrimaryHighlightColor */
    case -4: /* kThemeBrushSecondaryHighlightColor */
        color = [NSColor selectedContentBackgroundColor];
        break;
    case 6: /* kThemeBrushButtonFrameActive */
    case 7:
        color = [NSColor gridColor];
        break;
    case 8: /* kThemeBrushButtonFaceActive */
    case 9:
    case 10:
        color = [NSColor controlColor];
        break;
    case -1: /* kThemeBrushBlack */
        color = [NSColor blackColor];
        break;
    case -2: /* kThemeBrushWhite */
        color = [NSColor whiteColor];
        break;
    default:
        color = [NSColor windowBackgroundColor];
        break;
    }
    *out = CGColorRetain([color CGColor]);
    return kHINoErr;
}

/* ---- the Appearance Manager's metrics --------------------------------------------- */

/* Indexed by ThemeMetric, in the order Appearance.h documents them. */
static const int16_t theme_metrics[] = {
    15, /* ScrollBarWidth */          11, /* SmallScrollBarWidth */    14, /* CheckBoxHeight */
    16, /* RadioButtonHeight */       1,  /* EditTextWhitespace */     1,  /* EditTextFrameOutset */
    1,  /* ListBoxFrameOutset */      3,  /* FocusRectOutset */        3,  /* ImageWellThickness */
    0,  /* ScrollBarOverlap */        24, /* LargeTabHeight */         10, /* LargeTabCapsWidth */
    2,  /* TabFrameOverlap */         0,  /* TabIndentOrStyle */       0,  /* TabOverlap */
    19, /* SmallTabHeight */          8,  /* SmallTabCapsWidth */      20, /* DisclosureButtonHeight */
    20, /* RoundButtonSize */         20, /* PushButtonHeight */       17, /* ListHeaderHeight */
    12, /* SmallCheckBoxHeight */     21, /* DisclosureButtonWidth */  14, /* SmallDisclosureButtonHeight */
    14, /* SmallDisclosureButtonWidth */ 12, /* DisclosureTriangleHeight */ 12, /* DisclosureTriangleWidth */
    22, /* LittleArrowsHeight */      13, /* LittleArrowsWidth */      9,  /* PaneSplitterHeight */
    20, /* PopupButtonHeight */       17, /* SmallPopupButtonHeight */ 16, /* LargeProgressBarThickness */
    20, /* PullDownHeight */          17, /* SmallPullDownHeight */    17, /* SmallPushButtonHeight */
    12, /* SmallRadioButtonHeight */  13, /* RelevanceIndicatorHeight */ 15, /* ResizeControlHeight */
    13, /* SmallResizeControlHeight */ 25, /* LargeRoundButtonSize */  21, /* HSliderHeight */
    6,  /* HSliderTickHeight */       16, /* SmallHSliderHeight */     4,  /* SmallHSliderTickHeight */
    21, /* VSliderWidth */            6,  /* VSliderTickWidth */       16, /* SmallVSliderWidth */
    4,  /* SmallVSliderTickWidth */   22, /* TitleBarControlsHeight */ 14, /* CheckBoxWidth */
    12, /* SmallCheckBoxWidth */      16, /* RadioButtonWidth */       12, /* SmallRadioButtonWidth */
    11, /* SmallHSliderMinThumbWidth */ 11, /* SmallVSliderMinThumbHeight */ 0, /* SmallHSliderTickOffset */
    0,  /* SmallVSliderTickOffset */  6,  /* NormalProgressBarThickness */ 1, /* ProgressBarShadowOutset */
    1,  /* SmallProgressBarShadowOutset */ 16, /* PrimaryGroupBoxContentInset */
    12, /* SecondaryGroupBoxContentInset */ 20, /* MenuMarkColumnWidth */ 22, /* MenuExcludedMarkColumnWidth */
    4,  /* MenuMarkIndent */          8,  /* MenuTextLeadingEdgeMargin */ 18, /* MenuTextTrailingEdgeMargin */
    14, /* MenuIndentWidth */         6,  /* MenuIconTrailingEdgeMargin */
};

HIOSStatus GetThemeMetric(uint32_t metric, int32_t *out)
{
    if (!out)
        return kHIParamErr;
    if (metric >= sizeof theme_metrics / sizeof theme_metrics[0]) {
        *out = 0;
        return kHIParamErr;
    }
    *out = theme_metrics[metric];
    return kHINoErr;
}

/* ---- the event loop and the system's look ------------------------------------------- */

void *GetCurrentEventLoop(void) { return (void *)CFRunLoopGetCurrent(); }
void *GetMainEventLoop(void) { return (void *)CFRunLoopGetMain(); }
CFRunLoopRef GetCFRunLoopFromEventLoop(void *loop) { return loop ? (CFRunLoopRef)loop : CFRunLoopGetCurrent(); }

HIOSStatus SetSystemUIMode(uint32_t mode, OptionBits options) { return kHINoErr; }
HIOSStatus GetSystemUIMode(uint32_t *mode, OptionBits *options)
{
    if (mode)
        *mode = 0;
    if (options)
        *options = 0;
    return kHINoErr;
}

/* the pasteboard's paste location (for promised files): kept, never used */
HIOSStatus PasteboardSetPasteLocation(void *pasteboard, CFURLRef location) { return kHINoErr; }
