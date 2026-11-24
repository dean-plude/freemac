/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: rulers and ruler markers. Our own code, written from
 * Apple's public API documentation.
 *
 * A ruler lies along the top (horizontal) or the left (vertical) of its
 * scroll view's content, which tiles it there while rulersVisible is YES.
 * From the outside in it has the accessory view's area, the markers'
 * area and the rule itself, which lies next to the content and is
 * ruleThickness thick; the line between the markers and the rule is the
 * baseline. A ruler doesn't scroll: it draws what lies beside the part of
 * the document that is in sight, so a subclass that draws line numbers
 * works from the clip view's bounds, as Sequel Pro's does.
 *
 * Drawing: a light background, then drawHashMarksAndLabelsInRect:, which
 * subclasses override (the default draws the measurement unit's marks with
 * a label every so often, the zero mark originOffset from the document
 * view's origin), then drawMarkersInRect:, then a line along the edge next
 * to the content. Units are registered by name; Inches, Centimeters,
 * Points and Picas are there from the start, with the factors and cycles
 * Apple's documentation gives.
 *
 * Markers move while the mouse drags them and are removed when dragged off
 * a removable marker's ruler, asking the client view as the documentation
 * describes. A Mac follows the mouse in a loop of its own; Ferry follows
 * the ruler's own mouse events instead, and trackMarker:withMouseEvent:
 * adds its marker at once, at the event's place. */
#import "AInternal.h"

NSRulerViewUnitName const NSRulerViewUnitInches = @"Inches";
NSRulerViewUnitName const NSRulerViewUnitCentimeters = @"Centimeters";
NSRulerViewUnitName const NSRulerViewUnitPoints = @"Points";
NSRulerViewUnitName const NSRulerViewUnitPicas = @"Picas";

/* ---- units ----------------------------------------------------------------------------- */

@interface ARulerUnit : NSObject {
@public
    NSString *abbreviation;
    CGFloat points;
    NSArray *up, *down;
}
@end
@implementation ARulerUnit
- (void)dealloc
{
    [abbreviation release];
    [up release];
    [down release];
    [super dealloc];
}
@end

static NSMutableDictionary *units;

static void register_unit(NSString *name, NSString *abbreviation, CGFloat points, NSArray *up, NSArray *down)
{
    ARulerUnit *u = [[ARulerUnit alloc] init];
    u->abbreviation = [abbreviation copy];
    u->points = points;
    u->up = [up copy];
    u->down = [down copy];
    [units setObject:u forKey:name];
    [u release];
}
static void ensure_units(void)
{
    if (units)
        return;
    units = [[NSMutableDictionary alloc] init];
    register_unit(NSRulerViewUnitInches, @"in", 72.0, @[ @2.0 ], @[ @0.5, @0.2 ]);
    register_unit(NSRulerViewUnitCentimeters, @"cm", 28.35, @[ @2.0 ], @[ @0.5, @0.2 ]);
    register_unit(NSRulerViewUnitPoints, @"pt", 1.0, @[ @10.0 ], @[ @0.5 ]);
    register_unit(NSRulerViewUnitPicas, @"pc", 12.0, @[ @10.0 ], @[ @0.5 ]);
}

/* ---- NSRulerView ----------------------------------------------------------------------- */

@interface NSRulerView (FerryRulerPrivate)
- (CGFloat)_rulerCoordinateForLocation:(CGFloat)location;
- (CGFloat)_locationForRulerCoordinate:(CGFloat)coordinate;
- (void)_beginTracking:(NSRulerMarker *)marker event:(NSEvent *)event;
- (void)_thicknessChanged;
@end

@interface NSRulerMarker (FerryRulerPrivate)
- (void)_setRuler:(NSRulerView *)ruler;
- (void)_setDragging:(BOOL)flag;
@end

@implementation NSRulerView {
    NSScrollView *_scrollView;      /* not retained: it owns the ruler */
    NSRulerOrientation _orientation;
    CGFloat _ruleThickness, _reservedMarkers, _reservedAccessory, _originOffset;
    NSString *_units;
    NSView *_client;                /* not retained */
    NSMutableArray *_markers;
    NSView *_accessory;
    NSRulerMarker *_tracking;       /* the marker the mouse is moving */
    CGFloat _grab;                  /* where on the marker the mouse took it, along the ruler */
    BOOL _removing;
    CGFloat _rulerline;             /* the temporary line's place, in the ruler, or -1 */
}

+ (void)registerUnitWithName:(NSRulerViewUnitName)name abbreviation:(NSString *)abbreviation
    unitToPointsConversionFactor:(CGFloat)factor stepUpCycle:(NSArray *)up stepDownCycle:(NSArray *)down
{
    if (!name)
        return;
    ensure_units();
    register_unit(name, abbreviation ?: @"", factor > 0 ? factor : 1, up ?: @[ @2.0 ], down ?: @[ @0.5 ]);
}

- (void)_setUpRuler
{
    ensure_units();
    _ruleThickness = 16;
    _reservedMarkers = 15;
    _units = [NSRulerViewUnitInches copy];
    _markers = [[NSMutableArray alloc] init];
    _rulerline = -1;
}
- (instancetype)initWithScrollView:(NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation
{
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 32, 32)])) {
        [self _setUpRuler];
        _scrollView = scrollView;
        _orientation = orientation;
    }
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setUpRuler];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder]))
        [self _setUpRuler];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)dealloc
{
    for (NSRulerMarker *m in _markers)
        if ([m ruler] == self)
            [m _setRuler:nil];
    [_markers release];
    [_units release];
    [_accessory release];
    [super dealloc];
}

