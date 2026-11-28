/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: shared internals. Our own code, written from Apple's
 * public API documentation; built as a Mach-O library with ferry-cc. Views
 * draw with Ferry's Core Graphics into a backing image for each window, and
 * GTK (see gtk.h) shows that image in a toplevel window and hands back the
 * input. Built without ARC. */
#ifndef FERRY_APPKIT_INTERNAL_H
#define FERRY_APPKIT_INTERNAL_H
#include "../graphics/GInternal.h"
/* Some NSCoding methods live in NSNib.m, as categories. */
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#define FERRY_APPKIT_BUILD 1      /* NSFont and NSParagraphStyle are Core Text's */
#import <AppKit/AppKit.h>
#include <poll.h>
#include <pthread.h>
#include <unistd.h>
#include <objc/message.h>
#include "gtk.h"
#include <ImageIO/ImageIO.h>

#define A_EXPORT __attribute__((visibility("default")))

/* From Ferry's Foundation: lets AppKit add GLib's file descriptors and
 * timeout to every run-loop wait, and dispatch GLib when they fire. */
void FerryRunLoopSetPollHook(int (*prepare)(void *ctx, int *timeout_ms, struct pollfd *fds, int max),
                             BOOL (*dispatch)(void *ctx, struct pollfd *fds, int count), void *ctx);
/* From Ferry's Core Graphics: a context drawing on a Cairo surface. */
CGContextRef GContextCreateWithSurface(cairo_surface_t *surface, double height);
/* From Ferry's Core Animation (quartzcore/QInternal.h): drawing a layer
 * tree as it is shown now, with a view's own drawing standing for its
 * backing layer's content; where an animation has moved a root layer from
 * where its model puts it; the object told when a tree is to be drawn
 * again; and a property animated on any object (the animator proxies). */
void FerryCALayerRender(CALayer *layer, CGContextRef ctx, BOOL presentation, BOOL flipped,
                        void (^content)(CGContextRef ctx));
CGAffineTransform FerryCALayerPresentationOffset(CALayer *layer);
void FerryCALayerSetHost(CALayer *layer, id host);
void FerryCADriveValue(id target, NSString *key, id from, id to, CAAnimation *animation);
/* The animator proxy of an object that animates its properties (NSAnimationContext.m). */
id AAnimatorFor(id target);

/* ---- Auto Layout (NSLayoutConstraint.m) ------------------------------------------- */

/* Set once any constraint is made active: until then none of this costs anything. */
extern BOOL AConstraintsInUse;
/* a menu item chosen: its action, with the menu's will and did send notifications (AppKitMore.m) */
void ASendMenuItemAction(NSMenuItem *item);
void ALayoutConstraintsIfNeeded(NSView *view);
void ALayoutWindowIfNeeded(NSView *contentView);   /* constraints, then views marked as needing layout */
BOOL AConstraintFittingSize(NSView *view, NSSize *size);
BOOL AConstraintStretches(NSView *view, BOOL vertical, NSLayoutPriority priority);
void AConstraintsViewChanged(NSView *view);
void AConstraintsViewRemoved(NSView *view, NSView *oldSuperview);
void AConstraintsViewDying(NSView *view);
void AViewDecodeConstraints(NSView *view, NSCoder *coder);

/* ---- the display ------------------------------------------------------------------ */

/* Connects to the compositor the first time it is asked; NO when there is no
 * display (no WAYLAND_DISPLAY or DISPLAY, or GTK can't open it). Windows
 * still work without one, drawn off screen. */
BOOL ADisplayAvailable(void);
/* YES for a view in a HUD panel, which a Mac draws dark (its controls light
 * on dark, as in its dark appearance); NSWindow.m. And the colour a light
 * control's text takes there: the usual label colours turn white. */
BOOL AViewIsDark(NSView *view);
NSColor *ADarkText(NSColor *color);
NSRect AScreenFrame(BOOL visibleOnly);
CGFloat AScreenScale(void);
/* Where a nib's window starts (NSWindow.m, 1.229): its rect, laid out on
 * the screen it was designed on, moved onto this screen keeping its
 * distance from the edges in mask (1 left, 2 right, 4 top, 8 bottom) or, on
 * an axis with neither, its place in proportion. */
