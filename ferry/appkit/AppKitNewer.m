/* SPDX-License-Identifier: GPL-3.0-or-later
 * Newer AppKit names (sdk/include/AppKit/AppKitNewer.h; freemac 1.232,
 * Ferry 0.56.0): safe areas, display links, symbol configurations and a
 * few symbol images of Ferry's own drawing, menu section headers, the
 * system fills, dynamic colours, scroll phases and control switches.
 * Written from Apple's public documentation. */
#import "AInternal.h"
#import <objc/runtime.h>

/* ---- views ---------------------------------------------------------------------------------- */

static char safe_area_key, clips_key;

@implementation NSView (FerrySafeArea)
/* The guide is the view's bounds less its safe-area insets (only the
 * additional ones a program sets, AppKitDocumentApps.m), kept by four
 * constraints whose constants follow the insets. */
static void fit_safe_area(NSView *v, NSLayoutGuide *g)
{
    NSEdgeInsets i = [v safeAreaInsets];
    for (NSLayoutConstraint *c in [v constraints]) {
        if ([c firstItem] != g)
            continue;
        switch ([c firstAttribute]) {
        case NSLayoutAttributeLeading: [c setConstant:i.left]; break;
        case NSLayoutAttributeTrailing: [c setConstant:-i.right]; break;
        case NSLayoutAttributeTop: [c setConstant:i.top]; break;
        case NSLayoutAttributeBottom: [c setConstant:-i.bottom]; break;
        default: break;
        }
    }
}
- (NSLayoutGuide *)safeAreaLayoutGuide
{
    NSLayoutGuide *g = objc_getAssociatedObject(self, &safe_area_key);
    if (!g) {
        g = [[[NSLayoutGuide alloc] init] autorelease];
        [g setIdentifier:@"NSViewSafeAreaLayoutGuide"];
        [self addLayoutGuide:g];
        objc_setAssociatedObject(self, &safe_area_key, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [NSLayoutConstraint activateConstraints:@[
            [[g leadingAnchor] constraintEqualToAnchor:[self leadingAnchor]],
            [[g trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]],
            [[g topAnchor] constraintEqualToAnchor:[self topAnchor]],
            [[g bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]],
        ]];
        fit_safe_area(self, g);
    }
    return g;
}
- (void)_safeAreaInsetsChanged
{
    NSLayoutGuide *g = objc_getAssociatedObject(self, &safe_area_key);
    if (g)
        fit_safe_area(self, g);
}
- (BOOL)clipsToBounds { return [objc_getAssociatedObject(self, &clips_key) boolValue]; }
- (void)setClipsToBounds:(BOOL)c
{
    objc_setAssociatedObject(self, &clips_key, c ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSView (FerryDisplayLink)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector
{
    return [CADisplayLink displayLinkWithTarget:target selector:selector];
}
@end
@implementation NSWindow (FerryDisplayLink)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector
{
    return [CADisplayLink displayLinkWithTarget:target selector:selector];
}
@end
@implementation NSScreen (FerryDisplayLink)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector
{
    return [CADisplayLink displayLinkWithTarget:target selector:selector];
}
/* How fast the screen redraws (macOS 12): its display mode's refresh rate,
 * 60 times a second when that isn't known. Ferry's screens have a fixed
 * rate, so the shortest and longest intervals are the same. */
static double ferry_screen_hz(NSScreen *screen)
{
    CGDirectDisplayID d = (CGDirectDisplayID)[[screen deviceDescription][@"NSScreenNumber"] unsignedIntValue];
    CGDisplayModeRef m = CGDisplayCopyDisplayMode(d ? d : CGMainDisplayID());
    double hz = m ? CGDisplayModeGetRefreshRate(m) : 0;
    if (m)
        CGDisplayModeRelease(m);
    return hz >= 1 ? hz : 60;
}
- (NSInteger)maximumFramesPerSecond { return (NSInteger)(ferry_screen_hz(self) + 0.5); }
- (NSTimeInterval)minimumRefreshInterval { return 1.0 / ferry_screen_hz(self); }
- (NSTimeInterval)maximumRefreshInterval { return 1.0 / ferry_screen_hz(self); }
- (NSTimeInterval)displayUpdateGranularity { return 0; }
- (NSTimeInterval)lastDisplayUpdateTimestamp { return [[NSProcessInfo processInfo] systemUptime]; }
@end

/* ---- symbol configurations ------------------------------------------------------------------- */

@implementation NSImageSymbolConfiguration {
    CGFloat _size;
    NSFontWeight _weight;
    BOOL _hasWeight;
    NSImageSymbolScale _scale;
    NSColor *_color;
    NSArray *_palette;
}
+ (instancetype)configurationWithPointSize:(CGFloat)size weight:(NSFontWeight)weight
{
    return [self configurationWithPointSize:size weight:weight scale:0];
}
+ (instancetype)configurationWithPointSize:(CGFloat)size weight:(NSFontWeight)weight scale:(NSImageSymbolScale)scale
{
    NSImageSymbolConfiguration *c = [[[self alloc] init] autorelease];
    c->_size = size;
    c->_weight = weight;
    c->_hasWeight = YES;
    c->_scale = scale;
    return c;
}
+ (instancetype)configurationWithScale:(NSImageSymbolScale)scale
{
    NSImageSymbolConfiguration *c = [[[self alloc] init] autorelease];
    c->_scale = scale;
    return c;
}
+ (instancetype)configurationWithHierarchicalColor:(NSColor *)color
{
    NSImageSymbolConfiguration *c = [[[self alloc] init] autorelease];
    c->_color = [color retain];
    return c;
}
+ (instancetype)configurationWithPaletteColors:(NSArray *)colors
{
    NSImageSymbolConfiguration *c = [[[self alloc] init] autorelease];
    c->_palette = [colors copy];
    c->_color = [[colors firstObject] retain];
    return c;
}
+ (instancetype)configurationPreferringMulticolor { return [[[self alloc] init] autorelease]; }
+ (instancetype)configurationPreferringMonochrome { return [[[self alloc] init] autorelease]; }
+ (instancetype)configurationPreferringHierarchical { return [[[self alloc] init] autorelease]; }
- (void)dealloc
{
    [_color release];
    [_palette release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSImageSymbolConfiguration *c = [[NSImageSymbolConfiguration alloc] init];
    c->_size = _size;
    c->_weight = _weight;
    c->_hasWeight = _hasWeight;
    c->_scale = _scale;
    c->_color = [_color retain];
    c->_palette = [_palette copy];
    return c;
}
- (instancetype)configurationByApplyingConfiguration:(NSImageSymbolConfiguration *)o
{
    NSImageSymbolConfiguration *c = [[self copy] autorelease];
    if (o->_size > 0)
        c->_size = o->_size;
    if (o->_hasWeight) {
        c->_weight = o->_weight;
        c->_hasWeight = YES;
    }
    if (o->_scale)
        c->_scale = o->_scale;
    if (o->_color) {
        [c->_color release];
        c->_color = [o->_color retain];
    }
    return c;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_size forKey:@"pointSize"];
    [coder encodeDouble:_weight forKey:@"weight"];
    [coder encodeInteger:_scale forKey:@"scale"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _size = [coder decodeDoubleForKey:@"pointSize"];
        _weight = [coder decodeDoubleForKey:@"weight"];
        _hasWeight = [coder containsValueForKey:@"weight"];
        _scale = [coder decodeIntegerForKey:@"scale"];
    }
    return self;
}
- (BOOL)isEqual:(id)o
{
    if (![o isKindOfClass:[NSImageSymbolConfiguration class]])
        return NO;
    NSImageSymbolConfiguration *c = o;
    return c->_size == _size && c->_weight == _weight && c->_scale == _scale &&
           (c->_color == _color || [c->_color isEqual:_color]);
}
- (NSUInteger)hash { return (NSUInteger)(_size * 100) ^ (NSUInteger)_scale; }
- (CGFloat)_ferryPointSize { return _size; }
- (NSFontWeight)_ferryWeight { return _hasWeight ? _weight : NSFontWeightRegular; }
- (NSImageSymbolScale)_ferryScale { return _scale; }
- (NSColor *)_ferryColor { return _color; }
@end

/* ---- symbol images ----------------------------------------------------------------------------
 * SF Symbols are Apple's artwork, which Ferry hasn't got. For a few
 * common names Ferry draws a plain image of its own: simple strokes in the
 * spirit of the name, as template images, so that they take the control's
 * colour. Any other name finds nothing, as on a Mac for a name it doesn't
 * know. */

static char symbol_name_key, symbol_config_key;

typedef void (*symbol_drawer)(NSRect r, CGFloat line);

static NSBezierPath *stroke_path(CGFloat line)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p setLineWidth:line];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    return p;
}
static NSPoint at(NSRect r, CGFloat x, CGFloat y)
{
    return NSMakePoint(NSMinX(r) + x * NSWidth(r), NSMinY(r) + y * NSHeight(r));
}
static void draw_plus(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.5, 0.1)];
    [p lineToPoint:at(r, 0.5, 0.9)];
    [p moveToPoint:at(r, 0.1, 0.5)];
    [p lineToPoint:at(r, 0.9, 0.5)];
    [p stroke];
}
static void draw_minus(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.1, 0.5)];
    [p lineToPoint:at(r, 0.9, 0.5)];
    [p stroke];
}
static void chevron(NSRect r, CGFloat line, NSPoint a, NSPoint b, NSPoint c)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, a.x, a.y)];
    [p lineToPoint:at(r, b.x, b.y)];
    [p lineToPoint:at(r, c.x, c.y)];
    [p stroke];
}
/* the drawing is flipped: y goes down */
static void draw_chevron_right(NSRect r, CGFloat l) { chevron(r, l, NSMakePoint(0.35, 0.12), NSMakePoint(0.72, 0.5), NSMakePoint(0.35, 0.88)); }
static void draw_chevron_left(NSRect r, CGFloat l) { chevron(r, l, NSMakePoint(0.65, 0.12), NSMakePoint(0.28, 0.5), NSMakePoint(0.65, 0.88)); }
static void draw_chevron_down(NSRect r, CGFloat l) { chevron(r, l, NSMakePoint(0.12, 0.33), NSMakePoint(0.5, 0.7), NSMakePoint(0.88, 0.33)); }
static void draw_chevron_up(NSRect r, CGFloat l) { chevron(r, l, NSMakePoint(0.12, 0.67), NSMakePoint(0.5, 0.3), NSMakePoint(0.88, 0.67)); }
static void draw_xmark(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.18, 0.18)];
    [p lineToPoint:at(r, 0.82, 0.82)];
    [p moveToPoint:at(r, 0.82, 0.18)];
    [p lineToPoint:at(r, 0.18, 0.82)];
    [p stroke];
}
static void draw_checkmark(NSRect r, CGFloat l) { chevron(r, l, NSMakePoint(0.12, 0.52), NSMakePoint(0.4, 0.8), NSMakePoint(0.88, 0.2)); }
static void draw_video(NSRect r, CGFloat line)
{
    /* a camera's body and its lens's wedge */
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(r), NSMinY(r) + NSHeight(r) * 0.22,
                                                                            NSWidth(r) * 0.66, NSHeight(r) * 0.56)
                                                         xRadius:NSWidth(r) * 0.1
                                                         yRadius:NSWidth(r) * 0.1];
    [body fill];
    NSBezierPath *wedge = [NSBezierPath bezierPath];
    [wedge moveToPoint:at(r, 0.7, 0.5)];
    [wedge lineToPoint:at(r, 1.0, 0.26)];
    [wedge lineToPoint:at(r, 1.0, 0.74)];
    [wedge closePath];
    [wedge fill];
}
static void draw_delete_backward(NSRect r, CGFloat line)
{
    /* a key pointing left, with a cross in it */
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.04, 0.5)];
    [p lineToPoint:at(r, 0.32, 0.18)];
    [p lineToPoint:at(r, 0.96, 0.18)];
    [p lineToPoint:at(r, 0.96, 0.82)];
    [p lineToPoint:at(r, 0.32, 0.82)];
    [p closePath];
    [p moveToPoint:at(r, 0.5, 0.36)];
    [p lineToPoint:at(r, 0.76, 0.64)];
    [p moveToPoint:at(r, 0.76, 0.36)];
    [p lineToPoint:at(r, 0.5, 0.64)];
    [p stroke];
}
static void draw_trash(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.1, 0.2)];
    [p lineToPoint:at(r, 0.9, 0.2)];
    [p moveToPoint:at(r, 0.38, 0.2)];
    [p lineToPoint:at(r, 0.38, 0.08)];
    [p lineToPoint:at(r, 0.62, 0.08)];
    [p lineToPoint:at(r, 0.62, 0.2)];
    [p moveToPoint:at(r, 0.2, 0.2)];
    [p lineToPoint:at(r, 0.26, 0.92)];
    [p lineToPoint:at(r, 0.74, 0.92)];
    [p lineToPoint:at(r, 0.8, 0.2)];
    [p stroke];
}
static void draw_circle(NSRect r, CGFloat line)
{
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, line / 2 + NSWidth(r) * 0.06, line / 2 + NSWidth(r) * 0.06)];
    [p setLineWidth:line];
    [p stroke];
}
static void draw_circle_fill(NSRect r, CGFloat line)
{
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, NSWidth(r) * 0.06, NSWidth(r) * 0.06)] fill];
}
static void draw_ellipsis(NSRect r, CGFloat line)
{
    CGFloat d = NSWidth(r) * 0.18;
    for (int i = 0; i < 3; i++)
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(r) + NSWidth(r) * (0.1 + i * 0.31), NSMidY(r) - d / 2, d, d)] fill];
}
static void draw_magnifier(NSRect r, CGFloat line)
{
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(r) + NSWidth(r) * 0.08, NSMinY(r) + NSHeight(r) * 0.08,
                                                                        NSWidth(r) * 0.58, NSHeight(r) * 0.58)];
    [p setLineWidth:line];
    [p stroke];
    NSBezierPath *h = stroke_path(line * 1.3);
    [h moveToPoint:at(r, 0.6, 0.6)];
    [h lineToPoint:at(r, 0.92, 0.92)];
    [h stroke];
}

