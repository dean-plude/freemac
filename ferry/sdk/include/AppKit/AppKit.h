/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the AppKit subset Ferry provides. Written for freemac from
 * Apple's public API documentation; not Apple's header. Every class and call
 * declared here is implemented in ferry/appkit. Windows are shown with this
 * system's GTK (on Wayland, or X11), and drawn with Ferry's Core Graphics. */
#ifndef _FERRY_APPKIT_H_
#define _FERRY_APPKIT_H_
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>

#define APPKIT_EXTERN extern
#define NS_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))

@class NSApplication, NSWindow, NSView, NSEvent, NSColor, NSFont, NSMenu, NSMenuItem, NSScreen;
@class NSGraphicsContext, NSBitmapImageRep, NSParagraphStyle, NSBezierPath, NSCursor, NSImage;

/* ---- events ----------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSEventType) {
    NSEventTypeLeftMouseDown = 1, NSEventTypeLeftMouseUp = 2, NSEventTypeRightMouseDown = 3,
    NSEventTypeRightMouseUp = 4, NSEventTypeMouseMoved = 5, NSEventTypeLeftMouseDragged = 6,
    NSEventTypeRightMouseDragged = 7, NSEventTypeMouseEntered = 8, NSEventTypeMouseExited = 9,
    NSEventTypeKeyDown = 10, NSEventTypeKeyUp = 11, NSEventTypeFlagsChanged = 12,
    NSEventTypeAppKitDefined = 13, NSEventTypeSystemDefined = 14, NSEventTypeApplicationDefined = 15,
    NSEventTypePeriodic = 16, NSEventTypeCursorUpdate = 17, NSEventTypeScrollWheel = 22,
    NSEventTypeOtherMouseDown = 25, NSEventTypeOtherMouseUp = 26, NSEventTypeOtherMouseDragged = 27,
};
typedef NS_OPTIONS(unsigned long long, NSEventMask) {
    NSEventMaskLeftMouseDown = 1ULL << 1, NSEventMaskLeftMouseUp = 1ULL << 2,
    NSEventMaskRightMouseDown = 1ULL << 3, NSEventMaskRightMouseUp = 1ULL << 4,
    NSEventMaskMouseMoved = 1ULL << 5, NSEventMaskLeftMouseDragged = 1ULL << 6,
    NSEventMaskRightMouseDragged = 1ULL << 7, NSEventMaskMouseEntered = 1ULL << 8,
    NSEventMaskMouseExited = 1ULL << 9, NSEventMaskKeyDown = 1ULL << 10, NSEventMaskKeyUp = 1ULL << 11,
    NSEventMaskFlagsChanged = 1ULL << 12, NSEventMaskApplicationDefined = 1ULL << 15,
    NSEventMaskScrollWheel = 1ULL << 22, NSEventMaskOtherMouseDown = 1ULL << 25,
    NSEventMaskOtherMouseUp = 1ULL << 26, NSEventMaskOtherMouseDragged = 1ULL << 27,
    NSEventMaskAny = ~0ULL,
};
static inline NSEventMask NSEventMaskFromType(NSEventType type) { return 1ULL << type; }
typedef NS_OPTIONS(NSUInteger, NSEventModifierFlags) {
    NSEventModifierFlagCapsLock = 1 << 16, NSEventModifierFlagShift = 1 << 17,
    NSEventModifierFlagControl = 1 << 18, NSEventModifierFlagOption = 1 << 19,
    NSEventModifierFlagCommand = 1 << 20, NSEventModifierFlagNumericPad = 1 << 21,
    NSEventModifierFlagHelp = 1 << 22, NSEventModifierFlagFunction = 1 << 23,
    NSEventModifierFlagDeviceIndependentFlagsMask = 0xffff0000UL,
};
/* The older names, still common in code. */
enum {
    NSLeftMouseDown = 1, NSLeftMouseUp = 2, NSRightMouseDown = 3, NSRightMouseUp = 4, NSMouseMoved = 5,
    NSLeftMouseDragged = 6, NSRightMouseDragged = 7, NSMouseEntered = 8, NSMouseExited = 9, NSKeyDown = 10,
    NSKeyUp = 11, NSFlagsChanged = 12, NSApplicationDefined = 15, NSScrollWheel = 22,
    NSOtherMouseDown = 25, NSOtherMouseUp = 26, NSOtherMouseDragged = 27,
};
#define NSAnyEventMask NSEventMaskAny
#define NSAlphaShiftKeyMask NSEventModifierFlagCapsLock
#define NSShiftKeyMask NSEventModifierFlagShift
#define NSControlKeyMask NSEventModifierFlagControl
#define NSAlternateKeyMask NSEventModifierFlagOption
#define NSCommandKeyMask NSEventModifierFlagCommand
#define NSNumericPadKeyMask NSEventModifierFlagNumericPad
#define NSFunctionKeyMask NSEventModifierFlagFunction
#define NSDeviceIndependentModifierFlagsMask NSEventModifierFlagDeviceIndependentFlagsMask

/* The characters of keys that don't type one. */
enum {
    NSUpArrowFunctionKey = 0xF700, NSDownArrowFunctionKey = 0xF701, NSLeftArrowFunctionKey = 0xF702,
    NSRightArrowFunctionKey = 0xF703, NSF1FunctionKey = 0xF704, NSF2FunctionKey = 0xF705,
    NSF3FunctionKey = 0xF706, NSF4FunctionKey = 0xF707, NSF5FunctionKey = 0xF708, NSF6FunctionKey = 0xF709,
    NSF7FunctionKey = 0xF70A, NSF8FunctionKey = 0xF70B, NSF9FunctionKey = 0xF70C, NSF10FunctionKey = 0xF70D,
    NSF11FunctionKey = 0xF70E, NSF12FunctionKey = 0xF70F, NSInsertFunctionKey = 0xF727,
    NSDeleteFunctionKey = 0xF728, NSHomeFunctionKey = 0xF729, NSBeginFunctionKey = 0xF72A,
    NSEndFunctionKey = 0xF72B, NSPageUpFunctionKey = 0xF72C, NSPageDownFunctionKey = 0xF72D,
};
enum {
    NSEnterCharacter = 0x03, NSBackspaceCharacter = 0x08, NSTabCharacter = 0x09, NSNewlineCharacter = 0x0a,
    NSFormFeedCharacter = 0x0c, NSCarriageReturnCharacter = 0x0d, NSBackTabCharacter = 0x19,
    NSDeleteCharacter = 0x7f,
};

