/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Cameras for Ferry's AVFoundation (freemac 1.257, Ferry 0.80.0): the calls
 * src/camera.c serves to appkit/AVCapture*.m through ferry_camera_symbol.
 * The host side and the Mac side both include this file, so the structures
 * are the same on both: only fixed-size C types, laid out the same way by
 * both compilers (System V, x86-64).
 *
 * A camera is one of this system's video capture devices (Video4Linux2,
 * /dev/videoN), or, when FERRY_CAMERA_TEST is set, Ferry's own test camera,
 * which draws its own pictures so that capture can be tried and tested on a
 * computer with no camera.
 */
#ifndef FERRY_CAMERA_H
#define FERRY_CAMERA_H
#include <stddef.h>
#include <stdint.h>

/* The pixel formats a camera can send, as Video4Linux2 names them. */
#define FERRY_CAMERA_YUYV 0x56595559u /* 'YUYV': Y0 Cb Y1 Cr, 4:2:2 */
#define FERRY_CAMERA_UYVY 0x59565955u /* 'UYVY': Cb Y0 Cr Y1, 4:2:2 */
#define FERRY_CAMERA_NV12 0x3231564eu /* 'NV12': Y plane, then Cb Cr pairs, 4:2:0 */
#define FERRY_CAMERA_I420 0x32315559u /* 'YU12': Y, Cb and Cr planes, 4:2:0 */
#define FERRY_CAMERA_MJPEG 0x47504a4du /* 'MJPG': each picture a JPEG */

struct ferry_camera {
    char id[160];           /* the same from one run to the next for one camera on one port */
    char path[64];          /* /dev/videoN, or "test" */
    char name[128];         /* the camera's own name */
    char model[128];        /* its maker's numbers where the system knows them */
    char manufacturer[128];
    int32_t builtin;        /* 1 for a camera built into the computer */
};

struct ferry_camera_rate {
    uint32_t num, den; /* the time between pictures, num/den seconds */
};

struct ferry_camera_mode {
    uint32_t fourcc;
    int32_t width, height;
    uint32_t nrates;
    struct ferry_camera_rate rates[12]; /* longest first is not promised */
};

/* What a camera sends once it is started. */
struct ferry_camera_started {
    uint32_t fourcc;
    int32_t width, height;
    int32_t stride; /* bytes in a row of the first plane */
    struct ferry_camera_rate rate;
};

/* One picture: data stays the camera's until ferry_camera_release. */
struct ferry_camera_frame {
    const void *data;
    size_t size;
    uint64_t time_ns; /* CLOCK_MONOTONIC when the picture was taken */
    uint64_t sequence;
};

typedef int (*ferry_camera_list_fn)(struct ferry_camera *out, int max);
typedef int (*ferry_camera_modes_fn)(const char *path, struct ferry_camera_mode *out, int max);
typedef void *(*ferry_camera_start_fn)(const char *path, uint32_t fourcc, int32_t width, int32_t height,
                                       struct ferry_camera_rate rate, struct ferry_camera_started *got);
/* 1 with a picture, 0 when none came in timeout_ms, -1 when the camera went away */
typedef int (*ferry_camera_next_fn)(void *camera, int timeout_ms, struct ferry_camera_frame *frame);
typedef void (*ferry_camera_release_fn)(void *camera);
typedef void (*ferry_camera_stop_fn)(void *camera);
/* A JPEG picture into 32-bit BGRA; 0 when it was read, -1 otherwise (no libturbojpeg) */
typedef int (*ferry_camera_jpeg_fn)(const void *jpeg, size_t size, void *bgra, int32_t width, int32_t height,
                                    int32_t stride);

void *ferry_camera_symbol(const char *name);

#endif
