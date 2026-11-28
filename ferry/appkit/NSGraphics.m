/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: drawing. NSGraphicsContext wraps a Core Graphics context;
 * NSColor, NSFont, NSParagraphStyle, NSBezierPath and string drawing draw in
 * the current one, as on a Mac. NSFont is a Core Text font and
 * NSParagraphStyle a Core Text paragraph style (see AInternal.h), so
 * attributed strings made for AppKit lay out with Core Text unchanged. */
#import "AInternal.h"

void AWarnOnce(const char *what)
{
    static NSMutableSet *said;
    if (!said)
        said = [[NSMutableSet alloc] init];
    NSString *key = @(what);
    if ([said containsObject:key])
        return;
    [said addObject:key];
    fflush(stdout);
    fprintf(stderr, "AppKit (Ferry): %s isn't supported yet\n", what);
}

void ANoteOnce(const char *sentence)
{
    static NSMutableSet *said;
    if (!said)
        said = [[NSMutableSet alloc] init];
    NSString *key = @(sentence);
    if ([said containsObject:key])
        return;
    [said addObject:key];
    fflush(stdout);
    fprintf(stderr, "AppKit (Ferry): %s\n", sentence);
}

void AMainThreadOnly(const char *what)
{
    static int said;
    if (pthread_main_np() || __atomic_exchange_n(&said, 1, __ATOMIC_ACQ_REL))
        return;
    fprintf(stderr, "AppKit (Ferry): %s was called off the main thread; AppKit is for the main thread only, and "
                    "Ferry doesn't make it safe on others\n",
            what);
}

/* ---- NSGraphicsContext ---------------------------------------------------------- */

@implementation NSGraphicsContext {
    CGContextRef _cg;
    BOOL _flipped, _screen, _antialias;
    NSCompositingOperation _op;
}

static NSGraphicsContext *current_context;
static NSMutableArray *context_stack;

+ (NSGraphicsContext *)currentContext { return current_context; }

+ (void)setCurrentContext:(NSGraphicsContext *)context
{
    [context retain];
    [current_context release];
    current_context = context;
}

+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)cg flipped:(BOOL)flipped
{
    NSGraphicsContext *c = [[self alloc] init];
    c->_cg = CGContextRetain(cg);
    c->_flipped = flipped;
    c->_antialias = YES;
    c->_op = NSCompositingOperationSourceOver;
    return [c autorelease];
}

+ (NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)rep
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(rep.bitmapData, rep.pixelsWide, rep.pixelsHigh, 8, rep.bytesPerRow,
                                            space, rep.hasAlpha ? kCGImageAlphaPremultipliedLast
                                                                : kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (!cg)
        return nil;
    /* points, not pixels, when the bitmap is larger than its size */
    if (rep.size.width > 0 && rep.size.height > 0)
        CGContextScaleCTM(cg, rep.pixelsWide / rep.size.width, rep.pixelsHigh / rep.size.height);
    NSGraphicsContext *c = [self graphicsContextWithCGContext:cg flipped:NO];
    CGContextRelease(cg);
    return c;
}

+ (void)saveGraphicsState
{
    if (!context_stack)
        context_stack = [[NSMutableArray alloc] init];
    [context_stack addObject:current_context ?: (id)[NSNull null]];
    [current_context saveGraphicsState];
}

+ (void)restoreGraphicsState
{
    if (![context_stack count])
        return;
    id c = [[context_stack lastObject] retain];
    [context_stack removeLastObject];
    [self setCurrentContext:c == [NSNull null] ? nil : c];
    [current_context restoreGraphicsState];
    [c release];
}

+ (BOOL)currentContextDrawingToScreen { return current_context ? current_context->_screen : YES; }

- (void)dealloc
{
    CGContextRelease(_cg);
    [super dealloc];
}

- (CGContextRef)CGContext { return _cg; }
- (BOOL)isFlipped { return _flipped; }
- (BOOL)isDrawingToScreen { return _screen; }
- (void)_setDrawingToScreen:(BOOL)screen { _screen = screen; }
- (BOOL)shouldAntialias { return _antialias; }
- (void)setShouldAntialias:(BOOL)flag
{
    _antialias = flag;
    CGContextSetShouldAntialias(_cg, flag);
}
- (NSCompositingOperation)compositingOperation { return _op; }
- (void)setCompositingOperation:(NSCompositingOperation)op
{
    static const CGBlendMode modes[] = {
        kCGBlendModeClear, kCGBlendModeCopy, kCGBlendModeNormal, kCGBlendModeSourceIn, kCGBlendModeSourceOut,
        kCGBlendModeSourceAtop, kCGBlendModeDestinationOver, kCGBlendModeDestinationIn,
        kCGBlendModeDestinationOut, kCGBlendModeDestinationAtop, kCGBlendModeXOR, kCGBlendModePlusDarker,
        kCGBlendModeNormal, kCGBlendModePlusLighter,
    };
    _op = op;
    CGContextSetBlendMode(_cg, op < sizeof modes / sizeof modes[0] ? modes[op] : kCGBlendModeNormal);
}
- (void)saveGraphicsState { CGContextSaveGState(_cg); }
- (void)restoreGraphicsState { CGContextRestoreGState(_cg); }
- (void)flushGraphics { CGContextFlush(_cg); }
@end

static CGContextRef current_cg(void) { return current_context ? [current_context CGContext] : NULL; }

/* ---- NSColor ------------------------------------------------------------------------ */

NSString *const NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";
NSString *const NSDeviceRGBColorSpace = @"NSDeviceRGBColorSpace";
NSString *const NSCalibratedWhiteColorSpace = @"NSCalibratedWhiteColorSpace";
NSString *const NSDeviceWhiteColorSpace = @"NSDeviceWhiteColorSpace";
NSString *const NSDeviceCMYKColorSpace = @"NSDeviceCMYKColorSpace";
NSString *const NSNamedColorSpace = @"NSNamedColorSpace";
NSString *const NSPatternColorSpace = @"NSPatternColorSpace";
NSString *const NSCustomColorSpace = @"NSCustomColorSpace";

@implementation NSColor {
    CGFloat _c[4];      /* sRGB, not premultiplied */
    BOOL _gray;
    CGColorRef _cg;
    /* A colour that changes with the appearance (freemac 1.245, Ferry
     * 0.68.0): a system colour has its components in the dark appearance
     * too; one an app makes with colorWithName:dynamicProvider: asks its
     * provider, once for light and once for dark. */
    BOOL _dynamic;
    CGFloat _d[4];
    CGColorRef _cg_dark;
    NSString *_name;
    NSColor * (^_provider)(NSAppearance *);
    NSColor *_made[2];
    /* A colour made in, or turned into, a Lab space (freemac 1.NEXT) keeps
     * its components there as well as in sRGB: MacVim works out its tab
     * bar's colours from their lightness. */
    NSColorSpace *_space;
    CGFloat _k[4];
    NSInteger _nk;
}