NSRect AInitialWindowRect(NSRect rect, NSRect designScreen, unsigned mask);
void AWarnOnce(const char *what);
/* Says a whole sentence on stderr once, as it is (AWarnOnce adds "isn't supported yet"). */
void ANoteOnce(const char *sentence);

/* An image or colour from a bundle's asset catalogue, as ferry-actool
 * compiled it (NSAssets.m); nil when the bundle has none of that name. */
NSImage *AAssetImage(NSBundle *bundle, NSString *name);
NSColor *AAssetColor(NSBundle *bundle, NSString *name);
/* AppKit is for the main thread only, as on a Mac. Ferry doesn't stop a
 * program that calls it from another thread, but says so, once. */
void AMainThreadOnly(const char *what);

/* Code GTK calls back into (drawing, resizing, closing, focus, drops) runs
 * the app's code under GTK's own frames, which Ferry can't unwind through,
 * so an exception is caught here and reported, as the event loop does. */
#define A_REPORTING(...)                                                                                        \
    @try {                                                                                                      \
        __VA_ARGS__                                                                                             \
    } @catch (NSException * x_) {                                                                               \
        [NSApp reportException:x_];                                                                             \
    }

/* ---- events -------------------------------------------------------------------------- */

NSEvent *AMouseEvent(NSEventType type, NSPoint location, NSEventModifierFlags flags, NSWindow *window,
                     NSInteger clicks, NSInteger button);
NSEvent *AKeyEvent(NSEventType type, NSEventModifierFlags flags, NSWindow *window, NSString *chars,
                   NSString *unmodified, BOOL repeat, unsigned short code);
NSEvent *AScrollEvent(NSPoint location, NSEventModifierFlags flags, NSWindow *window, CGFloat dx, CGFloat dy,
                      BOOL precise);
void AEventSetWindow(NSEvent *event, NSWindow *window);
void AEnqueueEvent(NSEvent *event);
NSEventModifierFlags AModifiersFromGdk(unsigned state);
unsigned short AMacKeyCode(uint16_t evdevPlusEight);
NSString *ACharactersForKeyval(unsigned keyval, unsigned state, BOOL ignoringModifiers);
void ASetCurrentModifiers(NSEventModifierFlags flags);
void ASetMouseLocation(NSPoint screenPoint, NSUInteger buttons);
/* Event monitors (NSEvent.m, freemac 1.215, Ferry 0.41.0): what the local
 * monitors make of an event the app sends itself (nil: dropped), and an
 * event handed to the global monitors (the app's own hotkeys). */
NSEvent *ALocalMonitorsFilter(NSEvent *event);
void AGlobalMonitorsDeliver(NSEvent *event);

/* ---- windows and views --------------------------------------------------------------- */

/* OpenGL contexts drawing into views (NSOpenGL.m, freemac 1.235): how many
 * views have one; before a view's drawRect:, whether to skip it (the
 * context's drawing alone changed); after it, the context's last frame
 * drawn over it. */
extern int AGLViewCount;
BOOL AGLViewWillDraw(NSView *view);
BOOL AGLViewTakeFrameOnly(NSView *view);
void AGLViewDidDraw(NSView *view, CGContextRef ctx);
void AWindowsDisplayIfNeeded(void);
void AWindowsNeedUpdate(void);
void AWindowsUpdate(void);
void AGlibAttach(void);
/* the app's main menu in the desktop's menu bar (AMainMenuBar.m) */
void AMainMenuBarAttach(GdkWindow *window);
void AMainMenuBarChanged(void);
/* freemac's light or dark appearance (AppKitMore.m, freemac 1.245): whether
 * the desktop is dark, whether drawing is in a dark appearance now, the
 * appearance an object set for itself, and following the desktop's changes */
BOOL ADesktopDark(void);
BOOL ADrawsDark(void);
NSAppearance *AOwnAppearance(id object);
NSAppearance *ABeginDrawingAppearance(id object);
void AEndDrawingAppearance(NSAppearance *saved);
void AAppearanceFollow(void);
@interface NSColor (FerryDynamic)
- (NSString *)_ferryDynamicName; /* a system colour's name, nil for others */
@end
NSColor *AColorWithProvider(NSString *name, NSColor * (^provider)(NSAppearance *));
NSColor *ADynamicColor(NSString *name, const CGFloat light[4], const CGFloat dark[4]);
@interface NSUserDefaults (FerryGlobalDomain)
+ (void)_ferrySetGlobalValue:(id)value forKey:(NSString *)key;
@end
NSString *AMenuAccelerator(NSString *key, NSEventModifierFlags mask);
NSWindow *AKeyWindow(void);
NSWindow *AMainWindow(void);
NSArray *AAllWindows(void);
void AWindowDidClose(NSWindow *window);

