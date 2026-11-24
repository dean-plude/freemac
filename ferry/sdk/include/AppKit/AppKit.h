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
#import <QuartzCore/QuartzCore.h>

#define APPKIT_EXTERN extern
#define NS_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))

@class NSApplication, NSWindow, NSView, NSEvent, NSColor, NSFont, NSMenu, NSMenuItem, NSScreen;
@class NSGraphicsContext, NSBitmapImageRep, NSParagraphStyle, NSBezierPath, NSCursor, NSImage;
@class NSWindowController, NSViewController, NSStoryboard;

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
@property (readonly) NSUndoManager *undoManager;
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
+ (NSColor *)colorWithPatternImage:(NSImage *)image;
@property (readonly) NSImage *patternImage;
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
+ (NSFont *)menuBarFontOfSize:(CGFloat)size;
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
/* How editing ended, in an end-of-editing notification's user info. */
typedef NS_ENUM(NSInteger, NSTextMovement) {
    NSTextMovementReturn = 0x10, NSTextMovementTab = 0x11, NSTextMovementBacktab = 0x12,
    NSTextMovementLeft = 0x13, NSTextMovementRight = 0x14, NSTextMovementUp = 0x15, NSTextMovementDown = 0x16,
    NSTextMovementCancel = 0x17, NSTextMovementOther = 0,
};
#define NSIllegalTextMovement 0
#define NSReturnTextMovement NSTextMovementReturn
#define NSTabTextMovement NSTextMovementTab
#define NSBacktabTextMovement NSTextMovementBacktab
#define NSLeftTextMovement NSTextMovementLeft
#define NSRightTextMovement NSTextMovementRight
#define NSUpTextMovement NSTextMovementUp
#define NSDownTextMovement NSTextMovementDown
#define NSCancelTextMovement NSTextMovementCancel
#define NSOtherTextMovement NSTextMovementOther
typedef NS_ENUM(NSUInteger, NSLineBreakMode) {
    NSLineBreakByWordWrapping = 0, NSLineBreakByCharWrapping = 1, NSLineBreakByClipping = 2,
    NSLineBreakByTruncatingHead = 3, NSLineBreakByTruncatingTail = 4, NSLineBreakByTruncatingMiddle = 5,
};
typedef NS_ENUM(NSInteger, NSWritingDirection) {
    NSWritingDirectionNatural = -1, NSWritingDirectionLeftToRight = 0, NSWritingDirectionRightToLeft = 1,
};

#ifdef FERRY_APPKIT_BUILD
@interface NSParagraphStyle : GParagraphStyle <NSCopying, NSMutableCopying, NSCoding>
#else
@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying, NSCoding>
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

/* Vector images from PDF files, drawn by this system's Poppler. */
@interface NSPDFImageRep : NSImageRep
+ (instancetype)imageRepWithData:(NSData *)data;
- (instancetype)initWithData:(NSData *)data;
@property (readonly) NSData *PDFRepresentation;
@property (readonly) NSRect bounds;
@property (readonly) NSInteger pageCount;
@property NSInteger currentPage;
@end

/* An image drawn by a block each time it is drawn. */
@interface NSCustomImageRep : NSImageRep
- (instancetype)initWithSize:(NSSize)size flipped:(BOOL)flipped drawingHandler:(BOOL (^)(NSRect dstRect))handler;
@property (readonly) BOOL (^drawingHandler)(NSRect dstRect);
@end

typedef NSString *NSImageName;
APPKIT_EXTERN NSImageName const NSImageNameAddTemplate, NSImageNameRemoveTemplate, NSImageNameStopProgressTemplate,
    NSImageNameGoLeftTemplate, NSImageNameGoRightTemplate, NSImageNameGoBackTemplate,
    NSImageNameGoForwardTemplate, NSImageNameMenuOnStateTemplate, NSImageNameMenuMixedStateTemplate,
    NSImageNameRefreshTemplate, NSImageNameActionTemplate, NSImageNameApplicationIcon, NSImageNameCaution,
    NSImageNameInfo, NSImageNameStatusAvailable, NSImageNameStatusUnavailable, NSImageNameStatusPartiallyAvailable,
    NSImageNameStatusNone, NSImageNameFolder, NSImageNameTouchBarAddTemplate;
typedef NS_ENUM(NSUInteger, NSImageCacheMode) {
    NSImageCacheDefault, NSImageCacheAlways, NSImageCacheBySize, NSImageCacheNever,
};
typedef NSString *NSImageHintKey;
APPKIT_EXTERN NSImageHintKey const NSImageHintCTM, NSImageHintInterpolation;
APPKIT_EXTERN NSString *const NSImageCompressionFactor;

/* Images: read from PNG, JPEG, GIF, TIFF, BMP, ICO and ICNS files (by this
 * system's GdkPixbuf) and from PDF files (vector, by Poppler), drawn by a
 * block, or drawn into with lockFocus. Images named in an app's resources
 * are found by imageNamed:, as are a few standard template images, which
 * Ferry draws itself. */
@interface NSImage : NSObject <NSCopying, NSCoding>
+ (NSImage *)imageNamed:(NSImageName)name;
+ (instancetype)imageWithSize:(NSSize)size flipped:(BOOL)flipped drawingHandler:(BOOL (^)(NSRect dstRect))handler;
+ (NSArray<NSString *> *)imageTypes;
+ (NSArray<NSString *> *)imageUnfilteredTypes;
+ (NSArray<NSString *> *)imageFileTypes;
- (instancetype)initWithSize:(NSSize)size;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (instancetype)initWithContentsOfURL:(NSURL *)url;
- (instancetype)initByReferencingFile:(NSString *)path;
- (instancetype)initByReferencingURL:(NSURL *)url;
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithCGImage:(CGImageRef)image size:(NSSize)size;
- (BOOL)setName:(NSImageName)name;
- (NSImageName)name;
@property NSSize size;
@property (getter=isTemplate) BOOL template;
@property (readonly, getter=isValid) BOOL valid;
@property (copy) NSString *accessibilityDescription;
@property (copy) NSColor *backgroundColor;
@property NSImageCacheMode cacheMode;
@property BOOL matchesOnMultipleResolution, usesEPSOnResolutionMismatch, prefersColorMatch;
@property NSRect alignmentRect;
@property (getter=isFlipped) BOOL flipped; /* deprecated on a Mac; kept */
@property BOOL scalesWhenResized;
@property (readonly, copy) NSArray<NSImageRep *> *representations;
- (void)addRepresentation:(NSImageRep *)rep;
- (void)addRepresentations:(NSArray<NSImageRep *> *)reps;
- (void)removeRepresentation:(NSImageRep *)rep;
- (NSImageRep *)bestRepresentationForRect:(NSRect)rect context:(NSGraphicsContext *)context
                                    hints:(NSDictionary *)hints;
- (void)drawAtPoint:(NSPoint)point fromRect:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)f;
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)f;
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)f
    respectFlipped:(BOOL)respect hints:(NSDictionary *)hints;
- (void)drawInRect:(NSRect)rect;
- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op;
- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op fraction:(CGFloat)f;
- (void)dissolveToPoint:(NSPoint)point fraction:(CGFloat)f;
- (void)lockFocus;
- (void)lockFocusFlipped:(BOOL)flipped;
- (void)unlockFocus;
- (void)recache;
- (CGImageRef)CGImageForProposedRect:(NSRect *)rect context:(NSGraphicsContext *)context hints:(NSDictionary *)hints;
@property (readonly) NSData *TIFFRepresentation;
@end

@interface NSImageRep (FerryFiles)
+ (Class)imageRepClassForData:(NSData *)data;
+ (instancetype)imageRepWithContentsOfFile:(NSString *)path;
+ (NSArray<NSImageRep *> *)imageRepsWithContentsOfFile:(NSString *)path;
+ (NSArray<NSImageRep *> *)imageRepsWithData:(NSData *)data;
@end

@interface NSBitmapImageRep (FerryFiles)
+ (instancetype)imageRepWithData:(NSData *)data;
- (instancetype)initWithData:(NSData *)data;
@property (readonly) NSData *TIFFRepresentation;
@end

@interface NSBundle (NSBundleImageExtension)
- (NSImage *)imageForResource:(NSImageName)name;
- (NSString *)pathForImageResource:(NSImageName)name;
- (NSURL *)URLForImageResource:(NSImageName)name;
@end

/* ---- views ----------------------------------------------------------------------- */

typedef NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions) {
    NSViewNotSizable = 0, NSViewMinXMargin = 1, NSViewWidthSizable = 2, NSViewMaxXMargin = 4,
    NSViewMinYMargin = 8, NSViewHeightSizable = 16, NSViewMaxYMargin = 32,
};
typedef NS_ENUM(NSUInteger, NSFocusRingType) { NSFocusRingTypeDefault = 0, NSFocusRingTypeNone = 1, NSFocusRingTypeExterior = 2 };

typedef NSString *NSUserInterfaceItemIdentifier;

typedef NS_ENUM(NSInteger, NSViewLayerContentsRedrawPolicy) {
    NSViewLayerContentsRedrawNever = 0, NSViewLayerContentsRedrawOnSetNeedsDisplay = 1,
    NSViewLayerContentsRedrawDuringViewResize = 2, NSViewLayerContentsRedrawBeforeViewResize = 3,
    NSViewLayerContentsRedrawCrossfade = 4,
};

/* Objects whose properties an animator proxy animates: setting a property
 * through [object animator] inside an NSAnimationContext group (or alone,
 * over a quarter of a second) moves it there over the group's duration. */
@protocol NSAnimatablePropertyContainer
- (instancetype)animator;
@property (copy) NSDictionary<NSString *, id> *animations;
- (id)animationForKey:(NSString *)key;
+ (id)defaultAnimationForKey:(NSString *)key;
@end

@interface NSView : NSResponder <NSAnimatablePropertyContainer>
- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
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
@property (strong) CALayer *layer;
- (CALayer *)makeBackingLayer;
@property (readonly) BOOL wantsUpdateLayer;
- (void)updateLayer;
@property NSViewLayerContentsRedrawPolicy layerContentsRedrawPolicy;
@property BOOL canDrawSubviewsIntoLayer;
@property CGFloat alphaValue;
@property (copy) NSString *toolTip;
@property (copy) NSUserInterfaceItemIdentifier identifier;
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

/* A group of animated changes, as CATransaction groups a layer's: the
 * duration, timing function and completion handler set on the current
 * context apply to the animator proxies' changes made in the group. */
@interface NSAnimationContext : NSObject
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *context))changes completionHandler:(void (^)(void))completionHandler;
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *context))changes;
+ (void)beginGrouping;
+ (void)endGrouping;
+ (NSAnimationContext *)currentContext;
@property NSTimeInterval duration;
@property (strong) CAMediaTimingFunction *timingFunction;
@property (copy) void (^completionHandler)(void);
@property BOOL allowsImplicitAnimation;
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

@class NSCell;
typedef NS_ENUM(NSUInteger, NSImageScaling) {
    NSImageScaleProportionallyDown = 0, NSImageScaleAxesIndependently = 1, NSImageScaleNone = 2,
    NSImageScaleProportionallyUpOrDown = 3,
};
typedef NS_ENUM(NSUInteger, NSImageAlignment) {
    NSImageAlignCenter = 0, NSImageAlignTop = 1, NSImageAlignTopLeft = 2, NSImageAlignTopRight = 3,
    NSImageAlignLeft = 4, NSImageAlignBottom = 5, NSImageAlignBottomLeft = 6, NSImageAlignBottomRight = 7,
    NSImageAlignRight = 8,
};
typedef NS_ENUM(NSUInteger, NSImageFrameStyle) {
    NSImageFrameNone = 0, NSImageFramePhoto = 1, NSImageFrameGrayBezel = 2, NSImageFrameGroove = 3,
    NSImageFrameButton = 4,
};
typedef NS_ENUM(NSUInteger, NSCellImagePosition) {
    NSNoImage = 0, NSImageOnly = 1, NSImageLeft = 2, NSImageRight = 3, NSImageBelow = 4, NSImageAbove = 5,
    NSImageOverlaps = 6, NSImageLeading = 7, NSImageTrailing = 8,
};
@interface NSControl : NSView
@property (retain) __kindof NSCell *cell;
@property (class) Class cellClass;
@property (assign) id target;
@property SEL action;
- (NSInteger)sendActionOn:(NSInteger)mask;
@property NSInteger tag;
@property (getter=isEnabled) BOOL enabled;
/* Shows the value with stringForObjectValue: and reads what is typed with
 * getObjectValue:forString:errorDescription: (Ferry 0.17.0). */
@property (retain) __kindof NSFormatter *formatter;
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
- (BOOL)abortEditing;
- (void)validateEditing;
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

/* Cells. Ferry's controls draw and keep their state themselves; a cell is
 * the record of a control's settings that nib files store. */
typedef NS_ENUM(NSInteger, NSBackgroundStyle) {
    NSBackgroundStyleNormal = 0, NSBackgroundStyleEmphasized = 1, NSBackgroundStyleRaised = 2,
    NSBackgroundStyleLowered = 3, NSBackgroundStyleLight = 0, NSBackgroundStyleDark = 1,
};
@interface NSCell : NSObject <NSCopying, NSCoding>
- (instancetype)initTextCell:(NSString *)string;
- (instancetype)initImageCell:(NSImage *)image;
@property (copy) id objectValue;
@property (copy) NSString *stringValue, *title;
@property (copy) NSAttributedString *attributedStringValue;
@property (readonly) int intValue;
@property (readonly) NSInteger integerValue;
@property (readonly) double doubleValue;
@property (retain) NSFont *font;
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property BOOL wraps;
@property (getter=isEnabled) BOOL enabled;
@property (getter=isEditable) BOOL editable;
@property (getter=isSelectable) BOOL selectable;
@property (getter=isBordered) BOOL bordered;
@property (getter=isBezeled) BOOL bezeled;
@property (getter=isScrollable) BOOL scrollable;
@property (getter=isHighlighted) BOOL highlighted;
@property (getter=isContinuous) BOOL continuous;
@property NSControlStateValue state;
@property NSInteger tag;
@property NSControlSize controlSize;
@property (assign) id target;
@property SEL action;
@property (assign) NSView *controlView;
@property (retain) NSImage *image;
@property NSBackgroundStyle backgroundStyle;
@property (readonly) NSBackgroundStyle interiorBackgroundStyle;
@property (retain) __kindof NSFormatter *formatter;
@end

@interface NSActionCell : NSCell
@end

@interface NSButtonCell : NSActionCell
@property (copy) NSString *alternateTitle, *keyEquivalent;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property NSBezelStyle bezelStyle;
@property (getter=isTransparent) BOOL transparent;
@property BOOL allowsMixedState;
@property (retain) NSImage *alternateImage;
- (void)setButtonType:(NSButtonType)type;
@end

@interface NSTextFieldCell : NSActionCell
@property (copy) NSString *placeholderString;
@property (copy) NSAttributedString *placeholderAttributedString;
@property BOOL drawsBackground;
@property (retain) NSColor *backgroundColor, *textColor;
@end

@interface NSSecureTextFieldCell : NSTextFieldCell
@end

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
@property (retain) NSImage *image, *alternateImage;
@property NSCellImagePosition imagePosition;
@property NSImageScaling imageScaling;
@property BOOL imageHugsTitle;
+ (instancetype)buttonWithImage:(NSImage *)image target:(id)target action:(SEL)action;
+ (instancetype)buttonWithTitle:(NSString *)title image:(NSImage *)image target:(id)target action:(SEL)action;
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
@property BOOL allowsEditingTextAttributes, importsGraphics; /* kept; text is plain for now */
- (void)selectText:(id)sender;
@end
@interface NSImageCell : NSCell
@property NSImageScaling imageScaling;
@property NSImageAlignment imageAlignment;
@property NSImageFrameStyle imageFrameStyle;
@end

/* Shows an image, scaled and placed as its settings say. Template images
 * are drawn in the label colour, or the content tint colour if set. */
@interface NSImageView : NSControl
+ (instancetype)imageViewWithImage:(NSImage *)image;
@property (retain) NSImage *image;
@property NSImageScaling imageScaling;
@property NSImageAlignment imageAlignment;
@property NSImageFrameStyle imageFrameStyle;
@property (getter=isEditable) BOOL editable;
@property BOOL animates, allowsCutCopyPaste;
@property (retain) NSColor *contentTintColor;
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
/* fieldEditor is nil in Ferry: a text field edits its own text */
- (BOOL)control:(NSControl *)control textShouldBeginEditing:(id)fieldEditor;
- (BOOL)control:(NSControl *)control textShouldEndEditing:(id)fieldEditor;
/* The control's formatter couldn't read what was typed: YES keeps the
 * string as the value, NO (or no answer) keeps the editing going. */
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string
    errorDescription:(NSString *)error;
- (void)control:(NSControl *)control didFailToValidatePartialString:(NSString *)string
    errorDescription:(NSString *)error;
- (BOOL)control:(NSControl *)control isValidObject:(id)obj;
@end
@protocol NSTextFieldDelegate <NSControlTextEditingDelegate>
@end
APPKIT_EXTERN NSNotificationName const NSControlTextDidBeginEditingNotification;
APPKIT_EXTERN NSNotificationName const NSControlTextDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSControlTextDidEndEditingNotification;
/* the key of an end-of-editing notification's NSTextMovement */
APPKIT_EXTERN NSString *const NSTextMovementUserInfoKey;

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
- (void)windowWillBeginSheet:(NSNotification *)notification;
- (void)windowDidEndSheet:(NSNotification *)notification;
- (NSRect)window:(NSWindow *)window willPositionSheet:(NSWindow *)sheet usingRect:(NSRect)rect;
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window;
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
+ (instancetype)windowWithContentViewController:(NSViewController *)vc;
@property (assign) NSWindowController *windowController;
@property (retain) NSViewController *contentViewController;
@property (getter=isDocumentEdited) BOOL documentEdited;
- (void)setContentBorderThickness:(CGFloat)thickness forEdge:(NSRectEdge)edge;
- (CGFloat)contentBorderThicknessForEdge:(NSRectEdge)edge;
- (void)setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
- (BOOL)autorecalculatesContentBorderThicknessForEdge:(NSRectEdge)edge;
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

@protocol NSMenuDelegate <NSObject>
@optional
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (void)menuWillOpen:(NSMenu *)menu;
- (void)menuDidClose:(NSMenu *)menu;
- (NSInteger)numberOfItemsInMenu:(NSMenu *)menu;
- (BOOL)menu:(NSMenu *)menu updateItem:(NSMenuItem *)item atIndex:(NSInteger)index shouldCancel:(BOOL)shouldCancel;
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
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls;
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag;
- (NSError *)application:(NSApplication *)application willPresentError:(NSError *)error;
@end

@interface NSApplication : NSResponder
+ (NSApplication *)sharedApplication;
@property (assign) id<NSApplicationDelegate> delegate;
@property (retain) NSMenu *mainMenu;
@property (assign) NSMenu *windowsMenu, *servicesMenu, *helpMenu;
@property (assign) id servicesProvider;
- (void)registerServicesMenuSendTypes:(NSArray *)sendTypes returnTypes:(NSArray *)returnTypes;
@property (readonly, copy) NSArray<NSWindow *> *windows;
@property (readonly) NSWindow *keyWindow, *mainWindow;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly, getter=isActive) BOOL active;
@property (readonly) NSEvent *currentEvent;
- (void)reportException:(NSException *)exception;
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

/* ---- nibs ---------------------------------------------------------------------------- */

#ifndef IBOutlet
#define IBOutlet
#endif
#ifndef IBAction
#define IBAction void
#endif
#ifndef IBInspectable
#define IBInspectable
#endif

/* ---- controllers ------------------------------------------------------------------- */

typedef NSString *NSNibName;

/* Loads its window from a nib (as File's Owner) the first time the window
 * is asked for, and follows the window in the responder chain. */
@interface NSWindowController : NSResponder <NSCoding>
- (instancetype)initWithWindow:(NSWindow *)window;
- (instancetype)initWithWindowNibName:(NSNibName)name;
- (instancetype)initWithWindowNibName:(NSNibName)name owner:(id)owner;
- (instancetype)initWithWindowNibPath:(NSString *)path owner:(id)owner;
@property (retain) NSWindow *window;
@property (readonly, copy) NSNibName windowNibName;
@property (readonly, copy) NSString *windowNibPath;
@property (readonly, assign) id owner;
@property (readonly, getter=isWindowLoaded) BOOL windowLoaded;
@property (copy) NSString *windowFrameAutosaveName;
@property BOOL shouldCascadeWindows, shouldCloseDocument;
@property (assign) id document;
@property (retain) NSViewController *contentViewController;
@property (readonly) NSStoryboard *storyboard;
- (void)loadWindow;
- (void)windowWillLoad;
- (void)windowDidLoad;
- (IBAction)showWindow:(id)sender;
- (void)close;
- (void)dismissController:(id)sender;
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName;
- (void)synchronizeWindowTitleWithDocumentName;
- (void)setDocumentEdited:(BOOL)edited;
@end

/* Loads its view from a nib (named after the class unless given) the first
 * time the view is asked for, and sits between the view and its superview
 * in the responder chain. Sheets and popovers are shown as windows. */
/* Controllers for bindings: one object (NSObjectController), an array of
 * them (NSArrayController), and the user's defaults by key
 * (NSUserDefaultsController). */
@interface NSController : NSObject <NSCoding>
- (BOOL)commitEditing;
- (void)discardEditing;
@property (readonly, getter=isEditing) BOOL editing;
- (void)objectDidBeginEditing:(id)editor;
- (void)objectDidEndEditing:(id)editor;
@end
@interface NSUserDefaultsController : NSController
@property (class, readonly) NSUserDefaultsController *sharedUserDefaultsController;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults initialValues:(NSDictionary *)initialValues;
@property (readonly) NSUserDefaults *defaults;
@property (readonly) id values;
@property (copy) NSDictionary *initialValues;
@property BOOL appliesImmediately;
@property (readonly) BOOL hasUnappliedChanges;
- (void)save:(id)sender;
- (void)revert:(id)sender;
- (void)revertToInitialValues:(id)sender;
@end
/* Holds one content object; bind to "selection.someKey" to reach its keys
 * (NSNoSelectionMarker while there is no content). */
