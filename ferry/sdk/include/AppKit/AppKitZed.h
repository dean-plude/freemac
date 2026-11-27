/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What the Zed editor's Mac build (GPUI) calls in AppKit besides
 * (freemac 1.268), written from Apple's public documentation; not Apple's
 * header. Implemented in appkit/AppKitZed.m. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_ZED_H_
#define _FERRY_APPKIT_ZED_H_

@interface NSWindow (FerryMovable)
/* whether the user can drag the window; YES unless set */
@property(getter=isMovable) BOOL movable;
@end

@interface NSApplication (FerryWindowsItems)
/* the Window menu's item for a window (Ferry lists open windows itself) */
- (void)addWindowsItem:(NSWindow *)window title:(NSString *)title filename:(BOOL)isFilename;
- (void)changeWindowsItem:(NSWindow *)window title:(NSString *)title filename:(BOOL)isFilename;
- (void)removeWindowsItem:(NSWindow *)window;
- (void)updateWindowsItem:(NSWindow *)window;
@end

#endif
