/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core Text subset Ferry provides. Written for freemac from
 * Apple's public API documentation; not Apple's header. Fonts come from this
 * system (freemac's system font is Inter); Mac font names such as Helvetica,
 * SF or Menlo are matched to the nearest font that is installed. */
#ifndef _FERRY_CORETEXT_H_
#define _FERRY_CORETEXT_H_
#include <CoreGraphics/CoreGraphics.h>

__FERRY_BEGIN

typedef const struct __CTFont *CTFontRef;
typedef const struct __CTFontDescriptor *CTFontDescriptorRef;
typedef const struct __CTLine *CTLineRef;
typedef const struct __CTRun *CTRunRef;
typedef const struct __CTFramesetter *CTFramesetterRef;
typedef const struct __CTFrame *CTFrameRef;
typedef const struct __CTParagraphStyle *CTParagraphStyleRef;
/* ---- fonts ------------------------------------------------------------------- */

typedef enum {
    kCTFontUIFontNone = (uint32_t)-1, kCTFontUIFontUser = 0, kCTFontUIFontUserFixedPitch = 1,
    kCTFontUIFontSystem = 2, kCTFontUIFontEmphasizedSystem = 3, kCTFontUIFontSmallSystem = 4,
    kCTFontUIFontSmallEmphasizedSystem = 5, kCTFontUIFontMiniSystem = 6, kCTFontUIFontMiniEmphasizedSystem = 7,
    kCTFontUIFontViews = 8, kCTFontUIFontApplication = 9, kCTFontUIFontLabel = 10, kCTFontUIFontMenuTitle = 11,
    kCTFontUIFontMenuItem = 12, kCTFontUIFontMenuItemMark = 13, kCTFontUIFontMenuItemCmdKey = 14,
    kCTFontUIFontWindowTitle = 15, kCTFontUIFontPushButton = 16, kCTFontUIFontUtilityWindowTitle = 17,
    kCTFontUIFontAlertHeader = 18, kCTFontUIFontSystemDetail = 19, kCTFontUIFontEmphasizedSystemDetail = 20,
    kCTFontUIFontToolbar = 21, kCTFontUIFontSmallToolbar = 22, kCTFontUIFontMessage = 23,
    kCTFontUIFontPalette = 24, kCTFontUIFontToolTip = 25, kCTFontUIFontControlContent = 26,
} CTFontUIFontType;
typedef enum {
    kCTFontTraitItalic = (1 << 0), kCTFontTraitBold = (1 << 1), kCTFontTraitExpanded = (1 << 5),
    kCTFontTraitCondensed = (1 << 6), kCTFontTraitMonoSpace = (1 << 10), kCTFontTraitVertical = (1 << 11),
    kCTFontTraitUIOptimized = (1 << 12), kCTFontTraitColorGlyphs = (1 << 13), kCTFontTraitComposite = (1 << 14),
    kCTFontTraitClassMask = (15u << 28),
    kCTFontItalicTrait = kCTFontTraitItalic, kCTFontBoldTrait = kCTFontTraitBold,
    kCTFontExpandedTrait = kCTFontTraitExpanded, kCTFontCondensedTrait = kCTFontTraitCondensed,
    kCTFontMonoSpaceTrait = kCTFontTraitMonoSpace, kCTFontVerticalTrait = kCTFontTraitVertical,
    kCTFontUIOptimizedTrait = kCTFontTraitUIOptimized, kCTFontColorGlyphsTrait = kCTFontTraitColorGlyphs,
    kCTFontCompositeTrait = kCTFontTraitComposite, kCTFontClassMaskTrait = kCTFontTraitClassMask,
} CTFontSymbolicTraits;
typedef enum { kCTFontOrientationDefault = 0, kCTFontOrientationHorizontal = 1, kCTFontOrientationVertical = 2 }
    CTFontOrientation;

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix);
CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType type, CGFloat size, CFStringRef language);
CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                         CTFontDescriptorRef attributes);
CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                             CTFontSymbolicTraits value, CTFontSymbolicTraits mask);
CTFontRef CTFontCreateCopyWithFamily(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                     CFStringRef family);
CTFontRef CTFontCreateForString(CTFontRef current, CFStringRef string, CFRange range);

/* descriptors, collections and the font manager (freemac 1.238) */
typedef const struct __CTFontCollection *CTFontCollectionRef;
extern const CFStringRef kCTFontNameAttribute, kCTFontDisplayNameAttribute, kCTFontFamilyNameAttribute,
    kCTFontStyleNameAttribute, kCTFontSizeAttribute, kCTFontTraitsAttribute, kCTFontURLAttribute;
