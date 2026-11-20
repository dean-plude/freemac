/* SPDX-License-Identifier: GPL-3.0-or-later
 * Colour spaces and colours. Ferry draws everything as sRGB and doesn't do
 * colour management yet: a colour's components are taken as sRGB values
 * whatever the space is called (grey and CMYK are converted simply). */
#import "GInternal.h"

const CFStringRef kCGColorSpaceSRGB = (CFStringRef)@"kCGColorSpaceSRGB";
const CFStringRef kCGColorSpaceGenericRGB = (CFStringRef)@"kCGColorSpaceGenericRGB";
const CFStringRef kCGColorSpaceGenericGray = (CFStringRef)@"kCGColorSpaceGenericGray";
const CFStringRef kCGColorSpaceGenericGrayGamma2_2 = (CFStringRef)@"kCGColorSpaceGenericGrayGamma2_2";
const CFStringRef kCGColorSpaceLinearSRGB = (CFStringRef)@"kCGColorSpaceLinearSRGB";
const CFStringRef kCGColorSpaceExtendedSRGB = (CFStringRef)@"kCGColorSpaceExtendedSRGB";
const CFStringRef kCGColorSpaceDisplayP3 = (CFStringRef)@"kCGColorSpaceDisplayP3";
const CFStringRef kCGColorSpaceGenericCMYK = (CFStringRef)@"kCGColorSpaceGenericCMYK";
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

CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef cfname)
{
    NSString *name = (NSString *)cfname;
    if ([name isEqual:(id)kCGColorSpaceGenericGray] || [name isEqual:(id)kCGColorSpaceGenericGrayGamma2_2])
        return (CGColorSpaceRef)make_space(kCGColorSpaceModelMonochrome, 1, name);
    if ([name isEqual:(id)kCGColorSpaceGenericCMYK])
        return (CGColorSpaceRef)make_space(kCGColorSpaceModelCMYK, 4, name);
    if ([name isEqual:(id)kCGColorSpaceSRGB] || [name isEqual:(id)kCGColorSpaceGenericRGB] ||
        [name isEqual:(id)kCGColorSpaceLinearSRGB] || [name isEqual:(id)kCGColorSpaceExtendedSRGB] ||
        [name isEqual:(id)kCGColorSpaceDisplayP3])
        return (CGColorSpaceRef)make_space(kCGColorSpaceModelRGB, 3, name);
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
        s->model != kCGColorSpaceModelCMYK)
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
