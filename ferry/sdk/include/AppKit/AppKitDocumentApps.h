/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * AppKit calls MacPass and MacDown make, and the frameworks they bring
 * (HNHUi, MASPreferences), beyond what the rest of AppKit's headers
 * declare (freemac 1.225, Ferry 0.49.0): context menus from a responder's
 * menu, the window calls of a password manager's windows (sharing, the
 * window list, titlebar accessories), file promises, a few image names and
 * the colour spaces. Written from Apple's public documentation; not
 * Apple's header. Implemented in appkit/AppKitDocumentApps.m. Imported by
 * AppKit.h. */
#ifndef _FERRY_APPKIT_DOCUMENT_APPS_H_
#define _FERRY_APPKIT_DOCUMENT_APPS_H_

/* ---- context menus ------------------------------------------------------------------- */

@class UTType, CIImage;

/* an image rep that draws a Core Image image (appkit/CoreImage.m) */
@interface NSCIImageRep : NSImageRep
+ (instancetype)imageRepWithCIImage:(CIImage *)image;
- (instancetype)initWithCIImage:(CIImage *)image;
@property (readonly, strong) CIImage *CIImage;
@end

/* A responder's menu is its context menu: a view shows it on a right click
 * (or a control click), from menuForEvent:. */
@interface NSResponder (NSMenu)
@property (retain) NSMenu *menu;
@end
@interface NSView (FerryContextMenu)
- (NSMenu *)menuForEvent:(NSEvent *)event;
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event;
- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event;
@property (class, readonly, strong) NSMenu * FERRY_SWIFT_NONNULL defaultMenu;
/* as on a Mac; the view leaves its window, which draws again anyway */
- (void)removeFromSuperviewWithoutNeedingDisplay;
@property NSEdgeInsets additionalSafeAreaInsets;
@property (readonly) NSEdgeInsets safeAreaInsets;
@property (readonly) NSRect safeAreaRect;
@end
@interface NSMenu (FerryContextMenu)
/* the menu as a pop-up at the event's place in the view, run until an item
 * is chosen (its action is sent) or the menu is put away */
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view;
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view withFont:(NSFont *)font;
/* the menu with item at location in view (in screen coordinates for no
 * view); YES when an item was chosen */
- (BOOL)popUpMenuPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)location inView:(NSView *)view;
- (NSInteger)indexOfItemWithRepresentedObject:(id)object;
- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)action;
- (NSInteger)indexOfItemWithTag:(NSInteger)tag;
- (NSInteger)indexOfItemWithSubmenu:(NSMenu *)submenu;
@property (readonly) NSMenuItem *highlightedItem;
@property (readonly) NSSize size;
@property CGFloat minimumWidth;
@property (retain) NSFont *font;
@end

/* ---- windows ------------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSWindowSharingType) {
    NSWindowSharingNone = 0,
    NSWindowSharingReadOnly = 1,
    NSWindowSharingReadWrite = 2,
};
typedef NS_OPTIONS(NSUInteger, NSWindowNumberListOptions) {
    NSWindowNumberListAllApplications = 1 << 0,
    NSWindowNumberListAllSpaces = 1 << 4,
};
typedef NS_ENUM(NSUInteger, NSWindowButton) {
    NSWindowCloseButton,
    NSWindowMiniaturizeButton,
    NSWindowZoomButton,
    NSWindowToolbarButton,
    NSWindowDocumentIconButton,
    NSWindowDocumentVersionsButton = 6,
};
@class NSTitlebarAccessoryViewController;
@interface NSWindow (FerryDocumentApps) <NSAnimatablePropertyContainer>
/* this program's windows, front to back: on Wayland a program sees no
 * other program's windows, so all applications' are its own */
