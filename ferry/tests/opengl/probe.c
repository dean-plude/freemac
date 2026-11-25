/* SPDX-License-Identifier: GPL-3.0-or-later
 * Whether this system can run the OpenGL tests (freemac 1.235, Ferry
 * 0.59.0): run.sh runs them when this makes a legacy and a 3.2 core
 * context current, and skips them otherwise. */
#include <OpenGL/OpenGL.h>

static int works(CGLOpenGLProfile profile)
{
    CGLPixelFormatAttribute attrs[] = {kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)profile,
                                       (CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pf = NULL;
    CGLContextObj ctx = NULL;
    GLint n = 0;
    if (CGLChoosePixelFormat(attrs, &pf, &n) || !pf)
        return 0;
    CGLCreateContext(pf, NULL, &ctx);
    CGLReleasePixelFormat(pf);
    int ok = ctx && CGLSetCurrentContext(ctx) == kCGLNoError;
    CGLSetCurrentContext(NULL);
    if (ctx)
        CGLReleaseContext(ctx);
    return ok;
}

int main(void)
{
    return works(kCGLOGLPVersion_Legacy) && works(kCGLOGLPVersion_3_2_Core) ? 0 : 1;
}