static CGFloat clamp01(CGFloat v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

static NSColor *make_color(CGFloat r, CGFloat g, CGFloat b, CGFloat a, BOOL gray)
{
    NSColor *c = [[NSColor alloc] init];
    c->_c[0] = clamp01(r);
    c->_c[1] = clamp01(g);
    c->_c[2] = clamp01(b);
    c->_c[3] = clamp01(a);
    c->_gray = gray;
    return [c autorelease];
}

void GColorLabToSRGB(const CGFloat lab[3], CGFloat rgb[3]);
void GColorSRGBToLab(const CGFloat rgb[3], CGFloat lab[3]);

/* A colour in a Lab space, from its L*, a*, b* and alpha (AppKit's
 * colorWithColorSpace:components:count: and colorUsingColorSpace:). */
NSColor *FerryColorWithComponents(NSColorSpace *space, const CGFloat *k, NSInteger count)
{
    if ([space colorSpaceModel] != NSColorSpaceModelLAB || count < 3)
        return nil;
    CGFloat rgb[3];
    GColorLabToSRGB(k, rgb);
    NSColor *c = make_color(rgb[0], rgb[1], rgb[2], count > 3 ? k[3] : 1, NO);
    c->_space = [space retain];
    c->_nk = 4;
    memcpy(c->_k, k, 3 * sizeof *k);
    c->_k[3] = count > 3 ? k[3] : 1;
    return c;
}

static NSColor *make_dynamic(NSString *name, const CGFloat light[4], const CGFloat dark[4])
{
    NSColor *c = make_color(light[0], light[1], light[2], light[3], NO);
    c->_dynamic = YES;
    for (int i = 0; i < 4; i++)
        c->_d[i] = clamp01(dark[i]);
    c->_name = [name copy];
    return c;
}

/* the colour a provider gives in the light or dark appearance */
static NSColor *provided(NSColor *c, BOOL dark)
{
    if (!c->_made[dark]) {
        NSAppearance *a = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        NSColor *made = c->_provider(a);
        c->_made[dark] = [made == c ? nil : made retain];
    }
    return c->_made[dark];
}

/* the components drawing uses now */
static const CGFloat *comps(NSColor *c)
{
    for (int depth = 0; c && c->_dynamic && depth < 8; depth++) {
        BOOL dark = ADrawsDark();
        if (!c->_provider)
            return dark ? c->_d : c->_c;
        NSColor *made = provided(c, dark);
        if (!made)
            break;
        c = made;
    }
    return c->_c;
}

/* this colour as it is drawn now, a colour that stays the same */
static NSColor *resolved(NSColor *c)
{
    if (!c->_dynamic)
        return c;
    const CGFloat *v = comps(c);
    return make_color(v[0], v[1], v[2], v[3], NO);
}

static void hsb_to_rgb(CGFloat h, CGFloat s, CGFloat v, CGFloat *r, CGFloat *g, CGFloat *b)
{
    h = fmod(h, 1.0) * 6;
    if (h < 0)
        h += 6;
    int i = (int)h;
    CGFloat f = h - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
    switch (i % 6) {
    case 0: *r = v, *g = t, *b = p; break;
    case 1: *r = q, *g = v, *b = p; break;
    case 2: *r = p, *g = v, *b = t; break;
    case 3: *r = p, *g = q, *b = v; break;
    case 4: *r = t, *g = p, *b = v; break;
    default: *r = v, *g = p, *b = q; break;
    }
}

+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a
{
    return make_color(r, g, b, a, NO);
}
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a
{
    return make_color(r, g, b, a, NO);
}
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a
{
    return make_color(r, g, b, a, NO);
}
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a
{
    return make_color(r, g, b, a, NO);
}
+ (NSColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a { return make_color(w, w, w, a, YES); }
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a { return make_color(w, w, w, a, YES); }
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a { return make_color(w, w, w, a, YES); }
+ (NSColor *)colorWithGenericGamma22White:(CGFloat)w alpha:(CGFloat)a { return make_color(w, w, w, a, YES); }
/* A pattern colour keeps its image for patternImage. A window's
 * background tiles it (NSWindow.m); other fills use the image's average
 * colour. */
static char pattern_key;
+ (NSColor *)colorWithPatternImage:(NSImage *)image
{
    CGFloat rgba[4] = {0.9, 0.9, 0.9, 1};
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cg) {
        /* averaged by drawing the image into one pixel */
        unsigned char px[4] = {0};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(px, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
        CGContextDrawImage(c, CGRectMake(0, 0, 1, 1), cg);
        CGContextRelease(c);
        if (px[3])
            for (int i = 0; i < 3; i++)
                rgba[i] = px[i] / (CGFloat)px[3];
        rgba[3] = px[3] / 255.0;
    }
    NSColor *color = make_color(rgba[0], rgba[1], rgba[2], rgba[3], NO);
    if (image)
        objc_setAssociatedObject(color, &pattern_key, image, OBJC_ASSOCIATION_RETAIN);
    return color;
}
- (NSImage *)patternImage { return objc_getAssociatedObject(self, &pattern_key); }
+ (NSColor *)colorWithHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a
{
    CGFloat r, g, b;
    hsb_to_rgb(h, s, v, &r, &g, &b);
    return make_color(r, g, b, a, NO);
}
+ (NSColor *)colorWithCalibratedHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a
{
    return [self colorWithHue:h saturation:s brightness:v alpha:a];
}
+ (NSColor *)colorWithDeviceHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a
{
    return [self colorWithHue:h saturation:s brightness:v alpha:a];
}
+ (NSColor *)colorWithCGColor:(CGColorRef)color
{
    if (!color)
        return nil;
    GColor *g = (GColor *)color;
    return make_color(g->rgba[0], g->rgba[1], g->rgba[2], g->rgba[3], NO);
}

/* The catalogue colours: Ferry's own palette, chosen to sit well with
 * freemac's theme, light and, for the system colours, dark too. */
#define NAMED(name, r, g, b, a)                                                                                  \
    +(NSColor *)name                                                                                             \
    {                                                                                                            \
        static NSColor *c;                                                                                       \
        if (!c)                                                                                                  \
            c = [make_color(r, g, b, a, NO) retain];                                                             \
        return c;                                                                                                \
    }
/* a system colour with its components in the light and the dark appearance */
#define NAMED2(name, r, g, b, a, dr, dg, db, da)                                                                 \
    +(NSColor *)name                                                                                             \
    {                                                                                                            \
        static NSColor *c;                                                                                       \
        if (!c) {                                                                                                \
            const CGFloat light[4] = {r, g, b, a}, dark[4] = {dr, dg, db, da};                                   \
            c = [make_dynamic(@ #name, light, dark) retain];                                                     \
        }                                                                                                        \
        return c;                                                                                                \
    }
NAMED(blackColor, 0, 0, 0, 1)
NAMED(darkGrayColor, 1 / 3.0, 1 / 3.0, 1 / 3.0, 1)
NAMED(lightGrayColor, 2 / 3.0, 2 / 3.0, 2 / 3.0, 1)
NAMED(whiteColor, 1, 1, 1, 1)
NAMED(grayColor, 0.5, 0.5, 0.5, 1)
NAMED(redColor, 1, 0, 0, 1)
NAMED(greenColor, 0, 1, 0, 1)
NAMED(blueColor, 0, 0, 1, 1)
NAMED(cyanColor, 0, 1, 1, 1)
NAMED(yellowColor, 1, 1, 0, 1)
NAMED(magentaColor, 1, 0, 1, 1)
NAMED(orangeColor, 1, 0.5, 0, 1)
NAMED(purpleColor, 0.5, 0, 0.5, 1)
NAMED(brownColor, 0.6, 0.4, 0.2, 1)
NAMED(clearColor, 0, 0, 0, 0)
NAMED2(systemRedColor, 0.93, 0.26, 0.24, 1, 1.0, 0.33, 0.30, 1)
NAMED2(systemGreenColor, 0.23, 0.70, 0.33, 1, 0.27, 0.80, 0.38, 1)
NAMED2(systemBlueColor, 0.10, 0.45, 0.91, 1, 0.16, 0.52, 1.0, 1)
NAMED2(systemOrangeColor, 0.96, 0.55, 0.14, 1, 1.0, 0.62, 0.15, 1)
NAMED2(systemYellowColor, 0.98, 0.78, 0.15, 1, 1.0, 0.84, 0.16, 1)
NAMED2(systemPurpleColor, 0.62, 0.36, 0.84, 1, 0.72, 0.44, 0.94, 1)
NAMED2(systemGrayColor, 0.56, 0.56, 0.58, 1, 0.58, 0.58, 0.60, 1)
NAMED2(systemPinkColor, 0.95, 0.29, 0.48, 1, 1.0, 0.33, 0.53, 1)
NAMED2(systemBrownColor, 0.64, 0.52, 0.37, 1, 0.68, 0.56, 0.41, 1)
NAMED2(systemTealColor, 0.35, 0.68, 0.78, 1, 0.39, 0.76, 0.86, 1)
NAMED2(systemMintColor, 0.0, 0.78, 0.75, 1, 0.39, 0.89, 0.85, 1)
NAMED2(systemCyanColor, 0.38, 0.73, 0.95, 1, 0.40, 0.80, 1.0, 1)
NAMED2(systemIndigoColor, 0.37, 0.36, 0.85, 1, 0.42, 0.41, 0.95, 1)
NAMED2(labelColor, 0, 0, 0, 0.88, 1, 1, 1, 0.86)
NAMED2(secondaryLabelColor, 0, 0, 0, 0.55, 1, 1, 1, 0.55)
NAMED2(tertiaryLabelColor, 0, 0, 0, 0.3, 1, 1, 1, 0.26)
NAMED2(textColor, 0, 0, 0, 1, 1, 1, 1, 1)
NAMED2(textBackgroundColor, 1, 1, 1, 1, 0.12, 0.12, 0.13, 1)
NAMED2(selectedTextColor, 0, 0, 0, 1, 1, 1, 1, 1)
NAMED2(selectedTextBackgroundColor, 0.70, 0.83, 1.0, 1, 0.25, 0.38, 0.58, 1)
/* the text cursor's colour, a class property since macOS 14 (Hex Fiend asks for it) */
NAMED2(textInsertionPointColor, 0.10, 0.45, 0.91, 1, 0.16, 0.52, 1.0, 1)
NAMED2(placeholderTextColor, 0, 0, 0, 0.3, 1, 1, 1, 0.26)
NAMED2(controlColor, 1, 1, 1, 1, 0.36, 0.36, 0.38, 1)
NAMED2(controlBackgroundColor, 1, 1, 1, 1, 0.12, 0.12, 0.13, 1)
NAMED2(controlTextColor, 0, 0, 0, 0.88, 1, 1, 1, 0.86)
NAMED2(disabledControlTextColor, 0, 0, 0, 0.3, 1, 1, 1, 0.26)
NAMED2(selectedControlColor, 0.70, 0.83, 1.0, 1, 0.25, 0.38, 0.58, 1)
NAMED2(windowBackgroundColor, 0.93, 0.93, 0.93, 1, 0.19, 0.19, 0.20, 1)
NAMED2(underPageBackgroundColor, 0.59, 0.59, 0.59, 1, 0.14, 0.14, 0.15, 1)
NAMED2(gridColor, 0.88, 0.88, 0.88, 1, 0.28, 0.28, 0.29, 1)
NAMED2(separatorColor, 0, 0, 0, 0.1, 1, 1, 1, 0.1)
NAMED2(controlAccentColor, 0.10, 0.45, 0.91, 1, 0.16, 0.52, 1.0, 1)
NAMED2(keyboardFocusIndicatorColor, 0.10, 0.45, 0.91, 0.5, 0.16, 0.52, 1.0, 0.5)
NAMED2(alternateSelectedControlColor, 0.10, 0.45, 0.91, 1, 0.16, 0.52, 1.0, 1)
NAMED2(headerTextColor, 0, 0, 0, 0.88, 1, 1, 1, 0.86)
/* a table header's text since 10.14, and Interface Builder's colour for a source
 * list's headings and many labels (VLC's "Drop media here") */
NAMED2(headerColor, 0, 0, 0, 0.85, 1, 1, 1, 0.85)
/* Interface Builder's colour for a source list's background: a sidebar's grey */
NAMED2(_sourceListBackgroundColor, 0.94, 0.94, 0.94, 1, 0.16, 0.16, 0.17, 1)
NAMED2(linkColor, 0.0, 0.40, 0.85, 1, 0.25, 0.60, 1.0, 1)
/* the older system colours (freemac 1.221, Ferry 0.45.0) */
NAMED2(windowFrameColor, 0.80, 0.80, 0.80, 1, 0.30, 0.30, 0.31, 1)
NAMED2(windowFrameTextColor, 0, 0, 0, 0.88, 1, 1, 1, 0.86)
NAMED2(scrollBarColor, 0.90, 0.90, 0.90, 1, 0.22, 0.22, 0.23, 1)
NAMED2(knobColor, 0, 0, 0, 0.45, 1, 1, 1, 0.45)
NAMED2(selectedKnobColor, 0, 0, 0, 0.6, 1, 1, 1, 0.6)
NAMED2(highlightColor, 1, 1, 1, 1, 0.70, 0.70, 0.72, 1)
NAMED(shadowColor, 0, 0, 0, 1)
NAMED2(controlHighlightColor, 0.85, 0.85, 0.85, 1, 0.32, 0.32, 0.33, 1)
NAMED2(controlLightHighlightColor, 1, 1, 1, 1, 0.40, 0.40, 0.41, 1)
NAMED2(controlShadowColor, 0.5, 0.5, 0.5, 1, 0.10, 0.10, 0.11, 1)
NAMED2(controlDarkShadowColor, 0.25, 0.25, 0.25, 1, 0.05, 0.05, 0.06, 1)
NAMED2(selectedMenuItemColor, 0.10, 0.45, 0.91, 1, 0.16, 0.52, 1.0, 1)
NAMED(selectedMenuItemTextColor, 1, 1, 1, 1)
NAMED2(quaternaryLabelColor, 0, 0, 0, 0.1, 1, 1, 1, 0.1)
NAMED2(unemphasizedSelectedTextBackgroundColor, 0.86, 0.86, 0.86, 1, 0.27, 0.27, 0.28, 1)
NAMED(findHighlightColor, 1, 0.9, 0, 1)
/* An app's named colours are in the asset catalogue ferry-actool compiled
 * into its bundle (NSAssets.m, freemac 1.224, Ferry 0.48.0); nil, as on a
 * Mac, for a name it has no colour for. */
+ (NSColor *)colorNamed:(NSString *)name { return [self colorNamed:name bundle:nil]; }
+ (NSColor *)colorNamed:(NSString *)name bundle:(NSBundle *)bundle
{
    return AAssetColor(bundle ?: [NSBundle mainBundle], name);
}

- (void)dealloc
{
    CGColorRelease(_cg);
    CGColorRelease(_cg_dark);
    [_space release];
    [_name release];
    [_provider release];
    [_made[0] release];
    [_made[1] release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSColor class]])
        return NO;
    NSColor *o = other;
    if (_dynamic || o->_dynamic)
        return _dynamic && o->_dynamic && !_provider && !o->_provider && !memcmp(_c, o->_c, sizeof _c) &&
               !memcmp(_d, o->_d, sizeof _d);
    return !memcmp(_c, o->_c, sizeof _c);
}
- (NSUInteger)hash { return (NSUInteger)(_c[0] * 255) << 24 | (NSUInteger)(_c[1] * 255) << 16 | (NSUInteger)(_c[2] * 255) << 8 | (NSUInteger)(_c[3] * 255); }
- (NSString *)description
{
    if (_dynamic)
        return [NSString stringWithFormat:@"Catalog color: System %@", _name ?: @"dynamic"];
    if (_gray)
        return [NSString stringWithFormat:@"NSCalibratedWhiteColorSpace %g %g", _c[0], _c[3]];
    return [NSString stringWithFormat:@"sRGB IEC61966-2.1 colorspace %g %g %g %g", _c[0], _c[1], _c[2], _c[3]];
}
- (NSString *)_ferryDynamicName { return _dynamic ? _name : nil; }
/* The older name for a colour's space ("Color Spaces" in Apple's Color
 * Programming Topics): a system colour is a named (catalog) colour, which
 * an app turns into components with colorUsingColorSpaceName: first, as Qt
 * does (freemac 1.267). */
- (NSString *)colorSpaceName
{
    if (_dynamic)
        return NSNamedColorSpace;
    if ([self patternImage])
        return NSPatternColorSpace;
    return _gray ? NSCalibratedWhiteColorSpace : NSCalibratedRGBColorSpace;
}

- (CGFloat)redComponent { return comps(self)[0]; }
- (CGFloat)greenComponent { return comps(self)[1]; }
- (CGFloat)blueComponent { return comps(self)[2]; }
- (CGFloat)alphaComponent { return comps(self)[3]; }
- (CGFloat)whiteComponent
{
    const CGFloat *c = comps(self);
    return _gray ? c[0] : 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
}
- (NSInteger)numberOfComponents { return _space ? _nk : _gray ? 2 : 4; }
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a
{
    const CGFloat *c = comps(self);
    if (r) *r = c[0];
    if (g) *g = c[1];
    if (b) *b = c[2];
    if (a) *a = c[3];
}
- (void)getWhite:(CGFloat *)w alpha:(CGFloat *)a
{
    if (w) *w = [self whiteComponent];
    if (a) *a = comps(self)[3];
}
- (void)getHue:(CGFloat *)h saturation:(CGFloat *)s brightness:(CGFloat *)v alpha:(CGFloat *)a
{
    const CGFloat *c = comps(self);
    CGFloat mx = fmax(c[0], fmax(c[1], c[2])), mn = fmin(c[0], fmin(c[1], c[2])), d = mx - mn, hue = 0;
    if (d > 0) {
        if (mx == c[0])
            hue = fmod((c[1] - c[2]) / d, 6);
        else if (mx == c[1])
            hue = (c[2] - c[0]) / d + 2;
        else
            hue = (c[0] - c[1]) / d + 4;
        hue /= 6;
        if (hue < 0)
            hue += 1;
    }
    if (h) *h = hue;
    if (s) *s = mx > 0 ? d / mx : 0;
    if (v) *v = mx;
    if (a) *a = c[3];
}
- (CGFloat)hueComponent { CGFloat h; [self getHue:&h saturation:NULL brightness:NULL alpha:NULL]; return h; }
- (CGFloat)saturationComponent { CGFloat s; [self getHue:NULL saturation:&s brightness:NULL alpha:NULL]; return s; }
- (CGFloat)brightnessComponent { CGFloat v; [self getHue:NULL saturation:NULL brightness:&v alpha:NULL]; return v; }

/* A dynamic colour's CGColor is the one for the appearance drawing is in
 * when it's asked for, as on a Mac. */
- (CGColorRef)CGColor
{
    if (_dynamic && _provider) {
        NSColor *made = provided(self, ADrawsDark());
        return made ? [made CGColor] : CGColorGetConstantColor(kCGColorClear);
    }
    if (_dynamic && ADrawsDark()) {
        if (!_cg_dark)
            _cg_dark = CGColorCreateSRGB(_d[0], _d[1], _d[2], _d[3]);
        return _cg_dark;
    }
    if (!_cg)
        _cg = CGColorCreateSRGB(_c[0], _c[1], _c[2], _c[3]);
    return _cg;
}
/* a system colour with less alpha changes with the appearance too */
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha
{
    if (_dynamic) {
        CGFloat light[4], dark[4];
        if (_provider) {
            NSColor *l = provided(self, NO), *d = provided(self, YES);
            memcpy(light, l ? l->_c : _c, sizeof light);
            memcpy(dark, d ? d->_c : _c, sizeof dark);
            if (l && l->_dynamic)
                memcpy(light, l->_c, sizeof light);
            if (d && d->_dynamic)
                memcpy(dark, d->_d, sizeof dark);
        } else {
            memcpy(light, _c, sizeof light);
            memcpy(dark, _d, sizeof dark);
        }
        light[3] = dark[3] = alpha;
        return make_dynamic(_name, light, dark);
    }
    return make_color(_c[0], _c[1], _c[2], alpha, _gray);
}
- (NSColor *)blendedColorWithFraction:(CGFloat)f ofColor:(NSColor *)o
{
    if (!o)
        return nil;
    f = clamp01(f);
    const CGFloat *c = comps(self), *oc = comps(o);
    return make_color(c[0] + (oc[0] - c[0]) * f, c[1] + (oc[1] - c[1]) * f, c[2] + (oc[2] - c[2]) * f,
                      c[3] + (oc[3] - c[3]) * f, NO);
}
- (NSColor *)highlightWithLevel:(CGFloat)level { return [self blendedColorWithFraction:level ofColor:[NSColor whiteColor]]; }
- (NSColor *)shadowWithLevel:(CGFloat)level { return [self blendedColorWithFraction:level ofColor:[NSColor blackColor]]; }
/* A system colour in a colour space is the colour it is now. A colour
 * can't become a pattern unless it is one, and only a system colour is a
 * named colour: nil, as Apple's documentation says when a colour can't be
 * converted. Qt asks for the pattern space and uses the pattern's image
 * when the answer isn't nil (freemac 1.267). */
- (NSColor *)colorUsingColorSpaceName:(NSString *)name
{
    if ([name isEqualToString:NSPatternColorSpace])
        return [self patternImage] ? self : nil;
    if ([name isEqualToString:NSNamedColorSpace])
        return _dynamic ? self : nil;
    if ([self patternImage])
        return nil;
    return resolved(self);
}
- (NSColor *)colorUsingColorSpace:(id)space
{
    if ([space respondsToSelector:@selector(colorSpaceModel)] && [space colorSpaceModel] == NSColorSpaceModelLAB) {
        if ([_space isEqual:space])
            return self;
        if ([self patternImage])
            return nil;
        const CGFloat *v = comps(self);
        CGFloat k[4] = {0, 0, 0, v[3]};
        GColorSRGBToLab(v, k);
        return FerryColorWithComponents(space, k, 4);
    }
    return resolved(self);
}
/* The space a colour keeps its own components in, when that isn't sRGB. */
- (NSColorSpace *)_ferryColorSpace { return _space; }
- (void)getComponents:(CGFloat *)components
{
    if (!components)
        return;
    if (_space) {
        memcpy(components, _k, _nk * sizeof *components);
        return;
    }
    const CGFloat *c = comps(self);
    if (_gray) {
        components[0] = c[0];
        components[1] = c[3];
    } else {
        memcpy(components, c, 4 * sizeof *components);
    }
}
/* Ferry's colours are kept as components, a system colour as two sets of
 * them, which makes it a catalog colour; one made from a pattern image is
 * a pattern. */
- (NSColorType)type
{
    if (_dynamic)
        return NSColorTypeCatalog;
    return [self patternImage] ? NSColorTypePattern : NSColorTypeComponentBased;
}
- (NSColor *)colorUsingType:(NSColorType)type
{
    if (type == NSColorTypeComponentBased) return resolved(self);
    if (type == NSColorTypeCatalog) return _dynamic ? self : nil;
    if (type == NSColorTypePattern) return [self patternImage] ? self : nil;
    return nil;
}
- (void)set
{
    [self setFill];
    [self setStroke];
}
- (void)setFill
{
    const CGFloat *c = comps(self);
    if (current_cg())
        CGContextSetRGBFillColor(current_cg(), c[0], c[1], c[2], c[3]);
}
- (void)setStroke
{
    const CGFloat *c = comps(self);
    if (current_cg())
        CGContextSetRGBStrokeColor(current_cg(), c[0], c[1], c[2], c[3]);
}

NSColor *ADynamicColor(NSString *name, const CGFloat light[4], const CGFloat dark[4])
{
    return make_dynamic(name, light, dark);
}

/* a colour an app makes that changes with the appearance (macOS 10.15) */
NSColor *AColorWithProvider(NSString *name, NSColor * (^provider)(NSAppearance *))
{
    NSColor *c = make_color(0, 0, 0, 0, NO);
    c->_dynamic = YES;
    c->_name = [name copy];
    c->_provider = [provider copy];
    return c;
}
@end


void AColorRGBA(NSColor *color, CGFloat rgba[4])
{
    rgba[0] = rgba[1] = rgba[2] = 0;
    rgba[3] = 1;
    [color getRed:&rgba[0] green:&rgba[1] blue:&rgba[2] alpha:&rgba[3]];
}

/* ---- NSFont --------------------------------------------------------------------------- */

const NSFontWeight NSFontWeightUltraLight = -0.8, NSFontWeightThin = -0.6, NSFontWeightLight = -0.4;
const NSFontWeight NSFontWeightRegular = 0, NSFontWeightMedium = 0.23, NSFontWeightSemibold = 0.3;
const NSFontWeight NSFontWeightBold = 0.4, NSFontWeightHeavy = 0.56, NSFontWeightBlack = 0.62;

static const char *weight_word(NSFontWeight w)
{
    return w <= -0.7 ? "UltraLight" : w <= -0.5 ? "Thin" : w <= -0.2 ? "Light" : w < 0.1 ? "Regular"
         : w < 0.27 ? "Medium" : w < 0.35 ? "Semibold" : w < 0.5 ? "Bold" : w < 0.6 ? "Heavy" : "Black";
}

@implementation NSFont

static NSFont *named(const char *name, CGFloat size)
{
    CTFontRef f = CTFontCreateWithName((CFStringRef)@(name), size, NULL);
    return [(id)f autorelease];
}

+ (NSFont *)fontWithName:(NSString *)name size:(CGFloat)size
{
    if (!name)
        return nil;
    if (size <= 0)
        size = 12;
    return [(id)CTFontCreateWithName((CFStringRef)name, size, NULL) autorelease];
}
+ (NSFont *)systemFontOfSize:(CGFloat)size { return named(".AppleSystemUIFont", size > 0 ? size : 13); }
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight
{
    char name[64];
    snprintf(name, sizeof name, ".AppleSystemUIFont-%s", weight_word(weight));
    return named(name, size > 0 ? size : 13);
}
+ (NSFont *)boldSystemFontOfSize:(CGFloat)size { return named(".AppleSystemUIFont-Bold", size > 0 ? size : 13); }
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight
{
    char name[64];
    snprintf(name, sizeof name, "SFMono-%s", weight_word(weight));
    return named(name, size > 0 ? size : 13);
}
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight
{
    return [self systemFontOfSize:size weight:weight];
}
+ (NSFont *)userFontOfSize:(CGFloat)size { return named("Helvetica", size > 0 ? size : 12); }
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)size { return named("Menlo", size > 0 ? size : 10); }
+ (NSFont *)labelFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 10]; }
+ (NSFont *)messageFontOfSize:(CGFloat)size { return [self systemFontOfSize:size]; }
+ (NSFont *)menuFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 14]; }
+ (NSFont *)menuBarFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 14]; }
+ (NSFont *)titleBarFontOfSize:(CGFloat)size { return [self boldSystemFontOfSize:size]; }
+ (NSFont *)controlContentFontOfSize:(CGFloat)size { return [self systemFontOfSize:size]; }
+ (NSFont *)toolTipsFontOfSize:(CGFloat)size { return [self systemFontOfSize:size > 0 ? size : 11]; }
+ (CGFloat)systemFontSize { return 13; }
+ (CGFloat)smallSystemFontSize { return 11; }
+ (CGFloat)labelFontSize { return 10; }
+ (CGFloat)systemFontSizeForControlSize:(NSControlSize)size
{
    return size == NSControlSizeSmall ? 11 : size == NSControlSizeMini ? 9 : size == NSControlSizeLarge ? 15 : 13;
}

