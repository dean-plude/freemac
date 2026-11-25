/* SPDX-License-Identifier: GPL-3.0-or-later
 * IOSurfaces as OpenGL textures (freemac 1.235, Ferry 0.59.0): a BGRA
 * surface through CGLTexImageIOSurface2D, drawn into a context's drawable
 * and read back by a flush; the two planes of a 4:2:0 pixel buffer as R8
 * and RG8 textures, as OBS's mac-capture sources use them; a '2vuy'
 * surface as Apple's RGB_422 textures, as VLC's OpenGL output uses them;
 * and Core Video's texture cache. */
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurface.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <stdio.h>
#include <string.h>
#include "../../opengl/FerryGL.h"

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

static CGLContextObj make(CGLOpenGLProfile profile)
{
    CGLPixelFormatAttribute attrs[] = {kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAColorSize,
                                       (CGLPixelFormatAttribute)24, kCGLPFAOpenGLProfile,
                                       (CGLPixelFormatAttribute)profile, (CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pix = NULL;
    GLint n = 0;
    CGLContextObj ctx = NULL;
    if (CGLChoosePixelFormat(attrs, &pix, &n) || !pix)
        return NULL;
    CGLCreateContext(pix, NULL, &ctx);
    CGLReleasePixelFormat(pix);
    return ctx;
}

/* Reads a texture back through a framebuffer it is attached to. */
static void read_texture(GLenum target, GLuint tex, int x, int y, GLenum format, GLenum type, void *out)
{
    GLuint fb = 0;
    glGenFramebuffers(1, &fb);
    glBindFramebuffer(GL_FRAMEBUFFER, fb);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, target, tex, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(x, y, 1, 1, format, type, out);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &fb);
}

static IOSurfaceRef bgra_surface(int w, int h, int rowBytes)
{
    return IOSurfaceCreate((CFDictionaryRef) @{
        (id)kIOSurfaceWidth : @(w),
        (id)kIOSurfaceHeight : @(h),
        (id)kIOSurfaceBytesPerElement : @4,
        (id)kIOSurfaceBytesPerRow : @(rowBytes),
        (id)kIOSurfacePixelFormat : @((unsigned)'BGRA'),
    });
}

int main(void)
{
    @autoreleasepool {
        CGLContextObj legacy = make(kCGLOGLPVersion_Legacy);
        if (!check("a legacy context", legacy != NULL))
            return 1;
        CGLSetCurrentContext(legacy);

        /* a BGRA surface, its rows wider than its pixels: red on the left,
         * green on the right, the left of its last eight rows blue */
        IOSurfaceRef s = bgra_surface(64, 32, 320);
        check("a 64 by 32 BGRA surface, 320 bytes a row", s && IOSurfaceGetBytesPerRow(s) == 320);
        IOSurfaceLock(s, 0, NULL);
        unsigned char *p = IOSurfaceGetBaseAddress(s);
        for (int y = 0; y < 32; y++)
            for (int x = 0; x < 64; x++) {
                unsigned char *px = p + y * 320 + x * 4;
                int blue = y >= 24 && x < 32;
                px[0] = blue ? 255 : 0, px[1] = x >= 32 ? 255 : 0, px[2] = x < 32 && !blue ? 255 : 0, px[3] = 255;
            }
        IOSurfaceUnlock(s, 0, NULL);
        GLuint tex = 0;
        glGenTextures(1, &tex);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, tex);
        CGLError e = CGLTexImageIOSurface2D(legacy, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, 64, 32, GL_BGRA,
                                            GL_UNSIGNED_INT_8_8_8_8_REV, s, 0);
        check("CGLTexImageIOSurface2D", e == kCGLNoError && glGetError() == GL_NO_ERROR);
        GLint rowlen = -1;
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowlen);
        check("the unpack state left as it was", rowlen == 0);
        unsigned char got[4] = {0};
        read_texture(GL_TEXTURE_RECTANGLE_ARB, tex, 5, 0, GL_BGRA, GL_UNSIGNED_BYTE, got);
        check("the texture's first row: red on the left", got[0] == 0 && got[1] == 0 && got[2] == 255);
        read_texture(GL_TEXTURE_RECTANGLE_ARB, tex, 40, 0, GL_BGRA, GL_UNSIGNED_BYTE, got);
        check("green on the right", got[0] == 0 && got[1] == 255 && got[2] == 0);
        read_texture(GL_TEXTURE_RECTANGLE_ARB, tex, 5, 30, GL_BGRA, GL_UNSIGNED_BYTE, got);
        check("blue at the left of its last rows", got[0] == 255 && got[1] == 0 && got[2] == 0);

        /* drawn on a quad into the drawable, and read back by a flush */
        FerryCGLSetDrawableSize(legacy, 64, 32);
        glViewport(0, 0, 64, 32);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, 64, 0, 32, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glEnable(GL_TEXTURE_RECTANGLE_ARB);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, tex);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
        glBegin(GL_QUADS);
        glTexCoord2f(0, 0), glVertex2f(0, 0);
        glTexCoord2f(64, 0), glVertex2f(64, 0);
        glTexCoord2f(64, 32), glVertex2f(64, 32);
        glTexCoord2f(0, 32), glVertex2f(0, 32);
        glEnd();
        glDisable(GL_TEXTURE_RECTANGLE_ARB);
        CGLFlushDrawable(legacy);
        FerryGLFrame *f = FerryCGLCopyFrame(legacy);
        int shown = f && f->width == 64 && f->height == 32;
        if (shown) {
            unsigned char *bl = f->data + 2 * f->rowBytes + 2 * 4, *br = f->data + 2 * f->rowBytes + 60 * 4;
            unsigned char *tl = f->data + 30 * f->rowBytes + 2 * 4;
            shown = bl[2] == 255 && bl[1] == 0 && br[1] == 255 && br[2] == 0 && tl[0] == 255 && tl[2] == 0;
        }
        check("the surface shows in the drawable", shown);
        FerryGLFrameRelease(f);

        /* new contents need a new call: the texture holds the old ones */
        IOSurfaceLock(s, 0, NULL);
        memset(p, 255, 320 * 32);
        IOSurfaceUnlock(s, 0, NULL);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, tex);
        CGLTexImageIOSurface2D(legacy, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, 64, 32, GL_BGRA,
                               GL_UNSIGNED_INT_8_8_8_8_REV, s, 0);
        read_texture(GL_TEXTURE_RECTANGLE_ARB, tex, 5, 0, GL_BGRA, GL_UNSIGNED_BYTE, got);
        check("the surface's new contents after another call", got[0] == 255 && got[1] == 255 && got[2] == 255);
        check("a plane a packed surface hasn't refused",
              CGLTexImageIOSurface2D(legacy, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, 64, 32, GL_BGRA,
                                     GL_UNSIGNED_INT_8_8_8_8_REV, s, 1) == kCGLBadValue);
        glDeleteTextures(1, &tex);

        /* '2vuy' as Apple's RGB_422: Cb Y0 Cr Y1 */
        CVPixelBufferRef yuv = NULL;
        CVPixelBufferCreate(NULL, 8, 2, kCVPixelFormatType_422YpCbCr8, NULL, &yuv);
        CVPixelBufferLockBaseAddress(yuv, 0);
        unsigned char *q = CVPixelBufferGetBaseAddress(yuv);
        for (int y = 0; y < 2; y++)
            for (int i = 0; i < 4; i++)
                memcpy(q + y * CVPixelBufferGetBytesPerRow(yuv) + i * 4, (unsigned char[]){40, 100, 200, 150}, 4);
        CVPixelBufferUnlockBaseAddress(yuv, 0);
        glGenTextures(1, &tex);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, tex);
        e = CGLTexImageIOSurface2D(legacy, GL_TEXTURE_RECTANGLE_ARB, GL_RGB, 8, 2, GL_RGB_422_APPLE,
                                   GL_UNSIGNED_SHORT_8_8_APPLE, CVPixelBufferGetIOSurface(yuv), 0);
        unsigned char rgb0[4] = {0}, rgb1[4] = {0};
        read_texture(GL_TEXTURE_RECTANGLE_ARB, tex, 0, 1, GL_RGBA, GL_UNSIGNED_BYTE, rgb0);
        read_texture(GL_TEXTURE_RECTANGLE_ARB, tex, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, rgb1);
        check("2vuy: Cr, Y and Cb in red, green and blue",
              e == kCGLNoError && rgb0[0] == 200 && rgb0[1] == 100 && rgb0[2] == 40 && rgb1[1] == 150 && rgb1[0] == 200);
        glDeleteTextures(1, &tex);
        CVPixelBufferRelease(yuv);

        /* not current: refused */
        CGLSetCurrentContext(NULL);
        check("refused with no context current",
              CGLTexImageIOSurface2D(legacy, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, 64, 32, GL_BGRA,
                                     GL_UNSIGNED_INT_8_8_8_8_REV, s, 0) == kCGLBadContext);
        CFRelease(s);

        /* a 4:2:0 pixel buffer's planes, in a core context */
        CGLContextObj core = make(kCGLOGLPVersion_3_2_Core);
        check("a core context", core != NULL);
        CGLSetCurrentContext(core);
        CVPixelBufferRef nv12 = NULL;
        CVPixelBufferCreate(NULL, 64, 32, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &nv12);
        CVPixelBufferLockBaseAddress(nv12, 0);
        unsigned char *yp = CVPixelBufferGetBaseAddressOfPlane(nv12, 0), *cp = CVPixelBufferGetBaseAddressOfPlane(nv12, 1);
        for (int y = 0; y < 32; y++)
            memset(yp + y * CVPixelBufferGetBytesPerRowOfPlane(nv12, 0), y < 16 ? 60 : 200, 64);
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 32; x++)
                cp[y * CVPixelBufferGetBytesPerRowOfPlane(nv12, 1) + 2 * x] = 90,
                    cp[y * CVPixelBufferGetBytesPerRowOfPlane(nv12, 1) + 2 * x + 1] = 170;
        CVPixelBufferUnlockBaseAddress(nv12, 0);
        IOSurfaceRef ns = CVPixelBufferGetIOSurface(nv12);
        GLuint planes[2];
        glGenTextures(2, planes);
        glBindTexture(GL_TEXTURE_RECTANGLE, planes[0]);
        CGLError e0 = CGLTexImageIOSurface2D(core, GL_TEXTURE_RECTANGLE, GL_R8, 64, 32, GL_RED, GL_UNSIGNED_BYTE, ns, 0);
        glBindTexture(GL_TEXTURE_RECTANGLE, planes[1]);
        CGLError e1 = CGLTexImageIOSurface2D(core, GL_TEXTURE_RECTANGLE, GL_RG8, 32, 16, GL_RG, GL_UNSIGNED_BYTE, ns, 1);
        check("both planes as textures", e0 == kCGLNoError && e1 == kCGLNoError && glGetError() == GL_NO_ERROR);
        unsigned char luma[2] = {0}, luma2[2] = {0}, chroma[2] = {0};
        read_texture(GL_TEXTURE_RECTANGLE, planes[0], 10, 3, GL_RED, GL_UNSIGNED_BYTE, luma);
        read_texture(GL_TEXTURE_RECTANGLE, planes[0], 10, 20, GL_RED, GL_UNSIGNED_BYTE, luma2);
        read_texture(GL_TEXTURE_RECTANGLE, planes[1], 7, 9, GL_RG, GL_UNSIGNED_BYTE, chroma);
        check("Y read back from the R8 texture", luma[0] == 60 && luma2[0] == 200);
        check("Cb and Cr read back from the RG8 texture", chroma[0] == 90 && chroma[1] == 170);
        glDeleteTextures(2, planes);
        CVPixelBufferRelease(nv12);

        /* Core Video's texture cache */
        CVOpenGLTextureCacheRef cache = NULL;
        check("a texture cache", CVOpenGLTextureCacheCreate(NULL, NULL, core, CGLGetPixelFormat(core), NULL, &cache) ==
                                         kCVReturnSuccess &&
                                     cache);
        CVPixelBufferRef bgra = NULL;
        CVPixelBufferCreate(NULL, 16, 16, kCVPixelFormatType_32BGRA, NULL, &bgra);
        CVPixelBufferLockBaseAddress(bgra, 0);
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++)
                memcpy((unsigned char *)CVPixelBufferGetBaseAddress(bgra) + y * CVPixelBufferGetBytesPerRow(bgra) + x * 4,
                       (unsigned char[]){10, 20, 30, 255}, 4);
        CVPixelBufferUnlockBaseAddress(bgra, 0);
        CVBufferSetAttachment(bgra, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                              kCVAttachmentMode_ShouldPropagate);
        CVOpenGLTextureRef t = NULL;
        CVReturn r = CVOpenGLTextureCacheCreateTextureFromImage(NULL, cache, bgra, NULL, &t);
        check("a texture from a BGRA buffer", r == kCVReturnSuccess && t && CVOpenGLTextureGetName(t) &&
                                                   CVOpenGLTextureGetTarget(t) == GL_TEXTURE_RECTANGLE);
        GLfloat ll[2], lr[2], ur[2], ul[2];
        CVOpenGLTextureGetCleanTexCoords(t, ll, lr, ur, ul);
        check("flipped, with clean coordinates in pixels",
              CVOpenGLTextureIsFlipped(t) && ll[1] == 16 && ur[0] == 16 && ul[0] == 0 && ul[1] == 0);
        check("the buffer's attachments passed on", CVBufferHasAttachment(t, kCVImageBufferYCbCrMatrixKey));
        unsigned char c4[4] = {0};
        read_texture(CVOpenGLTextureGetTarget(t), CVOpenGLTextureGetName(t), 8, 8, GL_BGRA, GL_UNSIGNED_BYTE, c4);
        check("its pixels", c4[0] == 10 && c4[1] == 20 && c4[2] == 30);
        CVPixelBufferRef planar = NULL;
        CVPixelBufferCreate(NULL, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, NULL, &planar);
        CVOpenGLTextureRef none = NULL;
        check("a planar buffer refused",
              CVOpenGLTextureCacheCreateTextureFromImage(NULL, cache, planar, NULL, &none) ==
                      kCVReturnPixelBufferNotOpenGLCompatible &&
                  !none);
        CVPixelBufferRelease(planar);
        CVOpenGLTextureRelease(t);
        CVOpenGLTextureCacheFlush(cache, 0);
        CVPixelBufferRelease(bgra);
        CVOpenGLTextureCacheRelease(cache);
        check("no errors left", glGetError() == GL_NO_ERROR);

        CGLSetCurrentContext(NULL);
        CGLReleaseContext(core);
        CGLReleaseContext(legacy);
    }
    return 0;
}
