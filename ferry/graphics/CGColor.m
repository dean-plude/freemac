/* SPDX-License-Identifier: GPL-3.0-or-later
 * Colour spaces and colours. Ferry draws everything as sRGB and doesn't do
 * colour management yet: a colour's components are taken as sRGB values
 * whatever the space is called (grey and CMYK are converted simply). */
#include <pthread.h>
#import "GInternal.h"
#include <math.h>

const CFStringRef kCGColorSpaceSRGB = (CFStringRef)@"kCGColorSpaceSRGB";
const CFStringRef kCGColorSpaceGenericRGB = (CFStringRef)@"kCGColorSpaceGenericRGB";
const CFStringRef kCGColorSpaceGenericGray = (CFStringRef)@"kCGColorSpaceGenericGray";
const CFStringRef kCGColorSpaceGenericGrayGamma2_2 = (CFStringRef)@"kCGColorSpaceGenericGrayGamma2_2";
const CFStringRef kCGColorSpaceExtendedGray = (CFStringRef)@"kCGColorSpaceExtendedGray"; /* Stats (1.271) */
const CFStringRef kCGColorSpaceLinearGray = (CFStringRef)@"kCGColorSpaceLinearGray";
const CFStringRef kCGColorSpaceLinearSRGB = (CFStringRef)@"kCGColorSpaceLinearSRGB";
const CFStringRef kCGColorSpaceExtendedSRGB = (CFStringRef)@"kCGColorSpaceExtendedSRGB";
const CFStringRef kCGColorSpaceDisplayP3 = (CFStringRef)@"kCGColorSpaceDisplayP3";
const CFStringRef kCGColorSpaceGenericCMYK = (CFStringRef)@"kCGColorSpaceGenericCMYK";
/* more RGB spaces by name (freemac Godot work), drawn as sRGB like the rest */
const CFStringRef kCGColorSpaceExtendedLinearSRGB = (CFStringRef)@"kCGColorSpaceExtendedLinearSRGB";
const CFStringRef kCGColorSpaceDCIP3 = (CFStringRef)@"kCGColorSpaceDCIP3";
const CFStringRef kCGColorSpaceITUR_709 = (CFStringRef)@"kCGColorSpaceITUR_709";
const CFStringRef kCGColorSpaceITUR_2020 = (CFStringRef)@"kCGColorSpaceITUR_2020";
const CFStringRef kCGColorSpaceAdobeRGB1998 = (CFStringRef)@"kCGColorSpaceAdobeRGB1998";
const CFStringRef kCGColorSpaceExtendedDisplayP3 = (CFStringRef)@"kCGColorSpaceExtendedDisplayP3";
/* CIE L*a*b* (freemac 1.NEXT), MacVim works out its tab bar's colours in it */
const CFStringRef kCGColorSpaceGenericLab = (CFStringRef)@"kCGColorSpaceGenericLab";
const CFStringRef kCGColorWhite = (CFStringRef)@"kCGColorWhite";
const CFStringRef kCGColorBlack = (CFStringRef)@"kCGColorBlack";
const CFStringRef kCGColorClear = (CFStringRef)@"kCGColorClear";

@implementation GColorSpace

- (void)dealloc
{
    [name release];
    [super dealloc];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[GColorSpace class]])
        return NO;
    GColorSpace *o = other;
    return o->model == model && [o->name isEqual:name];
}

- (NSUInteger)hash { return (NSUInteger)model ^ [name hash]; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CGColorSpace %p> (%@)", self, name];
}

@end

static GColorSpace *make_space(CGColorSpaceModel model, size_t ncomp, NSString *name)
{
    GColorSpace *s = [[GColorSpace alloc] init];
    s->model = model;
    s->ncomp = ncomp;
    s->name = [name copy];
    return s;
}

GColorSpace *GSpaceRGB(void)
{
    static GColorSpace *s;
    if (!s)
        s = make_space(kCGColorSpaceModelRGB, 3, @"kCGColorSpaceDeviceRGB");
    return s;
}

GColorSpace *GSpaceGray(void)
{
    static GColorSpace *s;
    if (!s)
        s = make_space(kCGColorSpaceModelMonochrome, 1, @"kCGColorSpaceDeviceGray");
    return s;
}

GColorSpace *GSpaceCMYK(void)
{
    static GColorSpace *s;
    if (!s)
        s = make_space(kCGColorSpaceModelCMYK, 4, @"kCGColorSpaceDeviceCMYK");
    return s;
}

CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void) { return (CGColorSpaceRef)[GSpaceRGB() retain]; }
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void) { return (CGColorSpaceRef)[GSpaceGray() retain]; }
CGColorSpaceRef CGColorSpaceCreateDeviceCMYK(void) { return (CGColorSpaceRef)[GSpaceCMYK() retain]; }

static GColorSpace *named_space(NSString *name)
{
    if ([name isEqual:(id)kCGColorSpaceGenericLab])
        return make_space(kCGColorSpaceModelLab, 3, name);
    if ([name isEqual:(id)kCGColorSpaceGenericGray] || [name isEqual:(id)kCGColorSpaceGenericGrayGamma2_2] ||
        [name isEqual:(id)kCGColorSpaceExtendedGray] || [name isEqual:(id)kCGColorSpaceLinearGray])
        return make_space(kCGColorSpaceModelMonochrome, 1, name);
    if ([name isEqual:(id)kCGColorSpaceGenericCMYK])
        return make_space(kCGColorSpaceModelCMYK, 4, name);
    if ([name isEqual:(id)kCGColorSpaceSRGB] || [name isEqual:(id)kCGColorSpaceGenericRGB] ||
        [name isEqual:(id)kCGColorSpaceLinearSRGB] || [name isEqual:(id)kCGColorSpaceExtendedSRGB] ||
        [name isEqual:(id)kCGColorSpaceDisplayP3] || [name isEqual:(id)kCGColorSpaceExtendedLinearSRGB] ||
        [name isEqual:(id)kCGColorSpaceDCIP3] || [name isEqual:(id)kCGColorSpaceITUR_709] ||
        [name isEqual:(id)kCGColorSpaceITUR_2020] || [name isEqual:(id)kCGColorSpaceAdobeRGB1998] ||
        [name isEqual:(id)kCGColorSpaceExtendedDisplayP3])
        return make_space(kCGColorSpaceModelRGB, 3, name);
    return nil;
}

/* As on a Mac, a named space is made once and kept: each call hands back the
 * same space, retained, so a program that lets go of its reference while it
 * still uses the space (Qt's bitmap contexts do) keeps a live one. */
CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef cfname)
{
    static NSMutableDictionary *kept;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    NSString *name = (NSString *)cfname;
    if (![name isKindOfClass:[NSString class]])
        return NULL;
    pthread_mutex_lock(&lock);
    if (!kept)
        kept = [[NSMutableDictionary alloc] init];
    GColorSpace *s = [kept objectForKey:name];
    if (!s) {
        s = named_space(name);
        if (s) {
            [kept setObject:s forKey:name];
            [s release];
        }
    }
    [s retain];
    pthread_mutex_unlock(&lock);
    return (CGColorSpaceRef)s;
}

/* An ICC profile names its data's colour space at byte 16 ('RGB ', 'GRAY',
 * 'CMYK'); Ferry draws such data in its sRGB, grey or CMYK space. */
CGColorSpaceRef CGColorSpaceCreateWithICCData(CFTypeRef data)
{
    NSData *d = (NSData *)data;
    if (![d isKindOfClass:[NSData class]] || d.length < 20)
        return NULL;
    const unsigned char *b = d.bytes;
    if (!memcmp(b + 16, "GRAY", 4))
        return CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
    if (!memcmp(b + 16, "CMYK", 4))
        return CGColorSpaceCreateWithName(kCGColorSpaceGenericCMYK);
    if (!memcmp(b + 16, "RGB ", 4))
        return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return NULL;
}

CGColorSpaceRef CGColorSpaceCreateICCBased(size_t nComponents, const CGFloat *range, CGDataProviderRef profile,
                                           CGColorSpaceRef alternate)
{
    (void)range;
    CFDataRef data = profile ? CGDataProviderCopyData(profile) : NULL;
    CGColorSpaceRef s = data ? CGColorSpaceCreateWithICCData(data) : NULL;
    if (data)
        CFRelease(data);
    if (s && CGColorSpaceGetNumberOfComponents(s) == nComponents)
        return s;
    CGColorSpaceRelease(s);
    if (alternate)
        return CGColorSpaceRetain(alternate);
    return nComponents == 1 ? CGColorSpaceCreateDeviceGray()
           : nComponents == 4 ? CGColorSpaceCreateDeviceCMYK()
                              : CGColorSpaceCreateDeviceRGB();
}

