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
NSWindow *AKeyWindow(void);
NSWindow *AMainWindow(void);
NSArray *AAllWindows(void);
void AWindowDidClose(NSWindow *window);

@interface NSView (FerryPrivate)
- (void)_setWindow:(NSWindow *)window;
- (CGAffineTransform)_transformToSuperview;
- (CGAffineTransform)_transformToWindow;
- (void)_drawInContext:(CGContextRef)ctx dirty:(NSRect)dirty screen:(BOOL)screen;
- (BOOL)_needsDisplayAnywhere;
@end

@interface NSWindow (FerryPrivate)
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
NSRect AViewFrameFromCoder(NSCoder *coder);
void AViewDecode(NSView *view, NSCoder *coder);
/* Image references in nibs, kept by name until Ferry has NSImage. */
@interface NSObject (FerryNibImage)
- (NSString *)_imageName;
@end
/* Records a menu named in a nib ("_NSMainMenu", "_NSWindowsMenu"...). */
void ANibNoteNamedMenu(NSMenu *menu, NSString *name);

@interface NSGraphicsContext (FerryPrivate)
- (void)_setDrawingToScreen:(BOOL)screen;
@end

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