extern const CFStringRef kCTFontSymbolicTrait, kCTFontWeightTrait, kCTFontWidthTrait, kCTFontSlantTrait;
CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes);
CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size);
CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor);
CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute);
CTFontCollectionRef CTFontCollectionCreateWithFontDescriptors(CFArrayRef descriptors, CFDictionaryRef options);
CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef options);
CFArrayRef CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection);
CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef url);
CFStringRef CTFontCopyPostScriptName(CTFontRef font);
CFStringRef CTFontCopyFamilyName(CTFontRef font);
CFStringRef CTFontCopyFullName(CTFontRef font);
CFStringRef CTFontCopyDisplayName(CTFontRef font);
CGFloat CTFontGetSize(CTFontRef font);
CGAffineTransform CTFontGetMatrix(CTFontRef font);
CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef font);
CGFloat CTFontGetAscent(CTFontRef font);
CGFloat CTFontGetDescent(CTFontRef font);
CGFloat CTFontGetLeading(CTFontRef font);
unsigned CTFontGetUnitsPerEm(CTFontRef font);
CFIndex CTFontGetGlyphCount(CTFontRef font);
CGRect CTFontGetBoundingBox(CTFontRef font);
CGFloat CTFontGetUnderlinePosition(CTFontRef font);
CGFloat CTFontGetUnderlineThickness(CTFontRef font);
CGFloat CTFontGetSlantAngle(CTFontRef font);
CGFloat CTFontGetCapHeight(CTFontRef font);
CGFloat CTFontGetXHeight(CTFontRef font);
bool CTFontGetGlyphsForCharacters(CTFontRef font, const UniChar *characters, CGGlyph *glyphs, CFIndex count);
double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph *glyphs,
                                  CGSize *advances, CFIndex count);
CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph *glyphs,
                                       CGRect *boundingRects, CFIndex count);
CGPathRef CTFontCreatePathForGlyph(CTFontRef font, CGGlyph glyph, const CGAffineTransform *matrix);
void CTFontDrawGlyphs(CTFontRef font, const CGGlyph glyphs[], const CGPoint positions[], size_t count,
                      CGContextRef context);
CFTypeID CTFontGetTypeID(void);

/* ---- font descriptors, traits, names and tables (for Qt's font database) ---- */

/* A descriptor's attributes; the same keys as AppKit's NSFontDescriptor. */
extern const CFStringRef kCTFontURLAttribute;
extern const CFStringRef kCTFontNameAttribute;
extern const CFStringRef kCTFontDisplayNameAttribute;
extern const CFStringRef kCTFontFamilyNameAttribute;
extern const CFStringRef kCTFontStyleNameAttribute;
extern const CFStringRef kCTFontTraitsAttribute;
extern const CFStringRef kCTFontVariationAttribute;
extern const CFStringRef kCTFontSizeAttribute;
extern const CFStringRef kCTFontMatrixAttribute;
extern const CFStringRef kCTFontCascadeListAttribute;
extern const CFStringRef kCTFontCharacterSetAttribute;
/* a font's file format, a CFNumber of CTFontFormat (freemac 1.NEXT) */
extern const CFStringRef kCTFontFormatAttribute;
typedef uint32_t CTFontFormat;
enum {
    kCTFontFormatUnrecognized = 0,
    kCTFontFormatOpenTypePostScript = 1,
    kCTFontFormatOpenTypeTrueType = 2,
    kCTFontFormatTrueType = 3,
    kCTFontFormatPostScript = 4,
    kCTFontFormatBitmap = 5,
};
extern const CFStringRef kCTFontLanguagesAttribute;
extern const CFStringRef kCTFontFixedAdvanceAttribute;
extern const CFStringRef kCTFontFeatureSettingsAttribute;
/* the keys of a feature setting: an OpenType tag ("liga") and its value */
extern const CFStringRef kCTFontOpenTypeFeatureTag;
extern const CFStringRef kCTFontOpenTypeFeatureValue;
/* a font collection option: one descriptor per font */
extern const CFStringRef kCTFontCollectionRemoveDuplicatesOption;
/* the keys of a traits dictionary */
extern const CFStringRef kCTFontSymbolicTrait;
extern const CFStringRef kCTFontWeightTrait;
extern const CFStringRef kCTFontWidthTrait;
extern const CFStringRef kCTFontSlantTrait;
/* the weights a weight trait holds, -1 to 1 */
extern const CGFloat kCTFontWeightUltraLight, kCTFontWeightThin, kCTFontWeightLight, kCTFontWeightRegular,
    kCTFontWeightMedium, kCTFontWeightSemibold, kCTFontWeightBold, kCTFontWeightHeavy, kCTFontWeightBlack;
