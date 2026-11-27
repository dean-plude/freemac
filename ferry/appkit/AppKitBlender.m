/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * What Blender's Mac build calls besides the rest of AppKit and Carbon
 * (freemac Blender work). Written from Apple's public documentation; no
 * Apple code was read.
 *
 * - NSApplicationLoad(): makes the shared application, for a library
 *   (Blender's Python module) that uses AppKit in a program that isn't an
 *   AppKit application.
 * - +[NSEvent setMouseCoalescingEnabled:] and +isMouseCoalescingEnabled:
 *   recorded and reported; Ferry hands every mouse move on as it comes.
 * - GetCurrentEventButtonState() and GetCurrentButtonState(): the mouse
 *   buttons held, bit 0 the primary button, as pressedMouseButtons. */
#import "AInternal.h"

BOOL NSApplicationLoad(void)
{
    [NSApplication sharedApplication];
    return YES;
}

static BOOL mouse_coalescing = YES;

@implementation NSEvent (FerryBlender)
+ (void)setMouseCoalescingEnabled:(BOOL)flag { mouse_coalescing = flag; }
+ (BOOL)isMouseCoalescingEnabled { return mouse_coalescing; }
@end

UInt32 GetCurrentEventButtonState(void) { return (UInt32)[NSEvent pressedMouseButtons]; }
UInt32 GetCurrentButtonState(void) { return (UInt32)[NSEvent pressedMouseButtons]; }
