/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Core Text's font descriptors, a font's traits, names and tables, the font
 * manager's lists, and Core Graphics' CGFont, written from Apple's public
 * Core Text and Core Graphics documentation. Qt's font database on a Mac is
 * built on these (OBS's window draws its text through Qt).
 *
 * A descriptor is a dictionary of attributes, with the same keys as
 * AppKit's NSFontDescriptor. Matching one finds the faces Pango lists for
 * its family: an installed family by any case of its name, or, for a Mac
 * family that isn't installed (Helvetica, Menlo...), its stand-in, as
 * CTFontCreateWithName chooses one. A font's tables and names come from its
 * file through HarfBuzz.
 *
 * Ferry draws only installed fonts. A font made from a file's data (an
 * application's own font) describes itself from that data, and is drawn
 * with the installed family of its name, or Pango's nearest. Fonts are
 * drawn at their default variation, so no font reports variation axes.
 */
#import "GInternal.h"

/* ---- the keys ----------------------------------------------------------------------- */

const CFStringRef kCTFontURLAttribute = (CFStringRef)@"NSCTFontFileURLAttribute";
const CFStringRef kCTFontNameAttribute = (CFStringRef)@"NSFontNameAttribute";
const CFStringRef kCTFontDisplayNameAttribute = (CFStringRef)@"NSFontVisibleNameAttribute";
const CFStringRef kCTFontFamilyNameAttribute = (CFStringRef)@"NSFontFamilyAttribute";
const CFStringRef kCTFontStyleNameAttribute = (CFStringRef)@"NSFontFaceAttribute";
const CFStringRef kCTFontTraitsAttribute = (CFStringRef)@"NSCTFontTraitsAttribute";
const CFStringRef kCTFontVariationAttribute = (CFStringRef)@"NSCTFontVariationAttribute";
const CFStringRef kCTFontSizeAttribute = (CFStringRef)@"NSFontSizeAttribute";
const CFStringRef kCTFontMatrixAttribute = (CFStringRef)@"NSFontMatrixAttribute";
const CFStringRef kCTFontCascadeListAttribute = (CFStringRef)@"NSCTFontCascadeListAttribute";
const CFStringRef kCTFontCharacterSetAttribute = (CFStringRef)@"NSCTFontCharacterSetAttribute";
const CFStringRef kCTFontFormatAttribute = (CFStringRef)@"NSCTFontFormatAttribute";
const CFStringRef kCTFontLanguagesAttribute = (CFStringRef)@"NSCTFontLanguagesAttribute";
const CFStringRef kCTFontFixedAdvanceAttribute = (CFStringRef)@"NSCTFontFixedAdvanceAttribute";
const CFStringRef kCTFontFeatureSettingsAttribute = (CFStringRef)@"NSCTFontFeatureSettingsAttribute";
const CFStringRef kCTFontOpenTypeFeatureTag = (CFStringRef)@"CTFeatureOpenTypeTag";
const CFStringRef kCTFontOpenTypeFeatureValue = (CFStringRef)@"CTFeatureOpenTypeValue";
const CFStringRef kCTFontCollectionRemoveDuplicatesOption = (CFStringRef)@"NSFontCollectionRemoveDuplicatesOption";

const CFStringRef kCTFontSymbolicTrait = (CFStringRef)@"NSCTFontSymbolicTrait";
const CFStringRef kCTFontWeightTrait = (CFStringRef)@"NSCTFontWeightTrait";
const CFStringRef kCTFontWidthTrait = (CFStringRef)@"NSCTFontProportionTrait";
const CFStringRef kCTFontSlantTrait = (CFStringRef)@"NSCTFontSlantTrait";

const CGFloat kCTFontWeightUltraLight = -0.8, kCTFontWeightThin = -0.6, kCTFontWeightLight = -0.4,
              kCTFontWeightRegular = 0, kCTFontWeightMedium = 0.23, kCTFontWeightSemibold = 0.3,
              kCTFontWeightBold = 0.4, kCTFontWeightHeavy = 0.56, kCTFontWeightBlack = 0.62;

const CFStringRef kCTFontCopyrightNameKey = (CFStringRef)@"Copyright";
const CFStringRef kCTFontFamilyNameKey = (CFStringRef)@"Family";
const CFStringRef kCTFontSubFamilyNameKey = (CFStringRef)@"Subfamily";
const CFStringRef kCTFontStyleNameKey = (CFStringRef)@"Style";
const CFStringRef kCTFontUniqueNameKey = (CFStringRef)@"UniqueID";
const CFStringRef kCTFontFullNameKey = (CFStringRef)@"Full";
const CFStringRef kCTFontVersionNameKey = (CFStringRef)@"Version";
const CFStringRef kCTFontPostScriptNameKey = (CFStringRef)@"PostScript";
const CFStringRef kCTFontTrademarkNameKey = (CFStringRef)@"Trademark";
const CFStringRef kCTFontManufacturerNameKey = (CFStringRef)@"Manufacturer";
const CFStringRef kCTFontDesignerNameKey = (CFStringRef)@"Designer";
const CFStringRef kCTFontDescriptionNameKey = (CFStringRef)@"Description";
const CFStringRef kCTFontVendorURLNameKey = (CFStringRef)@"VendorURL";
const CFStringRef kCTFontDesignerURLNameKey = (CFStringRef)@"DesignerURL";
const CFStringRef kCTFontLicenseNameKey = (CFStringRef)@"License";
const CFStringRef kCTFontLicenseURLNameKey = (CFStringRef)@"LicenseURL";
const CFStringRef kCTFontSampleTextNameKey = (CFStringRef)@"SampleText";
const CFStringRef kCTFontPostScriptCIDNameKey = (CFStringRef)@"CIDFontName";

const CFStringRef kCTFontVariationAxisIdentifierKey = (CFStringRef)@"NSCTVariationAxisIdentifier";
const CFStringRef kCTFontVariationAxisMinimumValueKey = (CFStringRef)@"NSCTVariationAxisMinimumValue";
const CFStringRef kCTFontVariationAxisMaximumValueKey = (CFStringRef)@"NSCTVariationAxisMaximumValue";
const CFStringRef kCTFontVariationAxisDefaultValueKey = (CFStringRef)@"NSCTVariationAxisDefaultValue";
const CFStringRef kCTFontVariationAxisNameKey = (CFStringRef)@"NSCTVariationAxisName";
const CFStringRef kCTFontVariationAxisHiddenKey = (CFStringRef)@"NSCTVariationAxisHidden";

#define FONT ((GFont *)font)

/* ---- weights, widths and slants ---------------------------------------------------------- */

/* Core Text's weights (-1 to 1) for CSS's (100 to 900), as a Mac pairs them. */
static const struct { int css; CGFloat ct; } weight_steps[] = {
    {100, -0.8}, {200, -0.6}, {300, -0.4}, {400, 0}, {500, 0.23}, {600, 0.3}, {700, 0.4}, {800, 0.56}, {900, 0.62},
};
enum { N_WEIGHTS = sizeof weight_steps / sizeof weight_steps[0] };

static CGFloat ct_weight(int css)
{
    if (css <= weight_steps[0].css)
        return weight_steps[0].ct;
    for (int i = 1; i < N_WEIGHTS; i++)
        if (css <= weight_steps[i].css) {
            double t = (double)(css - weight_steps[i - 1].css) / (weight_steps[i].css - weight_steps[i - 1].css);
            return weight_steps[i - 1].ct + t * (weight_steps[i].ct - weight_steps[i - 1].ct);
        }
    return weight_steps[N_WEIGHTS - 1].ct;
}

static int css_weight(CGFloat ct)
{
    if (ct <= weight_steps[0].ct)
        return weight_steps[0].css;
    for (int i = 1; i < N_WEIGHTS; i++)
        if (ct <= weight_steps[i].ct) {
            double t = (ct - weight_steps[i - 1].ct) / (weight_steps[i].ct - weight_steps[i - 1].ct);
            return (int)lround(weight_steps[i - 1].css + t * (weight_steps[i].css - weight_steps[i - 1].css));
        }
    return weight_steps[N_WEIGHTS - 1].css;
}

/* Pango's widths run from 0 (ultra-condensed) to 8 (ultra-expanded), 4 being normal. */
enum { STRETCH_NORMAL = 4 };
/* An italic face's slant trait: small and positive, as a Mac's italic faces report. */
static const CGFloat italic_slant = 0.07;

static NSDictionary *traits_dict(int weight, int style, int stretch, BOOL monospace)
{
    uint32_t symbolic = 0;
    if (weight >= PANGO_WEIGHT_SEMIBOLD)
        symbolic |= kCTFontTraitBold;
    if (style != PANGO_STYLE_NORMAL)
        symbolic |= kCTFontTraitItalic;
    if (monospace)
        symbolic |= kCTFontTraitMonoSpace;
    if (stretch < STRETCH_NORMAL)
        symbolic |= kCTFontTraitCondensed;
    else if (stretch > STRETCH_NORMAL)
        symbolic |= kCTFontTraitExpanded;
    return @{
        (id)kCTFontSymbolicTrait : @(symbolic),
        (id)kCTFontWeightTrait : @(ct_weight(weight)),
        (id)kCTFontWidthTrait : @((stretch - STRETCH_NORMAL) / 4.0),
        (id)kCTFontSlantTrait : @(style != PANGO_STYLE_NORMAL ? italic_slant : 0.0),
    };
}

static NSString *squeeze(NSString *s) { return [s stringByReplacingOccurrencesOfString:@" " withString:@""]; }

static NSString *full_name(NSString *family, NSString *style)
{
    if (!style.length || [style caseInsensitiveCompare:@"Regular"] == NSOrderedSame)
        return family;
    return [NSString stringWithFormat:@"%@ %@", family, style];
}

/* ---- descriptors ------------------------------------------------------------------------- */

@interface GFontDescriptor : NSObject <NSCopying> {
@public
    NSDictionary *attrs;
}
@end

@implementation GFontDescriptor
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (void)dealloc
{
    [attrs release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[GFontDescriptor class]] && [attrs isEqual:((GFontDescriptor *)other)->attrs];
}
- (NSUInteger)hash { return attrs.hash; }
- (NSDictionary *)fontAttributes { return attrs; }
- (NSString *)description { return [NSString stringWithFormat:@"<CTFontDescriptor %p> %@", self, attrs]; }
@end

CTFontDescriptorRef GFontDescriptorMake(NSDictionary *attrs);
NSDictionary *GFontDescriptorAttributes(CTFontDescriptorRef descriptor);
id GFontInstalledFaceAttribute(NSDictionary *attributes, NSString *attribute); /* CoreTextFonts.m */

static CTFontDescriptorRef make_descriptor(NSDictionary *attrs) { return GFontDescriptorMake(attrs); }
CTFontDescriptorRef GFontDescriptorMake(NSDictionary *attrs)
{
    GFontDescriptor *d = [[GFontDescriptor alloc] init];
    d->attrs = [attrs copy] ?: [[NSDictionary alloc] init];
    return (CTFontDescriptorRef)d;
}

/* A descriptor's attributes; AppKit's NSFontDescriptor passed as one answers too. */
static NSDictionary *attrs_of(CTFontDescriptorRef descriptor) { return GFontDescriptorAttributes(descriptor); }
NSDictionary *GFontDescriptorAttributes(CTFontDescriptorRef descriptor)
{
    id d = (id)descriptor;
    if ([d isKindOfClass:[GFontDescriptor class]])
        return ((GFontDescriptor *)d)->attrs;
    if ([d respondsToSelector:@selector(fontAttributes)])
        return [d fontAttributes];
    return nil;
}

CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes)
{
    return make_descriptor((NSDictionary *)attributes);
}

CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size)
{
    NSMutableDictionary *a = [NSMutableDictionary dictionary];
    if (name)
        a[(id)kCTFontNameAttribute] = (NSString *)name;
    if (size > 0)
        a[(id)kCTFontSizeAttribute] = @(size);
    return make_descriptor(a);
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef original, CFDictionaryRef attributes)
{
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary:attrs_of(original) ?: @{}];
    [a addEntriesFromDictionary:(NSDictionary *)attributes ?: @{}];
    return make_descriptor(a);
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithFamily(CTFontDescriptorRef original, CFStringRef family)
{
    if (!family)
        return NULL;
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary:attrs_of(original) ?: @{}];
    [a removeObjectForKey:(id)kCTFontNameAttribute];
    [a removeObjectForKey:(id)kCTFontDisplayNameAttribute];
    a[(id)kCTFontFamilyNameAttribute] = (NSString *)family;
    return make_descriptor(a);
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithSymbolicTraits(CTFontDescriptorRef original,
                                                                 CTFontSymbolicTraits value, CTFontSymbolicTraits mask)
{
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary:attrs_of(original) ?: @{}];
    NSMutableDictionary *t = [NSMutableDictionary dictionaryWithDictionary:a[(id)kCTFontTraitsAttribute] ?: @{}];
    uint32_t s = [t[(id)kCTFontSymbolicTrait] unsignedIntValue];
    s = (s & ~(uint32_t)mask) | ((uint32_t)value & (uint32_t)mask);
    t[(id)kCTFontSymbolicTrait] = @(s);
    /* the weight and slant follow the bold and italic bits */
    if (mask & kCTFontTraitBold)
        t[(id)kCTFontWeightTrait] = @((value & kCTFontTraitBold) ? kCTFontWeightBold : kCTFontWeightRegular);
    if (mask & kCTFontTraitItalic)
        t[(id)kCTFontSlantTrait] = @((value & kCTFontTraitItalic) ? italic_slant : 0.0);
    a[(id)kCTFontTraitsAttribute] = t;
    [a removeObjectForKey:(id)kCTFontNameAttribute];
    [a removeObjectForKey:(id)kCTFontStyleNameAttribute];
    [a removeObjectForKey:(id)kCTFontDisplayNameAttribute];
    return make_descriptor(a);
}

CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor)
{
    return (CFDictionaryRef)[attrs_of(descriptor) copy];
}

CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute)
{
    NSDictionary *a = attrs_of(descriptor);
    id v = attribute ? [a objectForKey:(id)attribute] : nil;
    if (!v && attribute)   /* one that names an installed font answers for it */
        v = GFontInstalledFaceAttribute(a, (NSString *)attribute);
    return (CFTypeRef)[v retain];
}

CFTypeID CTFontDescriptorGetTypeID(void) { return (CFTypeID)[GFontDescriptor class]; }

/* An attribute in the user's language, and which language that was: Ferry's
 * font names come in one language, so the attribute as it is, with no
 * language named (Apple's CTFontDescriptor documentation; freemac 1.266). */
CFTypeRef CTFontDescriptorCopyLocalizedAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute,
                                                 CFStringRef *language)
{
    if (language)
        *language = NULL;
    return CTFontDescriptorCopyAttribute(descriptor, attribute);
}

/* Whether a descriptor names the system's interface font. Chromium declares
 * this private call in its own source; the Mac's interface font names start
 * with a full stop (".AppleSystemUIFont"), as Ferry's stand-in does. */
bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef descriptor)
{
    NSDictionary *a = attrs_of(descriptor);
    id name = a[(id)kCTFontNameAttribute] ?: a[(id)kCTFontFamilyNameAttribute];
    return [name isKindOfClass:[NSString class]] && [name hasPrefix:@"."];
}

/* ---- the installed families and their faces ---------------------------------------------- */

