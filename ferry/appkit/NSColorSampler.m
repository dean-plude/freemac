/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSColorSampler (freemac 1.232, Ferry 0.56.0), written
 * from Apple's public API documentation. On a Mac it lets the user pick a
 * colour anywhere on the screen. Ferry can't read the screen's pixels yet,
 * so the sampler ends at once as if the user had pressed Escape: the
 * handler is called with nil, on the main queue, as a cancelled sampler's
 * is. Qt's colour picker (QColorDialog's screen picker) uses it. */
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

@implementation NSColorSampler

- (void)showSamplerWithSelectionHandler:(void (^)(NSColor *selectedColor))selectionHandler
{
    if (!selectionHandler)
        return;
    void (^handler)(NSColor *) = [selectionHandler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(nil);
      [handler release];
    });
}

@end