#define CT ((CTFontRef)self)
- (NSString *)fontName { return [(NSString *)CTFontCopyPostScriptName(CT) autorelease]; }
- (NSString *)familyName { return [(NSString *)CTFontCopyFamilyName(CT) autorelease]; }
- (NSString *)displayName { return [(NSString *)CTFontCopyDisplayName(CT) autorelease]; }
- (CGFloat)pointSize { return CTFontGetSize(CT); }
- (CGFloat)ascender { return CTFontGetAscent(CT); }
- (CGFloat)descender { return -CTFontGetDescent(CT); }
- (CGFloat)leading { return CTFontGetLeading(CT); }
- (CGFloat)capHeight { return CTFontGetCapHeight(CT); }
- (CGFloat)xHeight { return CTFontGetXHeight(CT); }
- (CGFloat)underlinePosition { return CTFontGetUnderlinePosition(CT); }
- (CGFloat)underlineThickness { return CTFontGetUnderlineThickness(CT); }
- (CGFloat)italicAngle { return CTFontGetSlantAngle(CT); }
- (NSRect)boundingRectForFont { return CTFontGetBoundingBox(CT); }
- (BOOL)isFixedPitch { return (CTFontGetSymbolicTraits(CT) & kCTFontTraitMonoSpace) != 0; }
- (NSUInteger)numberOfGlyphs { return CTFontGetGlyphCount(CT); }
- (NSSize)advancementForGlyph:(CGGlyph)glyph
{
    CGSize s;
    CTFontGetAdvancesForGlyphs(CT, kCTFontOrientationHorizontal, &glyph, &s, 1);
    return s;
}
/* NSFont reference: advances and bounds for several glyphs at once, given
 * as NSGlyphs (32 bits each) or CGGlyphs (16). */
