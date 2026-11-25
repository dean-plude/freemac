/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: font descriptors and font traits (freemac 1.222, Ferry
 * 0.46.0), written from Apple's public documentation. A descriptor is a
 * dictionary of a font's attributes (family, face, name, size, traits);
 * NSFont makes the nearest installed font from one, and every font answers
 * its own. Also NSMutableAttributedString's applyFontTraits:range:, as
 * MacDown's Markdown highlighter uses it. Included from AppKit.h. */
#import <Foundation/Foundation.h>

typedef NSString *NSFontDescriptorAttributeName;
typedef NSString *NSFontDescriptorTraitKey;
typedef NSString *NSFontDescriptorVariationKey;
typedef NSString *NSFontDescriptorFeatureKey;
typedef NSString *NSFontDescriptorSystemDesign;
typedef CGFloat NSFontWidth;

typedef uint32_t NSFontSymbolicTraits;
typedef NS_OPTIONS(uint32_t, NSFontDescriptorSymbolicTraits) {
    NSFontDescriptorTraitItalic = 1u << 0,
    NSFontDescriptorTraitBold = 1u << 1,
    NSFontDescriptorTraitExpanded = 1u << 5,
    NSFontDescriptorTraitCondensed = 1u << 6,
    NSFontDescriptorTraitMonoSpace = 1u << 10,
    NSFontDescriptorTraitVertical = 1u << 11,
    NSFontDescriptorTraitUIOptimized = 1u << 12,
    NSFontDescriptorTraitTightLeading = 1u << 15,
    NSFontDescriptorTraitLooseLeading = 1u << 16,
    NSFontDescriptorTraitEmphasized = NSFontDescriptorTraitBold,
    NSFontDescriptorClassMask = 0xF0000000,
    NSFontDescriptorClassUnknown = 0u << 28,
    NSFontDescriptorClassOldStyleSerifs = 1u << 28,
    NSFontDescriptorClassTransitionalSerifs = 2u << 28,
    NSFontDescriptorClassModernSerifs = 3u << 28,
    NSFontDescriptorClassClarendonSerifs = 4u << 28,
    NSFontDescriptorClassSlabSerifs = 5u << 28,
    NSFontDescriptorClassFreeformSerifs = 7u << 28,
    NSFontDescriptorClassSansSerif = 8u << 28,
    NSFontDescriptorClassOrnamentals = 9u << 28,
    NSFontDescriptorClassScripts = 10u << 28,
    NSFontDescriptorClassSymbolic = 12u << 28,
};
/* the older names */
enum {
    NSFontUnknownClass = 0u << 28, NSFontOldStyleSerifsClass = 1u << 28, NSFontTransitionalSerifsClass = 2u << 28,
    NSFontModernSerifsClass = 3u << 28, NSFontClarendonSerifsClass = 4u << 28, NSFontSlabSerifsClass = 5u << 28,
    NSFontFreeformSerifsClass = 7u << 28, NSFontSansSerifClass = 8u << 28, NSFontOrnamentalsClass = 9u << 28,
    NSFontScriptsClass = 10u << 28, NSFontSymbolicClass = 12u << 28,
};
enum { NSFontFamilyClassMask = 0xF0000000 };
enum {
    NSFontItalicTrait = 1u << 0, NSFontBoldTrait = 1u << 1, NSFontExpandedTrait = 1u << 5,
    NSFontCondensedTrait = 1u << 6, NSFontMonoSpaceTrait = 1u << 10, NSFontVerticalTrait = 1u << 11,
    NSFontUIOptimizedTrait = 1u << 12,
};

