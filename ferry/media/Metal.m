/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal.framework for Ferry (freemac 1.232), from Apple's public
 * documentation. Ferry has no Metal GPU, so there is no device, as on a Mac
 * whose GPU doesn't support Metal: programs that check (Qt, OBS) take their
 * OpenGL or software path. */
#import <Metal/Metal.h>

id<MTLDevice> MTLCreateSystemDefaultDevice(void) { return nil; }
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) { return [[NSArray alloc] init]; }
