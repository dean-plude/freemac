/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What VLC's Mac interface calls besides the rest of AppKit (freemac 1.233,
 * Ferry 0.57.0): the drawing and tracking methods custom cells override
 * and call on super, the scroller's arrows, the application's presentation
 * options, alert sheets, the visual effect view, and a few names of
 * windows, views, events, images and screens. Written from Apple's public
 * documentation; not Apple's header. Implemented in appkit/AppKitVLC.m.
 * Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_VLC_H_
#define _FERRY_APPKIT_VLC_H_

/* ---- the application's presentation options ----------------------------------------- */

typedef NS_OPTIONS(NSUInteger, NSApplicationPresentationOptions) {
    NSApplicationPresentationDefault = 0,
    NSApplicationPresentationAutoHideDock = 1 << 0,
    NSApplicationPresentationHideDock = 1 << 1,
    NSApplicationPresentationAutoHideMenuBar = 1 << 2,
    NSApplicationPresentationHideMenuBar = 1 << 3,
    NSApplicationPresentationDisableAppleMenu = 1 << 4,
    NSApplicationPresentationDisableProcessSwitching = 1 << 5,
    NSApplicationPresentationDisableForceQuit = 1 << 6,
    NSApplicationPresentationDisableSessionTermination = 1 << 7,
    NSApplicationPresentationDisableHideApplication = 1 << 8,
    NSApplicationPresentationDisableMenuBarTransparency = 1 << 9,
    NSApplicationPresentationFullScreen = 1 << 10,
    NSApplicationPresentationAutoHideToolbar = 1 << 11,
    NSApplicationPresentationDisableCursorLocationAssistance = 1 << 12,
};
/* Kept as set; currentSystemPresentationOptions adds FullScreen while one
 * of the app's windows is full screen. */
@interface NSApplication (FerryPresentationOptions)
@property NSApplicationPresentationOptions presentationOptions;
@property (readonly) NSApplicationPresentationOptions currentSystemPresentationOptions;
@end
APPKIT_EXTERN NSNotificationName const NSApplicationDidChangeScreenParametersNotification;
APPKIT_EXTERN NSNotificationName const NSWindowWillMiniaturizeNotification;

/* ---- sheets the old way ------------------------------------------------------------- */

/* An alert run as a sheet on docWindow (or as a window of its own with
 * none). The buttons answer NSAlertDefaultReturn, NSAlertAlternateReturn
 * and NSAlertOtherReturn; the delegate is sent didEndSelector
 * (sheet:returnCode:contextInfo:) when one is pressed. */
APPKIT_EXTERN void NSBeginAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton,
                                     NSString *otherButton, NSWindow *docWindow, id modalDelegate,
                                     SEL didEndSelector, SEL didDismissSelector, void *contextInfo,
                                     NSString *msgFormat, ...) NS_FORMAT_FUNCTION(10, 11);
APPKIT_EXTERN void NSBeginInformationalAlertSheet(NSString *title, NSString *defaultButton,
                                                  NSString *alternateButton, NSString *otherButton,
                                                  NSWindow *docWindow, id modalDelegate, SEL didEndSelector,
                                                  SEL didDismissSelector, void *contextInfo,
                                                  NSString *msgFormat, ...) NS_FORMAT_FUNCTION(10, 11);
APPKIT_EXTERN void NSBeginCriticalAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton,
                                             NSString *otherButton, NSWindow *docWindow, id modalDelegate,
                                             SEL didEndSelector, SEL didDismissSelector, void *contextInfo,
                                             NSString *msgFormat, ...) NS_FORMAT_FUNCTION(10, 11);

/* ---- drawing ------------------------------------------------------------------------ */

APPKIT_EXTERN void NSFrameRectWithWidthUsingOperation(NSRect rect, CGFloat width, NSCompositingOperation op);
/* the grays of NSDrawTiledRects and NSDrawWhiteBezel */
APPKIT_EXTERN const CGFloat NSBlack, NSDarkGray, NSLightGray, NSWhite;

/* ---- cells: tracking, and the parts a subclass draws -------------------------------- */

@interface NSCell (FerryTracking)
/* Called by trackMouse:inRect:ofView:untilMouseUp: as the mouse goes
 * down, moves and comes up; YES carries on tracking. */
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView;
- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView;
- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag;
/* the control's, or left to right */
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@end

