/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: tracking areas, tracking rectangles, cursor rectangles and
 * cursors (appkit/NSTrackingArea.m, appkit/NSCursor.m), imported by
 * AppKit.h. Written for freemac from Apple's public API documentation; not
 * Apple's header. */
#ifndef _FERRY_APPKIT_NSTRACKINGAREA_H_
#define _FERRY_APPKIT_NSTRACKINGAREA_H_
#import <Foundation/Foundation.h>

@class NSView, NSWindow, NSEvent, NSImage, NSColor, NSResponder;

typedef NS_OPTIONS(NSUInteger, NSTrackingAreaOptions) {
    NSTrackingMouseEnteredAndExited = 0x01,
    NSTrackingMouseMoved = 0x02,
    NSTrackingCursorUpdate = 0x04,
    NSTrackingActiveWhenFirstResponder = 0x10,
    NSTrackingActiveInKeyWindow = 0x20,
    NSTrackingActiveInActiveApp = 0x40,
    NSTrackingActiveAlways = 0x80,
    NSTrackingAssumeInside = 0x100,
    NSTrackingInVisibleRect = 0x200,
    NSTrackingEnabledDuringMouseDrag = 0x400,
};

typedef NSInteger NSTrackingRectTag;

@interface NSTrackingArea : NSObject <NSCopying, NSCoding>
- (instancetype FERRY_SWIFT_NONNULL)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options owner:(id)owner
                    userInfo:(NSDictionary *)userInfo;
@property (readonly) NSRect rect;
@property (readonly) NSTrackingAreaOptions options;
@property (readonly, assign) id owner;
@property (readonly, copy) NSDictionary *userInfo;
@end

@interface NSView (NSTrackingArea)
- (void)addTrackingArea:(NSTrackingArea *)trackingArea;
- (void)removeTrackingArea:(NSTrackingArea *)trackingArea;
@property (readonly, copy) NSArray<NSTrackingArea *> *trackingAreas;
- (void)updateTrackingAreas;
- (NSTrackingRectTag)addTrackingRect:(NSRect)rect owner:(id)owner userData:(void *)data assumeInside:(BOOL)flag;
- (void)removeTrackingRect:(NSTrackingRectTag)tag;
- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)cursor;
- (void)removeCursorRect:(NSRect)rect cursor:(NSCursor *)cursor;
- (void)discardCursorRects;
- (void)resetCursorRects;
@end

@interface NSWindow (NSCursorRects)
- (void)invalidateCursorRectsForView:(NSView *)view;
- (void)resetCursorRects;
- (void)discardCursorRects;
- (void)enableCursorRects;
- (void)disableCursorRects;
@property (readonly) BOOL areCursorRectsEnabled;
@end

@interface NSEvent (NSTrackingArea)
+ (NSEvent *)enterExitEventWithType:(NSEventType)type location:(NSPoint)location
                      modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                       windowNumber:(NSInteger)windowNumber context:(id)context eventNumber:(NSInteger)eventNumber
                     trackingNumber:(NSInteger)trackingNumber userData:(void *)userData;
@property (readonly) NSInteger trackingNumber;
@property (readonly) void *userData;
@property (readonly, retain) NSTrackingArea *trackingArea;
@end

@interface NSResponder (NSCursorUpdate)
- (void)cursorUpdate:(NSEvent *)event;
@end

@interface NSCursor : NSObject <NSCoding>
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL currentCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL currentSystemCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL arrowCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL IBeamCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL IBeamCursorForVerticalLayout;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL pointingHandCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL closedHandCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL openHandCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL resizeLeftCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL resizeRightCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL resizeLeftRightCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL resizeUpCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL resizeDownCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL resizeUpDownCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL crosshairCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL disappearingItemCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL operationNotAllowedCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL dragLinkCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL dragCopyCursor;
@property (class, readonly, retain) NSCursor * FERRY_SWIFT_NONNULL contextualMenuCursor;
+ (void)hide;
+ (void)unhide;
+ (void)setHiddenUntilMouseMoves:(BOOL)flag;
+ (void)pop;
- (instancetype)initWithImage:(NSImage *)image hotSpot:(NSPoint)hotSpot;
- (instancetype)initWithImage:(NSImage *)image foregroundColorHint:(NSColor *)fg
          backgroundColorHint:(NSColor *)bg hotSpot:(NSPoint)hotSpot;
@property (readonly, retain) NSImage *image;
@property (readonly) NSPoint hotSpot;
- (void)set;
- (void)push;
- (void)pop;
@property (getter=isSetOnMouseEntered) BOOL onMouseEntered;
@property (getter=isSetOnMouseExited) BOOL onMouseExited;
- (void)mouseEntered:(NSEvent *)event;
- (void)mouseExited:(NSEvent *)event;
@end

#endif
