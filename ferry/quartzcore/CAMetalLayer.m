/* SPDX-License-Identifier: GPL-3.0-or-later
 * CAMetalLayer (freemac 1.232), from Apple's public documentation. Ferry
 * has no Metal device (Metal/Metal.h), so the layer keeps what a program
 * sets on it and draws as any layer does, and nextDrawable answers nil, as
 * a Mac's does when it has no drawable to give. Programs that subclass it
 * (Qt's QMetalLayer) and check for Metal before using it then work. */
#import "QInternal.h"
#import <QuartzCore/CAMetalLayer.h>

@implementation CAMetalLayer {
    CGColorSpaceRef _colorspace;
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
    if (_colorspace)
        CGColorSpaceRelease(_colorspace);
    [super dealloc];
}

- (id<MTLDevice>)preferredDevice { return nil; }
- (CGColorSpaceRef)colorspace { return _colorspace; }
- (void)setColorspace:(CGColorSpaceRef)space
{
    if (space)
        CGColorSpaceRetain(space);
    if (_colorspace)
        CGColorSpaceRelease(_colorspace);
    _colorspace = space;
}
- (id<CAMetalDrawable>)nextDrawable { return nil; }
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
