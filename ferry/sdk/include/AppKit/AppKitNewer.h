/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Newer AppKit names that menu-bar apps written for macOS 11 to 26 call,
 * Itsycal's among them (freemac 1.232, Ferry 0.56.0): safe areas, display
 * links, window occlusion, symbol configurations, section headers and
 * image visibility in menus, the system fill colours and dynamic colours,
 * full-size popovers, scroll phases and swipe tracking, and a few control
 * switches; and a few older calls of cells and text fields that Gas Mask
 * makes. Written from Apple's public documentation; not Apple's header.
 * Implemented in appkit/AppKitNewer.m. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_NEWER_H_
#define _FERRY_APPKIT_NEWER_H_

/* ---- views ------------------------------------------------------------------------------
 * The safe area is the whole view: Ferry's windows put nothing over their
 * content (no title bar drawn over a full-size content view, no notch). */
@interface NSView (FerrySafeArea)
@property (readonly, strong) NSLayoutGuide *safeAreaLayoutGuide;
@property (readonly) NSEdgeInsets safeAreaInsets;
@property (readonly) NSRect safeAreaRect;
@property BOOL clipsToBounds;    /* kept; a view's drawing is always clipped to it */
@end

/* A display link at 60 frames a second that calls target with itself
 * (QuartzCore's CADisplayLink). */