@interface NSView (FerryPrivate)
- (void)_backingPropertiesChanged;
- (void)_setWindow:(NSWindow *)window;
- (CGAffineTransform)_transformToSuperview;
- (CGAffineTransform)_transformToWindow;
- (void)_drawInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen;
- (BOOL)_collectDirty:(NSRect *)rects count:(int *)n max:(int)max;
- (void)_drawContentInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen;
- (BOOL)_needsDisplayAnywhere;
@end

/* Drag and drop (NSDragging.m): makes a window's GTK drawing area a drop
 * target, and the steps of a drop, which GTK's signals call (and tests). */
void ADragAttach(NSWindow *window, GtkWidget *area);
/* A drag within the app (freemac 1.220, Ferry 0.44.0): YES when a dragging
 * session took this left-button drag or release, which the window then
 * doesn't pass on. */
BOOL ADragSessionTakes(NSEvent *e);
/* A dragging session from what is already on the pasteboard pb. */
NSDraggingSession *ABeginDragSession(NSPasteboard *pb, NSArray *items, id<NSDraggingSource> source, NSEvent *e);

@interface NSWindow (FerryPrivate)
- (void)_appDidResignActive; /* hidesOnDeactivate, NSWindow.m */
- (void)_appDidBecomeActive;
- (void)_enableDrops;
- (NSArray *)_registeredDraggedTypes;
- (NSDragOperation)_dragUpdateAt:(NSPoint)point pasteboard:(NSPasteboard *)pb operations:(NSDragOperation)mask;
- (void)_dragExit;
- (BOOL)_dragDropAt:(NSPoint)point pasteboard:(NSPasteboard *)pb operations:(NSDragOperation)mask;
- (void)_noteNeedsDisplay;
- (BOOL)_wantsMouseMoved;
- (NSSize)_contentSize;
@end

@interface NSControl (FerryPrivate)
- (void)_setDefaults;
- (void)_takeFromCell:(NSCell *)cell;
@end

/* ---- bindings (NSKeyValueBinding.m) --------------------------------------------------- */

/* The user changed a bound view's value: each of its bindings that can be
 * written back sets its key path (only those bound with
 * NSContinuouslyUpdatesValueBindingOption when continuousOnly is YES). */
void ABindingsPush(id view, BOOL continuousOnly);
/* Whether a binding of the view asks for continuous updates. */
BOOL ABindingsWantContinuous(id view);
/* One binding of a view: whether it is bound, its key path's value now
 * (*bound says whether there is one), writing the view's value back, and
 * setting the view from the key path again (Ferry 0.18.0). */
BOOL ABindingIsBound(id view, NSString *name);
id ABindingModelValue(id view, NSString *name, BOOL *bound);
void ABindingPush(id view, NSString *name);
void ABindingRefresh(id view, NSString *name);
/* A table column whose value is bound to "arrangedObjects.key" of a
 * controller: the value shown in a row (transformed, nil's placeholder in
 * its place), and a new one written back to that row's object. */
id ABindingCellValue(NSTableColumn *column, NSInteger row, BOOL *bound);
BOOL ABindingSetCellValue(NSTableColumn *column, NSInteger row, id value);
/* (Ferry 0.19.0) In an outline view the row's object is its item's
 * represented object. A column's per-row bindings: whether all its
 * bindings named `name` (editable, enabled, enabled2...) are true for the
 * row (YES when none is bound), whether it has one, and whether the row's
 * cell takes edits (the value's controller editable, and the row's
 * editable and enabled true). ABindingSetCellValue writes nothing when it
 * doesn't. */
BOOL ABindingCellAllows(NSTableColumn *column, NSString *name, NSInteger row);
BOOL ABindingCellHas(NSTableColumn *column, NSString *name);
BOOL ABindingCellEditable(NSTableColumn *column, NSInteger row);
/* A bound column joined a table: the table's content, selectionIndexes and
 * sortDescriptors are bound to the same controller if they aren't yet. */