/* The ICC profile of an RGB or grey space: the space Ferry draws it in,
 * sRGB or grey with sRGB's curve, written as an ICC version 4 display
 * profile from the sRGB standard's (IEC 61966-2-1) primaries, adapted to
 * the D50 white ICC profiles are measured against, and its tone curve.
 * Programs such as Qt read a screen's or window's colour space from it. */
static void icc_u32(NSMutableData *d, size_t at, uint32_t v)
{
    unsigned char b[4] = { v >> 24, v >> 16, v >> 8, v };
    [d replaceBytesInRange:NSMakeRange(at, 4) withBytes:b];
}
static void icc_add32(NSMutableData *d, uint32_t v)
{
    unsigned char b[4] = { v >> 24, v >> 16, v >> 8, v };
    [d appendBytes:b length:4];
}
static uint32_t icc_fixed(double v) { return (uint32_t)(int32_t)lround(v * 65536.0); }
static void icc_pad(NSMutableData *d)
{
    static const unsigned char zero[4];
    if (d.length % 4)
        [d appendBytes:zero length:4 - d.length % 4];
}
static NSData *icc_xyz(double x, double y, double z)
{
    NSMutableData *t = [NSMutableData dataWithBytes:"XYZ \0\0\0\0" length:8];
    icc_add32(t, icc_fixed(x));
    icc_add32(t, icc_fixed(y));
    icc_add32(t, icc_fixed(z));
    return t;
}
static NSData *icc_text(NSString *text)
{
    NSMutableData *t = [NSMutableData dataWithBytes:"mluc\0\0\0\0" length:8];
    NSData *u = [text dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    icc_add32(t, 1);
    icc_add32(t, 12);
    [t appendBytes:"enUS" length:4];
    icc_add32(t, (uint32_t)u.length);
    icc_add32(t, 28);
    [t appendData:u];
    return t;
}
static NSData *icc_profile(BOOL gray)
{
    /* sRGB's curve: (a x + b)^g above d, c x below */
    NSMutableData *curve = [NSMutableData dataWithBytes:"para\0\0\0\0\0\3\0\0" length:12];
    const double para[5] = { 2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045 };
    for (int i = 0; i < 5; i++)
        icc_add32(curve, icc_fixed(para[i]));
    struct { const char *sig; NSData *data; } tags[10];
    int n = 0;
    tags[n].sig = "desc", tags[n++].data = icc_text(gray ? @"Gray (sRGB curve)" : @"sRGB");
    tags[n].sig = "cprt", tags[n++].data = icc_text(@"No copyright, use freely");
    tags[n].sig = "wtpt", tags[n++].data = icc_xyz(0.9642, 1.0, 0.8249);
    if (gray) {
        tags[n].sig = "kTRC", tags[n++].data = curve;
    } else {
        tags[n].sig = "rXYZ", tags[n++].data = icc_xyz(0.4360747, 0.2225045, 0.0139322);
        tags[n].sig = "gXYZ", tags[n++].data = icc_xyz(0.3850649, 0.7168786, 0.0971045);
        tags[n].sig = "bXYZ", tags[n++].data = icc_xyz(0.1430804, 0.0606169, 0.7141733);
        tags[n].sig = "rTRC", tags[n++].data = curve;
        tags[n].sig = "gTRC", tags[n++].data = curve;
        tags[n].sig = "bTRC", tags[n++].data = curve;
    }
    NSMutableData *d = [NSMutableData dataWithLength:128];
    icc_u32(d, 8, 0x04300000);                       /* version 4.3 */
    [d replaceBytesInRange:NSMakeRange(12, 4) withBytes:"mntr"];
    [d replaceBytesInRange:NSMakeRange(16, 4) withBytes:gray ? "GRAY" : "RGB "];
    [d replaceBytesInRange:NSMakeRange(20, 4) withBytes:"XYZ "];
    [d replaceBytesInRange:NSMakeRange(36, 4) withBytes:"acsp"];
    icc_u32(d, 68, icc_fixed(0.9642));               /* the D50 illuminant */
    icc_u32(d, 72, icc_fixed(1.0));
    icc_u32(d, 76, icc_fixed(0.8249));
    icc_add32(d, (uint32_t)n);
    size_t table = d.length;
    [d increaseLengthBy:12 * n];
    for (int i = 0; i < n; i++) {
        size_t at = 0;
        for (int j = 0; j < i; j++)
            if (tags[j].data == tags[i].data)        /* shared, as the three curves are */
                at = j;
        size_t offset, size = tags[i].data.length;
        if (at || (i && tags[0].data == tags[i].data)) {
            unsigned char b[4];
            [d getBytes:b range:NSMakeRange(table + 12 * at + 4, 4)];
            offset = (size_t)b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
        } else {
            icc_pad(d);
            offset = d.length;
            [d appendData:tags[i].data];
        }
        [d replaceBytesInRange:NSMakeRange(table + 12 * i, 4) withBytes:tags[i].sig];
        icc_u32(d, table + 12 * i + 4, (uint32_t)offset);
        icc_u32(d, table + 12 * i + 8, (uint32_t)size);
    }
    icc_pad(d);
    icc_u32(d, 0, (uint32_t)d.length);
    return d;
}

CFDataRef CGColorSpaceCopyICCData(CGColorSpaceRef space)
{
    CGColorSpaceModel model = CGColorSpaceGetModel(space);
    if (model != kCGColorSpaceModelRGB && model != kCGColorSpaceModelMonochrome)
        return NULL;
    return (CFDataRef)[icc_profile(model == kCGColorSpaceModelMonochrome) copy];
}

CFPropertyListRef CGColorSpaceCopyPropertyList(CGColorSpaceRef space)
{
    if (!space)
        return NULL;
    NSString *name = ((GColorSpace *)space)->name;
    if (name)
        return (CFPropertyListRef)[name copy];
    return (CFPropertyListRef)CGColorSpaceCopyICCData(space);
}

CGColorSpaceRef CGColorSpaceCreateWithPropertyList(CFPropertyListRef plist)
{
    id p = (id)plist;
    if ([p isKindOfClass:[NSString class]])
        return CGColorSpaceCreateWithName((CFStringRef)p);
    if ([p isKindOfClass:[NSData class]])
        return CGColorSpaceCreateWithICCData(p);
    return NULL;
}

CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef space) { return (CGColorSpaceRef)[OBJ(space) retain]; }
void CGColorSpaceRelease(CGColorSpaceRef space) { [OBJ(space) release]; }
size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef space) { return space ? ((GColorSpace *)space)->ncomp : 0; }
CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef space)
{
    return space ? ((GColorSpace *)space)->model : kCGColorSpaceModelUnknown;
}
CFStringRef CGColorSpaceGetName(CGColorSpaceRef space) { return (CFStringRef)((GColorSpace *)space)->name; }
CFStringRef CGColorSpaceCopyName(CGColorSpaceRef space)
{
    return (CFStringRef)[((GColorSpace *)space)->name copy];
}
CFTypeID CGColorSpaceGetTypeID(void) { return (CFTypeID)[GColorSpace class]; }

