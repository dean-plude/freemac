/* SPDX-License-Identifier: GPL-3.0-or-later
 * What the Zed editor's Mac build (GPUI) calls in AppKit besides
 * (freemac 1.268). Written from Apple's public documentation. */
#import "AInternal.h"
#import <objc/runtime.h>

static char movable_key;

/* NSWindow.movable: whether the user can drag the window around (by its
 * title bar, or wherever the app lets it). A window is movable unless told
 * otherwise. */
@implementation NSWindow (FerryMovable)
- (BOOL)isMovable
{
    NSNumber *n = objc_getAssociatedObject(self, &movable_key);
    return n ? [n boolValue] : YES;
}
- (void)setMovable:(BOOL)flag
{
    objc_setAssociatedObject(self, &movable_key, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* The Window menu's list of open windows. An app that manages that list
 * itself adds, renames and removes a window's item with these. Ferry's
 * Window menu shows the open windows from the window list when it opens, so
 * these keep nothing more; a window's title still comes from the window
 * (NSApplication, "Managing the Windows Menu"). */
@implementation NSApplication (FerryWindowsItems)
- (void)addWindowsItem:(NSWindow *)window title:(NSString *)title filename:(BOOL)isFilename
{
    (void)window, (void)title, (void)isFilename;
}
- (void)changeWindowsItem:(NSWindow *)window title:(NSString *)title filename:(BOOL)isFilename
{
    (void)window, (void)title, (void)isFilename;
}
- (void)removeWindowsItem:(NSWindow *)window
{
    (void)window;
}
- (void)updateWindowsItem:(NSWindow *)window
{
    (void)window;
}
@end