void ABindingColumnJoinedTable(NSTableColumn *column);
/* The number of times NSBeep was called (NSTableView.m beeps once). */
NSUInteger ABeepCount(void);
/* How a binding sets and reads a view's property; views and controllers
 * with properties of their own kind override them. */
@interface NSObject (FerryBindings)
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding;
- (id)_ferryValueForBinding:(NSString *)binding;
@end

/* A table's bound rows changed (a bound column's apply). */
@interface NSTableView (FerryBindings)
- (void)_ferryBoundRowsChanged;
/* whether the table is being set from a binding, and running a step so
 * (an outline view's own steps: nothing it does then is written back) */
- (BOOL)_ferryIsBindingUpdate;
- (void)_ferryAsBindingUpdate:(void (^)(void))step;
@end

/* A proxy that hears of its sources' keys (NSUserDefaultsController.m):
 * the first key of each key path observed on it is observed on each of
 * _sources (by default the one _source), and announced as its own. The
 * owner wraps a change of sources in _sourceWillChange and
 * _sourceDidChange. */
@interface AKeyProxy : NSObject {
@public
    NSMutableDictionary *_keys;   /* first key observed on the proxy -> how many times */
    NSArray *_watched;            /* what those keys are observed on */
}
- (id)_source;
- (NSArray *)_sources;
- (void)_sourceWillChange;
- (void)_sourceDidChange;
@end

/* The selection of an array or tree controller (NSArrayController.m):
 * "selection.key" is the one value the controller's selectedObjects share,
 * or NSMultipleValuesMarker (always, with more than one, when the
 * controller's alwaysUsesMultipleValuesMarker says so), NSNoSelectionMarker
 * or NSNotApplicableMarker; setting it sets every selected object's key. */
@interface AArraySelection : AKeyProxy {
@public
    id controller;   /* not retained: it owns us */
}
@end
/* The steps an array controller changes its content by, which
 * NSDictionaryController follows (NSArrayController.m). */
@interface NSArrayController (FerryPrivate)
- (void)_contentInsert:(NSArray *)objects atIndexes:(NSIndexSet *)indexes;
- (void)_contentRemove:(NSArray *)objects;
- (NSArray *)_contentObjects;
@end

@interface NSButtonCell (FerryPrivate)
- (BOOL)_hasButtonType;
- (NSButtonType)_buttonType;
@end

@interface NSButton (FerryPrivate)
- (NSButtonType)_buttonType;
@end

/* The steps of a text field's editing and drawing that NSSearchField
 * changes (NSControl.m). */
@interface NSTextField (FerryPrivate)
- (BOOL)_isEditing;
- (NSRect)_textRect;
- (NSRect)_clipRect;
- (void)_drawBezelInRect:(NSRect)rect focused:(BOOL)focused;
- (NSAttributedString *)_shownPlaceholder;
/* the size of what it shows, which an editable field doesn't give as its
 * intrinsic width (freemac 1.225) but a search field, combo box or token
 * field grows by */
- (NSSize)_textSize;
- (void)_changed;
- (void)_post:(NSNotificationName)name selector:(SEL)sel;
/* editing in a table's cell (NSTableView.m) */
- (NSTableView *)_editingTable;
- (NSInteger)_textMovement;
- (void)_setTextMovement:(NSInteger)movement;
- (void)_discardEditsTo:(id)value;
- (void)_placeCaretAtEnd;
@end

/* ---- menus opened in a window (NSPopUpButton.m) -------------------------------------- */

/* A menu drawn over a window's views, as a Mac draws a pop-up menu, which
 * takes the window's mouse and keys until an item is chosen or it is
 * dismissed. Wayland doesn't let a program place a window of its own over
 * another, so the menu stays inside its window. */
/* the standard key binding command for a key press, or NULL (NSEvent.m) */
SEL AKeyBindingCommand(unichar c, NSEventModifierFlags f);

@class AMenuView;
@protocol AMenuOwner <NSObject>
/* item is nil when the menu was dismissed */
- (void)_menuView:(AMenuView *)menu didChooseItem:(NSMenuItem *)item;
@end
@interface AMenuView : NSView
/* Opens menu for view: with item number aligned (its title over rect's,
 * in view's coordinates), or below rect when aligned is -1; a pull-down
 * list's menu leaves out its first item (skip). */
