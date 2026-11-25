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

#endif
