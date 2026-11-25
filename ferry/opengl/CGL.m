/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's OpenGL framework: Core OpenGL (CGL), written from Apple's public
 * CGL reference (freemac 1.235, Ferry 0.59.0).
 *
 * A pixel format is an EGL configuration of this system's OpenGL (Mesa
 * through EGL's surfaceless platform, so no window system is needed), and
 * a context is an EGL context: compatibility for the legacy profile, core
 * (and forward-compatible, as on a Mac) for the 3.2 and 4.1 core profiles.
 * A context's drawable is an EGL pbuffer of the size its view or layer
 * asks for; each CGLFlushDrawable reads it back as a frame, which Ferry's
 * AppKit and Core Animation show (FerryGL.h). That copy is the price of
 * drawing with any OpenGL into GTK's windows: about 2 ms for 1920 by 1080
 * on Mesa's software renderer.
 *
 * CGL lets a program make one context current on several threads, and
 * lock it to take turns; EGL binds a context to one thread at a time. So
 * the context each thread calls current is kept apart from the one EGL has
 * bound there: making a context current binds it, waiting (up to 2
 * seconds) for another thread to let it go, and unlocking it last lets it
 * go. A thread whose current context isn't bound to it gets it back at its
 * next OpenGL call (GLForward.m). Built without ARC. */
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "GLInternal.h"

struct FerryEGL ferry_egl;
struct FerryGLCalls ferry_gl;
EGLDisplay ferry_egl_display;
volatile int ferry_gl_pending;

static double refresh_hz; /* 0: not yet read from the environment */
void FerryGLSetRefreshRate(double hz)
{
    if (hz >= 10 && hz <= 500)
        refresh_hz = hz;
}
double FerryGLRefreshRate(void)
{
    if (refresh_hz <= 0) {
        const char *e = getenv("FERRY_REFRESH_RATE");
        double hz = e ? atof(e) : 0;
        refresh_hz = hz >= 10 && hz <= 500 ? hz : 60;
    }
    return refresh_hz;
}

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + (uint64_t)t.tv_nsec;
}

/* ---- opening EGL ------------------------------------------------------------------ */

static int gl_ok;
static void open_once(void)
{
#define E(field, name) *(void **)&ferry_egl.field = ferry_gl_symbol("egl" #name)
    E(GetPlatformDisplay, GetPlatformDisplay);
    E(GetPlatformDisplayEXT, GetPlatformDisplayEXT);
    E(GetDisplay, GetDisplay);
    E(QueryDevicesEXT, QueryDevicesEXT);
    E(Initialize, Initialize);
    E(BindAPI, BindAPI);
    E(GetConfigs, GetConfigs);
    E(ChooseConfig, ChooseConfig);
    E(GetConfigAttrib, GetConfigAttrib);
    E(CreateContext, CreateContext);
    E(DestroyContext, DestroyContext);
    E(CreatePbufferSurface, CreatePbufferSurface);
    E(DestroySurface, DestroySurface);
    E(MakeCurrent, MakeCurrent);
    E(GetCurrentContext, GetCurrentContext);
    E(GetError, GetError);
    E(QueryString, QueryString);
#undef E
#define G(field, name) *(void **)&ferry_gl.field = ferry_gl_symbol("gl" #name)
    G(GetIntegerv, GetIntegerv);
    G(ReadPixels, ReadPixels);
    G(PixelStorei, PixelStorei);
    G(BindFramebuffer, BindFramebuffer);
    G(BindBuffer, BindBuffer);
    G(ReadBuffer, ReadBuffer);
    G(Flush, Flush);
    G(Finish, Finish);
    G(Viewport, Viewport);
    G(TexImage2D, TexImage2D);
    G(GetError, GetError);
    G(GetString, GetString);
#undef G
    if (!ferry_egl.Initialize || !ferry_egl.CreateContext || !ferry_egl.MakeCurrent || !ferry_egl.BindAPI ||
        !ferry_egl.CreatePbufferSurface || !ferry_egl.GetConfigs || !ferry_gl.ReadPixels || !ferry_gl.GetIntegerv)
        return;
    EGLDisplay d = EGL_NO_DISPLAY;
    EGLint major = 0, minor = 0;
    /* the surfaceless platform needs no window system; then the first
     * device; then whatever the default display is */
    if (ferry_egl.GetPlatformDisplay)
        d = ferry_egl.GetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    else if (ferry_egl.GetPlatformDisplayEXT)
        d = ferry_egl.GetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    if (d && !ferry_egl.Initialize(d, &major, &minor))
        d = EGL_NO_DISPLAY;
    if (!d && ferry_egl.QueryDevicesEXT && (ferry_egl.GetPlatformDisplay || ferry_egl.GetPlatformDisplayEXT)) {
        EGLDeviceEXT dev[4];
        EGLint n = 0;
        if (ferry_egl.QueryDevicesEXT(4, dev, &n) && n > 0) {
            d = ferry_egl.GetPlatformDisplay ? ferry_egl.GetPlatformDisplay(EGL_PLATFORM_DEVICE_EXT, dev[0], NULL)
                                             : ferry_egl.GetPlatformDisplayEXT(EGL_PLATFORM_DEVICE_EXT, dev[0], NULL);
            if (d && !ferry_egl.Initialize(d, &major, &minor))
                d = EGL_NO_DISPLAY;
        }
    }
    if (!d && ferry_egl.GetDisplay) {
        d = ferry_egl.GetDisplay(EGL_DEFAULT_DISPLAY);
        if (d && !ferry_egl.Initialize(d, &major, &minor))
            d = EGL_NO_DISPLAY;
    }
    if (!d)
        return;
    ferry_egl_display = d;
    gl_ok = 1;
    if (getenv("FERRY_GL_DEBUG")) {
        fprintf(stderr, "ferry: OpenGL through EGL %d.%d (%s)\n", major, minor,
                ferry_egl.QueryString ? ferry_egl.QueryString(d, EGL_VENDOR) : "?");
    }
}

int FerryGLOpen(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, open_once);
    return gl_ok;
}

int FerryGLAvailable(void) { return FerryGLOpen(); }

/* ---- each thread's current context and binding ------------------------------------ */

struct tstate {
    CGLContextObj current; /* what CGL calls current here (retained) */
    CGLContextObj bound;   /* what EGL has bound here (retained) */
    int needs;             /* counted in ferry_gl_pending */
    int api;               /* eglBindAPI done */
};

static pthread_key_t tkey;
static void unbind_here(struct tstate *ts);
static void recount(struct tstate *ts);

static void tstate_end(void *p)
{
    struct tstate *ts = p;
    pthread_setspecific(tkey, ts);
    unbind_here(ts);
    if (ts->current) {
        CGLContextObj c = ts->current;
        ts->current = NULL;
        CGLReleaseContext(c);
    }
    recount(ts);
    pthread_setspecific(tkey, NULL);
    free(ts);
}
static int tkey_made;
static void make_key(void)
{
    pthread_key_create(&tkey, tstate_end);
    __atomic_store_n(&tkey_made, 1, __ATOMIC_RELEASE);
}

/* this thread's state if it has any, without making it */
static struct tstate *tstate_peek(void)
{
    return __atomic_load_n(&tkey_made, __ATOMIC_ACQUIRE) ? pthread_getspecific(tkey) : NULL;
}

static struct tstate *tstate(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, make_key);
    struct tstate *ts = pthread_getspecific(tkey);
    if (!ts) {
        ts = calloc(1, sizeof *ts);
        if (!ts)
            abort();
        pthread_setspecific(tkey, ts);
    }
    if (!ts->api && gl_ok) {
        ferry_egl.BindAPI(EGL_OPENGL_API);
        ts->api = 1;
    }
    return ts;
}