@interface NSEvent : NSObject <NSCopying>
+ (NSEvent *)mouseEventWithType:(NSEventType)type location:(NSPoint)location
                  modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                   windowNumber:(NSInteger)windowNumber context:(id)context eventNumber:(NSInteger)eventNumber
                     clickCount:(NSInteger)clickCount pressure:(float)pressure;
+ (NSEvent *)keyEventWithType:(NSEventType)type location:(NSPoint)location
                modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                 windowNumber:(NSInteger)windowNumber context:(id)context characters:(NSString *)characters
  charactersIgnoringModifiers:(NSString *)unmodCharacters isARepeat:(BOOL)repeat keyCode:(unsigned short)code;
+ (NSEvent *)otherEventWithType:(NSEventType)type location:(NSPoint)location
                  modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                   windowNumber:(NSInteger)windowNumber context:(id)context subtype:(short)subtype
                          data1:(NSInteger)d1 data2:(NSInteger)d2;
@property (class, readonly) NSPoint mouseLocation;
@property (class, readonly) NSEventModifierFlags modifierFlags;
@property (class, readonly) NSUInteger pressedMouseButtons;
@property (class, readonly) NSTimeInterval doubleClickInterval;
@property (readonly) NSEventType type;
@property (readonly) NSEventModifierFlags modifierFlags;
@property (readonly) NSTimeInterval timestamp;
@property (readonly, assign) NSWindow *window;
@property (readonly) NSInteger windowNumber;
@property (readonly) NSPoint locationInWindow;
@property (readonly) NSInteger clickCount;
@property (readonly) NSInteger buttonNumber;
@property (readonly) NSInteger eventNumber;
@property (readonly) float pressure;
@property (readonly) CGFloat deltaX, deltaY, deltaZ;
@property (readonly) CGFloat scrollingDeltaX, scrollingDeltaY;
@property (readonly) BOOL hasPreciseScrollingDeltas;
@property (readonly, copy) NSString *characters;
@property (readonly, copy) NSString *charactersIgnoringModifiers;
@property (readonly, getter=isARepeat) BOOL ARepeat;
@property (readonly) unsigned short keyCode;
@property (readonly) short subtype;
@property (readonly) NSInteger data1, data2;
@end

/* ---- responders --------------------------------------------------------------------- */

@interface NSResponder : NSObject <NSCoding>
@property (assign) NSResponder *nextResponder;
@property (readonly) BOOL acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (void)mouseDown:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)mouseEntered:(NSEvent *)event;
- (void)mouseExited:(NSEvent *)event;
- (void)rightMouseDown:(NSEvent *)event;
- (void)rightMouseDragged:(NSEvent *)event;
- (void)rightMouseUp:(NSEvent *)event;
- (void)otherMouseDown:(NSEvent *)event;
- (void)otherMouseDragged:(NSEvent *)event;
- (void)otherMouseUp:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (void)keyUp:(NSEvent *)event;
- (void)flagsChanged:(NSEvent *)event;
- (BOOL)performKeyEquivalent:(NSEvent *)event;
- (void)interpretKeyEvents:(NSArray<NSEvent *> *)events;
- (void)insertText:(id)string;
- (void)doCommandBySelector:(SEL)selector;
- (BOOL)tryToPerform:(SEL)action with:(id)object;
- (void)noResponderFor:(SEL)eventSelector;
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType;
@end

