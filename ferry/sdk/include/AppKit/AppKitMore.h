/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * AppKit names the nine apps' sources use that Ferry hadn't had (freemac
 * 1.221, Ferry 0.45.0), written from Apple's public documentation: the
 * run loop's tracking and modal modes, the older names of masks, styles and
 * options, modal sessions, focus rings, more of the system colours, the text
 * storage's edits, the layout manager's rectangles, the button cell's
 * highlight and state masks, the field editor's calls, cancelling a menu,
 * and appearances. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_MORE_H_
#define _FERRY_APPKIT_MORE_H_

/* ---- run loop modes: Ferry's run loop runs every source in every mode, so
 * these name the mode a loop runs in (currentMode) and change nothing else */
APPKIT_EXTERN NSRunLoopMode const NSEventTrackingRunLoopMode;
APPKIT_EXTERN NSRunLoopMode const NSModalPanelRunLoopMode;

/* ---- the AppKit version: macOS 14's, with the older releases' numbers */
APPKIT_EXTERN const double NSAppKitVersionNumber;
#define NSAppKitVersionNumber10_9 1265
#define NSAppKitVersionNumber10_10 1343
#define NSAppKitVersionNumber10_11 1404
#define NSAppKitVersionNumber10_12 1504
#define NSAppKitVersionNumber10_13 1561
#define NSAppKitVersionNumber10_14 1671
#define NSAppKitVersionNumber10_15 1894
#define NSAppKitVersionNumber11_0 2022

/* ---- older names ---- */
#define NSLeftMouseDownMask NSEventMaskLeftMouseDown
#define NSLeftMouseUpMask NSEventMaskLeftMouseUp
#define NSRightMouseDownMask NSEventMaskRightMouseDown
#define NSRightMouseUpMask NSEventMaskRightMouseUp
#define NSMouseMovedMask NSEventMaskMouseMoved
#define NSLeftMouseDraggedMask NSEventMaskLeftMouseDragged
#define NSRightMouseDraggedMask NSEventMaskRightMouseDragged
#define NSMouseEnteredMask NSEventMaskMouseEntered
#define NSMouseExitedMask NSEventMaskMouseExited
#define NSKeyDownMask NSEventMaskKeyDown
#define NSKeyUpMask NSEventMaskKeyUp
#define NSFlagsChangedMask NSEventMaskFlagsChanged
#define NSApplicationDefinedMask NSEventMaskApplicationDefined
#define NSPeriodicMask NSEventMaskPeriodic
#define NSScrollWheelMask NSEventMaskScrollWheel
#define NSOtherMouseDownMask NSEventMaskOtherMouseDown
#define NSOtherMouseUpMask NSEventMaskOtherMouseUp
#define NSOtherMouseDraggedMask NSEventMaskOtherMouseDragged
#define NSEventMaskPeriodic (1ULL << NSEventTypePeriodic)
#define NSEventMaskCursorUpdate (1ULL << NSEventTypeCursorUpdate)
#define NSEventMaskAppKitDefined (1ULL << NSEventTypeAppKitDefined)
#define NSEventMaskSystemDefined (1ULL << NSEventTypeSystemDefined)
#define NSPeriodic NSEventTypePeriodic
#define NSCursorUpdate NSEventTypeCursorUpdate
#define NSAppKitDefined NSEventTypeAppKitDefined
#define NSSystemDefined NSEventTypeSystemDefined

#define NSCompositeSourceIn NSCompositingOperationSourceIn
#define NSCompositeSourceOut NSCompositingOperationSourceOut
#define NSCompositeSourceAtop NSCompositingOperationSourceAtop
#define NSCompositeDestinationOver NSCompositingOperationDestinationOver
#define NSCompositeDestinationIn NSCompositingOperationDestinationIn
#define NSCompositeDestinationOut NSCompositingOperationDestinationOut
#define NSCompositeDestinationAtop NSCompositingOperationDestinationAtop
#define NSCompositeXOR NSCompositingOperationXOR
#define NSCompositePlusDarker NSCompositingOperationPlusDarker
#define NSCompositePlusLighter NSCompositingOperationPlusLighter

#define NSRegularControlSize NSControlSizeRegular
#define NSSmallControlSize NSControlSizeSmall
#define NSMiniControlSize NSControlSizeMini