/* A horizontal ruler counts down from its top; a vertical one runs the
 * way its scroll view's document view does. */
- (BOOL)isFlipped
{
    if (_orientation == NSHorizontalRuler)
        return YES;
    NSView *doc = [_scrollView documentView];
    return doc ? [doc isFlipped] : YES;
}
- (BOOL)isOpaque { return YES; }

- (NSScrollView *)scrollView { return _scrollView; }
- (void)setScrollView:(NSScrollView *)sv { _scrollView = sv; }
- (NSRulerOrientation)orientation { return _orientation; }
- (void)setOrientation:(NSRulerOrientation)o
{
    _orientation = o;
    [self _thicknessChanged];
}

- (CGFloat)ruleThickness { return _ruleThickness; }
- (void)setRuleThickness:(CGFloat)t
{
    _ruleThickness = fmax(t, 0);
    [self _thicknessChanged];
}
- (CGFloat)reservedThicknessForMarkers { return _reservedMarkers; }
- (void)setReservedThicknessForMarkers:(CGFloat)t
{
    _reservedMarkers = fmax(t, 0);
    [self _thicknessChanged];
}
- (CGFloat)reservedThicknessForAccessoryView { return _reservedAccessory; }
- (void)setReservedThicknessForAccessoryView:(CGFloat)t
{
    _reservedAccessory = fmax(t, 0);
    [self _thicknessChanged];
}
- (CGFloat)_markersThickness
{
    CGFloat t = _reservedMarkers;
    for (NSRulerMarker *m in _markers)
        t = fmax(t, [m thicknessRequiredInRuler]);
    return t;
}
- (CGFloat)_accessoryThickness
{
    CGFloat t = _reservedAccessory;
    if (_accessory)
        t = fmax(t, _orientation == NSHorizontalRuler ? [_accessory frame].size.height : [_accessory frame].size.width);
    return t;
}
- (CGFloat)requiredThickness { return _ruleThickness + [self _markersThickness] + [self _accessoryThickness]; }
- (CGFloat)baselineLocation
{
    CGFloat outer = [self _accessoryThickness] + [self _markersThickness];
    if (_orientation == NSHorizontalRuler)
        return outer;   /* flipped: down from the top */
    return outer;       /* across from the left */
}
/* The scroll view lays its rulers out again when one's thickness changes. */
- (void)_thicknessChanged
{
    [self setNeedsDisplay:YES];
    if (_scrollView && ([_scrollView horizontalRulerView] == self || [_scrollView verticalRulerView] == self))
        [_scrollView tile];
    [self _placeAccessory];
}