/* ---- graphics ----------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSCompositingOperation) {
    NSCompositingOperationClear = 0, NSCompositingOperationCopy = 1, NSCompositingOperationSourceOver = 2,
    NSCompositingOperationSourceIn = 3, NSCompositingOperationSourceOut = 4,
    NSCompositingOperationSourceAtop = 5, NSCompositingOperationDestinationOver = 6,
    NSCompositingOperationDestinationIn = 7, NSCompositingOperationDestinationOut = 8,
    NSCompositingOperationDestinationAtop = 9, NSCompositingOperationXOR = 10,
    NSCompositingOperationPlusDarker = 11, NSCompositingOperationPlusLighter = 13,
};
#define NSCompositeClear NSCompositingOperationClear
#define NSCompositeCopy NSCompositingOperationCopy
#define NSCompositeSourceOver NSCompositingOperationSourceOver

@interface NSGraphicsContext : NSObject
+ (NSGraphicsContext *)currentContext;
+ (void)setCurrentContext:(NSGraphicsContext *)context;
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)context flipped:(BOOL)flipped;
+ (NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)rep;
+ (void)saveGraphicsState;
+ (void)restoreGraphicsState;
+ (BOOL)currentContextDrawingToScreen;
@property (readonly) CGContextRef CGContext;
@property (readonly, getter=isFlipped) BOOL flipped;
@property (readonly, getter=isDrawingToScreen) BOOL drawingToScreen;
@property BOOL shouldAntialias;
@property NSCompositingOperation compositingOperation;
- (void)saveGraphicsState;
- (void)restoreGraphicsState;
- (void)flushGraphics;
@end

@interface NSColor : NSObject <NSCopying, NSCoding>
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithGenericGamma22White:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithDeviceHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithCGColor:(CGColorRef)color;
@property (class, readonly) NSColor *blackColor, *darkGrayColor, *lightGrayColor, *whiteColor, *grayColor;
@property (class, readonly) NSColor *redColor, *greenColor, *blueColor, *cyanColor, *yellowColor;
@property (class, readonly) NSColor *magentaColor, *orangeColor, *purpleColor, *brownColor, *clearColor;
@property (class, readonly) NSColor *systemRedColor, *systemGreenColor, *systemBlueColor, *systemOrangeColor;
@property (class, readonly) NSColor *systemYellowColor, *systemPurpleColor, *systemGrayColor, *systemPinkColor;
@property (class, readonly) NSColor *labelColor, *secondaryLabelColor, *tertiaryLabelColor;
@property (class, readonly) NSColor *textColor, *textBackgroundColor, *selectedTextColor;
@property (class, readonly) NSColor *selectedTextBackgroundColor, *placeholderTextColor;
@property (class, readonly) NSColor *controlColor, *controlBackgroundColor, *controlTextColor;
@property (class, readonly) NSColor *disabledControlTextColor, *selectedControlColor;
@property (class, readonly) NSColor *windowBackgroundColor, *underPageBackgroundColor, *gridColor;
@property (class, readonly) NSColor *separatorColor, *controlAccentColor, *keyboardFocusIndicatorColor;
@property (class, readonly) NSColor *alternateSelectedControlColor, *headerTextColor, *linkColor;
@property (readonly) CGFloat redComponent, greenComponent, blueComponent, alphaComponent, whiteComponent;
@property (readonly) CGFloat hueComponent, saturationComponent, brightnessComponent;
@property (readonly) NSInteger numberOfComponents;
@property (readonly) CGColorRef CGColor;
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (void)getWhite:(CGFloat *)w alpha:(CGFloat *)a;
- (void)getHue:(CGFloat *)h saturation:(CGFloat *)s brightness:(CGFloat *)b alpha:(CGFloat *)a;
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;
- (NSColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(NSColor *)color;
- (NSColor *)highlightWithLevel:(CGFloat)level;
- (NSColor *)shadowWithLevel:(CGFloat)level;
- (NSColor *)colorUsingColorSpaceName:(NSString *)name;
- (NSColor *)colorUsingColorSpace:(id)space;
- (void)set;
- (void)setFill;
- (void)setStroke;
@end
APPKIT_EXTERN NSString *const NSCalibratedRGBColorSpace;
APPKIT_EXTERN NSString *const NSDeviceRGBColorSpace;
APPKIT_EXTERN NSString *const NSCalibratedWhiteColorSpace;
APPKIT_EXTERN NSString *const NSDeviceWhiteColorSpace;

typedef CGFloat NSFontWeight;
APPKIT_EXTERN const NSFontWeight NSFontWeightUltraLight, NSFontWeightThin, NSFontWeightLight;
APPKIT_EXTERN const NSFontWeight NSFontWeightRegular, NSFontWeightMedium, NSFontWeightSemibold;
APPKIT_EXTERN const NSFontWeight NSFontWeightBold, NSFontWeightHeavy, NSFontWeightBlack;
typedef NS_ENUM(NSUInteger, NSControlSize) {
    NSControlSizeRegular = 0, NSControlSizeSmall = 1, NSControlSizeMini = 2, NSControlSizeLarge = 3,
};

/* An NSFont is a Core Text font: a CTFontRef can be used as an NSFont and an
 * NSFont as a CTFontRef, as on a Mac. */
#ifdef FERRY_APPKIT_BUILD
@interface NSFont : GFont <NSCopying, NSCoding>       /* inside Ferry: a Core Text font */
#else
@interface NSFont : NSObject <NSCopying, NSCoding>
#endif
+ (NSFont *)fontWithName:(NSString *)name size:(CGFloat)size;
+ (NSFont *)systemFontOfSize:(CGFloat)size;
+ (NSFont *)systemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)boldSystemFontOfSize:(CGFloat)size;
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
+ (NSFont *)userFontOfSize:(CGFloat)size;
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)size;
+ (NSFont *)labelFontOfSize:(CGFloat)size;
+ (NSFont *)messageFontOfSize:(CGFloat)size;
+ (NSFont *)menuFontOfSize:(CGFloat)size;
+ (NSFont *)titleBarFontOfSize:(CGFloat)size;
+ (NSFont *)controlContentFontOfSize:(CGFloat)size;
+ (NSFont *)toolTipsFontOfSize:(CGFloat)size;
@property (class, readonly) CGFloat systemFontSize, smallSystemFontSize, labelFontSize;
+ (CGFloat)systemFontSizeForControlSize:(NSControlSize)size;
@property (readonly, copy) NSString *fontName, *familyName, *displayName;
@property (readonly) CGFloat pointSize, ascender, descender, leading, capHeight, xHeight;
@property (readonly) CGFloat underlinePosition, underlineThickness, italicAngle;
@property (readonly) NSRect boundingRectForFont;
@property (readonly, getter=isFixedPitch) BOOL fixedPitch;
@property (readonly) NSUInteger numberOfGlyphs;
- (NSSize)advancementForGlyph:(CGGlyph)glyph;
- (void)set;
- (void)setInContext:(NSGraphicsContext *)context;
@end

typedef NS_ENUM(NSInteger, NSTextAlignment) {
    NSTextAlignmentLeft = 0, NSTextAlignmentRight = 1, NSTextAlignmentCenter = 2,
    NSTextAlignmentJustified = 3, NSTextAlignmentNatural = 4,
};
#define NSLeftTextAlignment NSTextAlignmentLeft
#define NSRightTextAlignment NSTextAlignmentRight
#define NSCenterTextAlignment NSTextAlignmentCenter
#define NSJustifiedTextAlignment NSTextAlignmentJustified
#define NSNaturalTextAlignment NSTextAlignmentNatural
typedef NS_ENUM(NSUInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0, NSLineBreakByCharWrapping = 1, NSLineBreakByClipping = 2,
    NSLineBreakByTruncatingHead = 3, NSLineBreakByTruncatingTail = 4, NSLineBreakByTruncatingMiddle = 5,
};
typedef NS_ENUM(NSInteger, NSWritingDirection) {
    NSWritingDirectionNatural = -1, NSWritingDirectionLeftToRight = 0, NSWritingDirectionRightToLeft = 1,
};