- (void)getAdvancements:(NSSize *)advancements forCGGlyphs:(const CGGlyph *)glyphs count:(NSUInteger)count
{
    CTFontGetAdvancesForGlyphs(CT, kCTFontOrientationHorizontal, glyphs, advancements, (CFIndex)count);
}
- (void)getAdvancements:(NSSize *)advancements forGlyphs:(const NSGlyph *)glyphs count:(NSUInteger)count
{
    for (NSUInteger i = 0; i < count; i++) {
        CGGlyph g = (CGGlyph)glyphs[i];
        CTFontGetAdvancesForGlyphs(CT, kCTFontOrientationHorizontal, &g, &advancements[i], 1);
    }
}
- (void)getBoundingRects:(NSRect *)rects forCGGlyphs:(const CGGlyph *)glyphs count:(NSUInteger)count
{
    CTFontGetBoundingRectsForGlyphs(CT, kCTFontOrientationHorizontal, glyphs, rects, (CFIndex)count);
}
- (void)getBoundingRects:(NSRect *)rects forGlyphs:(const NSGlyph *)glyphs count:(NSUInteger)count
{
    for (NSUInteger i = 0; i < count; i++) {
        CGGlyph g = (CGGlyph)glyphs[i];
        CTFontGetBoundingRectsForGlyphs(CT, kCTFontOrientationHorizontal, &g, &rects[i], 1);
    }
}
/* NSFont reference: the characters the font has glyphs for. */
- (NSCharacterSet *)coveredCharacterSet { return [(NSCharacterSet *)CTFontCopyCharacterSet(CT) autorelease]; }
/* NSFont reference: the largest advance of any of the font's glyphs,
 * worked out once per font (Hex Fiend sizes its byte columns by it). */
- (NSSize)maximumAdvancement
{
    static char key;
    NSValue *kept = objc_getAssociatedObject(self, &key);
    if (kept)
        return [kept sizeValue];
    NSSize most = NSZeroSize;
    CFIndex n = CTFontGetGlyphCount(CT);
    CGGlyph glyphs[256];
    CGSize adv[256];
    for (CFIndex at = 0; at < n; at += 256) {
        CFIndex k = n - at < 256 ? n - at : 256;
        for (CFIndex i = 0; i < k; i++)
            glyphs[i] = (CGGlyph)(at + i);
        CTFontGetAdvancesForGlyphs(CT, kCTFontOrientationHorizontal, glyphs, adv, k);
        for (CFIndex i = 0; i < k; i++) {
            if (adv[i].width > most.width)
                most.width = adv[i].width;
            if (adv[i].height > most.height)
                most.height = adv[i].height;
        }
    }
    objc_setAssociatedObject(self, &key, [NSValue valueWithSize:most], OBJC_ASSOCIATION_RETAIN);
    return most;
}
- (void)set { [self setInContext:[NSGraphicsContext currentContext]]; }
- (void)setInContext:(NSGraphicsContext *)context
{
    if (context) {
        /* the context's font too, as a Mac does: glyphs shown with
         * CGContextShowGlyphs... then draw in it (Hex Fiend) */
        CGFontRef g = CTFontCopyGraphicsFont(CT, NULL);
        if (g) {
            CGContextSetFont([context CGContext], g);
            CGFontRelease(g);
        }
        CGContextSetFontSize([context CGContext], [self pointSize]);
        /* and the text matrix, which programs count on to undo their own
         * scaling; flipped where the context is, so glyphs stand upright */
        CGContextSetTextMatrix([context CGContext], [context isFlipped] ? CGAffineTransformMakeScale(1, -1)
                                                                       : CGAffineTransformIdentity);
    }
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"\"%@ %gpt. P [] (0x%p) fobj=0x%p, spc=%.2f\"", [self fontName],
                                      [self pointSize], self, self, [self advancementForGlyph:3].width];
}
#undef CT
@end

NSFont *ADefaultFont(void) { return [NSFont systemFontOfSize:13]; }

/* ---- NSParagraphStyle ------------------------------------------------------------------- */

/* the tab stops a style was given (freemac 1.224) */
static char tab_stops_key;

@implementation NSParagraphStyle
+ (NSParagraphStyle *)defaultParagraphStyle
{
    static NSParagraphStyle *style;
    if (!style) {
        style = [[NSParagraphStyle alloc] init];
        style->alignment = kCTTextAlignmentNatural;
    }
    return style;
}
- (instancetype)init
{
    if ((self = [super init]))
        alignment = kCTTextAlignmentNatural;
    return self;
}
/* From a nib or an archived attributed string: the alignment is kept; tab
 * stops and the rest take their defaults. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        if ([coder containsValueForKey:@"NSAlignment"])
            alignment = (uint8_t)[coder decodeIntegerForKey:@"NSAlignment"];
        if ([coder containsValueForKey:@"NSLineBreakMode"])
            lineBreakMode = (uint8_t)[coder decodeIntegerForKey:@"NSLineBreakMode"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:alignment forKey:@"NSAlignment"];
    if (lineBreakMode)
        [coder encodeInteger:lineBreakMode forKey:@"NSLineBreakMode"];
}
- (id)copyWithZone:(NSZone *)zone
{
    if ([self class] == [NSParagraphStyle class])
        return [self retain];
    NSParagraphStyle *p = [[NSParagraphStyle alloc] init];
    p->alignment = alignment;
    p->lineBreakMode = lineBreakMode;
    p->writingDirection = writingDirection;
    memcpy(p->values, values, sizeof values);
    objc_setAssociatedObject(p, &tab_stops_key, objc_getAssociatedObject(self, &tab_stops_key),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return p;
}
- (NSArray *)tabStops
{
    NSArray *tabs = objc_getAssociatedObject(self, &tab_stops_key);
    if (tabs)
        return tabs;
    static NSArray *standard;
    @synchronized([NSParagraphStyle class]) {
        if (!standard) {
            NSMutableArray *a = [NSMutableArray array];
            for (int i = 1; i <= 12; i++)
                [a addObject:[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:28.0 * i] autorelease]];
            standard = [a copy];
        }
    }
    return standard;
}
- (id)mutableCopyWithZone:(NSZone *)zone
{
    NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
    [p setParagraphStyle:self];
    return p;
}
- (NSTextAlignment)alignment { return alignment; }
- (NSLineBreakMode)lineBreakMode { return lineBreakMode; }
- (NSWritingDirection)baseWritingDirection { return writingDirection == 0xff ? NSWritingDirectionNatural : writingDirection; }
- (CGFloat)lineSpacing { return values[kCTParagraphStyleSpecifierLineSpacingAdjustment]; }
- (CGFloat)paragraphSpacing { return values[kCTParagraphStyleSpecifierParagraphSpacing]; }
- (CGFloat)paragraphSpacingBefore { return values[kCTParagraphStyleSpecifierParagraphSpacingBefore]; }
- (CGFloat)headIndent { return values[kCTParagraphStyleSpecifierHeadIndent]; }
- (CGFloat)tailIndent { return values[kCTParagraphStyleSpecifierTailIndent]; }
- (CGFloat)firstLineHeadIndent { return values[kCTParagraphStyleSpecifierFirstLineHeadIndent]; }
- (CGFloat)minimumLineHeight { return values[kCTParagraphStyleSpecifierMinimumLineHeight]; }
- (CGFloat)maximumLineHeight { return values[kCTParagraphStyleSpecifierMaximumLineHeight]; }
- (CGFloat)lineHeightMultiple { return values[kCTParagraphStyleSpecifierLineHeightMultiple]; }
- (CGFloat)defaultTabInterval { return values[kCTParagraphStyleSpecifierDefaultTabInterval]; }
@end

@implementation NSMutableParagraphStyle
- (id)copyWithZone:(NSZone *)zone { return [super copyWithZone:zone]; }
- (void)setAlignment:(NSTextAlignment)a { alignment = (uint8_t)a; }
- (void)setLineBreakMode:(NSLineBreakMode)m { lineBreakMode = (uint8_t)m; }
- (void)setBaseWritingDirection:(NSWritingDirection)d { writingDirection = d < 0 ? 0xff : (uint8_t)d; }
- (void)setLineSpacing:(CGFloat)v { values[kCTParagraphStyleSpecifierLineSpacingAdjustment] = v; }
- (void)setParagraphSpacing:(CGFloat)v { values[kCTParagraphStyleSpecifierParagraphSpacing] = v; }
- (void)setParagraphSpacingBefore:(CGFloat)v { values[kCTParagraphStyleSpecifierParagraphSpacingBefore] = v; }
- (void)setHeadIndent:(CGFloat)v { values[kCTParagraphStyleSpecifierHeadIndent] = v; }
- (void)setTailIndent:(CGFloat)v { values[kCTParagraphStyleSpecifierTailIndent] = v; }
- (void)setFirstLineHeadIndent:(CGFloat)v { values[kCTParagraphStyleSpecifierFirstLineHeadIndent] = v; }
- (void)setMinimumLineHeight:(CGFloat)v { values[kCTParagraphStyleSpecifierMinimumLineHeight] = v; }
- (void)setMaximumLineHeight:(CGFloat)v { values[kCTParagraphStyleSpecifierMaximumLineHeight] = v; }
- (void)setLineHeightMultiple:(CGFloat)v { values[kCTParagraphStyleSpecifierLineHeightMultiple] = v; }
- (void)setDefaultTabInterval:(CGFloat)v { values[kCTParagraphStyleSpecifierDefaultTabInterval] = v; }
- (void)setTabStops:(NSArray *)tabs
{
    NSArray *sorted = [tabs sortedArrayUsingComparator:^NSComparisonResult(NSTextTab *a, NSTextTab *b) {
        return [a location] < [b location] ? NSOrderedAscending : [a location] > [b location] ? NSOrderedDescending
                                                                                            : NSOrderedSame;
    }];
    objc_setAssociatedObject(self, &tab_stops_key, sorted ?: @[], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)addTabStop:(NSTextTab *)tab
{
    if (tab)
        [self setTabStops:[[self tabStops] arrayByAddingObject:tab]];
}
- (void)removeTabStop:(NSTextTab *)tab
{
    NSMutableArray *a = [[[self tabStops] mutableCopy] autorelease];
    [a removeObject:tab];
    [self setTabStops:a];
}
- (void)setParagraphStyle:(NSParagraphStyle *)style
{
    objc_setAssociatedObject(self, &tab_stops_key, style ? objc_getAssociatedObject(style, &tab_stops_key) : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    GParagraphStyle *s = (GParagraphStyle *)style;
    alignment = s ? s->alignment : kCTTextAlignmentNatural;
    lineBreakMode = s ? s->lineBreakMode : 0;
    writingDirection = s ? s->writingDirection : 0;
    if (s)
        memcpy(values, s->values, sizeof values);
    else
        memset(values, 0, sizeof values);
}
@end

/* ---- tab stops (freemac 1.224) ---- */

