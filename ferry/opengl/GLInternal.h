/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's OpenGL framework, inside (freemac 1.235, Ferry 0.59.0): the EGL
 * and OpenGL calls it makes itself, looked up by name through
 * ferry_gl_symbol() (src/host.c), and what CGL.m and GLForward.m share.
 * The EGL and OpenGL names and values here are the Khronos registry's. */
#ifndef FERRY_OPENGL_GLINTERNAL_H
#define FERRY_OPENGL_GLINTERNAL_H
#include <OpenGL/OpenGL.h>
#include <pthread.h>
#include "FerryGL.h"

void *ferry_gl_symbol(const char *name);

/* ---- EGL ----------------------------------------------------------------------- */
typedef void *EGLDisplay, *EGLConfig, *EGLContext, *EGLSurface, *EGLDeviceEXT;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean, EGLenum;
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_DEFAULT_DISPLAY ((void *)0)
#define EGL_NONE 0x3038
#define EGL_SUCCESS 0x3000
#define EGL_SURFACE_TYPE 0x3033
#define EGL_PBUFFER_BIT 0x0001
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_BIT 0x0008
#define EGL_RED_SIZE 0x3024
#define EGL_GREEN_SIZE 0x3023
#define EGL_BLUE_SIZE 0x3022
#define EGL_ALPHA_SIZE 0x3021
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_SAMPLE_BUFFERS 0x3032
#define EGL_SAMPLES 0x3031
#define EGL_COLOR_BUFFER_TYPE 0x303F
#define EGL_RGB_BUFFER 0x308E
#define EGL_CONFIG_CAVEAT 0x3027
#define EGL_SLOW_CONFIG 0x3050
#define EGL_OPENGL_API 0x30A2
#define EGL_WIDTH 0x3057
#define EGL_HEIGHT 0x3056
#define EGL_VENDOR 0x3053
#define EGL_VERSION 0x3054
#define EGL_EXTENSIONS 0x3055
#define EGL_CONTEXT_MAJOR_VERSION 0x3098
#define EGL_CONTEXT_MINOR_VERSION 0x30FB
#define EGL_CONTEXT_OPENGL_PROFILE_MASK 0x30FD
#define EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT 0x0001
#define EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT 0x0002
#define EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE 0x31B1
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#define EGL_PLATFORM_DEVICE_EXT 0x313F