/* Generic names fontconfig answers to, which aren't families of their own. */
static BOOL generic_family(NSString *name)
{
    static NSSet *names;
    if (!names)
        names = [[NSSet setWithArray:@[ @"sans", @"sans-serif", @"serif", @"monospace", @"mono", @"system-ui",
                                        @"cursive", @"fantasy", @"emoji", @"math" ]] retain];
    return [names containsObject:[name lowercaseString]];
}

/* Pango's families by their lower-case names. */
static NSDictionary *families(void)
{
    static NSDictionary *all;
    if (all)
        return all;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    PangoFontFamily **list = NULL;
    int count = 0;
    pango_font_map_list_families(pango_cairo_font_map_get_default(), &list, &count);
    for (int i = 0; i < count; i++) {
        const char *name = pango_font_family_get_name(list[i]);
        if (name && !generic_family(@(name)))
            d[[@(name) lowercaseString]] = [NSValue valueWithPointer:list[i]];
    }
    g_free(list);
    all = [d copy];
    return all;
}

static PangoFontFamily *family_named(NSString *name)
{
    return name ? [families()[[name lowercaseString]] pointerValue] : NULL;
}

/* The installed family a family name stands for: itself, in any case, or a
 * Mac family's stand-in. */
static PangoFontFamily *resolve_family(NSString *name)
{
    PangoFontFamily *f = family_named(name);
    if (f || !name)
        return f;
    NSString *mac = GFontMacFamily(name);
    if (!mac)
        return NULL;
    GFont *font = GFontLoad(mac, PANGO_WEIGHT_NORMAL, PANGO_STYLE_NORMAL, 12, NULL);
    f = family_named(font ? font->family : nil);
    [font release];
    return f;
}

static NSString *family_name(PangoFontFamily *family) { return @(pango_font_family_get_name(family)); }

/* A face of an installed family, as a descriptor's attributes. */
static NSDictionary *face_attrs(PangoFontFamily *family, PangoFontFace *face)
{
    PangoFontDescription *pd = pango_font_face_describe(face);
    int weight = pango_font_description_get_weight(pd);
    int style = pango_font_description_get_style(pd);
    int stretch = pango_font_description_get_stretch(pd);
    pango_font_description_free(pd);
    NSString *fam = family_name(family);
    const char *fn = pango_font_face_get_face_name(face);
    NSString *styleName = fn ? @(fn) : @"Regular";
    return @{
        (id)kCTFontNameAttribute : [NSString stringWithFormat:@"%@-%@", squeeze(fam), squeeze(styleName)],
        (id)kCTFontFamilyNameAttribute : fam,
        (id)kCTFontStyleNameAttribute : styleName,
        (id)kCTFontDisplayNameAttribute : full_name(fam, styleName),
        (id)kCTFontTraitsAttribute : traits_dict(weight, style, stretch, pango_font_family_is_monospace(family)),
    };
}

/* A family's own faces (Pango's synthesized bold and italic left out: those
 * who draw a family make their own). */
static NSArray *family_faces(PangoFontFamily *family)
{
    NSMutableArray *out = [NSMutableArray array];
    PangoFontFace **faces = NULL;
    int count = 0;
    pango_font_family_list_faces(family, &faces, &count);
    for (int i = 0; i < count; i++)
        if (!pango_font_face_is_synthesized(faces[i]))
            [out addObject:face_attrs(family, faces[i])];
    g_free(faces);
    return out;
}

static NSInteger symbolic_of(NSDictionary *traits) { return [traits[(id)kCTFontSymbolicTrait] integerValue]; }

/* How far a face is from what was asked for: its weight, then its slant. */
static double distance(NSDictionary *face, NSDictionary *want)
{
    NSDictionary *ft = face[(id)kCTFontTraitsAttribute];
    double d = 0;
    id w = want[(id)kCTFontWeightTrait];
    NSInteger ws = symbolic_of(want);
    double target = w ? [w doubleValue] : (ws & kCTFontTraitBold) ? kCTFontWeightBold : kCTFontWeightRegular;
    d += fabs([ft[(id)kCTFontWeightTrait] doubleValue] - target);
    BOOL italic = [want[(id)kCTFontSlantTrait] doubleValue] > 0 || (ws & kCTFontTraitItalic);
    if (italic != (([ft[(id)kCTFontSlantTrait] doubleValue]) > 0))
        d += 2;
    d += fabs([ft[(id)kCTFontWidthTrait] doubleValue] - [want[(id)kCTFontWidthTrait] doubleValue]);
    return d;
}

static BOOL same_style(NSString *a, NSString *b)
{
    return [squeeze(a) caseInsensitiveCompare:squeeze(b)] == NSOrderedSame;
}

/* The faces a descriptor matches, best first, or nil. */
static NSArray *matching_faces(NSDictionary *a)
{
    NSString *family = a[(id)kCTFontFamilyNameAttribute];
    NSString *name = a[(id)kCTFontNameAttribute];
    NSString *style = a[(id)kCTFontStyleNameAttribute];
    NSDictionary *want = a[(id)kCTFontTraitsAttribute] ?: @{};
    if (!family && name) {
        /* a font name: the family and face CTFontCreateWithName gives it */
        GFont *f = (GFont *)CTFontCreateWithName((CFStringRef)name, 12, NULL);
        if (!f)
            return nil;
        family = [[f->family copy] autorelease];
        if (!style)
            style = GFontStyleName(f);
        [f release];
    }
    PangoFontFamily *fam = resolve_family(family);
    if (!fam)
        return nil;
    NSArray *faces = family_faces(fam);
    if (style) {
        NSArray *named = [faces filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id f, NSDictionary *b) {
                                    return same_style(f[(id)kCTFontStyleNameAttribute], style);
                                }]];
        if (named.count)
            return named;
    }
    if (!want.count)
        return faces;
    return [faces sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
        double dx = distance(x, want), dy = distance(y, want);
        return dx < dy ? NSOrderedAscending : dx > dy ? NSOrderedDescending : NSOrderedSame;
    }];
}

