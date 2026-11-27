/* SPDX-License-Identifier: GPL-3.0-or-later
 * CAMetalLayer, from Apple's public documentation. With Ferry's Metal
 * device (metal/fw) the layer gives drawables: a texture the size of
 * drawableSize (or of the layer's bounds at its scale), which, presented,
 * becomes the layer's contents. A layer gives at most maximumDrawableCount
 * drawables at a time; nextDrawable waits up to a second for one to come
 * back, as on a Mac. Without a device nextDrawable answers nil, as a Mac's
 * does when it has no drawable to give. QuartzCore doesn't link Metal: it
 * asks for Metal's classes by name. */
#import "QInternal.h"
#import <QuartzCore/CAMetalLayer.h>
#include <dispatch/dispatch.h>

@interface NSObject (FerryMetalForLayer)
+ (id)ferryDeviceIfOn;
+ (id)ferryDrawableForLayer:(id)layer device:(id)device width:(NSUInteger)w height:(NSUInteger)h
                     format:(MTLPixelFormat)format slot:(dispatch_semaphore_t)slot;
@end

@implementation CAMetalLayer {
    CGColorSpaceRef _colorspace;
    dispatch_semaphore_t _slots;
    NSUInteger _slotCount, _shownID;
}
@synthesize device = _device, pixelFormat = _pixelFormat, framebufferOnly = _framebufferOnly,
            drawableSize = _drawableSize, maximumDrawableCount = _maximumDrawableCount,
            presentsWithTransaction = _presentsWithTransaction,
            wantsExtendedDynamicRangeContent = _wantsExtendedDynamicRangeContent,
            displaySyncEnabled = _displaySyncEnabled, allowsNextDrawableTimeout = _allowsNextDrawableTimeout;

- (instancetype)init
{
    if ((self = [super init])) {
        _pixelFormat = MTLPixelFormatBGRA8Unorm;
        _framebufferOnly = YES;
        _maximumDrawableCount = 3;
        _displaySyncEnabled = YES;
        _allowsNextDrawableTimeout = YES;
    }
    return self;
}

- (void)dealloc
{
    [_device release];
    if (_slots)
        dispatch_release(_slots);
    if (_colorspace)
        CGColorSpaceRelease(_colorspace);
    [super dealloc];
}

- (id<MTLDevice>)preferredDevice { return [NSClassFromString(@"FerryMTLDevice") ferryDeviceIfOn]; }
- (CGColorSpaceRef)colorspace { return _colorspace; }
- (void)setColorspace:(CGColorSpaceRef)space
{
    if (space)
        CGColorSpaceRetain(space);
    if (_colorspace)
        CGColorSpaceRelease(_colorspace);
    _colorspace = space;
}
- (id<CAMetalDrawable>)nextDrawable
{
    Class cls = NSClassFromString(@"FerryMTLDrawable");
    id device = self.device;
    if (!cls || !device)
        return nil;
    CGSize size = self.drawableSize;
    if (size.width <= 0 || size.height <= 0) {
        CGRect b = self.bounds;
        double scale = self.contentsScale > 0 ? self.contentsScale : 1;
        size = CGSizeMake(ceil(b.size.width * scale), ceil(b.size.height * scale));
    }
    dispatch_semaphore_t slots;
    @synchronized(self) {
        NSUInteger n = _maximumDrawableCount < 2 ? 2 : _maximumDrawableCount > 3 ? 3 : _maximumDrawableCount;
        if (!_slots || _slotCount != n) {
            /* (drawables already given keep the old semaphore) */
            if (_slots)
                dispatch_release(_slots);
            _slots = dispatch_semaphore_create((long)n);
            _slotCount = n;
        }
        slots = _slots;
        dispatch_retain(slots);
    }
    dispatch_time_t limit = _allowsNextDrawableTimeout ? dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC) : DISPATCH_TIME_FOREVER;
    if (dispatch_semaphore_wait(slots, limit) != 0) {
        dispatch_release(slots);
        return nil;
    }
    id d = [cls ferryDrawableForLayer:self device:device width:(NSUInteger)size.width height:(NSUInteger)size.height
                               format:_pixelFormat slot:slots];
    if (!d)
        dispatch_semaphore_signal(slots);
    dispatch_release(slots);
    return d;
}

/* A presented drawable's picture: @[image, drawable id], on the main thread. */
- (void)_ferryShowMetalImage:(NSArray *)a
{
    NSUInteger serial = [a[1] unsignedIntegerValue];
    if (serial < _shownID)
        return;
    _shownID = serial;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self _ferrySetValue:a[0] forKey:@"contents"];
    [CATransaction commit];
}
@end

/* Any layer keeps whether it wants extended dynamic range (macOS 14); a
 * Metal layer keeps its own. */
@implementation CALayer (FerryExtendedDynamicRange)
static char edr_key;
- (BOOL)wantsExtendedDynamicRangeContent { return [objc_getAssociatedObject(self, &edr_key) boolValue]; }
- (void)setWantsExtendedDynamicRangeContent:(BOOL)wants
{
    objc_setAssociatedObject(self, &edr_key, wants ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