@interface NSObjectController : NSController
- (instancetype)initWithContent:(id)content;
@property (retain) id content;
@property (readonly, retain) id selection;
@property (readonly, copy) NSArray *selectedObjects;
@property (assign) Class objectClass;
@property BOOL automaticallyPreparesContent;
@property (getter=isEditable) BOOL editable;
@property (readonly) BOOL canAdd, canRemove;
/* Core Data's entity, kept from a nib; there is no Core Data (Ferry 0.20.0). */
@property (copy) NSString *entityName;
@property (retain) id managedObjectContext;
- (id)newObject;
- (void)prepareContent;
- (void)addObject:(id)object;
- (void)removeObject:(id)object;
- (IBAction)add:(id)sender;
- (IBAction)remove:(id)sender;
@end
/* An array (or set) of content objects, arranged (filtered and sorted) for
 * a table, with a selection of them (Ferry 0.18.0). "selection.someKey" is
 * the value the selected objects share, or NSMultipleValuesMarker. */
@interface NSArrayController : NSObjectController
- (void)rearrangeObjects;
- (NSArray *)arrangeObjects:(NSArray *)objects;
@property (readonly, retain) id arrangedObjects;
@property BOOL automaticallyRearrangesObjects;
@property (readonly, copy) NSArray<NSString *> *automaticRearrangementKeyPaths;
- (void)didChangeArrangementCriteria;
@property (copy) NSArray<NSSortDescriptor *> *sortDescriptors;
@property (retain) NSPredicate *filterPredicate;
@property BOOL clearsFilterPredicateOnInsertion;
@property BOOL avoidsEmptySelection, preservesSelection, selectsInsertedObjects, alwaysUsesMultipleValuesMarker;
- (BOOL)setSelectionIndexes:(NSIndexSet *)indexes;
@property (readonly, copy) NSIndexSet *selectionIndexes;
- (BOOL)setSelectionIndex:(NSUInteger)index;
@property (readonly) NSUInteger selectionIndex;
- (BOOL)addSelectionIndexes:(NSIndexSet *)indexes;
- (BOOL)removeSelectionIndexes:(NSIndexSet *)indexes;
- (BOOL)setSelectedObjects:(NSArray *)objects;
- (BOOL)addSelectedObjects:(NSArray *)objects;
- (BOOL)removeSelectedObjects:(NSArray *)objects;
@property (readonly) BOOL canSelectNext, canSelectPrevious, canInsert;
- (IBAction)selectNext:(id)sender;
- (IBAction)selectPrevious:(id)sender;
- (IBAction)insert:(id)sender;
- (void)addObjects:(NSArray *)objects;
- (void)insertObject:(id)object atArrangedObjectIndex:(NSUInteger)index;
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexes:(NSIndexSet *)indexes;
- (void)removeObjectAtArrangedObjectIndex:(NSUInteger)index;
- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)indexes;
- (void)removeObjects:(NSArray *)objects;
@end
/* A node of a tree (Ferry 0.19.0): an object it stands for, its parent and
 * its children. A tree controller's arrangedObjects are made of them, and
 * an outline view bound to one shows them as its items. */
@interface NSTreeNode : NSObject
+ (instancetype)treeNodeWithRepresentedObject:(id)modelObject;
- (instancetype)initWithRepresentedObject:(id)modelObject;
@property (readonly, retain) id representedObject;
@property (readonly, copy) NSIndexPath *indexPath;
@property (readonly, getter=isLeaf) BOOL leaf;
@property (readonly, copy) NSArray<NSTreeNode *> *childNodes;
@property (readonly) NSMutableArray<NSTreeNode *> *mutableChildNodes;
@property (readonly, assign) NSTreeNode *parentNode;
- (NSTreeNode *)descendantNodeAtIndexPath:(NSIndexPath *)indexPath;
- (void)sortWithSortDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors recursively:(BOOL)recursively;
@end
/* A tree of content objects (Ferry 0.19.0): each object's children are
 * found at childrenKeyPath; arrangedObjects answers childNodes and
 * descendantNodeAtIndexPath:, a tree of NSTreeNode sorted level by level;
 * the selection is a list of index paths. */
@interface NSTreeController : NSObjectController
@property (copy) NSString *childrenKeyPath, *countKeyPath, *leafKeyPath;
- (NSString *)childrenKeyPathForNode:(NSTreeNode *)node;
- (NSString *)countKeyPathForNode:(NSTreeNode *)node;
- (NSString *)leafKeyPathForNode:(NSTreeNode *)node;
@property (readonly, retain) id arrangedObjects;
- (void)rearrangeObjects;
@property (copy) NSArray<NSSortDescriptor *> *sortDescriptors;
@property BOOL avoidsEmptySelection, preservesSelection, selectsInsertedObjects, alwaysUsesMultipleValuesMarker;
@property (readonly, copy) NSArray<NSIndexPath *> *selectionIndexPaths;
- (BOOL)setSelectionIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
@property (readonly, copy) NSIndexPath *selectionIndexPath;
- (BOOL)setSelectionIndexPath:(NSIndexPath *)indexPath;
- (BOOL)addSelectionIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (BOOL)removeSelectionIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
@property (readonly, copy) NSArray<NSTreeNode *> *selectedNodes;
@property (readonly) BOOL canInsert, canInsertChild, canAddChild;
- (IBAction)addChild:(id)sender;
- (IBAction)insert:(id)sender;
- (IBAction)insertChild:(id)sender;
- (void)insertObject:(id)object atArrangedObjectIndexPath:(NSIndexPath *)indexPath;
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (void)removeObjectAtArrangedObjectIndexPath:(NSIndexPath *)indexPath;
- (void)removeObjectsAtArrangedObjectIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (void)moveNode:(NSTreeNode *)node toIndexPath:(NSIndexPath *)indexPath;
- (void)moveNodes:(NSArray<NSTreeNode *> *)nodes toIndexPath:(NSIndexPath *)startingIndexPath;
@end
/* One key and its value, as an NSDictionaryController arranges them. */
@protocol NSDictionaryControllerKeyValuePair
@property (copy) NSString *key;
@property (retain) id value;
@property (readonly, copy) NSString *localizedKey;
@property (readonly, getter=isExplicitlyIncluded) BOOL explicitlyIncluded;
@end
/* A dictionary shown as an array of key-value pairs (Ferry 0.19.0). */
@interface NSDictionaryController : NSArrayController
- (id<NSDictionaryControllerKeyValuePair>)newObject;
@property (copy) NSString *initialKey;
@property (retain) id initialValue;
@property (copy) NSArray<NSString *> *includedKeys, *excludedKeys;
@property (copy) NSDictionary<NSString *, NSString *> *localizedKeyDictionary;
@property (copy) NSString *localizedKeyTable;
@end
/* Index paths as collection views use them. */
@interface NSIndexPath (NSCollectionViewAdditions)
+ (NSIndexPath *)indexPathForItem:(NSInteger)item inSection:(NSInteger)section;
@property (readonly) NSInteger item, section;
@end
/* What a controller's selection answers when there is no single value. */
APPKIT_EXTERN id NSMultipleValuesMarker, NSNoSelectionMarker, NSNotApplicableMarker;
APPKIT_EXTERN BOOL NSIsControllerMarker(id object);

@interface NSViewController : NSResponder <NSCoding>
- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle;
@property (readonly, copy) NSNibName nibName;
@property (readonly, retain) NSBundle *nibBundle;
@property (retain) NSView *view;
@property (readonly) NSView *viewIfLoaded;
@property (readonly, getter=isViewLoaded) BOOL viewLoaded;
@property (copy) NSString *title;
@property (retain) id representedObject;
@property NSSize preferredContentSize;
@property (copy) NSArray<NSViewController *> *childViewControllers;
@property (readonly, assign) NSViewController *parentViewController;
@property (readonly, assign) NSViewController *presentingViewController;
@property (readonly) NSArray<NSViewController *> *presentedViewControllers;
@property (readonly) NSStoryboard *storyboard;
- (void)loadView;
- (void)loadViewIfNeeded;
- (void)viewDidLoad;
- (void)viewWillAppear;
- (void)viewDidAppear;
- (void)viewWillDisappear;
- (void)viewDidDisappear;
- (void)updateViewConstraints;
- (void)viewWillLayout;
- (void)viewDidLayout;
- (void)addChildViewController:(NSViewController *)child;
- (void)insertChildViewController:(NSViewController *)child atIndex:(NSInteger)index;
- (void)removeChildViewControllerAtIndex:(NSInteger)index;
- (void)removeFromParentViewController;
- (void)presentViewControllerAsSheet:(NSViewController *)vc;
- (void)presentViewControllerAsModalWindow:(NSViewController *)vc;
- (void)presentViewController:(NSViewController *)vc asPopoverRelativeToRect:(NSRect)rect ofView:(NSView *)view
                preferredEdge:(NSRectEdge)edge behavior:(NSInteger)behavior;
- (void)dismissViewController:(NSViewController *)vc;
- (void)dismissController:(id)sender;
@end
#ifndef IB_DESIGNABLE
#define IB_DESIGNABLE
#endif

typedef NSString *NSNibName;

@interface NSNib : NSObject <NSCoding>
- (instancetype)initWithNibNamed:(NSNibName)name bundle:(NSBundle *)bundle;
- (instancetype)initWithNibData:(NSData *)data bundle:(NSBundle *)bundle;
- (instancetype)initWithContentsOfURL:(NSURL *)url;
- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray **)topLevelObjects;
@end

@interface NSBundle (NSNibLoading)
- (BOOL)loadNibNamed:(NSNibName)name owner:(id)owner topLevelObjects:(NSArray **)topLevelObjects;
+ (BOOL)loadNibNamed:(NSString *)name owner:(id)owner;
+ (BOOL)loadNibFile:(NSString *)path externalNameTable:(NSDictionary *)context withZone:(NSZone *)zone;
@end

@interface NSObject (NSNibAwaking)
- (void)awakeFromNib;
- (void)prepareForInterfaceBuilder;
@end

/* Cocoa bindings (NSKeyValueBinding.m): a binding follows its key path by
 * key-value observing and writes the user's changes back to it. */
APPKIT_EXTERN NSString *const NSObservedObjectKey, *const NSObservedKeyPathKey, *const NSOptionsKey;
APPKIT_EXTERN NSString *const NSValueBinding, *const NSEnabledBinding, *const NSHiddenBinding, *const NSTitleBinding,
    *const NSContentBinding, *const NSSelectedIndexBinding, *const NSToolTipBinding, *const NSSelectedObjectBinding,
    *const NSSelectedValueBinding, *const NSSelectedTagBinding, *const NSContentValuesBinding,
    *const NSContentObjectBinding, *const NSContentObjectsBinding, *const NSEditableBinding,
    *const NSMinValueBinding, *const NSMaxValueBinding, *const NSTextColorBinding, *const NSImageBinding,
    *const NSAlternateTitleBinding, *const NSFontBinding, *const NSContentArrayBinding, *const NSContentSetBinding,
    *const NSSelectionIndexesBinding, *const NSSortDescriptorsBinding, *const NSFilterPredicateBinding,
    *const NSHeaderTitleBinding, *const NSMaxWidthBinding, *const NSMinWidthBinding, *const NSWidthBinding,
    *const NSSelectionIndexPathsBinding, *const NSContentDictionaryBinding, *const NSIncludedKeysBinding,
    *const NSExcludedKeysBinding, *const NSInitialKeyBinding, *const NSInitialValueBinding,
    *const NSLocalizedKeyDictionaryBinding;
APPKIT_EXTERN NSString *const NSNullPlaceholderBindingOption, *const NSNoSelectionPlaceholderBindingOption,
    *const NSMultipleValuesPlaceholderBindingOption, *const NSNotApplicablePlaceholderBindingOption,
    *const NSValueTransformerNameBindingOption, *const NSValueTransformerBindingOption,
    *const NSContinuouslyUpdatesValueBindingOption, *const NSRaisesForNotApplicableKeysBindingOption,
    *const NSConditionallySetsEnabledBindingOption, *const NSConditionallySetsEditableBindingOption,
    *const NSAllowsEditingMultipleValuesSelectionBindingOption, *const NSValidatesImmediatelyBindingOption,
    *const NSCreatesSortDescriptorBindingOption, *const NSDeletesObjectsOnRemoveBindingsOption,
    *const NSSelectsAllWhenSettingContentBindingOption, *const NSHandlesContentAsCompoundValueBindingOption;
@interface NSObject (NSKeyValueBindingCreation)
+ (void)exposeBinding:(NSString *)binding;
@property (readonly, copy) NSArray<NSString *> *exposedBindings;
- (Class)valueClassForBinding:(NSString *)binding;
- (void)bind:(NSString *)binding toObject:(id)observable withKeyPath:(NSString *)keyPath
     options:(NSDictionary *)options;
- (void)unbind:(NSString *)binding;
- (NSDictionary *)infoForBinding:(NSString *)binding;
- (NSArray *)optionDescriptionsForBinding:(NSString *)binding;
@end

/* ---- Backing scale (M7): points to the window's pixels ------------------------------- */
typedef NS_OPTIONS(unsigned long long, NSAlignmentOptions) {
    NSAlignMinXInward = 1ULL << 0, NSAlignMinYInward = 1ULL << 1, NSAlignMaxXInward = 1ULL << 2,
    NSAlignMaxYInward = 1ULL << 3, NSAlignWidthInward = 1ULL << 4, NSAlignHeightInward = 1ULL << 5,
    NSAlignMinXOutward = 1ULL << 8, NSAlignMinYOutward = 1ULL << 9, NSAlignMaxXOutward = 1ULL << 10,
    NSAlignMaxYOutward = 1ULL << 11, NSAlignWidthOutward = 1ULL << 12, NSAlignHeightOutward = 1ULL << 13,
    NSAlignMinXNearest = 1ULL << 16, NSAlignMinYNearest = 1ULL << 17, NSAlignMaxXNearest = 1ULL << 18,
    NSAlignMaxYNearest = 1ULL << 19, NSAlignWidthNearest = 1ULL << 20, NSAlignHeightNearest = 1ULL << 21,
    NSAlignRectFlipped = 1ULL << 63,
    NSAlignAllEdgesInward = NSAlignMinXInward | NSAlignMaxXInward | NSAlignMinYInward | NSAlignMaxYInward,
    NSAlignAllEdgesOutward = NSAlignMinXOutward | NSAlignMaxXOutward | NSAlignMinYOutward | NSAlignMaxYOutward,
    NSAlignAllEdgesNearest = NSAlignMinXNearest | NSAlignMaxXNearest | NSAlignMinYNearest | NSAlignMaxYNearest,
};
APPKIT_EXTERN NSNotificationName const NSWindowDidChangeBackingPropertiesNotification;
APPKIT_EXTERN NSString *const NSBackingPropertyOldScaleFactorKey, *const NSBackingPropertyOldColorSpaceKey;
@interface NSWindow (NSBackingCoordinates)
- (NSRect)convertRectToBacking:(NSRect)rect;
- (NSRect)convertRectFromBacking:(NSRect)rect;
- (NSPoint)convertPointToBacking:(NSPoint)point;
- (NSPoint)convertPointFromBacking:(NSPoint)point;
- (NSRect)backingAlignedRect:(NSRect)rect options:(NSAlignmentOptions)options;
@end
@interface NSView (NSBackingCoordinates)
- (NSRect)convertRectToBacking:(NSRect)rect;
- (NSRect)convertRectFromBacking:(NSRect)rect;
- (NSPoint)convertPointToBacking:(NSPoint)point;
- (NSPoint)convertPointFromBacking:(NSPoint)point;
- (NSSize)convertSizeToBacking:(NSSize)size;
- (NSSize)convertSizeFromBacking:(NSSize)size;
- (NSRect)backingAlignedRect:(NSRect)rect options:(NSAlignmentOptions)options;
- (void)viewDidChangeBackingProperties;
@end
@interface NSObject (NSWindowBackingDelegate)
- (void)windowDidChangeBackingProperties:(NSNotification *)notification;
@end

/* ---- Pasteboards (M7) ----------------------------------------------------------------
 * The general pasteboard is this system's clipboard for text (and, read
 * only, for files and images copied in other apps); everything else stays
 * inside the program. The old ...PboardType names are the same types as the
 * new ones, except NSFilenamesPboardType, an array of paths. */
typedef NSString *NSPasteboardType;
typedef NSString *NSPasteboardName;
typedef NSString *NSPasteboardReadingOptionKey;
APPKIT_EXTERN NSPasteboardType const NSPasteboardTypeString, NSPasteboardTypePDF, NSPasteboardTypeTIFF,
    NSPasteboardTypePNG, NSPasteboardTypeRTF, NSPasteboardTypeRTFD, NSPasteboardTypeHTML,
    NSPasteboardTypeTabularText, NSPasteboardTypeFont, NSPasteboardTypeRuler, NSPasteboardTypeColor,
    NSPasteboardTypeSound, NSPasteboardTypeMultipleTextSelection, NSPasteboardTypeTextFinderOptions,
    NSPasteboardTypeURL, NSPasteboardTypeFileURL;
APPKIT_EXTERN NSPasteboardType const NSStringPboardType, NSFilenamesPboardType, NSTIFFPboardType, NSPDFPboardType,
    NSRTFPboardType, NSRTFDPboardType, NSHTMLPboardType, NSTabularTextPboardType, NSFontPboardType,
    NSRulerPboardType, NSColorPboardType, NSURLPboardType, NSFileContentsPboardType, NSMultipleTextSelectionPboardType,
    NSPostScriptPboardType, NSVCardPboardType, NSInkTextPboardType, NSFilesPromisePboardType, NSPICTPboardType;
APPKIT_EXTERN NSPasteboardName const NSPasteboardNameGeneral, NSPasteboardNameFont, NSPasteboardNameRuler,
    NSPasteboardNameFind, NSPasteboardNameDrag;
APPKIT_EXTERN NSPasteboardName const NSGeneralPboard, NSFontPboard, NSRulerPboard, NSFindPboard, NSDragPboard;
APPKIT_EXTERN NSPasteboardReadingOptionKey const NSPasteboardURLReadingFileURLsOnlyKey,
    NSPasteboardURLReadingContentsConformToTypesKey;

typedef NS_OPTIONS(NSUInteger, NSPasteboardWritingOptions) { NSPasteboardWritingPromised = 1 << 9 };
typedef NS_OPTIONS(NSUInteger, NSPasteboardReadingOptions) {
    NSPasteboardReadingAsData = 0, NSPasteboardReadingAsString = 1 << 0,
    NSPasteboardReadingAsPropertyList = 1 << 1, NSPasteboardReadingAsKeyedArchive = 1 << 2,
};
typedef NS_OPTIONS(NSUInteger, NSPasteboardContentsOptions) { NSPasteboardContentsCurrentHostOnly = 1 << 0 };

@class NSPasteboard, NSPasteboardItem;
@protocol NSPasteboardWriting <NSObject>
- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard;
@optional
- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard;
@required
- (id)pasteboardPropertyListForType:(NSPasteboardType)type;
@end
@protocol NSPasteboardReading <NSObject>
+ (NSArray<NSPasteboardType> *)readableTypesForPasteboard:(NSPasteboard *)pasteboard;
@optional
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard;
- (id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSPasteboardType)type;
@end
@protocol NSPasteboardItemDataProvider <NSObject>
- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSPasteboardType)type;
@optional
- (void)pasteboardFinishedWithDataProvider:(NSPasteboard *)pasteboard;
@end
@interface NSObject (NSPasteboardOwner)
- (void)pasteboard:(NSPasteboard *)sender provideDataForType:(NSPasteboardType)type;
- (void)pasteboardChangedOwner:(NSPasteboard *)sender;
@end

@interface NSPasteboardItem : NSObject <NSPasteboardWriting, NSPasteboardReading>
@property (readonly, copy) NSArray<NSPasteboardType> *types;
- (NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)types;
- (BOOL)setDataProvider:(id<NSPasteboardItemDataProvider>)provider forTypes:(NSArray<NSPasteboardType> *)types;
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type;
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type;
- (BOOL)setPropertyList:(id)propertyList forType:(NSPasteboardType)type;
- (NSData *)dataForType:(NSPasteboardType)type;
- (NSString *)stringForType:(NSPasteboardType)type;
- (id)propertyListForType:(NSPasteboardType)type;
@end

@interface NSPasteboard : NSObject
@property (class, readonly, strong) NSPasteboard *generalPasteboard;
+ (NSPasteboard *)pasteboardWithName:(NSPasteboardName)name;
+ (NSPasteboard *)pasteboardWithUniqueName;
@property (readonly, copy) NSPasteboardName name;
@property (readonly) NSInteger changeCount;
- (void)releaseGlobally;
- (NSInteger)prepareForNewContentsWithOptions:(NSPasteboardContentsOptions)options;
- (NSInteger)clearContents;
- (BOOL)writeObjects:(NSArray<id<NSPasteboardWriting>> *)objects;
- (NSArray *)readObjectsForClasses:(NSArray<Class> *)classes options:(NSDictionary *)options;
@property (readonly, copy) NSArray<NSPasteboardItem *> *pasteboardItems;
- (NSUInteger)indexOfPasteboardItem:(NSPasteboardItem *)item;
- (BOOL)canReadItemWithDataConformingToTypes:(NSArray<NSString *> *)types;
- (BOOL)canReadObjectForClasses:(NSArray<Class> *)classes options:(NSDictionary *)options;
- (NSInteger)declareTypes:(NSArray<NSPasteboardType> *)types owner:(id)owner;
- (NSInteger)addTypes:(NSArray<NSPasteboardType> *)types owner:(id)owner;
@property (readonly, copy) NSArray<NSPasteboardType> *types;
- (NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)types;
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type;
- (BOOL)setPropertyList:(id)plist forType:(NSPasteboardType)type;
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type;
- (NSData *)dataForType:(NSPasteboardType)type;
- (id)propertyListForType:(NSPasteboardType)type;
- (NSString *)stringForType:(NSPasteboardType)type;
@end

