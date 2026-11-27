/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Chromium calls in Core Animation besides (freemac 1.265, Ferry
 * 0.88.0; first seen in Obsidian):
 *
 * - +[CATransaction addCommitHandler:forPhase:]: a block to run around the
 *   current transaction's commit. Ferry draws layers after the commit, on
 *   the main thread's next pass, so every phase's handler runs then, once.
 * - -[CALayer setContentsChanged]: the layer's contents (an IOSurface
 *   Chromium drew into) changed in place, so it is drawn again.
 * - -[CALayer setEDRMetadata:]: how to map high dynamic range content to
 *   the screen. freemac's screens show standard range, so it is kept and
 *   not used.
 */
#import "QInternal.h"
#import <objc/runtime.h>

@implementation CATransaction (FerryElectron)
+ (void)addCommitHandler:(void (^)(void))block forPhase:(NSInteger)phase
{
    if (!block)
        return;
    void (^handler)(void) = [block copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        handler();
        [handler release];
    });
}
@end

static char edr_metadata_key;

@implementation CALayer (FerryElectron)
- (void)setContentsChanged { [self _ferryChanged]; }
- (id)EDRMetadata { return objc_getAssociatedObject(self, &edr_metadata_key); }
- (void)setEDRMetadata:(id)metadata
{
    objc_setAssociatedObject(self, &edr_metadata_key, metadata, OBJC_ASSOCIATION_RETAIN);
}
@end