/* ---- colours ---------------------------------------------------------------------- */

static double clamp01(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

@implementation GColor

- (void)dealloc
{
    [space release];
    [super dealloc];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[GColor class]])
        return NO;
    GColor *o = other;
    if (o->ncomp != ncomp || ![o->space isEqual:space])
        return NO;
    for (size_t i = 0; i < ncomp; i++)
        if (o->comp[i] != comp[i])
            return NO;
    return YES;
}

- (NSUInteger)hash { return (NSUInteger)(rgba[0] * 255) << 24 ^ (NSUInteger)(rgba[1] * 255) << 16 ^ (NSUInteger)(rgba[2] * 255) << 8 ^ (NSUInteger)(rgba[3] * 255); }

- (NSString *)description
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"<CGColor %p> [%@] ( ", self, space->name];
    for (size_t i = 0; i < ncomp; i++)
        [s appendFormat:@"%g ", comp[i]];
    [s appendString:@")"];
    return s;
}

@end

/* ---- CIE L*a*b* ---------------------------------------------------------------------- */

/* Lab colours turn into sRGB and back through CIE XYZ, by the CIE's
 * published formulas (CIE 15) and the sRGB standard's (IEC 61966-2-1)
 * matrix and tone curve. A Lab space's own white point is taken to be
 * sRGB's D65 white, so L* 100 with a* and b* 0 is sRGB white whichever
 * white point the space was made with. */