+ (NSArray<NSNumber *> *)windowNumbersWithOptions:(NSWindowNumberListOptions)options;
+ (NSInteger)windowNumberAtPoint:(NSPoint)point belowWindowWithWindowNumber:(NSInteger)windowNumber;
- (void)setIsVisible:(BOOL)flag;
/* kept; the desktop decides what a screen recording shows */
@property NSWindowSharingType sharingType;
/* kept; freemac restores no windows */
@property (getter=isRestorable) BOOL restorable;
@property (assign) Class restorationClass;
- (void)invalidateRestorableState;
/* kept; the desktop draws the window's corner */
@property BOOL showsResizeIndicator;
/* the desktop draws the title bar's buttons, so there are none to give */
- (NSButton *)standardWindowButton:(NSWindowButton)button;
+ (NSButton *)standardWindowButton:(NSWindowButton)button forStyleMask:(NSWindowStyleMask)styleMask;
/* views a window keeps under its toolbar */
@property (copy) NSArray<NSTitlebarAccessoryViewController *> *titlebarAccessoryViewControllers;
- (void)addTitlebarAccessoryViewController:(NSTitlebarAccessoryViewController *)controller;
- (void)insertTitlebarAccessoryViewController:(NSTitlebarAccessoryViewController *)controller atIndex:(NSInteger)index;
- (void)removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)index;
@end

/* a view a window shows under its title bar, above the content */
@interface NSTitlebarAccessoryViewController : NSViewController
@property NSLayoutAttribute layoutAttribute;
@property CGFloat fullScreenMinHeight;
@property (getter=isHidden) BOOL hidden;
@property BOOL automaticallyAdjustsSize;
- (void)viewWillAppear;
- (void)viewDidAppear;
- (void)viewDidDisappear;
@end

/* ---- editing ------------------------------------------------------------------------- */

/* A view controller is an editor, as bindings ask (NSEditor): it has no
 * editing of its own to end, so commitEditing says YES. */
@interface NSViewController (FerryEditor) <NSEditor, NSEditorRegistration>
- (BOOL)commitEditing;
- (void)discardEditing;
- (void)commitEditingWithDelegate:(id)delegate didCommitSelector:(SEL)didCommitSelector contextInfo:(void *)contextInfo;
- (BOOL)commitEditingAndReturnError:(NSError **)error;
- (void)objectDidBeginEditing:(id<NSEditor>)editor;
- (void)objectDidEndEditing:(id<NSEditor>)editor;
@end

/* ---- attributed strings ---------------------------------------------------------------- */

APPKIT_EXTERN NSAttributedStringKey const NSStrikethroughColorAttributeName,
    NSBaselineOffsetAttributeName,
    NSSuperscriptAttributeName,
    NSObliquenessAttributeName,
    NSExpansionAttributeName,
    NSStrokeWidthAttributeName,
    NSStrokeColorAttributeName;
@interface NSAttributedString (FerryAttributeKinds)
/* the attributes at the range's start that are about characters (the
 * font, colours, underline and the like) or about paragraphs (the
 * paragraph style), as a text view's copy and paste of styles takes them */
- (NSDictionary<NSAttributedStringKey, id> *)fontAttributesInRange:(NSRange)range;
- (NSDictionary<NSAttributedStringKey, id> *)rulerAttributesInRange:(NSRange)range;
@end
@interface NSMutableAttributedString (FerryFixing)
/* each character keeps a font: a run without one takes the font before it,
 * else Helvetica 12 */
- (void)fixAttributesInRange:(NSRange)range;
- (void)fixFontAttributeInRange:(NSRange)range;
- (void)fixParagraphStyleAttributeInRange:(NSRange)range;
- (void)fixAttachmentAttributeInRange:(NSRange)range;
@end

/* ---- text checking ------------------------------------------------------------------- */

@interface NSTextView (FerryTextChecking)
/* the kinds of checking the view does as one set: spelling, grammar,
 * quotes, dashes, links, replacements and corrections are its
 * ...Enabled settings, which setting it sets (MacDown binds it) */
@property NSTextCheckingTypes enabledTextCheckingTypes;
@end

/* ---- documents ------------------------------------------------------------------------ */

@interface NSDocument (FerryDocumentApps)
/* lets the user work on while a save goes on: Ferry saves on the main
 * thread, so there is nothing to unblock */
- (void)unblockUserInteraction;
@end

/* ---- cells --------------------------------------------------------------------------- */

@interface NSCell (FerryDocumentApps)
@property BOOL truncatesLastVisibleLine;
@end
@interface NSButtonCell (FerryDocumentApps)
@property NSImageScaling imageScaling;
@end
/* a text field cell's bezel style is its text field's (HNHUi copies it from cell to cell) */
@interface NSTextFieldCell (FerryDocumentApps)
@property NSTextFieldBezelStyle bezelStyle;
@end