/* freemac 1.264: more names, for HandBrake's toolbar and other apps' */
static NSRect part(NSRect r, CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
    return NSMakeRect(NSMinX(r) + x * NSWidth(r), NSMinY(r) + y * NSHeight(r), w * NSWidth(r), h * NSHeight(r));
}
static void fill_poly(NSRect r, int n, const CGFloat *xy)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    for (int i = 0; i < n; i++) {
        if (i)
            [p lineToPoint:at(r, xy[2 * i], xy[2 * i + 1])];
        else
            [p moveToPoint:at(r, xy[0], xy[1])];
    }
    [p closePath];
    [p fill];
}
static void stroke_rounded(NSRect box, CGFloat radius, CGFloat line)
{
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(box, line / 2, line / 2) xRadius:radius yRadius:radius];
    [p setLineWidth:line];
    [p stroke];
}
static void draw_play(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.22, 0.1)];
    [p lineToPoint:at(r, 0.86, 0.5)];
    [p lineToPoint:at(r, 0.22, 0.9)];
    [p closePath];
    [p stroke];
}
static void draw_play_fill(NSRect r, CGFloat line)
{
    const CGFloat xy[] = {0.2, 0.08, 0.9, 0.5, 0.2, 0.92};
    fill_poly(r, 3, xy);
}
static void draw_pause_fill(NSRect r, CGFloat line)
{
    [[NSBezierPath bezierPathWithRoundedRect:part(r, 0.18, 0.1, 0.22, 0.8) xRadius:NSWidth(r) * 0.04 yRadius:NSWidth(r) * 0.04] fill];
    [[NSBezierPath bezierPathWithRoundedRect:part(r, 0.6, 0.1, 0.22, 0.8) xRadius:NSWidth(r) * 0.04 yRadius:NSWidth(r) * 0.04] fill];
}
static void draw_pause(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line * 1.4);
    [p moveToPoint:at(r, 0.32, 0.12)];
    [p lineToPoint:at(r, 0.32, 0.88)];
    [p moveToPoint:at(r, 0.68, 0.12)];
    [p lineToPoint:at(r, 0.68, 0.88)];
    [p stroke];
}
static void draw_stop_fill(NSRect r, CGFloat line)
{
    [[NSBezierPath bezierPathWithRoundedRect:part(r, 0.12, 0.12, 0.76, 0.76) xRadius:NSWidth(r) * 0.1 yRadius:NSWidth(r) * 0.1] fill];
}
static void draw_stop(NSRect r, CGFloat line) { stroke_rounded(part(r, 0.12, 0.12, 0.76, 0.76), NSWidth(r) * 0.1, line); }
static void draw_forward_fill(NSRect r, CGFloat line)
{
    const CGFloat a[] = {0.04, 0.2, 0.5, 0.5, 0.04, 0.8}, b[] = {0.5, 0.2, 0.96, 0.5, 0.5, 0.8};
    fill_poly(r, 3, a);
    fill_poly(r, 3, b);
}
static void draw_backward_fill(NSRect r, CGFloat line)
{
    const CGFloat a[] = {0.96, 0.2, 0.5, 0.5, 0.96, 0.8}, b[] = {0.5, 0.2, 0.04, 0.5, 0.5, 0.8};
    fill_poly(r, 3, a);
    fill_poly(r, 3, b);
}
static void draw_film(NSRect r, CGFloat line)
{
    /* a strip of film: a frame with holes down both edges */
    NSRect box = part(r, 0.08, 0.04, 0.84, 0.92);
    stroke_rounded(box, NSWidth(r) * 0.08, line);
    NSBezierPath *p = stroke_path(line * 0.8);
    [p moveToPoint:at(r, 0.3, 0.06)];
    [p lineToPoint:at(r, 0.3, 0.94)];
    [p moveToPoint:at(r, 0.7, 0.06)];
    [p lineToPoint:at(r, 0.7, 0.94)];
    [p moveToPoint:at(r, 0.3, 0.5)];
    [p lineToPoint:at(r, 0.7, 0.5)];
    for (int i = 0; i < 3; i++) {
        CGFloat y = 0.27 + i * 0.23;
        [p moveToPoint:at(r, 0.1, y)];
        [p lineToPoint:at(r, 0.3, y)];
        [p moveToPoint:at(r, 0.7, y)];
        [p lineToPoint:at(r, 0.9, y)];
    }
    [p stroke];
}
static void photo_in(NSRect r, CGFloat line)
{
    stroke_rounded(part(r, 0.04, 0.16, 0.92, 0.7), NSWidth(r) * 0.1, line);
    const CGFloat hill[] = {0.1, 0.8, 0.38, 0.48, 0.58, 0.68, 0.7, 0.58, 0.9, 0.8};
    fill_poly(r, 5, hill);
    [[NSBezierPath bezierPathWithOvalInRect:part(r, 0.62, 0.28, 0.14, 0.14)] fill];
}
static void draw_photo(NSRect r, CGFloat line) { photo_in(r, line); }
static void draw_photo_badge_plus(NSRect r, CGFloat line)
{
    photo_in(part(r, 0, 0.06, 0.8, 0.8), line);
    [[NSBezierPath bezierPathWithOvalInRect:part(r, 0.56, 0.56, 0.44, 0.44)] fill];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationClear];
    draw_plus(part(r, 0.64, 0.64, 0.28, 0.28), line * 0.9);
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}
static void draw_photo_stack(NSRect r, CGFloat line)
{
    photo_in(part(r, 0, 0.12, 0.88, 0.88), line);
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.16, 0.14)];
    [p lineToPoint:at(r, 0.92, 0.14)];
    [p lineToPoint:at(r, 0.92, 0.66)];
    [p stroke];
}
static void draw_sliders(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    const CGFloat knob[3] = {0.66, 0.3, 0.55};
    for (int i = 0; i < 3; i++) {
        CGFloat y = 0.2 + i * 0.3;
        [p moveToPoint:at(r, 0.06, y)];
        [p lineToPoint:at(r, 0.94, y)];
    }
    [p stroke];
    for (int i = 0; i < 3; i++) {
        CGFloat y = 0.2 + i * 0.3, d = 0.2;
        [[NSBezierPath bezierPathWithOvalInRect:part(r, knob[i] - d / 2, y - d / 2, d, d)] fill];
    }
}
static void draw_eye(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.04, 0.5)];
    [p curveToPoint:at(r, 0.96, 0.5) controlPoint1:at(r, 0.3, 0.08) controlPoint2:at(r, 0.7, 0.08)];
    [p curveToPoint:at(r, 0.04, 0.5) controlPoint1:at(r, 0.7, 0.92) controlPoint2:at(r, 0.3, 0.92)];
    [p stroke];
    [[NSBezierPath bezierPathWithOvalInRect:part(r, 0.36, 0.36, 0.28, 0.28)] fill];
}
static void draw_viewfinder_text(NSRect r, CGFloat line)
{
    /* four corners, and lines of text inside */
    NSBezierPath *p = stroke_path(line);
    const CGFloat c[4][2] = {{0.06, 0.06}, {0.94, 0.06}, {0.94, 0.94}, {0.06, 0.94}};
    for (int i = 0; i < 4; i++) {
        CGFloat dx = c[i][0] < 0.5 ? 0.26 : -0.26, dy = c[i][1] < 0.5 ? 0.26 : -0.26;
        [p moveToPoint:at(r, c[i][0] + dx, c[i][1])];
        [p lineToPoint:at(r, c[i][0], c[i][1])];
        [p lineToPoint:at(r, c[i][0], c[i][1] + dy)];
    }
    for (int i = 0; i < 3; i++) {
        CGFloat y = 0.33 + i * 0.17;
        [p moveToPoint:at(r, 0.28, y)];
        [p lineToPoint:at(r, i == 2 ? 0.56 : 0.72, y)];
    }
    [p stroke];
}
static void draw_list_bullet(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    for (int i = 0; i < 3; i++) {
        CGFloat y = 0.2 + i * 0.3, d = 0.14;
        [[NSBezierPath bezierPathWithOvalInRect:part(r, 0.06, y - d / 2, d, d)] fill];
        [p moveToPoint:at(r, 0.34, y)];
        [p lineToPoint:at(r, 0.94, y)];
    }
    [p stroke];
}
static void draw_gear(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line * 1.6);
    for (int i = 0; i < 8; i++) {
        CGFloat a = i * M_PI / 4;
        [p moveToPoint:at(r, 0.5 + 0.3 * cos(a), 0.5 + 0.3 * sin(a))];
        [p lineToPoint:at(r, 0.5 + 0.44 * cos(a), 0.5 + 0.44 * sin(a))];
    }
    [p stroke];
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:part(r, 0.2, 0.2, 0.6, 0.6)];
    [ring setLineWidth:line];
    [ring stroke];
    NSBezierPath *hub = [NSBezierPath bezierPathWithOvalInRect:part(r, 0.38, 0.38, 0.24, 0.24)];
    [hub setLineWidth:line];
    [hub stroke];
}
static void draw_folder(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.06, 0.2)];
    [p lineToPoint:at(r, 0.38, 0.2)];
    [p lineToPoint:at(r, 0.46, 0.3)];
    [p lineToPoint:at(r, 0.94, 0.3)];
    [p lineToPoint:at(r, 0.94, 0.86)];
    [p lineToPoint:at(r, 0.06, 0.86)];
    [p closePath];
    [p moveToPoint:at(r, 0.06, 0.42)];
    [p lineToPoint:at(r, 0.94, 0.42)];
    [p stroke];
}
static void draw_doc(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.16, 0.04)];
    [p lineToPoint:at(r, 0.6, 0.04)];
    [p lineToPoint:at(r, 0.84, 0.28)];
    [p lineToPoint:at(r, 0.84, 0.96)];
    [p lineToPoint:at(r, 0.16, 0.96)];
    [p closePath];
    [p moveToPoint:at(r, 0.6, 0.04)];
    [p lineToPoint:at(r, 0.6, 0.28)];
    [p lineToPoint:at(r, 0.84, 0.28)];
    [p stroke];
}
static void draw_share(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.34, 0.4)];
    [p lineToPoint:at(r, 0.16, 0.4)];
    [p lineToPoint:at(r, 0.16, 0.96)];
    [p lineToPoint:at(r, 0.84, 0.96)];
    [p lineToPoint:at(r, 0.84, 0.4)];
    [p lineToPoint:at(r, 0.66, 0.4)];
    [p moveToPoint:at(r, 0.5, 0.64)];
    [p lineToPoint:at(r, 0.5, 0.04)];
    [p moveToPoint:at(r, 0.32, 0.2)];
    [p lineToPoint:at(r, 0.5, 0.04)];
    [p lineToPoint:at(r, 0.68, 0.2)];
    [p stroke];
}
static void draw_info_circle(NSRect r, CGFloat line)
{
    draw_circle(r, line);
    NSBezierPath *p = stroke_path(line * 1.2);
    [p moveToPoint:at(r, 0.5, 0.46)];
    [p lineToPoint:at(r, 0.5, 0.74)];
    [p stroke];
    CGFloat d = 0.1;
    [[NSBezierPath bezierPathWithOvalInRect:part(r, 0.5 - d / 2, 0.27, d, d)] fill];
}
static void draw_arrow_clockwise(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p appendBezierPathWithArcWithCenter:at(r, 0.5, 0.54) radius:NSWidth(r) * 0.36 startAngle:-60 endAngle:240 clockwise:NO];
    [p stroke];
    NSPoint tip = NSMakePoint(NSMidX(r) + NSWidth(r) * 0.36 * cos(-60 * M_PI / 180),
                              NSMinY(r) + NSHeight(r) * 0.54 + NSWidth(r) * 0.36 * sin(-60 * M_PI / 180));
    NSBezierPath *h = stroke_path(line);
    [h moveToPoint:NSMakePoint(tip.x - NSWidth(r) * 0.2, tip.y + NSHeight(r) * 0.02)];
    [h lineToPoint:tip];
    [h lineToPoint:NSMakePoint(tip.x + NSWidth(r) * 0.02, tip.y + NSHeight(r) * 0.22)];
    [h stroke];
}
static void draw_square_grid(NSRect r, CGFloat line)
{
    for (int i = 0; i < 4; i++)
        stroke_rounded(part(r, 0.06 + (i % 2) * 0.5, 0.06 + (i / 2) * 0.5, 0.38, 0.38), NSWidth(r) * 0.06, line);
}
static void draw_sidebar_left(NSRect r, CGFloat line)
{
    stroke_rounded(part(r, 0.04, 0.12, 0.92, 0.76), NSWidth(r) * 0.1, line);
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.36, 0.14)];
    [p lineToPoint:at(r, 0.36, 0.86)];
    [p stroke];
}
static void draw_sidebar_right(NSRect r, CGFloat line)
{
    stroke_rounded(part(r, 0.04, 0.12, 0.92, 0.76), NSWidth(r) * 0.1, line);
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.64, 0.14)];
    [p lineToPoint:at(r, 0.64, 0.86)];
    [p stroke];
}
/* a square inside a ring, and filled, a square cut out of a disc */
static void draw_stop_circle(NSRect r, CGFloat line)
{
    draw_circle(r, line);
    [[NSBezierPath bezierPathWithRoundedRect:part(r, 0.36, 0.36, 0.28, 0.28) xRadius:NSWidth(r) * 0.03
                                     yRadius:NSWidth(r) * 0.03] fill];
}
static void draw_stop_circle_fill(NSRect r, CGFloat line)
{
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:part(r, 0.06, 0.06, 0.88, 0.88)];
    [p appendBezierPath:[NSBezierPath bezierPathWithRect:part(r, 0.36, 0.36, 0.28, 0.28)]];
    p.windingRule = NSWindingRuleEvenOdd;
    [p fill];
}
static void draw_star(NSRect r, CGFloat line, BOOL fill)
{
    NSBezierPath *p = stroke_path(line);
    for (int i = 0; i < 10; i++) {
        CGFloat a = -M_PI / 2 + i * M_PI / 5, k = i % 2 ? 0.2 : 0.46;
        NSPoint q = at(r, 0.5 + k * cos(a), 0.54 + k * sin(a));
        if (i)
            [p lineToPoint:q];
        else
            [p moveToPoint:q];
    }
    [p closePath];
    if (fill)
        [p fill];
    else
        [p stroke];
}
static void draw_star_line(NSRect r, CGFloat line) { draw_star(r, line, NO); }
static void draw_star_fill(NSRect r, CGFloat line) { draw_star(r, line, YES); }
static void draw_house(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.04, 0.5)];
    [p lineToPoint:at(r, 0.5, 0.08)];
    [p lineToPoint:at(r, 0.96, 0.5)];
    [p moveToPoint:at(r, 0.18, 0.4)];
    [p lineToPoint:at(r, 0.18, 0.92)];
    [p lineToPoint:at(r, 0.82, 0.92)];
    [p lineToPoint:at(r, 0.82, 0.4)];
    [p stroke];
}
static void draw_person(NSRect r, CGFloat line)
{
    NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:part(r, 0.32, 0.06, 0.36, 0.36)];
    [head setLineWidth:line];
    [head stroke];
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.1, 0.94)];
    [p curveToPoint:at(r, 0.9, 0.94) controlPoint1:at(r, 0.12, 0.48) controlPoint2:at(r, 0.88, 0.48)];
    [p closePath];
    [p stroke];
}
static void draw_bell(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.1, 0.78)];
    [p lineToPoint:at(r, 0.9, 0.78)];
    [p curveToPoint:at(r, 0.78, 0.4) controlPoint1:at(r, 0.8, 0.68) controlPoint2:at(r, 0.78, 0.6)];
    [p curveToPoint:at(r, 0.22, 0.4) controlPoint1:at(r, 0.78, 0.04) controlPoint2:at(r, 0.22, 0.04)];
    [p curveToPoint:at(r, 0.1, 0.78) controlPoint1:at(r, 0.22, 0.6) controlPoint2:at(r, 0.2, 0.68)];
    [p moveToPoint:at(r, 0.4, 0.9)];
    [p lineToPoint:at(r, 0.6, 0.9)];
    [p stroke];
}
static void draw_pencil(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.12, 0.88)];
    [p lineToPoint:at(r, 0.16, 0.66)];
    [p lineToPoint:at(r, 0.72, 0.1)];
    [p lineToPoint:at(r, 0.9, 0.28)];
    [p lineToPoint:at(r, 0.34, 0.84)];
    [p closePath];
    [p moveToPoint:at(r, 0.62, 0.2)];
    [p lineToPoint:at(r, 0.8, 0.38)];
    [p stroke];
}
static void draw_paperplane(NSRect r, CGFloat line)
{
    NSBezierPath *p = stroke_path(line);
    [p moveToPoint:at(r, 0.06, 0.44)];
    [p lineToPoint:at(r, 0.94, 0.06)];
    [p lineToPoint:at(r, 0.56, 0.94)];
    [p lineToPoint:at(r, 0.44, 0.56)];
    [p closePath];
    [p moveToPoint:at(r, 0.44, 0.56)];
    [p lineToPoint:at(r, 0.94, 0.06)];
    [p stroke];
}