static const double d65[3] = {0.95047, 1.0, 1.08883};
static double lab_f(double t) { return t > 216.0 / 24389 ? cbrt(t) : t * 841.0 / 108 + 4.0 / 29; }
static double lab_finv(double t) { return t > 6.0 / 29 ? t * t * t : (t - 4.0 / 29) * 108.0 / 841; }
static double to_linear(double c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static double from_linear(double l) { return l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055; }

void GColorLabToSRGB(const CGFloat lab[3], CGFloat rgb[3]) __attribute__((visibility("default")));
void GColorLabToSRGB(const CGFloat lab[3], CGFloat rgb[3])
{
    double fy = (lab[0] + 16) / 116, fx = fy + lab[1] / 500, fz = fy - lab[2] / 200;
    double x = d65[0] * lab_finv(fx), y = d65[1] * lab_finv(fy), z = d65[2] * lab_finv(fz);
    double r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    double g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    double b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
    rgb[0] = clamp01(from_linear(fmax(r, 0)));
    rgb[1] = clamp01(from_linear(fmax(g, 0)));
    rgb[2] = clamp01(from_linear(fmax(b, 0)));
}

void GColorSRGBToLab(const CGFloat rgb[3], CGFloat lab[3]) __attribute__((visibility("default")));
void GColorSRGBToLab(const CGFloat rgb[3], CGFloat lab[3])
{
    double r = to_linear(rgb[0]), g = to_linear(rgb[1]), b = to_linear(rgb[2]);
    double x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / d65[0];
    double y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / d65[1];
    double z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / d65[2];
    double fx = lab_f(x), fy = lab_f(y), fz = lab_f(z);
    lab[0] = 116 * fy - 16;
    lab[1] = 500 * (fx - fy);
    lab[2] = 200 * (fy - fz);
}

CGColorSpaceRef CGColorSpaceCreateLab(const CGFloat *whitePoint, const CGFloat *blackPoint, const CGFloat *range)
{
    if (!whitePoint || whitePoint[1] != 1 || whitePoint[0] <= 0 || whitePoint[2] <= 0)
        return NULL;
    (void)blackPoint;
    (void)range;
    return (CGColorSpaceRef)make_space(kCGColorSpaceModelLab, 3, @"kCGColorSpaceGenericLab");
}

GColor *GColorNew(GColorSpace *space, const CGFloat *components)
{
    GColor *c = [[GColor alloc] init];
    c->space = [space retain];
    c->ncomp = space->ncomp + 1;
    for (size_t i = 0; i < c->ncomp && i < 5; i++)
        c->comp[i] = components[i];
    const CGFloat *k = c->comp;
    switch (space->model) {
    case kCGColorSpaceModelMonochrome:
        c->rgba[0] = c->rgba[1] = c->rgba[2] = clamp01(k[0]);
        break;
    case kCGColorSpaceModelCMYK:
        for (int i = 0; i < 3; i++)
            c->rgba[i] = clamp01((1 - k[i]) * (1 - k[3]));
        break;
    case kCGColorSpaceModelLab:
        GColorLabToSRGB(k, c->rgba);
        break;
    default:
        for (int i = 0; i < 3; i++)
            c->rgba[i] = clamp01(k[i]);
        break;
    }
    c->rgba[3] = clamp01(k[c->ncomp - 1]);
    return c;
}

CGColorRef CGColorCreate(CGColorSpaceRef space, const CGFloat *components)
{
    if (!space || !components)
        return NULL;
    GColorSpace *s = (GColorSpace *)space;
    if (s->model != kCGColorSpaceModelRGB && s->model != kCGColorSpaceModelMonochrome &&
        s->model != kCGColorSpaceModelCMYK && s->model != kCGColorSpaceModelLab)
        return NULL;
    return (CGColorRef)GColorNew(s, components);
}

CGColorRef CGColorCreateGenericRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha)
{
    CGFloat k[] = {red, green, blue, alpha};
    GColorSpace *s = (GColorSpace *)CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    GColor *c = GColorNew(s, k);
    [s release];
    return (CGColorRef)c;
}

CGColorRef CGColorCreateSRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha)
{
    CGFloat k[] = {red, green, blue, alpha};
    GColorSpace *s = (GColorSpace *)CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    GColor *c = GColorNew(s, k);
    [s release];
    return (CGColorRef)c;
}

CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat alpha)
{
    CGFloat k[] = {gray, alpha};
    GColorSpace *s = (GColorSpace *)CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
    GColor *c = GColorNew(s, k);
    [s release];
    return (CGColorRef)c;
}

CGColorRef CGColorCreateGenericCMYK(CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat alpha)
{
    CGFloat comps[] = {cy, m, y, k, alpha};
    GColorSpace *s = (GColorSpace *)CGColorSpaceCreateWithName(kCGColorSpaceGenericCMYK);
    GColor *c = GColorNew(s, comps);
    [s release];
    return (CGColorRef)c;
}

CGColorRef CGColorCreateCopy(CGColorRef color) { return (CGColorRef)[OBJ(color) retain]; }

CGColorRef CGColorCreateCopyWithAlpha(CGColorRef color, CGFloat alpha)
{
    if (!color)
        return NULL;
    GColor *c = (GColor *)color;
    CGFloat k[5];
    memcpy(k, c->comp, sizeof k);
    k[c->ncomp - 1] = alpha;
    return (CGColorRef)GColorNew(c->space, k);
}

/* The colour in another colour space (freemac 1.264): through its sRGB
 * value, as Ferry draws in sRGB. Gray takes the colour's luminance; CMYK
 * the plain conversion with black taken out first. Patterns and spaces
 * with no components give NULL, as a colour that can't be matched does. */
CGColorRef CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceRef space, CGColorRenderingIntent intent,
                                                   CGColorRef color, CFDictionaryRef options)
{
    (void)intent;
    (void)options;
    if (!space || !color || ![(id)color isKindOfClass:[GColor class]])
        return NULL;
    GColor *c = (GColor *)color;
    GColorSpace *to = (GColorSpace *)space;
    if ([to isEqual:c->space])
        return (CGColorRef)[c retain];
    const double *v = c->rgba;
    CGFloat k[5] = {0};
    switch (to->model) {
    case kCGColorSpaceModelMonochrome:
        k[0] = 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
        k[1] = v[3];
        break;
    case kCGColorSpaceModelRGB:
        k[0] = v[0], k[1] = v[1], k[2] = v[2], k[3] = v[3];
        break;
    case kCGColorSpaceModelCMYK: {
        double black = 1 - fmax(v[0], fmax(v[1], v[2]));
        for (int i = 0; i < 3; i++)
            k[i] = black < 1 ? (1 - v[i] - black) / (1 - black) : 0;
        k[3] = black;
        k[4] = v[3];
        break;
    }
    default:
        return NULL;
    }
    return (CGColorRef)GColorNew(to, k);
}

CGColorRef CGColorGetConstantColor(CFStringRef name)
{
    static GColor *white, *black, *clear;
    if (!white) {
        GColorSpace *gray = (GColorSpace *)CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
        white = GColorNew(gray, (CGFloat[]){1, 1});
        black = GColorNew(gray, (CGFloat[]){0, 1});
        clear = GColorNew(gray, (CGFloat[]){0, 0});
        [gray release];
    }
    if ([(id)name isEqual:(id)kCGColorWhite])
        return (CGColorRef)white;
    if ([(id)name isEqual:(id)kCGColorBlack])
        return (CGColorRef)black;
    if ([(id)name isEqual:(id)kCGColorClear])
        return (CGColorRef)clear;
    return NULL;
}

CGColorRef CGColorRetain(CGColorRef color) { return (CGColorRef)[OBJ(color) retain]; }
void CGColorRelease(CGColorRef color) { [OBJ(color) release]; }
bool CGColorEqualToColor(CGColorRef a, CGColorRef b) { return a == b || (a && b && [OBJ(a) isEqual:OBJ(b)]); }
size_t CGColorGetNumberOfComponents(CGColorRef color) { return color ? ((GColor *)color)->ncomp : 0; }
const CGFloat *CGColorGetComponents(CGColorRef color) { return color ? ((GColor *)color)->comp : NULL; }
CGFloat CGColorGetAlpha(CGColorRef color) { return color ? ((GColor *)color)->comp[((GColor *)color)->ncomp - 1] : 0; }
CGColorSpaceRef CGColorGetColorSpace(CGColorRef color) { return color ? (CGColorSpaceRef)((GColor *)color)->space : NULL; }
CFTypeID CGColorGetTypeID(void) { return (CFTypeID)[GColor class]; }
