/* SPDX-License-Identifier: GPL-3.0-or-later
 * OpenGL on a system without it (freemac 1.235, Ferry 0.59.0): run.sh
 * points FERRY_EGL at a library that isn't there. No pixel format and no
 * context, said once on stderr, AppKit's and Core Animation's OpenGL
 * classes give nil or draw nothing, and Core Video's pixel buffers, which
 * need no OpenGL, still work. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#include <stdio.h>

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

@interface Layer : CAOpenGLLayer
@property int draws;
@end
@implementation Layer
- (void)drawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
            forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts
{
    self.draws++;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        CGLPixelFormatAttribute attrs[] = {kCGLPFAColorSize, (CGLPixelFormatAttribute)24, (CGLPixelFormatAttribute)0};
        CGLPixelFormatObj pf = (CGLPixelFormatObj)1;
        GLint n = -1;
        CGLError e = CGLChoosePixelFormat(attrs, &pf, &n);
        check("no pixel format: a bad display", e == kCGLBadDisplay && pf == NULL && n == 0);
        check("asked again, the same", CGLChoosePixelFormat(attrs, &pf, &n) == kCGLBadDisplay);
        CGLContextObj ctx = (CGLContextObj)1;
        check("no context", CGLCreateContext(NULL, NULL, &ctx) != kCGLNoError && ctx == NULL);
        check("none current", CGLGetCurrentContext() == NULL);

        NSOpenGLPixelFormatAttribute nsattrs[] = {NSOpenGLPFADoubleBuffer, 0};
        check("NSOpenGLPixelFormat: nil",
              [[[NSOpenGLPixelFormat alloc] initWithAttributes:nsattrs] autorelease] == nil);
        check("NSOpenGLContext: nil", [[[NSOpenGLContext alloc] initWithFormat:nil shareContext:nil] autorelease] == nil);
        NSOpenGLView *v = [[[NSOpenGLView alloc] initWithFrame:NSMakeRect(0, 0, 40, 30)] autorelease];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 60, 50) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        if (v)
            [[w contentView] addSubview:v];
        [w display];
        check("an NSOpenGLView with no context draws as a view", !v || [v openGLContext] == nil);

        Layer *l = [Layer layer];
        l.bounds = CGRectMake(0, 0, 40, 30);
        [l display];
        check("a CAOpenGLLayer draws nothing", l.draws == 0 && [l contents] == nil);

        CVPixelBufferRef pb = NULL;
        CVReturn r = CVPixelBufferCreate(NULL, 64, 48, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                         (CFDictionaryRef) @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}}, &pb);
        check("a 420v pixel buffer still", r == kCVReturnSuccess && pb && CVPixelBufferGetPlaneCount(pb) == 2 &&
                                               CVPixelBufferGetIOSurface(pb) != NULL);
        CVOpenGLTextureCacheRef cache = NULL;
        check("no texture cache without a context",
              CVOpenGLTextureCacheCreate(NULL, NULL, NULL, NULL, NULL, &cache) != kCVReturnSuccess && cache == NULL);
        CVPixelBufferRelease(pb);
    }
    return 0;
}