- (NSRulerViewUnitName)measurementUnits { return _units; }
- (void)setMeasurementUnits:(NSRulerViewUnitName)name
{
    ensure_units();
    if (![units objectForKey:name])
        [NSException raise:NSInvalidArgumentException format:@"NSRulerView: unknown measurement units %@", name];
    [_units release];
    _units = [name copy];
    [self invalidateHashMarks];
}
- (CGFloat)originOffset { return _originOffset; }
- (void)setOriginOffset:(CGFloat)o
{
    _originOffset = o;
    [self invalidateHashMarks];
}
- (void)invalidateHashMarks { [self setNeedsDisplay:YES]; }

- (NSView *)clientView { return _client; }
- (void)setClientView:(NSView *)client
{
    if (client == _client)
        return;
    if ([_client respondsToSelector:@selector(rulerView:willSetClientView:)])
        [_client rulerView:self willSetClientView:client];
    /* the markers were the old client's */
    for (NSRulerMarker *m in _markers)
        [m _setRuler:nil];
    [_markers removeAllObjects];
    _client = client;
    [self _thicknessChanged];
}

- (NSArray *)markers { return [[_markers copy] autorelease]; }
- (void)setMarkers:(NSArray *)markers
{
    for (NSRulerMarker *m in _markers)
        [m _setRuler:nil];
    [_markers removeAllObjects];
    for (NSRulerMarker *m in markers)
        if ([m isKindOfClass:[NSRulerMarker class]]) {
            [_markers addObject:m];
            [m _setRuler:self];
        }
    [self _thicknessChanged];
}
- (void)addMarker:(NSRulerMarker *)m
{
    if (!m || [_markers containsObject:m])
        return;
    [_markers addObject:m];
    [m _setRuler:self];
    [self _thicknessChanged];
}
- (void)removeMarker:(NSRulerMarker *)m
{
    if (![_markers containsObject:m])
        return;
    [[m retain] autorelease];
    if (_tracking == m)
        _tracking = nil;
    [_markers removeObject:m];
    [m _setRuler:nil];
    [self _thicknessChanged];
}

- (NSView *)accessoryView { return _accessory; }
- (void)setAccessoryView:(NSView *)v
{
    if (v == _accessory)
        return;
    if ([_accessory superview] == self)
        [_accessory removeFromSuperview];
    [v retain];
    [_accessory release];
    _accessory = v;
    if (v)
        [self addSubview:v];
    [self _thicknessChanged];
}
- (void)_placeAccessory
{
    if (!_accessory)
        return;
    NSRect b = [self bounds], f = [_accessory frame];
    if (_orientation == NSHorizontalRuler)
        f.origin = NSMakePoint(f.origin.x, NSMinY(b));
    else
        f.origin = NSMakePoint(NSMinX(b), f.origin.y);
    [_accessory setFrameOrigin:f.origin];
}

/* ---- where things are --------------------------------------------------------------- */

/* The view locations are measured in: the client view, else the scroll
 * view's document view. */
static BOOL same_tree(NSView *a, NSView *b)
{
    if (!a || !b)
        return NO;
    while ([a superview])
        a = [a superview];
    while ([b superview])
        b = [b superview];
    return a == b;
}
- (NSView *)_measuredView { return _client ?: [_scrollView documentView]; }