#ifdef FERRY_APPKIT_BUILD
@interface NSParagraphStyle : GParagraphStyle <NSCopying, NSMutableCopying>
#else
@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying>
#endif
@property (class, readonly) NSParagraphStyle *defaultParagraphStyle;
@property (readonly) NSTextAlignment alignment;
@property (readonly) NSLineBreakMode lineBreakMode;
@property (readonly) NSWritingDirection baseWritingDirection;
@property (readonly) CGFloat lineSpacing, paragraphSpacing, paragraphSpacingBefore;
@property (readonly) CGFloat headIndent, tailIndent, firstLineHeadIndent;
@property (readonly) CGFloat minimumLineHeight, maximumLineHeight, lineHeightMultiple;
@end
@interface NSMutableParagraphStyle : NSParagraphStyle
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property NSWritingDirection baseWritingDirection;
@property CGFloat lineSpacing, paragraphSpacing, paragraphSpacingBefore;
@property CGFloat headIndent, tailIndent, firstLineHeadIndent;
@property CGFloat minimumLineHeight, maximumLineHeight, lineHeightMultiple;
- (void)setParagraphStyle:(NSParagraphStyle *)style;
@end

typedef NSString *NSAttributedStringKey;
APPKIT_EXTERN NSAttributedStringKey const NSFontAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSForegroundColorAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSBackgroundColorAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSParagraphStyleAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSKernAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSUnderlineStyleAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSUnderlineColorAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSStrikethroughStyleAttributeName;
APPKIT_EXTERN NSAttributedStringKey const NSLigatureAttributeName;
typedef NS_OPTIONS(NSInteger, NSUnderlineStyle) {
    NSUnderlineStyleNone = 0, NSUnderlineStyleSingle = 1, NSUnderlineStyleThick = 2, NSUnderlineStyleDouble = 9,
};
typedef NS_OPTIONS(NSInteger, NSStringDrawingOptions) {
    NSStringDrawingUsesLineFragmentOrigin = 1 << 0, NSStringDrawingUsesFontLeading = 1 << 1,
    NSStringDrawingUsesDeviceMetrics = 1 << 3, NSStringDrawingTruncatesLastVisibleLine = 1 << 5,
};