@interface NSString (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
@end
@interface NSURL (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
+ (NSURL *)URLFromPasteboard:(NSPasteboard *)pasteboard;
- (void)writeToPasteboard:(NSPasteboard *)pasteboard;
@end
@interface NSImage (NSPasteboardSupport) <NSPasteboardWriting, NSPasteboardReading>
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)pasteboard;
- (instancetype)initWithPasteboard:(NSPasteboard *)pasteboard;
@end
/* The commands keys are bound to (interpretKeyEvents: sends them) */
@protocol NSStandardKeyBindingResponding <NSObject>
@optional
- (void)insertText:(id)insertString;
- (void)moveForward:(id)sender;
- (void)moveRight:(id)sender;
- (void)moveBackward:(id)sender;
- (void)moveLeft:(id)sender;
- (void)moveUp:(id)sender;
- (void)moveDown:(id)sender;
- (void)moveWordForward:(id)sender;
- (void)moveWordBackward:(id)sender;
- (void)moveToBeginningOfLine:(id)sender;
- (void)moveToEndOfLine:(id)sender;
- (void)moveToBeginningOfParagraph:(id)sender;
- (void)moveToEndOfParagraph:(id)sender;
- (void)moveToEndOfDocument:(id)sender;
- (void)moveToBeginningOfDocument:(id)sender;
- (void)pageDown:(id)sender;
- (void)pageUp:(id)sender;
- (void)centerSelectionInVisibleArea:(id)sender;
- (void)moveBackwardAndModifySelection:(id)sender;
- (void)moveForwardAndModifySelection:(id)sender;
- (void)moveWordForwardAndModifySelection:(id)sender;
- (void)moveWordBackwardAndModifySelection:(id)sender;
- (void)moveUpAndModifySelection:(id)sender;
- (void)moveDownAndModifySelection:(id)sender;
- (void)moveToBeginningOfLineAndModifySelection:(id)sender;
- (void)moveToEndOfLineAndModifySelection:(id)sender;
- (void)moveToBeginningOfParagraphAndModifySelection:(id)sender;
- (void)moveToEndOfParagraphAndModifySelection:(id)sender;
- (void)moveToEndOfDocumentAndModifySelection:(id)sender;
- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender;
- (void)pageDownAndModifySelection:(id)sender;
- (void)pageUpAndModifySelection:(id)sender;
- (void)moveWordRight:(id)sender;
- (void)moveWordLeft:(id)sender;
- (void)moveRightAndModifySelection:(id)sender;
- (void)moveLeftAndModifySelection:(id)sender;
- (void)moveWordRightAndModifySelection:(id)sender;
- (void)moveWordLeftAndModifySelection:(id)sender;
- (void)moveToLeftEndOfLine:(id)sender;
- (void)moveToRightEndOfLine:(id)sender;
- (void)scrollPageUp:(id)sender;
- (void)scrollPageDown:(id)sender;
- (void)scrollLineUp:(id)sender;
- (void)scrollLineDown:(id)sender;
- (void)scrollToBeginningOfDocument:(id)sender;
- (void)scrollToEndOfDocument:(id)sender;
- (void)transpose:(id)sender;
- (void)indent:(id)sender;
- (void)insertTab:(id)sender;
- (void)insertBacktab:(id)sender;
- (void)insertNewline:(id)sender;
- (void)insertParagraphSeparator:(id)sender;
- (void)insertNewlineIgnoringFieldEditor:(id)sender;
- (void)insertTabIgnoringFieldEditor:(id)sender;
- (void)insertLineBreak:(id)sender;
- (void)capitalizeWord:(id)sender;
- (void)uppercaseWord:(id)sender;
- (void)lowercaseWord:(id)sender;
- (void)deleteForward:(id)sender;
- (void)deleteBackward:(id)sender;
- (void)deleteWordForward:(id)sender;
- (void)deleteWordBackward:(id)sender;
- (void)deleteToBeginningOfLine:(id)sender;
- (void)deleteToEndOfLine:(id)sender;
- (void)deleteToBeginningOfParagraph:(id)sender;
- (void)deleteToEndOfParagraph:(id)sender;
- (void)yank:(id)sender;
- (void)complete:(id)sender;
- (void)setMark:(id)sender;
- (void)deleteToMark:(id)sender;
- (void)selectToMark:(id)sender;
- (void)swapWithMark:(id)sender;
- (void)cancelOperation:(id)sender;
- (void)selectAll:(id)sender;
- (void)selectLine:(id)sender;
- (void)selectParagraph:(id)sender;
- (void)selectWord:(id)sender;
- (void)doCommandBySelector:(SEL)selector;
@end
@interface NSResponder (NSStandardKeyBindingMethods) <NSStandardKeyBindingResponding>
@end

@interface NSResponder (NSStandardEditing)
- (IBAction)cut:(id)sender;
- (IBAction)copy:(id)sender;
- (IBAction)paste:(id)sender;
@end

/* ---- Drag and drop (M7) --------------------------------------------------------------
 * Views take files and text dropped on them from other apps. Dragging out
 * of a Ferry window is not done yet. */
typedef NS_OPTIONS(NSUInteger, NSDragOperation) {
    NSDragOperationNone = 0, NSDragOperationCopy = 1, NSDragOperationLink = 2, NSDragOperationGeneric = 4,
    NSDragOperationPrivate = 8, NSDragOperationMove = 16, NSDragOperationDelete = 32,
    NSDragOperationEvery = NSUIntegerMax,
};
typedef NS_ENUM(NSInteger, NSDraggingFormation) {
    NSDraggingFormationDefault = 0, NSDraggingFormationNone, NSDraggingFormationPile, NSDraggingFormationList,
    NSDraggingFormationStack,
};
typedef NS_ENUM(NSInteger, NSDraggingContext) { NSDraggingContextOutsideApplication = 0, NSDraggingContextWithinApplication };
@protocol NSDraggingInfo <NSObject>
@property (readonly, strong) NSWindow *draggingDestinationWindow;
@property (readonly) NSDragOperation draggingSourceOperationMask;
@property (readonly) NSPoint draggingLocation;
@property (readonly) NSPoint draggedImageLocation;
@property (readonly, strong) NSImage *draggedImage;
@property (readonly, strong) NSPasteboard *draggingPasteboard;
@property (readonly, strong) id draggingSource;
@property (readonly) NSInteger draggingSequenceNumber;
@property NSDraggingFormation draggingFormation;
@property BOOL animatesToDestination;
@property NSInteger numberOfValidItemsForDrop;
@end
@protocol NSDraggingDestination <NSObject>
@optional
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender;
- (void)draggingExited:(id<NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender;
- (void)concludeDragOperation:(id<NSDraggingInfo>)sender;
- (void)draggingEnded:(id<NSDraggingInfo>)sender;
- (BOOL)wantsPeriodicDraggingUpdates;
@end
@interface NSView (NSDragging)
- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)types;
- (void)unregisterDraggedTypes;
@property (readonly, copy) NSArray<NSPasteboardType> *registeredDraggedTypes;
@end
@interface NSWindow (NSDragging)
- (void)registerForDraggedTypes:(NSArray<NSPasteboardType> *)types;
- (void)unregisterDraggedTypes;
@end

/* ---- Open and Save panels (M7) -------------------------------------------------------
 * This system's file chooser. With no display, a panel answers Cancel,
 * unless FERRY_PANEL_ANSWER holds the paths to answer with, separated by
 * newlines (for scripted runs and tests). */
@class NSSavePanel, NSOpenPanel;
@protocol NSOpenSavePanelDelegate <NSObject>
@optional
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url;
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError;
- (void)panel:(id)sender didChangeToDirectoryURL:(NSURL *)url;
- (NSString *)panel:(id)sender userEnteredFilename:(NSString *)filename confirmed:(BOOL)okFlag;
- (void)panel:(id)sender willExpand:(BOOL)expanding;
- (void)panelSelectionDidChange:(id)sender;
@end
enum { NSFileHandlingPanelCancelButton = 0, NSFileHandlingPanelOKButton = 1 };
enum { NSCancelButton = 0, NSOKButton = 1 };
@interface NSSavePanel : NSPanel
+ (NSSavePanel *)savePanel;
@property (copy) NSURL *directoryURL;
@property (readonly, copy) NSURL *URL;
@property (copy) NSString *nameFieldStringValue;
@property (copy) NSString *nameFieldLabel;
@property (copy) NSString *message;
@property (copy) NSString *prompt;
@property (copy) NSArray<NSString *> *allowedFileTypes;
@property BOOL allowsOtherFileTypes;
@property BOOL canCreateDirectories;
@property BOOL canSelectHiddenExtension;
@property (getter=isExtensionHidden) BOOL extensionHidden;
@property BOOL showsHiddenFiles;
@property BOOL treatsFilePackagesAsDirectories;
@property BOOL showsTagField;
@property (copy) NSArray<NSString *> *tagNames;
@property (strong) NSView *accessoryView;
@property (weak) id<NSOpenSavePanelDelegate> delegate;
@property (getter=isExpanded, readonly) BOOL expanded;
- (NSModalResponse)runModal;
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse result))handler;
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse result))handler;
- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (void)validateVisibleColumns;
/* older calls */
- (NSString *)filename;
- (NSString *)directory;
- (void)setDirectory:(NSString *)path;
- (NSInteger)runModalForDirectory:(NSString *)path file:(NSString *)name;
- (NSString *)requiredFileType;
- (void)setRequiredFileType:(NSString *)type;
@end
@interface NSOpenPanel : NSSavePanel
+ (NSOpenPanel *)openPanel;
@property (readonly, copy) NSArray<NSURL *> *URLs;
@property BOOL canChooseFiles;
@property BOOL canChooseDirectories;
@property BOOL allowsMultipleSelection;
@property BOOL resolvesAliases;
@property (getter=isAccessoryViewDisclosed) BOOL accessoryViewDisclosed;
@property BOOL canDownloadUbiquitousContents;
@property BOOL canResolveUbiquitousConflicts;
- (NSArray<NSString *> *)filenames;
- (NSInteger)runModalForTypes:(NSArray *)fileTypes;
- (NSInteger)runModalForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes;
@end


/* ---- scrolling, text, progress and boxes ------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSBorderType) {
    NSNoBorder = 0, NSLineBorder = 1, NSBezelBorder = 2, NSGrooveBorder = 3,
};
typedef NS_ENUM(NSInteger, NSScrollerStyle) { NSScrollerStyleLegacy = 0, NSScrollerStyleOverlay = 1 };
typedef NS_ENUM(NSUInteger, NSScrollerPart) {
    NSScrollerNoPart = 0, NSScrollerDecrementPage = 1, NSScrollerKnob = 2, NSScrollerIncrementPage = 3,
    NSScrollerDecrementLine = 4, NSScrollerIncrementLine = 5, NSScrollerKnobSlot = 6,
};
typedef NS_ENUM(NSUInteger, NSScrollElasticity) {
    NSScrollElasticityAutomatic = 0, NSScrollElasticityNone = 1, NSScrollElasticityAllowed = 2,
};
@interface NSScroller : NSControl
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)size scrollerStyle:(NSScrollerStyle)style;
+ (CGFloat)scrollerWidth;
+ (NSScrollerStyle)preferredScrollerStyle;
@property CGFloat knobProportion;
@property NSScrollerStyle scrollerStyle;
@property NSInteger knobStyle;
@property (readonly) NSScrollerPart hitPart;
- (NSRect)rectForPart:(NSScrollerPart)part;
- (NSScrollerPart)testPart:(NSPoint)point;
- (void)drawKnob;
- (void)drawKnobSlotInRect:(NSRect)rect highlight:(BOOL)flag;
- (void)setFloatValue:(float)value knobProportion:(CGFloat)proportion;
@end

@interface NSClipView : NSView
@property (retain) __kindof NSView *documentView;
@property (readonly) NSRect documentRect;
@property (readonly) NSRect documentVisibleRect;
@property BOOL drawsBackground;
@property (copy) NSColor *backgroundColor;
@property BOOL copiesOnScroll;
@property NSEdgeInsets contentInsets;
@property BOOL automaticallyAdjustsContentInsets;
- (void)scrollToPoint:(NSPoint)point;
- (BOOL)autoscroll:(NSEvent *)event;
- (NSRect)constrainBoundsRect:(NSRect)proposed;
- (void)viewFrameChanged:(NSNotification *)note;
@end

@interface NSScrollView : NSView
+ (NSSize)contentSizeForFrameSize:(NSSize)frameSize horizontalScrollerClass:(Class)h
            verticalScrollerClass:(Class)v borderType:(NSBorderType)type controlSize:(NSControlSize)size
                    scrollerStyle:(NSScrollerStyle)style;
+ (NSSize)frameSizeForContentSize:(NSSize)contentSize horizontalScrollerClass:(Class)h
            verticalScrollerClass:(Class)v borderType:(NSBorderType)type controlSize:(NSControlSize)size
                    scrollerStyle:(NSScrollerStyle)style;
@property (retain) NSClipView *contentView;
@property (retain) __kindof NSView *documentView;
@property (readonly) NSSize contentSize;
@property (readonly) NSRect documentVisibleRect;
@property BOOL hasVerticalScroller, hasHorizontalScroller, autohidesScrollers;
@property (retain) NSScroller *verticalScroller, *horizontalScroller;
@property NSBorderType borderType;
@property BOOL drawsBackground;
@property (copy) NSColor *backgroundColor;
@property CGFloat lineScroll, verticalLineScroll, horizontalLineScroll;
@property CGFloat pageScroll, verticalPageScroll, horizontalPageScroll;
@property NSScrollerStyle scrollerStyle;
@property NSScrollElasticity verticalScrollElasticity, horizontalScrollElasticity;
@property BOOL scrollsDynamically, usesPredominantAxisScrolling, allowsMagnification;
@property CGFloat magnification, minMagnification, maxMagnification;
@property NSEdgeInsets contentInsets, scrollerInsets;
@property BOOL automaticallyAdjustsContentInsets;
@property (getter=isFindBarVisible) BOOL findBarVisible;
@property NSInteger findBarPosition;
@property BOOL hasVerticalRuler, hasHorizontalRuler, rulersVisible;
- (void)tile;
- (void)reflectScrolledClipView:(NSClipView *)clipView;
- (void)flashScrollers;
@end
APPKIT_EXTERN NSNotificationName const NSScrollViewWillStartLiveScrollNotification;
APPKIT_EXTERN NSNotificationName const NSScrollViewDidLiveScrollNotification;
APPKIT_EXTERN NSNotificationName const NSScrollViewDidEndLiveScrollNotification;

@interface NSView (NSScrolling)
@property (readonly) NSScrollView *enclosingScrollView;
- (BOOL)scrollRectToVisible:(NSRect)rect;
- (BOOL)autoscroll:(NSEvent *)event;
- (NSRect)adjustScroll:(NSRect)proposed;
@end


/* Documents to and from attributed strings: RTF, simple HTML and plain text */
typedef NSString *NSAttributedStringDocumentAttributeKey;
typedef NSString *NSAttributedStringDocumentReadingOptionKey;
typedef NSString *NSAttributedStringDocumentType;
APPKIT_EXTERN NSAttributedStringKey const NSLinkAttributeName;
APPKIT_EXTERN NSAttributedStringDocumentAttributeKey const NSDocumentTypeDocumentAttribute;
APPKIT_EXTERN NSAttributedStringDocumentAttributeKey const NSCharacterEncodingDocumentAttribute;
APPKIT_EXTERN NSAttributedStringDocumentReadingOptionKey const NSDocumentTypeDocumentOption;
APPKIT_EXTERN NSAttributedStringDocumentReadingOptionKey const NSCharacterEncodingDocumentOption;
APPKIT_EXTERN NSAttributedStringDocumentType const NSPlainTextDocumentType, NSRTFTextDocumentType,
    NSRTFDTextDocumentType, NSHTMLTextDocumentType;
@interface NSAttributedString (NSAttributedStringDocumentFormats)
- (instancetype)initWithRTF:(NSData *)data documentAttributes:(NSDictionary **)attributes;
- (instancetype)initWithRTFD:(NSData *)data documentAttributes:(NSDictionary **)attributes;
- (instancetype)initWithHTML:(NSData *)data documentAttributes:(NSDictionary **)attributes;
- (instancetype)initWithHTML:(NSData *)data baseURL:(NSURL *)base documentAttributes:(NSDictionary **)attributes;
- (instancetype)initWithData:(NSData *)data options:(NSDictionary *)options
          documentAttributes:(NSDictionary **)attributes error:(NSError **)error;
- (instancetype)initWithURL:(NSURL *)url options:(NSDictionary *)options
         documentAttributes:(NSDictionary **)attributes error:(NSError **)error;
- (instancetype)initWithPath:(NSString *)path documentAttributes:(NSDictionary **)attributes;
- (NSData *)RTFFromRange:(NSRange)range documentAttributes:(NSDictionary *)attributes;
- (NSData *)RTFDFromRange:(NSRange)range documentAttributes:(NSDictionary *)attributes;
- (NSData *)dataFromRange:(NSRange)range documentAttributes:(NSDictionary *)attributes error:(NSError **)error;
@end

/* Text: Ferry's NSTextView lays out its own text with Core Text. The text
 * system's other classes (NSLayoutManager, NSTextContainer) are kept as
 * small objects that answer for the text view. */
@class NSTextView, NSLayoutManager;
@interface NSTextStorage : NSMutableAttributedString
@property (readonly, copy) NSArray<NSLayoutManager *> *layoutManagers;
@property (assign) id delegate;
@property (readonly) NSInteger changeInLength;
- (void)addLayoutManager:(NSLayoutManager *)lm;
- (void)removeLayoutManager:(NSLayoutManager *)lm;
@end
@interface NSTextContainer : NSObject <NSCoding>
- (instancetype)initWithSize:(NSSize)size;
- (instancetype)initWithContainerSize:(NSSize)size;
@property NSSize size, containerSize;
@property (assign) NSTextView *textView;
@property (assign) NSLayoutManager *layoutManager;
@property BOOL widthTracksTextView, heightTracksTextView;
@property CGFloat lineFragmentPadding;
@property NSUInteger maximumNumberOfLines;
@property NSLineBreakMode lineBreakMode;
@end
@interface NSLayoutManager : NSObject <NSCoding>
@property (readonly, assign) NSTextStorage *textStorage;
@property (readonly) NSArray<NSTextContainer *> *textContainers;
@property BOOL allowsNonContiguousLayout, usesFontLeading, showsInvisibleCharacters, showsControlCharacters;
@property (readonly) NSTextView *firstTextView;
- (void)setTextStorage:(NSTextStorage *)storage;
- (void)replaceTextStorage:(NSTextStorage *)storage;
- (void)addTextContainer:(NSTextContainer *)container;
- (NSRect)usedRectForTextContainer:(NSTextContainer *)container;
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)container;
- (void)ensureLayoutForTextContainer:(NSTextContainer *)container;
- (CGFloat)defaultLineHeightForFont:(NSFont *)font;
- (NSUInteger)numberOfGlyphs;
@end

@interface NSText : NSView
@property (copy) NSString *string;
@property (getter=isEditable) BOOL editable;
@property (getter=isSelectable) BOOL selectable;
@property (getter=isRichText) BOOL richText;
@property BOOL importsGraphics, fieldEditor, usesFontPanel, drawsBackground;
@property (copy) NSColor *backgroundColor, *textColor;
@property (retain) NSFont *font;
@property NSTextAlignment alignment;
@property NSRange selectedRange;
@property (assign) id delegate;
@property (getter=isHorizontallyResizable) BOOL horizontallyResizable;
@property (getter=isVerticallyResizable) BOOL verticallyResizable;
@property NSSize minSize, maxSize;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;
- (void)scrollRangeToVisible:(NSRange)range;
- (void)sizeToFit;
- (void)selectAll:(id)sender;
- (void)setFont:(NSFont *)font range:(NSRange)range;
- (void)setTextColor:(NSColor *)color range:(NSRange)range;
- (NSData *)RTFFromRange:(NSRange)range;
- (BOOL)readRTFDFromFile:(NSString *)path;
- (void)replaceCharactersInRange:(NSRange)range withRTF:(NSData *)rtf;
@end
@interface NSTextView : NSText
- (instancetype)initWithFrame:(NSRect)frame textContainer:(NSTextContainer *)container;
+ (NSScrollView *)scrollableTextView;
@property (readonly) NSTextStorage *textStorage;
@property (readonly) NSLayoutManager *layoutManager;
@property (retain) NSTextContainer *textContainer;
@property NSSize textContainerInset;
@property (readonly) NSPoint textContainerOrigin;
@property (copy) NSDictionary<NSAttributedStringKey, id> *typingAttributes, *selectedTextAttributes,
    *linkTextAttributes, *markedTextAttributes;
@property BOOL allowsUndo, usesFindBar, usesFindPanel, usesRuler, rulerVisible, smartInsertDeleteEnabled;
@property BOOL continuousSpellCheckingEnabled, grammarCheckingEnabled, automaticQuoteSubstitutionEnabled,
    automaticDashSubstitutionEnabled, automaticLinkDetectionEnabled, automaticTextReplacementEnabled,
    automaticSpellingCorrectionEnabled, automaticDataDetectionEnabled, displaysLinkToolTips,
    allowsImageEditing, allowsDocumentBackgroundColorChange, usesInspectorBar;
