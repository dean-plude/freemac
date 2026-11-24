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

/* ---- the display ------------------------------------------------------------------ */

/* Connects to the compositor the first time it is asked; NO when there is no
 * display (no WAYLAND_DISPLAY or DISPLAY, or GTK can't open it). Windows
 * still work without one, drawn off screen. */
BOOL ADisplayAvailable(void);
NSRect AScreenFrame(BOOL visibleOnly);
CGFloat AScreenScale(void);
void AWarnOnce(const char *what);

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

/* ---- windows and views --------------------------------------------------------------- */

void AWindowsDisplayIfNeeded(void);
void AGlibAttach(void);
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
- (void)_drawContentInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen;
- (BOOL)_needsDisplayAnywhere;
@end

/* Drag and drop (NSDragging.m): makes a window's GTK drawing area a drop
 * target, and the steps of a drop, which GTK's signals call (and tests). */
void ADragAttach(NSWindow *window, GtkWidget *area);

@interface NSWindow (FerryPrivate)
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

@interface NSButtonCell (FerryPrivate)
- (BOOL)_hasButtonType;
- (NSButtonType)_buttonType;
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
@end

@interface NSTableRowView (FerryPrivate)
- (NSView *)_viewForColumnKey:(id)key;
@end
/* A line of text in frame, cut short with an ellipsis; a chevron pointing
 * right (or down); a selection, rounded and inset unless the style is full
 * width or plain, joined to the rows above and below if they are selected. */
void ATableDrawTextLine(NSAttributedString *string, NSRect frame, NSTextAlignment align, BOOL flipped);
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

#endif
