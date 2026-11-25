/* SPDX-License-Identifier: GPL-3.0-or-later
 * CGL (freemac 1.235, Ferry 0.59.0): a pixel format and a context of each
 * profile, cleared to a color and read back with glReadPixels, a drawable
 * read back by a flush, swap intervals and parameters, the lock, contexts
 * current on two threads in turns, and OpenGL's calls found by name the
 * way VLC and OBS find them (dlsym and dlopen of the framework). */
#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include "../../opengl/FerryGL.h"

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

static CGLContextObj make(CGLOpenGLProfile profile, CGLContextObj share)
{
    CGLPixelFormatAttribute attrs[] = {kCGLPFAAllowOfflineRenderers, kCGLPFADoubleBuffer, kCGLPFAAccelerated,
                                       kCGLPFANoRecovery, kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
                                       kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8, kCGLPFADepthSize,
                                       (CGLPixelFormatAttribute)24, kCGLPFAOpenGLProfile,
                                       (CGLPixelFormatAttribute)profile, kCGLPFASupportsAutomaticGraphicsSwitching,
                                       (CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pix = NULL;
    GLint n = 0;
    CGLError e = CGLChoosePixelFormat(attrs, &pix, &n);
    if (e || !pix) {
        printf("CGLChoosePixelFormat: %s\n", CGLErrorString(e));
        return NULL;
    }
    CGLContextObj ctx = NULL;
    e = CGLCreateContext(pix, share, &ctx);
    CGLDestroyPixelFormat(pix);
    if (e)
        printf("CGLCreateContext: %s\n", CGLErrorString(e));
    return ctx;
}

static int clear_and_read(float r, float g, float b, unsigned char want[4])
{
    GLuint fb = 0, tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &fb);
    glBindFramebuffer(GL_FRAMEBUFFER, fb);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    int complete = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    glViewport(0, 0, 4, 4);
    glClearColor(r, g, b, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    unsigned char px[4] = {0};
    glReadPixels(1, 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &fb);
    glDeleteTextures(1, &tex);
    return complete && !memcmp(px, want, 4);
}

static CGLContextObj shared;
static int thread_ok;
static void *other_thread(void *arg)
{
    CGLLockContext(shared);
    CGLSetCurrentContext(shared);
    unsigned char green[4] = {0, 255, 0, 255};
    thread_ok = clear_and_read(0, 1, 0, green) && glGetError() == GL_NO_ERROR;
    CGLUnlockContext(shared);
    return NULL;
}

int main(void)
{
    if (!check("no context current at first", CGLGetCurrentContext() == NULL))
        return 1;

    /* the legacy profile */
    CGLContextObj legacy = make(kCGLOGLPVersion_Legacy, NULL);
    if (!check("legacy context", legacy != NULL))
        return 1;
    CGLSetCurrentContext(legacy);
    check("current", CGLGetCurrentContext() == legacy);
    const char *version = (const char *)glGetString(GL_VERSION);
    int major = 0, minor = 0;
    sscanf(version ? version : "", "%d.%d", &major, &minor);
    check("legacy profile has OpenGL 2.1 or later", major * 10 + minor >= 21);
    check("legacy profile isn't core", version && !strstr(version, "Core"));
    glMatrixMode(GL_PROJECTION); /* a fixed-function call */
    glLoadIdentity();
    check("fixed function calls work", glGetError() == GL_NO_ERROR);
    unsigned char red[4] = {255, 0, 0, 255};
    check("cleared to red and read back", clear_and_read(1, 0, 0, red));

    /* the drawable: framebuffer 0, read back by a flush */
    FerryCGLSetDrawableSize(legacy, 64, 32);
    GLint size[2] = {0, 0}, has = 0;
    CGLGetParameter(legacy, kCGLCPSurfaceBackingSize, size);
    CGLGetParameter(legacy, kCGLCPHasDrawable, &has);
    check("a drawable of 64 by 32", size[0] == 64 && size[1] == 32 && has);
    GLint vp[4] = {0};
    glGetIntegerv(GL_VIEWPORT, vp);
    check("viewport set for the first drawable", vp[2] == 64 && vp[3] == 32);
    glClearColor(0, 0, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, 8, 8); /* the bottom left corner */
    glClearColor(1, 1, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
    CGLFlushDrawable(legacy);
    FerryGLFrame *f = FerryCGLCopyFrame(legacy);
    check("a flush made a frame", f && f->width == 64 && f->height == 32 && f->serial >= 1);
    if (f) {
        unsigned char *bl = f->data, *tr = f->data + (size_t)31 * f->rowBytes + 63 * 4;
        /* BGRA in memory, bottom row first */
        check("its bottom left corner is yellow", bl[0] == 0 && bl[1] == 255 && bl[2] == 255);
        check("its top right corner is blue", tr[0] == 255 && tr[1] == 0 && tr[2] == 0);
        FerryGLFrameRelease(f);
    }
    f = FerryCGLCaptureFrame(legacy, 1);
    check("a capture top row first", f && f->topDown && f->data[(size_t)31 * f->rowBytes + 1] == 255 &&
                                         f->data[(size_t)31 * f->rowBytes + 0] == 0);
    FerryGLFrameRelease(f);

    /* parameters */
    GLint one = 1, got = 0;
    CGLSetParameter(legacy, kCGLCPSwapInterval, &one);
    CGLGetParameter(legacy, kCGLCPSwapInterval, &got);
    check("swap interval 1", got == 1);
    NSDate *start = [NSDate date];
    for (int i = 0; i < 13; i++)
        CGLFlushDrawable(legacy);
    double took = -[start timeIntervalSinceNow];
    printf("13 flushes with swap interval 1 take about 0.2 s: %s\n", took > 0.15 && took < 0.6 ? "yes" : "NO");
    GLint zero = 0;
    CGLSetParameter(legacy, kCGLCPSwapInterval, &zero);
    CGLSetParameter(legacy, kCGLCPSurfaceOpacity, &zero);
    CGLGetParameter(legacy, kCGLCPSurfaceOpacity, &got);
    check("surface opacity 0", got == 0);
    GLint vs = -1;
    CGLGetVirtualScreen(legacy, &vs);
    check("virtual screen 0", vs == 0);
    check("locks nest", !CGLLockContext(legacy) && !CGLLockContext(legacy) && !CGLUnlockContext(legacy) &&
                            !CGLUnlockContext(legacy));
    check("one unlock too many", CGLUnlockContext(legacy) == kCGLBadState);
    check("still current after the lock", CGLGetCurrentContext() == legacy && glGetError() == GL_NO_ERROR);

    /* the core profiles */
    CGLContextObj core = make(kCGLOGLPVersion_3_2_Core, NULL);
    check("3.2 core context", core != NULL);
    CGLSetCurrentContext(core);
    version = (const char *)glGetString(GL_VERSION);
    major = minor = 0;
    sscanf(version ? version : "", "%d.%d", &major, &minor);
    check("core profile has OpenGL 3.2 or later", major * 10 + minor >= 32);
    GLint mask = 0;
    glGetIntegerv(GL_CONTEXT_PROFILE_MASK, &mask);
    check("core profile is core", mask & GL_CONTEXT_CORE_PROFILE_BIT);
    unsigned char blue[4] = {0, 0, 255, 255};
    check("core: cleared to blue and read back", clear_and_read(0, 0, 1, blue));
    GLuint vao = 0;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    check("vertex arrays", vao != 0 && glGetError() == GL_NO_ERROR);
    CGLContextObj gl4 = make(kCGLOGLPVersion_GL4_Core, core);
    check("4.1 core context sharing with it", gl4 != NULL);
    check("same share group", gl4 && CGLGetShareGroup(gl4) == CGLGetShareGroup(core));

    /* one context current on two threads, taking turns with the lock */
    shared = core;
    CGLLockContext(core);
    pthread_t t;
    pthread_create(&t, NULL, other_thread, NULL);
    usleep(50000);
    unsigned char white[4] = {255, 255, 255, 255};
    int main_ok = clear_and_read(1, 1, 1, white);
    CGLUnlockContext(core); /* lets the other thread have it */
    pthread_join(t, NULL);
    check("the other thread drew with it in its turn", thread_ok);
    check("this thread draws with it again", clear_and_read(1, 0, 0, red) && main_ok);

    /* found by name, as VLC and OBS look the calls up */
    void *self = dlsym(RTLD_DEFAULT, "glClear");
    check("dlsym(RTLD_DEFAULT, glClear)", self == (void *)glClear);
    void *fw = dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL", RTLD_LAZY | RTLD_LOCAL);
    check("dlopen of OpenGL.framework", fw != NULL);
    check("dlsym of glGenBuffers there", fw && dlsym(fw, "glGenBuffers") == (void *)glGenBuffers);
    check("dlsym of CGLGetCurrentContext there", fw && dlsym(fw, "CGLGetCurrentContext") == (void *)CGLGetCurrentContext);

    /* Apple's own extensions */
    CGLSetCurrentContext(legacy);
    GLuint avao = 0;
    glGenVertexArraysAPPLE(1, &avao);
    glBindVertexArrayAPPLE(avao);
    check("APPLE vertex array objects", avao && glIsVertexArrayAPPLE(avao) && glGetError() == GL_NO_ERROR);
    GLuint fence = 0;
    glGenFencesAPPLE(1, &fence);
    glSetFenceAPPLE(fence);
    check("APPLE fences", glTestFenceAPPLE(fence));

    /* renderers and errors */
    CGLRendererInfoObj ri = NULL;
    GLint nr = 0, acc = 0;
    CGLQueryRendererInfo(0xffffffff, &ri, &nr);
    CGLDescribeRenderer(ri, 0, kCGLRPAccelerated, &acc);
    CGLDestroyRendererInfo(ri);
    check("one renderer", nr == 1 && acc == 1);
    printf("CGLErrorString(kCGLBadContext): %s\n", CGLErrorString(kCGLBadContext));
    CGLPixelFormatAttribute fs[] = {kCGLPFAFullScreen, (CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pix = NULL;
    GLint n = 0;
    check("full screen refused", CGLChoosePixelFormat(fs, &pix, &n) == kCGLBadAttribute && !pix);

    CGLSetCurrentContext(NULL);
    check("none current at the end", CGLGetCurrentContext() == NULL);
    CGLDestroyContext(gl4);
    CGLDestroyContext(core);
    CGLDestroyContext(legacy);
    return 0;
}
