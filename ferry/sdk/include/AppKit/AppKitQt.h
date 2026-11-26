/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: what Qt's Mac platform plugin (the part of Qt that puts its
 * windows on a Mac's screen, which OBS Studio is built on) calls of AppKit
 * besides the rest, written from Apple's public AppKit documentation; not
 * Apple's header. Served from AppKit's file (appkit/AppKitQt.m). */
#ifndef _FERRY_APPKIT_APPKITQT_H_
#define _FERRY_APPKIT_APPKITQT_H_

/* ---- text input ------------------------------------------------------------------
 * A view that takes typed text conforms to NSTextInputClient; its input
 * context hands each key press to it, as the key bindings Ferry knows
 * (interpretKeyEvents:) do: a command such as moveLeft: or insertNewline:
 * goes to doCommandBySelector:, other characters to insertText:. Ferry has
 * no input methods that compose text yet, so nothing is ever marked. */
@protocol NSTextInputClient
@required
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange;
- (void)unmarkText;
- (NSRange)selectedRange;
- (NSRange)markedRange;
- (BOOL)hasMarkedText;
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange;
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText;
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange;
- (NSUInteger)characterIndexForPoint:(NSPoint)point;
@optional
- (NSAttributedString *)attributedString;
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point;
- (CGFloat)baselineDeltaForCharacterAtIndex:(NSUInteger)anIndex;
- (NSInteger)windowLevel;
- (BOOL)drawsVerticallyForCharacterAtIndex:(NSUInteger)charIndex;
@end

typedef NSString *NSTextInputSourceIdentifier;

@interface NSTextInputContext : NSObject
/* the context of the key window's first responder, or nil */
@property (class, readonly) NSTextInputContext *currentInputContext;
- (instancetype)initWithClient:(id<NSTextInputClient>)client;
@property (readonly) id<NSTextInputClient> client;
@property BOOL acceptsGlyphInfo;
@property (copy) NSArray<NSString *> *allowedInputSourceLocales;
- (void)activate;
- (void)deactivate;
/* YES when the event was a key press the client was given */
- (BOOL)handleEvent:(NSEvent *)event;
- (void)discardMarkedText;
- (void)invalidateCharacterCoordinates;
@property (readonly) NSArray<NSTextInputSourceIdentifier> *keyboardInputSources;
@property (copy) NSTextInputSourceIdentifier selectedKeyboardInputSource;
+ (NSString *)localizedNameForInputSource:(NSTextInputSourceIdentifier)inputSourceIdentifier;
@end

@interface NSView (FerryTextInput)
/* a context for a view that conforms to NSTextInputClient, else nil */
@property (readonly, retain) NSTextInputContext *inputContext;
@end

/* ---- screens ---------------------------------------------------------------------- */

typedef int NSWindowDepth;
enum {
    NSWindowDepthTwentyfourBitRGB = 0x208,
    NSWindowDepthSixtyfourBitRGB = 0x210,
    NSWindowDepthOnehundredtwentyeightBitRGB = 0x220
};
APPKIT_EXTERN NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth);
APPKIT_EXTERN NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth);
APPKIT_EXTERN NSInteger NSNumberOfColorComponents(NSString *colorSpaceName);

@interface NSScreen (FerryDepth)
/* every PC screen Ferry draws on is 8-bit RGB, in sRGB */
@property (readonly) NSWindowDepth depth;
@property (readonly) const NSWindowDepth *supportedWindowDepths;
@property (readonly, retain) NSColorSpace *colorSpace;
/* NO: Ferry's spaces span all the screens */
@property (class, readonly) BOOL screensHaveSeparateSpaces;
/* 1: Ferry draws in standard range */
@property (readonly) CGFloat maximumExtendedDynamicRangeColorComponentValue;
@property (readonly) CGFloat maximumPotentialExtendedDynamicRangeColorComponentValue;
@property (readonly) CGFloat maximumReferenceExtendedDynamicRangeColorComponentValue;
@end

@interface NSColorSpace (FerryICC)
- (instancetype)initWithICCProfileData:(NSData *)iccData;
/* the colour space's ICC profile, as Core Graphics writes one */
@property (readonly) NSData *ICCProfileData;
@end