@interface NSSliderCell (FerryDrawing)
@property (readonly) CGFloat knobThickness;
/* the bar's rectangle in the control, as drawing last placed it */
@property (readonly) NSRect trackRect;
- (NSRect)knobRectFlipped:(BOOL)flipped;
- (NSRect)barRectFlipped:(BOOL)flipped;
- (void)drawKnob;
- (void)drawKnob:(NSRect)knobRect;
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped;
- (void)drawTickMarks;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (double)closestTickMarkValueToValue:(double)value;
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point;
@end

@interface NSButtonCell (FerryDrawing)
/* The three parts drawInteriorWithFrame:inView: and drawWithFrame:inView:
 * are made of; the title's rectangle is returned. */
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView;
- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView;
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView;
@property BOOL showsBorderOnlyWhileMouseInside;
@end
@interface NSButton (FerryBorderWhileInside)
@property BOOL showsBorderOnlyWhileMouseInside;
@end

@interface NSSegmentedCell (FerryDrawing)
- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(NSView *)controlView;
@end

/* ---- the scroller's arrows, which Ferry's scrollers don't show ---------------------- */

typedef NS_ENUM(NSUInteger, NSScrollerArrow) { NSScrollerIncrementArrow = 0, NSScrollerDecrementArrow = 1 };
typedef NS_ENUM(NSUInteger, NSUsableScrollerParts) {
    NSNoScrollerParts = 0, NSOnlyScrollerArrows = 1, NSAllScrollerParts = 2,
};
typedef NS_ENUM(NSUInteger, NSScrollArrowPosition) {
    NSScrollerArrowsMaxEnd = 0, NSScrollerArrowsMinEnd = 1, NSScrollerArrowsDefaultSetting = 0,
    NSScrollerArrowsNone = 2,
};
@interface NSScroller (FerryArrows)
@property (readonly) NSUsableScrollerParts usableParts;
@property NSScrollArrowPosition arrowsPosition;
- (void)drawArrow:(NSScrollerArrow)arrow highlight:(BOOL)flag;
- (void)drawParts;
- (void)highlight:(BOOL)flag;
@end

/* ---- views, controls and windows ---------------------------------------------------- */

@interface NSView (FerryVLC)
/* the closest view both are inside, or nil */
- (NSView *)ancestorSharedWithView:(NSView *)view;
/* clipsToBounds is in AppKitNewer.h */
@end

@interface NSControl (FerryNeedsDisplay)
/* setNeedsDisplay:YES */
- (void)setNeedsDisplay;
@end

@interface NSTextField (FerryTextDelegate)
/* the field editor's notifications, which the field passes on to its delegate */
- (void)textDidBeginEditing:(NSNotification *)notification;
- (void)textDidChange:(NSNotification *)notification;
- (void)textDidEndEditing:(NSNotification *)notification;
@end

@interface NSWindow (FerryVLC)
/* Ferry draws a window whole each time; kept as set */
- (void)useOptimizedDrawing:(BOOL)flag;
/* the rectangle moved, and shrunk if need be, to keep its title bar on the
 * screen's visible frame */
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen;
/* Ferry shows a window's drawing once it's flushed anyway: nothing to hold */
- (void)disableScreenUpdatesUntilFlush;
@end

/* a layer-backed view's say in its layers' scale when the window moves to a
 * screen of another scale (VLC's video layer) */
@protocol NSViewLayerContentScaleDelegate <NSObject>
@optional
- (BOOL)layer:(CALayer *)layer shouldInheritContentsScale:(CGFloat)newScale fromWindow:(NSWindow *)window;
@end

/* ---- events ------------------------------------------------------------------------- */

typedef NS_ENUM(short, NSEventSubtype) {
    NSEventSubtypeWindowExposed = 0, NSEventSubtypeApplicationActivated = 1,
    NSEventSubtypeApplicationDeactivated = 2, NSEventSubtypeWindowMoved = 4, NSEventSubtypeScreenChanged = 8,
    NSEventSubtypePowerOff = 1, NSEventSubtypeMouseEvent = 0, NSEventSubtypeTabletPoint = 1,
    NSEventSubtypeTabletProximity = 2, NSEventSubtypeTouch = 3,
};
#define NSMouseEventSubtype NSEventSubtypeMouseEvent
#define NSTabletPointEventSubtype NSEventSubtypeTabletPoint
#define NSTabletProximityEventSubtype NSEventSubtypeTabletProximity
#define NSTouchEventSubtype NSEventSubtypeTouch
@interface NSEvent (FerryGestures)
/* a pinch's change of scale; Ferry's PCs send none, so 0 */
@property (readonly) CGFloat magnification;
/* whether the scroll deltas are the other way round from the fingers' */
@property (readonly, getter=isDirectionInvertedFromDevice) BOOL directionInvertedFromDevice;
@end