+ (AMenuView *)openMenu:(NSMenu *)menu forView:(NSView *)view rect:(NSRect)rect alignItem:(NSInteger)aligned
              skipFirst:(BOOL)skip font:(NSFont *)font owner:(id<AMenuOwner>)owner;
@property (readonly) NSMenu *menu;
@property (readonly) NSInteger highlightedIndex;
@property (readonly) NSRect menuRect;       /* in the window's coordinates */
- (NSRect)rectOfItemAtIndex:(NSInteger)index;  /* in the window's coordinates */
- (void)highlightItemAtIndex:(NSInteger)index;
- (void)chooseHighlightedItem;
- (void)dismiss;
@end

@interface NSWindow (FerryOverlay)
/* A root view drawn over everything else in the window that gets every
 * mouse and key event while it is there (an open menu). */
- (NSView *)_overlayView;
- (void)_setOverlayView:(NSView *)view;
/* The toolbar's strip changed height: the window grows or shrinks by as
 * much, keeping its content view's size (NSToolbar.m). */
- (void)_toolbarLayoutChanged;
- (NSView *)_toolbarView;
@end

/* Sheets (NSWindow.m). A sheet begun by NSApp's old call tells its
 * delegate before it is put away; a picture of a window, with a title bar
 * drawn as the desktop's compositor draws one, for tests and reports. */
@interface NSWindow (FerrySheets)
- (void)_setLegacySheet:(BOOL)flag;
- (void)_detachSheet:(NSWindow *)sheet;
- (BOOL)_isHostedSheet;
- (NSString *)_shownTitle;
- (NSBitmapImageRep *)_pictureWithTitleBar:(BOOL)titleBar;
@end

/* (NSApplication.m) Whether target takes item's action now: its
 * validateMenuItem: for a menu item, else validateUserInterfaceItem:, else
 * yes. */
BOOL AValidateItem(id target, id item);
/* (NSSavePanel.m) The file extensions a type name or uniform type
 * identifier stands for; nil for an identifier Ferry doesn't know. */
NSArray *AExtensionsForType(NSString *type);
/* (NSDocumentController.m) The Open Recent menu named in a nib. */
void ANoteRecentDocumentsMenu(NSMenu *menu);
@interface NSDocumentController (FerryPrivate)
/* the shared controller if one has been made, without making one */
+ (NSDocumentController *)_existingSharedController;
- (NSArray *)_typesForClass:(Class)cls editorsOnly:(BOOL)editors;
- (NSUInteger)_nextUntitledNumber;
- (void)_fillRecentMenu;
@end
@interface NSDocument (FerryPrivate)
/* (NSDocument.m) whether closing autosaves instead of asking: the class
 * autosaves in place and the document has a file */
- (BOOL)_closesWithoutAsking;
/* (NSDocument.m) a document the controller holds is one of NSFileCoordinator's
 * file presenters (freemac 1.220); NSDocumentController's addDocument: and
 * removeDocument: start and stop it */
- (void)_startPresenting;
- (void)_stopPresenting;
@end

/* (NSToolbar.m) the strip a window's toolbar is drawn in, a root view of the
 * window above its content view. */
@interface NSToolbar (FerryPrivate)
- (void)_setWindow:(NSWindow *)window;
- (NSWindow *)_window;
- (CGFloat)_height;
- (NSView *)_makeView;
@end

/* ---- nibs (NSNib.m) ---------------------------------------------------------------------- */

@interface NSKeyedUnarchiver (FerryPrivate)
- (NSArray *)_decodeArrayKeepingNullsForKey:(NSString *)key;
@end
/* Reads nibs in Xcode's "NIBArchive" form (ANibArchive.m). */
@interface ANibArchive : NSCoder
+ (BOOL)isNibArchive:(NSData *)data;
- (instancetype)initForReadingWithData:(NSData *)data;
- (NSArray *)_decodeArrayKeepingNullsForKey:(NSString *)key;
@end
/* Loads a nib with objects handed in from outside, by the names its
 * NSNibExternalObjectPlaceholders give (freemac 1.260). */
@interface NSNib (FerryExternalObjects)
- (BOOL)_instantiateWithOwner:(id)owner
              externalObjects:(NSDictionary *)externals
              topLevelObjects:(NSArray **)topLevelObjects;
@end
/* Storyboards (NSStoryboard.m): the storyboard whose scene is being
 * loaded, if any, and where one of its nibs is. */