/* ---- keys ------------------------------------------------------------------------- */

@interface NSEvent (FerryKeyRepeat)
/* the pause before a held key repeats, and the time between repeats */
@property (class, readonly) NSTimeInterval keyRepeatDelay;
@property (class, readonly) NSTimeInterval keyRepeatInterval;
@end

/* ---- windows ---------------------------------------------------------------------- */

typedef NS_OPTIONS(NSInteger, NSWindowListOptions) { NSWindowListOrderedFrontToBack = (1 << 0) };

@interface NSApplication (FerryWindowList)
/* the app's windows, front to back with NSWindowListOrderedFrontToBack */
- (void)enumerateWindowsWithOptions:(NSWindowListOptions)options
                         usingBlock:(void (^)(NSWindow *window, BOOL *stop))block;
@end

/* Ferry's window manager resizes windows itself, so these are never posted. */
APPKIT_EXTERN NSNotificationName const NSWindowWillStartLiveResizeNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidEndLiveResizeNotification;

/* ---- open and save panels: their file types as UTTypes (macOS 11) ------------------ */

@interface NSSavePanel (FerryContentTypes)
@property (copy) NSArray<UTType *> *allowedContentTypes;
@end

/* ---- Handoff ---------------------------------------------------------------------- */

@protocol NSUserActivityRestoring <NSObject>
- (void)restoreUserActivityState:(NSUserActivity *)userActivity;
@end


/* ---- touches and tablets ----------------------------------------------------------
 * Ferry gets no touches from trackpads or touch screens, and no tablet
 * events, so a touch set is always empty; the names are there for programs
 * that look for them. */

typedef NS_OPTIONS(NSUInteger, NSTouchPhase) {
    NSTouchPhaseBegan = 1U << 0, NSTouchPhaseMoved = 1U << 1, NSTouchPhaseStationary = 1U << 2,
    NSTouchPhaseEnded = 1U << 3, NSTouchPhaseCancelled = 1U << 4,
    NSTouchPhaseTouching = NSTouchPhaseBegan | NSTouchPhaseMoved | NSTouchPhaseStationary,
    NSTouchPhaseAny = NSUIntegerMax
};
typedef NS_ENUM(NSInteger, NSTouchType) { NSTouchTypeDirect = 0, NSTouchTypeIndirect = 1 };
typedef NS_OPTIONS(NSUInteger, NSTouchTypeMask) {
    NSTouchTypeMaskDirect = 1U << NSTouchTypeDirect, NSTouchTypeMaskIndirect = 1U << NSTouchTypeIndirect
};

@interface NSTouch : NSObject <NSCopying>
@property (readonly, retain) id<NSObject, NSCopying> identity;
@property (readonly) NSTouchPhase phase;
@property (readonly) NSPoint normalizedPosition;
@property (readonly, getter=isResting) BOOL resting;
@property (readonly, retain) id device;
@property (readonly) NSSize deviceSize;
@property (readonly) NSTouchType type;
- (NSPoint)locationInView:(NSView *)view;
- (NSPoint)previousLocationInView:(NSView *)view;
@end

typedef NS_OPTIONS(NSUInteger, NSEventButtonMask) {
    NSEventButtonMaskPenTip = 1, NSEventButtonMaskPenLowerSide = 2, NSEventButtonMaskPenUpperSide = 4
};
typedef NS_ENUM(NSUInteger, NSPointingDeviceType) {
    NSPointingDeviceTypeUnknown = 0, NSPointingDeviceTypePen = 1, NSPointingDeviceTypeCursor = 2,
    NSPointingDeviceTypeEraser = 3
};