@interface NSView (FerryDisplayLink)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector;
@end
@interface NSWindow (FerryDisplayLink)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector;
@end
@interface NSScreen (FerryDisplayLink)
- (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector;
@end

/* ---- windows ------------------------------------------------------------------------------
 * A window counts as visible while it is ordered in and not minimized;
 * the notification is posted when that changes. */
typedef NS_OPTIONS(NSUInteger, NSWindowOcclusionState) {
    NSWindowOcclusionStateVisible = 1UL << 1,
};
APPKIT_EXTERN NSNotificationName const NSWindowDidChangeOcclusionStateNotification;
@interface NSWindow (NSWindowOcclusion)
@property (readonly) NSWindowOcclusionState occlusionState;
@end

/* ---- symbol images ------------------------------------------------------------------------
 * Kept with the image and its button or image view; Ferry draws symbol
 * images of its own for a few names (NSImage.m), at the configuration's
 * point size and weight. */
typedef NS_ENUM(NSInteger, NSImageSymbolScale) {
    NSImageSymbolScaleSmall = 1,
    NSImageSymbolScaleMedium = 2,
    NSImageSymbolScaleLarge = 3,
};
@interface NSImageSymbolConfiguration : NSObject <NSCopying, NSCoding>
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(NSFontWeight)weight;
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(NSFontWeight)weight scale:(NSImageSymbolScale)scale;
+ (instancetype)configurationWithScale:(NSImageSymbolScale)scale;
+ (instancetype)configurationWithTextStyle:(NSFontTextStyle)style scale:(NSImageSymbolScale)scale;
+ (instancetype)configurationWithTextStyle:(NSFontTextStyle)style;
+ (instancetype)configurationWithHierarchicalColor:(NSColor *)hierarchicalColor;
+ (instancetype)configurationWithPaletteColors:(NSArray<NSColor *> *)paletteColors;
+ (instancetype)configurationPreferringMulticolor;
+ (instancetype)configurationPreferringMonochrome;
+ (instancetype)configurationPreferringHierarchical;
- (instancetype)configurationByApplyingConfiguration:(NSImageSymbolConfiguration *)configuration;
@end
/* Ferry's own: what a configuration holds (0 for "not set"). */
@interface NSImageSymbolConfiguration (FerryValues)
@property (readonly) CGFloat _ferryPointSize;
@property (readonly) NSFontWeight _ferryWeight;
@property (readonly) NSImageSymbolScale _ferryScale;
@property (readonly) NSColor *_ferryColor;
@end
@interface NSImage (NSImageSymbolConfiguration)
- (NSImage *)imageWithSymbolConfiguration:(NSImageSymbolConfiguration *)configuration;
@property (readonly, copy) NSImageSymbolConfiguration *symbolConfiguration;
@end
@interface NSButton (NSImageSymbolConfiguration)
@property (copy) NSImageSymbolConfiguration *symbolConfiguration;
@end
@interface NSImageView (NSImageSymbolConfiguration)
@property (copy) NSImageSymbolConfiguration *symbolConfiguration;
@end

/* ---- menus ----------------------------------------------------------------------------------
 * Whether an item's image is shown (macOS 26's menus hide most); kept.
 * The values are Ferry's own. */
typedef NS_ENUM(NSInteger, NSMenuItemImageVisibility) {
    NSMenuItemImageVisibilityAutomatic = 0,
    NSMenuItemImageVisibilityHidden = 1,
    NSMenuItemImageVisibilityVisible = 2,
};
@interface NSMenuItem (FerryNewer)
/* A section's header: a title that can't be chosen. */
+ (NSMenuItem *)sectionHeaderWithTitle:(NSString *)title;
@property (readonly, getter=isSectionHeader) BOOL sectionHeader;
@property (copy) NSAttributedString *attributedTitle;    /* its string is the title */
@property NSMenuItemImageVisibility preferredImageVisibility;
@end

/* ---- colours --------------------------------------------------------------------------------
 * The fills for shapes over the window's background, from the most to the
 * least prominent; and a colour named by a block that is given the
 * appearance, asked once with Ferry's one (light) appearance. */
@interface NSColor (FerrySystemFills)
@property (class, readonly, strong) NSColor *systemFillColor;
@property (class, readonly, strong) NSColor *secondarySystemFillColor;
@property (class, readonly, strong) NSColor *tertiarySystemFillColor;
@property (class, readonly, strong) NSColor *quaternarySystemFillColor;
@property (class, readonly, strong) NSColor *quinarySystemFillColor;
+ (NSColor *)colorWithName:(NSColorName)name dynamicProvider:(NSColor * (^)(NSAppearance *appearance))dynamicProvider;
@end

/* ---- popovers -------------------------------------------------------------------------------- */
@interface NSPopover (FerryNewer)
/* The content reaches the popover's edges; its safe area is all of it. Kept. */
@property BOOL hasFullSizeContent;
@end

/* ---- events --------------------------------------------------------------------------------
 * A scroll's phase: Ferry's scroll events come from a wheel or a touchpad
 * without the gesture's phases, so a scroll's phase is None and swipe
 * tracking calls its handler once, ended, with the scroll's direction. */
typedef NS_OPTIONS(NSUInteger, NSEventPhase) {
    NSEventPhaseNone = 0,
    NSEventPhaseBegan = 1 << 0,
    NSEventPhaseStationary = 1 << 1,
    NSEventPhaseChanged = 1 << 2,
    NSEventPhaseEnded = 1 << 3,
    NSEventPhaseCancelled = 1 << 4,
    NSEventPhaseMayBegin = 1 << 5,
};
typedef NS_OPTIONS(NSUInteger, NSEventSwipeTrackingOptions) {
    NSEventSwipeTrackingLockDirection = 1 << 0,
    NSEventSwipeTrackingClampGestureAmount = 1 << 1,
};
@interface NSEvent (FerryPhases)
@property (readonly) NSEventPhase phase;
@property (readonly) NSEventPhase momentumPhase;
@property (class, readonly, getter=isSwipeTrackingFromScrollEventsEnabled) BOOL swipeTrackingFromScrollEventsEnabled;
- (void)trackSwipeEventWithOptions:(NSEventSwipeTrackingOptions)options
          dampenAmountThresholdMin:(CGFloat)minDampenThreshold
                               max:(CGFloat)maxDampenThreshold
                      usingHandler:(void (^)(CGFloat gestureAmount, NSEventPhase phase, BOOL isComplete, BOOL *stop))handler;
@end

/* ---- controls ------------------------------------------------------------------------------ */
@interface NSControl (FerryRefusesFirstResponder)
@property BOOL refusesFirstResponder;
@end
@interface NSTextField (FerryNewer)
@property BOOL allowsExpansionToolTips;    /* kept */
@end
@interface NSTextView (FerryTextLayoutManager)
/* TextKit 2 or 1: Ferry has one text system, so both make the same view. */
- (instancetype)initUsingTextLayoutManager:(BOOL)usingTextLayoutManager;
+ (instancetype)textViewUsingTextLayoutManager:(BOOL)usingTextLayoutManager;
@end
/* How strongly a control shows the accent colour; kept. */
typedef NS_ENUM(NSInteger, NSTintProminence) {
    NSTintProminenceAutomatic = 0,
    NSTintProminenceNone = 1,
    NSTintProminencePrimary = 2,
    NSTintProminenceSecondary = 3,
};
@interface NSButton (FerryNewer)
@property BOOL hasDestructiveAction;    /* kept */
@property NSTintProminence tintProminence;
@end
@interface NSSlider (FerryNewer)
@property NSTintProminence tintProminence;
@end
@interface NSApplication (FerryNewer)
- (void)unhideWithoutActivation;    /* unhides, leaving the active app as it is */
@end
@interface NSViewController (FerryIdentifier)
@property (copy) NSUserInterfaceItemIdentifier identifier;
@end

/* ---- and older calls the same apps still make ------------------------------------------------
 * A cell's text is edited in a text field (the control itself, or the field
 * a table puts over the cell), which is its own editor: these make that
 * field the first responder, with the whole text or the range selected, and
 * end its editing. textObj, delegate and event aren't used. */
@interface NSCell (FerryFieldEditing)
- (void)editWithFrame:(NSRect)rect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)delegate
                event:(NSEvent *)event;
