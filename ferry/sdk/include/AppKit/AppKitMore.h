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

/* ---- more system colours; colorNamed: finds the colours of the app's asset
 * catalogue that ferry-actool compiled (freemac 1.224, Ferry 0.48.0), and
 * answers nil for any name it doesn't know */
@interface NSColor (FerryMoreSystemColors)
@property (class, readonly) NSColor * FERRY_SWIFT_NONNULL windowFrameColor, * FERRY_SWIFT_NONNULL windowFrameTextColor, * FERRY_SWIFT_NONNULL scrollBarColor, * FERRY_SWIFT_NONNULL knobColor;
@property (class, readonly) NSColor * FERRY_SWIFT_NONNULL selectedKnobColor, * FERRY_SWIFT_NONNULL highlightColor, * FERRY_SWIFT_NONNULL shadowColor, * FERRY_SWIFT_NONNULL controlHighlightColor;
@property (class, readonly) NSColor * FERRY_SWIFT_NONNULL controlLightHighlightColor, * FERRY_SWIFT_NONNULL controlShadowColor, * FERRY_SWIFT_NONNULL controlDarkShadowColor;
@property (class, readonly) NSColor * FERRY_SWIFT_NONNULL selectedMenuItemColor, * FERRY_SWIFT_NONNULL selectedMenuItemTextColor, * FERRY_SWIFT_NONNULL quaternaryLabelColor;
@property (class, readonly) NSColor * FERRY_SWIFT_NONNULL unemphasizedSelectedTextBackgroundColor, * FERRY_SWIFT_NONNULL findHighlightColor;
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
- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)index effectiveRange:(NSRangePointer)range;
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
/* posted when the fonts installed change; freemac doesn't watch, so never */
APPKIT_EXTERN NSNotificationName const NSFontSetChangedNotification;
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
@property (class, retain) NSAppearance * FERRY_SWIFT_NONNULL currentAppearance;
@property (class, readonly) NSAppearance * FERRY_SWIFT_NONNULL currentDrawingAppearance;
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

/* ---- the calls KeyCastr and its ShortcutRecorder make (freemac 1.224,
 * Ferry 0.48.0) */
/* Text runs left to right in the languages Ferry lays out. */
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutDirection) {
    NSUserInterfaceLayoutDirectionLeftToRight = 0, NSUserInterfaceLayoutDirectionRightToLeft = 1,
};
@interface NSApplication (FerryLayoutDirection)
@property (readonly) NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@end
@interface NSView (FerryLayoutDirection)
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@end
/* Ferry's controls have one tint, the blue one */
typedef NS_ENUM(NSUInteger, NSControlTint) {
    NSDefaultControlTint = 0, NSBlueControlTint = 1, NSGraphiteControlTint = 6, NSClearControlTint = 7,
};
@interface NSColor (FerryControlTint)
@property (class, readonly) NSControlTint currentControlTint;
+ (NSColor *)colorForControlTint:(NSControlTint)tint;
/* whether colour wells and the colour panel leave out opacity */
@property (class) BOOL ignoresAlpha;
@end
@interface NSCell (FerryControlTint)
@property NSControlTint controlTint;
@end
/* A controller that edits (a binding's controller, for one): asked to end
 * or drop its editing. */
@protocol NSEditor <NSObject>
- (BOOL)commitEditing;
@optional
- (void)discardEditing;
- (void)commitEditingWithDelegate:(id)delegate didCommitSelector:(SEL)didCommitSelector contextInfo:(void *)contextInfo;
- (BOOL)commitEditingAndReturnError:(NSError **)error;
@end
@protocol NSEditorRegistration <NSObject>
@optional
- (void)objectDidBeginEditing:(id<NSEditor>)editor;
- (void)objectDidEndEditing:(id<NSEditor>)editor;
@end
/* A window's frame kept in the user defaults under "NSWindow Frame NAME",
 * as a Mac keeps it; the desktop places the window, so only its size is
 * used when it is read back. */