NSTextTabOptionKey const NSTabColumnTerminatorsAttributeName = @"NSTabColumnTerminatorsAttributeName";

@implementation NSTextTab {
    CGFloat _location;
    NSTextAlignment _alignment;
    NSDictionary *_options;
}
- (instancetype)initWithTextAlignment:(NSTextAlignment)alignment location:(CGFloat)loc options:(NSDictionary *)options
{
    if ((self = [super init])) {
        _alignment = alignment;
        _location = loc;
        _options = [options copy] ?: [[NSDictionary alloc] init];
    }
    return self;
}
- (instancetype)initWithType:(NSTextTabType)type location:(CGFloat)loc
{
    NSTextAlignment a = type == NSRightTabStopType    ? NSTextAlignmentRight
                        : type == NSCenterTabStopType ? NSTextAlignmentCenter
                                                      : NSTextAlignmentLeft;
    NSDictionary *o = type == NSDecimalTabStopType
                          ? @{NSTabColumnTerminatorsAttributeName: [NSCharacterSet characterSetWithCharactersInString:@"."]}
                          : nil;
    if (type == NSDecimalTabStopType)
        a = NSTextAlignmentRight;
    return [self initWithTextAlignment:a location:loc options:o];
}
- (void)dealloc
{
    [_options release];
    [super dealloc];
}
- (CGFloat)location { return _location; }
- (NSTextAlignment)alignment { return _alignment; }
- (NSDictionary *)options { return _options; }
- (NSTextTabType)tabStopType
{
    if ([_options objectForKey:NSTabColumnTerminatorsAttributeName])
        return NSDecimalTabStopType;
    return _alignment == NSTextAlignmentRight    ? NSRightTabStopType
           : _alignment == NSTextAlignmentCenter ? NSCenterTabStopType
                                                 : NSLeftTabStopType;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[NSTextTab class]] && [o location] == _location && [o alignment] == _alignment;
}
- (NSUInteger)hash { return (NSUInteger)(_location * 16) ^ (NSUInteger)_alignment; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_location forKey:@"NSLocation"];
    [coder encodeInteger:_alignment forKey:@"NSAlignment"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithTextAlignment:[coder decodeIntegerForKey:@"NSAlignment"]
                              location:[coder decodeDoubleForKey:@"NSLocation"]
                               options:nil];
}
@end

/* ---- string drawing --------------------------------------------------------------------- */

NSAttributedStringKey const NSFontAttributeName = @"NSFont";
NSAttributedStringKey const NSForegroundColorAttributeName = @"NSColor";
NSAttributedStringKey const NSBackgroundColorAttributeName = @"NSBackgroundColor";
NSAttributedStringKey const NSParagraphStyleAttributeName = @"NSParagraphStyle";
NSAttributedStringKey const NSKernAttributeName = @"NSKern";
NSAttributedStringKey const NSUnderlineStyleAttributeName = @"NSUnderline";
NSAttributedStringKey const NSUnderlineColorAttributeName = @"NSUnderlineColor";
NSAttributedStringKey const NSStrikethroughStyleAttributeName = @"NSStrikethrough";
NSAttributedStringKey const NSLigatureAttributeName = @"NSLigature";

/* AppKit's default font is Helvetica 12 where Core Text's is 12-point too;
 * text with no font attribute is drawn in it. */
static NSAttributedString *with_defaults(NSString *string, NSDictionary *attrs)
{
    NSMutableDictionary *d = attrs ? [[attrs mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    if (!d[NSFontAttributeName])
        d[NSFontAttributeName] = [NSFont fontWithName:@"Helvetica" size:12];
    return [[[NSAttributedString alloc] initWithString:string ?: @"" attributes:d] autorelease];
}

NSAttributedString *AAttributed(NSString *string, NSFont *font, NSColor *color)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[NSFontAttributeName] = font ?: ADefaultFont();
    if (color)
        d[NSForegroundColorAttributeName] = color;
    return [[[NSAttributedString alloc] initWithString:string ?: @"" attributes:d] autorelease];
}

NSSize ALineSize(NSAttributedString *string, CGFloat *ascent, CGFloat *descent)
{
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)string);
    CGFloat a = 0, d = 0, l = 0;
    double w = CTLineGetTypographicBounds(line, &a, &d, &l);
    CFRelease(line);
    if (![string length]) {
        NSFont *f = ADefaultFont();
        a = [f ascender];
        d = -[f descender];
    }
    if (ascent)
        *ascent = a;
    if (descent)
        *descent = d;
    return NSMakeSize(ceil(w), ceil(a + d));
}

void ADrawLine(NSAttributedString *string, CGFloat x, CGFloat y)
{
    CGContextRef cg = current_cg();
    if (!cg || ![string length])
        return;
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)string);
    CGContextSaveGState(cg);
    CGAffineTransform saved = CGContextGetTextMatrix(cg);
    CGContextSetTextMatrix(cg, [current_context isFlipped] ? CGAffineTransformMakeScale(1, -1)
                                                            : CGAffineTransformIdentity);
    CGContextSetTextPosition(cg, x, y);
    CTLineDraw(line, cg);
    CGContextSetTextMatrix(cg, saved);
    CGContextRestoreGState(cg);
    CFRelease(line);
}

/* Draws a frame of text in rect, top to bottom, in a flipped or unflipped
 * context. Core Text frames lay out in unflipped space, so in a flipped
 * context the rect is drawn through a local flip. */
static void draw_frame(NSAttributedString *string, NSRect rect)
{
    CGContextRef cg = current_cg();
    if (!cg || ![string length] || rect.size.width <= 0)
        return;
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)string);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, CGRectMake(0, 0, rect.size.width, rect.size.height));
    CTFrameRef frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL);
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, rect);
    if ([current_context isFlipped]) {
        CGContextTranslateCTM(cg, rect.origin.x, rect.origin.y + rect.size.height);
        CGContextScaleCTM(cg, 1, -1);
    } else {
        CGContextTranslateCTM(cg, rect.origin.x, rect.origin.y);
    }
    CGAffineTransform saved = CGContextGetTextMatrix(cg);
    CGContextSetTextMatrix(cg, CGAffineTransformIdentity);
    CTFrameDraw(frame, cg);
    CGContextSetTextMatrix(cg, saved);
    CGContextRestoreGState(cg);
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(fs);
}

static NSRect bounding(NSAttributedString *string, NSSize size, NSStringDrawingOptions options)
{
    if (!(options & NSStringDrawingUsesLineFragmentOrigin) || size.width <= 0) {
        CGFloat a, d;
        NSSize s = ALineSize(string, &a, &d);
        return NSMakeRect(0, -d, s.width, s.height);
    }
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)string);
    CGSize s = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), NULL,
                                                            CGSizeMake(size.width, size.height > 0 ? size.height : 1e7),
                                                            NULL);
    CFRelease(fs);
    return NSMakeRect(0, 0, ceil(s.width), ceil(s.height));
}

static BOOL single_line(NSAttributedString *string)
{
    NSString *s = [string string];
    return [s rangeOfString:@"\n"].location == NSNotFound && [s rangeOfString:@"\r"].location == NSNotFound;
}

/* A point is the top-left of the text in a flipped view and its bottom-left
 * in an unflipped one. */
static void draw_at(NSAttributedString *string, NSPoint p)
{
    if (!single_line(string)) {
        NSRect r = bounding(string, NSMakeSize(1e6, 0), NSStringDrawingUsesLineFragmentOrigin);
        draw_frame(string, NSMakeRect(p.x, p.y, r.size.width + 1, r.size.height));
        return;
    }
    CGFloat a, d;
    ALineSize(string, &a, &d);
    ADrawLine(string, p.x, [current_context isFlipped] ? p.y + a : p.y + d);
}

static void draw_in(NSAttributedString *string, NSRect rect)
{
    if (single_line(string)) {
        CGFloat a, d;
        NSSize s = ALineSize(string, &a, &d);
        if (s.width <= rect.size.width) {
            /* one line that fits: aligned by the paragraph style */
            NSParagraphStyle *style = [string length] ? [string attribute:NSParagraphStyleAttributeName atIndex:0
                                                               effectiveRange:NULL]
                                                      : nil;
            CGFloat x = rect.origin.x;
            NSTextAlignment align = style ? [style alignment] : NSTextAlignmentNatural;
            if (align == NSTextAlignmentRight)
                x += rect.size.width - s.width;
            else if (align == NSTextAlignmentCenter)
                x += (rect.size.width - s.width) / 2;
            CGContextRef cg = current_cg();
            if (cg) {
                CGContextSaveGState(cg);
                CGContextClipToRect(cg, rect);
            }
            ADrawLine(string, x, [current_context isFlipped] ? rect.origin.y + a : NSMaxY(rect) - a);
            if (cg)
                CGContextRestoreGState(cg);
            return;
        }
    }
    draw_frame(string, rect);
}

@implementation NSString (NSStringDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary *)attributes
{
    NSAttributedString *s = with_defaults(self, attributes);
    if (single_line(s))
        return ALineSize(s, NULL, NULL);
    return bounding(s, NSMakeSize(1e6, 0), NSStringDrawingUsesLineFragmentOrigin).size;
}
- (void)drawAtPoint:(NSPoint)point withAttributes:(NSDictionary *)attributes
{
    draw_at(with_defaults(self, attributes), point);
}
- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary *)attributes
{
    draw_in(with_defaults(self, attributes), rect);
}
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options attributes:(NSDictionary *)attributes
{
    return bounding(with_defaults(self, attributes), size, options);
}
@end