CFArrayRef CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor, CFSetRef mandatoryAttributes)
{
    (void)mandatoryAttributes;
    NSArray *faces = matching_faces(attrs_of(descriptor));
    if (!faces.count)
        return NULL;
    NSMutableArray *out = [[NSMutableArray alloc] initWithCapacity:faces.count];
    for (NSDictionary *f in faces) {
        CTFontDescriptorRef d = make_descriptor(f);
        [out addObject:(id)d];
        CFRelease(d);
    }
    return (CFArrayRef)out;
}

CTFontDescriptorRef CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef descriptor,
                                                                 CFSetRef mandatoryAttributes)
{
    (void)mandatoryAttributes;
    NSDictionary *a = attrs_of(descriptor);
    NSArray *faces = matching_faces(a);
    if (!faces.count)
        return NULL;
    NSMutableDictionary *best = [NSMutableDictionary dictionaryWithDictionary:faces[0]];
    if (a[(id)kCTFontSizeAttribute])
        best[(id)kCTFontSizeAttribute] = a[(id)kCTFontSizeAttribute];
    return make_descriptor(best);
}

/* ---- fonts from descriptors ---------------------------------------------------------------- */

CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size, const CGAffineTransform *matrix)
{
    NSDictionary *a = attrs_of(descriptor);
    if (size <= 0)
        size = [a[(id)kCTFontSizeAttribute] doubleValue];
    if (size <= 0)
        size = 12;
    NSString *family = a[(id)kCTFontFamilyNameAttribute];
    NSString *name = a[(id)kCTFontNameAttribute];
    if (!family)
        return CTFontCreateWithName((CFStringRef)name, size, matrix);
    PangoFontFamily *fam = resolve_family(family);
    NSString *installed = fam ? family_name(fam) : family;
    int weight = PANGO_WEIGHT_NORMAL, style = PANGO_STYLE_NORMAL;
    NSArray *faces = fam ? matching_faces(a) : nil;
    NSDictionary *t = faces.count ? faces[0][(id)kCTFontTraitsAttribute] : a[(id)kCTFontTraitsAttribute];
    if (t) {
        NSInteger s = symbolic_of(t);
        id w = t[(id)kCTFontWeightTrait];
        weight = w ? css_weight([w doubleValue]) : (s & kCTFontTraitBold) ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL;
        if ((s & kCTFontTraitItalic) || [t[(id)kCTFontSlantTrait] doubleValue] > 0)
            style = PANGO_STYLE_ITALIC;
    }
    return (CTFontRef)GFontLoad(installed, weight, style, size, matrix);
}

/* The installed face a font is: the face of its family with its weight and style. */
static NSDictionary *font_face(GFont *f)
{
    PangoFontFamily *fam = family_named(f->family);
    if (!fam)
        return nil;
    NSDictionary *best = nil;
    double gap = INFINITY;
    for (NSDictionary *face in family_faces(fam)) {
        NSDictionary *t = face[(id)kCTFontTraitsAttribute];
        double d = fabs([t[(id)kCTFontWeightTrait] doubleValue] - ct_weight(f->weight));
        if ((symbolic_of(t) & kCTFontTraitItalic) != (f->style != PANGO_STYLE_NORMAL ? kCTFontTraitItalic : 0))
            d += 2;
        if (d < gap)
            gap = d, best = face;
    }
    return best;
}

CFDictionaryRef CTFontCopyTraits(CTFontRef font)
{
    if (!font)
        return NULL;
    NSDictionary *t = traits_dict(FONT->weight, FONT->style, STRETCH_NORMAL, FONT->monospace);
    return (CFDictionaryRef)[t copy];
}

CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font)
{
    if (!font)
        return NULL;
    NSDictionary *face = font_face(FONT);
    NSString *style = face ? face[(id)kCTFontStyleNameAttribute] : GFontStyleName(FONT);
    NSDictionary *t = [(NSDictionary *)CTFontCopyTraits(font) autorelease];
    return make_descriptor(@{
        (id)kCTFontNameAttribute : [(NSString *)CTFontCopyPostScriptName(font) autorelease],
        (id)kCTFontFamilyNameAttribute : FONT->family,
        (id)kCTFontStyleNameAttribute : style,
        (id)kCTFontDisplayNameAttribute : full_name(FONT->family, style),
        (id)kCTFontSizeAttribute : @(FONT->size),
        (id)kCTFontTraitsAttribute : t,
    });
}

CFTypeRef CTFontCopyAttribute(CTFontRef font, CFStringRef attribute)
{
    CTFontDescriptorRef d = CTFontCopyFontDescriptor(font);
    CFTypeRef v = CTFontDescriptorCopyAttribute(d, attribute);
    if (d)
        CFRelease(d);
    return v;
}