/* attributes */
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontFamilyAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontNameAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontFaceAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontSizeAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontVisibleNameAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontMatrixAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontVariationAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontCharacterSetAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontCascadeListAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontTraitsAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontFixedAdvanceAttribute;
APPKIT_EXTERN NSFontDescriptorAttributeName const NSFontFeatureSettingsAttribute;
/* the keys of NSFontTraitsAttribute's dictionary */
APPKIT_EXTERN NSFontDescriptorTraitKey const NSFontSymbolicTrait;
APPKIT_EXTERN NSFontDescriptorTraitKey const NSFontWeightTrait;
APPKIT_EXTERN NSFontDescriptorTraitKey const NSFontWidthTrait;
APPKIT_EXTERN NSFontDescriptorTraitKey const NSFontSlantTrait;
/* variation axes and features */
APPKIT_EXTERN NSFontDescriptorVariationKey const NSFontVariationAxisIdentifierKey;
APPKIT_EXTERN NSFontDescriptorVariationKey const NSFontVariationAxisMinimumValueKey;
APPKIT_EXTERN NSFontDescriptorVariationKey const NSFontVariationAxisMaximumValueKey;
APPKIT_EXTERN NSFontDescriptorVariationKey const NSFontVariationAxisDefaultValueKey;
APPKIT_EXTERN NSFontDescriptorVariationKey const NSFontVariationAxisNameKey;
APPKIT_EXTERN NSFontDescriptorFeatureKey const NSFontFeatureTypeIdentifierKey;
APPKIT_EXTERN NSFontDescriptorFeatureKey const NSFontFeatureSelectorIdentifierKey;
/* the system font's designs */
APPKIT_EXTERN NSFontDescriptorSystemDesign const NSFontDescriptorSystemDesignDefault;
APPKIT_EXTERN NSFontDescriptorSystemDesign const NSFontDescriptorSystemDesignSerif;
APPKIT_EXTERN NSFontDescriptorSystemDesign const NSFontDescriptorSystemDesignMonospaced;
APPKIT_EXTERN NSFontDescriptorSystemDesign const NSFontDescriptorSystemDesignRounded;
/* widths */
APPKIT_EXTERN const NSFontWidth NSFontWidthCompressed, NSFontWidthCondensed, NSFontWidthStandard,
    NSFontWidthExpanded;

@interface NSFontDescriptor : NSObject <NSCopying, NSSecureCoding>
+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(NSDictionary<NSFontDescriptorAttributeName, id> *)attributes;
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)fontName size:(CGFloat)size;
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)fontName matrix:(NSAffineTransform *)matrix;
- (instancetype)initWithFontAttributes:(NSDictionary<NSFontDescriptorAttributeName, id> *)attributes;
@property (readonly, copy) NSDictionary<NSFontDescriptorAttributeName, id> *fontAttributes;
@property (readonly) NSString *postscriptName;
@property (readonly) CGFloat pointSize;
@property (readonly) NSAffineTransform *matrix;
@property (readonly) NSFontDescriptorSymbolicTraits symbolicTraits;
@property (readonly) BOOL requiresFontAssetRequest;
- (id)objectForKey:(NSFontDescriptorAttributeName)attribute;
- (NSArray<NSFontDescriptor *> *)matchingFontDescriptorsWithMandatoryKeys:(NSSet<NSFontDescriptorAttributeName> *)keys;
- (NSFontDescriptor *)matchingFontDescriptorWithMandatoryKeys:(NSSet<NSFontDescriptorAttributeName> *)keys;
- (NSFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary<NSFontDescriptorAttributeName, id> *)attributes;
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSFontDescriptorSymbolicTraits)symbolicTraits;
- (NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)newPointSize;
- (NSFontDescriptor *)fontDescriptorWithMatrix:(NSAffineTransform *)matrix;
- (NSFontDescriptor *)fontDescriptorWithFace:(NSString *)newFace;
- (NSFontDescriptor *)fontDescriptorWithFamily:(NSString *)newFamily;
- (NSFontDescriptor *)fontDescriptorWithDesign:(NSFontDescriptorSystemDesign)design;
@end

@interface NSFont (NSFontDescriptor)
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor size:(CGFloat)size;
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor textTransform:(NSAffineTransform *)textTransform;
@property (readonly) NSFontDescriptor *fontDescriptor;
- (NSFont *)fontWithSize:(CGFloat)size;
@end

@interface NSMutableAttributedString (NSFontTraits)
/* gives each font in the range the traits (NSBoldFontMask, NSUnitalicFontMask and the rest) */
- (void)applyFontTraits:(NSFontTraitMask)traitMask range:(NSRange)range;
@end