static NSAttributedString *with_default_font(NSAttributedString *s)
{
    __block BOOL missing = NO;
    NSUInteger i = 0, n = [s length];
    while (i < n) {
        NSRange r;
        if (![s attribute:NSFontAttributeName atIndex:i effectiveRange:&r]) {
            missing = YES;
            break;
        }
        i = NSMaxRange(r);
    }
    if (!missing)
        return s;
    NSMutableAttributedString *m = [[s mutableCopy] autorelease];
    i = 0;
    while (i < n) {
        NSRange r;
        if (![m attribute:NSFontAttributeName atIndex:i effectiveRange:&r])
            [m addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Helvetica" size:12] range:r];
        i = NSMaxRange(r);
    }
    return m;
}

@implementation NSAttributedString (NSStringDrawing)
- (NSSize)size
{
    NSAttributedString *s = with_default_font(self);
    if (single_line(s))
        return ALineSize(s, NULL, NULL);
    return bounding(s, NSMakeSize(1e6, 0), NSStringDrawingUsesLineFragmentOrigin).size;
}
- (void)drawAtPoint:(NSPoint)point { draw_at(with_default_font(self), point); }
- (void)drawInRect:(NSRect)rect { draw_in(with_default_font(self), rect); }
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
{
    return bounding(with_default_font(self), size, options);
}
@end

/* ---- NSBezierPath -------------------------------------------------------------------- */

static CGFloat default_line_width = 1;

@implementation NSBezierPath {
    CGMutablePathRef _path;
    CGFloat _lineWidth, _miter, _flatness;
    NSLineCapStyle _cap;
    NSLineJoinStyle _join;
    NSWindingRule _rule;
    CGFloat *_dash;
    NSInteger _dashCount;
    CGFloat _phase;
}

+ (NSBezierPath *)bezierPath { return [[[self alloc] init] autorelease]; }
+ (NSBezierPath *)bezierPathWithRect:(NSRect)rect
{
    NSBezierPath *p = [self bezierPath];
    [p appendBezierPathWithRect:rect];
    return p;
}
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect
{
    NSBezierPath *p = [self bezierPath];
    [p appendBezierPathWithOvalInRect:rect];
    return p;
}
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xr yRadius:(CGFloat)yr
{
    NSBezierPath *p = [self bezierPath];
    [p appendBezierPathWithRoundedRect:rect xRadius:xr yRadius:yr];
    return p;
}
+ (void)fillRect:(NSRect)rect { if (current_cg()) CGContextFillRect(current_cg(), rect); }
+ (void)strokeRect:(NSRect)rect { [[self bezierPathWithRect:rect] stroke]; }
+ (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b
{
    NSBezierPath *p = [self bezierPath];
    [p moveToPoint:a];
    [p lineToPoint:b];
    [p stroke];
}
+ (void)clipRect:(NSRect)rect { if (current_cg()) CGContextClipToRect(current_cg(), rect); }
+ (CGFloat)defaultLineWidth { return default_line_width; }
+ (void)setDefaultLineWidth:(CGFloat)w { default_line_width = w; }

- (instancetype)init
{
    if ((self = [super init])) {
        _path = CGPathCreateMutable();
        _lineWidth = default_line_width;
        _miter = 10;
        _flatness = 0.6;
    }
    return self;
}
- (void)dealloc
{
    CGPathRelease(_path);
    free(_dash);
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSBezierPath *p = [[NSBezierPath alloc] init];
    CGPathRelease(p->_path);
    p->_path = CGPathCreateMutableCopy(_path);
    p->_lineWidth = _lineWidth;
    p->_miter = _miter;
    p->_flatness = _flatness;
    p->_cap = _cap;
    p->_join = _join;
    p->_rule = _rule;
    if (_dashCount)
        [p setLineDash:_dash count:_dashCount phase:_phase];
    return p;
}

- (void)moveToPoint:(NSPoint)p { CGPathMoveToPoint(_path, NULL, p.x, p.y); }
- (void)lineToPoint:(NSPoint)p { CGPathAddLineToPoint(_path, NULL, p.x, p.y); }
- (void)curveToPoint:(NSPoint)p controlPoint1:(NSPoint)a controlPoint2:(NSPoint)b
{
    CGPathAddCurveToPoint(_path, NULL, a.x, a.y, b.x, b.y, p.x, p.y);
}
- (void)relativeMoveToPoint:(NSPoint)p
{
    NSPoint c = [self currentPoint];
    [self moveToPoint:NSMakePoint(c.x + p.x, c.y + p.y)];
}
- (void)relativeLineToPoint:(NSPoint)p
{
    NSPoint c = [self currentPoint];
    [self lineToPoint:NSMakePoint(c.x + p.x, c.y + p.y)];
}
- (void)closePath { CGPathCloseSubpath(_path); }
- (void)removeAllPoints
{
    CGPathRelease(_path);
    _path = CGPathCreateMutable();
}
- (void)appendBezierPath:(NSBezierPath *)path { CGPathAddPath(_path, NULL, path->_path); }
- (void)appendBezierPathWithRect:(NSRect)rect { CGPathAddRect(_path, NULL, rect); }
- (void)appendBezierPathWithOvalInRect:(NSRect)rect { CGPathAddEllipseInRect(_path, NULL, rect); }
- (void)appendBezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xr yRadius:(CGFloat)yr
{
    xr = fmin(xr, rect.size.width / 2);
    yr = fmin(yr, rect.size.height / 2);
    if (xr <= 0 || yr <= 0)
        CGPathAddRect(_path, NULL, rect);
    else
        CGPathAddRoundedRect(_path, NULL, rect, xr, yr);
}
/* Angles are in degrees, counterclockwise unless asked otherwise. */
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a1
                                 endAngle:(CGFloat)a2 clockwise:(BOOL)clockwise
{
    CGPathAddArc(_path, NULL, c.x, c.y, r, a1 * M_PI / 180, a2 * M_PI / 180, clockwise);
}
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a1 endAngle:(CGFloat)a2
{
    [self appendBezierPathWithArcWithCenter:c radius:r startAngle:a1 endAngle:a2 clockwise:NO];
}

static void apply_style(NSBezierPath *p, CGContextRef cg)
{
    CGContextSetLineWidth(cg, p->_lineWidth);
    CGContextSetMiterLimit(cg, p->_miter);
    CGContextSetLineCap(cg, (CGLineCap)p->_cap);
    CGContextSetLineJoin(cg, (CGLineJoin)p->_join);
    CGContextSetFlatness(cg, p->_flatness);
    CGContextSetLineDash(cg, p->_phase, p->_dash, (size_t)p->_dashCount);
}

- (void)fill
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    CGContextSaveGState(cg);
    CGContextBeginPath(cg);
    CGContextAddPath(cg, _path);
    if (_rule == NSWindingRuleEvenOdd)
        CGContextEOFillPath(cg);
    else
        CGContextFillPath(cg);
    CGContextRestoreGState(cg);
}
- (void)stroke
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    CGContextSaveGState(cg);
    apply_style(self, cg);
    CGContextBeginPath(cg);
    CGContextAddPath(cg, _path);
    CGContextStrokePath(cg);
    CGContextRestoreGState(cg);
}
- (void)addClip
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    CGContextBeginPath(cg);
    CGContextAddPath(cg, _path);
    if (_rule == NSWindingRuleEvenOdd)
        CGContextEOClip(cg);
    else
        CGContextClip(cg);
}
- (void)setClip
{
    AWarnOnce("-[NSBezierPath setClip] (it adds to the clip instead of replacing it)");
    [self addClip];
}
- (BOOL)containsPoint:(NSPoint)p { return CGPathContainsPoint(_path, NULL, p, _rule == NSWindingRuleEvenOdd); }
static CGAffineTransform cg_transform(NSAffineTransform *t)
{
    NSAffineTransformStruct s = [t transformStruct];
    return (CGAffineTransform){s.m11, s.m12, s.m21, s.m22, s.tX, s.tY};
}
- (void)transformUsingAffineTransform:(NSAffineTransform *)transform
{
    if (!transform)
        return;
    CGAffineTransform m = cg_transform(transform);
    CGMutablePathRef p = CGPathCreateMutableCopyByTransformingPath(_path, &m);
    if (!p)
        return;
    CGPathRelease(_path);
    _path = p;
}

/* Elements as NSBezierPath reports them: a quadratic piece of the CGPath comes
 * back as the equivalent cubic curve, since NSBezierPath has no quadratic
 * element. */
struct element_walk {
    NSInteger want, at;
    BOOL found;
    NSBezierPathElement type;
    NSPoint pts[3];
    NSPoint cur, start;
};
static void walk_element(void *info, const CGPathElement *e)
{
    struct element_walk *w = info;
    BOOL mine = w->at == w->want && !w->found;
    NSPoint q, p;
    switch (e->type) {
    case kCGPathElementMoveToPoint:
        if (mine) {
            w->type = NSBezierPathElementMoveTo;
            w->pts[0] = e->points[0];
        }
        w->cur = w->start = e->points[0];
        break;
    case kCGPathElementAddLineToPoint:
        if (mine) {
            w->type = NSBezierPathElementLineTo;
            w->pts[0] = e->points[0];
        }
        w->cur = e->points[0];
        break;
    case kCGPathElementAddQuadCurveToPoint:
        q = e->points[0];
        p = e->points[1];
        if (mine) {
            w->type = NSBezierPathElementCurveTo;
            w->pts[0] = NSMakePoint(w->cur.x + 2.0 / 3.0 * (q.x - w->cur.x), w->cur.y + 2.0 / 3.0 * (q.y - w->cur.y));
            w->pts[1] = NSMakePoint(p.x + 2.0 / 3.0 * (q.x - p.x), p.y + 2.0 / 3.0 * (q.y - p.y));
            w->pts[2] = p;
        }
        w->cur = p;
        break;
    case kCGPathElementAddCurveToPoint:
        if (mine) {
            w->type = NSBezierPathElementCurveTo;
            w->pts[0] = e->points[0];
            w->pts[1] = e->points[1];
            w->pts[2] = e->points[2];
        }
        w->cur = e->points[2];
        break;
    case kCGPathElementCloseSubpath:
        if (mine) {
            w->type = NSBezierPathElementClosePath;
            w->pts[0] = w->start;
        }
        w->cur = w->start;
        break;
    }
    if (mine)
        w->found = YES;
    w->at++;
}
- (NSBezierPathElement)elementAtIndex:(NSInteger)index associatedPoints:(NSPointArray)points
{
    struct element_walk w = {0};
    w.want = index;
    CGPathApply(_path, &w, walk_element);
    if (!w.found)
        @throw [NSException exceptionWithName:NSRangeException
                                       reason:[NSString stringWithFormat:@"-[NSBezierPath elementAtIndex:]: index %ld beyond bounds", (long)index]
                                     userInfo:nil];
    if (points) {
        int n = w.type == NSBezierPathElementCurveTo ? 3 : w.type == NSBezierPathElementClosePath ? 0 : 1;
        for (int i = 0; i < n; i++)
            points[i] = w.pts[i];
    }
    return w.type;
}
- (NSBezierPathElement)elementAtIndex:(NSInteger)index { return [self elementAtIndex:index associatedPoints:NULL]; }
- (void)appendBezierPathWithPoints:(NSPointArray)points count:(NSInteger)count
{
    if (!points || count <= 0)
        return;
    /* As documented: a line to each point, starting with a move when the path
     * is empty. */
    NSInteger i = 0;
    if (CGPathIsEmpty(_path)) {
        CGPathMoveToPoint(_path, NULL, points[0].x, points[0].y);
        i = 1;
    }
    for (; i < count; i++)
        CGPathAddLineToPoint(_path, NULL, points[i].x, points[i].y);
}
- (void)appendBezierPathWithArcFromPoint:(NSPoint)p1 toPoint:(NSPoint)p2 radius:(CGFloat)radius
{
    if (CGPathIsEmpty(_path))
        @throw [NSException exceptionWithName:NSGenericException
                                       reason:@"-[NSBezierPath appendBezierPathWithArcFromPoint:toPoint:radius:]: no current point"
                                     userInfo:nil];
    CGPathAddArcToPoint(_path, NULL, p1.x, p1.y, p2.x, p2.y, radius);
}
- (void)setLineDash:(const CGFloat *)pattern count:(NSInteger)count phase:(CGFloat)phase
{
    free(_dash);
    _dash = NULL;
    _dashCount = pattern && count > 0 ? count : 0;
    if (_dashCount) {
        _dash = malloc(sizeof(CGFloat) * count);
        memcpy(_dash, pattern, sizeof(CGFloat) * count);
    }
    _phase = phase;
}
- (CGFloat)lineWidth { return _lineWidth; }
- (void)setLineWidth:(CGFloat)w { _lineWidth = w; }
- (CGFloat)miterLimit { return _miter; }
- (void)setMiterLimit:(CGFloat)m { _miter = m; }
- (CGFloat)flatness { return _flatness; }
- (void)setFlatness:(CGFloat)f { _flatness = f; }
- (NSLineCapStyle)lineCapStyle { return _cap; }
- (void)setLineCapStyle:(NSLineCapStyle)c { _cap = c; }
- (NSLineJoinStyle)lineJoinStyle { return _join; }
- (void)setLineJoinStyle:(NSLineJoinStyle)j { _join = j; }
- (NSWindingRule)windingRule { return _rule; }
- (void)setWindingRule:(NSWindingRule)r { _rule = r; }
- (BOOL)isEmpty { return CGPathIsEmpty(_path); }
- (NSPoint)currentPoint { return CGPathGetCurrentPoint(_path); }
- (NSRect)bounds { return CGPathIsEmpty(_path) ? NSZeroRect : CGPathGetPathBoundingBox(_path); }
- (NSRect)controlPointBounds { return CGPathIsEmpty(_path) ? NSZeroRect : CGPathGetBoundingBox(_path); }
static void count_element(void *info, const CGPathElement *e) { (*(NSInteger *)info)++; }
- (NSInteger)elementCount
{
    NSInteger n = 0;
    CGPathApply(_path, &n, count_element);
    return n;
}
- (CGPathRef)CGPath { return _path; }
@end