/* a font's names */
extern const CFStringRef kCTFontCopyrightNameKey, kCTFontFamilyNameKey, kCTFontSubFamilyNameKey,
    kCTFontStyleNameKey, kCTFontUniqueNameKey, kCTFontFullNameKey, kCTFontVersionNameKey,
    kCTFontPostScriptNameKey, kCTFontTrademarkNameKey, kCTFontManufacturerNameKey, kCTFontDesignerNameKey,
    kCTFontDescriptionNameKey, kCTFontVendorURLNameKey, kCTFontDesignerURLNameKey, kCTFontLicenseNameKey,
    kCTFontLicenseURLNameKey, kCTFontSampleTextNameKey, kCTFontPostScriptCIDNameKey;
/* a variation axis's keys */
extern const CFStringRef kCTFontVariationAxisIdentifierKey, kCTFontVariationAxisMinimumValueKey,
    kCTFontVariationAxisMaximumValueKey, kCTFontVariationAxisDefaultValueKey, kCTFontVariationAxisNameKey,
    kCTFontVariationAxisHiddenKey;

typedef uint32_t CTFontTableTag;
typedef CF_OPTIONS(uint32_t, CTFontTableOptions) { kCTFontTableOptionNoOptions = 0, kCTFontTableOptionExcludeSynthetic = (1 << 0) };
enum {
    kCTFontTableBASE = 'BASE', kCTFontTableCFF = 'CFF ', kCTFontTableGDEF = 'GDEF', kCTFontTableGPOS = 'GPOS',
    kCTFontTableGSUB = 'GSUB', kCTFontTableOS2 = 'OS/2', kCTFontTableCmap = 'cmap', kCTFontTableGlyf = 'glyf',
    kCTFontTableHead = 'head', kCTFontTableHhea = 'hhea', kCTFontTableHmtx = 'hmtx', kCTFontTableKern = 'kern',
    kCTFontTableLoca = 'loca', kCTFontTableMaxp = 'maxp', kCTFontTableName = 'name', kCTFontTablePost = 'post',
};

CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes);
CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size);
CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef original, CFDictionaryRef attributes);
CTFontDescriptorRef CTFontDescriptorCreateCopyWithFamily(CTFontDescriptorRef original, CFStringRef family);
CTFontDescriptorRef CTFontDescriptorCreateCopyWithSymbolicTraits(CTFontDescriptorRef original,
                                                                 CTFontSymbolicTraits value, CTFontSymbolicTraits mask);
CFArrayRef CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor, CFSetRef mandatoryAttributes);
CTFontDescriptorRef CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef descriptor,
                                                                 CFSetRef mandatoryAttributes);
CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor);
CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute);
CFTypeID CTFontDescriptorGetTypeID(void);

CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size, const CGAffineTransform *matrix);
CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font);
CFTypeRef CTFontCopyAttribute(CTFontRef font, CFStringRef attribute);
CFDictionaryRef CTFontCopyTraits(CTFontRef font);
CFStringRef CTFontCopyName(CTFontRef font, CFStringRef nameKey);
CFStringRef CTFontCopyLocalizedName(CTFontRef font, CFStringRef nameKey, CFStringRef *actualLanguage);
CFDataRef CTFontCopyTable(CTFontRef font, CTFontTableTag table, CTFontTableOptions options);
CFArrayRef CTFontCopyAvailableTables(CTFontRef font, CTFontTableOptions options);
CFArrayRef CTFontCopyVariationAxes(CTFontRef font);
CFDictionaryRef CTFontCopyVariation(CTFontRef font);
CGGlyph CTFontGetGlyphWithName(CTFontRef font, CFStringRef glyphName);
CFStringRef CTFontCopyNameForGlyph(CTFontRef font, CGGlyph glyph);
CFArrayRef CTFontCopyDefaultCascadeListForLanguages(CTFontRef font, CFArrayRef languagePrefList);
CGFontRef CTFontCopyGraphicsFont(CTFontRef font, CTFontDescriptorRef *attributes);
CTFontRef CTFontCreateWithGraphicsFont(CGFontRef graphicsFont, CGFloat size, const CGAffineTransform *matrix,
                                       CTFontDescriptorRef attributes);

/* ---- the font manager ------------------------------------------------------------ */