CGWindowID ACGWindowNumberForView(int64_t view); /* CGServices.m */
NSStoryboard *AStoryboardLoading(void);
void ALoadMainStoryboard(void);
@interface NSStoryboard (FerryPrivate)
- (NSString *)_pathForNibNamed:(NSString *)name;
@end
NSRect AViewFrameFromCoder(NSCoder *coder);
void AViewDecode(NSView *view, NSCoder *coder);
/* The name of an image, or of a nib's stand-in for one (NSSwitch...). */
@interface NSObject (FerryNibImage)
- (NSString *)_imageName;
@end
@interface NSWindow (FerryControllers)
- (NSWindowController *)_windowController;
- (void)_setWindowController:(NSWindowController *)wc;
@end
@interface NSView (FerryControllers)
- (NSViewController *)_viewController;
- (void)_setViewController:(NSViewController *)vc;
- (void)_safeAreaInsetsChanged;   /* AppKitNewer.m */
@end
@interface NSImage (FerryPrivate)
/* In rect, upright in flipped views; a template is filled with color. */
- (void)_drawInControlRect:(NSRect)rect color:(NSColor *)color fraction:(CGFloat)fraction;
@end
/* Records a menu named in a nib ("_NSMainMenu", "_NSWindowsMenu"...). */
void ANibNoteNamedMenu(NSMenu *menu, NSString *name);

@interface NSGraphicsContext (FerryPrivate)
- (void)_setDrawingToScreen:(BOOL)screen;
@end

/* ---- tables (NSTableView.m, NSOutlineView.m) --------------------------------------------- */

/* Private steps the table, its header and row views, and NSOutlineView
 * share. NSOutlineView overrides the data and delegate ones. */
@interface NSTableView (FerryTablePrivate)
- (NSInteger)_countRows;
- (id)_objectValueForColumn:(NSTableColumn *)column row:(NSInteger)row;
- (void)_setObjectValue:(id)value forColumn:(NSTableColumn *)column row:(NSInteger)row;
- (BOOL)_delegateMakesViews;
- (NSView *)_delegateViewForColumn:(NSTableColumn *)column row:(NSInteger)row;
/* (Ferry 0.20.0) A table from a nib with cell view prototypes, its rows
 * from bindings, makes its own views when its delegate doesn't: the
 * prototype named by each column's identifier, the delegate its owner. */
- (BOOL)_makesViewsFromNib;
- (NSView *)_viewFromNibForColumn:(NSTableColumn *)column;
- (NSTableRowView *)_delegateRowViewForRow:(NSInteger)row;
- (void)_didAddRowView:(NSTableRowView *)view row:(NSInteger)row;
- (void)_didRemoveRowView:(NSTableRowView *)view row:(NSInteger)row;
- (NSCell *)_delegateCellForColumn:(NSTableColumn *)column row:(NSInteger)row;
- (void)_willDisplayCell:(NSCell *)cell column:(NSTableColumn *)column row:(NSInteger)row;
- (BOOL)_delegateHasRowHeights;
- (CGFloat)_delegateHeightOfRow:(NSInteger)row;
- (BOOL)_isGroupRow:(NSInteger)row;
- (BOOL)_selectionShouldChange;
- (BOOL)_shouldSelectRow:(NSInteger)row;
- (NSNotificationName)_selectionDidChangeName;
- (SEL)_selectionDidChangeSelector;
- (NSNotificationName)_columnDidResizeName;
- (SEL)_columnDidResizeSelector;
- (void)_sortDescriptorsDidChange:(NSArray *)old;
- (void)_mouseDownInHeaderOfColumn:(NSTableColumn *)column;
- (void)_didClickColumn:(NSTableColumn *)column;
- (CGFloat)_indentationForRow:(NSInteger)row column:(NSInteger)column;
- (BOOL)_handleMouseDown:(NSEvent *)event row:(NSInteger)row column:(NSInteger)column point:(NSPoint)p;
- (void)_drawDecorationsForRow:(NSInteger)row;
- (void)_drawDecorationsInRowView:(NSTableRowView *)view;
/* dragging rows and dropping on them (freemac 1.220, Ferry 0.44.0) */
- (BOOL)_canDragRows;
- (BOOL)_putRows:(NSIndexSet *)rows onPasteboard:(NSPasteboard *)pb;
- (void)_dragOfRows:(NSIndexSet *)rows session:(NSDraggingSession *)session willBeginAt:(NSPoint)screenPoint;
- (void)_dragSession:(NSDraggingSession *)session endedAt:(NSPoint)screenPoint operation:(NSDragOperation)op;
- (void)_updateDraggingItemsForDrag:(id<NSDraggingInfo>)info;
- (void)_proposeDropAt:(NSPoint)p;
- (NSDragOperation)_validateDrop:(id<NSDraggingInfo>)info;
- (BOOL)_acceptDrop:(id<NSDraggingInfo>)info;
/* where the drop now proposed is shown: on a row (-1: the whole table), or
 * above one (the row count: below the last), with a line indent; NO for
 * nowhere */