#define NSNonZeroWindingRule NSWindingRuleNonZero
#define NSEvenOddWindingRule NSWindingRuleEvenOdd
#define NSButtLineCapStyle NSLineCapStyleButt
#define NSRoundLineCapStyle NSLineCapStyleRound
#define NSSquareLineCapStyle NSLineCapStyleSquare
#define NSMiterLineJoinStyle NSLineJoinStyleMiter
#define NSRoundLineJoinStyle NSLineJoinStyleRound
#define NSBevelLineJoinStyle NSLineJoinStyleBevel

#define NSTIFFFileType NSBitmapImageFileTypeTIFF
#define NSBMPFileType NSBitmapImageFileTypeBMP
#define NSGIFFileType NSBitmapImageFileTypeGIF
#define NSJPEGFileType NSBitmapImageFileTypeJPEG
#define NSPNGFileType NSBitmapImageFileTypePNG
typedef NS_ENUM(NSUInteger, NSTIFFCompression) {
    NSTIFFCompressionNone = 1, NSTIFFCompressionCCITTFAX3 = 3, NSTIFFCompressionCCITTFAX4 = 4,
    NSTIFFCompressionLZW = 5, NSTIFFCompressionJPEG = 6, NSTIFFCompressionNEXT = 32766,
    NSTIFFCompressionPackBits = 32773, NSTIFFCompressionOldJPEG = 32865,
};

#define NSDisclosureBezelStyle NSBezelStyleDisclosure
#define NSShadowlessSquareBezelStyle NSBezelStyleShadowlessSquare
#define NSCircularBezelStyle NSBezelStyleCircular
#define NSTexturedSquareBezelStyle NSBezelStyleTexturedSquare
#define NSHelpButtonBezelStyle NSBezelStyleHelpButton
#define NSSmallSquareBezelStyle NSBezelStyleSmallSquare
#define NSRoundedDisclosureBezelStyle NSBezelStyleRoundedDisclosure
#define NSInlineBezelStyle NSBezelStyleInline

#define NSUtilityWindowMask NSWindowStyleMaskUtilityWindow
#define NSDocModalWindowMask NSWindowStyleMaskDocModalWindow
#define NSNonactivatingPanelMask NSWindowStyleMaskNonactivatingPanel
#define NSUnifiedTitleAndToolbarWindowMask NSWindowStyleMaskUnifiedTitleAndToolbar
#define NSHUDWindowMask NSWindowStyleMaskHUDWindow
#define NSFullScreenWindowMask NSWindowStyleMaskFullScreen
#define NSFullSizeContentViewWindowMask NSWindowStyleMaskFullSizeContentView

#define NSProgressIndicatorBarStyle NSProgressIndicatorStyleBar
#define NSProgressIndicatorSpinningStyle NSProgressIndicatorStyleSpinning

#define NSFontPanelFaceModeMask NSFontPanelModeMaskFace
#define NSFontPanelSizeModeMask NSFontPanelModeMaskSize
#define NSFontPanelCollectionModeMask NSFontPanelModeMaskCollection
#define NSFontPanelStandardModesMask NSFontPanelModesMaskStandardModes
#define NSFontPanelAllModesMask NSFontPanelModesMaskAllModes

/* ---- modal sessions: a modal loop the program runs itself, a turn at a time */
typedef struct _NSModalSession *NSModalSession;
enum { NSRunStoppedResponse = -1000, NSRunAbortedResponse = -1001, NSRunContinuesResponse = -1002 };
@interface NSApplication (NSModalSessions)
- (NSModalSession)beginModalSessionForWindow:(NSWindow *)window;
/* handles the events waiting (none are waited for) and answers
 * NSModalResponseContinue, or the code once stopModal... has been called */
- (NSModalResponse)runModalSession:(NSModalSession)session;
- (void)endModalSession:(NSModalSession)session;
@end

/* ---- focus rings and filling lists of rectangles */
typedef NS_ENUM(NSUInteger, NSFocusRingPlacement) {
    NSFocusRingOnly = 0, NSFocusRingBelow = 1, NSFocusRingAbove = 2,
};
/* Draws, until the graphics state is restored, a focus ring around what is
 * filled or stroked next (NSFocusRingOnly: only the ring). */
void NSSetFocusRingStyle(NSFocusRingPlacement placement);
void NSRectFillListWithColors(const NSRect *rects, NSColor *const *colors, NSInteger count);
void NSRectFillListWithGrays(const NSRect *rects, const CGFloat *grays, NSInteger count);
void NSRectFillListUsingOperation(const NSRect *rects, NSInteger count, NSCompositingOperation op);
void NSRectFillListWithColorsUsingOperation(const NSRect *rects, NSColor *const *colors, NSInteger count,
                                            NSCompositingOperation op);