@interface NSString (NSStringDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;
- (void)drawAtPoint:(NSPoint)point withAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;
- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
                    attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;
@end
@interface NSAttributedString (NSStringDrawing)
- (NSSize)size;
- (void)drawAtPoint:(NSPoint)point;
- (void)drawInRect:(NSRect)rect;
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options;
@end

typedef NS_ENUM(NSUInteger, NSLineCapStyle) { NSLineCapStyleButt = 0, NSLineCapStyleRound = 1, NSLineCapStyleSquare = 2 };
typedef NS_ENUM(NSUInteger, NSLineJoinStyle) { NSLineJoinStyleMiter = 0, NSLineJoinStyleRound = 1, NSLineJoinStyleBevel = 2 };
typedef NS_ENUM(NSUInteger, NSWindingRule) { NSWindingRuleNonZero = 0, NSWindingRuleEvenOdd = 1 };
typedef NS_ENUM(NSUInteger, NSBezierPathElement) {
    NSBezierPathElementMoveTo = 0, NSBezierPathElementLineTo = 1, NSBezierPathElementCurveTo = 2,
    NSBezierPathElementClosePath = 3,
};

@interface NSBezierPath : NSObject <NSCopying>
+ (NSBezierPath *)bezierPath;
+ (NSBezierPath *)bezierPathWithRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xr yRadius:(CGFloat)yr;
+ (void)fillRect:(NSRect)rect;
+ (void)strokeRect:(NSRect)rect;
+ (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b;
+ (void)clipRect:(NSRect)rect;
@property (class) CGFloat defaultLineWidth;
- (void)moveToPoint:(NSPoint)p;
- (void)lineToPoint:(NSPoint)p;
- (void)curveToPoint:(NSPoint)p controlPoint1:(NSPoint)c1 controlPoint2:(NSPoint)c2;
- (void)relativeMoveToPoint:(NSPoint)p;
- (void)relativeLineToPoint:(NSPoint)p;
- (void)closePath;
- (void)removeAllPoints;
- (void)appendBezierPath:(NSBezierPath *)path;
- (void)appendBezierPathWithRect:(NSRect)rect;
- (void)appendBezierPathWithOvalInRect:(NSRect)rect;
- (void)appendBezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xr yRadius:(CGFloat)yr;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a1
                                 endAngle:(CGFloat)a2 clockwise:(BOOL)clockwise;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a1 endAngle:(CGFloat)a2;
- (void)fill;
- (void)stroke;
- (void)addClip;
- (void)setClip;
- (BOOL)containsPoint:(NSPoint)p;
- (void)transformUsingAffineTransform:(id)transform;
- (void)setLineDash:(const CGFloat *)pattern count:(NSInteger)count phase:(CGFloat)phase;
@property CGFloat lineWidth, miterLimit, flatness;
@property NSLineCapStyle lineCapStyle;
@property NSLineJoinStyle lineJoinStyle;
@property NSWindingRule windingRule;
@property (readonly, getter=isEmpty) BOOL empty;
@property (readonly) NSPoint currentPoint;
@property (readonly) NSRect bounds, controlPointBounds;
@property (readonly) NSInteger elementCount;
@property (readonly) CGPathRef CGPath;
@end

void NSRectFill(NSRect rect);
void NSRectFillUsingOperation(NSRect rect, NSCompositingOperation op);
void NSRectFillList(const NSRect *rects, NSInteger count);
void NSFrameRect(NSRect rect);
void NSFrameRectWithWidth(NSRect rect, CGFloat width);
void NSEraseRect(NSRect rect);
void NSRectClip(NSRect rect);
void NSBeep(void);

typedef NS_ENUM(NSUInteger, NSBitmapImageFileType) {
    NSBitmapImageFileTypeTIFF = 0, NSBitmapImageFileTypeBMP = 1, NSBitmapImageFileTypeGIF = 2,
    NSBitmapImageFileTypeJPEG = 3, NSBitmapImageFileTypePNG = 4,
};
typedef NS_OPTIONS(NSUInteger, NSBitmapFormat) {
    NSBitmapFormatAlphaFirst = 1 << 0, NSBitmapFormatAlphaNonpremultiplied = 1 << 1,
};
APPKIT_EXTERN NSString *const NSDeviceRGBColorSpace;

@interface NSImageRep : NSObject <NSCopying>
@property NSSize size;
@property NSInteger pixelsWide, pixelsHigh;
@property (readonly) NSInteger bitsPerSample;
@property (getter=hasAlpha) BOOL alpha;
- (BOOL)draw;
- (BOOL)drawAtPoint:(NSPoint)point;
- (BOOL)drawInRect:(NSRect)rect;
@end

/* Bitmaps of 8-bit RGB or RGBA (premultiplied, alpha last), as a view's
 * cacheDisplayInRect:toBitmapImageRep: makes them. */
@interface NSBitmapImageRep : NSImageRep
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar
                          colorSpaceName:(NSString *)space bytesPerRow:(NSInteger)bpr
                            bitsPerPixel:(NSInteger)bpp;
- (instancetype)initWithCGImage:(CGImageRef)image;
@property (readonly) unsigned char *bitmapData;
@property (readonly) NSInteger bytesPerRow, samplesPerPixel, bitsPerPixel;
@property (readonly) NSBitmapFormat bitmapFormat;
@property (readonly) CGImageRef CGImage;
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y;
- (void)setColor:(NSColor *)color atX:(NSInteger)x y:(NSInteger)y;
- (NSData *)representationUsingType:(NSBitmapImageFileType)type properties:(NSDictionary *)properties;
@end

/* ---- views ----------------------------------------------------------------------- */

typedef NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions) {
    NSViewNotSizable = 0, NSViewMinXMargin = 1, NSViewWidthSizable = 2, NSViewMaxXMargin = 4,
    NSViewMinYMargin = 8, NSViewHeightSizable = 16, NSViewMaxYMargin = 32,
};
typedef NS_ENUM(NSUInteger, NSFocusRingType) { NSFocusRingTypeDefault = 0, NSFocusRingTypeNone = 1, NSFocusRingTypeExterior = 2 };

@interface NSView : NSResponder
- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
@property NSRect frame, bounds;
@property NSPoint frameOrigin;
@property NSSize frameSize;
- (void)setFrameOrigin:(NSPoint)origin;
- (void)setFrameSize:(NSSize)size;
- (void)setBoundsOrigin:(NSPoint)origin;
- (void)setBoundsSize:(NSSize)size;
@property (readonly, assign) NSView *superview;
@property (copy) NSArray<NSView *> *subviews;
@property (readonly, assign) NSWindow *window;
@property (readonly, getter=isFlipped) BOOL flipped;
@property (readonly, getter=isOpaque) BOOL opaque;
@property (getter=isHidden) BOOL hidden;
@property (readonly, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property BOOL needsDisplay;
@property BOOL autoresizesSubviews;
@property NSAutoresizingMaskOptions autoresizingMask;
@property (readonly) NSInteger tag;
@property BOOL wantsLayer;
@property CGFloat alphaValue;
@property (copy) NSString *toolTip;
@property NSFocusRingType focusRingType;
@property (assign) NSView *nextKeyView;
@property (readonly, assign) NSView *previousKeyView;
@property (readonly) NSView *nextValidKeyView;
@property (readonly) BOOL canBecomeKeyView;
@property (readonly) NSRect visibleRect;
@property BOOL postsFrameChangedNotifications, postsBoundsChangedNotifications;
@property (readonly) BOOL inLiveResize;
@property BOOL translatesAutoresizingMaskIntoConstraints;
- (void)addSubview:(NSView *)view;
- (void)addSubview:(NSView *)view positioned:(NSInteger)place relativeTo:(NSView *)other;
- (void)removeFromSuperview;
- (void)replaceSubview:(NSView *)old with:(NSView *)replacement;
- (BOOL)isDescendantOf:(NSView *)view;
- (NSView *)viewWithTag:(NSInteger)tag;
- (void)viewWillMoveToWindow:(NSWindow *)window;
- (void)viewDidMoveToWindow;
- (void)viewWillMoveToSuperview:(NSView *)superview;
- (void)viewDidMoveToSuperview;
- (void)didAddSubview:(NSView *)view;
- (void)willRemoveSubview:(NSView *)view;
- (void)resizeSubviewsWithOldSize:(NSSize)size;
- (void)resizeWithOldSuperviewSize:(NSSize)size;
- (void)drawRect:(NSRect)dirtyRect;
- (void)setNeedsDisplayInRect:(NSRect)rect;
- (void)display;
- (void)displayIfNeeded;
- (void)displayRect:(NSRect)rect;
- (void)lockFocus;
- (void)unlockFocus;
- (NSView *)hitTest:(NSPoint)point;
- (BOOL)mouse:(NSPoint)point inRect:(NSRect)rect;
- (BOOL)acceptsFirstMouse:(NSEvent *)event;
- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)view;
- (NSPoint)convertPoint:(NSPoint)point toView:(NSView *)view;
- (NSSize)convertSize:(NSSize)size fromView:(NSView *)view;
- (NSSize)convertSize:(NSSize)size toView:(NSView *)view;
- (NSRect)convertRect:(NSRect)rect fromView:(NSView *)view;
- (NSRect)convertRect:(NSRect)rect toView:(NSView *)view;
- (NSRect)centerScanRect:(NSRect)rect;
- (NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)rect;
- (void)cacheDisplayInRect:(NSRect)rect toBitmapImageRep:(NSBitmapImageRep *)rep;
- (void)scrollPoint:(NSPoint)point;
- (BOOL)performKeyEquivalent:(NSEvent *)event;
- (void)setKeyboardFocusRingNeedsDisplayInRect:(NSRect)rect;
@end
APPKIT_EXTERN NSNotificationName const NSViewFrameDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSViewBoundsDidChangeNotification;

/* ---- controls -------------------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSControlStateValue) {
    NSControlStateValueMixed = -1, NSControlStateValueOff = 0, NSControlStateValueOn = 1,
};
#define NSMixedState NSControlStateValueMixed
#define NSOffState NSControlStateValueOff
#define NSOnState NSControlStateValueOn

@interface NSControl : NSView
@property (assign) id target;
@property SEL action;
@property NSInteger tag;
@property (getter=isEnabled) BOOL enabled;
@property (copy) id objectValue;
@property (copy) NSString *stringValue;
@property (copy) NSAttributedString *attributedStringValue;
@property int intValue;
@property NSInteger integerValue;
@property float floatValue;
@property double doubleValue;
@property (retain) NSFont *font;
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property NSControlSize controlSize;
@property (getter=isContinuous) BOOL continuous;
@property (getter=isHighlighted) BOOL highlighted;
- (BOOL)sendAction:(SEL)action to:(id)target;
- (void)takeStringValueFrom:(id)sender;
- (void)takeIntValueFrom:(id)sender;
- (void)takeDoubleValueFrom:(id)sender;
- (void)performClick:(id)sender;
- (void)sizeToFit;
@property (readonly) NSSize intrinsicContentSize;
@end

typedef NS_ENUM(NSUInteger, NSButtonType) {
    NSButtonTypeMomentaryLight = 0, NSButtonTypePushOnPushOff = 1, NSButtonTypeToggle = 2,
    NSButtonTypeSwitch = 3, NSButtonTypeRadio = 4, NSButtonTypeMomentaryChange = 5, NSButtonTypeOnOff = 6,
    NSButtonTypeMomentaryPushIn = 7, NSButtonTypeAccelerator = 8, NSButtonTypeMultiLevelAccelerator = 9,
};
#define NSMomentaryLightButton NSButtonTypeMomentaryLight
#define NSPushOnPushOffButton NSButtonTypePushOnPushOff
#define NSToggleButton NSButtonTypeToggle
#define NSSwitchButton NSButtonTypeSwitch
#define NSRadioButton NSButtonTypeRadio
#define NSMomentaryChangeButton NSButtonTypeMomentaryChange
#define NSOnOffButton NSButtonTypeOnOff
#define NSMomentaryPushInButton NSButtonTypeMomentaryPushIn
typedef NS_ENUM(NSUInteger, NSBezelStyle) {
    NSBezelStyleRounded = 1, NSBezelStyleRegularSquare = 2, NSBezelStyleDisclosure = 5,
    NSBezelStyleShadowlessSquare = 6, NSBezelStyleCircular = 7, NSBezelStyleTexturedSquare = 8,
    NSBezelStyleHelpButton = 9, NSBezelStyleSmallSquare = 10, NSBezelStyleTexturedRounded = 11,
    NSBezelStyleRoundRect = 12, NSBezelStyleRecessed = 13, NSBezelStyleRoundedDisclosure = 14,
    NSBezelStyleInline = 15,
};
#define NSRoundedBezelStyle NSBezelStyleRounded
#define NSRegularSquareBezelStyle NSBezelStyleRegularSquare
#define NSTexturedRoundedBezelStyle NSBezelStyleTexturedRounded
#define NSRecessedBezelStyle NSBezelStyleRecessed
#define NSRoundRectBezelStyle NSBezelStyleRoundRect

@interface NSButton : NSControl
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
+ (instancetype)checkboxWithTitle:(NSString *)title target:(id)target action:(SEL)action;
+ (instancetype)radioButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
@property (copy) NSString *title, *alternateTitle;
@property (copy) NSAttributedString *attributedTitle;
@property NSBezelStyle bezelStyle;
@property NSControlStateValue state;
@property BOOL allowsMixedState;
@property (getter=isBordered) BOOL bordered;
@property (getter=isTransparent) BOOL transparent;
@property (copy) NSString *keyEquivalent;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property (retain) NSColor *contentTintColor, *bezelColor;
@property (retain) NSImage *image;
- (void)setButtonType:(NSButtonType)type;
- (void)setNextState;
- (void)highlight:(BOOL)flag;
@end

typedef NS_ENUM(NSUInteger, NSTextFieldBezelStyle) { NSTextFieldSquareBezel = 0, NSTextFieldRoundedBezel = 1 };

@interface NSTextField : NSControl
+ (instancetype)labelWithString:(NSString *)string;
+ (instancetype)wrappingLabelWithString:(NSString *)string;
+ (instancetype)labelWithAttributedString:(NSAttributedString *)string;
+ (instancetype)textFieldWithString:(NSString *)string;
@property (copy) NSString *placeholderString;
@property (copy) NSAttributedString *placeholderAttributedString;
@property (getter=isEditable) BOOL editable;
@property (getter=isSelectable) BOOL selectable;
@property (getter=isBezeled) BOOL bezeled;
@property (getter=isBordered) BOOL bordered;
@property NSTextFieldBezelStyle bezelStyle;
@property BOOL drawsBackground;
@property (retain) NSColor *backgroundColor, *textColor;
@property (assign) id delegate;
@property NSInteger maximumNumberOfLines;
@property CGFloat preferredMaxLayoutWidth;
@property BOOL usesSingleLineMode;
- (void)selectText:(id)sender;
@end
/* An NSTextField that hides what is typed. */
@interface NSSecureTextField : NSTextField
@end

@protocol NSControlTextEditingDelegate <NSObject>
@optional
- (void)controlTextDidBeginEditing:(NSNotification *)notification;
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (BOOL)control:(NSControl *)control textView:(id)textView doCommandBySelector:(SEL)selector;
@end
@protocol NSTextFieldDelegate <NSControlTextEditingDelegate>
@end
APPKIT_EXTERN NSNotificationName const NSControlTextDidBeginEditingNotification;
APPKIT_EXTERN NSNotificationName const NSControlTextDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSControlTextDidEndEditingNotification;

/* ---- windows ------------------------------------------------------------------------ */

typedef NS_OPTIONS(NSUInteger, NSWindowStyleMask) {
    NSWindowStyleMaskBorderless = 0, NSWindowStyleMaskTitled = 1 << 0, NSWindowStyleMaskClosable = 1 << 1,
    NSWindowStyleMaskMiniaturizable = 1 << 2, NSWindowStyleMaskResizable = 1 << 3,
    NSWindowStyleMaskUtilityWindow = 1 << 4, NSWindowStyleMaskDocModalWindow = 1 << 6,
    NSWindowStyleMaskNonactivatingPanel = 1 << 7, NSWindowStyleMaskUnifiedTitleAndToolbar = 1 << 12,
    NSWindowStyleMaskHUDWindow = 1 << 13, NSWindowStyleMaskFullScreen = 1 << 14,
    NSWindowStyleMaskFullSizeContentView = 1 << 15,
};
#define NSBorderlessWindowMask NSWindowStyleMaskBorderless
#define NSTitledWindowMask NSWindowStyleMaskTitled
#define NSClosableWindowMask NSWindowStyleMaskClosable
#define NSMiniaturizableWindowMask NSWindowStyleMaskMiniaturizable
#define NSResizableWindowMask NSWindowStyleMaskResizable
typedef NS_ENUM(NSUInteger, NSBackingStoreType) {
    NSBackingStoreRetained = 0, NSBackingStoreNonretained = 1, NSBackingStoreBuffered = 2,
};
typedef NS_ENUM(NSInteger, NSWindowOrderingMode) { NSWindowAbove = 1, NSWindowBelow = -1, NSWindowOut = 0 };
typedef NSInteger NSWindowLevel;
enum { NSNormalWindowLevel = 0, NSFloatingWindowLevel = 3, NSModalPanelWindowLevel = 8, NSMainMenuWindowLevel = 24 };

@protocol NSWindowDelegate <NSObject>
@optional
- (BOOL)windowShouldClose:(NSWindow *)sender;
- (void)windowWillClose:(NSNotification *)notification;
- (void)windowDidResize:(NSNotification *)notification;
- (void)windowDidMove:(NSNotification *)notification;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)windowDidBecomeMain:(NSNotification *)notification;
- (void)windowDidResignMain:(NSNotification *)notification;
- (void)windowDidMiniaturize:(NSNotification *)notification;
- (void)windowDidDeminiaturize:(NSNotification *)notification;
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)size;
@end

