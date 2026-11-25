/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSFontDescriptor (freemac 1.222, Ferry 0.46.0): a font's attributes as
 * a dictionary, written from Apple's public documentation. A descriptor
 * becomes a font through NSFontManager, which knows the installed families
 * and their faces, so a family with bold and italic traits finds the
 * family's bold italic face, and a Mac family that isn't installed finds its
 * stand-in. A font's own descriptor holds its name and size, and answers its
 * traits from the font. Also NSMutableAttributedString's
 * applyFontTraits:range:. */
#import "AInternal.h"
#include <math.h>

NSString *const NSFontFamilyAttribute = @"NSFontFamilyAttribute";
NSString *const NSFontNameAttribute = @"NSFontNameAttribute";
NSString *const NSFontFaceAttribute = @"NSFontFaceAttribute";
NSString *const NSFontSizeAttribute = @"NSFontSizeAttribute";
NSString *const NSFontVisibleNameAttribute = @"NSFontVisibleNameAttribute";
NSString *const NSFontMatrixAttribute = @"NSFontMatrixAttribute";
NSString *const NSFontVariationAttribute = @"NSCTFontVariationAttribute";
NSString *const NSFontCharacterSetAttribute = @"NSCTFontCharacterSetAttribute";
NSString *const NSFontCascadeListAttribute = @"NSCTFontCascadeListAttribute";
NSString *const NSFontTraitsAttribute = @"NSCTFontTraitsAttribute";
NSString *const NSFontFixedAdvanceAttribute = @"NSCTFontFixedAdvanceAttribute";
NSString *const NSFontFeatureSettingsAttribute = @"NSCTFontFeatureSettingsAttribute";
NSString *const NSFontSymbolicTrait = @"NSCTFontSymbolicTrait";
NSString *const NSFontWeightTrait = @"NSCTFontWeightTrait";
NSString *const NSFontWidthTrait = @"NSCTFontProportionTrait";
NSString *const NSFontSlantTrait = @"NSCTFontSlantTrait";
NSString *const NSFontVariationAxisIdentifierKey = @"NSCTVariationAxisIdentifier";
NSString *const NSFontVariationAxisMinimumValueKey = @"NSCTVariationAxisMinimumValue";
NSString *const NSFontVariationAxisMaximumValueKey = @"NSCTVariationAxisMaximumValue";
NSString *const NSFontVariationAxisDefaultValueKey = @"NSCTVariationAxisDefaultValue";
NSString *const NSFontVariationAxisNameKey = @"NSCTVariationAxisName";
NSString *const NSFontFeatureTypeIdentifierKey = @"CTFeatureTypeIdentifier";
NSString *const NSFontFeatureSelectorIdentifierKey = @"CTFeatureSelectorIdentifier";
NSString *const NSFontDescriptorSystemDesignDefault = @"NSCTFontUIFontDesignDefault";
NSString *const NSFontDescriptorSystemDesignSerif = @"NSCTFontUIFontDesignSerif";
NSString *const NSFontDescriptorSystemDesignMonospaced = @"NSCTFontUIFontDesignMonospaced";
NSString *const NSFontDescriptorSystemDesignRounded = @"NSCTFontUIFontDesignRounded";
const NSFontWidth NSFontWidthCompressed = -0.3, NSFontWidthCondensed = -0.2, NSFontWidthStandard = 0,
                  NSFontWidthExpanded = 0.2;

/* NSFontWeight (-1 to 1) as NSFontManager's weights (0 to 15) */
static NSInteger manager_weight(CGFloat w)
{
    static const struct {
        CGFloat weight;
        NSInteger manager;
    } steps[] = {{-0.8, 2}, {-0.6, 3}, {-0.4, 4}, {0, 5}, {0.23, 6}, {0.3, 8}, {0.4, 9}, {0.56, 10}, {0.62, 11}};
    NSInteger best = 5;
    CGFloat gap = INFINITY;
    for (size_t i = 0; i < sizeof steps / sizeof steps[0]; i++)
        if (fabs(steps[i].weight - w) < gap)
            gap = fabs(steps[i].weight - w), best = steps[i].manager;
    return best;
}

static CGFloat number_of(id v) { return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0; }

@implementation NSFontDescriptor {
    NSDictionary *_attributes;
}

+ (BOOL)supportsSecureCoding { return YES; }

+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(NSDictionary *)attributes
{
    return [[[self alloc] initWithFontAttributes:attributes] autorelease];
}