/* ---- more system colours; colorNamed: finds colours an app's asset
 * catalogue holds only once Ferry reads compiled catalogues, so it answers
 * nil for any name it doesn't know */
@interface NSColor (FerryMoreSystemColors)
@property (class, readonly) NSColor *windowFrameColor, *windowFrameTextColor, *scrollBarColor, *knobColor;
@property (class, readonly) NSColor *selectedKnobColor, *highlightColor, *shadowColor, *controlHighlightColor;
@property (class, readonly) NSColor *controlLightHighlightColor, *controlShadowColor, *controlDarkShadowColor;
@property (class, readonly) NSColor *selectedMenuItemColor, *selectedMenuItemTextColor, *quaternaryLabelColor;
@property (class, readonly) NSColor *unemphasizedSelectedTextBackgroundColor, *findHighlightColor;
+ (NSColor *)colorNamed:(NSString *)name;
+ (NSColor *)colorNamed:(NSString *)name bundle:(NSBundle *)bundle;
@end

/* ---- the text storage's edits */
typedef NS_OPTIONS(NSUInteger, NSTextStorageEditActions) {
    NSTextStorageEditedAttributes = 1 << 0, NSTextStorageEditedCharacters = 1 << 1,
};
enum { NSTextStorageEditedAttributesMask = 1, NSTextStorageEditedCharactersMask = 2 };
@protocol NSTextStorageDelegate <NSObject>
@optional
- (void)textStorage:(NSTextStorage *)textStorage willProcessEditing:(NSTextStorageEditActions)editedMask
              range:(NSRange)editedRange changeInLength:(NSInteger)delta;
- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask
              range:(NSRange)editedRange changeInLength:(NSInteger)delta;
- (void)textStorageWillProcessEditing:(NSNotification *)notification;
- (void)textStorageDidProcessEditing:(NSNotification *)notification;
@end
APPKIT_EXTERN NSNotificationName const NSTextStorageWillProcessEditingNotification;
APPKIT_EXTERN NSNotificationName const NSTextStorageDidProcessEditingNotification;
@interface NSTextStorage (FerryEditing)
/* what changed since the edits began, in the text as it is now; valid while
 * the storage processes them (its delegate's calls) */
@property (readonly) NSTextStorageEditActions editedMask;
@property (readonly) NSRange editedRange;
@property (readonly) BOOL fixesAttributesLazily;
- (void)edited:(NSTextStorageEditActions)mask range:(NSRange)range changeInLength:(NSInteger)delta;
- (void)processEditing;
- (void)ensureAttributesAreFixedInRange:(NSRange)range;
- (void)invalidateAttributesInRange:(NSRange)range;
@end

/* ---- the layout manager's geometry: Ferry lays out one glyph for each
 * character, so glyph and character ranges are the same */
@interface NSLayoutManager (FerryGeometry)
/* in the text container's coordinates */
- (NSRect)boundingRectForGlyphRange:(NSRange)range inTextContainer:(NSTextContainer *)container;
- (NSRange)glyphRangeForCharacterRange:(NSRange)range actualCharacterRange:(NSRangePointer)actual;
- (NSRange)characterRangeForGlyphRange:(NSRange)range actualGlyphRange:(NSRangePointer)actual;
- (NSRange)glyphRangeForBoundingRect:(NSRect)rect inTextContainer:(NSTextContainer *)container;
- (NSUInteger)glyphIndexForCharacterAtIndex:(NSUInteger)index;
- (NSUInteger)characterIndexForGlyphAtIndex:(NSUInteger)index;
- (NSUInteger)glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;
- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)index effectiveRange:(NSRangePointer)range;
@end

/* ---- cells: the button cell's highlight and state masks, a cell's menu,
 * its image position, and hit testing */