@interface NSWindow : NSResponder
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)defer;
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)defer screen:(NSScreen *)screen;
+ (NSRect)frameRectForContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style;
+ (NSRect)contentRectForFrameRect:(NSRect)rect styleMask:(NSWindowStyleMask)style;
- (NSRect)frameRectForContentRect:(NSRect)rect;
- (NSRect)contentRectForFrameRect:(NSRect)rect;
@property (copy) NSString *title;
@property (retain) NSView *contentView;
@property (assign) id<NSWindowDelegate> delegate;
@property (readonly) NSRect frame;
@property NSWindowStyleMask styleMask;
@property (readonly) NSInteger windowNumber;
@property (readonly, getter=isVisible) BOOL visible;
@property (readonly, getter=isKeyWindow) BOOL keyWindow;
@property (readonly, getter=isMainWindow) BOOL mainWindow;
@property (readonly, getter=isMiniaturized) BOOL miniaturized;
@property (readonly, getter=isZoomed) BOOL zoomed;
@property (readonly) BOOL canBecomeKeyWindow, canBecomeMainWindow;
@property (getter=isReleasedWhenClosed) BOOL releasedWhenClosed;
@property (retain) NSColor *backgroundColor;
@property (readonly) NSResponder *firstResponder;
@property (assign) NSView *initialFirstResponder;
@property BOOL acceptsMouseMovedEvents;
@property BOOL autorecalculatesKeyViewLoop;
@property NSSize minSize, maxSize, contentMinSize, contentMaxSize;
@property NSWindowLevel level;
@property (getter=isOpaque) BOOL opaque;
@property BOOL hasShadow;
@property CGFloat alphaValue;
@property (getter=isMovableByWindowBackground) BOOL movableByWindowBackground;
@property BOOL viewsNeedDisplay;
@property (readonly) CGFloat backingScaleFactor;
@property (readonly) NSScreen *screen;
@property (readonly, copy) NSString *frameAutosaveName;
@property BOOL titlebarAppearsTransparent;
@property NSInteger titleVisibility;
@property (readonly) NSGraphicsContext *graphicsContext;
@property (readonly) NSEvent *currentEvent;
- (void)setFrame:(NSRect)frame display:(BOOL)display;
- (void)setFrame:(NSRect)frame display:(BOOL)display animate:(BOOL)animate;
- (void)setFrameOrigin:(NSPoint)origin;
- (void)setFrameTopLeftPoint:(NSPoint)point;
- (void)setContentSize:(NSSize)size;
- (void)center;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)orderFrontRegardless;
- (void)orderBack:(id)sender;
- (void)orderOut:(id)sender;
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other;
- (void)makeKeyWindow;
- (void)makeMainWindow;
- (void)becomeKeyWindow;
- (void)resignKeyWindow;
- (void)becomeMainWindow;
- (void)resignMainWindow;
- (void)close;
- (void)performClose:(id)sender;
- (void)miniaturize:(id)sender;
- (void)deminiaturize:(id)sender;
- (void)performMiniaturize:(id)sender;
- (void)zoom:(id)sender;
- (void)performZoom:(id)sender;
- (void)toggleFullScreen:(id)sender;
- (BOOL)makeFirstResponder:(NSResponder *)responder;
- (void)selectNextKeyView:(id)sender;
- (void)selectPreviousKeyView:(id)sender;
- (void)selectKeyViewFollowingView:(NSView *)view;
- (void)selectKeyViewPrecedingView:(NSView *)view;
- (void)recalculateKeyViewLoop;
- (void)sendEvent:(NSEvent *)event;
- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart;
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask;
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)date inMode:(NSRunLoopMode)mode
                           dequeue:(BOOL)dequeue;