static void recount(struct tstate *ts)
{
    int needs = ts->current && ts->current != ts->bound;
    if (needs != ts->needs) {
        ts->needs = needs;
        __atomic_add_fetch(&ferry_gl_pending, needs ? 1 : -1, __ATOMIC_SEQ_CST);
    }
}

static int same_thread(CGLContextObj c) { return c->bound && pthread_equal(c->boundThread, pthread_self()); }

/* Called with c->state held, c bound here or nowhere: makes the surface
 * the size asked for. */
static void apply_size_locked(CGLContextObj c)
{
    if (c->wantWidth == c->width && c->wantHeight == c->height && (c->surface || !c->width))
        return;
    EGLSurface old = c->surface, s = EGL_NO_SURFACE;
    if (c->wantWidth > 0 && c->wantHeight > 0) {
        EGLint attrs[] = {EGL_WIDTH, c->wantWidth, EGL_HEIGHT, c->wantHeight, EGL_NONE};
        s = ferry_egl.CreatePbufferSurface(ferry_egl_display, c->config, attrs);
        if (!s) {
            fprintf(stderr, "ferry: OpenGL couldn't make a %d by %d drawable (EGL error 0x%x)\n", c->wantWidth,
                    c->wantHeight, ferry_egl.GetError ? ferry_egl.GetError() : 0);
            c->wantWidth = c->width;
            c->wantHeight = c->height;
            return;
        }
    }
    if (c->bound)
        ferry_egl.MakeCurrent(ferry_egl_display, s, s, c->egl);
    if (old)
        ferry_egl.DestroySurface(ferry_egl_display, old);
    c->surface = s;
    c->width = s ? c->wantWidth : 0;
    c->height = s ? c->wantHeight : 0;
    if (s && c->bound && !c->viewportSet) {
        /* as a Mac sets the viewport when a context first has a drawable */
        ferry_gl.Viewport(0, 0, c->width, c->height);
        c->viewportSet = 1;
    }
}