typedef CF_ENUM(uint32_t, CTFontManagerScope) {
    kCTFontManagerScopeNone = 0, kCTFontManagerScopeProcess = 1, kCTFontManagerScopePersistent = 2,
    kCTFontManagerScopeSession = 3, kCTFontManagerScopeUser = 2,
};
CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void);
CFArrayRef CTFontManagerCopyAvailablePostScriptNames(void);
CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL);
CTFontDescriptorRef CTFontManagerCreateFontDescriptorFromData(CFDataRef data);
CFArrayRef CTFontManagerCreateFontDescriptorsFromData(CFDataRef data);
void CTFontManagerEnableFontDescriptors(CFArrayRef descriptors, bool enable);

/* ---- string attributes --------------------------------------------------------- */

extern const CFStringRef kCTFontAttributeName;
extern const CFStringRef kCTForegroundColorAttributeName;
extern const CFStringRef kCTForegroundColorFromContextAttributeName;
extern const CFStringRef kCTKernAttributeName;
extern const CFStringRef kCTUnderlineStyleAttributeName;
extern const CFStringRef kCTUnderlineColorAttributeName;
extern const CFStringRef kCTStrokeWidthAttributeName;
extern const CFStringRef kCTStrokeColorAttributeName;
extern const CFStringRef kCTParagraphStyleAttributeName;
extern const CFStringRef kCTLigatureAttributeName;
typedef enum { kCTUnderlineStyleNone = 0, kCTUnderlineStyleSingle = 1, kCTUnderlineStyleThick = 2,
               kCTUnderlineStyleDouble = 9 } CTUnderlineStyle;

/* ---- paragraph styles ---------------------------------------------------------- */

/* These two are one byte each, as on a Mac: CTParagraphStyleSetting passes them by size. */
typedef CF_ENUM(uint8_t, CTTextAlignment) {
    kCTTextAlignmentLeft = 0, kCTTextAlignmentRight = 1, kCTTextAlignmentCenter = 2,
    kCTTextAlignmentJustified = 3, kCTTextAlignmentNatural = 4,
};
typedef CF_ENUM(uint8_t, CTLineBreakMode) {
    kCTLineBreakByWordWrapping = 0, kCTLineBreakByCharWrapping = 1, kCTLineBreakByClipping = 2,
    kCTLineBreakByTruncatingHead = 3, kCTLineBreakByTruncatingTail = 4, kCTLineBreakByTruncatingMiddle = 5,
};
typedef enum {
    kCTParagraphStyleSpecifierAlignment = 0, kCTParagraphStyleSpecifierFirstLineHeadIndent = 1,
    kCTParagraphStyleSpecifierHeadIndent = 2, kCTParagraphStyleSpecifierTailIndent = 3,
    kCTParagraphStyleSpecifierTabStops = 4, kCTParagraphStyleSpecifierDefaultTabInterval = 5,
    kCTParagraphStyleSpecifierLineBreakMode = 6, kCTParagraphStyleSpecifierLineHeightMultiple = 7,
    kCTParagraphStyleSpecifierMaximumLineHeight = 8, kCTParagraphStyleSpecifierMinimumLineHeight = 9,
    kCTParagraphStyleSpecifierParagraphSpacing = 11, kCTParagraphStyleSpecifierParagraphSpacingBefore = 12,
    kCTParagraphStyleSpecifierBaseWritingDirection = 13, kCTParagraphStyleSpecifierMaximumLineSpacing = 14,
    kCTParagraphStyleSpecifierMinimumLineSpacing = 15, kCTParagraphStyleSpecifierLineSpacingAdjustment = 16,
} CTParagraphStyleSpecifier;
typedef struct CTParagraphStyleSetting {
    CTParagraphStyleSpecifier spec;
    size_t valueSize;
    const void *value;
} CTParagraphStyleSetting;

CTParagraphStyleRef CTParagraphStyleCreate(const CTParagraphStyleSetting *settings, size_t count);
bool CTParagraphStyleGetValueForSpecifier(CTParagraphStyleRef style, CTParagraphStyleSpecifier spec,
                                          size_t valueBufferSize, void *valueBuffer);

/* ---- lines ------------------------------------------------------------------- */

typedef enum { kCTLineTruncationStart = 0, kCTLineTruncationEnd = 1, kCTLineTruncationMiddle = 2 }
    CTLineTruncationType;

CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef string);
CTLineRef CTLineCreateTruncatedLine(CTLineRef line, double width, CTLineTruncationType truncationType,
                                    CTLineRef truncationToken);
