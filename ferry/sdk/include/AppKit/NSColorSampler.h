/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSColorSampler (freemac 1.232, Ferry 0.56.0), written for
 * Ferry from Apple's public API documentation (appkit/NSColorSampler.m).
 * Ferry can't yet sample a colour from the screen, so the sampler ends at
 * once as if the user had cancelled it: the handler gets nil. */
#ifndef FERRY_NSCOLORSAMPLER_H
#define FERRY_NSCOLORSAMPLER_H
#import <AppKit/AppKit.h>
@interface NSColorSampler : NSObject
- (void)showSamplerWithSelectionHandler:(void (^)(NSColor *selectedColor))selectionHandler;
@end
#endif
