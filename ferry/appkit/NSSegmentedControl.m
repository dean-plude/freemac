/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: segmented controls (NSSegmentedControl, NSSegmentedCell).
 * Ferry's own code, written from Apple's public API documentation. It is
 * drawn to look like a current Mac's rounded segmented control (a light
 * gray track, the chosen segment a raised white knob), with Ferry's own
 * drawing code.
 *
 * Clicking a segment selects it as the tracking mode says (one at a time,
 * any number, or only while it is pressed) and sends the action; a segment
 * with a menu opens the menu instead, below it. With full keyboard access
 * the arrow keys move between segments and Space presses one.
 *
 * A nib keeps the segments in the cell as an array, "NSSegmentImages", of
 * NSSegmentItem objects ("NSSegmentItemLabel", "NSSegmentItemImage",
 * "NSSegmentItemWidth", "NSSegmentItemSelected", "NSSegmentItemEnabled" or
 * "NSSegmentItemDisabled", "NSSegmentItemTag", "NSSegmentItemTooltip",
 * "NSSegmentItemMenu", "NSSegmentItemImageScaling"), with
 * "NSSelectedSegment", "NSTrackingMode", "NSSegmentStyle" and
 * "NSSegmentDistribution" beside them. Those names are the ones given in
 * descriptions of the format published by developers and by the GNUstep
 * project; no Apple code was read, and a nib that names them differently
 * loads with the defaults. */
#import "AInternal.h"


/* One segment (nibs name the class). */
@interface NSSegmentItem : NSObject <NSCoding> {
@public
    NSString *label, *toolTip;
    NSImage *image;
    NSMenu *menu;
    CGFloat width;
    BOOL selected, enabled;
    NSInteger tag;
    NSImageScaling scaling;
    NSTextAlignment alignment;
}
@end

@implementation NSSegmentItem
- (instancetype)init
{
    if ((self = [super init])) {
        label = @"";
        enabled = YES;
        scaling = NSImageScaleProportionallyDown;
        alignment = NSTextAlignmentCenter;
    }
    return self;
}
static id value(NSCoder *c, NSString *key, Class cls)
{
    id v = [c containsValueForKey:key] ? [c decodeObjectForKey:key] : nil;
    return [v isKindOfClass:cls] ? v : nil;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [self init]))
        return nil;
    NSString *l = value(c, @"NSSegmentItemLabel", [NSString class]);
    if (l)
        label = [l copy];
    image = [value(c, @"NSSegmentItemImage", [NSImage class]) retain];
    menu = [value(c, @"NSSegmentItemMenu", [NSMenu class]) retain];
    toolTip = [value(c, @"NSSegmentItemTooltip", [NSString class]) copy];
    if ([c containsValueForKey:@"NSSegmentItemWidth"])
        width = [c decodeDoubleForKey:@"NSSegmentItemWidth"];
    selected = [c decodeBoolForKey:@"NSSegmentItemSelected"];
    if ([c containsValueForKey:@"NSSegmentItemEnabled"])
        enabled = [c decodeBoolForKey:@"NSSegmentItemEnabled"];
    if ([c decodeBoolForKey:@"NSSegmentItemDisabled"])
        enabled = NO;
    tag = [c decodeIntegerForKey:@"NSSegmentItemTag"];
    if ([c containsValueForKey:@"NSSegmentItemImageScaling"])
        scaling = [c decodeIntegerForKey:@"NSSegmentItemImageScaling"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:label forKey:@"NSSegmentItemLabel"];
    if (image)
        [c encodeObject:image forKey:@"NSSegmentItemImage"];
    if (menu)
        [c encodeObject:menu forKey:@"NSSegmentItemMenu"];
    if (toolTip)
        [c encodeObject:toolTip forKey:@"NSSegmentItemTooltip"];
    [c encodeDouble:width forKey:@"NSSegmentItemWidth"];
    [c encodeBool:selected forKey:@"NSSegmentItemSelected"];
    [c encodeBool:enabled forKey:@"NSSegmentItemEnabled"];
    [c encodeInteger:tag forKey:@"NSSegmentItemTag"];
    [c encodeInteger:scaling forKey:@"NSSegmentItemImageScaling"];
}
- (void)dealloc
{
    [label release];
    [toolTip release];
    [image release];
    [menu release];
    [super dealloc];
}
@end