@interface NSWindow (FerryFrameNames)
- (BOOL)setFrameUsingName:(NSString *)name force:(BOOL)force;
- (void)saveFrameUsingName:(NSString *)name;
+ (void)removeFrameUsingName:(NSString *)name;
@property (readonly, copy) NSString *stringWithSavedFrame;
- (void)setFrameFromString:(NSString *)string;
/* whether hiding the app hides this window */
@property BOOL canHide;
@end
/* Tool tips for parts of a view: the view's own tool tip is the text of the
 * last one added (an owner that is a string, or the owner's answer for the
 * rectangle's middle); a view has one tool tip here. */
typedef NSInteger NSToolTipTag;
@protocol NSViewToolTipOwner <NSObject>
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data;
@end
@interface NSView (FerryToolTipRects)
- (NSToolTipTag)addToolTipRect:(NSRect)rect owner:(id)owner userData:(void *)data;
- (void)removeToolTip:(NSToolTipTag)tag;
- (void)removeAllToolTips;
@end
@interface NSBezierPath (FerryRelativeCurve)
- (void)relativeCurveToPoint:(NSPoint)endPoint controlPoint1:(NSPoint)controlPoint1
               controlPoint2:(NSPoint)controlPoint2;
@end
/* Drawing the text a layout manager holds, its origin at the point given:
 * the text is drawn as its attributed string draws in the first text
 * container's width. */
@interface NSLayoutManager (FerryDrawing)
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin;
- (void)drawBackgroundForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin;
@end
/* Launching an app: this app again (KeyCastr's restart) starts a new copy
 * of it under Ferry; another Mac app isn't launched, as launchApplication:
 * says. */
typedef NS_OPTIONS(NSUInteger, NSWorkspaceLaunchOptions) {
    NSWorkspaceLaunchAndPrint = 0x2, NSWorkspaceLaunchWithErrorPresentation = 0x40,
    NSWorkspaceLaunchInhibitingBackgroundOnly = 0x80, NSWorkspaceLaunchWithoutAddingToRecents = 0x100,
    NSWorkspaceLaunchWithoutActivation = 0x200, NSWorkspaceLaunchAsync = 0x10000,
    NSWorkspaceLaunchNewInstance = 0x80000, NSWorkspaceLaunchAndHide = 0x100000,
    NSWorkspaceLaunchAndHideOthers = 0x200000, NSWorkspaceLaunchDefault = NSWorkspaceLaunchAsync,
};
typedef NSString *NSWorkspaceLaunchConfigurationKey;
APPKIT_EXTERN NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationArguments;
APPKIT_EXTERN NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationEnvironment;
@interface NSWorkspace (FerryLaunching)
- (NSRunningApplication *)launchApplicationAtURL:(NSURL *)url options:(NSWorkspaceLaunchOptions)options
                                   configuration:(NSDictionary<NSWorkspaceLaunchConfigurationKey, id> *)configuration
                                           error:(NSError **)error;
- (void)openApplicationAtURL:(NSURL *)applicationURL configuration:(NSWorkspaceOpenConfiguration *)configuration
           completionHandler:(void (^)(NSRunningApplication *app, NSError *error))completionHandler;
@end
/* The other characters of keys that don't type one, by the values Apple's
 * documentation of NSEvent gives them. */