@property (getter=isAutomaticTextCompletionEnabled) BOOL automaticTextCompletionEnabled;
@property (copy) NSColor *insertionPointColor;
@property (copy) NSParagraphStyle *defaultParagraphStyle;
@property (readonly) NSArray<NSValue *> *selectedRanges;
- (void)setSelectedRange:(NSRange)range affinity:(NSInteger)affinity stillSelecting:(BOOL)still;
- (void)insertText:(id)string replacementRange:(NSRange)range;
- (BOOL)shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string;
- (void)didChangeText;
- (NSUInteger)characterIndexForInsertionAtPoint:(NSPoint)point;
@end
APPKIT_EXTERN NSNotificationName const NSTextDidBeginEditingNotification;
APPKIT_EXTERN NSNotificationName const NSTextDidEndEditingNotification;
APPKIT_EXTERN NSNotificationName const NSTextDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSTextViewDidChangeSelectionNotification;
@protocol NSTextViewDelegate <NSObject>
@optional
- (void)textDidChange:(NSNotification *)note;
- (void)textDidBeginEditing:(NSNotification *)note;
- (void)textDidEndEditing:(NSNotification *)note;
- (void)textViewDidChangeSelection:(NSNotification *)note;
- (BOOL)textView:(NSTextView *)tv shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string;
- (BOOL)textView:(NSTextView *)tv doCommandBySelector:(SEL)sel;
@end

typedef NS_ENUM(NSUInteger, NSProgressIndicatorStyle) {
    NSProgressIndicatorStyleBar = 0, NSProgressIndicatorStyleSpinning = 1,
};
@interface NSProgressIndicator : NSView
@property double doubleValue, minValue, maxValue;
@property (getter=isIndeterminate) BOOL indeterminate;
@property NSProgressIndicatorStyle style;
@property NSControlSize controlSize;
@property BOOL displayedWhenStopped, usesThreadedAnimation, bezeled;
- (void)incrementBy:(double)delta;
- (void)startAnimation:(id)sender;
- (void)stopAnimation:(id)sender;
- (void)sizeToFit;
@end

typedef NS_ENUM(NSUInteger, NSBoxType) {
    NSBoxPrimary = 0, NSBoxSeparator = 2, NSBoxCustom = 4,
};
typedef NS_ENUM(NSUInteger, NSTitlePosition) {
    NSNoTitle = 0, NSAboveTop = 1, NSAtTop = 2, NSBelowTop = 3, NSAboveBottom = 4, NSAtBottom = 5,
    NSBelowBottom = 6,
};
@interface NSBox : NSView
@property NSBoxType boxType;
@property (copy) NSString *title;
@property (retain) NSFont *titleFont;
@property NSTitlePosition titlePosition;
@property (getter=isTransparent) BOOL transparent;
@property NSSize contentViewMargins;
@property (retain) __kindof NSView *contentView;
@property (copy) NSColor *fillColor, *borderColor;
@property CGFloat borderWidth, cornerRadius;
@property NSBorderType borderType;
@property (readonly) NSRect titleRect, borderRect;
- (void)setFrameFromContentFrame:(NSRect)contentFrame;
- (void)sizeToFit;
@end


/* ---- split views and tab views ------------------------------------------------------- */
typedef float NSLayoutPriority;
static const NSLayoutPriority NSLayoutPriorityRequired = 1000;
static const NSLayoutPriority NSLayoutPriorityDefaultHigh = 750;
static const NSLayoutPriority NSLayoutPriorityDragThatCanResizeWindow = 510;
static const NSLayoutPriority NSLayoutPriorityWindowSizeStayPut = 500;
static const NSLayoutPriority NSLayoutPriorityDragThatCannotResizeWindow = 490;
static const NSLayoutPriority NSLayoutPriorityDefaultLow = 250;
static const NSLayoutPriority NSLayoutPriorityFittingSizeCompression = 50;

typedef NS_ENUM(NSInteger, NSSplitViewDividerStyle) {
    NSSplitViewDividerStyleThick = 1, NSSplitViewDividerStyleThin = 2, NSSplitViewDividerStylePaneSplitter = 3,
};
@class NSSplitView;
@protocol NSSplitViewDelegate <NSObject>
@optional
- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)subview;
- (BOOL)splitView:(NSSplitView *)sv shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)i;
- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)i;
- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)i;
- (CGFloat)splitView:(NSSplitView *)sv constrainSplitPosition:(CGFloat)proposed ofSubviewAt:(NSInteger)i;
- (void)splitView:(NSSplitView *)sv resizeSubviewsWithOldSize:(NSSize)old;
- (BOOL)splitView:(NSSplitView *)sv shouldAdjustSizeOfSubview:(NSView *)view;
- (BOOL)splitView:(NSSplitView *)sv shouldHideDividerAtIndex:(NSInteger)i;
- (NSRect)splitView:(NSSplitView *)sv effectiveRect:(NSRect)proposed forDrawnRect:(NSRect)drawn
   ofDividerAtIndex:(NSInteger)i;
- (NSRect)splitView:(NSSplitView *)sv additionalEffectiveRectOfDividerAtIndex:(NSInteger)i;
- (void)splitViewWillResizeSubviews:(NSNotification *)note;
- (void)splitViewDidResizeSubviews:(NSNotification *)note;
@end
APPKIT_EXTERN NSNotificationName const NSSplitViewWillResizeSubviewsNotification;
APPKIT_EXTERN NSNotificationName const NSSplitViewDidResizeSubviewsNotification;
@interface NSSplitView : NSView
@property (getter=isVertical) BOOL vertical;
@property NSSplitViewDividerStyle dividerStyle;
@property (readonly) CGFloat dividerThickness;
@property (readonly, copy) NSColor *dividerColor;
@property (assign) id<NSSplitViewDelegate> delegate;
@property (copy) NSString *autosaveName;
@property BOOL arrangesAllSubviews;
@property (readonly, copy) NSArray<__kindof NSView *> *arrangedSubviews;
- (void)addArrangedSubview:(NSView *)view;
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)index;
- (void)removeArrangedSubview:(NSView *)view;
- (void)adjustSubviews;
- (BOOL)isSubviewCollapsed:(NSView *)subview;
- (CGFloat)positionOfDividerAtIndex:(NSInteger)index;
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)index;
- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)index;
- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)index;
- (NSLayoutPriority)holdingPriorityForSubviewAtIndex:(NSInteger)index;
- (void)setHoldingPriority:(NSLayoutPriority)priority forSubviewAtIndex:(NSInteger)index;
- (void)drawDividerInRect:(NSRect)rect;
@end

typedef NS_ENUM(NSUInteger, NSTabViewType) {
    NSTopTabsBezelBorder = 0, NSLeftTabsBezelBorder = 1, NSBottomTabsBezelBorder = 2, NSRightTabsBezelBorder = 3,
    NSNoTabsBezelBorder = 4, NSNoTabsLineBorder = 5, NSNoTabsNoBorder = 6,
};
typedef NS_ENUM(NSUInteger, NSTabPosition) {
    NSTabPositionNone = 0, NSTabPositionTop = 1, NSTabPositionLeft = 2, NSTabPositionBottom = 3, NSTabPositionRight = 4,
};
typedef NS_ENUM(NSUInteger, NSTabViewBorderType) {
    NSTabViewBorderTypeNone = 0, NSTabViewBorderTypeLine = 1, NSTabViewBorderTypeBezel = 2,
};
typedef NS_ENUM(NSUInteger, NSTabState) { NSSelectedTab = 0, NSBackgroundTab = 1, NSPressedTab = 2 };
@class NSTabView;
@interface NSTabViewItem : NSObject <NSCoding>
- (instancetype)initWithIdentifier:(id)identifier;
+ (instancetype)tabViewItemWithViewController:(NSViewController *)vc;
@property (retain) id identifier;
@property (copy) NSString *label;
@property (copy) NSString *toolTip;
@property (copy) NSColor *color;
@property (retain) NSImage *image;
@property (retain) NSView *view;
@property (retain) NSViewController *viewController;
@property (assign) NSView *initialFirstResponder;
@property (readonly) NSTabState tabState;
@property (readonly, assign) NSTabView *tabView;
- (NSSize)sizeOfLabel:(BOOL)shouldTruncate;
- (void)drawLabel:(BOOL)shouldTruncate inRect:(NSRect)rect;
@end
@protocol NSTabViewDelegate <NSObject>
@optional
- (BOOL)tabView:(NSTabView *)tv shouldSelectTabViewItem:(NSTabViewItem *)item;
- (void)tabView:(NSTabView *)tv willSelectTabViewItem:(NSTabViewItem *)item;
- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item;
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tv;
@end
@interface NSTabView : NSView
@property NSTabViewType tabViewType;
@property NSTabPosition tabPosition;
@property NSTabViewBorderType tabViewBorderType;
@property (copy) NSArray<NSTabViewItem *> *tabViewItems;
@property (readonly) NSInteger numberOfTabViewItems;
@property (readonly) NSTabViewItem *selectedTabViewItem;
@property (assign) id<NSTabViewDelegate> delegate;
@property (retain) NSFont *font;
@property BOOL drawsBackground, allowsTruncatedLabels;
@property NSControlSize controlSize;
@property (readonly) NSRect contentRect;
@property (readonly) NSSize minimumSize;
- (void)addTabViewItem:(NSTabViewItem *)item;
- (void)insertTabViewItem:(NSTabViewItem *)item atIndex:(NSInteger)index;
- (void)removeTabViewItem:(NSTabViewItem *)item;
- (NSTabViewItem *)tabViewItemAtIndex:(NSInteger)index;
- (NSInteger)indexOfTabViewItem:(NSTabViewItem *)item;
- (NSInteger)indexOfTabViewItemWithIdentifier:(id)identifier;
- (NSTabViewItem *)tabViewItemAtPoint:(NSPoint)point;
- (void)selectTabViewItem:(NSTabViewItem *)item;
- (void)selectTabViewItemAtIndex:(NSInteger)index;
- (void)selectTabViewItemWithIdentifier:(id)identifier;
- (void)selectFirstTabViewItem:(id)sender;
- (void)selectLastTabViewItem:(id)sender;
- (void)selectNextTabViewItem:(id)sender;
- (void)selectPreviousTabViewItem:(id)sender;
- (void)takeSelectedTabViewItemFromSender:(id)sender;
@end

/* ---- menu bar items (NSStatusBar.m) -------------------------------------------------- */

@class NSStatusItem;
#define NSVariableStatusItemLength (-1.0)
#define NSSquareStatusItemLength (-2.0)
typedef NS_OPTIONS(NSUInteger, NSStatusItemBehavior) {
    NSStatusItemBehaviorRemovalAllowed = 1 << 1, NSStatusItemBehaviorTerminationOnRemoval = 1 << 2,
};
@interface NSStatusBar : NSObject
+ (NSStatusBar *)systemStatusBar;
- (NSStatusItem *)statusItemWithLength:(CGFloat)length;
- (void)removeStatusItem:(NSStatusItem *)item;
@property (readonly, getter=isVertical) BOOL vertical;
@property (readonly) CGFloat thickness;
@end
@interface NSStatusBarButton : NSButton
@property BOOL appearsDisabled;
@end
@interface NSStatusItem : NSObject
@property (readonly, assign) NSStatusBar *statusBar;
@property CGFloat length;
@property (retain) NSMenu *menu;
@property (readonly, retain) NSStatusBarButton *button;
@property NSStatusItemBehavior behavior;
@property (getter=isVisible) BOOL visible;
@property (copy) NSString *autosaveName;
/* the older ways, which a Mac still accepts */
@property (copy) NSString *title;
@property (copy) NSAttributedString *attributedTitle;
@property (retain) NSImage *image, *alternateImage;
@property (copy) NSString *toolTip;
@property (assign) id target;
@property SEL action, doubleAction;
@property (getter=isEnabled) BOOL enabled;
@property BOOL highlightMode;
@property (retain) NSView *view;
- (NSInteger)sendActionOn:(NSInteger)mask;
- (void)popUpStatusItemMenu:(NSMenu *)menu;
- (void)drawStatusBarBackgroundInRect:(NSRect)rect withHighlight:(BOOL)highlight;
@end

/* ---- table views and outline views (NSTableView.m, NSOutlineView.m) ------------------ */

/* Cells draw themselves for cell-based tables (and anyone else who asks). */
@interface NSCell (NSCellDrawing)
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view;
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view;
@property (readonly) NSSize cellSize;
- (NSSize)cellSizeForBounds:(NSRect)rect;
- (NSRect)titleRectForBounds:(NSRect)rect;
- (NSRect)imageRectForBounds:(NSRect)rect;
- (NSRect)drawingRectForBounds:(NSRect)rect;
@end

@interface NSColor (NSTableViewColors)
@property (class, readonly) NSArray<NSColor *> *alternatingContentBackgroundColors;
@property (class, readonly) NSArray<NSColor *> *controlAlternatingRowBackgroundColors;
@property (class, readonly) NSColor *selectedContentBackgroundColor, *unemphasizedSelectedContentBackgroundColor;
@property (class, readonly) NSColor *alternateSelectedControlTextColor, *unemphasizedSelectedTextColor;
@property (class, readonly) NSColor *selectedControlTextColor;
@end

@class NSTableView, NSTableColumn, NSTableHeaderView, NSTableRowView, NSOutlineView;

typedef NS_OPTIONS(NSUInteger, NSTableViewGridLineStyle) {
    NSTableViewGridNone = 0, NSTableViewSolidVerticalGridLineMask = 1 << 0,
    NSTableViewSolidHorizontalGridLineMask = 1 << 1, NSTableViewDashedHorizontalGridLineMask = 1 << 3,
};
typedef NS_ENUM(NSUInteger, NSTableViewColumnAutoresizingStyle) {
    NSTableViewNoColumnAutoresizing = 0, NSTableViewUniformColumnAutoresizingStyle = 1,
    NSTableViewSequentialColumnAutoresizingStyle = 2, NSTableViewReverseSequentialColumnAutoresizingStyle = 3,
    NSTableViewLastColumnOnlyAutoresizingStyle = 4, NSTableViewFirstColumnOnlyAutoresizingStyle = 5,
};
typedef NS_ENUM(NSInteger, NSTableViewSelectionHighlightStyle) {
    NSTableViewSelectionHighlightStyleNone = -1, NSTableViewSelectionHighlightStyleRegular = 0,
    NSTableViewSelectionHighlightStyleSourceList = 1,
};
typedef NS_ENUM(NSInteger, NSTableViewDraggingDestinationFeedbackStyle) {
    NSTableViewDraggingDestinationFeedbackStyleNone = -1, NSTableViewDraggingDestinationFeedbackStyleRegular = 0,
    NSTableViewDraggingDestinationFeedbackStyleSourceList = 1, NSTableViewDraggingDestinationFeedbackStyleGap = 2,
};
typedef NS_ENUM(NSInteger, NSTableViewRowSizeStyle) {
    NSTableViewRowSizeStyleDefault = -1, NSTableViewRowSizeStyleCustom = 0, NSTableViewRowSizeStyleSmall = 1,
    NSTableViewRowSizeStyleMedium = 2, NSTableViewRowSizeStyleLarge = 3,
};
typedef NS_ENUM(NSInteger, NSTableViewStyle) {
    NSTableViewStyleAutomatic = 0, NSTableViewStyleFullWidth = 1, NSTableViewStyleInset = 2,
    NSTableViewStyleSourceList = 3, NSTableViewStylePlain = 4,
};
typedef NS_OPTIONS(NSUInteger, NSTableColumnResizingOptions) {
    NSTableColumnNoResizing = 0, NSTableColumnAutoresizingMask = 1 << 0, NSTableColumnUserResizingMask = 1 << 1,
};
typedef NS_OPTIONS(NSUInteger, NSTableViewAnimationOptions) {
    NSTableViewAnimationEffectNone = 0x0, NSTableViewAnimationEffectFade = 0x1, NSTableViewAnimationEffectGap = 0x2,
    NSTableViewAnimationSlideUp = 0x10, NSTableViewAnimationSlideDown = 0x20, NSTableViewAnimationSlideLeft = 0x30,
    NSTableViewAnimationSlideRight = 0x40,
};
typedef NS_ENUM(NSInteger, NSTableViewDropOperation) { NSTableViewDropOn = 0, NSTableViewDropAbove = 1 };

APPKIT_EXTERN NSNotificationName const NSTableViewSelectionDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSTableViewSelectionIsChangingNotification;
APPKIT_EXTERN NSNotificationName const NSTableViewColumnDidMoveNotification;
APPKIT_EXTERN NSNotificationName const NSTableViewColumnDidResizeNotification;
APPKIT_EXTERN NSUserInterfaceItemIdentifier const NSTableViewRowViewKey;

@interface NSTableHeaderCell : NSTextFieldCell
- (void)drawSortIndicatorWithFrame:(NSRect)frame inView:(NSView *)view ascending:(BOOL)ascending
                          priority:(NSInteger)priority;
- (NSRect)sortIndicatorRectForBounds:(NSRect)rect;
@end

@interface NSTableColumn : NSObject <NSCoding>
- (instancetype)initWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;
@property (copy) NSUserInterfaceItemIdentifier identifier;
@property (assign) NSTableView *tableView;
@property CGFloat width, minWidth, maxWidth;
@property (copy) NSString *title;
@property (copy) NSString *headerToolTip;
@property (retain) __kindof NSTableHeaderCell *headerCell;
@property (retain) __kindof NSCell *dataCell;
- (__kindof NSCell *)dataCellForRow:(NSInteger)row;
@property (getter=isEditable) BOOL editable;
@property (getter=isHidden) BOOL hidden;
@property NSTableColumnResizingOptions resizingMask;
@property (copy) NSSortDescriptor *sortDescriptorPrototype;
- (void)sizeToFit;
@end

@protocol NSTableViewDataSource <NSObject>
@optional
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors;
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rows
     toPasteboard:(NSPasteboard *)pasteboard;
@end

@protocol NSTableViewDelegate <NSControlTextEditingDelegate>
@optional
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row;
- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView;
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row;
- (NSIndexSet *)tableView:(NSTableView *)tableView
    selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes;
- (BOOL)tableView:(NSTableView *)tableView shouldSelectTableColumn:(NSTableColumn *)column;
- (void)tableView:(NSTableView *)tableView mouseDownInHeaderOfTableColumn:(NSTableColumn *)column;
- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column;
- (void)tableView:(NSTableView *)tableView didDragTableColumn:(NSTableColumn *)column;
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row;
- (CGFloat)tableView:(NSTableView *)tableView sizeToFitWidthOfColumn:(NSInteger)column;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)tableViewSelectionIsChanging:(NSNotification *)notification;
- (void)tableViewColumnDidMove:(NSNotification *)notification;
- (void)tableViewColumnDidResize:(NSNotification *)notification;
@end

/* A table of rows and columns. Cell-based tables draw each column's data
 * cell with the data source's values; view-based tables show the views
 * the delegate makes. A double click (or Return) edits a text cell in
 * place: in a cell-based table the value goes back through the data
 * source, in a view-based one through the text field's action. */
@interface NSTableView : NSControl
@property (assign) id<NSTableViewDataSource> dataSource;
@property (assign) id<NSTableViewDelegate> delegate;
@property (retain) NSTableHeaderView *headerView;
@property (retain) NSView *cornerView;
@property (readonly, copy) NSArray<NSTableColumn *> *tableColumns;
@property (readonly) NSInteger numberOfColumns, numberOfRows;
- (void)addTableColumn:(NSTableColumn *)column;
- (void)removeTableColumn:(NSTableColumn *)column;
- (void)moveColumn:(NSInteger)oldIndex toColumn:(NSInteger)newIndex;
- (NSInteger)columnWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;
- (NSTableColumn *)tableColumnWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;
@property CGFloat rowHeight;
@property NSSize intercellSpacing;
@property NSTableViewRowSizeStyle rowSizeStyle;
@property (readonly) NSTableViewRowSizeStyle effectiveRowSizeStyle;
@property NSTableViewStyle style;
@property (readonly) NSTableViewStyle effectiveStyle;
@property BOOL usesAlternatingRowBackgroundColors;
@property BOOL usesAutomaticRowHeights;
@property (copy) NSColor *backgroundColor, *gridColor;
@property NSTableViewGridLineStyle gridStyleMask;
@property NSTableViewColumnAutoresizingStyle columnAutoresizingStyle;
@property NSTableViewSelectionHighlightStyle selectionHighlightStyle;
@property NSTableViewDraggingDestinationFeedbackStyle draggingDestinationFeedbackStyle;
@property BOOL allowsColumnReordering, allowsColumnResizing, allowsColumnSelection;
@property BOOL allowsMultipleSelection, allowsEmptySelection, allowsTypeSelect;
@property BOOL floatsGroupRows, usesStaticContents, verticalMotionCanBeginDrag;
@property (copy) NSString *autosaveName;
@property BOOL autosaveTableColumns;
@property SEL doubleAction;
@property (readonly) NSInteger clickedRow, clickedColumn, editedRow, editedColumn;
@property (copy) NSArray<NSSortDescriptor *> *sortDescriptors;
@property (retain) NSTableColumn *highlightedTableColumn;
- (void)setIndicatorImage:(NSImage *)image inTableColumn:(NSTableColumn *)column;
- (NSImage *)indicatorImageInTableColumn:(NSTableColumn *)column;
- (void)sizeLastColumnToFit;
- (void)sizeToFit;
- (void)tile;
/* loading */
- (void)reloadData;
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns;
- (void)noteNumberOfRowsChanged;
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)rows;
- (void)beginUpdates;
- (void)endUpdates;
- (void)insertRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)options;
- (void)removeRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)options;
- (void)moveRowAtIndex:(NSInteger)oldIndex toIndex:(NSInteger)newIndex;
/* geometry */
- (NSRect)rectOfRow:(NSInteger)row;
- (NSRect)rectOfColumn:(NSInteger)column;
- (NSRange)rowsInRect:(NSRect)rect;
- (NSIndexSet *)columnIndexesInRect:(NSRect)rect;
- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row;
- (NSInteger)rowAtPoint:(NSPoint)point;
- (NSInteger)columnAtPoint:(NSPoint)point;
- (NSInteger)rowForView:(NSView *)view;
- (NSInteger)columnForView:(NSView *)view;
- (void)scrollRowToVisible:(NSInteger)row;
- (void)scrollColumnToVisible:(NSInteger)column;
/* selection */
@property (readonly) NSInteger selectedRow, selectedColumn, numberOfSelectedRows, numberOfSelectedColumns;
@property (readonly, copy) NSIndexSet *selectedRowIndexes, *selectedColumnIndexes;
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
- (void)selectColumnIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
- (void)selectRow:(NSInteger)row byExtendingSelection:(BOOL)extend;
- (void)deselectRow:(NSInteger)row;
- (void)deselectColumn:(NSInteger)column;
- (BOOL)isRowSelected:(NSInteger)row;
- (BOOL)isColumnSelected:(NSInteger)column;
- (void)selectAll:(id)sender;
- (void)deselectAll:(id)sender;
/* views */
- (__kindof NSView *)makeViewWithIdentifier:(NSUserInterfaceItemIdentifier)identifier owner:(id)owner;
- (void)registerNib:(NSNib *)nib forIdentifier:(NSUserInterfaceItemIdentifier)identifier;
@property (readonly, copy) NSDictionary<NSUserInterfaceItemIdentifier, NSNib *> *registeredNibsByIdentifier;
- (__kindof NSView *)viewAtColumn:(NSInteger)column row:(NSInteger)row makeIfNecessary:(BOOL)make;
- (__kindof NSTableRowView *)rowViewAtRow:(NSInteger)row makeIfNecessary:(BOOL)make;
- (void)enumerateAvailableRowViewsUsingBlock:(void (^)(__kindof NSTableRowView *rowView, NSInteger row))block;
/* drawing */
- (void)drawRow:(NSInteger)row clipRect:(NSRect)clip;
- (void)drawGridInClipRect:(NSRect)clip;
- (void)drawBackgroundInClipRect:(NSRect)clip;
- (void)highlightSelectionInClipRect:(NSRect)clip;
- (NSCell *)preparedCellAtColumn:(NSInteger)column row:(NSInteger)row;
- (void)editColumn:(NSInteger)column row:(NSInteger)row withEvent:(NSEvent *)event select:(BOOL)select;
@end