+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)name size:(CGFloat)size
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (name)
        d[NSFontNameAttribute] = name;
    if (size > 0)
        d[NSFontSizeAttribute] = @(size);
    return [self fontDescriptorWithFontAttributes:d];
}

+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)name matrix:(NSAffineTransform *)matrix
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (name)
        d[NSFontNameAttribute] = name;
    if (matrix)
        d[NSFontMatrixAttribute] = matrix;
    return [self fontDescriptorWithFontAttributes:d];
}

- (instancetype)init { return [self initWithFontAttributes:nil]; }

- (instancetype)initWithFontAttributes:(NSDictionary *)attributes
{
    if ((self = [super init]))
        _attributes = [attributes ?: @{} copy];
    return self;
}

- (void)dealloc
{
    [_attributes release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[NSFontDescriptor class]] &&
                             [_attributes isEqualToDictionary:[other fontAttributes]]);
}
- (NSUInteger)hash { return [_attributes hash]; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSDictionary *d = [coder decodeObjectForKey:@"NSFontDescriptorAttributes"];
    return [self initWithFontAttributes:[d isKindOfClass:[NSDictionary class]] ? d : nil];
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_attributes forKey:@"NSFontDescriptorAttributes"]; }

- (NSDictionary *)fontAttributes { return _attributes; }
/* A descriptor naming a font answers the font's family, face and visible
 * name too, as a font's own descriptor does on a Mac. */
- (id)objectForKey:(NSString *)attribute
{
    id v = _attributes[attribute];
    if (v || !_attributes[NSFontNameAttribute])
        return v;
    BOOL family = [attribute isEqualToString:NSFontFamilyAttribute],
         face = [attribute isEqualToString:NSFontFaceAttribute],
         visible = [attribute isEqualToString:NSFontVisibleNameAttribute];
    if (!family && !face && !visible)
        return nil;
    NSFont *f = [NSFont fontWithName:_attributes[NSFontNameAttribute] size:12];
    if (family || visible)
        return family ? [f familyName] : [f displayName];
    for (NSArray *m in [[NSFontManager sharedFontManager] availableMembersOfFontFamily:[f familyName]])
        if ([m[0] isEqualToString:[f fontName]])
            return m[1];
    return nil;
}
- (NSString *)postscriptName { return _attributes[NSFontNameAttribute]; }
- (CGFloat)pointSize { return number_of(_attributes[NSFontSizeAttribute]); }
- (NSAffineTransform *)matrix { return _attributes[NSFontMatrixAttribute]; }
- (BOOL)requiresFontAssetRequest { return NO; }