- (CGFloat)_rulerCoordinateForLocation:(CGFloat)location
{
    NSView *v = [self _measuredView];
    if ([v respondsToSelector:@selector(rulerView:pointForLocation:)]) {
        NSPoint p = [self convertPoint:[v rulerView:self pointForLocation:location] fromView:v];
        return _orientation == NSHorizontalRuler ? p.x : p.y;
    }
    if (!same_tree(v, self)) {
        /* not placed yet: across the document as the clip view shows it */
        NSClipView *clip = [_scrollView contentView];
        NSRect b = clip ? [clip bounds] : NSZeroRect;
        return location - (_orientation == NSHorizontalRuler ? b.origin.x : b.origin.y);
    }
    NSPoint p = _orientation == NSHorizontalRuler ? NSMakePoint(location, 0) : NSMakePoint(0, location);
    p = [self convertPoint:p fromView:v];
    return _orientation == NSHorizontalRuler ? p.x : p.y;
}
- (CGFloat)_locationForRulerCoordinate:(CGFloat)c
{
    NSView *v = [self _measuredView];
    NSPoint p = _orientation == NSHorizontalRuler ? NSMakePoint(c, 0) : NSMakePoint(0, c);
    if ([v respondsToSelector:@selector(rulerView:locationForPoint:)])
        return [v rulerView:self locationForPoint:[self convertPoint:p toView:v]];
    if (!same_tree(v, self)) {
        NSClipView *clip = [_scrollView contentView];
        NSRect b = clip ? [clip bounds] : NSZeroRect;
        return c + (_orientation == NSHorizontalRuler ? b.origin.x : b.origin.y);
    }
    p = [self convertPoint:p toView:v];
    return _orientation == NSHorizontalRuler ? p.x : p.y;
}
/* The zero mark is originOffset from the document view's origin. */
- (CGFloat)_zeroLocation
{
    NSView *doc = [_scrollView documentView];
    NSView *v = [self _measuredView];
    if (!doc || doc == v || !same_tree(doc, v))
        return _originOffset;
    NSPoint p = _orientation == NSHorizontalRuler ? NSMakePoint(_originOffset, 0) : NSMakePoint(0, _originOffset);
    p = [v convertPoint:p fromView:doc];
    return _orientation == NSHorizontalRuler ? p.x : p.y;
}

/* ---- drawing ---------------------------------------------------------------------- */

- (NSRect)_ruleRect
{
    NSRect b = [self bounds];
    CGFloat base = [self baselineLocation];
    if (_orientation == NSHorizontalRuler)
        return NSMakeRect(NSMinX(b), NSMinY(b) + base, b.size.width, fmax(b.size.height - base, 0));
    return NSMakeRect(NSMinX(b) + base, NSMinY(b), fmax(b.size.width - base, 0), b.size.height);
}

- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    [[NSColor colorWithCalibratedWhite:0.965 alpha:1] setFill];
    NSRectFill(dirty);
    [self drawHashMarksAndLabelsInRect:dirty];
    [self drawMarkersInRect:dirty];
    [[NSColor colorWithCalibratedWhite:0.75 alpha:1] setFill];
    if (_orientation == NSHorizontalRuler)
        NSRectFill(NSMakeRect(NSMinX(b), [self isFlipped] ? NSMaxY(b) - 1 : NSMinY(b), b.size.width, 1));
    else
        NSRectFill(NSMakeRect(NSMaxX(b) - 1, NSMinY(b), 1, b.size.height));
    if (_rulerline >= 0) {
        [[NSColor colorWithCalibratedWhite:0.3 alpha:1] setFill];
        if (_orientation == NSHorizontalRuler)
            NSRectFill(NSMakeRect(floor(_rulerline), NSMinY(b), 1, b.size.height));
        else
            NSRectFill(NSMakeRect(NSMinX(b), floor(_rulerline), b.size.width, 1));
    }
}

static NSString *label_for(double v)
{
    if (fabs(v - round(v)) < 1e-6)
        return [NSString stringWithFormat:@"%lld", (long long)llround(v)];
    return [NSString stringWithFormat:@"%g", v];
}

/* The unit's marks: a labelled mark every so many units (multiplied up by
 * the step-up cycle until labels are at least 40 points apart), and
 * smaller marks between (divided by the step-down cycle while they stay at
 * least 5 points apart). */
