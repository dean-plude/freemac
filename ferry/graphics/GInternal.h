/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Graphics and Core Text: shared internals. Our own code,
 * written from Apple's public API documentation; it is built as a Mach-O
 * library with ferry-cc and draws with this system's Cairo and Pango (see
 * host.h). Every CG and CT object is an Objective-C object, so CFRetain and
 * CFRelease work on them. Built without ARC. */
#ifndef FERRY_GRAPHICS_INTERNAL_H
#define FERRY_GRAPHICS_INTERNAL_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "host.h"

#define OBJ(x) ((id)(x))

/* Says once, on stderr, that something isn't supported yet. */
void GWarnOnce(const char *what);

/* ---- colour ------------------------------------------------------------------- */

@interface GColorSpace : NSObject {
@public
    CGColorSpaceModel model;
    size_t ncomp;
    NSString *name;
}
@end

@interface GColor : NSObject {
@public
    GColorSpace *space;
    size_t ncomp;           /* including alpha */
    CGFloat comp[5];
    double rgba[4];         /* the colour as sRGB, not premultiplied */
}
@end

GColorSpace *GSpaceRGB(void);   /* shared, not retained */
GColorSpace *GSpaceGray(void);
GColorSpace *GSpaceCMYK(void);
GColor *GColorNew(GColorSpace *space, const CGFloat *components);   /* retained */

/* ---- paths ------------------------------------------------------------------- */

struct gelem {
    CGPathElementType type;
    CGPoint pts[3];
};

@interface GPath : NSObject <NSCopying, NSMutableCopying> {
@public
    struct gelem *elems;
    size_t count, cap;
    CGPoint start, current;
    BOOL hasCurrent;
}
@end

/* Somewhere to send path pieces: a CGPath or a Cairo context. */
struct gsink {
    void (*move)(void *info, CGPoint p);
    void (*line)(void *info, CGPoint p);
    void (*curve)(void *info, CGPoint c1, CGPoint c2, CGPoint p);
    void (*close)(void *info);
    BOOL (*current)(void *info, CGPoint *p);
    void *info;
};
void GSinkArc(const struct gsink *s, CGFloat x, CGFloat y, CGFloat r, CGFloat start, CGFloat end, BOOL clockwise);
void GSinkArcToPoint(const struct gsink *s, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r);
void GSinkEllipse(const struct gsink *s, CGRect rect);
void GSinkRoundedRect(const struct gsink *s, CGRect rect, CGFloat cw, CGFloat ch);
void GSinkRect(const struct gsink *s, CGRect rect);
void GSinkQuad(const struct gsink *s, CGPoint c, CGPoint p);

void GPathToCairo(GPath *path, cairo_t *cr);       /* appends, in cr's user space */
GPath *GPathFromCairo(cairo_t *cr);                  /* retained */

/* ---- images --------------------------------------------------------------------- */

/* How one pixel of 8-bit-per-component data is laid out. */
struct gfmt {
    int bytes;          /* per pixel */
    int r, g, b, a;     /* byte offsets; -1 if absent (a grey image uses g only) */
    BOOL gray, premultiplied, alphaOnly;
};
BOOL GFormatFor(size_t bpc, size_t bpp, CGColorSpaceModel model, uint32_t info, struct gfmt *out);
void GToCairo(const struct gfmt *f, const uint8_t *src, uint32_t *dst, size_t width);
void GFromCairo(const struct gfmt *f, const uint32_t *src, uint8_t *dst, size_t width, BOOL opaque);

@interface GDataProvider : NSObject {
@public
    NSData *data;
}
@end

@interface GImage : NSObject {
@public
    size_t width, height, bpc, bpp, bpr;
    uint32_t info;
    GColorSpace *space;
    GDataProvider *provider;
    BOOL interpolate, mask;
    cairo_surface_t *surface;   /* made the first time the image is drawn */
}
@end
cairo_surface_t *GImageSurface(GImage *image);
GImage *GImageDecode(NSData *data, NSString **type);   /* retained; nil if unreadable */

@interface GGradient : NSObject {
@public
    size_t count;
    double *locations;
    double (*rgba)[4];
}
@end

/* ---- contexts ------------------------------------------------------------------- */