struct FerryEGL {
    EGLDisplay (*GetPlatformDisplay)(EGLenum, void *, const intptr_t *);
    EGLDisplay (*GetPlatformDisplayEXT)(EGLenum, void *, const EGLint *);
    EGLDisplay (*GetDisplay)(void *);
    EGLBoolean (*QueryDevicesEXT)(EGLint, EGLDeviceEXT *, EGLint *);
    EGLBoolean (*Initialize)(EGLDisplay, EGLint *, EGLint *);
    EGLBoolean (*BindAPI)(EGLenum);
    EGLBoolean (*GetConfigs)(EGLDisplay, EGLConfig *, EGLint, EGLint *);
    EGLBoolean (*ChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
    EGLBoolean (*GetConfigAttrib)(EGLDisplay, EGLConfig, EGLint, EGLint *);
    EGLContext (*CreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
    EGLBoolean (*DestroyContext)(EGLDisplay, EGLContext);
    EGLSurface (*CreatePbufferSurface)(EGLDisplay, EGLConfig, const EGLint *);
    EGLBoolean (*DestroySurface)(EGLDisplay, EGLSurface);
    EGLBoolean (*MakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
    EGLContext (*GetCurrentContext)(void);
    EGLint (*GetError)(void);
    const char *(*QueryString)(EGLDisplay, EGLint);
};
extern struct FerryEGL ferry_egl;
extern EGLDisplay ferry_egl_display;

/* ---- the OpenGL calls Ferry makes itself ------------------------------------------ */
#define FGL_BACK 0x0405
#define FGL_READ_BUFFER 0x0C02
#define FGL_VIEWPORT 0x0BA2
#define FGL_PACK_ROW_LENGTH 0x0D02
#define FGL_PACK_SKIP_ROWS 0x0D03
#define FGL_PACK_SKIP_PIXELS 0x0D04
#define FGL_PACK_ALIGNMENT 0x0D05
#define FGL_UNPACK_ROW_LENGTH 0x0CF2
#define FGL_UNPACK_SKIP_ROWS 0x0CF3
#define FGL_UNPACK_SKIP_PIXELS 0x0CF4
#define FGL_UNPACK_ALIGNMENT 0x0CF5
#define FGL_UNPACK_IMAGE_HEIGHT 0x806E
#define FGL_UNPACK_SKIP_IMAGES 0x806D
#define FGL_PIXEL_PACK_BUFFER 0x88EB
#define FGL_PIXEL_UNPACK_BUFFER 0x88EC
#define FGL_PIXEL_PACK_BUFFER_BINDING 0x88ED
#define FGL_PIXEL_UNPACK_BUFFER_BINDING 0x88EF
#define FGL_READ_FRAMEBUFFER 0x8CA8
#define FGL_READ_FRAMEBUFFER_BINDING 0x8CAA
#define FGL_BGRA 0x80E1
#define FGL_RGB 0x1907
#define FGL_RGBA 0x1908
#define FGL_UNSIGNED_BYTE 0x1401
#define FGL_UNSIGNED_INT_8_8_8_8_REV 0x8367
#define FGL_VERSION 0x1F02
#define FGL_RENDERER 0x1F01
#define FGL_VENDOR 0x1F00
#define FGL_RGB_422_APPLE 0x8A1F
#define FGL_UNSIGNED_SHORT_8_8_APPLE 0x85BA
#define FGL_UNSIGNED_SHORT_8_8_REV_APPLE 0x85BB

struct FerryGLCalls {
    void (*GetIntegerv)(GLenum, GLint *);
    void (*ReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
    void (*PixelStorei)(GLenum, GLint);
    void (*BindFramebuffer)(GLenum, GLuint);
    void (*BindBuffer)(GLenum, GLuint);
    void (*ReadBuffer)(GLenum);
    void (*Flush)(void);
    void (*Finish)(void);
    void (*Viewport)(GLint, GLint, GLsizei, GLsizei);
    void (*TexImage2D)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *);
    GLenum (*GetError)(void);
    const GLubyte *(*GetString)(GLenum);
};
extern struct FerryGLCalls ferry_gl;

/* Opens EGL and the display once; 0 if this system has no OpenGL. */
int FerryGLOpen(void);

/* Called by every OpenGL call while some thread's current context isn't
 * bound to it (GLForward.m): binds this thread's, as CGL lets one context
 * be current on several threads and EGL doesn't. */
void FerryGLBindCurrent(void);
extern volatile int ferry_gl_pending;

/* ---- the objects ------------------------------------------------------------------ */
struct _CGLPixelFormatObject {
    int refs;
    EGLConfig config;
    int doubleBuffer, colorSize, alphaSize, depthSize, stencilSize, accumSize, samples, sampleBuffers, auxBuffers;
    int profile, offScreen, pbuffer, window, accelerated, colorFloat, stereo, backingStore;
    int displayMask;
};

struct _CGLShareGroupObject {
    int refs;
};

struct _CGLPBufferObject {
    int refs;
    GLsizei width, height;
    GLenum target, internalFormat;
    GLint maxLevel;
};

struct _CGLContextObject {
    int refs;
    CGLPixelFormatObj pixelFormat;
    struct _CGLShareGroupObject *shareGroup;
    EGLContext egl;
    EGLConfig config;
    int core;

    /* the CGL lock (recursive) and how deep the owner holds it */
    pthread_mutex_t cglLock;
    int lockDepth;

    /* the binding and drawable, under state */
    pthread_mutex_t state;
    pthread_cond_t unbound;
    int bound;              /* bound to boundThread with EGL */
    pthread_t boundThread;
    EGLSurface surface;
    int width, height;          /* the surface's */
    int wantWidth, wantHeight;  /* asked for */
    int viewportSet;            /* the viewport was set for the first drawable */

    /* parameters */
    GLint swapInterval, opacity, surfaceOrder, backingSize[2], swapRect[4];
    int backingSizeEnabled, swapRectEnabled, rasterization, mpEngine, virtualScreen;
    CGLPBufferObj pbuffer;
    GLsizei offWidth, offHeight;
    GLint offRowBytes;
    void *offBase;

    /* frames */
    pthread_mutex_t frames;
    FerryGLFrame *latest, *spare;
    uint64_t serial;
    FerryCGLFlushCallback callback;
    void *callbackInfo;
    uint64_t lastFlush; /* ns, for the swap interval */
};

#endif