static void unbind_here(struct tstate *ts)
{
    CGLContextObj c = ts->bound;
    if (!c)
        return;
    pthread_mutex_lock(&c->state);
    ferry_egl.MakeCurrent(ferry_egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    c->bound = 0;
    apply_size_locked(c);
    pthread_cond_broadcast(&c->unbound);
    pthread_mutex_unlock(&c->state);
    ts->bound = NULL;
    CGLReleaseContext(c);
}

/* Binds c to this thread with EGL, waiting for another thread to let it go. */
static int bind_here(struct tstate *ts, CGLContextObj c)
{
    if (ts->bound == c)
        return 1;
    unbind_here(ts);
    pthread_mutex_lock(&c->state);
    if (c->bound) {
        struct timespec until;
        clock_gettime(CLOCK_REALTIME, &until);
        until.tv_sec += 2;
        while (c->bound)
            if (pthread_cond_timedwait(&c->unbound, &c->state, &until) == ETIMEDOUT)
                break;
        if (c->bound) {
            pthread_mutex_unlock(&c->state);
            static int warned;
            if (!warned++)
                fprintf(stderr, "ferry: an OpenGL context is current on another thread that hasn't let it go "
                                "(without CGLLockContext around its drawing); this thread's calls are dropped\n");
            return 0;
        }
    }
    apply_size_locked(c);
    if (!ferry_egl.MakeCurrent(ferry_egl_display, c->surface, c->surface, c->egl)) {
        pthread_mutex_unlock(&c->state);
        fprintf(stderr, "ferry: OpenGL couldn't make a context current (EGL error 0x%x)\n",
                ferry_egl.GetError ? ferry_egl.GetError() : 0);
        return 0;
    }
    c->bound = 1;
    c->boundThread = pthread_self();
    if (c->surface && !c->viewportSet) {
        ferry_gl.Viewport(0, 0, c->width, c->height);
        c->viewportSet = 1;
    }
    pthread_mutex_unlock(&c->state);
    ts->bound = CGLRetainContext(c);
    return 1;
}

void FerryGLBindCurrent(void)
{
    struct tstate *ts = tstate();
    if (ts->current && ts->current != ts->bound) {
        bind_here(ts, ts->current);
        recount(ts);
    }
}

CGLError CGLSetCurrentContext(CGLContextObj c)
{
    if (c && !gl_ok)
        return kCGLBadContext;
    struct tstate *ts = tstate();
    if (c != ts->current) {
        CGLContextObj old = ts->current;
        ts->current = c ? CGLRetainContext(c) : NULL;
        if (old)
            CGLReleaseContext(old);
    }
    if (!c)
        unbind_here(ts);
    else
        bind_here(ts, c);
    recount(ts);
    return kCGLNoError;
}

CGLContextObj CGLGetCurrentContext(void)
{
    struct tstate *ts = tstate_peek();
    return ts ? ts->current : NULL;
}

/* ---- pixel formats ----------------------------------------------------------------- */

static int attr_has_value(CGLPixelFormatAttribute a)
{
    switch ((int)a) {
    case kCGLPFAAuxBuffers:
    case kCGLPFAColorSize:
    case kCGLPFAAlphaSize:
    case kCGLPFADepthSize:
    case kCGLPFAStencilSize:
    case kCGLPFAAccumSize:
    case kCGLPFASampleBuffers:
    case kCGLPFASamples:
    case kCGLPFARendererID:
    case kCGLPFADisplayMask:
    case kCGLPFAOpenGLProfile:
    case kCGLPFAVirtualScreenCount:
        return 1;
    default:
        return 0;
    }
}

static EGLint cfg(EGLConfig c, EGLint a)
{
    EGLint v = 0;
    ferry_egl.GetConfigAttrib(ferry_egl_display, c, a, &v);
    return v;
}

/* The config closest to what was asked: 8-bit color, and at least the
 * alpha, depth, stencil and samples asked for, with as little more as
 * there is. */
static EGLConfig choose_config(CGLPixelFormatObj p)
{
    EGLint n = 0;
    if (!ferry_egl.GetConfigs(ferry_egl_display, NULL, 0, &n) || n <= 0)
        return NULL;
    EGLConfig *all = calloc((size_t)n, sizeof *all);
    if (!all)
        return NULL;
    ferry_egl.GetConfigs(ferry_egl_display, all, n, &n);
    int color = p->colorSize > 24 ? 8 : p->colorSize > 16 || !p->colorSize ? 8 : 5;
    EGLConfig best = NULL;
    long best_cost = 0;
    for (EGLint i = 0; i < n; i++) {
        EGLConfig c = all[i];
        if (!(cfg(c, EGL_SURFACE_TYPE) & EGL_PBUFFER_BIT) || !(cfg(c, EGL_RENDERABLE_TYPE) & EGL_OPENGL_BIT))
            continue;
        if (cfg(c, EGL_COLOR_BUFFER_TYPE) != EGL_RGB_BUFFER)
            continue;
        EGLint r = cfg(c, EGL_RED_SIZE), g = cfg(c, EGL_GREEN_SIZE), b = cfg(c, EGL_BLUE_SIZE);
        EGLint a = cfg(c, EGL_ALPHA_SIZE), d = cfg(c, EGL_DEPTH_SIZE), s = cfg(c, EGL_STENCIL_SIZE);
        EGLint samples = cfg(c, EGL_SAMPLES);
        if (r < color || g < color || b < color || a < p->alphaSize || d < p->depthSize || s < p->stencilSize)
            continue;
        int want_samples = p->samples > 0 && (p->sampleBuffers > 0 || p->samples > 1) ? p->samples : 0;
        if (samples < want_samples)
            continue;
        long cost = (long)(r - 8) * 1000 + (g - 8) * 1000 + (b - 8) * 1000 + (a - p->alphaSize) * 10 +
                    (d - p->depthSize) + (s - p->stencilSize) + (samples - want_samples) * 100;
        if (cfg(c, EGL_CONFIG_CAVEAT) == EGL_SLOW_CONFIG)
            cost += 100000;
        if (!best || cost < best_cost) {
            best = c;
            best_cost = cost;
        }
    }
    free(all);
    return best;
}

CGLError CGLChoosePixelFormat(const CGLPixelFormatAttribute *attribs, CGLPixelFormatObj *pix, GLint *npix)
{
    if (!pix)
        return kCGLBadAddress;
    *pix = NULL;
    if (npix)
        *npix = 0;
    struct _CGLPixelFormatObject f = {.refs = 1, .profile = kCGLOGLPVersion_Legacy, .colorSize = 24};
    for (const CGLPixelFormatAttribute *a = attribs; a && *a; a++) {
        GLint v = attr_has_value(*a) ? (GLint)a[1] : 1;
        switch ((int)*a) {
        case kCGLPFADoubleBuffer: f.doubleBuffer = 1; break;
        case kCGLPFATripleBuffer: f.doubleBuffer = 1; break;
        case kCGLPFAStereo: f.stereo = 1; break;
        case kCGLPFAAuxBuffers: f.auxBuffers = v; break;
        case kCGLPFAColorSize: f.colorSize = v; break;
        case kCGLPFAAlphaSize: f.alphaSize = v; break;
        case kCGLPFADepthSize: f.depthSize = v; break;
        case kCGLPFAStencilSize: f.stencilSize = v; break;
        case kCGLPFAAccumSize: f.accumSize = v; break;
        case kCGLPFASampleBuffers: f.sampleBuffers = v; break;
        case kCGLPFASamples: f.samples = v; break;
        case kCGLPFADisplayMask: f.displayMask = v; break;
        case kCGLPFAOpenGLProfile: f.profile = v; break;
        case kCGLPFAOffScreen: f.offScreen = 1; break;
        case kCGLPFAPBuffer: f.pbuffer = 1; break;
        case kCGLPFAWindow: f.window = 1; break;
        case kCGLPFAAccelerated: f.accelerated = 1; break;
        case kCGLPFAColorFloat: f.colorFloat = 1; break;
        case kCGLPFABackingStore: f.backingStore = 1; break;
        case kCGLPFAFullScreen:
            return kCGLBadAttribute;
        default: break; /* the policies, renderer choices and the like change nothing here */
        }
        if (attr_has_value(*a))
            a++;
    }
    if (f.profile != kCGLOGLPVersion_Legacy && f.profile != kCGLOGLPVersion_3_2_Core &&
        f.profile != kCGLOGLPVersion_GL4_Core)
        return kCGLBadValue;
    if (!FerryGLOpen()) {
        static int warned;
        if (!warned++)
            fprintf(stderr, "ferry: this program draws with OpenGL, and this system's OpenGL (libEGL.so.1, "
                            "Mesa) %s\n",
                    ferry_gl_symbol("eglGetProcAddress") ? "has no display Ferry can use" : "isn't installed");
        return kCGLBadDisplay;
    }
    f.config = choose_config(&f);
    if (!f.config)
        return kCGLNoError; /* nothing matches: no pixel format, as on a Mac */
    CGLPixelFormatObj p = malloc(sizeof *p);
    if (!p)
        return kCGLBadAlloc;
    *p = f;
    *pix = p;
    if (npix)
        *npix = 1;
    return kCGLNoError;
}

CGLPixelFormatObj CGLRetainPixelFormat(CGLPixelFormatObj p)
{
    if (p)
        __atomic_add_fetch(&p->refs, 1, __ATOMIC_ACQ_REL);
    return p;
}
void CGLReleasePixelFormat(CGLPixelFormatObj p)
{
    if (p && !__atomic_sub_fetch(&p->refs, 1, __ATOMIC_ACQ_REL))
        free(p);
}
CGLError CGLDestroyPixelFormat(CGLPixelFormatObj p)
{
    CGLReleasePixelFormat(p);
    return kCGLNoError;
}
GLuint CGLGetPixelFormatRetainCount(CGLPixelFormatObj p) { return p ? (GLuint)p->refs : 0; }

CGLError CGLDescribePixelFormat(CGLPixelFormatObj p, GLint pix_num, CGLPixelFormatAttribute attrib, GLint *value)
{
    if (!p)
        return kCGLBadPixelFormat;
    if (!value)
        return kCGLBadAddress;
    if (pix_num != 0)
        return kCGLBadValue;
    EGLConfig c = p->config;
    switch ((int)attrib) {
    case kCGLPFADoubleBuffer: *value = p->doubleBuffer; break;
    case kCGLPFATripleBuffer: *value = 0; break;
    case kCGLPFAStereo: *value = 0; break;
    case kCGLPFAAuxBuffers: *value = 0; break;
    case kCGLPFAColorSize: *value = cfg(c, EGL_RED_SIZE) + cfg(c, EGL_GREEN_SIZE) + cfg(c, EGL_BLUE_SIZE); break;
    case kCGLPFAAlphaSize: *value = cfg(c, EGL_ALPHA_SIZE); break;
    case kCGLPFADepthSize: *value = cfg(c, EGL_DEPTH_SIZE); break;
    case kCGLPFAStencilSize: *value = cfg(c, EGL_STENCIL_SIZE); break;
    case kCGLPFAAccumSize: *value = 0; break;
    case kCGLPFASampleBuffers: *value = cfg(c, EGL_SAMPLE_BUFFERS); break;
    case kCGLPFASamples: *value = cfg(c, EGL_SAMPLES); break;
    case kCGLPFAOpenGLProfile: *value = p->profile; break;
    case kCGLPFARendererID: *value = kCGLRendererGenericFloatID; break;
    case kCGLPFAAccelerated: *value = 1; break;
    case kCGLPFANoRecovery: *value = 1; break;
    case kCGLPFAWindow: *value = 1; break;
    case kCGLPFAOffScreen: *value = p->offScreen; break;
    case kCGLPFAPBuffer: *value = 1; break;
    case kCGLPFADisplayMask: *value = 1; break;
    case kCGLPFAVirtualScreenCount: *value = 1; break;
    case kCGLPFAColorFloat: *value = 0; break;
    case kCGLPFABackingStore: *value = p->backingStore; break;
    case kCGLPFAMPSafe: *value = 1; break;
    case kCGLPFAMultiScreen: *value = 1; break;
    case kCGLPFACompliant: *value = 1; break;
    case kCGLPFAAllowOfflineRenderers: *value = 1; break;
    case kCGLPFASupportsAutomaticGraphicsSwitching: *value = 1; break;
    case kCGLPFAAcceleratedCompute: *value = 0; break;
    default: *value = 0; break;
    }
    return kCGLNoError;
}

/* ---- renderers: the one this system's OpenGL is ----------------------------------- */

struct _CGLRendererInfoObject {
    int count;
};

CGLError CGLQueryRendererInfo(GLuint display_mask, CGLRendererInfoObj *rend, GLint *nrend)
{
    if (!rend || !nrend)
        return kCGLBadAddress;
    *rend = NULL;
    *nrend = 0;
    if (!FerryGLOpen())
        return kCGLBadDisplay;
    *rend = calloc(1, sizeof **rend);
    if (!*rend)
        return kCGLBadAlloc;
    (*rend)->count = 1;
    *nrend = 1;
    return kCGLNoError;
}
CGLError CGLDestroyRendererInfo(CGLRendererInfoObj rend)
{
    free(rend);
    return kCGLNoError;
}
CGLError CGLDescribeRenderer(CGLRendererInfoObj rend, GLint rend_num, CGLRendererProperty prop, GLint *value)
{
    if (!rend)
        return kCGLBadRendererInfo;
    if (!value)
        return kCGLBadAddress;
    if (rend_num != 0 && prop != kCGLRPRendererCount)
        return kCGLBadValue;
    switch ((int)prop) {
    case kCGLRPRendererCount: *value = 1; break;
    case kCGLRPRendererID: *value = kCGLRendererGenericFloatID; break;
    case kCGLRPDisplayMask: *value = 1; break;
    case kCGLRPOnline: *value = 1; break;
    case kCGLRPAccelerated: *value = 1; break;
    case kCGLRPWindow: *value = 1; break;
    case kCGLRPOffScreen: *value = 1; break;
    case kCGLRPMPSafe: *value = 1; break;
    case kCGLRPCompliant: *value = 1; break;
    case kCGLRPMultiScreen: *value = 1; break;
    case kCGLRPBackingStore: *value = 1; break;
    case kCGLRPFullScreen: *value = 0; break;
    case kCGLRPMaxSampleBuffers: *value = 1; break;
    case kCGLRPMaxSamples: *value = 8; break;
    case kCGLRPVideoMemory: *value = 1024 * 1024 * 1024; break;
    case kCGLRPTextureMemory: *value = 1024 * 1024 * 1024; break;
    case kCGLRPVideoMemoryMegabytes: *value = 1024; break;
    case kCGLRPTextureMemoryMegabytes: *value = 1024; break;
    case kCGLRPGPUVertProcCapable: *value = 1; break;
    case kCGLRPGPUFragProcCapable: *value = 1; break;
    case kCGLRPMajorGLVersion: *value = 4; break;
    case kCGLRPAcceleratedCompute: *value = 0; break;
    default: *value = 0; break;
    }
    return kCGLNoError;
}

/* ---- contexts ----------------------------------------------------------------------- */

CGLError CGLCreateContext(CGLPixelFormatObj pix, CGLContextObj share, CGLContextObj *out)
{
    if (!out)
        return kCGLBadAddress;
    *out = NULL;
    if (!pix)
        return kCGLBadPixelFormat;
    if (!FerryGLOpen())
        return kCGLBadDisplay;
    tstate(); /* binds the OpenGL API on this thread */
    int core = pix->profile != kCGLOGLPVersion_Legacy;
    EGLint attrs[16], n = 0;
    if (core) {
        int major = pix->profile == kCGLOGLPVersion_GL4_Core ? 4 : 3;
        int minor = pix->profile == kCGLOGLPVersion_GL4_Core ? 1 : 2;
        attrs[n++] = EGL_CONTEXT_MAJOR_VERSION;
        attrs[n++] = major;
        attrs[n++] = EGL_CONTEXT_MINOR_VERSION;
        attrs[n++] = minor;
        attrs[n++] = EGL_CONTEXT_OPENGL_PROFILE_MASK;
        attrs[n++] = EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT;
        attrs[n++] = EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE;
        attrs[n++] = 1;
    } else {
        attrs[n++] = EGL_CONTEXT_OPENGL_PROFILE_MASK;
        attrs[n++] = EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT;
    }
    attrs[n] = EGL_NONE;
    EGLContext e = ferry_egl.CreateContext(ferry_egl_display, pix->config, share ? share->egl : EGL_NO_CONTEXT, attrs);
    if (!e) {
        fprintf(stderr, "ferry: this system's OpenGL couldn't make a%s context (EGL error 0x%x)\n",
                core ? " core profile" : "", ferry_egl.GetError ? ferry_egl.GetError() : 0);
        return kCGLBadMatch;
    }
    CGLContextObj c = calloc(1, sizeof *c);
    if (!c) {
        ferry_egl.DestroyContext(ferry_egl_display, e);
        return kCGLBadAlloc;
    }
    c->refs = 1;
    c->pixelFormat = CGLRetainPixelFormat(pix);
    c->egl = e;
    c->config = pix->config;
    c->core = core;
    if (share && share->shareGroup) {
        c->shareGroup = share->shareGroup;
        __atomic_add_fetch(&c->shareGroup->refs, 1, __ATOMIC_ACQ_REL);
    } else {
        c->shareGroup = calloc(1, sizeof *c->shareGroup);
        if (c->shareGroup)
            c->shareGroup->refs = 1;
    }
    pthread_mutexattr_t ma;
    pthread_mutexattr_init(&ma);
    pthread_mutexattr_settype(&ma, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&c->cglLock, &ma);
    pthread_mutexattr_destroy(&ma);
    pthread_mutex_init(&c->state, NULL);
    pthread_mutex_init(&c->frames, NULL);
    pthread_cond_init(&c->unbound, NULL);
    c->opacity = 1;
    c->surfaceOrder = 1;
    c->rasterization = 1;
    *out = c;
    return kCGLNoError;
}

CGLContextObj CGLRetainContext(CGLContextObj c)
{
    if (c)
        __atomic_add_fetch(&c->refs, 1, __ATOMIC_ACQ_REL);
    return c;
}

void CGLReleaseContext(CGLContextObj c)
{
    if (!c || __atomic_sub_fetch(&c->refs, 1, __ATOMIC_ACQ_REL))
        return;
    /* nothing has it bound or current now: those hold references */
    if (c->surface)
        ferry_egl.DestroySurface(ferry_egl_display, c->surface);
    ferry_egl.DestroyContext(ferry_egl_display, c->egl);
    if (c->shareGroup && !__atomic_sub_fetch(&c->shareGroup->refs, 1, __ATOMIC_ACQ_REL))
        free(c->shareGroup);
    CGLReleasePixelFormat(c->pixelFormat);
    if (c->pbuffer)
        CGLReleasePBuffer(c->pbuffer);
    FerryGLFrameRelease(c->latest);
    FerryGLFrameRelease(c->spare);
    pthread_mutex_destroy(&c->cglLock);
    pthread_mutex_destroy(&c->state);
    pthread_mutex_destroy(&c->frames);
    pthread_cond_destroy(&c->unbound);
    free(c);
}

CGLError CGLDestroyContext(CGLContextObj c)
{
    if (!c)
        return kCGLBadContext;
    struct tstate *ts = tstate_peek();
    if (ts && ts->current == c)
        CGLSetCurrentContext(NULL);
    CGLReleaseContext(c);
    return kCGLNoError;
}

GLuint CGLGetContextRetainCount(CGLContextObj c) { return c ? (GLuint)c->refs : 0; }
CGLPixelFormatObj CGLGetPixelFormat(CGLContextObj c) { return c ? c->pixelFormat : NULL; }
CGLShareGroupObj CGLGetShareGroup(CGLContextObj c) { return c ? c->shareGroup : NULL; }
void *CGLGetDeviceFromGLRenderer(GLint rendererID) { return NULL; }

CGLError CGLCopyContext(CGLContextObj src, CGLContextObj dst, GLbitfield mask)
{
    /* EGL has no copy of state between contexts; the program sets its own */
    return src && dst ? kCGLNoError : kCGLBadContext;
}

CGLError CGLLockContext(CGLContextObj c)
{
    if (!c)
        return kCGLBadContext;
    pthread_mutex_lock(&c->cglLock);
    c->lockDepth++;
    return kCGLNoError;
}

CGLError CGLUnlockContext(CGLContextObj c)
{
    if (!c)
        return kCGLBadContext;
    if (c->lockDepth <= 0)
        return kCGLBadState;
    if (--c->lockDepth == 0) {
        /* let the context go, so another thread taking the lock can bind it;
         * this thread binds it again at its next call if it is still current */
        struct tstate *ts = tstate_peek();
        if (ts && ts->bound == c) {
            unbind_here(ts);
            recount(ts);
        }
    }
    pthread_mutex_unlock(&c->cglLock);
    return kCGLNoError;
}

/* ---- the drawable ------------------------------------------------------------------ */

void FerryCGLSetDrawableSize(CGLContextObj c, int w, int h)
{
    if (!c)
        return;
    if (w < 0 || h < 0 || w > 16384 || h > 16384)
        w = h = 0;
    if (!w || !h)
        w = h = 0;
    pthread_mutex_lock(&c->state);
    c->wantWidth = w;
    c->wantHeight = h;
    if (!c->bound || same_thread(c))
        apply_size_locked(c);
    pthread_mutex_unlock(&c->state);
}

void FerryCGLGetDrawableSize(CGLContextObj c, int *w, int *h)
{
    pthread_mutex_lock(&c->state);
    if (w)
        *w = c->wantWidth;
    if (h)
        *h = c->wantHeight;
    pthread_mutex_unlock(&c->state);
}

void FerryCGLSetFlushCallback(CGLContextObj c, FerryCGLFlushCallback cb, void *info)
{
    if (!c)
        return;
    pthread_mutex_lock(&c->frames);
    c->callback = cb;
    c->callbackInfo = info;
    pthread_mutex_unlock(&c->frames);
}

CGLError CGLClearDrawable(CGLContextObj c)
{
    if (!c)
        return kCGLBadContext;
    FerryCGLSetDrawableSize(c, 0, 0);
    pthread_mutex_lock(&c->frames);
    FerryGLFrame *f = c->latest;
    c->latest = NULL;
    c->callback = NULL;
    c->callbackInfo = NULL;
    pthread_mutex_unlock(&c->frames);
    FerryGLFrameRelease(f);
    c->offBase = NULL;
    if (c->pbuffer) {
        CGLReleasePBuffer(c->pbuffer);
        c->pbuffer = NULL;
    }
    return kCGLNoError;
}

CGLError CGLUpdateContext(CGLContextObj c) { return c ? kCGLNoError : kCGLBadContext; }

/* ---- frames --------------------------------------------------------------------------- */

FerryGLFrame *FerryGLFrameRetain(FerryGLFrame *f)
{
    if (f)
        __atomic_add_fetch(&f->refs, 1, __ATOMIC_ACQ_REL);
    return f;
}
void FerryGLFrameRelease(FerryGLFrame *f)
{
    if (f && !__atomic_sub_fetch(&f->refs, 1, __ATOMIC_ACQ_REL)) {
        free(f->data);
        free(f);
    }
}

static FerryGLFrame *frame_for(FerryGLFrame *reuse, int w, int h)
{
    size_t rb = (size_t)w * 4, need = rb * (size_t)h;
    FerryGLFrame *f = reuse && __atomic_load_n(&reuse->refs, __ATOMIC_ACQUIRE) == 1 ? reuse : NULL;
    if (!f) {
        FerryGLFrameRelease(reuse);
        f = calloc(1, sizeof *f);
        if (!f)
            return NULL;
        f->refs = 1;
    }
    if (f->capacity < need) {
        free(f->data);
        f->data = malloc(need ? need : 1);
        f->capacity = f->data ? need : 0;
        if (!f->data) {
            FerryGLFrameRelease(f);
            return NULL;
        }
    }
    f->width = w;
    f->height = h;
    f->rowBytes = rb;
    return f;
}

/* Reads framebuffer 0 into dst, leaving the program's pack state and
 * bindings as they were. */
static void read_back(CGLContextObj c, void *dst, int w, int h, size_t rowBytes)
{
    GLint fb = 0, pbo = 0, align = 4, rowlen = 0, skiprows = 0, skippix = 0, readbuf = FGL_BACK;
    ferry_gl.GetIntegerv(FGL_READ_FRAMEBUFFER_BINDING, &fb);
    ferry_gl.GetIntegerv(FGL_PIXEL_PACK_BUFFER_BINDING, &pbo);
    ferry_gl.GetIntegerv(FGL_PACK_ALIGNMENT, &align);
    ferry_gl.GetIntegerv(FGL_PACK_ROW_LENGTH, &rowlen);
    ferry_gl.GetIntegerv(FGL_PACK_SKIP_ROWS, &skiprows);
    ferry_gl.GetIntegerv(FGL_PACK_SKIP_PIXELS, &skippix);
    if (fb)
        ferry_gl.BindFramebuffer(FGL_READ_FRAMEBUFFER, 0);
    ferry_gl.GetIntegerv(FGL_READ_BUFFER, &readbuf);
    if (pbo)
        ferry_gl.BindBuffer(FGL_PIXEL_PACK_BUFFER, 0);
    ferry_gl.PixelStorei(FGL_PACK_ALIGNMENT, 4);
    ferry_gl.PixelStorei(FGL_PACK_ROW_LENGTH, (GLint)(rowBytes / 4));
    ferry_gl.PixelStorei(FGL_PACK_SKIP_ROWS, 0);
    ferry_gl.PixelStorei(FGL_PACK_SKIP_PIXELS, 0);
    if (readbuf != FGL_BACK && ferry_gl.ReadBuffer)
        ferry_gl.ReadBuffer(FGL_BACK);
    ferry_gl.ReadPixels(0, 0, w, h, FGL_BGRA, FGL_UNSIGNED_INT_8_8_8_8_REV, dst);
    if (readbuf != FGL_BACK && ferry_gl.ReadBuffer)
        ferry_gl.ReadBuffer((GLenum)readbuf);
    ferry_gl.PixelStorei(FGL_PACK_ALIGNMENT, align);
    ferry_gl.PixelStorei(FGL_PACK_ROW_LENGTH, rowlen);
    ferry_gl.PixelStorei(FGL_PACK_SKIP_ROWS, skiprows);
    ferry_gl.PixelStorei(FGL_PACK_SKIP_PIXELS, skippix);
    if (pbo)
        ferry_gl.BindBuffer(FGL_PIXEL_PACK_BUFFER, (GLuint)pbo);
    if (fb)
        ferry_gl.BindFramebuffer(FGL_READ_FRAMEBUFFER, (GLuint)fb);
}

static void flip_rows(unsigned char *data, int h, size_t rowBytes)
{
    unsigned char tmp[4096];
    for (int y = 0; y < h / 2; y++) {
        unsigned char *a = data + (size_t)y * rowBytes, *b = data + (size_t)(h - 1 - y) * rowBytes;
        for (size_t off = 0; off < rowBytes; off += sizeof tmp) {
            size_t n = rowBytes - off < sizeof tmp ? rowBytes - off : sizeof tmp;
            memcpy(tmp, a + off, n);
            memcpy(a + off, b + off, n);
            memcpy(b + off, tmp, n);
        }
    }
}

/* the context bound here, binding the current one if it must */
static int bound_here(CGLContextObj c)
{
    struct tstate *ts = tstate();
    if (ts->bound == c)
        return 1;
    if (ts->current == c) {
        int ok = bind_here(ts, c);
        recount(ts);
        return ok;
    }
    return 0;
}

FerryGLFrame *FerryCGLCaptureFrame(CGLContextObj c, int topDown)
{
    if (!c || !bound_here(c) || !c->surface)
        return NULL;
    FerryGLFrame *f = frame_for(NULL, c->width, c->height);
    if (!f)
        return NULL;
    read_back(c, f->data, f->width, f->height, f->rowBytes);
    if (topDown)
        flip_rows(f->data, f->height, f->rowBytes);
    f->topDown = topDown;
    f->opaque = c->opacity != 0;
    pthread_mutex_lock(&c->frames);
    f->serial = ++c->serial;
    pthread_mutex_unlock(&c->frames);
    return f;
}

FerryGLFrame *FerryCGLCopyFrame(CGLContextObj c)
{
    if (!c)
        return NULL;
    pthread_mutex_lock(&c->frames);
    FerryGLFrame *f = FerryGLFrameRetain(c->latest);
    pthread_mutex_unlock(&c->frames);
    return f;
}

CGLError CGLFlushDrawable(CGLContextObj c)
{
    if (!c)
        return kCGLBadContext;
    if (!bound_here(c))
        return kCGLNoError;
    if (c->offBase && c->surface) {
        /* CGLSetOffScreen's memory: rows top first, as a bitmap context has them */
        read_back(c, c->offBase, c->width, c->height, (size_t)c->offRowBytes);
        flip_rows(c->offBase, c->height, (size_t)c->offRowBytes);
    } else if (c->surface) {
        pthread_mutex_lock(&c->frames);
        FerryGLFrame *reuse = c->spare;
        c->spare = NULL;
        pthread_mutex_unlock(&c->frames);
        FerryGLFrame *f = frame_for(reuse, c->width, c->height);
        if (f) {
            read_back(c, f->data, f->width, f->height, f->rowBytes);
            f->topDown = 0;
            f->opaque = c->opacity != 0;
            pthread_mutex_lock(&c->frames);
            f->serial = ++c->serial;
            FerryGLFrame *old = c->latest;
            c->latest = f;
            if (old && !c->spare)
                c->spare = old;
            else
                FerryGLFrameRelease(old);
            FerryCGLFlushCallback cb = c->callback;
            void *info = c->callbackInfo;
            pthread_mutex_unlock(&c->frames);
            if (cb)
                cb(c, info);
        }
    } else if (ferry_gl.Flush) {
        ferry_gl.Flush();
    }
    /* a size asked for from another thread */
    pthread_mutex_lock(&c->state);
    apply_size_locked(c);
    pthread_mutex_unlock(&c->state);
    if (c->swapInterval > 0 && c->surface) {
        uint64_t period = (uint64_t)(1e9 / FerryGLRefreshRate()) * (uint64_t)c->swapInterval, t = now_ns();
        uint64_t next = c->lastFlush + period;
        if (c->lastFlush && t < next && next - t <= period) {
            for (uint64_t left; (t = now_ns()) < next;) {
                left = next - t;
                struct timespec d = {(time_t)(left / 1000000000ull), (long)(left % 1000000000ull)};
                nanosleep(&d, NULL);
            }
            c->lastFlush = next;
        } else {
            c->lastFlush = t;
        }
    }
    return kCGLNoError;
}

/* ---- parameters and options ----------------------------------------------------------- */

CGLError CGLEnable(CGLContextObj c, CGLContextEnable p)
{
    if (!c)
        return kCGLBadContext;
    switch ((int)p) {
    case kCGLCESurfaceBackingSize: c->backingSizeEnabled = 1; break;
    case kCGLCESwapRectangle: c->swapRectEnabled = 1; break;
    case kCGLCERasterization: c->rasterization = 1; break;
    case kCGLCEMPEngine: c->mpEngine = 1; break;
    default: break;
    }
    return kCGLNoError;
}
CGLError CGLDisable(CGLContextObj c, CGLContextEnable p)
{
    if (!c)
        return kCGLBadContext;
    switch ((int)p) {
    case kCGLCESurfaceBackingSize: c->backingSizeEnabled = 0; break;
    case kCGLCESwapRectangle: c->swapRectEnabled = 0; break;
    case kCGLCERasterization: c->rasterization = 0; break;
    case kCGLCEMPEngine: c->mpEngine = 0; break;
    default: break;
    }
    return kCGLNoError;
}
CGLError CGLIsEnabled(CGLContextObj c, CGLContextEnable p, GLint *enable)
{
    if (!c)
        return kCGLBadContext;
    if (!enable)
        return kCGLBadAddress;
    switch ((int)p) {
    case kCGLCESurfaceBackingSize: *enable = c->backingSizeEnabled; break;
    case kCGLCESwapRectangle: *enable = c->swapRectEnabled; break;
    case kCGLCERasterization: *enable = c->rasterization; break;
    case kCGLCEMPEngine: *enable = c->mpEngine; break;
    default: *enable = 0; break;
    }
    return kCGLNoError;
}

CGLError CGLSetParameter(CGLContextObj c, CGLContextParameter p, const GLint *v)
{
    if (!c)
        return kCGLBadContext;
    if (!v)
        return kCGLBadAddress;
    switch ((int)p) {
    case kCGLCPSwapInterval: c->swapInterval = v[0] < 0 ? 0 : v[0]; break;
    case kCGLCPSurfaceOpacity: c->opacity = v[0] != 0; break;
    case kCGLCPSurfaceOrder: c->surfaceOrder = v[0]; break;
    case kCGLCPSurfaceBackingSize:
        c->backingSize[0] = v[0];
        c->backingSize[1] = v[1];
        break;
    case kCGLCPSwapRectangle: memcpy(c->swapRect, v, sizeof c->swapRect); break;
    default: break; /* the GPU and dispatch parameters mean nothing here */
    }
    return kCGLNoError;
}

CGLError CGLGetParameter(CGLContextObj c, CGLContextParameter p, GLint *v)
{
    if (!c)
        return kCGLBadContext;
    if (!v)
        return kCGLBadAddress;
    switch ((int)p) {
    case kCGLCPSwapInterval: v[0] = c->swapInterval; break;
    case kCGLCPSurfaceOpacity: v[0] = c->opacity; break;
    case kCGLCPSurfaceOrder: v[0] = c->surfaceOrder; break;
    case kCGLCPSurfaceBackingSize:
        if (c->backingSizeEnabled) {
            v[0] = c->backingSize[0];
            v[1] = c->backingSize[1];
        } else {
            v[0] = c->width;
            v[1] = c->height;
        }
        break;
    case kCGLCPSwapRectangle: memcpy(v, c->swapRect, sizeof c->swapRect); break;
    case kCGLCPHasDrawable: v[0] = c->surface != NULL; break;
    case kCGLCPCurrentRendererID: v[0] = kCGLRendererGenericFloatID; break;
    case kCGLCPGPUVertexProcessing:
    case kCGLCPGPUFragmentProcessing: v[0] = 1; break;
    case kCGLCPMPSwapsInFlight: v[0] = 1; break;
    case kCGLCPGPURestartStatus: v[0] = kCGLCPGPURestartStatusNone; break;
    default: v[0] = 0; break;
    }
    return kCGLNoError;
}

CGLError CGLSetVirtualScreen(CGLContextObj c, GLint screen)
{
    if (!c)
        return kCGLBadContext;
    return screen == 0 ? kCGLNoError : kCGLBadValue;
}
CGLError CGLGetVirtualScreen(CGLContextObj c, GLint *screen)
{
    if (!c)
        return kCGLBadContext;
    if (!screen)
        return kCGLBadAddress;
    *screen = 0;
    return kCGLNoError;
}

static GLint options[16];
static int option_index(CGLGlobalOption p)
{
    switch ((int)p) {
    case kCGLGOFormatCacheSize: return 0;
    case kCGLGOClearFormatCache: return 1;
    case kCGLGORetainRenderers: return 2;
    case kCGLGOUseBuildCache: return 3;
    case kCGLGOResetLibrary: return 4;
    case kCGLGOUseErrorHandler: return 5;
    default: return -1;
    }
}
CGLError CGLSetGlobalOption(CGLGlobalOption p, const GLint *v)
{
    int i = option_index(p);
    if (i < 0)
        return kCGLBadEnumeration;
    if (!v)
        return kCGLBadAddress;
    options[i] = *v;
    return kCGLNoError;
}
CGLError CGLGetGlobalOption(CGLGlobalOption p, GLint *v)
{
    int i = option_index(p);
    if (i < 0)
        return kCGLBadEnumeration;
    if (!v)
        return kCGLBadAddress;
    *v = options[i];
    return kCGLNoError;
}
CGLError CGLSetOption(CGLGlobalOption p, GLint v) { return CGLSetGlobalOption(p, &v); }
CGLError CGLGetOption(CGLGlobalOption p, GLint *v) { return CGLGetGlobalOption(p, v); }

void CGLGetVersion(GLint *major, GLint *minor)
{
    if (major)
        *major = 1;
    if (minor)
        *minor = 2;
}

const char *CGLErrorString(CGLError e)
{
    switch ((int)e) {
    case kCGLNoError: return "no error";
    case kCGLBadAttribute: return "invalid pixel format attribute";
    case kCGLBadProperty: return "invalid renderer property";
    case kCGLBadPixelFormat: return "invalid pixel format";
    case kCGLBadRendererInfo: return "invalid renderer info";
    case kCGLBadContext: return "invalid context";
    case kCGLBadDrawable: return "invalid drawable";
    case kCGLBadDisplay: return "invalid graphics device";
    case kCGLBadState: return "invalid context state";
    case kCGLBadValue: return "invalid numerical value";
    case kCGLBadMatch: return "invalid share context";
    case kCGLBadEnumeration: return "invalid enumerant";
    case kCGLBadOffScreen: return "invalid offscreen drawable";
    case kCGLBadFullScreen: return "invalid fullscreen drawable";
    case kCGLBadWindow: return "invalid window";
    case kCGLBadAddress: return "invalid pointer";
    case kCGLBadCodeModule: return "invalid code module";
    case kCGLBadAlloc: return "invalid memory allocation";
    case kCGLBadConnection: return "invalid CoreGraphics connection";
    default: return "unknown error";
    }
}

/* ---- offscreen memory, pbuffers and full screen --------------------------------------- */

CGLError CGLSetOffScreen(CGLContextObj c, GLsizei w, GLsizei h, GLint rowbytes, void *base)
{
    if (!c)
        return kCGLBadContext;
    if (!base || w <= 0 || h <= 0 || rowbytes < w * 4 || rowbytes % 4)
        return kCGLBadOffScreen;
    c->offWidth = w;
    c->offHeight = h;
    c->offRowBytes = rowbytes;
    c->offBase = base;
    FerryCGLSetDrawableSize(c, w, h);
    return kCGLNoError;
}
CGLError CGLGetOffScreen(CGLContextObj c, GLsizei *w, GLsizei *h, GLint *rowbytes, void **base)
{
    if (!c)
        return kCGLBadContext;
    if (w)
        *w = c->offBase ? c->offWidth : 0;
    if (h)
        *h = c->offBase ? c->offHeight : 0;
    if (rowbytes)
        *rowbytes = c->offBase ? c->offRowBytes : 0;
    if (base)
        *base = c->offBase;
    return kCGLNoError;
}

CGLError CGLSetFullScreen(CGLContextObj c) { return kCGLBadFullScreen; }
CGLError CGLSetFullScreenOnDisplay(CGLContextObj c, GLuint mask) { return kCGLBadFullScreen; }

CGLError CGLCreatePBuffer(GLsizei w, GLsizei h, GLenum target, GLenum internalFormat, GLint maxLevel,
                          CGLPBufferObj *out)
{
    if (!out)
        return kCGLBadAddress;
    *out = NULL;
    if (w <= 0 || h <= 0)
        return kCGLBadValue;
    CGLPBufferObj p = calloc(1, sizeof *p);
    if (!p)
        return kCGLBadAlloc;
    p->refs = 1;
    p->width = w;
    p->height = h;
    p->target = target;
    p->internalFormat = internalFormat;
    p->maxLevel = maxLevel;
    *out = p;
    return kCGLNoError;
}
CGLPBufferObj CGLRetainPBuffer(CGLPBufferObj p)
{
    if (p)
        __atomic_add_fetch(&p->refs, 1, __ATOMIC_ACQ_REL);
    return p;
}
void CGLReleasePBuffer(CGLPBufferObj p)
{
    if (p && !__atomic_sub_fetch(&p->refs, 1, __ATOMIC_ACQ_REL))
        free(p);
}
CGLError CGLDestroyPBuffer(CGLPBufferObj p)
{
    CGLReleasePBuffer(p);
    return kCGLNoError;
}
GLuint CGLGetPBufferRetainCount(CGLPBufferObj p) { return p ? (GLuint)p->refs : 0; }
CGLError CGLDescribePBuffer(CGLPBufferObj p, GLsizei *w, GLsizei *h, GLenum *target, GLenum *internalFormat,
                            GLint *mipmap)
{
    if (!p)
        return kCGLBadAddress;
    if (w)
        *w = p->width;
    if (h)
        *h = p->height;
    if (target)
        *target = p->target;
    if (internalFormat)
        *internalFormat = p->internalFormat;
    if (mipmap)
        *mipmap = p->maxLevel;
    return kCGLNoError;
}
/* A pbuffer is the context's drawable at the pbuffer's size; what is drawn
 * stays with the context, so another context can't texture from it. */
CGLError CGLSetPBuffer(CGLContextObj c, CGLPBufferObj p, GLenum face, GLint level, GLint screen)
{
    if (!c)
        return kCGLBadContext;
    if (!p)
        return kCGLBadAddress;
    CGLRetainPBuffer(p);
    if (c->pbuffer)
        CGLReleasePBuffer(c->pbuffer);
    c->pbuffer = p;
    FerryCGLSetDrawableSize(c, p->width, p->height);
    return kCGLNoError;
}
CGLError CGLGetPBuffer(CGLContextObj c, CGLPBufferObj *p, GLenum *face, GLint *level, GLint *screen)
{
    if (!c)
        return kCGLBadContext;
    if (p)
        *p = c->pbuffer;
    if (face)
        *face = 0;
    if (level)
        *level = 0;
    if (screen)
        *screen = 0;
    return kCGLNoError;
}
CGLError CGLTexImagePBuffer(CGLContextObj c, CGLPBufferObj p, GLenum source) { return kCGLBadDrawable; }

/* ---- textures from IOSurfaces --------------------------------------------------------- */

static int components_of(GLenum format)
{
    switch (format) {
    case 0x1903: /* RED */
    case 0x1906: /* ALPHA */
    case 0x1909: /* LUMINANCE */
    case 0x1902: /* DEPTH_COMPONENT */
    case 0x8D94: /* RED_INTEGER */
        return 1;
    case 0x8227: /* RG */
    case 0x190A: /* LUMINANCE_ALPHA */
    case 0x8228: /* RG_INTEGER */
        return 2;
    case 0x1907: /* RGB */
    case 0x80E0: /* BGR */
        return 3;
    default:
        return 4;
    }
}

static int bytes_per_pixel(GLenum format, GLenum type)
{
    switch (type) {
    case 0x1400: /* BYTE */
    case 0x1401: /* UNSIGNED_BYTE */
        return components_of(format);
    case 0x1402: /* SHORT */
    case 0x1403: /* UNSIGNED_SHORT */
    case 0x140B: /* HALF_FLOAT */
    case 0x8D61: /* HALF_APPLE, HALF_FLOAT_OES */
        return components_of(format) * 2;
    case 0x1404: /* INT */
    case 0x1405: /* UNSIGNED_INT */
    case 0x1406: /* FLOAT */
        return components_of(format) * 4;
    case 0x8033: /* UNSIGNED_SHORT_4_4_4_4 */
    case 0x8034: /* UNSIGNED_SHORT_5_5_5_1 */
    case 0x8363: /* UNSIGNED_SHORT_5_6_5 */
    case 0x8364: /* UNSIGNED_SHORT_5_6_5_REV */
    case 0x8365: /* UNSIGNED_SHORT_4_4_4_4_REV */
    case 0x8366: /* UNSIGNED_SHORT_1_5_5_5_REV */
    case FGL_UNSIGNED_SHORT_8_8_APPLE:
    case FGL_UNSIGNED_SHORT_8_8_REV_APPLE:
        return 2;
    default: /* the packed 32-bit types */
        return 4;
    }
}

/* The image a surface's plane holds, given to the texture bound at target.
 * On a Mac the texture then is the surface's memory; here it is a copy as
 * the surface is now, so a program that changes the surface afterwards
 * calls this again (as VLC and OBS do for each frame). The 4:2:2 formats
 * Apple's OpenGL reads as RGB (GL_RGB_422_APPLE) are spread out to one
 * texel per pixel, luma as green, Cb as blue and Cr as red. */
CGLError CGLTexImageIOSurface2D(CGLContextObj c, GLenum target, GLenum internalFormat, GLsizei w, GLsizei h,
                                GLenum format, GLenum type, IOSurfaceRef surface, GLuint plane)
{
    if (!c)
        return kCGLBadContext;
    if (!surface)
        return kCGLBadAddress;
    if (!bound_here(c))
        return kCGLBadContext;
    size_t planes = IOSurfaceGetPlaneCount(surface);
    if (planes ? plane >= planes : plane != 0)
        return kCGLBadValue;
    const unsigned char *base = planes ? IOSurfaceGetBaseAddressOfPlane(surface, plane) : IOSurfaceGetBaseAddress(surface);
    size_t rowBytes = planes ? IOSurfaceGetBytesPerRowOfPlane(surface, plane) : IOSurfaceGetBytesPerRow(surface);
    size_t surfH = planes ? IOSurfaceGetHeightOfPlane(surface, plane) : IOSurfaceGetHeight(surface);
    if (!base || w <= 0 || h <= 0 || (size_t)h > surfH)
        return kCGLBadValue;
    GLint unpack = 0, align = 4, rowlen = 0, skiprows = 0, skippix = 0, imgh = 0, skipimg = 0;
    ferry_gl.GetIntegerv(FGL_PIXEL_UNPACK_BUFFER_BINDING, &unpack);
    ferry_gl.GetIntegerv(FGL_UNPACK_ALIGNMENT, &align);
    ferry_gl.GetIntegerv(FGL_UNPACK_ROW_LENGTH, &rowlen);
    ferry_gl.GetIntegerv(FGL_UNPACK_SKIP_ROWS, &skiprows);
    ferry_gl.GetIntegerv(FGL_UNPACK_SKIP_PIXELS, &skippix);
    ferry_gl.GetIntegerv(FGL_UNPACK_IMAGE_HEIGHT, &imgh);
    ferry_gl.GetIntegerv(FGL_UNPACK_SKIP_IMAGES, &skipimg);
    if (unpack)
        ferry_gl.BindBuffer(FGL_PIXEL_UNPACK_BUFFER, 0);
    ferry_gl.PixelStorei(FGL_UNPACK_SKIP_ROWS, 0);
    ferry_gl.PixelStorei(FGL_UNPACK_SKIP_PIXELS, 0);
    ferry_gl.PixelStorei(FGL_UNPACK_IMAGE_HEIGHT, 0);
    ferry_gl.PixelStorei(FGL_UNPACK_SKIP_IMAGES, 0);
    CGLError result = kCGLNoError;
    unsigned char *copy = NULL;
    if (format == FGL_RGB_422_APPLE) {
        /* two pixels in each four bytes: Cb Y0 Cr Y1 ('2vuy', 8_8_APPLE) or Y0 Cb Y1 Cr ('yuvs', 8_8_REV_APPLE) */
        copy = malloc((size_t)w * (size_t)h * 3);
        if (!copy) {
            result = kCGLBadAlloc;
            goto restore;
        }
        int rev = type == FGL_UNSIGNED_SHORT_8_8_REV_APPLE;
        for (GLsizei y = 0; y < h; y++) {
            const unsigned char *s = base + (size_t)y * rowBytes;
            unsigned char *d = copy + (size_t)y * (size_t)w * 3;
            for (GLsizei x = 0; x < w; x += 2, s += 4) {
                unsigned char cb = rev ? s[1] : s[0], y0 = rev ? s[0] : s[1], cr = rev ? s[3] : s[2],
                              y1 = rev ? s[2] : s[3];
                d[0] = cr, d[1] = y0, d[2] = cb, d += 3;
                if (x + 1 < w)
                    d[0] = cr, d[1] = y1, d[2] = cb, d += 3;
            }
        }
        ferry_gl.PixelStorei(FGL_UNPACK_ALIGNMENT, 1);
        ferry_gl.PixelStorei(FGL_UNPACK_ROW_LENGTH, 0);
        ferry_gl.TexImage2D(target, 0, c->core ? 0x8051 /* RGB8 */ : FGL_RGB, w, h, 0, FGL_RGB, FGL_UNSIGNED_BYTE,
                            copy);
    } else {
        size_t bpp = (size_t)bytes_per_pixel(format, type);
        const void *pixels = base;
        if (rowBytes % bpp) {
            copy = malloc((size_t)w * bpp * (size_t)h);
            if (!copy) {
                result = kCGLBadAlloc;
                goto restore;
            }
            for (GLsizei y = 0; y < h; y++)
                memcpy(copy + (size_t)y * (size_t)w * bpp, base + (size_t)y * rowBytes, (size_t)w * bpp);
            pixels = copy;
            ferry_gl.PixelStorei(FGL_UNPACK_ROW_LENGTH, 0);
        } else {
            ferry_gl.PixelStorei(FGL_UNPACK_ROW_LENGTH, (GLint)(rowBytes / bpp));
        }
        ferry_gl.PixelStorei(FGL_UNPACK_ALIGNMENT, 1);
        ferry_gl.TexImage2D(target, 0, (GLint)internalFormat, w, h, 0, format, type, pixels);
    }
restore:
    free(copy);
    ferry_gl.PixelStorei(FGL_UNPACK_ALIGNMENT, align);
    ferry_gl.PixelStorei(FGL_UNPACK_ROW_LENGTH, rowlen);
    ferry_gl.PixelStorei(FGL_UNPACK_SKIP_ROWS, skiprows);
    ferry_gl.PixelStorei(FGL_UNPACK_SKIP_PIXELS, skippix);
    ferry_gl.PixelStorei(FGL_UNPACK_IMAGE_HEIGHT, imgh);
    ferry_gl.PixelStorei(FGL_UNPACK_SKIP_IMAGES, skipimg);
    if (unpack)
        ferry_gl.BindBuffer(FGL_PIXEL_UNPACK_BUFFER, (GLuint)unpack);
    return result;
}