/* The row of column titles above a table; click a title to sort, drag a
 * divider to resize. */
@interface NSTableHeaderView : NSView
@property (assign) NSTableView *tableView;
@property (readonly) NSInteger draggedColumn, resizedColumn;
@property (readonly) CGFloat draggedDistance;
- (NSInteger)columnAtPoint:(NSPoint)point;
- (NSRect)headerRectOfColumn:(NSInteger)column;
@end

/* The view behind one row of a view-based table, which draws the row's
 * selection (and, in an outline view, its disclosure triangle). */
@interface NSTableRowView : NSView
@property (getter=isSelected) BOOL selected;
@property (getter=isEmphasized) BOOL emphasized;
@property (getter=isGroupRowStyle) BOOL groupRowStyle;
@property (getter=isFloating) BOOL floating;
@property (getter=isPreviousRowSelected) BOOL previousRowSelected;
@property (getter=isNextRowSelected) BOOL nextRowSelected;
@property NSTableViewSelectionHighlightStyle selectionHighlightStyle;
@property NSTableViewDraggingDestinationFeedbackStyle draggingDestinationFeedbackStyle;
@property (copy) NSColor *backgroundColor;
@property (readonly) NSBackgroundStyle interiorBackgroundStyle;
@property (readonly) NSInteger numberOfColumns;
@property CGFloat indentationForDropOperation;
@property (getter=isTargetForDropOperation) BOOL targetForDropOperation;
- (void)drawBackgroundInRect:(NSRect)dirtyRect;
- (void)drawSelectionInRect:(NSRect)dirtyRect;
- (void)drawSeparatorInRect:(NSRect)dirtyRect;
- (void)drawDraggingDestinationFeedbackInRect:(NSRect)dirtyRect;
- (__kindof NSView *)viewAtColumn:(NSInteger)column;
@end

/* The usual cell view: an optional image view and text field, and the row's
 * object. */
@interface NSTableCellView : NSView
@property (retain) id objectValue;
@property (assign) IBOutlet NSTextField *textField;
@property (assign) IBOutlet NSImageView *imageView;
@property NSBackgroundStyle backgroundStyle;
@property NSTableViewRowSizeStyle rowSizeStyle;
@property (retain) NSArray *draggingImageComponents;
@end

/* An outline: a table whose rows are a tree of items, which open and close
 * with a disclosure triangle in the outline column. */
APPKIT_EXTERN NSNotificationName const NSOutlineViewSelectionDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewSelectionIsChangingNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewColumnDidMoveNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewColumnDidResizeNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewItemWillExpandNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewItemDidExpandNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewItemWillCollapseNotification;
APPKIT_EXTERN NSNotificationName const NSOutlineViewItemDidCollapseNotification;
APPKIT_EXTERN NSUserInterfaceItemIdentifier const NSOutlineViewDisclosureButtonKey;
APPKIT_EXTERN NSUserInterfaceItemIdentifier const NSOutlineViewShowHideButtonKey;
enum { NSOutlineViewDropOnItemIndex = -1 };

@protocol NSOutlineViewDataSource <NSObject>
@optional
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item;
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column
             byItem:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object;
- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(id)item;
- (void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors;
- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item;
@end

@protocol NSOutlineViewDelegate <NSControlTextEditingDelegate>
@optional
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)column item:(id)item;
- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item;
- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row;
- (void)outlineView:(NSOutlineView *)outlineView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row;
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column
               item:(id)item;
- (void)outlineView:(NSOutlineView *)outlineView willDisplayOutlineCell:(id)cell
     forTableColumn:(NSTableColumn *)column item:(id)item;
- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)column item:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)column item:(id)item;
- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item;
- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item;
- (void)outlineView:(NSOutlineView *)outlineView mouseDownInHeaderOfTableColumn:(NSTableColumn *)column;
- (void)outlineView:(NSOutlineView *)outlineView didClickTableColumn:(NSTableColumn *)column;
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
- (void)outlineViewSelectionIsChanging:(NSNotification *)notification;
- (void)outlineViewColumnDidMove:(NSNotification *)notification;
- (void)outlineViewColumnDidResize:(NSNotification *)notification;
- (void)outlineViewItemWillExpand:(NSNotification *)notification;
- (void)outlineViewItemDidExpand:(NSNotification *)notification;
- (void)outlineViewItemWillCollapse:(NSNotification *)notification;
- (void)outlineViewItemDidCollapse:(NSNotification *)notification;
@end

@interface NSOutlineView : NSTableView
@property (assign) id<NSOutlineViewDataSource> dataSource;
@property (assign) id<NSOutlineViewDelegate> delegate;
@property (assign) NSTableColumn *outlineTableColumn;
@property CGFloat indentationPerLevel;
@property BOOL indentationMarkerFollowsCell, autoresizesOutlineColumn, autosaveExpandedItems;
@property BOOL stronglyReferencesItems;
- (BOOL)isExpandable:(id)item;
- (NSInteger)numberOfChildrenOfItem:(id)item;
- (id)child:(NSInteger)index ofItem:(id)item;
- (void)expandItem:(id)item;
- (void)expandItem:(id)item expandChildren:(BOOL)expandChildren;
- (void)collapseItem:(id)item;
- (void)collapseItem:(id)item collapseChildren:(BOOL)collapseChildren;
- (BOOL)isItemExpanded:(id)item;
- (void)reloadItem:(id)item;
- (void)reloadItem:(id)item reloadChildren:(BOOL)reloadChildren;
- (id)itemAtRow:(NSInteger)row;
- (NSInteger)rowForItem:(id)item;
- (NSInteger)levelForItem:(id)item;
- (NSInteger)levelForRow:(NSInteger)row;
- (id)parentForItem:(id)item;
- (NSInteger)childIndexForItem:(id)item;
- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row;
- (void)insertItemsAtIndexes:(NSIndexSet *)indexes inParent:(id)parent
               withAnimation:(NSTableViewAnimationOptions)options;
- (void)removeItemsAtIndexes:(NSIndexSet *)indexes inParent:(id)parent
               withAnimation:(NSTableViewAnimationOptions)options;
- (void)moveItemAtIndex:(NSInteger)fromIndex inParent:(id)oldParent toIndex:(NSInteger)toIndex inParent:(id)newParent;
@end

/* ---- pop-up buttons, segmented controls, search fields, stack views and toolbars ------ */
/* (NSPopUpButton.m, NSSegmentedControl.m, NSSearchField.m, NSStackView.m, NSToolbar.m) */

/* Auto Layout isn't in Ferry; these are what a view says about its own size,
 * which stack views and toolbars use to lay views out by hand. */
#define NSViewNoIntrinsicMetric ((CGFloat)-1)
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutOrientation) {
    NSUserInterfaceLayoutOrientationHorizontal = 0, NSUserInterfaceLayoutOrientationVertical = 1,
};
typedef NS_ENUM(NSInteger, NSLayoutConstraintOrientation) {
    NSLayoutConstraintOrientationHorizontal = 0, NSLayoutConstraintOrientationVertical = 1,
};
typedef NS_ENUM(NSInteger, NSLayoutAttribute) {
    NSLayoutAttributeLeft = 1, NSLayoutAttributeRight, NSLayoutAttributeTop, NSLayoutAttributeBottom,
    NSLayoutAttributeLeading, NSLayoutAttributeTrailing, NSLayoutAttributeWidth, NSLayoutAttributeHeight,
    NSLayoutAttributeCenterX, NSLayoutAttributeCenterY, NSLayoutAttributeLastBaseline,
    NSLayoutAttributeBaseline = NSLayoutAttributeLastBaseline, NSLayoutAttributeFirstBaseline,
    NSLayoutAttributeNotAnAttribute = 0,
};
@interface NSView (NSConstraintBasedLayout)
@property (readonly) NSSize intrinsicContentSize;
@property (readonly) NSSize fittingSize;
@property BOOL needsLayout;
- (void)layout;
- (void)layoutSubtreeIfNeeded;
- (void)invalidateIntrinsicContentSize;
- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setContentHuggingPriority:(NSLayoutPriority)priority forOrientation:(NSLayoutConstraintOrientation)orientation;
- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)priority
                                 forOrientation:(NSLayoutConstraintOrientation)orientation;
@end

@interface NSApplication (FerryKeyboardAccess)
/* Whether Tab reaches every control, not only text fields and lists (the
 * "AppleKeyboardUIMode" default, as a Mac keeps it). */
@property (readonly, getter=isFullKeyboardAccessEnabled) BOOL fullKeyboardAccessEnabled;
@end

/* A pop-up button shows a menu: as a pop-up list, the chosen item is the
 * button's title; as a pull-down list, the first item is the title and the
 * menu opens below with the others. The menu opens inside the window. */
typedef NS_ENUM(NSUInteger, NSPopUpArrowPosition) {
    NSPopUpNoArrow = 0, NSPopUpArrowAtCenter = 1, NSPopUpArrowAtBottom = 2,
};
@interface NSMenuItemCell : NSButtonCell
@property (retain) NSMenuItem *menuItem;
@end
@interface NSPopUpButtonCell : NSMenuItemCell
- (instancetype)initTextCell:(NSString *)string pullsDown:(BOOL)pullDown;
@property (retain) NSMenu *menu;
@property BOOL pullsDown, autoenablesItems, usesItemFromMenu, altersStateOfSelectedItem;
@property NSRectEdge preferredEdge;
@property NSPopUpArrowPosition arrowPosition;
- (void)addItemWithTitle:(NSString *)title;
- (void)addItemsWithTitles:(NSArray<NSString *> *)titles;
- (void)insertItemWithTitle:(NSString *)title atIndex:(NSInteger)index;
- (void)removeItemWithTitle:(NSString *)title;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;
@property (readonly, copy) NSArray<NSMenuItem *> *itemArray;
@property (readonly) NSInteger numberOfItems;
- (NSInteger)indexOfItem:(NSMenuItem *)item;
- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (NSInteger)indexOfItemWithTag:(NSInteger)tag;
- (NSInteger)indexOfItemWithRepresentedObject:(id)obj;
- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)action;
- (NSMenuItem *)itemAtIndex:(NSInteger)index;
- (NSMenuItem *)itemWithTitle:(NSString *)title;
@property (readonly) NSMenuItem *lastItem;
- (void)selectItem:(NSMenuItem *)item;
- (void)selectItemAtIndex:(NSInteger)index;
- (BOOL)selectItemWithTag:(NSInteger)tag;
- (void)selectItemWithTitle:(NSString *)title;
@property (readonly) NSMenuItem *selectedItem;
@property (readonly) NSInteger indexOfSelectedItem;
@property (readonly) NSInteger selectedTag;
- (void)synchronizeTitleAndSelectedItem;
- (NSString *)itemTitleAtIndex:(NSInteger)index;
@property (readonly, copy) NSArray<NSString *> *itemTitles;
@property (readonly, copy) NSString *titleOfSelectedItem;
- (void)attachPopUpWithFrame:(NSRect)frame inView:(NSView *)view;
- (void)dismissPopUp;
- (void)performClickWithFrame:(NSRect)frame inView:(NSView *)view;
@end
@interface NSPopUpButton : NSButton
+ (instancetype)popUpButtonWithMenu:(NSMenu *)menu target:(id)target action:(SEL)action;
+ (instancetype)pullDownButtonWithTitle:(NSString *)title menu:(NSMenu *)menu;
- (instancetype)initWithFrame:(NSRect)frame pullsDown:(BOOL)flag;
@property (retain) NSMenu *menu;
@property BOOL pullsDown, autoenablesItems, usesItemFromMenu;
@property NSRectEdge preferredEdge;
- (void)addItemWithTitle:(NSString *)title;
- (void)addItemsWithTitles:(NSArray<NSString *> *)titles;
- (void)insertItemWithTitle:(NSString *)title atIndex:(NSInteger)index;
- (void)removeItemWithTitle:(NSString *)title;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;
@property (readonly, copy) NSArray<NSMenuItem *> *itemArray;
@property (readonly) NSInteger numberOfItems;
- (NSInteger)indexOfItem:(NSMenuItem *)item;
- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (NSInteger)indexOfItemWithTag:(NSInteger)tag;
- (NSInteger)indexOfItemWithRepresentedObject:(id)obj;
- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)action;
- (NSMenuItem *)itemAtIndex:(NSInteger)index;
- (NSMenuItem *)itemWithTitle:(NSString *)title;
@property (readonly) NSMenuItem *lastItem;
- (void)selectItem:(NSMenuItem *)item;
- (void)selectItemAtIndex:(NSInteger)index;
- (BOOL)selectItemWithTag:(NSInteger)tag;
- (void)selectItemWithTitle:(NSString *)title;
@property (readonly) NSMenuItem *selectedItem;
@property (readonly) NSInteger indexOfSelectedItem;
@property (readonly) NSInteger selectedTag;
- (void)synchronizeTitleAndSelectedItem;
- (NSString *)itemTitleAtIndex:(NSInteger)index;
@property (readonly, copy) NSArray<NSString *> *itemTitles;
@property (readonly, copy) NSString *titleOfSelectedItem;
@end
APPKIT_EXTERN NSNotificationName const NSPopUpButtonWillPopUpNotification;
APPKIT_EXTERN NSNotificationName const NSPopUpButtonCellWillPopUpNotification;

/* A row of segments, each with a label or an image, that act as one
 * control. */
typedef NS_ENUM(NSUInteger, NSSegmentSwitchTracking) {
    NSSegmentSwitchTrackingSelectOne = 0, NSSegmentSwitchTrackingSelectAny = 1,
    NSSegmentSwitchTrackingMomentary = 2, NSSegmentSwitchTrackingMomentaryAccelerator = 3,
};
typedef NS_ENUM(NSInteger, NSSegmentStyle) {
    NSSegmentStyleAutomatic = 0, NSSegmentStyleRounded = 1, NSSegmentStyleTexturedRounded = 2,
    NSSegmentStyleRoundRect = 3, NSSegmentStyleTexturedSquare = 4, NSSegmentStyleCapsule = 5,
    NSSegmentStyleSmallSquare = 6, NSSegmentStyleSeparated = 8,
};
typedef NS_ENUM(NSInteger, NSSegmentDistribution) {
    NSSegmentDistributionFit = 0, NSSegmentDistributionFill, NSSegmentDistributionFillEqually,
    NSSegmentDistributionFillProportionally,
};
@interface NSSegmentedCell : NSActionCell
@property NSInteger segmentCount, selectedSegment;
@property NSSegmentSwitchTracking trackingMode;
@property NSSegmentStyle segmentStyle;
- (BOOL)selectSegmentWithTag:(NSInteger)tag;
- (void)makeNextSegmentKey;
- (void)makePreviousSegmentKey;
- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment;
- (CGFloat)widthForSegment:(NSInteger)segment;
- (void)setImage:(NSImage *)image forSegment:(NSInteger)segment;
- (NSImage *)imageForSegment:(NSInteger)segment;
- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment;
- (NSImageScaling)imageScalingForSegment:(NSInteger)segment;
- (void)setLabel:(NSString *)label forSegment:(NSInteger)segment;
- (NSString *)labelForSegment:(NSInteger)segment;
- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment;
- (BOOL)isSelectedForSegment:(NSInteger)segment;
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment;
- (BOOL)isEnabledForSegment:(NSInteger)segment;
- (void)setMenu:(NSMenu *)menu forSegment:(NSInteger)segment;
- (NSMenu *)menuForSegment:(NSInteger)segment;
- (void)setToolTip:(NSString *)toolTip forSegment:(NSInteger)segment;
- (NSString *)toolTipForSegment:(NSInteger)segment;
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment;
- (NSInteger)tagForSegment:(NSInteger)segment;
@end
@interface NSSegmentedControl : NSControl
+ (instancetype)segmentedControlWithLabels:(NSArray<NSString *> *)labels trackingMode:(NSSegmentSwitchTracking)mode
                                    target:(id)target action:(SEL)action;
+ (instancetype)segmentedControlWithImages:(NSArray<NSImage *> *)images trackingMode:(NSSegmentSwitchTracking)mode
                                    target:(id)target action:(SEL)action;
@property NSInteger segmentCount, selectedSegment;
@property (readonly) NSInteger indexOfSelectedItem;
@property NSSegmentSwitchTracking trackingMode;
@property NSSegmentStyle segmentStyle;
@property NSSegmentDistribution segmentDistribution;
@property (copy) NSColor *selectedSegmentBezelColor;
@property (getter=isSpringLoaded) BOOL springLoaded;
- (BOOL)selectSegmentWithTag:(NSInteger)tag;
- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment;
- (CGFloat)widthForSegment:(NSInteger)segment;
- (void)setImage:(NSImage *)image forSegment:(NSInteger)segment;
- (NSImage *)imageForSegment:(NSInteger)segment;
- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment;
- (NSImageScaling)imageScalingForSegment:(NSInteger)segment;
- (void)setLabel:(NSString *)label forSegment:(NSInteger)segment;
- (NSString *)labelForSegment:(NSInteger)segment;
- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment;
- (BOOL)isSelectedForSegment:(NSInteger)segment;
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment;
- (BOOL)isEnabledForSegment:(NSInteger)segment;
- (void)setMenu:(NSMenu *)menu forSegment:(NSInteger)segment;
- (NSMenu *)menuForSegment:(NSInteger)segment;
- (void)setToolTip:(NSString *)toolTip forSegment:(NSInteger)segment;
- (NSString *)toolTipForSegment:(NSInteger)segment;
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment;
- (NSInteger)tagForSegment:(NSInteger)segment;
- (void)setAlignment:(NSTextAlignment)alignment forSegment:(NSInteger)segment;
- (NSTextAlignment)alignmentForSegment:(NSInteger)segment;
@end

/* Sliders (NSSlider.m, Ferry 0.17.0): a value between minValue and
 * maxValue (0 and 1 unless set), with tick marks if asked for. */
typedef NS_ENUM(NSUInteger, NSTickMarkPosition) {
    NSTickMarkPositionBelow = 0, NSTickMarkPositionAbove = 1,
    NSTickMarkPositionLeading = 1, NSTickMarkPositionTrailing = 0,
};
#define NSTickMarkBelow NSTickMarkPositionBelow
#define NSTickMarkAbove NSTickMarkPositionAbove
#define NSTickMarkLeft NSTickMarkPositionLeading
#define NSTickMarkRight NSTickMarkPositionTrailing
typedef NS_ENUM(NSUInteger, NSSliderType) { NSSliderTypeLinear = 0, NSSliderTypeCircular = 1 };
@interface NSSliderCell : NSActionCell
@property double minValue, maxValue, altIncrementValue;
@property NSInteger numberOfTickMarks;
@property BOOL allowsTickMarkValuesOnly;
@property NSTickMarkPosition tickMarkPosition;
@property NSSliderType sliderType;
@property (getter=isVertical) BOOL vertical;
@end
@interface NSSlider : NSControl
+ (instancetype)sliderWithTarget:(id)target action:(SEL)action;
+ (instancetype)sliderWithValue:(double)value minValue:(double)min maxValue:(double)max target:(id)target
                         action:(SEL)action;
@property double minValue, maxValue, altIncrementValue;
@property (readonly) double knobThickness;
@property NSInteger numberOfTickMarks;
@property BOOL allowsTickMarkValuesOnly;
@property NSTickMarkPosition tickMarkPosition;
@property NSSliderType sliderType;
@property (getter=isVertical) BOOL vertical;
@property (copy) NSColor *trackFillColor;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (double)closestTickMarkValueToValue:(double)value;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point;
@end