- (BOOL)_dropFeedbackRow:(NSInteger *)row operation:(NSTableViewDropOperation *)op indent:(CGFloat *)indent;
/* the table's own */
- (void)_columnWidthChanged:(NSTableColumn *)column from:(CGFloat)old;
- (void)_userResizedColumn:(NSTableColumn *)column by:(CGFloat)delta;
- (void)_headerClickedColumn:(NSTableColumn *)column;
- (BOOL)_isEmphasized;
- (NSTableViewStyle)_drawingStyle;
- (NSInteger)_rowForRowView:(NSTableRowView *)view;
- (void)_updateVisibleViews;
- (void)_dropAllRowViews;
/* the rows were worked out again, with no notifications (an outline opened or closed) */
- (void)_reloadRowsQuietly;
- (void)_setAnchor:(NSInteger)row;
- (void)_selectionChanged;
- (void)_setSelection:(NSIndexSet *)rows notify:(BOOL)notify;
- (void)_post:(NSNotificationName)name selector:(SEL)sel userInfo:(NSDictionary *)info;
/* editing a cell in place: NSOutlineView asks its own delegate and data source */
- (BOOL)_shouldEditColumn:(NSTableColumn *)column row:(NSInteger)row;
- (BOOL)_dataSourceTakesValues;
/* the text field being edited calls these (NSControl.m) */
- (BOOL)_isEditingField:(NSTextField *)field;
- (void)_endEditingWithMovement:(NSInteger)movement;
- (void)_editingFieldDidResign:(NSTextField *)field;
@end

@interface NSTableRowView (FerryPrivate)
- (NSView *)_viewForColumnKey:(id)key;
@end
/* A line of text in frame, cut short with an ellipsis; a chevron pointing
 * right (or down); a selection, rounded and inset unless the style is full
 * width or plain, joined to the rows above and below if they are selected. */
void ATableDrawTextLine(NSAttributedString *string, NSRect frame, NSTextAlignment align, BOOL flipped);
void ATableDrawTextLines(NSAttributedString *string, NSRect frame, NSTextAlignment align, BOOL flipped);
void ATableDrawChevron(NSRect rect, BOOL down, NSColor *color, BOOL flipped);
void ATableDrawSelection(NSRect rect, NSTableViewStyle style, NSTableViewSelectionHighlightStyle highlight,
                         BOOL emphasized, BOOL joinsAbove, BOOL joinsBelow);

/* ---- graphics ----------------------------------------------------------------------- */

void AColorRGBA(NSColor *color, CGFloat rgba[4]);
NSFont *ADefaultFont(void);
/* Draws the attributed string's first line with its baseline at (x, y) in the
 * current context, the right way up whether or not the context is flipped. */
void ADrawLine(NSAttributedString *string, CGFloat x, CGFloat y);
NSSize ALineSize(NSAttributedString *string, CGFloat *ascent, CGFloat *descent);
NSAttributedString *AAttributed(NSString *string, NSFont *font, NSColor *color);
void AFillRoundedRect(NSRect rect, CGFloat radius, NSColor *fill, NSColor *stroke);

/* ---- more controls (NSPopover.m, NSControl.m) --------------------------------------- */

/* A view controller presented as a popover, and dismissed again (NO when it
 * wasn't shown as one). */
void APresentAsPopover(NSViewController *vc, NSRect rect, NSView *view, NSRectEdge edge, NSInteger behavior);
BOOL ADismissPopover(NSViewController *vc);
@interface NSTextField (FerryEditingText)
/* the text being edited, and its selection, set and read by a subclass
 * (completion in a combo box) */