enum {
    NSF13FunctionKey = 0xF710, NSF14FunctionKey = 0xF711, NSF15FunctionKey = 0xF712, NSF16FunctionKey = 0xF713,
    NSF17FunctionKey = 0xF714, NSF18FunctionKey = 0xF715, NSF19FunctionKey = 0xF716, NSF20FunctionKey = 0xF717,
    NSF21FunctionKey = 0xF718, NSF22FunctionKey = 0xF719, NSF23FunctionKey = 0xF71A, NSF24FunctionKey = 0xF71B,
    NSF25FunctionKey = 0xF71C, NSF26FunctionKey = 0xF71D, NSF27FunctionKey = 0xF71E, NSF28FunctionKey = 0xF71F,
    NSF29FunctionKey = 0xF720, NSF30FunctionKey = 0xF721, NSF31FunctionKey = 0xF722, NSF32FunctionKey = 0xF723,
    NSF33FunctionKey = 0xF724, NSF34FunctionKey = 0xF725, NSF35FunctionKey = 0xF726,
    NSPrintScreenFunctionKey = 0xF72E, NSScrollLockFunctionKey = 0xF72F, NSPauseFunctionKey = 0xF730,
    NSSysReqFunctionKey = 0xF731, NSBreakFunctionKey = 0xF732, NSResetFunctionKey = 0xF733,
    NSStopFunctionKey = 0xF734, NSMenuFunctionKey = 0xF735, NSUserFunctionKey = 0xF736,
    NSSystemFunctionKey = 0xF737, NSPrintFunctionKey = 0xF738, NSClearLineFunctionKey = 0xF739,
    NSClearDisplayFunctionKey = 0xF73A, NSInsertLineFunctionKey = 0xF73B, NSDeleteLineFunctionKey = 0xF73C,
    NSInsertCharFunctionKey = 0xF73D, NSDeleteCharFunctionKey = 0xF73E, NSPrevFunctionKey = 0xF73F,
    NSNextFunctionKey = 0xF740, NSSelectFunctionKey = 0xF741, NSExecuteFunctionKey = 0xF742,
    NSUndoFunctionKey = 0xF743, NSRedoFunctionKey = 0xF744, NSFindFunctionKey = 0xF745,
    NSHelpFunctionKey = 0xF746, NSModeSwitchFunctionKey = 0xF747,
};
/* Binding names and options, as the binding calls take them. A class's
 * option descriptions (Core Data attribute descriptions) are none unless
 * the class gives its own. */
typedef NSString *NSBindingName;
typedef NSString *NSBindingOption;
typedef NSString *NSBindingInfoKey;
@class NSAttributeDescription;
@interface NSObject (FerryBindingOptions)
- (NSArray<NSAttributeDescription *> *)optionDescriptionsForBinding:(NSBindingName)binding;
@end
/* posted when the control tint and the accessibility display options
 * change, which they don't here: the desktop's own settings aren't read
 * yet, so each option is NO, as on a Mac with none of them turned on */
APPKIT_EXTERN NSNotificationName const NSControlTintDidChangeNotification;
APPKIT_EXTERN NSNotificationName const NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification;
@interface NSWorkspace (FerryAccessibilityDisplay)
@property (readonly) BOOL accessibilityDisplayShouldIncreaseContrast;
@property (readonly) BOOL accessibilityDisplayShouldDifferentiateWithoutColor;
@property (readonly) BOOL accessibilityDisplayShouldReduceTransparency;
@property (readonly) BOOL accessibilityDisplayShouldReduceMotion;
@property (readonly) BOOL accessibilityDisplayShouldInvertColors;
@property (readonly, getter=isVoiceOverEnabled) BOOL voiceOverEnabled;
@property (readonly, getter=isSwitchControlEnabled) BOOL switchControlEnabled;
@end
/* A view: being reused (by a table), its appearance changed, whether a
 * rectangle is to be drawn (one that meets the visible rectangle), its
 * focus ring's shape changed (the ring is drawn round the frame here), and
 * the tool tip a view that owns its own tool tip rectangles gives (its own
 * tool tip). */
@interface NSView (FerryReuse)
- (void)prepareForReuse;
- (void)viewDidChangeEffectiveAppearance;
- (BOOL)needsToDrawRect:(NSRect)rect;
- (void)getRectsBeingDrawn:(const NSRect **)rects count:(NSInteger *)count;
- (void)noteFocusRingMaskChanged;
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data;
@end
/* Drawing a string with a context, which nothing here uses: as
 * drawInRect:withAttributes: and boundingRectWithSize:options:attributes:. */
@interface NSStringDrawingContext : NSObject
@property CGFloat minimumScaleFactor;
@property (readonly) CGFloat actualScaleFactor;
@property (readonly) NSRect totalBounds;
@end
@interface NSString (FerryDrawingContext)
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options
          attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes context:(NSStringDrawingContext *)context;
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
                    attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
                       context:(NSStringDrawingContext *)context;
@end
@interface NSAttributedString (FerryDrawingContext)
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options context:(NSStringDrawingContext *)context;
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
                       context:(NSStringDrawingContext *)context;
@end
/* A colour from a colour list: the "System" list holds the colours NSColor
 * names (controlTextColor and the like); there are no other lists here,
 * so any other gives nil, as an unknown colour does. */