/* ---- names, tables and glyph names ------------------------------------------------------------ */

static hb_face_t *face_of(CTFontRef font) { return font ? hb_font_get_face(FONT->hb) : NULL; }

/* A name from a font file's name table, in English where it has one. */
static NSString *table_name(hb_face_t *face, unsigned id)
{
    if (!face)
        return nil;
    unsigned size = 0;
    unsigned len = hb_ot_name_get_utf8(face, id, hb_language_from_string("en", -1), &size, NULL);
    if (!len)
        return nil;
    char *buf = malloc(len + 1);
    size = len + 1;
    hb_ot_name_get_utf8(face, id, hb_language_from_string("en", -1), &size, buf);
    NSString *s = [NSString stringWithUTF8String:buf];
    free(buf);
    return s;
}

/* The OpenType name table's numbers for Core Text's name keys. */
static int name_id(NSString *key)
{
    static const struct { const char *key; int id; } ids[] = {
        {"Copyright", 0},    {"UniqueID", 3},      {"Version", 5},      {"Trademark", 7},
        {"Manufacturer", 8}, {"Designer", 9},      {"Description", 10}, {"VendorURL", 11},
        {"DesignerURL", 12}, {"License", 13},      {"LicenseURL", 14},  {"SampleText", 19},
        {"CIDFontName", 20},
    };
    for (size_t i = 0; i < sizeof ids / sizeof ids[0]; i++)
        if ([key isEqualToString:@(ids[i].key)])
            return ids[i].id;
    return -1;
}

CFStringRef CTFontCopyName(CTFontRef font, CFStringRef nameKey)
{
    if (!font || !nameKey)
        return NULL;
    NSString *key = (NSString *)nameKey;
    if ([key isEqualToString:(id)kCTFontFamilyNameKey])
        return CTFontCopyFamilyName(font);
    if ([key isEqualToString:(id)kCTFontPostScriptNameKey])
        return CTFontCopyPostScriptName(font);
    if ([key isEqualToString:(id)kCTFontFullNameKey])
        return CTFontCopyFullName(font);
    if ([key isEqualToString:(id)kCTFontStyleNameKey] || [key isEqualToString:(id)kCTFontSubFamilyNameKey]) {
        NSDictionary *face = font_face(FONT);
        return (CFStringRef)[(face ? face[(id)kCTFontStyleNameAttribute] : GFontStyleName(FONT)) copy];
    }
    int id = name_id(key);
    NSString *s = id >= 0 ? table_name(face_of(font), (unsigned)id) : nil;
    if (!s && id == 3) /* a font always has a unique name: its full name serves */
        return CTFontCopyFullName(font);
    return (CFStringRef)[s copy];
}

CFStringRef CTFontCopyLocalizedName(CTFontRef font, CFStringRef nameKey, CFStringRef *actualLanguage)
{
    CFStringRef s = CTFontCopyName(font, nameKey);
    if (actualLanguage)
        *actualLanguage = s ? (CFStringRef)[@"en" retain] : NULL;
    return s;
}

static CFDataRef copy_table(hb_face_t *face, uint32_t tag)
{
    if (!face)
        return NULL;
    hb_blob_t *blob = hb_face_reference_table(face, tag);
    unsigned len = 0;
    const char *bytes = hb_blob_get_data(blob, &len);
    CFDataRef data = len ? (CFDataRef)[[NSData alloc] initWithBytes:bytes length:len] : NULL;
    hb_blob_destroy(blob);
    return data;
}

CFDataRef CTFontCopyTable(CTFontRef font, CTFontTableTag table, CTFontTableOptions options)
{
    (void)options;
    return copy_table(face_of(font), table);
}

CFArrayRef CTFontCopyAvailableTables(CTFontRef font, CTFontTableOptions options)
{
    (void)options;
    hb_face_t *face = face_of(font);
    if (!face)
        return NULL;
    uint32_t tags[256];
    unsigned count = 256;
    hb_face_get_table_tags(face, 0, &count, tags);
    NSMutableArray *out = [[NSMutableArray alloc] initWithCapacity:count];
    for (unsigned i = 0; i < count; i++)
        [out addObject:@(tags[i])];
    return (CFArrayRef)out;
}

CFArrayRef CTFontCopyVariationAxes(CTFontRef font)
{
    (void)font;
    return NULL;
}
/* The same, as Chromium asks for it in a private call it declares itself. */
CFArrayRef CTFontCopyVariationAxesInternal(CTFontRef font) { return CTFontCopyVariationAxes(font); }

CFDictionaryRef CTFontCopyVariation(CTFontRef font)
{
    (void)font;
    return NULL;
}

CGGlyph CTFontGetGlyphWithName(CTFontRef font, CFStringRef glyphName)
{
    hb_codepoint_t g = 0;
    const char *name = glyphName ? ((NSString *)glyphName).UTF8String : NULL;
    if (!font || !name || !hb_font_get_glyph_from_name(FONT->hb, name, -1, &g))
        return 0;
    return (CGGlyph)g;
}

/* A glyph by its name in the font (Apple's CGFont documentation). */
CGGlyph CGFontGetGlyphWithGlyphName(CGFontRef cgfont, CFStringRef name)
{
    CTFontRef f = CTFontCreateWithGraphicsFont(cgfont, 12, NULL, NULL);
    CGGlyph g = f ? CTFontGetGlyphWithName(f, name) : 0;
    if (f)
        CFRelease(f);
    return g;
}