/* A text field for searching: a magnifying glass, a placeholder, and a
 * button that clears it. It sends its action as the user types (after a
 * short pause, or at once), or only on Return. */
@class NSSearchField;
/* tags that mark the places for recent searches in a search menu template */
enum {
    NSSearchFieldRecentsTitleMenuItemTag = 1000, NSSearchFieldRecentsMenuItemTag = 1001,
    NSSearchFieldClearRecentsMenuItemTag = 1002, NSSearchFieldNoRecentsMenuItemTag = 1003,
};
@interface NSSearchFieldCell : NSTextFieldCell
@property (retain) NSButtonCell *searchButtonCell, *cancelButtonCell;
- (void)resetSearchButtonCell;
- (void)resetCancelButtonCell;
- (NSRect)searchTextRectForBounds:(NSRect)rect;
- (NSRect)searchButtonRectForBounds:(NSRect)rect;
- (NSRect)cancelButtonRectForBounds:(NSRect)rect;
@property (retain) NSMenu *searchMenuTemplate;
@property BOOL sendsWholeSearchString, sendsSearchStringImmediately;
@property NSInteger maximumRecents;
@property (copy) NSArray<NSString *> *recentSearches;
@property (copy) NSString *recentsAutosaveName;
@end
@protocol NSSearchFieldDelegate <NSTextFieldDelegate>
@optional
- (void)searchFieldDidStartSearching:(NSSearchField *)sender;
- (void)searchFieldDidEndSearching:(NSSearchField *)sender;
@end
@interface NSSearchField : NSTextField
@property (retain) NSMenu *searchMenuTemplate;
@property BOOL sendsWholeSearchString, sendsSearchStringImmediately, centersPlaceholder;
@property NSInteger maximumRecents;
@property (copy) NSArray<NSString *> *recentSearches;
@property (copy) NSString *recentsAutosaveName;
@property (readonly) NSRect searchTextBounds, searchButtonBounds, cancelButtonBounds;
- (NSRect)rectForSearchTextWhenCentered:(BOOL)isCentered;
- (NSRect)rectForSearchButtonWhenCentered:(BOOL)isCentered;
- (NSRect)rectForCancelButtonWhenCentered:(BOOL)isCentered;
@end

/* ---- more controls (NSStepper.m, NSDatePicker.m, NSComboBox.m, NSColorWell.m,
 * NSLevelIndicator.m, NSPopover.m, NSPathControl.m, NSSound.m, NSTokenField.m) ---- */

/* A pair of arrows that step a value up and down between minValue and
 * maxValue (0 and 59 unless set) by increment (1), wrapping round if
 * valueWraps, repeating while held if autorepeat. */
@interface NSStepperCell : NSActionCell
@property double minValue, maxValue, increment;
@property BOOL autorepeat, valueWraps;
@end
@interface NSStepper : NSControl
@property double minValue, maxValue, increment;
@property BOOL autorepeat, valueWraps;
@end

/* Dates and times, shown as a text field with a stepper, a text field
 * alone, or a calendar month (and clock). */
typedef NS_ENUM(NSUInteger, NSDatePickerStyle) {
    NSDatePickerStyleTextFieldAndStepper = 0, NSDatePickerStyleClockAndCalendar = 1, NSDatePickerStyleTextField = 2,
};
#define NSTextFieldAndStepperDatePickerStyle NSDatePickerStyleTextFieldAndStepper
#define NSClockAndCalendarDatePickerStyle NSDatePickerStyleClockAndCalendar
#define NSTextFieldDatePickerStyle NSDatePickerStyleTextField
typedef NS_ENUM(NSUInteger, NSDatePickerMode) { NSDatePickerModeSingle = 0, NSDatePickerModeRange = 1 };
#define NSSingleDateMode NSDatePickerModeSingle
#define NSRangeDateMode NSDatePickerModeRange
typedef NS_OPTIONS(NSUInteger, NSDatePickerElementFlags) {
    NSDatePickerElementFlagHourMinute = 0x000c, NSDatePickerElementFlagHourMinuteSecond = 0x000e,
    NSDatePickerElementFlagTimeZone = 0x0010, NSDatePickerElementFlagYearMonth = 0x00c0,
    NSDatePickerElementFlagYearMonthDay = 0x00e0, NSDatePickerElementFlagEra = 0x0100,
};
#define NSHourMinuteDatePickerElementFlag NSDatePickerElementFlagHourMinute
#define NSHourMinuteSecondDatePickerElementFlag NSDatePickerElementFlagHourMinuteSecond
#define NSTimeZoneDatePickerElementFlag NSDatePickerElementFlagTimeZone
#define NSYearMonthDatePickerElementFlag NSDatePickerElementFlagYearMonth
#define NSYearMonthDayDatePickerElementFlag NSDatePickerElementFlagYearMonthDay
#define NSEraDatePickerElementFlag NSDatePickerElementFlagEra
@class NSDatePickerCell, NSDatePicker;
@protocol NSDatePickerCellDelegate <NSObject>
@optional
- (void)datePickerCell:(NSDatePickerCell *)cell validateProposedDateValue:(NSDate **)date
          timeInterval:(NSTimeInterval *)interval;
@end
@interface NSDatePickerCell : NSActionCell
@property NSDatePickerStyle datePickerStyle;
@property NSDatePickerMode datePickerMode;
@property NSDatePickerElementFlags datePickerElements;
@property (copy) NSDate *dateValue, *minDate, *maxDate;
@property NSTimeInterval timeInterval;
@property (copy) NSCalendar *calendar;
@property (copy) NSLocale *locale;
@property (copy) NSTimeZone *timeZone;
@property BOOL drawsBackground;
@property (copy) NSColor *backgroundColor, *textColor;
@property (assign) id<NSDatePickerCellDelegate> delegate;
@end
@interface NSDatePicker : NSControl
@property NSDatePickerStyle datePickerStyle;
@property NSDatePickerMode datePickerMode;
@property NSDatePickerElementFlags datePickerElements;
@property (copy) NSDate *dateValue, *minDate, *maxDate;
@property NSTimeInterval timeInterval;
@property (copy) NSCalendar *calendar;
@property (copy) NSLocale *locale;
@property (copy) NSTimeZone *timeZone;
@property (getter=isBezeled) BOOL bezeled;
@property (getter=isBordered) BOOL bordered;
@property BOOL drawsBackground, presentsCalendarOverlay;
@property (copy) NSColor *backgroundColor, *textColor;
@property (assign) id<NSDatePickerCellDelegate> delegate;
@end

/* A text field with a list of values to choose from, or to complete what
 * is typed with. */
@class NSComboBox, NSComboBoxCell;
@protocol NSComboBoxDataSource <NSObject>
@optional
- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)comboBox;
- (id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index;
- (NSUInteger)comboBox:(NSComboBox *)comboBox indexOfItemWithStringValue:(NSString *)string;
- (NSString *)comboBox:(NSComboBox *)comboBox completedString:(NSString *)string;
@end
@protocol NSComboBoxCellDataSource <NSObject>
@optional
- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBoxCell *)cell;
- (id)comboBoxCell:(NSComboBoxCell *)cell objectValueForItemAtIndex:(NSInteger)index;
- (NSUInteger)comboBoxCell:(NSComboBoxCell *)cell indexOfItemWithStringValue:(NSString *)string;
- (NSString *)comboBoxCell:(NSComboBoxCell *)cell completedString:(NSString *)string;
@end
@protocol NSComboBoxDelegate <NSTextFieldDelegate>
@optional
- (void)comboBoxWillPopUp:(NSNotification *)notification;
- (void)comboBoxWillDismiss:(NSNotification *)notification;
- (void)comboBoxSelectionDidChange:(NSNotification *)notification;
- (void)comboBoxSelectionIsChanging:(NSNotification *)notification;
@end
APPKIT_EXTERN NSNotificationName const NSComboBoxWillPopUpNotification, NSComboBoxWillDismissNotification;
APPKIT_EXTERN NSNotificationName const NSComboBoxSelectionDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSComboBoxSelectionIsChangingNotification;
@interface NSComboBoxCell : NSTextFieldCell
@property BOOL usesDataSource, completes, hasVerticalScroller;
@property (getter=isButtonBordered) BOOL buttonBordered;
@property (assign) id<NSComboBoxCellDataSource> dataSource;
@property NSInteger numberOfVisibleItems;
@property CGFloat itemHeight;
@property NSSize intercellSpacing;
@property (readonly) NSInteger numberOfItems, indexOfSelectedItem;
@property (readonly, copy) NSArray *objectValues;
@property (readonly) id objectValueOfSelectedItem;
- (void)addItemWithObjectValue:(id)object;
- (void)addItemsWithObjectValues:(NSArray *)objects;
- (void)insertItemWithObjectValue:(id)object atIndex:(NSInteger)index;
- (void)removeItemWithObjectValue:(id)object;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;
- (id)itemObjectValueAtIndex:(NSInteger)index;
- (NSInteger)indexOfItemWithObjectValue:(id)object;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithObjectValue:(id)object;
- (void)deselectItemAtIndex:(NSInteger)index;
- (void)noteNumberOfItemsChanged;
- (void)reloadData;
- (void)scrollItemAtIndexToTop:(NSInteger)index;
- (void)scrollItemAtIndexToVisible:(NSInteger)index;
- (NSString *)completedString:(NSString *)string;
@end
@interface NSComboBox : NSTextField
@property BOOL usesDataSource, completes, hasVerticalScroller;
@property (getter=isButtonBordered) BOOL buttonBordered;
@property (assign) id<NSComboBoxDataSource> dataSource;
@property NSInteger numberOfVisibleItems;
@property CGFloat itemHeight;
@property NSSize intercellSpacing;
@property (readonly) NSInteger numberOfItems, indexOfSelectedItem;
@property (readonly, copy) NSArray *objectValues;
@property (readonly) id objectValueOfSelectedItem;
- (void)addItemWithObjectValue:(id)object;
- (void)addItemsWithObjectValues:(NSArray *)objects;
- (void)insertItemWithObjectValue:(id)object atIndex:(NSInteger)index;
- (void)removeItemWithObjectValue:(id)object;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;
- (id)itemObjectValueAtIndex:(NSInteger)index;
- (NSInteger)indexOfItemWithObjectValue:(id)object;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithObjectValue:(id)object;
- (void)deselectItemAtIndex:(NSInteger)index;
- (void)noteNumberOfItemsChanged;
- (void)reloadData;
- (void)scrollItemAtIndexToTop:(NSInteger)index;
- (void)scrollItemAtIndexToVisible:(NSInteger)index;
@end

/* Colours: a well that shows one and opens the shared colour panel, and
 * the panel, which sends changeColor: when the user picks a colour. */
@class NSColorPanel;
typedef NS_ENUM(NSInteger, NSColorPanelMode) {
    NSColorPanelModeNone = -1, NSColorPanelModeGray = 0, NSColorPanelModeRGB = 1, NSColorPanelModeCMYK = 2,
    NSColorPanelModeHSB = 3, NSColorPanelModeCustomPalette = 4, NSColorPanelModeColorList = 5,
    NSColorPanelModeWheel = 6, NSColorPanelModeCrayon = 7,
};
typedef NS_OPTIONS(NSUInteger, NSColorPanelOptions) {
    NSColorPanelGrayModeMask = 1 << 0, NSColorPanelRGBModeMask = 1 << 1, NSColorPanelCMYKModeMask = 1 << 2,
    NSColorPanelHSBModeMask = 1 << 3, NSColorPanelCustomPaletteModeMask = 1 << 4,
    NSColorPanelColorListModeMask = 1 << 5, NSColorPanelWheelModeMask = 1 << 6, NSColorPanelCrayonModeMask = 1 << 7,
    NSColorPanelAllModesMask = 0xffff,
};
APPKIT_EXTERN NSNotificationName const NSColorPanelColorDidChangeNotification;
@protocol NSColorChanging <NSObject>
- (void)changeColor:(NSColorPanel *)sender;
@end
@interface NSColorPanel : NSPanel
@property (class, readonly) NSColorPanel *sharedColorPanel;
@property (class, readonly) BOOL sharedColorPanelExists;
+ (void)setPickerMask:(NSColorPanelOptions)mask;
+ (void)setPickerMode:(NSColorPanelMode)mode;
+ (BOOL)dragColor:(NSColor *)color withEvent:(NSEvent *)event fromView:(NSView *)view;
@property (copy) NSColor *color;
@property (readonly) CGFloat alpha;
@property BOOL showsAlpha;
@property NSColorPanelMode mode;
@property (getter=isContinuous) BOOL continuous;
@property (retain) NSView *accessoryView;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
@end
typedef NS_ENUM(NSInteger, NSColorWellStyle) {
    NSColorWellStyleDefault = 0, NSColorWellStyleMinimal = 1, NSColorWellStyleExpanded = 2,
};
@interface NSColorWell : NSControl
@property (copy) NSColor *color;
@property (getter=isBordered) BOOL bordered;
@property (readonly, getter=isActive) BOOL active;
@property NSColorWellStyle colorWellStyle;
@property BOOL supportsAlpha;
- (void)activate:(BOOL)exclusive;
- (void)deactivate;
- (void)takeColorFrom:(id)sender;
- (void)drawWellInside:(NSRect)rect;
@end

/* A level: a capacity bar (continuous or in segments), relevancy bars or
 * a row of stars, coloured by warning and critical values. */
typedef NS_ENUM(NSUInteger, NSLevelIndicatorStyle) {
    NSLevelIndicatorStyleRelevancy = 0, NSLevelIndicatorStyleContinuousCapacity = 1,
    NSLevelIndicatorStyleDiscreteCapacity = 2, NSLevelIndicatorStyleRating = 3,
};
#define NSRelevancyLevelIndicatorStyle NSLevelIndicatorStyleRelevancy
#define NSContinuousCapacityLevelIndicatorStyle NSLevelIndicatorStyleContinuousCapacity
#define NSDiscreteCapacityLevelIndicatorStyle NSLevelIndicatorStyleDiscreteCapacity
#define NSRatingLevelIndicatorStyle NSLevelIndicatorStyleRating
typedef NS_ENUM(NSInteger, NSLevelIndicatorPlaceholderVisibility) {
    NSLevelIndicatorPlaceholderVisibilityAutomatic = 0, NSLevelIndicatorPlaceholderVisibilityAlways = 1,
    NSLevelIndicatorPlaceholderVisibilityWhileEditing = 2,
};
@interface NSLevelIndicatorCell : NSActionCell
- (instancetype)initWithLevelIndicatorStyle:(NSLevelIndicatorStyle)style;
@property NSLevelIndicatorStyle levelIndicatorStyle;
@property double minValue, maxValue, warningValue, criticalValue;
@property NSTickMarkPosition tickMarkPosition;
@property NSInteger numberOfTickMarks, numberOfMajorTickMarks;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;
@property (retain) NSImage *ratingImage, *ratingPlaceholderImage;
@end
@interface NSLevelIndicator : NSControl
@property NSLevelIndicatorStyle levelIndicatorStyle;
@property double minValue, maxValue, warningValue, criticalValue;
@property NSTickMarkPosition tickMarkPosition;
@property NSInteger numberOfTickMarks, numberOfMajorTickMarks;
@property (getter=isEditable) BOOL editable;
@property (copy) NSColor *fillColor, *warningFillColor, *criticalFillColor;
@property BOOL drawsTieredCapacityLevels;
@property NSLevelIndicatorPlaceholderVisibility placeholderVisibility;
@property (retain) NSImage *ratingImage, *ratingPlaceholderImage;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;
@end

/* A popover: a view controller's view shown next to a rectangle of a view,
 * with an arrow pointing at it, inside that view's window. */
@class NSPopover;
typedef NS_ENUM(NSInteger, NSPopoverBehavior) {
    NSPopoverBehaviorApplicationDefined = 0, NSPopoverBehaviorTransient = 1, NSPopoverBehaviorSemitransient = 2,
};
typedef NS_ENUM(NSInteger, NSPopoverAppearance) { NSPopoverAppearanceMinimal = 0, NSPopoverAppearanceHUD = 1 };
typedef NSString *NSPopoverCloseReasonValue;
APPKIT_EXTERN NSString *const NSPopoverCloseReasonKey;
APPKIT_EXTERN NSPopoverCloseReasonValue const NSPopoverCloseReasonStandard, NSPopoverCloseReasonDetachToWindow;
APPKIT_EXTERN NSNotificationName const NSPopoverWillShowNotification, NSPopoverDidShowNotification;
APPKIT_EXTERN NSNotificationName const NSPopoverWillCloseNotification, NSPopoverDidCloseNotification;
@protocol NSPopoverDelegate <NSObject>
@optional
- (BOOL)popoverShouldClose:(NSPopover *)popover;
- (BOOL)popoverShouldDetach:(NSPopover *)popover;
- (NSWindow *)detachableWindowForPopover:(NSPopover *)popover;
- (void)popoverWillShow:(NSNotification *)notification;
- (void)popoverDidShow:(NSNotification *)notification;
- (void)popoverWillClose:(NSNotification *)notification;
- (void)popoverDidClose:(NSNotification *)notification;
@end
@interface NSPopover : NSResponder <NSCoding>
@property (retain) NSViewController *contentViewController;
@property NSSize contentSize;
@property NSPopoverBehavior behavior;
@property BOOL animates;
@property NSPopoverAppearance appearance;
@property (assign) id<NSPopoverDelegate> delegate;
@property (readonly, getter=isShown) BOOL shown;
@property (readonly, getter=isDetached) BOOL detached;
@property NSRect positioningRect;
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (IBAction)performClose:(id)sender;
- (void)close;
@end

/* A path, one component a step: a file URL's folders from the computer
 * down, or a web address's host and folders. */
@class NSPathControl, NSPathCell;
typedef NS_ENUM(NSInteger, NSPathStyle) { NSPathStyleStandard = 0, NSPathStyleNavigationBar = 1, NSPathStylePopUp = 2 };
@interface NSPathControlItem : NSObject
@property (copy) NSString *title;
@property (copy) NSAttributedString *attributedTitle;
@property (retain) NSImage *image;
@property (readonly, copy) NSURL *URL;
@end
@interface NSPathComponentCell : NSTextFieldCell
@property (retain) NSImage *image;
@property (copy) NSURL *URL;
@end
@protocol NSPathControlDelegate <NSObject>
@optional
- (void)pathControl:(NSPathControl *)pathControl willPopUpMenu:(NSMenu *)menu;
@end
@interface NSPathCell : NSActionCell
+ (Class)pathComponentCellClass;
- (NSRect)rectOfPathComponentCell:(NSPathComponentCell *)cell withFrame:(NSRect)frame inView:(NSView *)view;
- (NSPathComponentCell *)pathComponentCellAtPoint:(NSPoint)point withFrame:(NSRect)frame inView:(NSView *)view;
@property (copy) NSAttributedString *placeholderAttributedString;
@property NSPathStyle pathStyle;
@property (copy) NSURL *URL;
@property (copy) NSArray<NSPathComponentCell *> *pathComponentCells;
@property (readonly) NSPathComponentCell *clickedPathComponentCell;
@property (copy) NSString *placeholderString;
@property (copy) NSColor *backgroundColor;
@property (copy) NSArray<NSString *> *allowedTypes;
@property SEL doubleAction;
@end
@interface NSPathControl : NSControl
@property NSPathStyle pathStyle;
@property (copy) NSURL *URL;
@property (copy) NSArray<NSPathControlItem *> *pathItems;
@property (readonly) NSPathControlItem *clickedPathItem;
@property (copy) NSArray<NSPathComponentCell *> *pathComponentCells;
- (NSPathComponentCell *)clickedPathComponentCell;
@property (copy) NSString *placeholderString;
@property (copy) NSAttributedString *placeholderAttributedString;
@property (copy) NSColor *backgroundColor;
@property (copy) NSArray<NSString *> *allowedTypes;
@property (getter=isEditable) BOOL editable;
@property SEL doubleAction;
@property (assign) id<NSPathControlDelegate> delegate;
@end

/* Sounds, played through the system's own player (pw-play, paplay or
 * aplay). */