@interface NSColor (FerryCatalog)
+ (NSColor *)colorWithCatalogName:(NSString *)listName colorName:(NSString *)colorName;
/* A catalog colour's list and name: a system colour, which changes with
 * the appearance, is in the System list; other colours give nil. */
@property (readonly, copy) NSString *catalogNameComponent;
@property (readonly, copy) NSString *colorNameComponent;
@property (readonly, copy) NSString *localizedCatalogNameComponent;
@property (readonly, copy) NSString *localizedColorNameComponent;
@end
/* the item whose submenu holds this item's menu */
@interface NSMenuItem (FerryParentItem)
@property (readonly, assign) NSMenuItem *parentItem;
@end
/* The actions of the find bar, as a text view's performTextFinderAction:
 * takes them from a menu item's tag. */
typedef NS_ENUM(NSInteger, NSTextFinderAction) {
    NSTextFinderActionShowFindInterface = 1, NSTextFinderActionNextMatch = 2,
    NSTextFinderActionPreviousMatch = 3, NSTextFinderActionReplaceAll = 4, NSTextFinderActionReplace = 5,
    NSTextFinderActionReplaceAndFind = 6, NSTextFinderActionSetSearchString = 7,
    NSTextFinderActionReplaceAllInSelection = 8, NSTextFinderActionSelectAll = 9,
    NSTextFinderActionSelectAllInSelection = 10, NSTextFinderActionHideFindInterface = 11,
    NSTextFinderActionShowReplaceInterface = 12, NSTextFinderActionHideReplaceInterface = 13,
};
/* Whether a window shows its title, as its titleVisibility says */
typedef NS_ENUM(NSInteger, NSWindowTitleVisibility) { NSWindowTitleVisible = 0, NSWindowTitleHidden = 1 };
/* A constraint changed through its animator changes at once. */
@interface NSLayoutConstraint (FerryAnimator) <NSAnimatablePropertyContainer>
@end
/* A text view's colours stay as they are in a dark appearance. */
@interface NSTextView (FerryAdaptiveColor)
@property BOOL usesAdaptiveColorMappingForDarkAppearance;
@end
/* TextKit 2's layout manager and content storage, which only hold their
 * container and each other here: a text view made with such a container
 * lays out as with TextKit 1 (Sparkle makes one only on macOS 16 and
 * later, which this system doesn't say it is). */
@interface NSTextLayoutManager : NSObject
@property (retain) NSTextContainer *textContainer;
@property (readonly, assign) id textContentManager;
@end
@interface NSTextContentManager : NSObject
@property (readonly, copy) NSArray<NSTextLayoutManager *> *textLayoutManagers;
- (void)addTextLayoutManager:(NSTextLayoutManager *)textLayoutManager;
- (void)removeTextLayoutManager:(NSTextLayoutManager *)textLayoutManager;
@end
@interface NSTextContentStorage : NSTextContentManager
@property (retain) NSTextStorage *textStorage;
@end
/* Drawing a frame from caps and a middle (and, for nine parts, corners and
 * edges): the caps and corners keep their size, and the middle and edges
 * are stretched over the rest (they aren't tiled here). */
APPKIT_EXTERN void NSDrawThreePartImage(NSRect frame, NSImage *startCap, NSImage *centerFill, NSImage *endCap,
                                        BOOL vertical, NSCompositingOperation op, CGFloat alphaFraction,
                                        BOOL flipped);
APPKIT_EXTERN void NSDrawNinePartImage(NSRect frame, NSImage *topLeftCorner, NSImage *topEdgeFill,
                                       NSImage *topRightCorner, NSImage *leftEdgeFill, NSImage *centerFill,
                                       NSImage *rightEdgeFill, NSImage *bottomLeftCorner, NSImage *bottomEdgeFill,
                                       NSImage *bottomRightCorner, NSCompositingOperation op, CGFloat alphaFraction,
                                       BOOL flipped);
/* MacDown (freemac 1.224): there's no input method composing text here,
 * so a text view never has marked text; and the cursor a range of text
 * shows, kept as an attribute */
@interface NSTextView (FerryMarkedText)
- (BOOL)hasMarkedText;
- (NSRange)markedRange;
- (void)unmarkText;
@end
APPKIT_EXTERN NSAttributedStringKey const NSCursorAttributeName;
#endif