CFIndex CTLineGetGlyphCount(CTLineRef line);
CFRange CTLineGetStringRange(CTLineRef line);
double CTLineGetTypographicBounds(CTLineRef line, CGFloat *ascent, CGFloat *descent, CGFloat *leading);
typedef CFOptionFlags CTLineBoundsOptions;
enum {
    kCTLineBoundsExcludeTypographicLeading = 1 << 0,
    kCTLineBoundsExcludeTypographicShifts = 1 << 1,
    kCTLineBoundsUseHangingPunctuation = 1 << 2,
    kCTLineBoundsUseGlyphPathBounds = 1 << 3,
    kCTLineBoundsUseOpticalBounds = 1 << 4,
    kCTLineBoundsIncludeLanguageExtents = 1 << 5,
};
CGRect CTLineGetBoundsWithOptions(CTLineRef line, CTLineBoundsOptions options);
CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef context);
double CTLineGetTrailingWhitespaceWidth(CTLineRef line);
double CTLineGetPenOffsetForFlush(CTLineRef line, CGFloat flushFactor, double flushWidth);
CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *secondaryOffset);
CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position);
void CTLineDraw(CTLineRef line, CGContextRef context);
CFTypeID CTLineGetTypeID(void);
/* a line's glyph runs, left to right; the line keeps them */
CFArrayRef CTLineGetGlyphRuns(CTLineRef line);

/* ---- glyph runs -------------------------------------------------------------- */

typedef enum {
    kCTRunStatusNoStatus = 0, kCTRunStatusRightToLeft = 1 << 0, kCTRunStatusNonMonotonic = 1 << 1,
    kCTRunStatusHasNonIdentityMatrix = 1 << 2,
} CTRunStatus;

CFTypeID CTRunGetTypeID(void);
CFIndex CTRunGetGlyphCount(CTRunRef run);
CFDictionaryRef CTRunGetAttributes(CTRunRef run);
CTRunStatus CTRunGetStatus(CTRunRef run);
CFRange CTRunGetStringRange(CTRunRef run);
CGAffineTransform CTRunGetTextMatrix(CTRunRef run);
const CGGlyph *CTRunGetGlyphsPtr(CTRunRef run);
const CGPoint *CTRunGetPositionsPtr(CTRunRef run);
const CGSize *CTRunGetAdvancesPtr(CTRunRef run);
const CFIndex *CTRunGetStringIndicesPtr(CTRunRef run);
/* a range of glyphs (length 0: to the end) copied out */
void CTRunGetGlyphs(CTRunRef run, CFRange range, CGGlyph buffer[]);
void CTRunGetPositions(CTRunRef run, CFRange range, CGPoint buffer[]);
void CTRunGetAdvances(CTRunRef run, CFRange range, CGSize buffer[]);
void CTRunGetStringIndices(CTRunRef run, CFRange range, CFIndex buffer[]);
void CTRunGetBaseAdvancesAndOrigins(CTRunRef run, CFRange range, CGSize advancesBuffer[], CGPoint originsBuffer[]);
double CTRunGetTypographicBounds(CTRunRef run, CFRange range, CGFloat *ascent, CGFloat *descent, CGFloat *leading);
CGRect CTRunGetImageBounds(CTRunRef run, CGContextRef context, CFRange range);
/* draws the glyphs at the context's text position */
void CTRunDraw(CTRunRef run, CGContextRef context, CFRange range);

/* ---- frames ------------------------------------------------------------------ */

CTFramesetterRef CTFramesetterCreateWithAttributedString(CFAttributedStringRef string);
CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef framesetter, CFRange stringRange, CGPathRef path,
                                    CFDictionaryRef frameAttributes);
CGSize CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef framesetter, CFRange stringRange,
                                                    CFDictionaryRef frameAttributes, CGSize constraints,
                                                    CFRange *fitRange);
CFArrayRef CTFrameGetLines(CTFrameRef frame);
void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range, CGPoint origins[]);
CFRange CTFrameGetStringRange(CTFrameRef frame);
CFRange CTFrameGetVisibleStringRange(CTFrameRef frame);
CGPathRef CTFrameGetPath(CTFrameRef frame);
void CTFrameDraw(CTFrameRef frame, CGContextRef context);

/* Font features by type and selector, as the TrueType feature registry
 * numbers them (SFNTLayoutTypes.h; freemac 1.232); Ferry's fonts are
 * drawn without them. */
enum { kNumberSpacingType = 6, kNumberCaseType = 21, kLowerCaseType = 37, kUpperCaseType = 38 };
enum { kMonospacedNumbersSelector = 0, kProportionalNumbersSelector = 1 };

__FERRY_END

#endif