- (void)drawHashMarksAndLabelsInRect:(NSRect)dirty
{
    ARulerUnit *u = [units objectForKey:_units] ?: [units objectForKey:NSRulerViewUnitInches];
    CGFloat zero = [self _rulerCoordinateForLocation:[self _zeroLocation]];
    CGFloat one = [self _rulerCoordinateForLocation:[self _zeroLocation] + 1];
    CGFloat scale = one - zero;   /* ruler points for each point of the document */
    if (fabs(scale) < 1e-6)
        return;
    double labelStep = u->points;  /* in document points */
    for (NSUInteger i = 0; fabs(labelStep * scale) < 40 && i < 64; i++)
        labelStep *= [[u->up objectAtIndex:i % [u->up count]] doubleValue];
    double steps[8];
    int levels = 0;
    steps[levels++] = labelStep;
    for (NSUInteger i = 0; levels < 8; i++) {
        double next = steps[levels - 1] * [[u->down objectAtIndex:i % [u->down count]] doubleValue];
        if (fabs(next * scale) < 5)
            break;
        steps[levels++] = next;
    }
    double finest = steps[levels - 1];
    NSRect rule = [self _ruleRect];
    BOOL h = _orientation == NSHorizontalRuler;
    CGFloat lo = h ? NSMinX(dirty) : NSMinY(dirty), hi = h ? NSMaxX(dirty) : NSMaxY(dirty);
    /* the document locations that lie in the dirty part */
    double a = (lo - zero) / scale, b = (hi - zero) / scale;
    if (a > b) {
        double t = a;
        a = b;
        b = t;
    }
    long first = (long)floor(a / finest) - 1, last = (long)ceil(b / finest) + 1;
    if (last - first > 20000)
        return;
    NSColor *ink = [NSColor colorWithCalibratedWhite:0.45 alpha:1];
    NSFont *font = [NSFont systemFontOfSize:9];
    [ink setFill];
    CGFloat thick = h ? rule.size.height : rule.size.width;
    for (long k = first; k <= last; k++) {
        double loc = k * finest;
        int level = levels - 1;
        for (int l = 0; l < levels; l++) {
            double q = loc / steps[l];
            if (fabs(q - round(q)) < 1e-6) {
                level = l;
                break;
            }
        }
        CGFloat len = level == 0 ? thick * 0.75 : level == 1 ? thick * 0.45 : thick * 0.25;
        CGFloat at = floor(zero + loc * scale);
        if (h)
            NSRectFill(NSMakeRect(at, NSMaxY(rule) - len, 1, len));
        else
            NSRectFill(NSMakeRect(NSMaxX(rule) - len, at, len, 1));
        if (level == 0) {
            NSAttributedString *text = AAttributed(label_for(loc / u->points), font, ink);
            CGFloat ascent = 0;
            ALineSize(text, &ascent, NULL);
            if (h)
                ADrawLine(text, at + 3, NSMinY(rule) + ascent + 1);
            else
                ADrawLine(text, NSMinX(rule) + 2, [self isFlipped] ? at + ascent + 2 : at - ascent - 2);
        }
    }
}

- (void)drawMarkersInRect:(NSRect)dirty
{
    for (NSRulerMarker *m in _markers)
        if (NSIntersectsRect([m imageRectInRuler], dirty))
            [m drawRect:dirty];
}

- (void)moveRulerlineFromLocation:(CGFloat)old toLocation:(CGFloat)location
{
    _rulerline = location < 0 ? -1 : [self _rulerCoordinateForLocation:location];
    [self setNeedsDisplay:YES];
}

/* ---- the mouse ---------------------------------------------------------------------- */