- (void)display;
- (void)displayIfNeeded;
- (void)update;
- (void)invalidateShadow;
- (NSPoint)mouseLocationOutsideOfEventStream;
- (NSRect)convertRectToScreen:(NSRect)rect;
- (NSRect)convertRectFromScreen:(NSRect)rect;
- (NSPoint)convertPointToScreen:(NSPoint)point;
- (NSPoint)convertPointFromScreen:(NSPoint)point;
- (void)setDefaultButtonCell:(id)cell;
- (BOOL)setFrameUsingName:(NSString *)name;
- (BOOL)setFrameAutosaveName:(NSString *)name;
- (void)setTitleWithRepresentedFilename:(NSString *)path;
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)point;
@end
APPKIT_EXTERN NSNotificationName const NSWindowWillCloseNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidResizeNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidMoveNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidBecomeKeyNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidResignKeyNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidBecomeMainNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidResignMainNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidMiniaturizeNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidDeminiaturizeNotification;

@interface NSPanel : NSWindow
@property (getter=isFloatingPanel) BOOL floatingPanel;
@property BOOL becomesKeyOnlyIfNeeded;
@property BOOL worksWhenModal;
@end

/* ---- screens ---------------------------------------------------------------------- */

@interface NSScreen : NSObject
@property (class, readonly) NSScreen *mainScreen;
@property (class, readonly) NSArray<NSScreen *> *screens;
@property (readonly) NSRect frame, visibleFrame;
@property (readonly) CGFloat backingScaleFactor;
@property (readonly, copy) NSString *localizedName;
@property (readonly, copy) NSDictionary *deviceDescription;
@end

