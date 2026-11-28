/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Stats' menu bar items need of AppKit (freemac 1.271, Stats 3.1.1):
 * a status item's button has a window, at the top of the screen under the
 * item, from which Stats places its panel; a window's occlusion state has
 * bit 13 set as a Mac's window server sets it, so Stats' check for exactly
 * 8192 (a panel not on screen) opens the panel; the button's own subviews
 * are views of the item's picture. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered defer:YES];
        NSWindowOcclusionState state = [w occlusionState];
        printf("hidden window: %lu, visible bit %s\n", (unsigned long)state,
               state & NSWindowOcclusionStateVisible ? "set" : "clear");
        [w miniaturize:nil];
        printf("minimized: %lu\n", (unsigned long)[w occlusionState]);

        NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:58];
        NSStatusBarButton *button = item.button;
        NSWindow *bar = button.window;
        printf("button window: %s, same again: %s\n", bar ? "yes" : "no", bar == button.window ? "yes" : "no");
        printf("height %.0f, level %s, top of screen: %s\n", bar.frame.size.height,
               bar.level == NSStatusWindowLevel ? "status" : "other",
               NSMaxY(bar.frame) == NSMaxY([[NSScreen mainScreen] frame]) ? "yes" : "no");
        printf("released when closed: %s\n", bar.releasedWhenClosed ? "yes" : "no");

        NSTextField *label = [NSTextField labelWithString:@"41%"];
        [button addSubview:label];
        [label setNeedsDisplay:YES];   /* tells the item to draw again */
        printf("subview in button: %s\n", label.superview == button ? "yes" : "no");
        [[NSStatusBar systemStatusBar] removeStatusItem:item];
    }
    return 0;
}