typedef NS_OPTIONS(NSUInteger, NSCellStyleMask) {
    NSNoCellMask = 0, NSContentsCellMask = 1, NSPushInCellMask = 2, NSChangeGrayCellMask = 4,
    NSChangeBackgroundCellMask = 8,
};
typedef NS_OPTIONS(NSUInteger, NSCellHitResult) {
    NSCellHitNone = 0, NSCellHitContentArea = 1 << 0, NSCellHitEditableTextArea = 1 << 1,
    NSCellHitTrackableArea = 1 << 2,
};
@interface NSButtonCell (FerryMasks)
/* set with the button type, as Apple documents for each type */
@property NSCellStyleMask highlightsBy, showsStateBy;
@property NSCellImagePosition imagePosition;
@property (copy) NSAttributedString *attributedTitle;
@end
@interface NSCell (FerryMore)
@property (retain) NSMenu *menu;
- (NSMenu *)menuForEvent:(NSEvent *)event inRect:(NSRect)rect ofView:(NSView *)view;
- (NSCellHitResult)hitTestForEvent:(NSEvent *)event inRect:(NSRect)rect ofView:(NSView *)view;
@end

/* ---- the field editor: a Ferry text field edits its own text, so a field
 * being edited is its own current editor, answering NSText's selection
 * calls; endEditingFor: ends the editing (the text is kept) */
@interface NSControl (FerryFieldEditor)
- (NSText *)currentEditor;
@end
@interface NSTextField (FerryFieldEditor)
@property NSRange selectedRange;
@property (copy) NSString *string;
- (void)selectAll:(id)sender;
@end
@interface NSWindow (FerryFieldEditor)
- (void)endEditingFor:(id)object;
- (NSText *)fieldEditor:(BOOL)create forObject:(id)object;
@end

/* ---- menus: closes a menu open in one of the program's windows */
@interface NSMenu (FerryTracking)
- (void)cancelTracking;
- (void)cancelTrackingWithoutAnimation;
@end

/* ---- a menu that opens over a window posts these, with the menu; system
 * colours don't change in Ferry, so that notification is never posted */
APPKIT_EXTERN NSNotificationName const NSMenuDidBeginTrackingNotification;
APPKIT_EXTERN NSNotificationName const NSMenuDidEndTrackingNotification;
APPKIT_EXTERN NSNotificationName const NSSystemColorsDidChangeNotification;
/* A menu item's action is sent between these two, with the item's menu and
 * the item as "MenuItem" in the user info. */
APPKIT_EXTERN NSNotificationName const NSMenuWillSendActionNotification;
APPKIT_EXTERN NSNotificationName const NSMenuDidSendActionNotification;
/* the keyboard layout changing; freemac's layout is fixed while an app runs,
 * so it isn't posted */
APPKIT_EXTERN NSNotificationName const NSTextInputContextKeyboardSelectionDidChangeNotification;

/* ---- more image names, which imageNamed: answers nil for until Ferry has
 * pictures of its own for them */
APPKIT_EXTERN NSImageName const NSImageNameComputer, NSImageNameNetwork, NSImageNamePreferencesGeneral;
APPKIT_EXTERN NSImageName const NSImageNameAdvanced, NSImageNameEveryone, NSImageNameUser, NSImageNameUserGroup;

/* ---- appearances: Ferry draws in the light (Aqua) appearance */
typedef NSString *NSAppearanceName;
APPKIT_EXTERN NSAppearanceName const NSAppearanceNameAqua, NSAppearanceNameDarkAqua;
APPKIT_EXTERN NSAppearanceName const NSAppearanceNameVibrantLight, NSAppearanceNameVibrantDark;
APPKIT_EXTERN NSAppearanceName const NSAppearanceNameAccessibilityHighContrastAqua;
APPKIT_EXTERN NSAppearanceName const NSAppearanceNameAccessibilityHighContrastDarkAqua;
@interface NSAppearance : NSObject <NSCoding>
+ (NSAppearance *)appearanceNamed:(NSAppearanceName)name;
@property (class, retain) NSAppearance *currentAppearance;
@property (class, readonly) NSAppearance *currentDrawingAppearance;
@property (readonly, copy) NSAppearanceName name;
@property (readonly) BOOL allowsVibrancy;
- (NSAppearanceName)bestMatchFromAppearancesWithNames:(NSArray<NSAppearanceName> *)names;
- (void)performAsCurrentDrawingAppearance:(void (^)(void))block;
@end
@protocol NSAppearanceCustomization <NSObject>
@property (retain) NSAppearance *appearance;
@property (readonly, retain) NSAppearance *effectiveAppearance;
@end
@interface NSApplication (FerryAppearance) <NSAppearanceCustomization>
@end
@interface NSView (FerryAppearance) <NSAppearanceCustomization>
@end
@interface NSWindow (FerryAppearance) <NSAppearanceCustomization>
@end
#endif