- (CGFloat)_along:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    return _orientation == NSHorizontalRuler ? p.x : p.y;
}
- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    for (NSRulerMarker *m in [_markers reverseObjectEnumerator])
        if (NSPointInRect(p, [m imageRectInRuler])) {
            [m trackMouse:e adding:NO];
            return;
        }
    NSView *client = [self _measuredView];
    if ([client respondsToSelector:@selector(rulerView:handleMouseDown:)])
        [client rulerView:self handleMouseDown:e];
}
- (void)_beginTracking:(NSRulerMarker *)m event:(NSEvent *)e
{
    NSView *client = [self _measuredView];
    if (![m isMovable] && ![m isRemovable])
        return;
    if ([client respondsToSelector:@selector(rulerView:shouldMoveMarker:)] && ![client rulerView:self shouldMoveMarker:m])
        return;
    _tracking = m;
    _removing = NO;
    _grab = [self _along:e] - [self _rulerCoordinateForLocation:[m markerLocation]];
    [m _setDragging:YES];
}
- (void)mouseDragged:(NSEvent *)e
{
    if (!_tracking)
        return;
    NSRulerMarker *m = _tracking;
    NSView *client = [self _measuredView];
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    CGFloat across = _orientation == NSHorizontalRuler ? p.y : p.x;
    CGFloat extent = _orientation == NSHorizontalRuler ? [self bounds].size.height : [self bounds].size.width;
    _removing = [m isRemovable] && (across < -8 || across > extent + 8);
    if (![m isMovable])
        return;
    CGFloat location = [self _locationForRulerCoordinate:[self _along:e] - _grab];
    if ([client respondsToSelector:@selector(rulerView:willMoveMarker:toLocation:)])
        location = [client rulerView:self willMoveMarker:m toLocation:location];
    [m setMarkerLocation:location];
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)e
{
    if (!_tracking)
        return;
    [self mouseDragged:e];
    NSRulerMarker *m = [[_tracking retain] autorelease];
    NSView *client = [self _measuredView];
    _tracking = nil;
    [m _setDragging:NO];
    if (_removing && (![client respondsToSelector:@selector(rulerView:shouldRemoveMarker:)] ||
                      [client rulerView:self shouldRemoveMarker:m])) {
        [self removeMarker:m];
        if ([client respondsToSelector:@selector(rulerView:didRemoveMarker:)])
            [client rulerView:self didRemoveMarker:m];
    } else if ([m isMovable] && [client respondsToSelector:@selector(rulerView:didMoveMarker:)]) {
        [client rulerView:self didMoveMarker:m];
    }
    _removing = NO;
    [self setNeedsDisplay:YES];
}

/* Adds a marker the user drags in from elsewhere (a palette): at once,
 * where the event is, as the client allows. */
- (BOOL)trackMarker:(NSRulerMarker *)m withMouseEvent:(NSEvent *)e
{
    if (!m)
        return NO;
    NSView *client = [self _measuredView];
    if ([client respondsToSelector:@selector(rulerView:shouldAddMarker:)] && ![client rulerView:self shouldAddMarker:m])
        return NO;
    CGFloat location = e ? [self _locationForRulerCoordinate:[self _along:e]] : [m markerLocation];
    if ([client respondsToSelector:@selector(rulerView:willAddMarker:atLocation:)])
        location = [client rulerView:self willAddMarker:m atLocation:location];
    [m setMarkerLocation:location];
    [self addMarker:m];
    if ([client respondsToSelector:@selector(rulerView:didAddMarker:)])
        [client rulerView:self didAddMarker:m];
    return YES;
}
@end

/* ---- NSRulerMarker -------------------------------------------------------------------- */