CFStringRef CTFontCopyNameForGlyph(CTFontRef font, CGGlyph glyph)
{
    char name[128];
    if (!font || !hb_font_get_glyph_name(FONT->hb, glyph, name, sizeof name) || !*name)
        return NULL;
    return (CFStringRef)[[NSString alloc] initWithUTF8String:name];
}

/* Families to fall back to for characters a font lacks, those installed of
 * them: wide-coverage families, then CJK, emoji and symbols. */
CFArrayRef CTFontCopyDefaultCascadeListForLanguages(CTFontRef font, CFArrayRef languagePrefList)
{
    (void)languagePrefList;
    static const char *const fallbacks[] = {
        "Noto Sans",         "DejaVu Sans",     "Liberation Sans",       "FreeSans",          "Noto Sans CJK SC",
        "Noto Sans CJK JP",  "Noto Sans CJK KR", "Noto Sans CJK TC",     "WenQuanYi Zen Hei", "IPAGothic",
        "Noto Sans Arabic",  "Noto Sans Hebrew", "Noto Sans Devanagari", "Noto Sans Thai",    "Loma",
        "Noto Color Emoji",  "Noto Sans Symbols", "Noto Sans Symbols 2", "OpenSymbol",        "Unifont",
    };
    NSString *own = font ? FONT->family : nil;
    NSMutableArray *out = [[NSMutableArray alloc] init];
    for (size_t i = 0; i < sizeof fallbacks / sizeof fallbacks[0]; i++) {
        PangoFontFamily *fam = family_named(@(fallbacks[i]));
        if (!fam)
            continue;
        NSString *name = family_name(fam);
        if (own && [name caseInsensitiveCompare:own] == NSOrderedSame)
            continue;
        CTFontDescriptorRef d = make_descriptor(@{(id)kCTFontFamilyNameAttribute : name});
        [out addObject:(id)d];
        CFRelease(d);
    }
    return (CFArrayRef)out;
}

/* ---- the font manager ---------------------------------------------------------------------- */

/* The installed families, and the Mac families that stand-ins answer for,
 * as the available fonts list them: Chromium looks a CSS family up in this
 * list, and draws nothing when its last resort, Times, isn't there. */
CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSValue *v in families().allValues)
        [names addObject:family_name(v.pointerValue)];
    for (NSString *mac in GFontStandInFamilyNames())
        if (!family_named(mac))
            [names addObject:mac];
    return (CFArrayRef)[[names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] copy];
}

CFArrayRef CTFontManagerCopyAvailablePostScriptNames(void)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSValue *v in families().allValues)
        for (NSDictionary *face in family_faces(v.pointerValue))
            [names addObject:face[(id)kCTFontNameAttribute]];
    return (CFArrayRef)[[names sortedArrayUsingSelector:@selector(compare:)] copy];
}

/* A font file's face as a descriptor's attributes, from its own tables:
 * names 16 and 17 (or 1 and 2) for the family and style, 6 for the
 * PostScript name; OS/2's weight class and selection bits; post's fixed
 * pitch flag. */
static NSDictionary *file_face_attrs(hb_face_t *face)
{
    NSString *family = table_name(face, 16) ?: table_name(face, 1);
    if (!family)
        return nil;
    NSString *style = table_name(face, 17) ?: table_name(face, 2) ?: @"Regular";
    NSString *ps = table_name(face, 6) ?: [NSString stringWithFormat:@"%@-%@", squeeze(family), squeeze(style)];
    int weight = PANGO_WEIGHT_NORMAL, slant = PANGO_STYLE_NORMAL, stretch = STRETCH_NORMAL;
    BOOL mono = NO;
    NSData *os2 = [(NSData *)copy_table(face, HB_TAG('O', 'S', '/', '2')) autorelease];
    if (os2.length >= 64) {
        const unsigned char *b = os2.bytes;
        weight = b[4] << 8 | b[5];
        int width = b[6] << 8 | b[7]; /* 1 to 9, 5 normal */
        if (width >= 1 && width <= 9)
            stretch = width - 1;
        if (b[63] & 1) /* fsSelection's italic bit */
            slant = PANGO_STYLE_ITALIC;
    }
    NSData *post = [(NSData *)copy_table(face, HB_TAG('p', 'o', 's', 't')) autorelease];
    if (post.length >= 16) {
        const unsigned char *b = post.bytes;
        mono = (b[12] | b[13] | b[14] | b[15]) != 0;
    }
    return @{
        (id)kCTFontNameAttribute : ps,
        (id)kCTFontFamilyNameAttribute : family,
        (id)kCTFontStyleNameAttribute : style,
        (id)kCTFontDisplayNameAttribute : table_name(face, 4) ?: full_name(family, style),
        (id)kCTFontTraitsAttribute : traits_dict(weight, slant, stretch, mono),
    };
}

