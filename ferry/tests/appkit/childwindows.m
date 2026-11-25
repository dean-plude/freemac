/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0), with no display: child
 * windows, as Flycut, KeyCastr, Hex Fiend and Sequel Pro use them. A child
 * moves with its parent, goes when the parent is ordered out and comes back
 * with it, leaves when removed or when the parent closes; panels hide when
 * the app is deactivated and come back when it is activated again; and the
 * window properties those apps set (ignoring the mouse, the window menu,
 * collection and animation behaviour, levels, flushing) read back. */
#import <Cocoa/Cocoa.h>

static const char *yn(BOOL b) { return b ? "yes" : "no"; }

static NSWindow *make(NSRect r, Class c)
{
    return [[c alloc] initWithContentRect:r styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                    defer:NO];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *parent = make(NSMakeRect(100, 100, 400, 300), [NSWindow class]);
        NSWindow *child = make(NSMakeRect(150, 150, 100, 50), [NSWindow class]);
        NSWindow *other = make(NSMakeRect(600, 100, 100, 50), [NSWindow class]);
        [parent orderFront:nil];
        [parent addChildWindow:child ordered:NSWindowAbove];
        [parent addChildWindow:other ordered:NSWindowBelow];
        printf("children %lu, child's parent is the parent %s, child visible %s\n",
               (unsigned long)[[parent childWindows] count], yn([child parentWindow] == parent), yn([child isVisible]));
        [parent addChildWindow:child ordered:NSWindowAbove];
        printf("adding the same child again: still %lu\n", (unsigned long)[[parent childWindows] count]);

        [parent setFrameOrigin:NSMakePoint(130, 80)];
        NSRect cf = [child frame];
        printf("after moving the parent by (30, -20) the child is at (%.0f, %.0f)\n", cf.origin.x, cf.origin.y);
        [parent setFrame:NSMakeRect(130, 80, 500, 400) display:NO];
        printf("resizing in place leaves it at (%.0f, %.0f)\n", [child frame].origin.x, [child frame].origin.y);

        [parent orderOut:nil];
        printf("parent ordered out: child visible %s, other visible %s\n", yn([child isVisible]), yn([other isVisible]));
        [parent orderFront:nil];
        printf("parent back: child visible %s, other visible %s\n", yn([child isVisible]), yn([other isVisible]));

        [parent removeChildWindow:other];
        printf("removed one: children %lu, its parent %s\n", (unsigned long)[[parent childWindows] count],
               [other parentWindow] ? "still set" : "nil");
        [parent setFrameOrigin:NSMakePoint(0, 0)];
        printf("a removed child stays put: (%.0f, %.0f)\n", [other frame].origin.x, [other frame].origin.y);

        NSWindow *p2 = make(NSMakeRect(0, 0, 200, 200), [NSWindow class]);
        [child setParentWindow:p2];
        printf("setParentWindow moves it: old parent has %lu, new parent has %lu\n",
               (unsigned long)[[parent childWindows] count], (unsigned long)[[p2 childWindows] count]);
        [p2 setReleasedWhenClosed:NO];
        [p2 close];
        printf("closing the parent: child's parent %s, new parent's children %lu\n",
               [child parentWindow] ? "still set" : "nil", (unsigned long)[[p2 childWindows] count]);

        /* Panels hide when the app does. */
        NSPanel *panel = (NSPanel *)make(NSMakeRect(10, 10, 100, 100), [NSPanel class]);
        printf("panel hides on deactivate: %s, window does: %s\n", yn([panel hidesOnDeactivate]),
               yn([parent hidesOnDeactivate]));
        [panel orderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp deactivate];
        printf("app deactivated: panel visible %s, window visible %s\n", yn([panel isVisible]), yn([parent isVisible]));
        [NSApp activateIgnoringOtherApps:YES];
        printf("app active again: panel visible %s\n", yn([panel isVisible]));
        [panel setHidesOnDeactivate:NO];
        [NSApp deactivate];
        printf("one that doesn't hide stays: %s\n", yn([panel isVisible]));
        [panel setFloatingPanel:YES];
        printf("floating panel level %ld (floating is %ld)\n", (long)[panel level], (long)NSFloatingWindowLevel);

        /* Properties. */
        [parent setIgnoresMouseEvents:YES];
        [parent setExcludedFromWindowsMenu:YES];
        [parent setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                      NSWindowCollectionBehaviorStationary];
        [parent setAnimationBehavior:NSWindowAnimationBehaviorNone];
        [parent setLevel:NSStatusWindowLevel];
        printf("ignores mouse %s, out of the window menu %s, collection behaviour %lu, animation %ld, level %ld\n",
               yn([parent ignoresMouseEvents]), yn([parent isExcludedFromWindowsMenu]),
               (unsigned long)[parent collectionBehavior], (long)[parent animationBehavior], (long)[parent level]);
        printf("levels: dock %ld, pop-up menu %ld, screen saver %ld\n", (long)NSDockWindowLevel,
               (long)NSPopUpMenuWindowLevel, (long)NSScreenSaverWindowLevel);
        [parent disableFlushWindow];
        [parent disableFlushWindow];
        printf("flushing disabled %s", yn([parent isFlushWindowDisabled]));
        [parent enableFlushWindow];
        printf(", after one enable %s", yn([parent isFlushWindowDisabled]));
        [parent enableFlushWindow];
        printf(", after two %s\n", yn([parent isFlushWindowDisabled]));
        [parent flushWindow];
        [parent flushWindowIfNeeded];
        NSDisableScreenUpdates();
        NSEnableScreenUpdates();
        [parent setFrameOrigin:NSMakePoint(130, 80)];
        NSPoint s = [parent convertBaseToScreen:NSMakePoint(10, 10)];
        NSPoint b = [parent convertScreenToBase:s];
        printf("base (10, 10) on the screen is (%.0f, %.0f), and back (%.0f, %.0f)\n", s.x, s.y, b.x, b.y);
    }
    return 0;
}