/* ---- text views and images ---------------------------------------------------------------- */

@interface NSTextView (FerryDocumentApps)
/* the character at a point given in screen coordinates (NSTextInputClient's;
 * HNHUi asks for the one under [NSEvent mouseLocation]), or NSNotFound */
- (NSUInteger)characterIndexForPoint:(NSPoint)screenPoint;
/* its menu, or the one its delegate's textView:menu:forEvent:atIndex: makes of it */
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end
@interface NSBitmapImageRep (FerryFocusedView)
/* the pixels in a rectangle of what is being drawn: an image's while its
 * focus is locked, or any bitmap context's (TransformerKit's image
 * transformers); nil when the context is not a bitmap's */
- (instancetype FERRY_SWIFT_NONNULL)initWithFocusedViewRect:(NSRect)rect;
@end

/* ---- the application and documents ------------------------------------------------------ */

APPKIT_EXTERN NSNotificationName const NSApplicationDidFinishRestoringWindowsNotification;
@interface NSApplication (FerryDocumentApps)
/* the open documents, front to back, as AppleScript sees them */
@property (readonly) NSArray *orderedDocuments;
@property (readonly) NSArray<NSWindow *> *orderedWindows;
/* kept; there is no Touch Bar to customise */
@property BOOL automaticCustomizeTouchBarMenuItemEnabled;
@end

/* ---- the workspace ----------------------------------------------------------------------- */

APPKIT_EXTERN NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationAppleEvent,
    NSWorkspaceLaunchConfigurationArchitecture;
@interface NSWorkspace (FerryLaunchOptions)
/* the URLs opened with the application: started with them, as
 * openURL:configuration:completionHandler: does, and the application
 * answered once it is running (nil, with the error, when it can't be) */
- (NSRunningApplication *)openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)applicationURL
                           options:(NSWorkspaceLaunchOptions)options
                     configuration:(NSDictionary<NSWorkspaceLaunchConfigurationKey, id> *)configuration
                             error:(NSError **)error;
/* the icon for files of a type: iconForFileType: with its identifier (Sparkle 2) */
- (NSImage *)iconForContentType:(UTType *)contentType;
@end

/* ---- events ------------------------------------------------------------------------------ */

@interface NSEvent (FerryCarbonEvents)
/* a Carbon event (Carbon.m's, as a hot key's handler gets) as an NSEvent:
 * a key down of its key, at the moment it came */
+ (NSEvent *)eventWithEventRef:(const void *)eventRef;
@property (readonly) const void *eventRef;
@end

/* ---- file promises ------------------------------------------------------------------------- */

@class NSFilePromiseProvider;
@protocol NSFilePromiseProviderDelegate <NSObject>
- (NSString *)filePromiseProvider:(NSFilePromiseProvider *)filePromiseProvider fileNameForType:(NSString *)fileType;
- (void)filePromiseProvider:(NSFilePromiseProvider *)filePromiseProvider
          writePromiseToURL:(NSURL *)url
          completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
@optional
- (NSOperationQueue *)operationQueueForFilePromiseProvider:(NSFilePromiseProvider *)filePromiseProvider;
@end
/* A file that a drag promises, written when it is dropped: here, when the
 * pasteboard is asked for a file URL, into the temporary folder. */
@interface NSFilePromiseProvider : NSObject <NSPasteboardWriting>
- (instancetype)initWithFileType:(NSString *)fileType delegate:(id<NSFilePromiseProviderDelegate>)delegate;
@property (copy) NSString *fileType;
@property (weak) id<NSFilePromiseProviderDelegate> delegate;
@property (strong) id userInfo;
@end
@interface NSFilePromiseReceiver : NSObject <NSPasteboardReading>
@property (class, readonly, copy) NSArray<NSString *> *readableDraggedTypes;
@property (readonly, copy) NSArray<NSString *> *fileTypes;
@property (readonly, copy) NSArray<NSString *> *fileNames;
- (void)receivePromisedFilesAtDestination:(NSURL *)destinationDir options:(NSDictionary *)options
                           operationQueue:(NSOperationQueue *)operationQueue
                                   reader:(void (^)(NSURL *fileURL, NSError *errorOrNil))reader;