@interface NSEvent (FerryTouchesAndTablets)
- (NSSet<NSTouch *> *)touchesMatchingPhase:(NSTouchPhase)phase inView:(NSView *)view;
- (NSSet<NSTouch *> *)allTouches;
- (NSSet<NSTouch *> *)touchesForView:(NSView *)view;
/* the device an event came from: 0, as Ferry tells its pointers apart by no number */
@property (readonly) NSUInteger deviceID;
/* a gesture's turn in degrees, counterclockwise (0 off rotate events) */
@property (readonly) float rotation;
/* tablet values: none, as Ferry gets no tablet events */
@property (readonly) NSInteger absoluteX, absoluteY, absoluteZ;
@property (readonly) NSEventButtonMask buttonMask;
@property (readonly) NSPoint tilt;
@property (readonly) float tangentialPressure;
@property (readonly, retain) NSArray *vendorDefined;
@property (readonly) NSUInteger vendorID, tabletID, pointingDeviceID, systemTabletID, vendorPointingDeviceType,
    pointingDeviceSerialNumber, capabilityMask;
@property (readonly) unsigned long long uniqueID;
@property (readonly) NSPointingDeviceType pointingDeviceType;
@property (readonly, getter=isEnteringProximity) BOOL enteringProximity;
@end

@interface NSView (FerryTouches)
@property NSTouchTypeMask allowedTouchTypes;
@property BOOL wantsRestingTouches;
@end

/* ---- layers ----------------------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSViewLayerContentsPlacement) {
    NSViewLayerContentsPlacementScaleAxesIndependently = 0,
    NSViewLayerContentsPlacementScaleProportionallyToFit = 1,
    NSViewLayerContentsPlacementScaleProportionallyToFill = 2,
    NSViewLayerContentsPlacementCenter = 3,
    NSViewLayerContentsPlacementTop = 4,
    NSViewLayerContentsPlacementTopRight = 5,
    NSViewLayerContentsPlacementRight = 6,
    NSViewLayerContentsPlacementBottomRight = 7,
    NSViewLayerContentsPlacementBottom = 8,
    NSViewLayerContentsPlacementBottomLeft = 9,
    NSViewLayerContentsPlacementLeft = 10,
    NSViewLayerContentsPlacementTopLeft = 11
};

@interface NSView (FerryLayerPlacement)
@property NSViewLayerContentsPlacement layerContentsPlacement;
@end

/* ---- windows: colour, resize steps, tabs, full screen ------------------------------ */

typedef NS_ENUM(NSInteger, NSWindowTabbingMode) {
    NSWindowTabbingModeAutomatic = 0, NSWindowTabbingModePreferred = 1, NSWindowTabbingModeDisallowed = 2
};
typedef NSString *NSWindowTabbingIdentifier;

@interface NSWindow (FerryQtWindow)
/* the screen's colour space, sRGB, unless one is set */
@property (retain) NSColorSpace *colorSpace;
@property BOOL displaysWhenScreenProfileChanges;
/* steps a window's size moves in when the person resizes it; Ferry's window
 * manager resizes freely, so they are kept but not followed */
@property NSSize resizeIncrements, contentResizeIncrements;
/* NO for a window; NSPanel sets its own */
@property (readonly) BOOL worksWhenModal;
/* Ferry's windows have no tabs, so tabbing modes are kept and nothing else */
@property NSWindowTabbingMode tabbingMode;
@property (copy) NSWindowTabbingIdentifier tabbingIdentifier;
@property (class) BOOL allowsAutomaticWindowTabbing;
@property (class, readonly) NSWindowTabbingMode userTabbingPreference;
@end

APPKIT_EXTERN NSNotificationName const NSWindowWillEnterFullScreenNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidEnterFullScreenNotification;
APPKIT_EXTERN NSNotificationName const NSWindowWillExitFullScreenNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidExitFullScreenNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidChangeScreenProfileNotification;

/* ---- Services menu ---------------------------------------------------------------- */

@protocol NSServicesMenuRequestor <NSObject>
@optional
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray<NSPasteboardType> *)types;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard;
@end


/* ---- scroller knobs and the menu bar's height -------------------------------------- */

typedef NS_ENUM(NSInteger, NSScrollerKnobStyle) {
    NSScrollerKnobStyleDefault = 0, NSScrollerKnobStyleDark = 1, NSScrollerKnobStyleLight = 2,
};
APPKIT_EXTERN NSNotificationName const NSPreferredScrollerStyleDidChangeNotification;

@interface NSMenu (FerryMenuBarHeight)
/* the height of the strip the main menu takes at the top of the screen; 0 for
 * any other menu */
@property (readonly) CGFloat menuBarHeight;
@end

#endif