/* the traits it asks for, or, naming a font, the font's */
- (NSFontDescriptorSymbolicTraits)symbolicTraits
{
    NSDictionary *traits = _attributes[NSFontTraitsAttribute];
    if (traits[NSFontSymbolicTrait])
        return (NSFontDescriptorSymbolicTraits)[traits[NSFontSymbolicTrait] unsignedIntValue];
    if (_attributes[NSFontNameAttribute]) {
        NSFont *f = [NSFont fontWithName:_attributes[NSFontNameAttribute] size:12];
        if (f)
            return (NSFontDescriptorSymbolicTraits)CTFontGetSymbolicTraits((CTFontRef)f);
    }
    return 0;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ %@", [super description], _attributes]; }

- (NSFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary *)attributes
{
    NSMutableDictionary *d = [[_attributes mutableCopy] autorelease];
    [d addEntriesFromDictionary:attributes ?: @{}];
    return [NSFontDescriptor fontDescriptorWithFontAttributes:d];
}

/* With a family rather than a name, so that the traits choose the face. */
- (NSMutableDictionary *)_byFamily
{
    NSMutableDictionary *d = [[_attributes mutableCopy] autorelease];
    if (d[NSFontNameAttribute] && !d[NSFontFamilyAttribute]) {
        NSFont *f = [NSFont fontWithName:d[NSFontNameAttribute] size:12];
        if ([f familyName])
            d[NSFontFamilyAttribute] = [f familyName];
    }
    if (d[NSFontFamilyAttribute]) {
        [d removeObjectForKey:NSFontNameAttribute];
        [d removeObjectForKey:NSFontFaceAttribute];
    }
    return d;
}

- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSFontDescriptorSymbolicTraits)symbolicTraits
{
    NSMutableDictionary *d = [self _byFamily];
    NSMutableDictionary *traits = [[d[NSFontTraitsAttribute] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
    traits[NSFontSymbolicTrait] = @(symbolicTraits);
    /* the traits take the place of a weight that says otherwise */
    [traits removeObjectForKey:NSFontWeightTrait];
    d[NSFontTraitsAttribute] = traits;
    return [NSFontDescriptor fontDescriptorWithFontAttributes:d];
}

- (NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)size
{
    return [self fontDescriptorByAddingAttributes:@{NSFontSizeAttribute : @(size)}];
}

- (NSFontDescriptor *)fontDescriptorWithMatrix:(NSAffineTransform *)matrix
{
    return matrix ? [self fontDescriptorByAddingAttributes:@{NSFontMatrixAttribute : matrix}] : self;
}

- (NSFontDescriptor *)fontDescriptorWithFace:(NSString *)face
{
    NSMutableDictionary *d = [self _byFamily];
    if (face)
        d[NSFontFaceAttribute] = face;
    return [NSFontDescriptor fontDescriptorWithFontAttributes:d];
}

- (NSFontDescriptor *)fontDescriptorWithFamily:(NSString *)family
{
    NSMutableDictionary *d = [[_attributes mutableCopy] autorelease];
    /* a named face's bold and italic go with it to the other family */
    if (d[NSFontNameAttribute] && !d[NSFontTraitsAttribute]) {
        NSFontDescriptorSymbolicTraits t =
            [self symbolicTraits] & (NSFontDescriptorTraitBold | NSFontDescriptorTraitItalic);
        if (t)
            d[NSFontTraitsAttribute] = @{NSFontSymbolicTrait : @(t)};
    }
    [d removeObjectForKey:NSFontNameAttribute];
    [d removeObjectForKey:NSFontFaceAttribute];
    if (family)
        d[NSFontFamilyAttribute] = family;
    return [NSFontDescriptor fontDescriptorWithFontAttributes:d];
}

/* the system font's designs, as the families that stand in for them here */
- (NSFontDescriptor *)fontDescriptorWithDesign:(NSString *)design
{
    if ([design isEqualToString:NSFontDescriptorSystemDesignMonospaced])
        return [self fontDescriptorWithFamily:@"Menlo"];
    if ([design isEqualToString:NSFontDescriptorSystemDesignSerif])
        return [self fontDescriptorWithFamily:@"Times"];
    if ([design isEqualToString:NSFontDescriptorSystemDesignDefault] ||
        [design isEqualToString:NSFontDescriptorSystemDesignRounded])
        return self;
    return nil;
}

/* what a font made from it keeps of what was asked for */
static BOOL keeps(NSFontDescriptor *asked, NSFontDescriptor *got, NSSet *keys)
{
    for (NSString *key in keys) {
        id want = [asked objectForKey:key];
        if (!want)
            continue;
        if ([key isEqualToString:NSFontTraitsAttribute]) {
            NSFontDescriptorSymbolicTraits t = [asked symbolicTraits] & 0xFFFF;
            if (([got symbolicTraits] & t) != t)
                return NO;
        } else if ([key isEqualToString:NSFontSizeAttribute]) {
            continue;
        } else {
            id have = [got objectForKey:key];
            if (![have isKindOfClass:[NSString class]] || [have caseInsensitiveCompare:want] != NSOrderedSame)
                return NO;
        }
    }
    return YES;
}

- (NSFontDescriptor *)matchingFontDescriptorWithMandatoryKeys:(NSSet *)keys
{
    NSFont *f = [NSFont fontWithDescriptor:self size:[self pointSize]];
    NSFontDescriptor *got = [f fontDescriptor];
    return got && keeps(self, got, keys) ? got : nil;
}

- (NSArray *)matchingFontDescriptorsWithMandatoryKeys:(NSSet *)keys
{
    NSMutableArray *out = [NSMutableArray array];
    NSString *family = _attributes[NSFontFamilyAttribute];
    CGFloat size = [self pointSize] > 0 ? [self pointSize] : 12;
    if (family) {
        /* each face of the family that keeps what was asked */
        for (NSArray *member in [[NSFontManager sharedFontManager] availableMembersOfFontFamily:family]) {
            NSFont *f = [NSFont fontWithName:member[0] size:size];
            NSFontDescriptor *got = [f fontDescriptor];
            if (got && keeps(self, got, keys) && ![out containsObject:got])
                [out addObject:got];
        }
    }
    if (![out count]) {
        NSFontDescriptor *one = [self matchingFontDescriptorWithMandatoryKeys:keys];
        if (one)
            [out addObject:one];
    }
    return out;
}
@end

@implementation NSFont (NSFontDescriptor)

+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor size:(CGFloat)size
{
    if (!descriptor)
        return nil;
    if (size <= 0)
        size = [descriptor pointSize] > 0 ? [descriptor pointSize] : 12;
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSDictionary *a = [descriptor fontAttributes], *traits = a[NSFontTraitsAttribute];
    NSFontDescriptorSymbolicTraits sym = (NSFontDescriptorSymbolicTraits)[traits[NSFontSymbolicTrait] unsignedIntValue];
    NSFontTraitMask mask = 0;
    if (sym & NSFontDescriptorTraitBold)
        mask |= NSBoldFontMask;
    if (sym & NSFontDescriptorTraitItalic)
        mask |= NSItalicFontMask;
    if (sym & NSFontDescriptorTraitMonoSpace)
        mask |= NSFixedPitchFontMask;
    if (sym & NSFontDescriptorTraitCondensed)
        mask |= NSCondensedFontMask;
    if (sym & NSFontDescriptorTraitExpanded)
        mask |= NSExpandedFontMask;
    id weight = traits[NSFontWeightTrait];
    NSInteger w = weight ? manager_weight(number_of(weight)) : 5;

    NSFont *f = nil;
    if (a[NSFontNameAttribute]) {
        f = [NSFont fontWithName:a[NSFontNameAttribute] size:size];
    } else if (a[NSFontFamilyAttribute]) {
        f = [fm fontWithFamily:a[NSFontFamilyAttribute] traits:mask & (NSBoldFontMask | NSItalicFontMask) weight:w
                          size:size];
        if (!f)
            f = [NSFont fontWithName:a[NSFontFamilyAttribute] size:size];
        if (f && a[NSFontFaceAttribute])
            f = [fm convertFont:f toFace:a[NSFontFaceAttribute]];
    } else if (a[NSFontVisibleNameAttribute]) {
        f = [NSFont fontWithName:a[NSFontVisibleNameAttribute] size:size];
    }
    if (!f)
        f = weight ? [NSFont systemFontOfSize:size weight:number_of(weight)] : [NSFont systemFontOfSize:size];
    /* a weight on a named font: the family's face of that weight */
    if (weight && a[NSFontNameAttribute]) {
        NSFont *heavier = [fm fontWithFamily:[f familyName] traits:[fm traitsOfFont:f] & NSItalicFontMask
                                      weight:w size:size];
        if (heavier)
            f = heavier;
    }
    if (mask)
        f = [fm convertFont:f toHaveTrait:mask];
    return f;
}

+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor textTransform:(NSAffineTransform *)textTransform
{
    NSAffineTransformStruct m = textTransform ? [textTransform transformStruct] : (NSAffineTransformStruct){0};
    CGFloat size = textTransform ? hypot(m.m21, m.m22) : 0;
    return [self fontWithDescriptor:descriptor size:size];
}

- (NSFontDescriptor *)fontDescriptor
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([self fontName])
        d[NSFontNameAttribute] = [self fontName];
    d[NSFontSizeAttribute] = @([self pointSize]);
    return [NSFontDescriptor fontDescriptorWithFontAttributes:d];
}

- (NSFont *)fontWithSize:(CGFloat)newSize
{
    return [[NSFontManager sharedFontManager] convertFont:self toSize:newSize];
}
@end

@implementation NSMutableAttributedString (NSFontTraits)
- (void)applyFontTraits:(NSFontTraitMask)traitMask range:(NSRange)range
{
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSUInteger end = NSMaxRange(range), at = range.location;
    if (end > [self length])
        end = [self length];
    [self beginEditing];
    while (at < end) {
        NSRange run;
        NSFont *font = [self attribute:NSFontAttributeName atIndex:at longestEffectiveRange:&run
                               inRange:NSMakeRange(at, end - at)];
        /* text without a font is in the default one, Helvetica 12 */
        if (!font)
            font = [NSFont fontWithName:@"Helvetica" size:12];
        NSFont *changed = [fm convertFont:font toHaveTrait:traitMask];
        if (changed && changed != font)
            [self addAttribute:NSFontAttributeName value:changed range:run];
        at = NSMaxRange(run);
    }
    [self endEditing];
}
@end