static symbol_drawer symbol_drawer_for(NSString *name)
{
    static NSDictionary *names;
    if (!names)
        names = [@{
            @"plus" : [NSValue valueWithPointer:(void *)draw_plus],
            @"minus" : [NSValue valueWithPointer:(void *)draw_minus],
            @"chevron.right" : [NSValue valueWithPointer:(void *)draw_chevron_right],
            @"chevron.forward" : [NSValue valueWithPointer:(void *)draw_chevron_right],
            @"chevron.left" : [NSValue valueWithPointer:(void *)draw_chevron_left],
            @"chevron.backward" : [NSValue valueWithPointer:(void *)draw_chevron_left],
            @"chevron.down" : [NSValue valueWithPointer:(void *)draw_chevron_down],
            @"chevron.up" : [NSValue valueWithPointer:(void *)draw_chevron_up],
            @"xmark" : [NSValue valueWithPointer:(void *)draw_xmark],
            @"checkmark" : [NSValue valueWithPointer:(void *)draw_checkmark],
            @"video" : [NSValue valueWithPointer:(void *)draw_video],
            @"video.fill" : [NSValue valueWithPointer:(void *)draw_video],
            @"delete.backward" : [NSValue valueWithPointer:(void *)draw_delete_backward],
            @"delete.left" : [NSValue valueWithPointer:(void *)draw_delete_backward],
            @"trash" : [NSValue valueWithPointer:(void *)draw_trash],
            @"circle" : [NSValue valueWithPointer:(void *)draw_circle],
            @"circle.fill" : [NSValue valueWithPointer:(void *)draw_circle_fill],
            @"ellipsis" : [NSValue valueWithPointer:(void *)draw_ellipsis],
            @"magnifyingglass" : [NSValue valueWithPointer:(void *)draw_magnifier],
            @"play" : [NSValue valueWithPointer:(void *)draw_play],
            @"play.fill" : [NSValue valueWithPointer:(void *)draw_play_fill],
            @"pause" : [NSValue valueWithPointer:(void *)draw_pause],
            @"pause.fill" : [NSValue valueWithPointer:(void *)draw_pause_fill],
            @"stop" : [NSValue valueWithPointer:(void *)draw_stop],
            @"stop.fill" : [NSValue valueWithPointer:(void *)draw_stop_fill],
            @"forward.fill" : [NSValue valueWithPointer:(void *)draw_forward_fill],
            @"backward.fill" : [NSValue valueWithPointer:(void *)draw_backward_fill],
            @"film" : [NSValue valueWithPointer:(void *)draw_film],
            @"photo" : [NSValue valueWithPointer:(void *)draw_photo],
            @"photo.badge.plus" : [NSValue valueWithPointer:(void *)draw_photo_badge_plus],
            @"photo.stack" : [NSValue valueWithPointer:(void *)draw_photo_stack],
            @"photo.on.rectangle" : [NSValue valueWithPointer:(void *)draw_photo_stack],
            @"slider.horizontal.3" : [NSValue valueWithPointer:(void *)draw_sliders],
            @"eye" : [NSValue valueWithPointer:(void *)draw_eye],
            @"text.viewfinder" : [NSValue valueWithPointer:(void *)draw_viewfinder_text],
            @"list.bullet" : [NSValue valueWithPointer:(void *)draw_list_bullet],
            @"gearshape" : [NSValue valueWithPointer:(void *)draw_gear],
            @"gear" : [NSValue valueWithPointer:(void *)draw_gear],
            @"folder" : [NSValue valueWithPointer:(void *)draw_folder],
            @"doc" : [NSValue valueWithPointer:(void *)draw_doc],
            @"square.and.arrow.up" : [NSValue valueWithPointer:(void *)draw_share],
            @"info.circle" : [NSValue valueWithPointer:(void *)draw_info_circle],
            @"arrow.clockwise" : [NSValue valueWithPointer:(void *)draw_arrow_clockwise],
            @"square.grid.2x2" : [NSValue valueWithPointer:(void *)draw_square_grid],
            @"sidebar.left" : [NSValue valueWithPointer:(void *)draw_sidebar_left],
            @"sidebar.right" : [NSValue valueWithPointer:(void *)draw_sidebar_right],
            @"stop.circle" : [NSValue valueWithPointer:(void *)draw_stop_circle],
            @"stop.circle.fill" : [NSValue valueWithPointer:(void *)draw_stop_circle_fill],
            @"star" : [NSValue valueWithPointer:(void *)draw_star_line],
            @"star.fill" : [NSValue valueWithPointer:(void *)draw_star_fill],
            @"house" : [NSValue valueWithPointer:(void *)draw_house],
            @"person" : [NSValue valueWithPointer:(void *)draw_person],
            @"bell" : [NSValue valueWithPointer:(void *)draw_bell],
            @"pencil" : [NSValue valueWithPointer:(void *)draw_pencil],
            @"square.and.pencil" : [NSValue valueWithPointer:(void *)draw_pencil],
            @"paperplane" : [NSValue valueWithPointer:(void *)draw_paperplane],
        } retain];
    return (symbol_drawer)[[names objectForKey:name] pointerValue];
}