@class NSSound;
typedef NSString *NSSoundName;
@protocol NSSoundDelegate <NSObject>
@optional
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finished;
@end
@interface NSSound : NSObject <NSCopying, NSCoding>
+ (NSSound *)soundNamed:(NSSoundName)name;
+ (NSArray<NSString *> *)soundUnfilteredTypes;
- (instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byRef;
- (instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byRef;
- (instancetype)initWithData:(NSData *)data;
- (BOOL)setName:(NSSoundName)name;
@property (readonly, copy) NSSoundName name;
- (BOOL)play;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
@property (readonly, getter=isPlaying) BOOL playing;
@property (assign) id<NSSoundDelegate> delegate;
@property float volume;
@property BOOL loops;
@property (readonly) NSTimeInterval duration;
@property NSTimeInterval currentTime;
@end

/* Tokens: what is typed becomes rounded tokens, split at commas (or the
 * tokenizing characters). Its objectValue is an array. */
@class NSTokenField;
typedef NS_ENUM(NSUInteger, NSTokenStyle) {
    NSTokenStyleDefault = 0, NSTokenStyleNone = 1, NSTokenStyleRounded = 2, NSTokenStyleSquared = 3,
    NSTokenStylePlainSquared = 4,
};
#define NSDefaultTokenStyle NSTokenStyleDefault
#define NSPlainTextTokenStyle NSTokenStyleNone
#define NSRoundedTokenStyle NSTokenStyleRounded
@protocol NSTokenFieldDelegate <NSTextFieldDelegate>
@optional
- (NSArray *)tokenField:(NSTokenField *)field completionsForSubstring:(NSString *)substring
            indexOfToken:(NSInteger)index indexOfSelectedItem:(NSInteger *)selected;
- (NSArray *)tokenField:(NSTokenField *)field shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index;
- (NSString *)tokenField:(NSTokenField *)field displayStringForRepresentedObject:(id)object;
- (NSString *)tokenField:(NSTokenField *)field editingStringForRepresentedObject:(id)object;
- (id)tokenField:(NSTokenField *)field representedObjectForEditingString:(NSString *)string;
- (NSTokenStyle)tokenField:(NSTokenField *)field styleForRepresentedObject:(id)object;
@end
@interface NSTokenFieldCell : NSTextFieldCell
@property NSTokenStyle tokenStyle;
@property (copy) NSCharacterSet *tokenizingCharacterSet;
@property NSTimeInterval completionDelay;
+ (NSCharacterSet *)defaultTokenizingCharacterSet;
+ (NSTimeInterval)defaultCompletionDelay;
@end
@interface NSTokenField : NSTextField
@property NSTokenStyle tokenStyle;
@property (copy) NSCharacterSet *tokenizingCharacterSet;
@property NSTimeInterval completionDelay;
+ (NSCharacterSet *)defaultTokenizingCharacterSet;
+ (NSTimeInterval)defaultCompletionDelay;
@end

/* Lays out its views in a row or a column, by hand (there is no Auto
 * Layout in Ferry): each at its intrinsic size, or its frame's size when it
 * has none. */
typedef NS_ENUM(NSInteger, NSStackViewGravity) {
    NSStackViewGravityTop = 1, NSStackViewGravityLeading = 1, NSStackViewGravityCenter = 2,
    NSStackViewGravityBottom = 3, NSStackViewGravityTrailing = 3,
};
typedef NS_ENUM(NSInteger, NSStackViewDistribution) {
    NSStackViewDistributionGravityAreas = -1, NSStackViewDistributionFill = 0, NSStackViewDistributionFillEqually,
    NSStackViewDistributionFillProportionally, NSStackViewDistributionEqualSpacing,
    NSStackViewDistributionEqualCentering,
};
typedef float NSStackViewVisibilityPriority;
static const NSStackViewVisibilityPriority NSStackViewVisibilityPriorityMustHold = 1000;
static const NSStackViewVisibilityPriority NSStackViewVisibilityPriorityDetachOnlyIfNecessary = 900;
static const NSStackViewVisibilityPriority NSStackViewVisibilityPriorityNotVisible = 0;
#define NSStackViewSpacingUseDefault ((CGFloat)3.40282347e+38)
@class NSStackView;
@protocol NSStackViewDelegate <NSObject>
@optional
- (void)stackView:(NSStackView *)stackView willDetachViews:(NSArray<NSView *> *)views;
- (void)stackView:(NSStackView *)stackView didReattachViews:(NSArray<NSView *> *)views;
@end
@interface NSStackView : NSView
+ (instancetype)stackViewWithViews:(NSArray<NSView *> *)views;
@property (assign) id<NSStackViewDelegate> delegate;
@property NSUserInterfaceLayoutOrientation orientation;
@property NSLayoutAttribute alignment;
@property NSEdgeInsets edgeInsets;
@property NSStackViewDistribution distribution;
@property CGFloat spacing;
@property BOOL detachesHiddenViews;
@property (readonly, copy) NSArray<__kindof NSView *> *arrangedSubviews;
- (void)addArrangedSubview:(NSView *)view;
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)index;
- (void)removeArrangedSubview:(NSView *)view;
@property (readonly, copy) NSArray<__kindof NSView *> *views;
@property (readonly, copy) NSArray<__kindof NSView *> *detachedViews;
- (void)addView:(NSView *)view inGravity:(NSStackViewGravity)gravity;
- (void)insertView:(NSView *)view atIndex:(NSUInteger)index inGravity:(NSStackViewGravity)gravity;
- (void)removeView:(NSView *)view;
- (NSArray<NSView *> *)viewsInGravity:(NSStackViewGravity)gravity;
- (void)setViews:(NSArray<NSView *> *)views inGravity:(NSStackViewGravity)gravity;
- (void)setVisibilityPriority:(NSStackViewVisibilityPriority)priority forView:(NSView *)view;
- (NSStackViewVisibilityPriority)visibilityPriorityForView:(NSView *)view;
- (void)setCustomSpacing:(CGFloat)spacing afterView:(NSView *)view;
- (CGFloat)customSpacingAfterView:(NSView *)view;
- (NSLayoutPriority)clippingResistancePriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setClippingResistancePriority:(NSLayoutPriority)priority forOrientation:(NSLayoutConstraintOrientation)orientation;
- (NSLayoutPriority)huggingPriorityForOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setHuggingPriority:(NSLayoutPriority)priority forOrientation:(NSLayoutConstraintOrientation)orientation;
@end

/* A window's toolbar, drawn under the title bar in the same colour, as a
 * Mac's unified title bar and toolbar look. */
typedef NSString *NSToolbarIdentifier;
typedef NSString *NSToolbarItemIdentifier;
typedef NS_ENUM(NSUInteger, NSToolbarDisplayMode) {
    NSToolbarDisplayModeDefault = 0, NSToolbarDisplayModeIconAndLabel = 1, NSToolbarDisplayModeIconOnly = 2,
    NSToolbarDisplayModeLabelOnly = 3,
};
typedef NS_ENUM(NSUInteger, NSToolbarSizeMode) {
    NSToolbarSizeModeDefault = 0, NSToolbarSizeModeRegular = 1, NSToolbarSizeModeSmall = 2,
};
typedef NS_ENUM(NSInteger, NSWindowToolbarStyle) {
    NSWindowToolbarStyleAutomatic = 0, NSWindowToolbarStyleExpanded = 1, NSWindowToolbarStylePreference = 2,
    NSWindowToolbarStyleUnified = 3, NSWindowToolbarStyleUnifiedCompact = 4,
};
typedef NSInteger NSToolbarItemVisibilityPriority;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityStandard = 0;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityLow = -1000;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityHigh = 1000;
static const NSToolbarItemVisibilityPriority NSToolbarItemVisibilityPriorityUser = 2000;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarSpaceItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarFlexibleSpaceItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarSeparatorItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarShowColorsItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarShowFontsItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarCustomizeToolbarItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarPrintItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarToggleSidebarItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarCloudSharingItemIdentifier;
APPKIT_EXTERN NSToolbarItemIdentifier const NSToolbarSidebarTrackingSeparatorItemIdentifier;
APPKIT_EXTERN NSNotificationName const NSToolbarWillAddItemNotification;
APPKIT_EXTERN NSNotificationName const NSToolbarDidRemoveItemNotification;
@class NSToolbar;
@interface NSToolbarItem : NSObject <NSCopying>
- (instancetype)initWithItemIdentifier:(NSToolbarItemIdentifier)identifier NS_DESIGNATED_INITIALIZER;
@property (readonly, copy) NSToolbarItemIdentifier itemIdentifier;
@property (readonly, assign) NSToolbar *toolbar;
@property (copy) NSString *label, *paletteLabel, *toolTip, *title;
@property (retain) NSMenuItem *menuFormRepresentation;
@property NSInteger tag;
@property (assign) id target;
@property SEL action;
@property (getter=isEnabled) BOOL enabled;
@property (retain) NSImage *image;
@property (retain) NSView *view;
@property NSSize minSize, maxSize;
@property NSToolbarItemVisibilityPriority visibilityPriority;
@property BOOL autovalidates;
@property (getter=isBordered) BOOL bordered;
@property (getter=isNavigational) BOOL navigational;
@property (readonly) BOOL allowsDuplicatesInToolbar;
@property (readonly, getter=isVisible) BOOL visible;
- (void)validate;
@end
@interface NSToolbarItemGroup : NSToolbarItem
@property (copy) NSArray<NSToolbarItem *> *subitems;
@end
@protocol NSToolbarItemValidation <NSObject>
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
@end
@protocol NSToolbarDelegate <NSObject>
@optional
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)flag;
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
- (void)toolbarWillAddItem:(NSNotification *)notification;
- (void)toolbarDidRemoveItem:(NSNotification *)notification;
@end
@interface NSToolbar : NSObject <NSCoding>
- (instancetype)initWithIdentifier:(NSToolbarIdentifier)identifier NS_DESIGNATED_INITIALIZER;
@property (readonly, copy) NSToolbarIdentifier identifier;
@property (assign) id<NSToolbarDelegate> delegate;
@property (readonly, copy) NSArray<__kindof NSToolbarItem *> *items, *visibleItems;
@property NSToolbarDisplayMode displayMode;
@property NSToolbarSizeMode sizeMode;
@property (getter=isVisible) BOOL visible;
@property BOOL showsBaselineSeparator, allowsUserCustomization, autosavesConfiguration, allowsExtensionItems;
@property (copy) NSToolbarItemIdentifier selectedItemIdentifier, centeredItemIdentifier;
@property (readonly) BOOL customizationPaletteIsRunning;
@property (readonly, copy) NSDictionary<NSString *, id> *configurationDictionary;
- (void)setConfigurationFromDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (void)insertItemWithItemIdentifier:(NSToolbarItemIdentifier)identifier atIndex:(NSInteger)index;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)validateVisibleItems;
- (void)runCustomizationPalette:(id)sender;
@end
@interface NSWindow (NSToolbarSupport)
@property (retain) NSToolbar *toolbar;
@property NSWindowToolbarStyle toolbarStyle;
- (void)toggleToolbarShown:(id)sender;
- (void)runToolbarCustomizationPalette:(id)sender;
@end

/* ---- validating menu items and controls ------------------------------------------- */

@protocol NSValidatedUserInterfaceItem
@property (readonly) SEL action;
@property (readonly) NSInteger tag;
@end
@protocol NSUserInterfaceValidations
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item;
@end
@interface NSMenuItem (NSValidatedUserInterfaceItem) <NSValidatedUserInterfaceItem>
@end

/* ---- sheets -------------------------------------------------------------------------
 * A sheet is drawn inside its window, under the title bar and toolbar, as
 * a Mac shows it; one bigger than its window gets a window of its own, set
 * modal for its parent (which the compositor may show attached to it). */
APPKIT_EXTERN NSNotificationName const NSWindowWillBeginSheetNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidEndSheetNotification;
@interface NSWindow (NSSheets)
- (void)beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse returnCode))handler;
- (void)beginCriticalSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse returnCode))handler;
- (void)endSheet:(NSWindow *)sheet;
- (void)endSheet:(NSWindow *)sheet returnCode:(NSModalResponse)returnCode;
@property (readonly) NSWindow *attachedSheet;
@property (readonly) NSWindow *sheetParent;
@property (readonly, copy) NSArray<NSWindow *> *sheets;
@property (readonly, getter=isSheet) BOOL sheet;
@property (copy) NSURL *representedURL;
@property (copy) NSString *representedFilename;
@property (readonly) NSUndoManager *undoManager;
@end
@interface NSApplication (NSSheets)
- (void)beginSheet:(NSWindow *)sheet modalForWindow:(NSWindow *)window modalDelegate:(id)delegate
    didEndSelector:(SEL)selector contextInfo:(void *)context;
- (void)endSheet:(NSWindow *)sheet;
- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode;
@end

/* ---- errors, presented in an alert ---------------------------------------------------- */

@interface NSResponder (NSErrorPresentation)
- (BOOL)presentError:(NSError *)error;
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)selector contextInfo:(void *)context;
- (NSError *)willPresentError:(NSError *)error;
@end

/* ---- alerts -------------------------------------------------------------------------
 * Drawn by Ferry as a current Mac draws them: the icon, the message in
 * bold, the informative text, an accessory view and a "Do not show this
 * message again" check box above the buttons, all centred. runModal runs
 * a nested event loop until a button is pressed; a sheet is shown inside
 * its window. With no display, FERRY_ALERT_ANSWER (a button's title or
 * number) answers an alert run modally at once. */
typedef NS_ENUM(NSUInteger, NSAlertStyle) {
    NSAlertStyleWarning = 0, NSAlertStyleInformational = 1, NSAlertStyleCritical = 2,
};
#define NSWarningAlertStyle NSAlertStyleWarning
#define NSInformationalAlertStyle NSAlertStyleInformational
#define NSCriticalAlertStyle NSAlertStyleCritical
enum { NSAlertFirstButtonReturn = 1000, NSAlertSecondButtonReturn = 1001, NSAlertThirdButtonReturn = 1002 };
enum { NSAlertDefaultReturn = 1, NSAlertAlternateReturn = 0, NSAlertOtherReturn = -1, NSAlertErrorReturn = -2 };
@class NSAlert, NSButton;
@protocol NSAlertDelegate <NSObject>
@optional
- (BOOL)alertShowHelp:(NSAlert *)alert;
@end
@interface NSAlert : NSObject
+ (NSAlert *)alertWithError:(NSError *)error;
+ (NSAlert *)alertWithMessageText:(NSString *)message defaultButton:(NSString *)defaultButton
                  alternateButton:(NSString *)alternateButton otherButton:(NSString *)otherButton
        informativeTextWithFormat:(NSString *)format, ...;
@property (copy) NSString *messageText;
@property (copy) NSString *informativeText;
@property (retain) NSImage *icon;
@property NSAlertStyle alertStyle;
@property BOOL showsHelp;
@property (copy) NSString *helpAnchor;
@property (assign) id<NSAlertDelegate> delegate;
@property (readonly, copy) NSArray<NSButton *> *buttons;
- (NSButton *)addButtonWithTitle:(NSString *)title;
@property BOOL showsSuppressionButton;
@property (readonly) NSButton *suppressionButton;
@property (retain) NSView *accessoryView;
- (void)layout;
@property (readonly) NSWindow *window;
- (NSModalResponse)runModal;
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse returnCode))handler;
- (void)beginSheetModalForWindow:(NSWindow *)window modalDelegate:(id)delegate didEndSelector:(SEL)selector
                     contextInfo:(void *)context;
@end
NSInteger NSRunAlertPanel(NSString *title, NSString *format, NSString *defaultButton, NSString *alternateButton,
                          NSString *otherButton, ...);
NSInteger NSRunInformationalAlertPanel(NSString *title, NSString *format, NSString *defaultButton,
                                       NSString *alternateButton, NSString *otherButton, ...);
NSInteger NSRunCriticalAlertPanel(NSString *title, NSString *format, NSString *defaultButton,
                                  NSString *alternateButton, NSString *otherButton, ...);

/* ---- the workspace ------------------------------------------------------------------
 * Files and web addresses are opened by the desktop's own launcher (gio
 * open, else xdg-open), which hands them to the app the desktop has for
 * them; that is the only way Ferry starts anything outside itself. Icons
 * come from the desktop's icon theme. The notifications are all there, but
 * nothing on this system posts most of them. */
@class NSRunningApplication;
APPKIT_EXTERN NSNotificationName const NSWorkspaceWillLaunchApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidLaunchApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidTerminateApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidActivateApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidDeactivateApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidHideApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidUnhideApplicationNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceWillSleepNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidWakeNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceScreensDidSleepNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceScreensDidWakeNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceWillPowerOffNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceSessionDidBecomeActiveNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceSessionDidResignActiveNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidMountNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceWillUnmountNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceDidUnmountNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceActiveSpaceDidChangeNotification;
APPKIT_EXTERN NSString *const NSWorkspaceApplicationKey;
@interface NSWorkspaceOpenConfiguration : NSObject <NSCopying>
+ (instancetype)configuration;
@property BOOL activates, promptsUserIfNeeded, addsToRecentItems, hides, createsNewApplicationInstance;
@property (copy) NSArray<NSString *> *arguments;
@end
@interface NSWorkspace : NSObject
@property (class, readonly) NSWorkspace *sharedWorkspace;
@property (readonly) NSNotificationCenter *notificationCenter;
- (BOOL)openURL:(NSURL *)url;
- (void)openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^)(NSRunningApplication *app, NSError *error))handler;
- (BOOL)openFile:(NSString *)path;
- (BOOL)openFile:(NSString *)path withApplication:(NSString *)app;
- (BOOL)openFile:(NSString *)path withApplication:(NSString *)app andDeactivate:(BOOL)deactivate;
- (BOOL)selectFile:(NSString *)path inFileViewerRootedAtPath:(NSString *)root;
- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)urls;
- (BOOL)launchApplication:(NSString *)name;
- (NSImage *)iconForFile:(NSString *)path;
- (NSImage *)iconForFiles:(NSArray<NSString *> *)paths;
- (NSImage *)iconForFileType:(NSString *)type;
- (BOOL)setIcon:(NSImage *)image forFile:(NSString *)path options:(NSUInteger)options;
- (NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)identifier;
- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)identifier;
- (NSString *)fullPathForApplication:(NSString *)name;
- (NSURL *)URLForApplicationToOpenURL:(NSURL *)url;
- (BOOL)isFilePackageAtPath:(NSString *)path;
- (NSString *)typeOfFile:(NSString *)path error:(NSError **)error;
- (NSString *)localizedDescriptionForType:(NSString *)type;
- (NSString *)preferredFilenameExtensionForType:(NSString *)type;
- (BOOL)filenameExtension:(NSString *)extension isValidForType:(NSString *)type;
- (BOOL)type:(NSString *)type conformsToType:(NSString *)other;
- (void)noteFileSystemChanged:(NSString *)path;
@end

/* ---- documents ----------------------------------------------------------------------
 * The document architecture, as Apple documents it: the Info.plist's
 * CFBundleDocumentTypes say which types the app reads and writes and which
 * NSDocument subclass holds each; NSDocumentController (or the app's own
 * subclass, if one is made first) makes and opens documents and keeps the
 * Recent Documents list; each document reads and writes its file and keeps
 * its change count, which its windows show. A class whose autosavesInPlace
 * answers YES is autosaved autosavingDelay seconds after a change (over its
 * file, or into Autosave Information while untitled), closes without
 * asking, and gets Revert To > Last Saved Version; versions (Browse All
 * Versions) are left out. */
typedef NS_ENUM(NSUInteger, NSDocumentChangeType) {
    NSChangeDone = 0, NSChangeUndone = 1, NSChangeCleared = 2, NSChangeReadOtherContents = 3,
    NSChangeAutosaved = 4, NSChangeRedone = 5, NSChangeDiscardable = 256,
};
typedef NS_ENUM(NSUInteger, NSSaveOperationType) {
    NSSaveOperation = 0, NSSaveAsOperation = 1, NSSaveToOperation = 2, NSAutosaveElsewhereOperation = 3,
    NSAutosaveInPlaceOperation = 4, NSAutosaveAsOperation = 5,
};
#define NSAutosaveOperation NSAutosaveElsewhereOperation
@class NSSavePanel, NSOpenPanel;
@interface NSDocument : NSObject <NSUserInterfaceValidations, NSMenuItemValidation>
- (instancetype)init;
- (instancetype)initWithType:(NSString *)type error:(NSError **)error;
- (instancetype)initWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error;
- (instancetype)initForURL:(NSURL *)url withContentsOfURL:(NSURL *)contentsURL ofType:(NSString *)type
                     error:(NSError **)error;
@property (class, readonly, copy) NSArray<NSString *> *readableTypes, *writableTypes;
+ (BOOL)isNativeType:(NSString *)type;
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)type;
@property (copy) NSURL *fileURL;
@property (copy) NSString *fileType;
@property (copy) NSDate *fileModificationDate;
@property (readonly, copy) NSString *displayName;
- (void)setDisplayName:(NSString *)name;
- (NSString *)defaultDraftName;
@property (getter=isDraft) BOOL draft;
@property (readonly, getter=isDocumentEdited) BOOL documentEdited;
@property (readonly) BOOL hasUnautosavedChanges;
@property (retain) NSUndoManager *undoManager;
@property BOOL hasUndoManager;
- (void)updateChangeCount:(NSDocumentChangeType)change;
- (id)changeCountTokenForSaveOperation:(NSSaveOperationType)operation;
- (void)updateChangeCountWithToken:(id)token forSaveOperation:(NSSaveOperationType)operation;
/* reading */
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error;
- (BOOL)readFromFileWrapper:(NSFileWrapper *)wrapper ofType:(NSString *)type error:(NSError **)error;
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error;
- (BOOL)revertToContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error;
@property (readonly, getter=isEntireFileLoaded) BOOL entireFileLoaded;
/* writing */
- (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
                   error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
    originalContentsURL:(NSURL *)original error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error;
- (NSFileWrapper *)fileWrapperOfType:(NSString *)type error:(NSError **)error;
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error;
- (NSDictionary *)fileAttributesToWriteToURL:(NSURL *)url ofType:(NSString *)type
                            forSaveOperation:(NSSaveOperationType)operation originalContentsURL:(NSURL *)original
                                       error:(NSError **)error;
@property (readonly) BOOL keepBackupFile;
- (NSArray<NSString *> *)writableTypesForSaveOperation:(NSSaveOperationType)operation;
- (NSString *)fileNameExtensionForType:(NSString *)type saveOperation:(NSSaveOperationType)operation;
/* the calls before Mac OS X 10.4, still used by older apps */
- (BOOL)readFromFile:(NSString *)path ofType:(NSString *)type;
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type;
- (BOOL)loadDataRepresentation:(NSData *)data ofType:(NSString *)type;
- (BOOL)loadFileWrapperRepresentation:(NSFileWrapper *)wrapper ofType:(NSString *)type;
- (NSData *)dataRepresentationOfType:(NSString *)type;
- (NSFileWrapper *)fileWrapperRepresentationOfType:(NSString *)type;
- (BOOL)writeToFile:(NSString *)path ofType:(NSString *)type;
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type;
- (NSString *)fileName;
- (void)setFileName:(NSString *)name;
/* saving */
- (IBAction)saveDocument:(id)sender;
- (IBAction)saveDocumentAs:(id)sender;
- (IBAction)saveDocumentTo:(id)sender;
- (IBAction)revertDocumentToSaved:(id)sender;
- (IBAction)duplicateDocument:(id)sender;
- (IBAction)renameDocument:(id)sender;
- (IBAction)moveDocument:(id)sender;
- (IBAction)lockDocument:(id)sender;
- (IBAction)unlockDocument:(id)sender;
- (IBAction)browseDocumentVersions:(id)sender;
- (IBAction)printDocument:(id)sender;
- (IBAction)runPageLayout:(id)sender;
- (NSDocument *)duplicateAndReturnError:(NSError **)error;
- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)selector contextInfo:(void *)context;
- (void)runModalSavePanelForSaveOperation:(NSSaveOperationType)operation delegate:(id)delegate
                          didSaveSelector:(SEL)selector contextInfo:(void *)context;