/* ---- NSSegmentedCell ---------------------------------------------------------------- */

@interface NSSegmentedCell (FerryPrivate) <AMenuOwner>
- (NSSegmentItem *)_segment:(NSInteger)i;
- (NSInteger)_keySegment;
- (void)_setKeySegment:(NSInteger)i;
- (NSSegmentDistribution)_distribution;
- (void)_setDistribution:(NSSegmentDistribution)d;
- (void)_clicked:(NSInteger)segment;
@end

@implementation NSSegmentedCell {
    NSMutableArray *_segments;
    NSInteger _selected, _key;
    NSSegmentSwitchTracking _mode;
    NSSegmentStyle _style;
    NSSegmentDistribution _distribution;
}

- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super initTextCell:string])) {
        _segments = [[NSMutableArray alloc] init];
        _selected = -1;
        _distribution = NSSegmentDistributionFill;
        [self setAlignment:NSTextAlignmentCenter];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [super initWithCoder:c]))
        return nil;
    for (NSSegmentItem *s in value(c, @"NSSegmentImages", [NSArray class]))
        if ([s isKindOfClass:[NSSegmentItem class]])
            [_segments addObject:s];
    if ([c containsValueForKey:@"NSTrackingMode"])
        _mode = (NSSegmentSwitchTracking)[c decodeIntegerForKey:@"NSTrackingMode"];
    if ([c containsValueForKey:@"NSSegmentStyle"])
        _style = (NSSegmentStyle)[c decodeIntegerForKey:@"NSSegmentStyle"];
    if ([c containsValueForKey:@"NSSegmentDistribution"])
        _distribution = (NSSegmentDistribution)[c decodeIntegerForKey:@"NSSegmentDistribution"];
    _selected = -1;
    for (NSUInteger i = 0; i < [_segments count]; i++)
        if (((NSSegmentItem *)_segments[i])->selected && _selected < 0)
            _selected = (NSInteger)i;
    if ([c containsValueForKey:@"NSSelectedSegment"]) {
        NSInteger s = [c decodeIntegerForKey:@"NSSelectedSegment"];
        if (s >= 0 && s < (NSInteger)[_segments count])
            [self setSelectedSegment:s];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [super encodeWithCoder:c];
    [c encodeObject:_segments forKey:@"NSSegmentImages"];
    [c encodeInteger:_selected forKey:@"NSSelectedSegment"];
    [c encodeInteger:_mode forKey:@"NSTrackingMode"];
    [c encodeInteger:_style forKey:@"NSSegmentStyle"];
    [c encodeInteger:_distribution forKey:@"NSSegmentDistribution"];
}
- (void)dealloc
{
    [_segments release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSSegmentedCell *c = [super copyWithZone:zone];
    for (NSSegmentItem *s in _segments) {
        NSSegmentItem *t = [[NSSegmentItem alloc] init];
        [t->label release];
        t->label = [s->label copy];
        t->toolTip = [s->toolTip copy];
        t->image = [s->image retain];
        t->menu = [s->menu retain];
        t->width = s->width;
        t->selected = s->selected;
        t->enabled = s->enabled;
        t->tag = s->tag;
        t->scaling = s->scaling;
        t->alignment = s->alignment;
        [c->_segments addObject:t];
        [t release];
    }
    c->_selected = _selected;
    c->_mode = _mode;
    c->_style = _style;
    c->_distribution = _distribution;
    return c;
}

- (void)_changed { [[self controlView] setNeedsDisplay:YES]; }
- (NSSegmentItem *)_segment:(NSInteger)i
{
    return i >= 0 && i < (NSInteger)[_segments count] ? _segments[i] : nil;
}

- (NSInteger)segmentCount { return (NSInteger)[_segments count]; }
- (void)setSegmentCount:(NSInteger)count
{
    if (count < 0)
        count = 0;
    while ((NSInteger)[_segments count] < count) {
        NSSegmentItem *s = [[NSSegmentItem alloc] init];
        [_segments addObject:s];
        [s release];
    }
    while ((NSInteger)[_segments count] > count)
        [_segments removeLastObject];
    if (_selected >= count)
        _selected = -1;
    if (_key >= count)
        _key = 0;
    [self _changed];
}
- (NSInteger)selectedSegment { return _selected; }
/* In a select-one control, choosing a segment unselects the others; -1
 * unselects them all. */
- (void)setSelectedSegment:(NSInteger)segment
{
    if (segment < 0 || segment >= (NSInteger)[_segments count]) {
        if (_mode != NSSegmentSwitchTrackingSelectAny)
            for (NSSegmentItem *s in _segments)
                s->selected = NO;
        _selected = -1;
    } else {
        [self setSelected:YES forSegment:segment];
    }
    [self _changed];
}
- (NSSegmentSwitchTracking)trackingMode { return _mode; }
- (void)setTrackingMode:(NSSegmentSwitchTracking)mode
{
    _mode = mode;
    if (mode == NSSegmentSwitchTrackingSelectOne) {
        NSInteger keep = _selected;
        for (NSUInteger i = 0; i < [_segments count]; i++)
            ((NSSegmentItem *)_segments[i])->selected = (NSInteger)i == keep;
    }
    [self _changed];
}
- (NSSegmentStyle)segmentStyle { return _style; }
- (void)setSegmentStyle:(NSSegmentStyle)style
{
    _style = style;
    [self _changed];
}
- (NSSegmentDistribution)_distribution { return _distribution; }
- (void)_setDistribution:(NSSegmentDistribution)d
{
    _distribution = d;
    [self _changed];
}
- (BOOL)selectSegmentWithTag:(NSInteger)tag
{
    for (NSUInteger i = 0; i < [_segments count]; i++)
        if (((NSSegmentItem *)_segments[i])->tag == tag) {
            [self setSelectedSegment:(NSInteger)i];
            return YES;
        }
    return NO;
}
- (NSInteger)_keySegment { return _key; }
- (void)_setKeySegment:(NSInteger)i
{
    if (i >= 0 && i < (NSInteger)[_segments count])
        _key = i;
    [self _changed];
}
- (void)makeNextSegmentKey
{
    NSInteger n = (NSInteger)[_segments count];
    for (NSInteger k = 1; k <= n; k++) {
        NSInteger i = (_key + k) % n;
        if ([self isEnabledForSegment:i]) {
            [self _setKeySegment:i];
            return;
        }
    }
}
- (void)makePreviousSegmentKey
{
    NSInteger n = (NSInteger)[_segments count];
    for (NSInteger k = 1; k <= n; k++) {
        NSInteger i = (_key - k + n) % n;
        if ([self isEnabledForSegment:i]) {
            [self _setKeySegment:i];
            return;
        }
    }
}

#define SEG(i, ...)                                                                                             \
    NSSegmentItem *s = [self _segment:(i)];                                                                     \
    if (!s)                                                                                                     \
        return __VA_ARGS__;

- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment
{
    SEG(segment)
    s->width = fmax(width, 0);
    [self _changed];
}
- (CGFloat)widthForSegment:(NSInteger)segment
{
    SEG(segment, 0)
    return s->width;
}
- (void)setImage:(NSImage *)image forSegment:(NSInteger)segment
{
    SEG(segment)
    [image retain];
    [s->image release];
    s->image = image;
    [self _changed];
}
- (NSImage *)imageForSegment:(NSInteger)segment
{
    SEG(segment, nil)
    return s->image;
}
- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment
{
    SEG(segment)
    s->scaling = scaling;
    [self _changed];
}
- (NSImageScaling)imageScalingForSegment:(NSInteger)segment
{
    SEG(segment, NSImageScaleProportionallyDown)
    return s->scaling;
}
- (void)setLabel:(NSString *)label forSegment:(NSInteger)segment
{
    SEG(segment)
    [s->label release];
    s->label = [label copy] ?: @"";
    [self _changed];
}
- (NSString *)labelForSegment:(NSInteger)segment
{
    SEG(segment, nil)
    return s->label;
}
- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment
{
    SEG(segment)
    if (selected && _mode != NSSegmentSwitchTrackingSelectAny)
        for (NSSegmentItem *o in _segments)
            o->selected = NO;
    s->selected = selected;
    if (selected) {
        _selected = segment;
    } else if (_selected == segment) {
        /* another selected segment, if any */
        _selected = -1;
        for (NSUInteger i = 0; i < [_segments count]; i++)
            if (((NSSegmentItem *)_segments[i])->selected) {
                _selected = (NSInteger)i;
                break;
            }
    }
    [self _changed];
}
- (BOOL)isSelectedForSegment:(NSInteger)segment
{
    SEG(segment, NO)
    return s->selected;
}
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment
{
    SEG(segment)
    s->enabled = enabled;
    [self _changed];
}
- (BOOL)isEnabledForSegment:(NSInteger)segment
{
    SEG(segment, NO)
    return s->enabled;
}
- (void)setMenu:(NSMenu *)menu forSegment:(NSInteger)segment
{
    SEG(segment)
    [menu retain];
    [s->menu release];
    s->menu = menu;
}
- (NSMenu *)menuForSegment:(NSInteger)segment
{
    SEG(segment, nil)
    return s->menu;
}
- (void)setToolTip:(NSString *)toolTip forSegment:(NSInteger)segment
{
    SEG(segment)
    [s->toolTip release];
    s->toolTip = [toolTip copy];
}
- (NSString *)toolTipForSegment:(NSInteger)segment
{
    SEG(segment, nil)
    return s->toolTip;
}
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment
{
    SEG(segment)
    s->tag = tag;
}
- (NSInteger)tagForSegment:(NSInteger)segment
{
    SEG(segment, 0)
    return s->tag;
}

/* A click on a segment: what it does to the selection, then the action
 * (from the control, which sends it). A momentary segment is selected only
 * while the action is sent. */
- (void)_clicked:(NSInteger)segment
{
    NSSegmentItem *s = [self _segment:segment];
    if (!s || !s->enabled)
        return;
    _key = segment;
    switch (_mode) {
    case NSSegmentSwitchTrackingSelectOne:
        [self setSelected:YES forSegment:segment];
        break;
    case NSSegmentSwitchTrackingSelectAny:
        [self setSelected:!s->selected forSegment:segment];
        if (s->selected)
            _selected = segment;
        break;
    default:     /* momentary: selected while its action goes out */
        for (NSSegmentItem *o in _segments)
            o->selected = NO;
        s->selected = YES;
        _selected = segment;
        break;
    }
    [self _changed];
}

/* A segment's menu closed: the chosen item's action is sent. */
- (void)_menuView:(AMenuView *)menu didChooseItem:(NSMenuItem *)item
{
    NSView *v = [self controlView];
    if ([v respondsToSelector:@selector(setHighlighted:)])
        [(NSControl *)v setHighlighted:NO];
    [v setNeedsDisplay:YES];
    if (item && [item action])
        [NSApp sendAction:[item action] to:[item target] from:item];
}
@end

/* ---- NSSegmentedControl -------------------------------------------------------------- */

enum { SEG_PAD = 10, SEG_HEIGHT = 22 };

@implementation NSSegmentedControl {
    BOOL _loading, _springLoaded;
    NSInteger _pressed;          /* the segment being pressed, or -1 */
    BOOL _inside;
    NSColor *_selectedBezel;
}

+ (Class)cellClass { return [NSSegmentedCell class]; }

+ (instancetype)segmentedControlWithLabels:(NSArray *)labels trackingMode:(NSSegmentSwitchTracking)mode
                                    target:(id)target action:(SEL)action
{
    NSSegmentedControl *c = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)] autorelease];
    [c setSegmentCount:(NSInteger)[labels count]];
    for (NSUInteger i = 0; i < [labels count]; i++)
        [c setLabel:labels[i] forSegment:(NSInteger)i];
    [c setTrackingMode:mode];
    [c setTarget:target];
    [c setAction:action];
    [c sizeToFit];
    return c;
}
+ (instancetype)segmentedControlWithImages:(NSArray *)images trackingMode:(NSSegmentSwitchTracking)mode
                                    target:(id)target action:(SEL)action
{
    NSSegmentedControl *c = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)] autorelease];
    [c setSegmentCount:(NSInteger)[images count]];
    for (NSUInteger i = 0; i < [images count]; i++)
        [c setImage:images[i] forSegment:(NSInteger)i];
    [c setTrackingMode:mode];
    [c setTarget:target];
    [c setAction:action];
    [c sizeToFit];
    return c;
}