@end

/* ---- images ------------------------------------------------------------------------------- */

APPKIT_EXTERN NSImageName const NSImageNameLockLockedTemplate, NSImageNameLockUnlockedTemplate,
    NSImageNameTouchBarSearchTemplate, NSImageNameTouchBarGetInfoTemplate, NSImageNameTouchBarFolderTemplate,
    NSImageNameTouchBarQuickLookTemplate, NSImageNameTouchBarDeleteTemplate, NSImageNameTouchBarShareTemplate,
    NSImageNameTouchBarHistoryTemplate, NSImageNameTouchBarComposeTemplate;
@interface NSImage (FerrySymbols)
/* a symbol by its name, drawn from this system's icon theme where it has
 * an icon of that meaning, else nil */
+ (NSImage *)imageWithSystemSymbolName:(NSString *)symbolName accessibilityDescription:(NSString *)description;
@end

/* ---- colour spaces ------------------------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSColorSpaceModel) {
    NSColorSpaceModelUnknown = -1,
    NSColorSpaceModelGray = 0,
    NSColorSpaceModelRGB = 1,
    NSColorSpaceModelCMYK = 2,
    NSColorSpaceModelLAB = 3,
    NSColorSpaceModelDeviceN = 4,
    NSColorSpaceModelIndexed = 5,
    NSColorSpaceModelPatterned = 6,
};
@interface NSColorSpace : NSObject <NSSecureCoding>
@property (class, readonly) NSColorSpace *sRGBColorSpace, *genericRGBColorSpace, *deviceRGBColorSpace,
    *genericGrayColorSpace, *deviceGrayColorSpace, *genericGamma22GrayColorSpace, *extendedSRGBColorSpace,
    *displayP3ColorSpace, *adobeRGB1998ColorSpace, *genericCMYKColorSpace, *deviceCMYKColorSpace;
- (instancetype)initWithCGColorSpace:(CGColorSpaceRef)cgColorSpace;
@property (readonly) CGColorSpaceRef CGColorSpace;
@property (readonly) NSColorSpaceModel colorSpaceModel;
@property (readonly) NSInteger numberOfColorComponents;
@property (readonly, copy) NSString *localizedName;
@end
@interface NSColor (FerryColorSpaces)
@property (readonly) NSColorSpace *colorSpace;
+ (NSColor *)colorWithColorSpace:(NSColorSpace *)space components:(const CGFloat *)components count:(NSInteger)count;
@end

/* ---- the Touch Bar ---------------------------------------------------------------------- */

@interface NSPopoverTouchBarItem : NSTouchBarItem
@property (strong) NSTouchBar *popoverTouchBar;
@property (copy) NSString *customizationLabel;
@property (strong) NSView *collapsedRepresentation;
@property (strong) NSImage *collapsedRepresentationImage;
@property (strong) NSString *collapsedRepresentationLabel;
@property (strong) NSTouchBar *pressAndHoldTouchBar;
@property BOOL showsCloseButton;
- (void)showPopover:(id)sender;
- (void)dismissPopover:(id)sender;
@end

/* ---- OpenGL's error type, which AppKit's headers bring on a Mac --------------------------- */

#ifndef _FERRY_CGLERROR_DEFINED
#define _FERRY_CGLERROR_DEFINED
typedef enum _CGLError {
    kCGLNoError = 0,
    kCGLBadAttribute = 10000,
    kCGLBadProperty = 10001,
    kCGLBadPixelFormat = 10002,
    kCGLBadRendererInfo = 10003,
    kCGLBadContext = 10004,
    kCGLBadDrawable = 10005,
    kCGLBadDisplay = 10006,
    kCGLBadState = 10007,
    kCGLBadValue = 10008,
    kCGLBadMatch = 10009,
    kCGLBadEnumeration = 10010,
    kCGLBadOffScreen = 10011,
    kCGLBadFullScreen = 10012,
    kCGLBadWindow = 10013,
    kCGLBadAddress = 10014,
    kCGLBadCodeModule = 10015,
    kCGLBadAlloc = 10016,
    kCGLBadConnection = 10017,
} CGLError;
#endif

#endif