- (void)selectWithFrame:(NSRect)rect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)delegate
                  start:(NSInteger)selStart length:(NSInteger)selLength;
- (void)endEditing:(NSText *)textObj;
@end
/* The shape a cell's focus ring follows: its frame with rounded corners. */
@interface NSCell (FerryFocusRingMask)
- (void)drawFocusRingMaskWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (NSRect)focusRingMaskBoundsForFrame:(NSRect)cellFrame inView:(NSView *)controlView;
@end
/* filled behind the button's bezel and title; nil for none */
@interface NSButtonCell (FerryBackgroundColor)
@property (retain) NSColor *backgroundColor;
@end
@interface NSTextField (FerryMnemonic)
/* the title with its first "&" taken out (it marked a Windows-style access key) */
- (void)setTitleWithMnemonic:(NSString *)stringWithAmpersand;
@end

/* macOS 11: the line under a window's title bar (freemac 1.264, HandBrake's
 * queue window). Ferry's title bars keep their own line, so it's kept. */
@interface NSWindow (FerryTitlebarSeparator)
@property NSTitlebarSeparatorStyle titlebarSeparatorStyle;
@end

/* ---- NSComboButton (macOS 13; freemac 1.264, HandBrake's toolbar) -------------------
 * A button with a menu: a click on its main part sends the action, and a
 * click on the arrow at its right end (or, in the unified style, a press
 * held on the button) opens the menu. */
typedef NS_ENUM(NSInteger, NSComboButtonStyle) {
    NSComboButtonStyleSplit = 0,
    NSComboButtonStyleUnified = 1,
};
@interface NSComboButton : NSControl
+ (instancetype)comboButtonWithTitle:(NSString *)title menu:(NSMenu *)menu target:(id)target action:(SEL)action;
+ (instancetype)comboButtonWithImage:(NSImage *)image menu:(NSMenu *)menu target:(id)target action:(SEL)action;
+ (instancetype)comboButtonWithTitle:(NSString *)title image:(NSImage *)image menu:(NSMenu *)menu
                              target:(id)target action:(SEL)action;
@property (copy) NSString *title;
@property (strong) NSImage *image;
@property NSImageScaling imageScaling;
@property (strong) NSMenu *menu;
@property NSComboButtonStyle style;
@end

#endif