- (BOOL)prepareSavePanel:(NSSavePanel *)panel;
@property (readonly) BOOL shouldRunSavePanelWithAccessoryView;
@property (readonly) BOOL fileNameExtensionWasHiddenInLastRunSavePanel;
@property (readonly, copy) NSString *fileTypeFromLastRunSavePanel;
- (void)saveToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
             delegate:(id)delegate didSaveSelector:(SEL)selector contextInfo:(void *)context;
- (void)saveToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
    completionHandler:(void (^)(NSError *error))handler;
- (BOOL)saveToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
            error:(NSError **)error;
/* autosaving (versions aren't kept: preservesVersions has no effect) */
@property (class, readonly) BOOL autosavesInPlace, autosavesDrafts, preservesVersions;
@property (copy) NSURL *autosavedContentsFileURL;
@property (readonly, copy) NSString *autosavingFileType;
@property (readonly) BOOL autosavingIsImplicitlyCancellable;
- (void)autosaveWithImplicitCancellability:(BOOL)cancellable completionHandler:(void (^)(NSError *error))handler;
- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)selector contextInfo:(void *)context;
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)error;
- (void)scheduleAutosaving;
/* closing */
- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)context;
- (void)shouldCloseWindowController:(NSWindowController *)controller delegate:(id)delegate
                shouldCloseSelector:(SEL)selector contextInfo:(void *)context;
- (void)close;
/* windows */
- (void)makeWindowControllers;
@property (readonly) NSString *windowNibName;
- (void)windowControllerWillLoadNib:(NSWindowController *)controller;
- (void)windowControllerDidLoadNib:(NSWindowController *)controller;
- (void)setWindow:(NSWindow *)window;
- (void)addWindowController:(NSWindowController *)controller;
- (void)removeWindowController:(NSWindowController *)controller;
@property (readonly, copy) NSArray<NSWindowController *> *windowControllers;
- (void)showWindows;
@property (readonly) NSWindow *windowForSheet;
@property (readonly, getter=isLocked) BOOL locked;
@property (readonly, getter=isInViewingMode) BOOL inViewingMode;
/* errors */
- (BOOL)presentError:(NSError *)error;
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)selector contextInfo:(void *)context;
- (NSError *)willPresentError:(NSError *)error;
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@interface NSDocumentController : NSObject <NSCoding, NSUserInterfaceValidations, NSMenuItemValidation>
@property (class, readonly) __kindof NSDocumentController *sharedDocumentController;
@property (readonly, copy) NSArray<__kindof NSDocument *> *documents;
@property (readonly) __kindof NSDocument *currentDocument;
@property (readonly, copy) NSString *currentDirectory;
- (void)addDocument:(NSDocument *)document;
- (void)removeDocument:(NSDocument *)document;
- (__kindof NSDocument *)documentForURL:(NSURL *)url;
- (__kindof NSDocument *)documentForWindow:(NSWindow *)window;
@property (readonly) BOOL hasEditedDocuments;
/* types */
@property (readonly, copy) NSArray<NSString *> *documentClassNames;
@property (readonly, copy) NSString *defaultType;
- (Class)documentClassForType:(NSString *)type;
- (NSString *)displayNameForType:(NSString *)type;
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)error;
- (NSString *)typeFromFileExtension:(NSString *)extension;
- (NSArray<NSString *> *)fileExtensionsFromType:(NSString *)type;
/* new documents */
- (IBAction)newDocument:(id)sender;
- (id)openUntitledDocumentAndDisplay:(BOOL)display error:(NSError **)error;
- (id)makeUntitledDocumentOfType:(NSString *)type error:(NSError **)error;
- (id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error;
- (id)makeDocumentForURL:(NSURL *)url withContentsOfURL:(NSURL *)contentsURL ofType:(NSString *)type
                   error:(NSError **)error;
/* opening */
- (IBAction)openDocument:(id)sender;
- (NSArray<NSURL *> *)URLsFromRunningOpenPanel;
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray<NSString *> *)types;
- (void)beginOpenPanelWithCompletionHandler:(void (^)(NSArray<NSURL *> *urls))handler;
- (void)beginOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray<NSString *> *)types
     completionHandler:(void (^)(NSInteger result))handler;
- (void)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display
                    completionHandler:(void (^)(NSDocument *document, BOOL alreadyOpen, NSError *error))handler;
- (id)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display error:(NSError **)error;
- (id)openDocumentWithContentsOfFile:(NSString *)path display:(BOOL)display;
/* closing */
- (void)closeAllDocumentsWithDelegate:(id)delegate didCloseAllSelector:(SEL)selector contextInfo:(void *)context;
- (void)reviewUnsavedDocumentsWithAlertTitle:(NSString *)title cancellable:(BOOL)cancellable delegate:(id)delegate
                        didReviewAllSelector:(SEL)selector contextInfo:(void *)context;
- (IBAction)saveAllDocuments:(id)sender;
/* the Recent Documents list, and the Open Recent menu it fills */
- (void)noteNewRecentDocument:(NSDocument *)document;
- (void)noteNewRecentDocumentURL:(NSURL *)url;
@property (readonly, copy) NSArray<NSURL *> *recentDocumentURLs;
@property (readonly) NSUInteger maximumRecentDocumentCount;
- (IBAction)clearRecentDocuments:(id)sender;
@property NSTimeInterval autosavingDelay;
/* errors */
- (BOOL)presentError:(NSError *)error;
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)selector contextInfo:(void *)context;
- (NSError *)willPresentError:(NSError *)error;
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

/* ---- printing (freemac 1.NEXT, Ferry 0.NEXT) ------------------------------------------- */

@class NSPrinter, NSPrintPanel, NSPrintOperation, NSPrintInfo, NSFontPanel, NSFontManager;
typedef NSString *NSPrintInfoAttributeKey;
typedef NSString *NSPrintJobDispositionValue;
typedef NSString *NSPrinterPaperName;
typedef NSString *NSPrintInfoSettingKey;
typedef NS_ENUM(NSInteger, NSPaperOrientation) { NSPaperOrientationPortrait = 0, NSPaperOrientationLandscape = 1 };
typedef NS_ENUM(NSUInteger, NSPrintingOrientation) { NSPortraitOrientation = 0, NSLandscapeOrientation = 1 };
typedef NS_ENUM(NSUInteger, NSPrintingPaginationMode) {
    NSPrintingPaginationModeAutomatic = 0, NSPrintingPaginationModeFit = 1, NSPrintingPaginationModeClip = 2,
    NSAutoPagination = 0, NSFitPagination = 1, NSClipPagination = 2
};
typedef NS_ENUM(NSInteger, NSPrintingPageOrder) {
    NSDescendingPageOrder = -1, NSSpecialPageOrder = 0, NSAscendingPageOrder = 1, NSUnknownPageOrder = 2
};
typedef NS_ENUM(NSInteger, NSPrintRenderingQuality) {
    NSPrintRenderingQualityBest = 0, NSPrintRenderingQualityResponsive = 1
};
typedef NS_OPTIONS(NSInteger, NSPrintPanelOptions) {
    NSPrintPanelShowsCopies = 1 << 0, NSPrintPanelShowsPageRange = 1 << 1, NSPrintPanelShowsPaperSize = 1 << 2,
    NSPrintPanelShowsOrientation = 1 << 3, NSPrintPanelShowsScaling = 1 << 4,
    NSPrintPanelShowsPrintSelection = 1 << 5, NSPrintPanelShowsPageSetupAccessory = 1 << 8,
    NSPrintPanelShowsPreview = 1 << 17
};
typedef NSString *NSPrintPanelJobStyleHint;
APPKIT_EXTERN NSPrintPanelJobStyleHint const NSPrintPhotoJobStyleHint, NSPrintAllPresetsJobStyleHint,
    NSPrintNoPresetsJobStyleHint;

APPKIT_EXTERN NSPrintInfoAttributeKey const NSPrintPaperName, NSPrintPaperSize, NSPrintOrientation,
    NSPrintScalingFactor, NSPrintLeftMargin, NSPrintRightMargin, NSPrintTopMargin, NSPrintBottomMargin,
    NSPrintHorizontallyCentered, NSPrintVerticallyCentered, NSPrintHorizontalPagination, NSPrintVerticalPagination,
    NSPrintPrinter, NSPrintCopies, NSPrintAllPages, NSPrintFirstPage, NSPrintLastPage, NSPrintMustCollate,
    NSPrintReversePageOrder, NSPrintJobDisposition, NSPrintJobSavingURL, NSPrintJobSavingFileNameExtensionHidden,
    NSPrintHeaderAndFooter, NSPrintSelectionOnly, NSPrintPagesAcross, NSPrintPagesDown, NSPrintTime,
    NSPrintDetailedErrorReporting, NSPrintPrinterName, NSPrintSavePath;
APPKIT_EXTERN NSPrintJobDispositionValue const NSPrintSpoolJob, NSPrintPreviewJob, NSPrintSaveJob, NSPrintCancelJob;

/* The printers this system's print service (CUPS) knows, asked with
 * lpstat when the program first wants them. */
@interface NSPrinter : NSObject <NSCopying, NSCoding>
@property (class, readonly, copy) NSArray<NSString *> *printerNames;
@property (class, readonly, copy) NSArray<NSString *> *printerTypes;
+ (NSPrinter *)printerWithName:(NSString *)name;
+ (NSPrinter *)printerWithType:(NSString *)type;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *type;
@property (readonly) NSInteger languageLevel;
@property (readonly, copy) NSDictionary *deviceDescription;
- (NSSize)pageSizeForPaper:(NSPrinterPaperName)paperName;
@end

@interface NSPrintInfo : NSObject <NSCopying, NSCoding>
@property (class, retain) NSPrintInfo *sharedPrintInfo;
@property (class, readonly) NSPrinter *defaultPrinter;
+ (NSSize)sizeForPaperName:(NSPrinterPaperName)name;
- (instancetype)initWithDictionary:(NSDictionary<NSPrintInfoAttributeKey, id> *)attributes;
@property (readonly, retain) NSMutableDictionary<NSPrintInfoAttributeKey, id> *dictionary;
@property (copy) NSPrinterPaperName paperName;
@property (readonly, copy) NSString *localizedPaperName;
@property NSSize paperSize;
@property NSPaperOrientation orientation;
@property CGFloat scalingFactor;
@property CGFloat leftMargin, rightMargin, topMargin, bottomMargin;
@property (getter=isHorizontallyCentered) BOOL horizontallyCentered;
@property (getter=isVerticallyCentered) BOOL verticallyCentered;
@property NSPrintingPaginationMode horizontalPagination, verticalPagination;
@property (copy) NSPrintJobDispositionValue jobDisposition;
@property (copy) NSPrinter *printer;
@property (getter=isSelectionOnly) BOOL selectionOnly;
@property (readonly) NSRect imageablePageBounds;
@property (readonly) NSMutableDictionary<NSPrintInfoSettingKey, id> *printSettings;
- (void)setUpPrintOperationDefaultValues;
- (void)updateFromPMPrintSettings;
- (void)updateFromPMPageFormat;
@end

@interface NSPrintPanel : NSObject
+ (NSPrintPanel *)printPanel;
@property NSPrintPanelOptions options;
@property (copy) NSPrintPanelJobStyleHint jobStyleHint;
@property (copy) NSString *helpAnchor, *defaultButtonTitle;
@property (readonly) NSPrintInfo *printInfo;
- (void)addAccessoryController:(NSViewController *)controller;
- (void)removeAccessoryController:(NSViewController *)controller;
@property (readonly, copy) NSArray<NSViewController *> *accessoryControllers;
- (NSInteger)runModal;
- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)printInfo;
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)printInfo modalForWindow:(NSWindow *)window delegate:(id)delegate
                 didEndSelector:(SEL)selector contextInfo:(void *)context;
- (void)beginSheetUsingPrintInfo:(NSPrintInfo *)printInfo onWindow:(NSWindow *)window
               completionHandler:(void (^)(NSInteger result))handler;
@end

@interface NSPageLayout : NSObject
+ (NSPageLayout *)pageLayout;
@property (readonly) NSPrintInfo *printInfo;
- (void)addAccessoryController:(NSViewController *)controller;
- (void)removeAccessoryController:(NSViewController *)controller;
@property (readonly, copy) NSArray<NSViewController *> *accessoryControllers;
- (NSInteger)runModal;
- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)printInfo;
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)printInfo modalForWindow:(NSWindow *)window delegate:(id)delegate
                 didEndSelector:(SEL)selector contextInfo:(void *)context;
- (void)beginSheetUsingPrintInfo:(NSPrintInfo *)printInfo onWindow:(NSWindow *)window
               completionHandler:(void (^)(NSInteger result))handler;
@end

@interface NSPrintOperation : NSObject
+ (NSPrintOperation *)printOperationWithView:(NSView *)view;
+ (NSPrintOperation *)printOperationWithView:(NSView *)view printInfo:(NSPrintInfo *)printInfo;
+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data;
+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
                                 printInfo:(NSPrintInfo *)printInfo;
+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toPath:(NSString *)path
                                 printInfo:(NSPrintInfo *)printInfo;
+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data;
+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
                                 printInfo:(NSPrintInfo *)printInfo;
+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toPath:(NSString *)path
                                 printInfo:(NSPrintInfo *)printInfo;
@property (class, retain) NSPrintOperation *currentOperation;
@property (readonly, getter=isCopyingOperation) BOOL copyingOperation;
@property (readonly) NSPrintRenderingQuality preferredRenderingQuality;
@property (copy) NSString *jobTitle;
@property BOOL showsPrintPanel, showsProgressPanel, canSpawnSeparateThread;
@property (retain) NSPrintPanel *printPanel;
@property NSPrintingPageOrder pageOrder;
@property (retain) NSPrintInfo *printInfo;
@property (readonly, retain) NSView *view;
@property (readonly) NSInteger currentPage;
@property (readonly) NSRange pageRange;
@property (readonly, retain) NSGraphicsContext *context;
- (BOOL)runOperation;
- (void)runOperationModalForWindow:(NSWindow *)window delegate:(id)delegate didRunSelector:(SEL)selector
                       contextInfo:(void *)context;
- (NSGraphicsContext *)createContext;
- (void)destroyContext;
- (BOOL)deliverResult;
- (void)cleanUpOperation;
@end

@interface NSView (NSPrinting)
- (IBAction)print:(id)sender;
- (NSData *)dataWithPDFInsideRect:(NSRect)rect;
- (NSData *)dataWithEPSInsideRect:(NSRect)rect;
- (void)writePDFInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard;
- (void)writeEPSInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard;
@property (readonly, copy) NSString *printJobTitle;
- (BOOL)knowsPageRange:(NSRangePointer)range;
- (NSRect)rectForPage:(NSInteger)page;
- (NSPoint)locationOfPrintRect:(NSRect)rect;
- (void)adjustPageWidthNew:(CGFloat *)newRight left:(CGFloat)left right:(CGFloat)right limit:(CGFloat)limit;
- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)top bottom:(CGFloat)bottom limit:(CGFloat)limit;
@property (readonly) CGFloat heightAdjustLimit, widthAdjustLimit;
- (void)beginDocument;
- (void)endDocument;
- (void)beginPageInRect:(NSRect)rect atPlacement:(NSPoint)location;
- (void)endPage;
- (void)drawPageBorderWithSize:(NSSize)borderSize;
- (void)drawSheetBorderWithSize:(NSSize)borderSize;
@property (readonly, copy) NSAttributedString *pageHeader, *pageFooter;
@end

@interface NSWindow (NSPrinting)
- (IBAction)print:(id)sender;
- (NSData *)dataWithPDFInsideRect:(NSRect)rect;
- (NSData *)dataWithEPSInsideRect:(NSRect)rect;
@end

@interface NSApplication (NSPrinting)
- (IBAction)runPageLayout:(id)sender;
@end

@interface NSDocument (NSPrinting)
@property (copy) NSPrintInfo *printInfo;
- (BOOL)shouldChangePrintInfo:(NSPrintInfo *)printInfo;
- (BOOL)preparePageLayout:(NSPageLayout *)pageLayout;
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo delegate:(id)delegate
                         didRunSelector:(SEL)selector contextInfo:(void *)context;
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary<NSPrintInfoAttributeKey, id> *)settings
                                           error:(NSError **)error;
- (void)printDocumentWithSettings:(NSDictionary<NSPrintInfoAttributeKey, id> *)settings
                   showPrintPanel:(BOOL)show delegate:(id)delegate didPrintSelector:(SEL)selector
                      contextInfo:(void *)context;
- (void)runModalPrintOperation:(NSPrintOperation *)operation delegate:(id)delegate didRunSelector:(SEL)selector
                   contextInfo:(void *)context;
- (void)printShowingPrintPanel:(BOOL)show;
@end

/* ---- the font manager and the font panel ---------------------------------------------- */

typedef NS_OPTIONS(NSUInteger, NSFontTraitMask) {
    NSItalicFontMask = 0x00000001, NSBoldFontMask = 0x00000002, NSUnboldFontMask = 0x00000004,
    NSNonStandardCharacterSetFontMask = 0x00000008, NSNarrowFontMask = 0x00000010,
    NSExpandedFontMask = 0x00000020, NSCondensedFontMask = 0x00000040, NSSmallCapsFontMask = 0x00000080,
    NSPosterFontMask = 0x00000100, NSCompressedFontMask = 0x00000200, NSFixedPitchFontMask = 0x00000400,
    NSUnitalicFontMask = 0x01000000
};
typedef NS_ENUM(NSUInteger, NSFontAction) {
    NSNoFontChangeAction = 0, NSViaPanelFontAction = 1, NSAddTraitFontAction = 2, NSSizeUpFontAction = 3,
    NSSizeDownFontAction = 4, NSHeavierFontAction = 5, NSLighterFontAction = 6, NSRemoveTraitFontAction = 7
};
typedef NS_OPTIONS(NSUInteger, NSFontPanelModeMask) {
    NSFontPanelModeMaskFace = 1 << 0, NSFontPanelModeMaskSize = 1 << 1, NSFontPanelModeMaskCollection = 1 << 2,
    NSFontPanelModesMaskStandardModes = 0xFFFF, NSFontPanelModesMaskAllModes = 0xFFFFFFFF
};

@protocol NSFontChanging <NSObject>
@optional
- (void)changeFont:(NSFontManager *)sender;
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel;
@end

@interface NSFontManager : NSObject <NSMenuItemValidation>
@property (class, readonly) NSFontManager *sharedFontManager;
+ (void)setFontManagerFactory:(Class)factoryClass;
+ (void)setFontPanelFactory:(Class)factoryClass;
@property (readonly, copy) NSArray<NSString *> *availableFonts;
@property (readonly, copy) NSArray<NSString *> *availableFontFamilies;
- (NSArray<NSArray *> *)availableMembersOfFontFamily:(NSString *)family;
- (NSArray<NSString *> *)availableFontNamesWithTraits:(NSFontTraitMask)traits;
- (NSFont *)fontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits weight:(NSInteger)weight
                      size:(CGFloat)size;
- (NSFont *)convertFont:(NSFont *)font;
- (NSFont *)convertFont:(NSFont *)font toFamily:(NSString *)family;
- (NSFont *)convertFont:(NSFont *)font toFace:(NSString *)typeface;
- (NSFont *)convertFont:(NSFont *)font toHaveTrait:(NSFontTraitMask)trait;
- (NSFont *)convertFont:(NSFont *)font toNotHaveTrait:(NSFontTraitMask)trait;
- (NSFont *)convertFont:(NSFont *)font toSize:(CGFloat)size;
- (NSFont *)convertWeight:(BOOL)upFlag ofFont:(NSFont *)font;
- (NSFontTraitMask)traitsOfFont:(NSFont *)font;
- (NSInteger)weightOfFont:(NSFont *)font;
- (BOOL)fontNamed:(NSString *)name hasTraits:(NSFontTraitMask)traits;
- (NSString *)localizedNameForFamily:(NSString *)family face:(NSString *)face;
@property (readonly, retain) NSFont *selectedFont;
- (void)setSelectedFont:(NSFont *)font isMultiple:(BOOL)flag;
@property (readonly, getter=isMultiple) BOOL multiple;
@property (readonly) NSFontAction currentFontAction;
@property SEL action;
@property (assign) id target;
@property (assign) id delegate;
@property (getter=isEnabled) BOOL enabled;
@property (retain) NSMenu *fontMenu;
- (NSMenu *)fontMenu:(BOOL)create;
- (NSFontPanel *)fontPanel:(BOOL)create;
- (BOOL)sendAction;
- (IBAction)addFontTrait:(id)sender;
- (IBAction)removeFontTrait:(id)sender;
- (IBAction)modifyFont:(id)sender;
- (IBAction)modifyFontViaPanel:(id)sender;
- (IBAction)orderFrontFontPanel:(id)sender;
- (IBAction)orderFrontStylesPanel:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@interface NSFontPanel : NSPanel
@property (class, readonly) NSFontPanel *sharedFontPanel;
@property (class, readonly) BOOL sharedFontPanelExists;
- (void)setPanelFont:(NSFont *)font isMultiple:(BOOL)flag;
- (NSFont *)panelConvertFont:(NSFont *)font;
@property (getter=isEnabled) BOOL enabled;
@property (retain) NSView *accessoryView;
- (void)reloadDefaultFontFamilies;
@end

@interface NSTextView (NSFontChanging) <NSFontChanging>
- (void)changeFont:(id)sender;
@end

#endif
