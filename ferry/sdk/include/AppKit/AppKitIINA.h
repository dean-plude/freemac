/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What the IINA video player calls besides the rest of AppKit (freemac
 * 1.262, Ferry 0.85.0): a window's aspect ratio and dragging a window
 * from its content, gesture recognizers, a reversed Bézier path, colour
 * effects, the menu bar's visibility and a text view's selected ranges.
 * Written from Apple's public documentation; not Apple's header.
 * Implemented in appkit/AppKitIINA.m. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_IINA_H_
#define _FERRY_APPKIT_IINA_H_

/* ---- windows ------------------------------------------------------------------------------
 * The shape a window keeps while the user resizes it; zero for none. The
 * content's ratio is passed on to the window system. */
@interface NSWindow (FerryAspectRatio)
@property NSSize aspectRatio;
@property NSSize contentAspectRatio;
/* Starts moving the window with the pointer, from a mouse-down event. */
- (void)performWindowDragWithEvent:(NSEvent *)event;
@end

/* ---- gesture recognizers ------------------------------------------------------------------
 * Kept with their view, target and action. They don't fire yet: Ferry's
 * windows get no trackpad gestures, and the view's own mouse methods
 * still see every click. */
typedef NS_ENUM(NSInteger, NSGestureRecognizerState) {
    NSGestureRecognizerStatePossible, NSGestureRecognizerStateBegan, NSGestureRecognizerStateChanged,
    NSGestureRecognizerStateEnded, NSGestureRecognizerStateCancelled, NSGestureRecognizerStateFailed,
    NSGestureRecognizerStateRecognized = NSGestureRecognizerStateEnded,
};
@class NSGestureRecognizer;
@protocol NSGestureRecognizerDelegate <NSObject>
@optional
- (BOOL)gestureRecognizerShouldBegin:(NSGestureRecognizer *)gestureRecognizer;
@end
@interface NSGestureRecognizer : NSObject <NSCoding>
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@property (weak) id target;
@property SEL action;
@property (readonly) NSGestureRecognizerState state;
@property (weak) id<NSGestureRecognizerDelegate> delegate;
@property (getter=isEnabled) BOOL enabled;
@property (readonly, weak) NSView *view;
@property BOOL delaysPrimaryMouseButtonEvents, delaysSecondaryMouseButtonEvents;
- (NSPoint)locationInView:(NSView *)view;
@end
@interface NSClickGestureRecognizer : NSGestureRecognizer
@property NSUInteger buttonMask, numberOfClicksRequired, numberOfTouchesRequired;
@end
@interface NSPressGestureRecognizer : NSGestureRecognizer
@property NSUInteger buttonMask, numberOfTouchesRequired;
@property NSTimeInterval minimumPressDuration;
@property CGFloat allowableMovement;
@end
@interface NSPanGestureRecognizer : NSGestureRecognizer
@property NSUInteger buttonMask, numberOfTouchesRequired;
- (NSPoint)translationInView:(NSView *)view;
- (void)setTranslation:(NSPoint)translation inView:(NSView *)view;
- (NSPoint)velocityInView:(NSView *)view;
@end
@interface NSMagnificationGestureRecognizer : NSGestureRecognizer
@property CGFloat magnification;
@end
@interface NSRotationGestureRecognizer : NSGestureRecognizer
@property CGFloat rotation, rotationInDegrees;
@end
@interface NSView (FerryGestureRecognizers)
@property (copy) NSArray<NSGestureRecognizer *> *gestureRecognizers;
- (void)addGestureRecognizer:(NSGestureRecognizer *)gestureRecognizer;
- (void)removeGestureRecognizer:(NSGestureRecognizer *)gestureRecognizer;
@end

/* ---- the rest -------------------------------------------------------------------------- */
@interface NSBezierPath (FerryReversing)
/* the same path, each subpath drawn from its end to its start */
@property (readonly, strong) NSBezierPath *bezierPathByReversingPath;
@end
typedef NS_ENUM(NSInteger, NSColorSystemEffect) {
    NSColorSystemEffectNone, NSColorSystemEffectPressed, NSColorSystemEffectDeepPressed,
    NSColorSystemEffectDisabled, NSColorSystemEffectRollover,
};
@interface NSColor (FerrySystemEffect)
/* pressed is a little darker, disabled half transparent, the rest itself */
- (NSColor *)colorWithSystemEffect:(NSColorSystemEffect)systemEffect;
@end
@interface NSMenu (FerryMenuBarVisible)
/* kept; freemac's menu bar is always shown */
+ (BOOL)menuBarVisible;
+ (void)setMenuBarVisible:(BOOL)visible;
@end
@interface NSTextView (FerrySelectedRanges)
/* the first range is selected: Ferry's text view keeps one selection */
- (void)setSelectedRanges:(NSArray<NSValue *> *)ranges;
@end
@interface NSApplication (FerryTouchBarCustomization)
- (IBAction)toggleTouchBarCustomizationPalette:(id)sender;   /* no Touch Bar: does nothing */
@end

#endif