struct gstate {
    double fill[4], stroke[4];
    GColorSpace *fillSpace, *strokeSpace;
    double alpha;
    BOOL antialias;
    CGInterpolationQuality interpolation;
    CGTextDrawingMode textMode;
    CGFloat characterSpacing, fontSize;
    /* the shadow, in base space: none when its colour's alpha is 0 */
    CGSize shadowOffset;
    CGFloat shadowBlur;
    double shadowColor[4];
    BOOL shadowOnly;    /* only the shadow outside the shape is painted (AppKit's NSFocusRingOnly) */
};

@interface GContext : NSObject {
@public
    cairo_t *cr;
    cairo_surface_t *surface;
    cairo_matrix_t base;          /* device space as CG sees it, to Cairo's */
    struct gstate *states;
    int depth, cap;
    BOOL allowsAntialias;
    CGAffineTransform textMatrix;   /* its tx and ty are the text position */
    /* bitmap contexts */
    void *data;
    BOOL ownsData, shadow;
    BOOL shadowLoaded;   /* the shadow surface holds the pixels: between GContextWillDraw and DidDraw */
    size_t width, height, bpc, bpp, bpr;
    uint32_t info;
    GColorSpace *space;
    struct gfmt fmt;
    BOOL shadowOnly;    /* draw only the shadows of what is drawn (a text run's shadow, under the line) */
}
@end

#define GSTATE(c) (&(c)->states[(c)->depth])
void GContextWillDraw(GContext *c);    /* brings outside changes to the pixels in */
void GContextDidDraw(GContext *c);     /* writes the drawing out to the caller's pixels */
void GContextSetSource(GContext *c, const double rgba[4]);
/* Around one drawing call: with a shadow set, what the call draws goes into
 * a group, and GContextEndShadow paints its shadow and then the drawing. */
BOOL GContextBeginShadow(GContext *c);
void GContextEndShadow(GContext *c, BOOL began);
/* For AppKit's focus rings: what is drawn next paints only its shadow, and
 * that only outside the shape, until the graphics state is restored. */
void GContextSetShadowOnly(CGContextRef c, BOOL only);

/* Draws glyphs or a laid-out line in the context's text space, at (x, y)
 * there, following the text drawing mode. The body draws with Cairo's y
 * going down from the baseline, as Pango and Cairo's glyph calls expect;
 * when path is YES it must only add to the current path. */
void GContextDrawText(GContext *c, CGFloat x, CGFloat y, void (^body)(BOOL path));

/* ---- Core Text ---------------------------------------------------------------- */

/* A font. AppKit's NSFont and NSParagraphStyle are subclasses of these two
 * that add no instance variables, so Core Text calls work on them. */
@interface GFont : NSObject <NSCopying> {
@public
    PangoFontDescription *desc;
    PangoFont *font;
    hb_font_t *hb;
    unsigned upem;
    CGFloat size;
    CGAffineTransform matrix;
    NSString *family;   /* as installed */
    int weight, style;
    BOOL monospace;
}
@end

/* A font of a family as installed (or Pango's nearest), with a Pango weight
 * and style; and a font's style name ("Bold Italic" as "BoldItalic"). */
__attribute__((visibility("hidden"))) GFont *GFontLoad(NSString *family, int weight, int style, CGFloat size,
                                                       const CGAffineTransform *matrix);
__attribute__((visibility("hidden"))) NSString *GFontStyleName(GFont *f);
/* the family that stands for a Mac family (Helvetica, Menlo...), or nil */
NSString *GFontMacFamily(NSString *name);

@interface GParagraphStyle : NSObject <NSCopying> {
@public
    uint8_t alignment, lineBreakMode, writingDirection;
    CGFloat values[17];
}
@end


/* ---- conversions ---------------------------------------------------------------- */

static inline cairo_matrix_t GMatrix(CGAffineTransform t)
{
    cairo_matrix_t m = {t.a, t.b, t.c, t.d, t.tx, t.ty};
    return m;
}
static inline CGAffineTransform GTransform(cairo_matrix_t m)
{
    CGAffineTransform t = {m.xx, m.yx, m.xy, m.yy, m.x0, m.y0};
    return t;
}

#endif
