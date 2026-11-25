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
    kCTFontTraitUIOptimized = (1 << 12),
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

/* descriptors, collections and the font manager (freemac 1.NEXT) */
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
CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef context);
double CTLineGetTrailingWhitespaceWidth(CTLineRef line);
double CTLineGetPenOffsetForFlush(CTLineRef line, CGFloat flushFactor, double flushWidth);
CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *secondaryOffset);
CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position);
void CTLineDraw(CTLineRef line, CGContextRef context);
CFTypeID CTLineGetTypeID(void);

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