/* ---- NSAffineTransform's AppKit part ------------------------------------------------ */

@implementation NSAffineTransform (NSAppKitAdditions)
- (NSBezierPath *)transformBezierPath:(NSBezierPath *)path
{
    NSBezierPath *p = [[path copy] autorelease];
    [p transformUsingAffineTransform:self];
    return p;
}
- (void)set
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    /* There is no CGContextSetCTM: undo the current transform, then apply ours. */
    CGContextConcatCTM(cg, CGAffineTransformInvert(CGContextGetCTM(cg)));
    CGContextConcatCTM(cg, cg_transform(self));
}
- (void)concat
{
    CGContextRef cg = current_cg();
    if (cg)
        CGContextConcatCTM(cg, cg_transform(self));
}
@end

/* ---- rectangle drawing ------------------------------------------------------------- */

void NSRectFill(NSRect rect) { if (current_cg()) CGContextFillRect(current_cg(), rect); }
void NSRectFillList(const NSRect *rects, NSInteger count) { if (current_cg()) CGContextFillRects(current_cg(), rects, count); }
void NSRectFillUsingOperation(NSRect rect, NSCompositingOperation op)
{
    NSGraphicsContext *c = current_context;
    if (!c)
        return;
    NSCompositingOperation saved = [c compositingOperation];
    [c saveGraphicsState];
    [c setCompositingOperation:op];
    NSRectFill(rect);
    [c restoreGraphicsState];
    [c setCompositingOperation:saved];
}
/* lists of rectangles (freemac 1.221, Ferry 0.45.0) */
static void fill_list(const NSRect *rects, NSColor *const *colors, const CGFloat *grays, NSInteger count,
                      BOOL withOp, NSCompositingOperation op)
{
    NSGraphicsContext *c = current_context;
    if (!c || !current_cg() || count <= 0)
        return;
    NSCompositingOperation saved = [c compositingOperation];
    [c saveGraphicsState];
    if (withOp)
        [c setCompositingOperation:op];
    for (NSInteger i = 0; i < count; i++) {
        if (colors)
            [colors[i] setFill];
        else if (grays)
            [[NSColor colorWithCalibratedWhite:grays[i] alpha:1] setFill];
        CGContextFillRect(current_cg(), rects[i]);
    }
    [c restoreGraphicsState];
    [c setCompositingOperation:saved];
}
void NSRectFillListWithColors(const NSRect *rects, NSColor *const *colors, NSInteger count)
{
    fill_list(rects, colors, NULL, count, NO, 0);
}
void NSRectFillListWithGrays(const NSRect *rects, const CGFloat *grays, NSInteger count)
{
    fill_list(rects, NULL, grays, count, NO, 0);
}
void NSRectFillListUsingOperation(const NSRect *rects, NSInteger count, NSCompositingOperation op)
{
    fill_list(rects, NULL, NULL, count, YES, op);
}
void NSRectFillListWithColorsUsingOperation(const NSRect *rects, NSColor *const *colors, NSInteger count,
                                            NSCompositingOperation op)
{
    fill_list(rects, colors, NULL, count, YES, op);
}

/* A focus ring around what is filled or stroked next, until the graphics
 * state is restored: a glow of the focus colour as the shape's shadow, and
 * with NSFocusRingOnly the glow outside the shape alone, leaving what is
 * under the shape as it was. The ring goes below the shape for
 * NSFocusRingAbove as well (freemac 1.221, Ferry 0.45.0). */
void NSSetFocusRingStyle(NSFocusRingPlacement placement)
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    NSColor *ring = [[NSColor keyboardFocusIndicatorColor] colorWithAlphaComponent:1];
    CGContextSetShadowWithColor(cg, CGSizeZero, 3, [ring CGColor]);
    GContextSetShadowOnly(cg, placement == NSFocusRingOnly);
}

void NSFrameRectWithWidth(NSRect r, CGFloat w)
{
    if (!current_cg())
        return;
    /* drawn inside the rectangle, as the four edges */
    NSRect edges[4] = {
        NSMakeRect(r.origin.x, r.origin.y, r.size.width, w), NSMakeRect(r.origin.x, NSMaxY(r) - w, r.size.width, w),
        NSMakeRect(r.origin.x, r.origin.y + w, w, r.size.height - 2 * w),
        NSMakeRect(NSMaxX(r) - w, r.origin.y + w, w, r.size.height - 2 * w),
    };
    CGContextFillRects(current_cg(), edges, 4);
}
void NSFrameRect(NSRect rect) { NSFrameRectWithWidth(rect, 1); }
void NSEraseRect(NSRect rect)
{
    CGContextRef cg = current_cg();
    if (!cg)
        return;
    CGContextSaveGState(cg);
    CGContextSetRGBFillColor(cg, 1, 1, 1, 1);
    CGContextFillRect(cg, rect);
    CGContextRestoreGState(cg);
}
void NSRectClip(NSRect rect) { if (current_cg()) CGContextClipToRect(current_cg(), rect); }

void AFillRoundedRect(NSRect rect, CGFloat radius, NSColor *fill, NSColor *stroke)
{
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    if (fill) {
        [fill setFill];
        [p fill];
    }
    if (stroke) {
        NSBezierPath *s = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.5, 0.5) xRadius:radius - 0.5
                                                         yRadius:radius - 0.5];
        [stroke setStroke];
        [s stroke];
    }
}

/* ---- bitmaps ------------------------------------------------------------------------ */

@implementation NSImageRep {
@protected
    NSSize _size;
    NSInteger _wide, _high, _bps;
    BOOL _alpha;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSSize)size { return _size; }
- (void)setSize:(NSSize)size { _size = size; }
- (NSInteger)pixelsWide { return _wide; }
- (void)setPixelsWide:(NSInteger)w { _wide = w; }
- (NSInteger)pixelsHigh { return _high; }
- (void)setPixelsHigh:(NSInteger)h { _high = h; }
- (NSInteger)bitsPerSample { return _bps; }
- (BOOL)hasAlpha { return _alpha; }
- (void)setAlpha:(BOOL)alpha { _alpha = alpha; }
- (BOOL)draw { return [self drawAtPoint:NSZeroPoint]; }
- (BOOL)drawAtPoint:(NSPoint)point { return [self drawInRect:(NSRect){point, _size}]; }
- (BOOL)drawInRect:(NSRect)rect { return NO; }
@end

@implementation NSBitmapImageRep {
    unsigned char *_data;
    BOOL _owns;
    BOOL _exposed; /* bitmapData was handed out, so the pixels may change at any time */
    BOOL _stale;   /* _image is out of date */
    NSInteger _bpr, _spp;
    CGImageRef _image;
    /* Any other layout (freemac 1.263): 1, 2, 4, 8 or 16 bits a sample,
     * planar or meshed, white, black, RGB or CMYK, alpha first or last,
     * premultiplied or not. The pixels stay as the program lays them out,
     * in _planes, and are turned into _data's 8-bit RGBA when drawn or read. */
    BOOL _foreign, _rowns, _rplanar, _rdirty;
    NSInteger _rbps, _rbpp, _rbpr, _rplaneCount;
    NSBitmapFormat _rformat;
    int _rspace;
    unsigned char *_planes[5];
    NSString *_space;
}

enum { RSPACE_WHITE, RSPACE_BLACK, RSPACE_RGB, RSPACE_CMYK };

static int bitmap_space(NSString *space, NSInteger colours)
{
    if ([space isEqualToString:@"NSCalibratedBlackColorSpace"] || [space isEqualToString:@"NSDeviceBlackColorSpace"])
        return RSPACE_BLACK;
    if ([space isEqualToString:@"NSDeviceCMYKColorSpace"])
        return RSPACE_CMYK;
    if ([space isEqualToString:@"NSCalibratedWhiteColorSpace"] || [space isEqualToString:@"NSDeviceWhiteColorSpace"])
        return RSPACE_WHITE;
    if (space == nil || [space hasSuffix:@"RGBColorSpace"])
        return colours == 1 ? RSPACE_WHITE : RSPACE_RGB;
    return -1;
}

- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar
                          colorSpaceName:(NSString *)space bytesPerRow:(NSInteger)bpr
                            bitsPerPixel:(NSInteger)bpp
{
    return [self initWithBitmapDataPlanes:planes pixelsWide:width pixelsHigh:height bitsPerSample:bps
                          samplesPerPixel:spp hasAlpha:alpha isPlanar:planar colorSpaceName:space
                             bitmapFormat:0 bytesPerRow:bpr bitsPerPixel:bpp];
}

- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar
                          colorSpaceName:(NSString *)space bitmapFormat:(NSBitmapFormat)format
                             bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp
{
    if (!(self = [super init]))
        return nil;
    _wide = width;
    _high = height;
    _alpha = alpha;
    _spp = spp;
    _size = NSMakeSize(width, height);
    _space = [(space ? space : NSDeviceRGBColorSpace) copy];
    if (bps == 8 && !planar && (spp == 4 || spp == 3) && (!bpp || bpp == 32) && format == 0 &&
        bitmap_space(space, 3) == RSPACE_RGB) {
        _bps = 8;
        _bpr = bpr ? bpr : width * 4;
        if (planes && planes[0]) {
            _data = planes[0];
        } else {
            _data = calloc((size_t)(_bpr * height), 1);
            _owns = YES;
        }
        return self;
    }
    NSInteger colours = spp - (alpha ? 1 : 0);
    int rspace = bitmap_space(space, colours);
    BOOL fits = rspace >= 0 && width >= 0 && height >= 0 && spp >= 1 && spp <= 5 &&
                (bps == 1 || bps == 2 || bps == 4 || bps == 8 || bps == 16) &&
                colours == (rspace == RSPACE_CMYK ? 4 : rspace == RSPACE_RGB ? 3 : 1) &&
                !(format & ~(NSUInteger)(NSBitmapFormatAlphaFirst | NSBitmapFormatAlphaNonpremultiplied));
    if (!fits) {
        AWarnOnce("an NSBitmapImageRep of this layout");
        [self release];
        return nil;
    }
    _foreign = YES;
    _bps = _rbps = bps;
    _rspace = rspace;
    _rplanar = planar && spp > 1;
    _rformat = format;
    _rplaneCount = _rplanar ? spp : 1;
    _rbpp = _rplanar ? bps : (bpp ? bpp : bps * spp);
    _rbpr = bpr ? bpr : (width * _rbpp + 7) / 8;
    _bpr = width * 4;
    _data = calloc((size_t)(_bpr * (height ? height : 1)), 1);
    _owns = YES;
    BOOL given = planes && planes[0];
    for (NSInteger i = 0; i < _rplaneCount; i++) {
        if (given && planes[i]) {
            _planes[i] = planes[i];
        } else {
            _planes[i] = calloc((size_t)(_rbpr * (height ? height : 1)), 1);
            _rowns = YES; /* all of them were allocated here, or none */
        }
    }
    _rdirty = YES;
    return self;
}

