/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Ferry's OpenGL framework offers Ferry's own AppKit, Core Animation
 * and Core Video (freemac 1.235, Ferry 0.59.0): a context's drawable, the
 * frames its flushes show, and the frames read from it at once. These are
 * Ferry's own calls, exported by the OpenGL framework under names no Mac
 * program uses.
 *
 * A context's drawable is an image of the size its view or layer asks for,
 * in pixels; what a program draws in framebuffer 0 lands there. Each
 * CGLFlushDrawable reads it back as a frame (BGRA in memory, which is
 * Cairo's ARGB32 and Core Graphics' 32-bit little-endian
 * alpha-premultiplied-first, bottom row first as OpenGL reads it), which
 * the view shows the next time it draws. */
#ifndef FERRY_OPENGL_FERRYGL_H
#define FERRY_OPENGL_FERRYGL_H
#include <OpenGL/OpenGL.h>
#include <stddef.h>
#include <stdint.h>

typedef struct FerryGLFrame {
    int refs;           /* atomically: FerryGLFrameRetain, FerryGLFrameRelease */
    int width, height;  /* pixels */
    size_t rowBytes;
    int opaque;         /* the context's surface opacity: alpha means nothing */
    int topDown;        /* first row is the top one */
    uint64_t serial;    /* the flush that made it, from 1 */
    unsigned char *data;
    size_t capacity;
} FerryGLFrame;

FerryGLFrame *FerryGLFrameRetain(FerryGLFrame *f);
void FerryGLFrameRelease(FerryGLFrame *f);

/* 1 if a context can be made on this system (opens EGL the first time). */
int FerryGLAvailable(void);

/* The drawable's size in pixels; 0 by 0 takes the drawable away. May be
 * called on any thread: a context drawing on another thread changes size at
 * its next flush or when it is next made current there. */
void FerryCGLSetDrawableSize(CGLContextObj ctx, int width, int height);
void FerryCGLGetDrawableSize(CGLContextObj ctx, int *width, int *height);

/* Called on the flushing thread after each flush made a new frame. */
typedef void (*FerryCGLFlushCallback)(CGLContextObj ctx, void *info);
void FerryCGLSetFlushCallback(CGLContextObj ctx, FerryCGLFlushCallback callback, void *info);

/* The frame the last flush showed (retained), or NULL. */
FerryGLFrame *FerryCGLCopyFrame(CGLContextObj ctx);

/* Reads framebuffer 0 of the context current on this thread now, as a new
 * frame (retained), top row first if topDown; no pacing, no callback. */
FerryGLFrame *FerryCGLCaptureFrame(CGLContextObj ctx, int topDown);

/* The display's refresh rate, in Hz: what flushes with a swap interval
 * are paced to, and the rate of Core Video's display links and Core
 * Animation's CADisplayLink. 60, or FERRY_REFRESH_RATE from the
 * environment (10 to 500), unless set. */
void FerryGLSetRefreshRate(double hz);
double FerryGLRefreshRate(void);

#endif