/* ---- images and screens ------------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSImageResizingMode) { NSImageResizingModeTile = 0, NSImageResizingModeStretch = 1 };
@interface NSImage (FerryCapInsets)
/* Drawn bigger than it is, the image keeps its edges this wide and
 * stretches (or tiles) the middle. */
@property NSEdgeInsets capInsets;
@property NSImageResizingMode resizingMode;
@end

@interface NSScreen (FerryVLC)
/* the screen with the most colours: the main one */
+ (NSScreen *)deepestScreen;
/* a PC's screen has no notch */
@property (readonly) NSEdgeInsets safeAreaInsets;
@property (readonly) NSRect auxiliaryTopLeftArea, auxiliaryTopRightArea;
@end

/* ---- the visual effect view --------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSVisualEffectMaterial) {
    NSVisualEffectMaterialAppearanceBased = 0, NSVisualEffectMaterialLight = 1, NSVisualEffectMaterialDark = 2,
    NSVisualEffectMaterialTitlebar = 3, NSVisualEffectMaterialSelection = 4, NSVisualEffectMaterialMenu = 5,
    NSVisualEffectMaterialPopover = 6, NSVisualEffectMaterialSidebar = 7, NSVisualEffectMaterialMediumLight = 8,
    NSVisualEffectMaterialUltraDark = 9, NSVisualEffectMaterialHeaderView = 10, NSVisualEffectMaterialSheet = 11,
    NSVisualEffectMaterialWindowBackground = 12, NSVisualEffectMaterialHUDWindow = 13,
    NSVisualEffectMaterialFullScreenUI = 15, NSVisualEffectMaterialToolTip = 17,
    NSVisualEffectMaterialContentBackground = 18, NSVisualEffectMaterialUnderWindowBackground = 21,
    NSVisualEffectMaterialUnderPageBackground = 22,
};
typedef NS_ENUM(NSInteger, NSVisualEffectBlendingMode) {
    NSVisualEffectBlendingModeBehindWindow = 0, NSVisualEffectBlendingModeWithinWindow = 1,
};
typedef NS_ENUM(NSInteger, NSVisualEffectState) {
    NSVisualEffectStateFollowsWindowActiveState = 0, NSVisualEffectStateActive = 1,
    NSVisualEffectStateInactive = 2,
};
/* Ferry doesn't blur what is behind: the view fills with its material's
 * colour, nearly opaque, and keeps the mask image's shape if it has one. */
@interface NSVisualEffectView : NSView
@property NSVisualEffectMaterial material;
@property NSVisualEffectBlendingMode blendingMode;
@property NSVisualEffectState state;
@property (getter=isEmphasized) BOOL emphasized;
@property (retain) NSImage *maskImage;
@property (readonly) NSBackgroundStyle interiorBackgroundStyle;
@end

/* ---- the workspace's file system queries -------------------------------------------- */

@interface NSWorkspace (FerryFileSystemInfo)
/* From the mount the path is on: removable and unmountable when it is
 * under /media or /run/media, writable unless mounted read-only; type is
 * the file system's name (ext4, vfat, ...). */
- (BOOL)getFileSystemInfoForPath:(NSString *)fullPath isRemovable:(BOOL *)removableFlag
                      isWritable:(BOOL *)writableFlag isUnmountable:(BOOL *)unmountableFlag
                     description:(NSString **)description type:(NSString **)fileSystemType;
@end
@interface NSWorkspace (FerryRemovableMedia)
/* the mount points of removable disks: those under /media, /run/media and /Volumes */
- (NSArray<NSString *> *)mountedRemovableMedia;
@end

/* ---- attributed strings ------------------------------------------------------------- */

/* NSWindow answers it (NSWindow.m) */
@interface NSWindow (FerryValidateMenuItem)
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

/* a control's selected cell is its one cell; NSMatrix answers its own */
@interface NSControl (FerrySelectedCell)
@property (readonly, strong) __kindof NSCell *selectedCell;
@end

APPKIT_EXTERN NSAttributedStringDocumentReadingOptionKey const NSBaseURLDocumentOption;
@interface NSAttributedString (FerryHTMLOptions)
- (instancetype)initWithHTML:(NSData *)data options:(NSDictionary *)options
          documentAttributes:(NSDictionary **)attributes;
@end
@interface NSMutableAttributedString (FerryAlignment)
/* the range's paragraphs get a paragraph style with this alignment */
- (void)setAlignment:(NSTextAlignment)alignment range:(NSRange)range;
- (void)setBaseWritingDirection:(NSWritingDirection)direction range:(NSRange)range;
@end

#endif