- (void)_setEditingText:(NSString *)text selectedRange:(NSRange)range;
- (NSRange)_selectedTextRange;
@end

/* ---- printing and fonts (NSPrintInfo.m, NSPrintOperation.m, NSFontManager.m) ---------- */

/* From Ferry's Core Text: a font of an installed family, as named, with a
 * Pango weight and style. */
GFont *GFontCreate(NSString *family, int weight, int style, CGFloat size);
/* The family that stands for a Mac family (Helvetica, Times, Menlo...),
 * or nil for a name that isn't one. */
NSString *GFontMacFamily(NSString *name);
NSArray *GFontStandInFamilyNames(void);
@interface NSWindow (FerryPrinting)
/* the GTK window shown for this one, or NULL (a dialog's parent) */
- (GtkWidget *)_gtkWindow;
@end
@interface NSPrintInfo (FerryPrivate)
/* GTK's page setup and print settings made from the print info, and the
 * print info changed to what they say (after GTK's dialogs) */
- (GtkPageSetup *)_gtkPageSetup;
- (GtkPrintSettings *)_gtkPrintSettings;
- (void)_takeGtkPageSetup:(GtkPageSetup *)setup;
- (void)_takeGtkPrintSettings:(GtkPrintSettings *)settings;
/* the words of FERRY_PRINT_ANSWER or FERRY_PAGE_LAYOUT_ANSWER, applied */
- (void)_takeAnswerWords:(NSArray *)words;
@end
@interface NSPrintPanel (FerryPrivate)
/* the printer GTK's dialog chose, if one did */
- (GtkPrinter *)_chosenPrinter;
@end
/* The shared font manager if one has been made, without making one. */
NSFontManager *AExistingFontManager(void);

/* (Ferry 0.36.0) The Core Data calls an entity-mode controller makes. AppKit
 * doesn't link CoreData: the classes are looked up by name, and these
 * declarations name the methods. */
@protocol AManagedCalls
+ (id)fetchRequestWithEntityName:(NSString *)name;
+ (id)insertNewObjectForEntityForName:(NSString *)name inManagedObjectContext:(id)context;
+ (id)entityForName:(NSString *)name inManagedObjectContext:(id)context;
- (void)setPredicate:(NSPredicate *)predicate;
- (NSArray *)executeFetchRequest:(id)request error:(NSError **)error;
- (void)deleteObject:(id)object;
- (BOOL)isKindOfEntity:(id)entity;
- (id)entity;
@end
@interface NSObjectController (AEntityMode)
- (BOOL)_ferryEntityMode;
- (void)_ferryTakeFetched:(NSArray *)found merge:(BOOL)merge;
@end

/* ---- tracking areas and cursors (NSTrackingArea.m, NSCursor.m) ------------------------ */

/* An entered, exited or cursor-update event for a tracking area or
 * tracking rectangle, caused by the mouse event given (NSEvent.m). */
NSEvent *ATrackingEvent(NSEventType type, NSPoint location, NSEvent *cause, NSWindow *window,
                        NSInteger number, void *userData, NSTrackingArea *area);
/* The window's tracking for an event it is sent: YES when the event was
 * one of tracking's own and nothing more is to be done with it. */
BOOL ATrackEvent(NSWindow *window, NSEvent *event);
/* Whether moving the mouse matters to a window's tracking even when the
 * window doesn't take mouse-moved events, and the event GTK's pointer
 * leaving the window becomes. */
BOOL ATrackingWantsMoves(NSWindow *window);
NSEvent *ATrackingWindowExitEvent(NSWindow *window, NSPoint location);
/* A view's geometry changed, or it moves between windows: its tracking
 * areas are updated and its window's cursor rectangles built again. */
void ATrackingGeometryChanged(NSView *view);
void ATrackingViewMoving(NSView *view, NSWindow *from, NSWindow *to);
/* Where the menu bar last said a menu bar item was clicked, in the
 * screen's pixels from its top left; negative when it hasn't said
 * (NSStatusBar.m, for NSPopover.m). */
@interface NSStatusBarButton (FerryClick)
- (NSPoint)_clickedAt;
@end

/* Shows the current cursor (hidden or not) on a window that has a display. */
void ACursorApply(NSWindow *window);
BOOL ACursorMouseMoved(void);

#endif