/* ---- menus ------------------------------------------------------------------------ */

/* Menus are kept, and their key equivalents (Command-Q and the like) work;
 * Ferry doesn't show a menu bar yet. */
@interface NSMenuItem : NSObject <NSCopying>
+ (NSMenuItem *)separatorItem;
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
@property (copy) NSString *title;
@property SEL action;
@property (assign) id target;
@property (copy) NSString *keyEquivalent;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property NSInteger tag;
@property NSControlStateValue state;
@property (getter=isEnabled) BOOL enabled;
@property (getter=isHidden) BOOL hidden;
@property (retain) NSMenu *submenu;
@property (readonly) BOOL hasSubmenu;
@property (readonly, assign) NSMenu *menu;
@property (readonly, getter=isSeparatorItem) BOOL separatorItem;
@property (retain) id representedObject;
@property (retain) NSImage *image;
@property NSInteger indentationLevel;
@property (copy) NSString *toolTip;
@end

@interface NSMenu : NSObject <NSCopying>
- (instancetype)initWithTitle:(NSString *)title;
@property (copy) NSString *title;
@property (readonly, copy) NSArray<NSMenuItem *> *itemArray;
@property (readonly) NSInteger numberOfItems;
@property (assign) NSMenu *supermenu;
@property BOOL autoenablesItems;
@property (assign) id delegate;
- (void)addItem:(NSMenuItem *)item;
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
- (void)insertItem:(NSMenuItem *)item atIndex:(NSInteger)index;
- (NSMenuItem *)insertItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key
                            atIndex:(NSInteger)index;
- (void)removeItem:(NSMenuItem *)item;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;
- (NSMenuItem *)itemAtIndex:(NSInteger)index;
- (NSMenuItem *)itemWithTitle:(NSString *)title;
- (NSMenuItem *)itemWithTag:(NSInteger)tag;
- (NSInteger)indexOfItem:(NSMenuItem *)item;
- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (void)setSubmenu:(NSMenu *)menu forItem:(NSMenuItem *)item;
- (BOOL)performKeyEquivalent:(NSEvent *)event;
- (void)update;
@end

@protocol NSMenuItemValidation <NSObject>
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

/* ---- the application ----------------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSApplicationActivationPolicy) {
    NSApplicationActivationPolicyRegular = 0, NSApplicationActivationPolicyAccessory = 1,
    NSApplicationActivationPolicyProhibited = 2,
};
typedef NS_ENUM(NSUInteger, NSApplicationTerminateReply) {
    NSTerminateCancel = 0, NSTerminateNow = 1, NSTerminateLater = 2,
};
typedef NSInteger NSModalResponse;
enum { NSModalResponseStop = -1000, NSModalResponseAbort = -1001, NSModalResponseContinue = -1002,
       NSModalResponseOK = 1, NSModalResponseCancel = 0 };

@protocol NSApplicationDelegate <NSObject>
@optional
- (void)applicationWillFinishLaunching:(NSNotification *)notification;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
- (void)applicationDidResignActive:(NSNotification *)notification;
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename;
- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames;
@end

@interface NSApplication : NSResponder
+ (NSApplication *)sharedApplication;
@property (assign) id<NSApplicationDelegate> delegate;
@property (retain) NSMenu *mainMenu;
@property (assign) NSMenu *windowsMenu, *servicesMenu, *helpMenu;
@property (readonly, copy) NSArray<NSWindow *> *windows;
@property (readonly) NSWindow *keyWindow, *mainWindow;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly, getter=isActive) BOOL active;
@property (readonly) NSEvent *currentEvent;
@property (retain) NSImage *applicationIconImage;
@property (readonly) NSWindow *modalWindow;
- (void)finishLaunching;
- (void)run;
- (void)stop:(id)sender;
- (void)terminate:(id)sender;
- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate;
- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)date inMode:(NSRunLoopMode)mode
                           dequeue:(BOOL)dequeue;
- (void)discardEventsMatchingMask:(NSEventMask)mask beforeEvent:(NSEvent *)event;
- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart;
- (void)sendEvent:(NSEvent *)event;
- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender;
- (id)targetForAction:(SEL)action;
- (id)targetForAction:(SEL)action to:(id)target from:(id)sender;
- (BOOL)tryToPerform:(SEL)action with:(id)object;
- (void)updateWindows;
- (NSWindow *)windowWithWindowNumber:(NSInteger)number;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy;
- (NSApplicationActivationPolicy)activationPolicy;
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)activate;
- (void)deactivate;
- (void)hide:(id)sender;
- (void)unhide:(id)sender;
- (void)hideOtherApplications:(id)sender;
- (void)unhideAllApplications:(id)sender;
- (void)arrangeInFront:(id)sender;
- (void)miniaturizeAll:(id)sender;
- (void)orderFrontStandardAboutPanel:(id)sender;
- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)options;
- (NSInteger)requestUserAttention:(NSInteger)type;
- (NSModalResponse)runModalForWindow:(NSWindow *)window;
- (void)stopModal;
- (void)stopModalWithCode:(NSModalResponse)code;
- (void)abortModal;
@end
APPKIT_EXTERN NSApplication *NSApp;
int NSApplicationMain(int argc, const char *argv[]);
APPKIT_EXTERN NSNotificationName const NSApplicationWillFinishLaunchingNotification;
APPKIT_EXTERN NSNotificationName const NSApplicationDidFinishLaunchingNotification;
APPKIT_EXTERN NSNotificationName const NSApplicationWillTerminateNotification;
APPKIT_EXTERN NSNotificationName const NSApplicationDidBecomeActiveNotification;
APPKIT_EXTERN NSNotificationName const NSApplicationDidResignActiveNotification;

#endif