@implementation NSRulerMarker {
    NSRulerView *_ruler;   /* not retained */
    CGFloat _location;
    NSImage *_image;
    NSPoint _origin;
    BOOL _movable, _removable, _dragging;
    id _represented;
}
- (instancetype)initWithRulerView:(NSRulerView *)ruler markerLocation:(CGFloat)location image:(NSImage *)image
                      imageOrigin:(NSPoint)origin
{
    if ((self = [super init])) {
        _ruler = ruler;
        _location = location;
        _image = [image retain];
        _origin = origin;
        _movable = YES;
    }
    return self;
}
- (instancetype)init { return [self initWithRulerView:nil markerLocation:0 image:nil imageOrigin:NSZeroPoint]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self init];
    if (self && [coder allowsKeyedCoding]) {
        _location = [coder decodeDoubleForKey:@"NSMarkerLocation"];
        _image = [[coder decodeObjectForKey:@"NSImage"] retain];
        _origin = [coder decodePointForKey:@"NSImageOrigin"];
        _movable = [coder containsValueForKey:@"NSMovable"] ? [coder decodeBoolForKey:@"NSMovable"] : YES;
        _removable = [coder decodeBoolForKey:@"NSRemovable"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding])
        return;
    [coder encodeDouble:_location forKey:@"NSMarkerLocation"];
    if (_image)
        [coder encodeObject:_image forKey:@"NSImage"];
    [coder encodePoint:_origin forKey:@"NSImageOrigin"];
    [coder encodeBool:_movable forKey:@"NSMovable"];
    [coder encodeBool:_removable forKey:@"NSRemovable"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSRulerMarker *m = [[NSRulerMarker alloc] initWithRulerView:_ruler markerLocation:_location image:_image
                                                    imageOrigin:_origin];
    m->_movable = _movable;
    m->_removable = _removable;
    m->_represented = [(id)_represented copyWithZone:zone];
    return m;
}
- (void)dealloc
{
    [_image release];
    [_represented release];
    [super dealloc];
}

- (NSRulerView *)ruler { return _ruler; }
- (void)_setRuler:(NSRulerView *)r { _ruler = r; }
- (void)_setDragging:(BOOL)f { _dragging = f; }
- (CGFloat)markerLocation { return _location; }
- (void)setMarkerLocation:(CGFloat)l
{
    _location = l;
    [_ruler setNeedsDisplay:YES];
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)i
{
    [i retain];
    [_image release];
    _image = i;
    [_ruler setNeedsDisplay:YES];
}
- (NSPoint)imageOrigin { return _origin; }
- (void)setImageOrigin:(NSPoint)p
{
    _origin = p;
    [_ruler setNeedsDisplay:YES];
}
- (BOOL)isMovable { return _movable; }
- (void)setMovable:(BOOL)f { _movable = f; }
- (BOOL)isRemovable { return _removable; }
- (void)setRemovable:(BOOL)f { _removable = f; }
- (BOOL)isDragging { return _dragging; }
- (id)representedObject { return _represented; }
- (void)setRepresentedObject:(id)o
{
    [o retain];
    [_represented release];
    _represented = o;
}

/* The image's imageOrigin lies on the ruler's baseline at the marker's
 * place: a horizontal ruler's markers stand above the baseline, a vertical
 * one's to the left of it. */
- (NSRect)imageRectInRuler
{
    if (!_ruler)
        return NSZeroRect;
    NSSize s = _image ? [_image size] : NSZeroSize;
    CGFloat at = [_ruler _rulerCoordinateForLocation:_location], base = [_ruler baselineLocation];
    if ([_ruler orientation] == NSHorizontalRuler)
        return NSMakeRect(at - _origin.x, base + _origin.y - s.height, s.width, s.height);
    if ([_ruler isFlipped])
        return NSMakeRect(base - _origin.x, at - (s.height - _origin.y), s.width, s.height);
    return NSMakeRect(base - _origin.x, at - _origin.y, s.width, s.height);
}
- (CGFloat)thicknessRequiredInRuler
{
    if (!_image)
        return 0;
    NSSize s = [_image size];
    return _ruler && [_ruler orientation] == NSVerticalRuler ? _origin.x : s.height - _origin.y;
}
- (void)drawRect:(NSRect)rect
{
    if (!_image || !_ruler)
        return;
    [_image _drawInControlRect:[self imageRectInRuler] color:nil fraction:_dragging ? 0.6 : 1];
}
- (BOOL)trackMouse:(NSEvent *)e adding:(BOOL)adding
{
    if (!_ruler)
        return NO;
    if (adding)
        return [_ruler trackMarker:self withMouseEvent:e];
    [_ruler _beginTracking:self event:e];
    return YES;
}
@end