- (NSSegmentedCell *)_segCell { return (NSSegmentedCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    _pressed = -1;
    if (!_loading && ![[self cell] isKindOfClass:[NSSegmentedCell class]]) {
        NSSegmentedCell *cell = [[NSSegmentedCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    _loading = YES;
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _loading = NO;
    if (![[self cell] isKindOfClass:[NSSegmentedCell class]]) {
        NSSegmentedCell *cell = [[NSSegmentedCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    return self;
}
- (void)dealloc
{
    [_selectedBezel release];
    [super dealloc];
}

/* ---- the settings, kept in the cell ---- */

- (NSInteger)segmentCount { return [[self _segCell] segmentCount]; }
- (void)setSegmentCount:(NSInteger)n { [[self _segCell] setSegmentCount:n]; }
- (NSInteger)selectedSegment { return [[self _segCell] selectedSegment]; }
- (void)setSelectedSegment:(NSInteger)s { [[self _segCell] setSelectedSegment:s]; }
- (NSInteger)indexOfSelectedItem { return [self selectedSegment]; }
- (NSSegmentSwitchTracking)trackingMode { return [[self _segCell] trackingMode]; }
- (void)setTrackingMode:(NSSegmentSwitchTracking)m { [[self _segCell] setTrackingMode:m]; }
- (NSSegmentStyle)segmentStyle { return [[self _segCell] segmentStyle]; }
- (void)setSegmentStyle:(NSSegmentStyle)s { [[self _segCell] setSegmentStyle:s]; }
- (NSSegmentDistribution)segmentDistribution { return [[self _segCell] _distribution]; }
- (void)setSegmentDistribution:(NSSegmentDistribution)d { [[self _segCell] _setDistribution:d]; }
- (NSColor *)selectedSegmentBezelColor { return _selectedBezel; }
- (void)setSelectedSegmentBezelColor:(NSColor *)c
{
    [_selectedBezel release];
    _selectedBezel = [c copy];
    [self setNeedsDisplay:YES];
}
- (BOOL)isSpringLoaded { return _springLoaded; }
- (void)setSpringLoaded:(BOOL)f { _springLoaded = f; }
- (BOOL)selectSegmentWithTag:(NSInteger)tag { return [[self _segCell] selectSegmentWithTag:tag]; }
- (void)setWidth:(CGFloat)w forSegment:(NSInteger)i { [[self _segCell] setWidth:w forSegment:i]; }
- (CGFloat)widthForSegment:(NSInteger)i { return [[self _segCell] widthForSegment:i]; }
- (void)setImage:(NSImage *)im forSegment:(NSInteger)i { [[self _segCell] setImage:im forSegment:i]; }
- (NSImage *)imageForSegment:(NSInteger)i { return [[self _segCell] imageForSegment:i]; }
- (void)setImageScaling:(NSImageScaling)s forSegment:(NSInteger)i { [[self _segCell] setImageScaling:s forSegment:i]; }
- (NSImageScaling)imageScalingForSegment:(NSInteger)i { return [[self _segCell] imageScalingForSegment:i]; }
- (void)setLabel:(NSString *)l forSegment:(NSInteger)i { [[self _segCell] setLabel:l forSegment:i]; }
- (NSString *)labelForSegment:(NSInteger)i { return [[self _segCell] labelForSegment:i]; }
- (void)setSelected:(BOOL)f forSegment:(NSInteger)i { [[self _segCell] setSelected:f forSegment:i]; }
- (BOOL)isSelectedForSegment:(NSInteger)i { return [[self _segCell] isSelectedForSegment:i]; }
- (void)setEnabled:(BOOL)f forSegment:(NSInteger)i { [[self _segCell] setEnabled:f forSegment:i]; }
- (BOOL)isEnabledForSegment:(NSInteger)i { return [[self _segCell] isEnabledForSegment:i]; }
- (void)setMenu:(NSMenu *)m forSegment:(NSInteger)i { [[self _segCell] setMenu:m forSegment:i]; }
- (NSMenu *)menuForSegment:(NSInteger)i { return [[self _segCell] menuForSegment:i]; }
- (void)setToolTip:(NSString *)t forSegment:(NSInteger)i { [[self _segCell] setToolTip:t forSegment:i]; }
- (NSString *)toolTipForSegment:(NSInteger)i { return [[self _segCell] toolTipForSegment:i]; }
- (void)setTag:(NSInteger)t forSegment:(NSInteger)i { [[self _segCell] setTag:t forSegment:i]; }
- (NSInteger)tagForSegment:(NSInteger)i { return [[self _segCell] tagForSegment:i]; }
- (void)setAlignment:(NSTextAlignment)a forSegment:(NSInteger)i
{
    NSSegmentItem *s = [[self _segCell] _segment:i];
    if (s)
        s->alignment = a;
    [self setNeedsDisplay:YES];
}
- (NSTextAlignment)alignmentForSegment:(NSInteger)i
{
    NSSegmentItem *s = [[self _segCell] _segment:i];
    return s ? s->alignment : NSTextAlignmentCenter;
}
- (id)objectValue { return @([self selectedSegment]); }
- (void)setObjectValue:(id)v { [self setSelectedSegment:[v integerValue]]; }
- (NSInteger)integerValue { return [self selectedSegment]; }
- (void)setIntegerValue:(NSInteger)v { [self setSelectedSegment:v]; }
- (int)intValue { return (int)[self selectedSegment]; }
- (void)setIntValue:(int)v { [self setSelectedSegment:v]; }

/* ---- geometry ---- */

/* A segment's width for its content: the label or image and some room. */
- (CGFloat)_contentWidth:(NSSegmentItem *)s
{
    CGFloat w = 0;
    if (s->image)
        w = fmin([s->image size].width, 24);
    if ([s->label length])
        w += (w > 0 ? 4 : 0) + ceil(ALineSize(AAttributed(s->label, [self font], nil), NULL, NULL).width);
    return fmax(w + 2 * SEG_PAD, 24);
}

/* The segments' rects across the bounds, by the distribution: at their
 * own widths, with the room left over shared between the ones without a
 * width set (Fill), all alike (Fill Equally), or in proportion (Fill
 * Proportionally). */
- (void)_rects:(NSRect *)out count:(NSInteger)n
{
    NSRect b = [self bounds];
    CGFloat want[n > 0 ? n : 1], total = 0;
    NSInteger flexible = 0;
    NSSegmentedCell *cell = [self _segCell];
    for (NSInteger i = 0; i < n; i++) {
        NSSegmentItem *s = [cell _segment:i];
        want[i] = s->width > 0 ? s->width : [self _contentWidth:s];
        total += want[i];
        flexible += s->width <= 0;
    }
    CGFloat extra = b.size.width - total;
    NSSegmentDistribution d = [cell _distribution];
    CGFloat x = b.origin.x, h = fmin(b.size.height, SEG_HEIGHT);
    CGFloat y = round(NSMidY(b) - h / 2);
    for (NSInteger i = 0; i < n; i++) {
        NSSegmentItem *s = [cell _segment:i];
        CGFloat w = want[i];
        if (d == NSSegmentDistributionFillEqually)
            w = b.size.width / n;
        else if (d == NSSegmentDistributionFillProportionally && total > 0)
            w = want[i] + extra * want[i] / total;
        else if (d == NSSegmentDistributionFill && extra > 0 && s->width <= 0 && flexible > 0)
            w = want[i] + extra / flexible;
        out[i] = NSMakeRect(round(x), y, round(x + w) - round(x), h);
        x += w;
    }
}

- (NSInteger)_segmentAt:(NSPoint)p
{
    NSInteger n = [self segmentCount];
    if (n <= 0)
        return -1;
    NSRect r[n];
    [self _rects:r count:n];
    for (NSInteger i = 0; i < n; i++)
        if (p.x >= NSMinX(r[i]) && p.x < NSMaxX(r[i]) && p.y >= NSMinY([self bounds]) && p.y < NSMaxY([self bounds]))
            return i;
    return -1;
}

- (NSSize)intrinsicContentSize
{
    CGFloat w = 0;
    NSSegmentedCell *cell = [self _segCell];
    for (NSInteger i = 0; i < [self segmentCount]; i++) {
        NSSegmentItem *s = [cell _segment:i];
        w += s->width > 0 ? s->width : [self _contentWidth:s];
    }
    return NSMakeSize(ceil(w), 24);
}

/* ---- the mouse and keys ---- */

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder { return [self isEnabled] && [NSApp isFullKeyboardAccessEnabled]; }

- (void)_press:(NSInteger)i
{
    NSSegmentedCell *cell = [self _segCell];
    [cell _clicked:i];
    [self sendAction:[self action] to:[self target]];
    if ([cell trackingMode] == NSSegmentSwitchTrackingMomentary ||
        [cell trackingMode] == NSSegmentSwitchTrackingMomentaryAccelerator) {
        [cell setSelected:NO forSegment:i];
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    if (![self isEnabled])
        return;
    NSInteger i = [self _segmentAt:[self convertPoint:[event locationInWindow] fromView:nil]];
    if (i < 0 || ![self isEnabledForSegment:i])
        return;
    NSMenu *menu = [self menuForSegment:i];
    if (menu) {
        NSInteger n = [self segmentCount];
        NSRect r[n];
        [self _rects:r count:n];
        _pressed = -1;
        [self setHighlighted:YES];
        [AMenuView openMenu:menu forView:self rect:r[i] alignItem:-1 skipFirst:NO font:[self font]
                      owner:[self _segCell]];
        return;
    }
    _pressed = i;
    _inside = YES;
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)event
{
    NSView *m = [[self window] _overlayView];
    if ([m isKindOfClass:[AMenuView class]]) {
        [m mouseDragged:event];
        return;
    }
    if (_pressed < 0)
        return;
    BOOL inside = [self _segmentAt:[self convertPoint:[event locationInWindow] fromView:nil]] == _pressed;
    if (inside != _inside) {
        _inside = inside;
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseUp:(NSEvent *)event
{
    NSView *m = [[self window] _overlayView];
    if ([m isKindOfClass:[AMenuView class]]) {
        [m mouseUp:event];
        return;
    }
    NSInteger i = _pressed;
    _pressed = -1;
    [self setNeedsDisplay:YES];
    if (i >= 0 && [self _segmentAt:[self convertPoint:[event locationInWindow] fromView:nil]] == i)
        [self _press:i];
}
- (void)keyDown:(NSEvent *)event
{
    NSString *c = [event charactersIgnoringModifiers];
    unichar k = [c length] ? [c characterAtIndex:0] : 0;
    NSSegmentedCell *cell = [self _segCell];
    if (k == NSRightArrowFunctionKey)
        [cell makeNextSegmentKey];
    else if (k == NSLeftArrowFunctionKey)
        [cell makePreviousSegmentKey];
    else if (k == ' ' && [self isEnabled])
        [self _press:[cell _keySegment]];
    else
        [super keyDown:event];
}
- (void)performClick:(id)sender
{
    if ([self isEnabled] && [self segmentCount] > 0)
        [self _press:[[self _segCell] _keySegment]];
}

/* ---- drawing ---- */

- (void)drawRect:(NSRect)dirty
{
    NSInteger n = [self segmentCount];
    if (n <= 0)
        return;
    NSSegmentedCell *cell = [self _segCell];
    NSRect r[n];
    [self _rects:r count:n];
    BOOL enabled = [self isEnabled];
    CGFloat dim = enabled ? 1 : 0.45;
    NSRect track = NSMakeRect(NSMinX(r[0]), r[0].origin.y, NSMaxX(r[n - 1]) - NSMinX(r[0]), r[0].size.height);
    NSSegmentSwitchTracking mode = [cell trackingMode];
    BOOL one = mode == NSSegmentSwitchTrackingSelectOne;
    AFillRoundedRect(track, 6, [NSColor colorWithWhite:0 alpha:0.055 * dim], [NSColor colorWithWhite:0 alpha:0.08 * dim]);

    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    /* the selected segments: a raised knob when one is chosen at a time,
     * else darker */
    for (NSInteger i = 0; i < n; i++) {
        BOOL sel = [cell isSelectedForSegment:i];
        BOOL pressed = i == _pressed && _inside;
        NSRect k = NSInsetRect(r[i], 1.5, 1.5);
        if (sel && one) {
            CGContextSaveGState(cg);
            CGColorRef shadow = CGColorCreateGenericRGB(0, 0, 0, 0.18 * dim);
            CGContextSetShadowWithColor(cg, CGSizeMake(0, -0.5), 1.5, shadow);
            CGColorRelease(shadow);
            NSColor *fill = _selectedBezel ?: [NSColor whiteColor];
            if (pressed)
                fill = [fill shadowWithLevel:0.08];
            AFillRoundedRect(k, 4.5, [fill colorWithAlphaComponent:dim], nil);
            CGContextRestoreGState(cg);
        } else if (sel) {
            NSColor *fill = _selectedBezel ?: [NSColor colorWithWhite:0 alpha:pressed ? 0.24 : 0.16];
            AFillRoundedRect(k, 4.5, [fill colorWithAlphaComponent:[fill alphaComponent] * dim], nil);
        } else if (pressed) {
            AFillRoundedRect(k, 4.5, [NSColor colorWithWhite:0 alpha:0.1], nil);
        }
    }
    /* dividers between segments, except beside a selected one */
    for (NSInteger i = 1; i < n; i++) {
        if ([cell isSelectedForSegment:i] || [cell isSelectedForSegment:i - 1])
            continue;
        [[NSColor colorWithWhite:0 alpha:0.12 * dim] setFill];
        NSRectFill(NSMakeRect(NSMinX(r[i]) - 0.5, r[i].origin.y + 5, 1, r[i].size.height - 10));
    }
    BOOL focused = [[self window] firstResponder] == self && [[self window] isKeyWindow];
    for (NSInteger i = 0; i < n; i++) {
        NSSegmentItem *s = [cell _segment:i];
        BOOL on = s->enabled && enabled;
        BOOL light = s->selected && _selectedBezel;
        NSColor *text = light ? [NSColor colorWithWhite:1 alpha:on ? 1 : 0.5]
                              : [NSColor colorWithWhite:0 alpha:on ? 0.85 : 0.3];
        NSRect c = NSInsetRect(r[i], SEG_PAD / 2.0, 0);
        CGFloat iw = 0, ih = 0;
        if (s->image) {
            NSSize sz = [s->image size];
            CGFloat k = 1;
            if (s->scaling != NSImageScaleNone && (sz.height > c.size.height - 4 || sz.width > c.size.width))
                k = fmin((c.size.height - 4) / fmax(sz.height, 1), c.size.width / fmax(sz.width, 1));
            if (s->scaling == NSImageScaleProportionallyUpOrDown)
                k = fmin((c.size.height - 4) / fmax(sz.height, 1), c.size.width / fmax(sz.width, 1));
            iw = sz.width * k;
            ih = sz.height * k;
        }
        NSAttributedString *t = [s->label length] ? AAttributed(s->label, [self font], text) : nil;
        CGFloat a = 0, d = 0;
        CGFloat tw = t ? ceil(ALineSize(t, &a, &d).width) : 0;
        CGFloat total = iw + (iw > 0 && tw > 0 ? 4 : 0) + tw;
        CGFloat x = NSMidX(c) - total / 2;
        if (s->alignment == NSTextAlignmentLeft)
            x = c.origin.x;
        else if (s->alignment == NSTextAlignmentRight)
            x = NSMaxX(c) - total;
        x = fmax(x, c.origin.x);
        CGContextSaveGState(cg);
        CGContextClipToRect(cg, c);
        if (s->image) {
            NSRect ir = NSMakeRect(round(x), round(NSMidY(c) - ih / 2), iw, ih);
            [s->image _drawInControlRect:ir color:text fraction:on ? 1 : 0.4];
            x += iw + 4;
        }
        if (t) {
            CGFloat baseline = [self isFlipped] ? ceil(NSMidY(c) + (a + d) / 2 - d) : floor(NSMidY(c) - (a + d) / 2 + d);
            ADrawLine(t, round(x), baseline);
        }
        CGContextRestoreGState(cg);
        if (focused && i == [cell _keySegment])
            AFillRoundedRect(NSInsetRect(r[i], 0.5, 0.5), 5.5, nil, [NSColor keyboardFocusIndicatorColor]);
    }
}
@end