/* one sample of one pixel, scaled to 0...255 */
static unsigned bitmap_sample(const unsigned char *row, NSInteger bit, NSInteger bps)
{
    switch (bps) {
    case 16: {
        const unsigned char *p = row + bit / 8;
        return (unsigned)((p[0] << 8 | p[1]) >> 8); /* big-endian, as NSBitmapImageRep stores them */
    }
    case 8:
        return row[bit / 8];
    default: {
        unsigned v = (row[bit / 8] >> (8 - bps - bit % 8)) & ((1u << bps) - 1);
        return v * 255 / ((1u << bps) - 1);
    }
    }
}

/* turns the program's pixels into 8-bit RGBA, premultiplied */
- (void)_syncForeign
{
    if (!_foreign)
        return;
    _rdirty = NO;
    _stale = YES;
    NSInteger colours = _spp - (_alpha ? 1 : 0);
    BOOL first = _alpha && (_rformat & NSBitmapFormatAlphaFirst);
    BOOL straight = _alpha && (_rformat & NSBitmapFormatAlphaNonpremultiplied);
    for (NSInteger y = 0; y < _high; y++) {
        unsigned char *out = _data + y * _bpr;
        for (NSInteger x = 0; x < _wide; x++, out += 4) {
            unsigned v[5];
            for (NSInteger s = 0; s < _spp; s++) {
                const unsigned char *row = _planes[_rplanar ? s : 0] + y * _rbpr;
                NSInteger bit = _rplanar ? x * _rbps : x * _rbpp + s * _rbps;
                v[s] = bitmap_sample(row, bit, _rbps);
            }
            unsigned a = 255;
            const unsigned *c = v;
            if (_alpha) {
                if (first) {
                    a = v[0];
                    c = v + 1;
                } else {
                    a = v[colours];
                }
            }
            unsigned r, g, b;
            switch (_rspace) {
            case RSPACE_WHITE: r = g = b = c[0]; break;
            case RSPACE_BLACK: r = g = b = (straight || !_alpha ? 255 : a) - c[0]; break;
            case RSPACE_RGB: r = c[0]; g = c[1]; b = c[2]; break;
            default: { /* CMYK, the simple way */
                unsigned k = c[3];
                r = (255 - (c[0] > 255 - k ? 255 : c[0] + k));
                g = (255 - (c[1] > 255 - k ? 255 : c[1] + k));
                b = (255 - (c[2] > 255 - k ? 255 : c[2] + k));
            }
            }
            if (straight) {
                r = r * a / 255;
                g = g * a / 255;
                b = b * a / 255;
            } else if (_alpha) {
                if (r > a) r = a;
                if (g > a) g = a;
                if (b > a) b = a;
            }
            out[0] = (unsigned char)r;
            out[1] = (unsigned char)g;
            out[2] = (unsigned char)b;
            out[3] = (unsigned char)a;
        }
    }
}

- (instancetype)initWithCGImage:(CGImageRef)image
{
    if (!image)
        return [self initWithBitmapDataPlanes:NULL pixelsWide:0 pixelsHigh:0 bitsPerSample:8 samplesPerPixel:4
                                     hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0
                                 bitsPerPixel:32];
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    if (!(self = [self initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4
                                        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                     bytesPerRow:0 bitsPerPixel:32]))
        return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(_data, w, h, 8, _bpr, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextDrawImage(cg, CGRectMake(0, 0, w, h), image);
    CGContextRelease(cg);
    /* drawn as itself until the pixels change */
    _image = CGImageRetain(image);
    CGImageAlphaInfo a = CGImageGetAlphaInfo(image);
    _alpha = a != kCGImageAlphaNone && a != kCGImageAlphaNoneSkipFirst && a != kCGImageAlphaNoneSkipLast;
    return self;
}

- (instancetype)initWithData:(NSData *)data
{
    CGImageSourceRef src = data ? CGImageSourceCreateWithData((CFDataRef)data, NULL) : NULL;
    CGImageRef image = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
    if (src)
        CFRelease(src);
    if (!image) {
        [self release];
        return nil;
    }
    self = [self initWithCGImage:image];
    CGImageRelease(image);
    return self;
}
+ (instancetype)imageRepWithData:(NSData *)data { return [[[self alloc] initWithData:data] autorelease]; }

- (BOOL)drawInRect:(NSRect)rect
{
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    CGImageRef image = cg ? [self CGImage] : NULL;
    if (!image)
        return NO;
    CGContextDrawImage(cg, rect, image);
    return YES;
}

- (void)dealloc
{
    if (_owns)
        free(_data);
    if (_rowns)
        for (NSInteger i = 0; i < _rplaneCount; i++)
            free(_planes[i]);
    [_space release];
    CGImageRelease(_image);
    [super dealloc];
}

- (unsigned char *)bitmapData
{
    _exposed = YES;
    _rdirty = YES;
    return _foreign ? _planes[0] : _data;
}
- (void)getBitmapDataPlanes:(unsigned char **)data
{
    if (!data)
        return;
    _exposed = YES;
    _rdirty = YES;
    for (int i = 0; i < 5; i++)
        data[i] = _foreign ? (i < _rplaneCount ? _planes[i] : NULL) : (i == 0 ? _data : NULL);
}
- (BOOL)isPlanar { return _foreign && _rplanar; }
- (NSInteger)numberOfPlanes { return _foreign ? _rplaneCount : 1; }
- (NSInteger)bytesPerPlane { return (_foreign ? _rbpr : _bpr) * _high; }
- (NSInteger)bytesPerRow { return _foreign ? _rbpr : _bpr; }
- (NSInteger)samplesPerPixel { return _spp; }
- (NSInteger)bitsPerPixel { return _foreign ? _rbpp : 32; }
- (NSBitmapFormat)bitmapFormat { return _foreign ? _rformat : 0; }
- (NSString *)colorSpaceName { return _space ? _space : NSDeviceRGBColorSpace; }

- (CGImageRef)CGImage
{
    if (_foreign && (_exposed || _rdirty))
        [self _syncForeign];
    if (_image && !_exposed && !_stale)
        return _image;
    _stale = NO;
    CGImageRelease(_image);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(_data, _wide, _high, 8, _bpr, space,
                                            _alpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    _image = cg ? CGBitmapContextCreateImage(cg) : NULL;
    CGContextRelease(cg);
    return _image;
}

/* Rows run top to bottom; colours come back un-premultiplied. */
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y
{
    if (x < 0 || y < 0 || x >= _wide || y >= _high)
        return nil;
    if (_rdirty)
        [self _syncForeign];
    const unsigned char *p = _data + y * _bpr + x * 4;
    CGFloat a = _alpha ? p[3] / 255.0 : 1;
    if (a == 0)
        return [NSColor colorWithRed:0 green:0 blue:0 alpha:0];
    return [NSColor colorWithRed:p[0] / 255.0 / a green:p[1] / 255.0 / a blue:p[2] / 255.0 / a alpha:a];
}

- (void)setColor:(NSColor *)color atX:(NSInteger)x y:(NSInteger)y
{
    if (x < 0 || y < 0 || x >= _wide || y >= _high)
        return;
    CGFloat c[4];
    AColorRGBA(color, c);
    if (_rdirty)
        [self _syncForeign];
    unsigned char *p = _data + y * _bpr + x * 4;
    CGFloat a = _alpha ? c[3] : 1;
    _stale = YES;
    for (int i = 0; i < 3; i++)
        p[i] = (unsigned char)lround(c[i] * a * 255);
    p[3] = (unsigned char)lround(a * 255);
}

static cairo_status_t append_png(void *closure, const unsigned char *data, unsigned int length)
{
    [(NSMutableData *)closure appendBytes:data length:length];
    return 0;
}

/* TIFF, JPEG and BMP files are written by this system's GdkPixbuf, from
 * the pixels un-premultiplied; PNG files by Cairo. */
- (NSData *)_pixbufFileOfType:(const char *)type quality:(NSNumber *)quality
{
    size_t bpr = (size_t)_wide * 4;
    unsigned char *plain = malloc(bpr * (_high ? _high : 1));
    for (NSInteger y = 0; y < _high; y++) {
        const unsigned char *p = _data + y * _bpr;
        unsigned char *q = plain + y * bpr;
        for (NSInteger x = 0; x < _wide; x++, p += 4, q += 4) {
            unsigned a = _alpha ? p[3] : 255;
            for (int i = 0; i < 3; i++)
                q[i] = a ? (unsigned char)(a == 255 ? p[i] : (p[i] * 255 + a / 2) / a) : 0;
            q[3] = (unsigned char)a;
        }
    }
    BOOL alpha = _alpha && strcmp(type, "jpeg") && strcmp(type, "bmp");
    if (!alpha) /* packed to RGB */
        for (NSInteger i = 0; i < _wide * _high; i++)
            memmove(plain + i * 3, plain + i * 4, 3);
    GdkPixbuf *pb = gdk_pixbuf_new_from_data(plain, 0, alpha, 8, (int)_wide, (int)_high,
                                             (int)(alpha ? bpr : (size_t)_wide * 3), NULL, NULL);
    char *buffer = NULL;
    unsigned long size = 0;
    GError *error = NULL;
    char q[8];
    char *keys[2] = {"quality", NULL}, *values[2] = {q, NULL};
    snprintf(q, sizeof q, "%d", quality ? (int)lround(fmin(fmax([quality doubleValue], 0), 1) * 100) : 90);
    BOOL ok = pb && gdk_pixbuf_save_to_bufferv(pb, &buffer, &size, type, !strcmp(type, "jpeg") ? keys : NULL,
                                               !strcmp(type, "jpeg") ? values : NULL, &error);
    if (error)
        g_error_free(error);
    NSData *out = ok ? [NSData dataWithBytes:buffer length:size] : nil;
    g_free(buffer);
    if (pb)
        g_object_unref(pb);
    free(plain);
    return out;
}

- (NSData *)TIFFRepresentation { return [self representationUsingType:NSBitmapImageFileTypeTIFF properties:@{}]; }

- (NSData *)representationUsingType:(NSBitmapImageFileType)type properties:(NSDictionary *)properties
{
    if (_foreign && (_exposed || _rdirty))
        [self _syncForeign];
    if (type == NSBitmapImageFileTypeTIFF)
        return [self _pixbufFileOfType:"tiff" quality:nil];
    if (type == NSBitmapImageFileTypeJPEG)
        return [self _pixbufFileOfType:"jpeg" quality:properties[NSImageCompressionFactor]];
    if (type == NSBitmapImageFileTypeBMP)
        return [self _pixbufFileOfType:"bmp" quality:nil];
    if (type != NSBitmapImageFileTypePNG) {
        AWarnOnce("writing GIF files");
        return nil;
    }
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)_wide, (int)_high);
    uint32_t *dst = (uint32_t *)cairo_image_surface_get_data(s);
    int stride = cairo_image_surface_get_stride(s);
    cairo_surface_flush(s);
    for (NSInteger y = 0; y < _high; y++) {
        const unsigned char *p = _data + y * _bpr;
        uint32_t *row = (uint32_t *)((unsigned char *)dst + y * stride);
        for (NSInteger x = 0; x < _wide; x++, p += 4)
            row[x] = (uint32_t)(_alpha ? p[3] : 255) << 24 | (uint32_t)p[0] << 16 | (uint32_t)p[1] << 8 | p[2];
    }
    cairo_surface_mark_dirty(s);
    NSMutableData *out = [NSMutableData data];
    cairo_surface_write_to_png_stream(s, append_png, out);
    cairo_surface_destroy(s);
    return out;
}
@end