static NSArray *descriptors_from_data(NSData *data, NSURL *url)
{
    if (!data.length)
        return nil;
    hb_blob_t *blob = hb_blob_create(data.bytes, (unsigned)data.length, HB_MEMORY_MODE_READONLY, NULL, NULL);
    unsigned n = hb_face_count(blob);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) {
        hb_face_t *face = hb_face_create(blob, i);
        NSDictionary *a = file_face_attrs(face);
        hb_face_destroy(face);
        if (!a)
            continue;
        if (url) {
            NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:a];
            m[(id)kCTFontURLAttribute] = url;
            a = m;
        }
        CTFontDescriptorRef d = make_descriptor(a);
        [out addObject:(id)d];
        CFRelease(d);
    }
    hb_blob_destroy(blob);
    return out.count ? out : nil;
}

CFArrayRef CTFontManagerCreateFontDescriptorsFromData(CFDataRef data)
{
    return (CFArrayRef)[descriptors_from_data((NSData *)data, nil) copy];
}

CTFontDescriptorRef CTFontManagerCreateFontDescriptorFromData(CFDataRef data)
{
    NSArray *all = descriptors_from_data((NSData *)data, nil);
    return all.count ? (CTFontDescriptorRef)[all[0] retain] : NULL;
}

/* Matching finds installed fonts only, so there is nothing to turn on or off. */
void CTFontManagerEnableFontDescriptors(CFArrayRef descriptors, bool enable)
{
    (void)descriptors;
    (void)enable;
}

/* ---- CGFont ------------------------------------------------------------------------------------ */

@interface GCGFont : NSObject {
@public
    hb_blob_t *blob;   /* a font file's data, or NULL for a Core Text font's */
    hb_face_t *face;
    GFont *font;       /* the Core Text font it came from, if it did */
    NSDictionary *attrs;
}
@end

@implementation GCGFont
- (void)dealloc
{
    if (face)
        hb_face_destroy(face);
    if (blob)
        hb_blob_destroy(blob);
    [font release];
    [attrs release];
    [super dealloc];
}
@end

#define CGF ((GCGFont *)cgfont)

CGFontRef CGFontCreateWithDataProvider(CGDataProviderRef provider)
{
    NSData *data = [(NSData *)CGDataProviderCopyData(provider) autorelease];
    if (!data.length)
        return NULL;
    GCGFont *g = [[GCGFont alloc] init];
    g->blob = hb_blob_create(data.bytes, (unsigned)data.length, HB_MEMORY_MODE_DUPLICATE, NULL, NULL);
    g->face = hb_face_create(g->blob, 0);
    g->attrs = [file_face_attrs(g->face) copy];
    if (!g->attrs) {
        [g release];
        return NULL;
    }
    return (CGFontRef)g;
}

CGFontRef CTFontCopyGraphicsFont(CTFontRef font, CTFontDescriptorRef *attributes)
{
    if (attributes)
        *attributes = NULL;
    if (!font)
        return NULL;
    GCGFont *g = [[GCGFont alloc] init];
    g->font = [FONT retain];
    g->face = hb_face_reference(hb_font_get_face(FONT->hb));
    CTFontDescriptorRef d = CTFontCopyFontDescriptor(font);
    g->attrs = [attrs_of(d) copy];
    CFRelease(d);
    return (CGFontRef)g;
}

CGFontRef CGFontCreateWithFontName(CFStringRef name)
{
    CTFontRef f = CTFontCreateWithName(name, 12, NULL);
    CGFontRef g = CTFontCopyGraphicsFont(f, NULL);
    if (f)
        CFRelease(f);
    return g;
}

CTFontRef CTFontCreateWithGraphicsFont(CGFontRef cgfont, CGFloat size, const CGAffineTransform *matrix,
                                       CTFontDescriptorRef attributes)
{
    if (!cgfont)
        return NULL;
    if (size <= 0)
        size = 12;
    if (CGF->font)
        return (CTFontRef)GFontLoad(CGF->font->family, CGF->font->weight, CGF->font->style, size, matrix);
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary:CGF->attrs];
    [a addEntriesFromDictionary:attrs_of(attributes) ?: @{}];
    [a removeObjectForKey:(id)kCTFontStyleNameAttribute]; /* the file's style names needn't be the installed ones */
    CTFontDescriptorRef d = make_descriptor(a);
    CTFontRef f = CTFontCreateWithFontDescriptor(d, size, matrix);
    CFRelease(d);
    return f;
}

CGFontRef CGFontRetain(CGFontRef cgfont) { return (CGFontRef)[(id)cgfont retain]; }
void CGFontRelease(CGFontRef cgfont) { [(id)cgfont release]; }
CFStringRef CGFontCopyFullName(CGFontRef cgfont)
{
    return cgfont ? (CFStringRef)[CGF->attrs[(id)kCTFontDisplayNameAttribute] copy] : NULL;
}
CFStringRef CGFontCopyPostScriptName(CGFontRef cgfont)
{
    return cgfont ? (CFStringRef)[CGF->attrs[(id)kCTFontNameAttribute] copy] : NULL;
}
int CGFontGetUnitsPerEm(CGFontRef cgfont) { return cgfont ? (int)hb_face_get_upem(CGF->face) : 0; }
size_t CGFontGetNumberOfGlyphs(CGFontRef cgfont) { return cgfont ? hb_face_get_glyph_count(CGF->face) : 0; }
CFDataRef CGFontCopyTableForTag(CGFontRef cgfont, uint32_t tag) { return cgfont ? copy_table(CGF->face, tag) : NULL; }
CFTypeID CGFontGetTypeID(void) { return (CFTypeID)[GCGFont class]; }