static NSImage *symbol_image(NSString *name, NSImageSymbolConfiguration *config)
{
    symbol_drawer draw = symbol_drawer_for(name);
    if (!draw)
        return nil;
    CGFloat size = [config _ferryPointSize] > 0 ? [config _ferryPointSize] : 13;
    NSImageSymbolScale scale = [config _ferryScale];
    size *= scale == NSImageSymbolScaleSmall ? 0.8 : scale == NSImageSymbolScaleLarge ? 1.25 : 1;
    NSFontWeight weight = config ? [config _ferryWeight] : NSFontWeightRegular;
    /* the weight from ultralight's -0.8 to black's 0.62: a line of 5% to 16% of the size */
    CGFloat line = fmax(1, size * (0.095 + 0.07 * weight));
    NSColor *color = [config _ferryColor];
    CGFloat side = ceil(size * 1.15);
    NSImage *image = [NSImage imageWithSize:NSMakeSize(side, side)
                                    flipped:YES
                             drawingHandler:^BOOL(NSRect dst) {
                               [(color ?: [NSColor blackColor]) set];
                               draw(NSInsetRect(dst, side * 0.12, side * 0.12), line);
                               return YES;
                             }];
    [image setTemplate:color == nil];
    [image setAccessibilityDescription:name];
    objc_setAssociatedObject(image, &symbol_name_key, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (config)
        objc_setAssociatedObject(image, &symbol_config_key, config, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return image;
}

@implementation NSImage (FerrySymbols)
+ (NSImage *)imageWithSystemSymbolName:(NSString *)symbolName accessibilityDescription:(NSString *)description
{
    NSImage *image = symbol_image(symbolName, nil);
    if (description)
        [image setAccessibilityDescription:description];
    return image;
}
@end

@implementation NSImage (NSImageSymbolConfiguration)
- (NSImage *)imageWithSymbolConfiguration:(NSImageSymbolConfiguration *)config
{
    NSString *name = objc_getAssociatedObject(self, &symbol_name_key);
    if (!name)
        return self;
    NSImageSymbolConfiguration *now = [self symbolConfiguration];
    return symbol_image(name, now && config ? [now configurationByApplyingConfiguration:config] : config ?: now);
}
- (NSImageSymbolConfiguration *)symbolConfiguration { return objc_getAssociatedObject(self, &symbol_config_key); }
@end

static char button_config_key;
@implementation NSButton (NSImageSymbolConfiguration)
- (NSImageSymbolConfiguration *)symbolConfiguration { return objc_getAssociatedObject(self, &button_config_key); }
- (void)setSymbolConfiguration:(NSImageSymbolConfiguration *)c
{
    objc_setAssociatedObject(self, &button_config_key, c, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if ([self image] && c)
        [self setImage:[[self image] imageWithSymbolConfiguration:c]];
}
@end
@implementation NSImageView (NSImageSymbolConfiguration)
- (NSImageSymbolConfiguration *)symbolConfiguration { return objc_getAssociatedObject(self, &button_config_key); }
- (void)setSymbolConfiguration:(NSImageSymbolConfiguration *)c
{
    objc_setAssociatedObject(self, &button_config_key, c, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if ([self image] && c)
        [self setImage:[[self image] imageWithSymbolConfiguration:c]];
}
@end

/* ---- menus ---------------------------------------------------------------------------------- */

static char header_key, visibility_key, attributed_key;

@implementation NSMenuItem (FerryNewer)
+ (NSMenuItem *)sectionHeaderWithTitle:(NSString *)title
{
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title ?: @"" action:NULL keyEquivalent:@""] autorelease];
    [item setEnabled:NO];
    objc_setAssociatedObject(item, &header_key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return item;
}
- (BOOL)isSectionHeader { return objc_getAssociatedObject(self, &header_key) != nil; }
- (NSAttributedString *)attributedTitle { return objc_getAssociatedObject(self, &attributed_key); }
- (void)setAttributedTitle:(NSAttributedString *)t
{
    objc_setAssociatedObject(self, &attributed_key, t, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (t)
        [self setTitle:[t string]];
}
- (NSMenuItemImageVisibility)preferredImageVisibility { return [objc_getAssociatedObject(self, &visibility_key) integerValue]; }
- (void)setPreferredImageVisibility:(NSMenuItemImageVisibility)v
{
    objc_setAssociatedObject(self, &visibility_key, v ? @(v) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* ---- colours -------------------------------------------------------------------------------- */

#define FILL(name, opacity)                                                                                              \
    +(NSColor *)name                                                                                                   \
    {                                                                                                                  \
        static NSColor *c;                                                                                             \
        if (!c) {                                                                                                      \
            const CGFloat light[4] = {0, 0, 0, opacity}, dark[4] = {1, 1, 1, opacity * 1.6};                           \
            c = [ADynamicColor(@ #name, light, dark) retain];                                                          \
        }                                                                                                              \
        return c;                                                                                                      \
    }
@implementation NSColor (FerrySystemFills)
FILL(systemFillColor, 0.10)
FILL(secondarySystemFillColor, 0.08)
FILL(tertiarySystemFillColor, 0.05)
FILL(quaternarySystemFillColor, 0.03)
FILL(quinarySystemFillColor, 0.02)
/* a colour that asks the provider for itself in the appearance it's drawn
 * in (freemac 1.245) */
+ (NSColor *)colorWithName:(NSColorName)name dynamicProvider:(NSColor * (^)(NSAppearance *))provider
{
    return provider ? AColorWithProvider(name, provider) : [NSColor clearColor];
}
@end
#undef FILL

/* ---- popovers ------------------------------------------------------------------------------- */

static char full_size_key;
@implementation NSPopover (FerryNewer)
- (BOOL)hasFullSizeContent { return objc_getAssociatedObject(self, &full_size_key) != nil; }
- (void)setHasFullSizeContent:(BOOL)f
{
    objc_setAssociatedObject(self, &full_size_key, f ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* ---- events --------------------------------------------------------------------------------- */

@implementation NSEvent (FerryPhases)
- (NSEventPhase)phase { return NSEventPhaseNone; }
- (NSEventPhase)momentumPhase { return NSEventPhaseNone; }
+ (BOOL)isSwipeTrackingFromScrollEventsEnabled { return NO; }
- (void)trackSwipeEventWithOptions:(NSEventSwipeTrackingOptions)options
          dampenAmountThresholdMin:(CGFloat)minDampen
                               max:(CGFloat)maxDampen
                      usingHandler:(void (^)(CGFloat, NSEventPhase, BOOL, BOOL *))handler
{
    if (!handler)
        return;
    CGFloat dx = [self scrollingDeltaX];
    CGFloat amount = dx > 0 ? 1 : dx < 0 ? -1 : 0;
    amount = fmax(minDampen, fmin(maxDampen, amount));
    BOOL stop = NO;
    handler(amount, NSEventPhaseEnded, YES, &stop);
}
@end

/* ---- controls ------------------------------------------------------------------------------- */

static char refuses_key, expansion_key, destructive_key, prominence_key, identifier_key;

@implementation NSControl (FerryRefusesFirstResponder)
- (BOOL)refusesFirstResponder
{
    id cell = [self respondsToSelector:@selector(cell)] ? [self cell] : nil;
    if (cell)
        return [cell refusesFirstResponder];
    return objc_getAssociatedObject(self, &refuses_key) != nil;
}
- (void)setRefusesFirstResponder:(BOOL)r
{
    id cell = [self respondsToSelector:@selector(cell)] ? [self cell] : nil;
    [cell setRefusesFirstResponder:r];
    objc_setAssociatedObject(self, &refuses_key, r ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSTextField (FerryNewer)
- (BOOL)allowsExpansionToolTips { return objc_getAssociatedObject(self, &expansion_key) != nil; }
- (void)setAllowsExpansionToolTips:(BOOL)a
{
    objc_setAssociatedObject(self, &expansion_key, a ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSTextView (FerryTextLayoutManager)
- (instancetype)initUsingTextLayoutManager:(BOOL)usingTextLayoutManager
{
    return [self initWithFrame:NSZeroRect];
}
+ (instancetype)textViewUsingTextLayoutManager:(BOOL)usingTextLayoutManager
{
    return [[[self alloc] initUsingTextLayoutManager:usingTextLayoutManager] autorelease];
}
@end

@implementation NSButton (FerryNewer)
- (BOOL)hasDestructiveAction { return objc_getAssociatedObject(self, &destructive_key) != nil; }
- (void)setHasDestructiveAction:(BOOL)d
{
    objc_setAssociatedObject(self, &destructive_key, d ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSTintProminence)tintProminence { return [objc_getAssociatedObject(self, &prominence_key) integerValue]; }
- (void)setTintProminence:(NSTintProminence)p
{
    objc_setAssociatedObject(self, &prominence_key, p ? @(p) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSSlider (FerryNewer)
- (NSTintProminence)tintProminence { return [objc_getAssociatedObject(self, &prominence_key) integerValue]; }
- (void)setTintProminence:(NSTintProminence)p
{
    objc_setAssociatedObject(self, &prominence_key, p ? @(p) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSApplication (FerryNewer)
- (void)unhideWithoutActivation { [self unhide:nil]; }
@end

@implementation NSViewController (FerryIdentifier)
- (NSUserInterfaceItemIdentifier)identifier { return objc_getAssociatedObject(self, &identifier_key); }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)i
{
    objc_setAssociatedObject(self, &identifier_key, i, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

/* ---- older calls ---- */

@implementation NSCell (FerryFieldEditing)
- (void)editWithFrame:(NSRect)rect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)delegate
                event:(NSEvent *)event
{
    if ([controlView isKindOfClass:[NSTextField class]])
        [(NSTextField *)controlView selectText:nil];
}
- (void)selectWithFrame:(NSRect)rect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)delegate
                  start:(NSInteger)selStart length:(NSInteger)selLength
{
    if (![controlView isKindOfClass:[NSTextField class]])
        return;
    NSTextField *field = (NSTextField *)controlView;
    [field selectText:nil];
    NSUInteger n = [[field stringValue] length];
    NSUInteger start = MIN((NSUInteger)MAX(selStart, 0), n);
    [(NSText *)[field currentEditor] setSelectedRange:NSMakeRange(start, MIN((NSUInteger)MAX(selLength, 0), n - start))];
}
- (void)endEditing:(NSText *)textObj
{
    NSView *v = [self controlView];
    NSWindow *w = [v window];
    if (w && [w firstResponder] == (NSResponder *)v)
        [w makeFirstResponder:nil];
}
@end

@implementation NSCell (FerryFocusRingMask)
- (void)drawFocusRingMaskWithFrame:(NSRect)frame inView:(NSView *)view
{
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 1, 1) xRadius:5 yRadius:5] fill];
}
- (NSRect)focusRingMaskBoundsForFrame:(NSRect)frame inView:(NSView *)view { return frame; }
@end

static char button_background_key;
@implementation NSButtonCell (FerryBackgroundColor)
- (NSColor *)backgroundColor { return objc_getAssociatedObject(self, &button_background_key); }
- (void)setBackgroundColor:(NSColor *)c
{
    objc_setAssociatedObject(self, &button_background_key, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self controlView] setNeedsDisplay:YES];
}
@end

@implementation NSTextField (FerryMnemonic)
- (void)setTitleWithMnemonic:(NSString *)s
{
    NSRange amp = [s rangeOfString:@"&"];
    if (amp.location == NSNotFound)
        [self setStringValue:s ?: @""];
    else
        [self setStringValue:[[s substringToIndex:amp.location] stringByAppendingString:[s substringFromIndex:amp.location + 1]]];
}
@end

/* ---- haptic feedback (freemac 1.260) -------------------------------------------- */

/* A PC has no Force Touch trackpad, so feedback is accepted and nothing is
 * felt, as on a Mac without one. */
@interface AHapticPerformer : NSObject <NSHapticFeedbackPerformer>
@end
@implementation AHapticPerformer
- (void)performFeedbackPattern:(NSHapticFeedbackPattern)pattern
               performanceTime:(NSHapticFeedbackPerformanceTime)performanceTime
{
}
@end

@implementation NSHapticFeedbackManager
+ (id<NSHapticFeedbackPerformer>)defaultPerformer
{
    static AHapticPerformer *performer;
    if (!performer)
        performer = [[AHapticPerformer alloc] init];
    return performer;
}
@end

/* macOS 11: the line under a window's title bar, kept for the app to read
 * back (freemac 1.264, HandBrake's queue window) */
static char separator_key;
@implementation NSWindow (FerryTitlebarSeparator)
- (NSTitlebarSeparatorStyle)titlebarSeparatorStyle
{
    return [objc_getAssociatedObject(self, &separator_key) integerValue];
}
- (void)setTitlebarSeparatorStyle:(NSTitlebarSeparatorStyle)style
{
    objc_setAssociatedObject(self, &separator_key, style ? @(style) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
