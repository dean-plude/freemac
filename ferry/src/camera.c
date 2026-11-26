/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Cameras for Ferry's AVFoundation (freemac 1.257, Ferry 0.80.0): see
 * ferry_camera.h. A Mac app finds cameras with AVCaptureDevice and reads
 * them with AVCaptureSession; Ferry's (appkit/AVCapture*.m) asks this file,
 * which reads this system's Video4Linux2 devices, written from the kernel's
 * published V4L2 documentation (linux/videodev2.h).
 *
 * A camera is a /dev/videoN that captures video by streaming and sends at
 * least one of the pixel formats Ferry turns into a Mac's (YUYV, UYVY,
 * NV12, YU12 or Motion JPEG); a USB camera's other nodes (its metadata)
 * aren't cameras. Its pictures come by memory-mapped buffers, four of them,
 * one held by the app at a time.
 *
 * Motion JPEG pictures are read with this system's libturbojpeg, opened
 * the first time one is read; without it a camera's JPEG formats aren't
 * offered.
 *
 * FERRY_CAMERA_TEST=1 adds Ferry's test camera, first: a few formats and
 * sizes, and pictures it draws itself (red on the left, blue on the right,
 * a white square that moves along the top) at the rate asked.
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "ferry.h"
#include "ferry_camera.h"

static int xioctl(int fd, unsigned long req, void *arg)
{
    int r;
    do
        r = ioctl(fd, req, arg);
    while (r < 0 && errno == EINTR);
    return r;
}

static int known_format(uint32_t f)
{
    return f == FERRY_CAMERA_YUYV || f == FERRY_CAMERA_UYVY || f == FERRY_CAMERA_NV12 || f == FERRY_CAMERA_I420 ||
           f == FERRY_CAMERA_MJPEG;
}

/* ---- Motion JPEG ------------------------------------------------------------------------------- */

static pthread_mutex_t jpeg_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t jpeg_once = PTHREAD_ONCE_INIT;
static void *jpeg_handle;
static void *(*tj_init_decompress)(void);
static int (*tj_header)(void *, const unsigned char *, unsigned long, int *, int *, int *, int *);
static int (*tj_decompress)(void *, const unsigned char *, unsigned long, unsigned char *, int, int, int, int, int);

static void open_jpeg(void)
{
    void *lib = dlopen("libturbojpeg.so.0", RTLD_NOW | RTLD_LOCAL);
    if (!lib)
        return;
    tj_init_decompress = (void *(*)(void))dlsym(lib, "tjInitDecompress");
    tj_header = (int (*)(void *, const unsigned char *, unsigned long, int *, int *, int *, int *))dlsym(
        lib, "tjDecompressHeader3");
    tj_decompress = (int (*)(void *, const unsigned char *, unsigned long, unsigned char *, int, int, int, int,
                             int))dlsym(lib, "tjDecompress2");
    if (tj_init_decompress && tj_header && tj_decompress)
        jpeg_handle = tj_init_decompress();
}

static int have_jpeg(void)
{
    pthread_once(&jpeg_once, open_jpeg);
    return jpeg_handle != NULL;
}

static int camera_jpeg(const void *jpeg, size_t size, void *bgra, int32_t width, int32_t height, int32_t stride)
{
    if (!have_jpeg() || !jpeg || size < 4)
        return -1;
    enum { TJPF_BGRA = 8, TJFLAG_FASTDCT = 2048 };
    pthread_mutex_lock(&jpeg_lock);
    int w = 0, h = 0, sub = 0, space = 0, rc = -1;
    if (tj_header(jpeg_handle, jpeg, size, &w, &h, &sub, &space) == 0 && w == width && h == height)
        rc = tj_decompress(jpeg_handle, jpeg, size, bgra, width, stride, height, TJPF_BGRA, TJFLAG_FASTDCT) == 0
                 ? 0
                 : -1;
    pthread_mutex_unlock(&jpeg_lock);
    return rc;
}

/* ---- the test camera --------------------------------------------------------------------------- */

static int test_wanted(void)
{
    const char *t = getenv("FERRY_CAMERA_TEST");
    return t && *t && strcmp(t, "0");
}

static const struct ferry_camera_mode test_modes[] = {
    {FERRY_CAMERA_YUYV, 640, 480, 2, {{1, 30}, {1, 15}}},
    {FERRY_CAMERA_YUYV, 320, 240, 1, {{1, 30}}},
    {FERRY_CAMERA_UYVY, 640, 480, 1, {{1, 30}}},
    {FERRY_CAMERA_NV12, 1280, 720, 1, {{1, 30}}},
    {FERRY_CAMERA_I420, 640, 480, 1, {{1, 30}}},
};

struct test_camera {
    struct ferry_camera_started got;
    unsigned char *pixels;
    size_t size;
    uint64_t sequence, start_ns, step_ns;
};

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + (uint64_t)t.tv_nsec;
}

/* BT.601, video range: red, blue and white */
static const unsigned char red[3] = {82, 90, 240}, blue[3] = {41, 240, 110}, white[3] = {235, 128, 128};

static const unsigned char *test_colour(int x, int y, int w, uint64_t seq)
{
    int square = (int)((seq * 8) % (uint64_t)(w > 48 ? w - 32 : 1));
    if (y >= 16 && y < 48 && x >= square && x < square + 32)
        return white;
    return x < w / 2 ? red : blue;
}

static void test_draw(struct test_camera *c)
{
    int w = c->got.width, h = c->got.height;
    unsigned char *p = c->pixels;
    switch (c->got.fourcc) {
    case FERRY_CAMERA_YUYV:
    case FERRY_CAMERA_UYVY: {
        int yuyv = c->got.fourcc == FERRY_CAMERA_YUYV;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x += 2) {
                const unsigned char *a = test_colour(x, y, w, c->sequence), *b = test_colour(x + 1, y, w, c->sequence);
                unsigned char *q = p + (size_t)y * c->got.stride + (size_t)x * 2;
                unsigned char cb = (unsigned char)((a[1] + b[1]) / 2), cr = (unsigned char)((a[2] + b[2]) / 2);
                if (yuyv)
                    q[0] = a[0], q[1] = cb, q[2] = b[0], q[3] = cr;
                else
                    q[0] = cb, q[1] = a[0], q[2] = cr, q[3] = b[0];
            }
        break;
    }
    case FERRY_CAMERA_NV12:
    case FERRY_CAMERA_I420: {
        unsigned char *yp = p, *up = p + (size_t)w * h, *vp = up + (size_t)(w / 2) * (h / 2);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                yp[(size_t)y * w + x] = test_colour(x, y, w, c->sequence)[0];
        for (int y = 0; y < h / 2; y++)
            for (int x = 0; x < w / 2; x++) {
                const unsigned char *a = test_colour(x * 2, y * 2, w, c->sequence);
                if (c->got.fourcc == FERRY_CAMERA_NV12)
                    up[(size_t)y * w + x * 2] = a[1], up[(size_t)y * w + x * 2 + 1] = a[2];
                else
                    up[(size_t)y * (w / 2) + x] = a[1], vp[(size_t)y * (w / 2) + x] = a[2];
            }
        break;
    }
    }
}

static void *test_start(uint32_t fourcc, int32_t width, int32_t height, struct ferry_camera_rate rate,
                        struct ferry_camera_started *got)
{
    const struct ferry_camera_mode *m = NULL;
    for (size_t i = 0; i < sizeof test_modes / sizeof *test_modes; i++)
        if (test_modes[i].fourcc == fourcc && test_modes[i].width == width && test_modes[i].height == height)
            m = &test_modes[i];
    for (size_t i = 0; !m && i < sizeof test_modes / sizeof *test_modes; i++)
        if (test_modes[i].fourcc == fourcc)
            m = &test_modes[i];
    if (!m)
        m = &test_modes[0];
    struct test_camera *c = calloc(1, sizeof *c);
    if (!c)
        return NULL;
    c->got.fourcc = m->fourcc;
    c->got.width = m->width;
    c->got.height = m->height;
    int packed = m->fourcc == FERRY_CAMERA_YUYV || m->fourcc == FERRY_CAMERA_UYVY;
    c->got.stride = packed ? m->width * 2 : m->width;
    c->got.rate = m->rates[0];
    for (uint32_t i = 0; i < m->nrates; i++)
        if (rate.den && m->rates[i].num * (uint64_t)rate.den == rate.num * (uint64_t)m->rates[i].den)
            c->got.rate = m->rates[i];
    c->size = packed ? (size_t)m->width * 2 * m->height : (size_t)m->width * m->height * 3 / 2;
    c->pixels = malloc(c->size);
    if (!c->pixels) {
        free(c);
        return NULL;
    }
    c->step_ns = (uint64_t)c->got.rate.num * 1000000000ull / (c->got.rate.den ? c->got.rate.den : 30);
    c->start_ns = now_ns();
    *got = c->got;
    return c;
}

static int test_next(struct test_camera *c, int timeout_ms, struct ferry_camera_frame *frame)
{
    uint64_t due = c->start_ns + c->sequence * c->step_ns, now = now_ns();
    if (due > now) {
        uint64_t wait = due - now;
        if (timeout_ms >= 0 && wait > (uint64_t)timeout_ms * 1000000ull) {
            struct timespec t = {timeout_ms / 1000, (long)(timeout_ms % 1000) * 1000000l};
            nanosleep(&t, NULL);
            return 0;
        }
        struct timespec t = {(time_t)(wait / 1000000000ull), (long)(wait % 1000000000ull)};
        nanosleep(&t, NULL);
    }
    test_draw(c);
    frame->data = c->pixels;
    frame->size = c->size;
    frame->time_ns = due > now ? due : now;
    frame->sequence = c->sequence++;
    return 1;
}

/* ---- this system's cameras --------------------------------------------------------------------- */

static void read_line(const char *path, char *out, size_t n)
{
    out[0] = 0;
    FILE *f = fopen(path, "re");
    if (!f)
        return;
    if (fgets(out, (int)n, f)) {
        size_t l = strlen(out);
        while (l && isspace((unsigned char)out[l - 1]))
            out[--l] = 0;
    }
    fclose(f);
}

/* What sysfs says of the USB device a video node belongs to. */
static void usb_details(const char *node, struct ferry_camera *c)
{
    char link[PATH_MAX], dev[PATH_MAX], p[PATH_MAX + 32], vendor[16], product[16], removable[32];
    snprintf(link, sizeof link, "/sys/class/video4linux/%s/device", node);
    if (!realpath(link, dev))
        return;
    char *slash = strrchr(dev, '/'); /* the interface's parent is the USB device */
    if (slash)
        *slash = 0;
    snprintf(p, sizeof p, "%s/idVendor", dev);
    read_line(p, vendor, sizeof vendor);
    snprintf(p, sizeof p, "%s/idProduct", dev);
    read_line(p, product, sizeof product);
    if (vendor[0] && product[0])
        snprintf(c->model, sizeof c->model, "UVC Camera VendorID_%ld ProductID_%ld", strtol(vendor, NULL, 16),
                 strtol(product, NULL, 16));
    snprintf(p, sizeof p, "%s/manufacturer", dev);
    read_line(p, c->manufacturer, sizeof c->manufacturer);
    snprintf(p, sizeof p, "%s/removable", dev);
    read_line(p, removable, sizeof removable);
    c->builtin = !strcmp(removable, "fixed");
}

static int capture_caps(int fd, struct v4l2_capability *cap)
{
    if (xioctl(fd, VIDIOC_QUERYCAP, cap) < 0)
        return 0;
    uint32_t caps = cap->capabilities & V4L2_CAP_DEVICE_CAPS ? cap->device_caps : cap->capabilities;
    return (caps & V4L2_CAP_VIDEO_CAPTURE) && (caps & V4L2_CAP_STREAMING);
}

static int has_known_format(int fd)
{
    for (struct v4l2_fmtdesc d = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE}; xioctl(fd, VIDIOC_ENUM_FMT, &d) == 0;
         d.index++)
        if (known_format(d.pixelformat) && (d.pixelformat != FERRY_CAMERA_MJPEG || have_jpeg()))
            return 1;
    return 0;
}

static int by_number(const struct dirent **a, const struct dirent **b)
{
    return atoi((*a)->d_name + 5) - atoi((*b)->d_name + 5);
}

static int is_video_node(const struct dirent *e)
{
    if (strncmp(e->d_name, "video", 5) || !e->d_name[5])
        return 0;
    for (const char *s = e->d_name + 5; *s; s++)
        if (!isdigit((unsigned char)*s))
            return 0;
    return 1;
}

static int camera_list(struct ferry_camera *out, int max)
{
    int n = 0;
    if (test_wanted() && n < max) {
        memset(&out[n], 0, sizeof *out);
        snprintf(out[n].id, sizeof out[n].id, "ferry-test-camera");
        snprintf(out[n].path, sizeof out[n].path, "test");
        snprintf(out[n].name, sizeof out[n].name, "Ferry Test Camera");
        snprintf(out[n].model, sizeof out[n].model, "Ferry Test Camera");
        snprintf(out[n].manufacturer, sizeof out[n].manufacturer, "freemac");
        n++;
    }
    struct dirent **names = NULL;
    int count = scandir("/dev", &names, is_video_node, by_number);
    for (int i = 0; i < count; i++) {
        char path[64];
        snprintf(path, sizeof path, "/dev/%s", names[i]->d_name);
        int fd = n < max ? open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC) : -1;
        struct v4l2_capability cap;
        if (fd >= 0 && capture_caps(fd, &cap) && has_known_format(fd)) {
            struct ferry_camera *c = &out[n];
            memset(c, 0, sizeof *c);
            snprintf(c->path, sizeof c->path, "%s", path);
            snprintf(c->name, sizeof c->name, "%s", (const char *)cap.card);
            snprintf(c->model, sizeof c->model, "%s", (const char *)cap.card);
            usb_details(names[i]->d_name, c);
            snprintf(c->id, sizeof c->id, "%s@%s", (const char *)cap.card, (const char *)cap.bus_info);
            for (int j = 0; j < n; j++) /* two nodes of one camera that both capture */
                if (!strcmp(out[j].id, c->id)) {
                    snprintf(c->id, sizeof c->id, "%s@%s#%s", (const char *)cap.card, (const char *)cap.bus_info,
                             names[i]->d_name);
                    break;
                }
            n++;
        }
        if (fd >= 0)
            close(fd);
        free(names[i]);
    }
    free(names);
    return n;
}

static void add_rates(int fd, uint32_t fourcc, int w, int h, struct ferry_camera_mode *m)
{
    m->nrates = 0;
    struct v4l2_frmivalenum iv = {.pixel_format = fourcc, .width = (uint32_t)w, .height = (uint32_t)h};
    for (; m->nrates < 12 && xioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &iv) == 0; iv.index++) {
        if (iv.type == V4L2_FRMIVAL_TYPE_DISCRETE) {
            if (iv.discrete.numerator && iv.discrete.denominator)
                m->rates[m->nrates++] = (struct ferry_camera_rate){iv.discrete.numerator, iv.discrete.denominator};
            continue;
        }
        /* a range: its two ends, and 30 a second where that is inside it */
        struct v4l2_fract lo = iv.stepwise.min, hi = iv.stepwise.max;
        if (lo.numerator && lo.denominator)
            m->rates[m->nrates++] = (struct ferry_camera_rate){lo.numerator, lo.denominator};
        if (lo.numerator * 30ull < lo.denominator && hi.numerator * 30ull > hi.denominator && m->nrates < 12)
            m->rates[m->nrates++] = (struct ferry_camera_rate){1, 30};
        if (hi.numerator && hi.denominator && m->nrates < 12 &&
            (hi.numerator != lo.numerator || hi.denominator != lo.denominator))
            m->rates[m->nrates++] = (struct ferry_camera_rate){hi.numerator, hi.denominator};
        break;
    }
    if (!m->nrates) /* a camera that doesn't say: as it is set now, or 30 a second */
    {
        struct v4l2_streamparm parm = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
        struct v4l2_fract t = {1, 30};
        if (xioctl(fd, VIDIOC_G_PARM, &parm) == 0 && parm.parm.capture.timeperframe.numerator &&
            parm.parm.capture.timeperframe.denominator)
            t = parm.parm.capture.timeperframe;
        m->rates[m->nrates++] = (struct ferry_camera_rate){t.numerator, t.denominator};
    }
}

static int camera_modes(const char *path, struct ferry_camera_mode *out, int max)
{
    if (!path)
        return 0;
    if (!strcmp(path, "test")) {
        int n = 0;
        for (size_t i = 0; i < sizeof test_modes / sizeof *test_modes && n < max; i++)
            out[n++] = test_modes[i];
        return n;
    }
    int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
        return 0;
    int n = 0;
    for (struct v4l2_fmtdesc d = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
         n < max && xioctl(fd, VIDIOC_ENUM_FMT, &d) == 0; d.index++) {
        if (!known_format(d.pixelformat) || (d.pixelformat == FERRY_CAMERA_MJPEG && !have_jpeg()))
            continue;
        struct v4l2_frmsizeenum fs = {.pixel_format = d.pixelformat};
        for (; n < max && xioctl(fd, VIDIOC_ENUM_FRAMESIZES, &fs) == 0; fs.index++) {
            if (fs.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
                out[n] = (struct ferry_camera_mode){d.pixelformat, (int32_t)fs.discrete.width,
                                                    (int32_t)fs.discrete.height, 0, {{0, 0}}};
                add_rates(fd, d.pixelformat, out[n].width, out[n].height, &out[n]);
                n++;
                continue;
            }
            /* any size in a range: the usual ones inside it */
            static const int sizes[][2] = {{320, 240}, {640, 360}, {640, 480}, {800, 600}, {1024, 576},
                                           {1280, 720}, {1600, 900}, {1920, 1080}, {2560, 1440}, {3840, 2160}};
            struct v4l2_frmsize_stepwise s = fs.stepwise;
            for (size_t k = 0; k < sizeof sizes / sizeof *sizes && n < max; k++) {
                uint32_t w = (uint32_t)sizes[k][0], h = (uint32_t)sizes[k][1];
                if (w < s.min_width || w > s.max_width || h < s.min_height || h > s.max_height ||
                    (s.step_width > 1 && (w - s.min_width) % s.step_width) ||
                    (s.step_height > 1 && (h - s.min_height) % s.step_height))
                    continue;
                out[n] = (struct ferry_camera_mode){d.pixelformat, (int32_t)w, (int32_t)h, 0, {{0, 0}}};
                add_rates(fd, d.pixelformat, (int)w, (int)h, &out[n]);
                n++;
            }
            break;
        }
    }
    close(fd);
    return n;
}

struct v4l2_camera {
    int test; /* 0: this is a real one */
    int fd;
    struct { void *start; size_t length; } buffers[4];
    unsigned nbuffers;
    int held; /* the buffer the app has, or -1 */
    struct ferry_camera_started got;
};

static void unmap_all(struct v4l2_camera *c)
{
    for (unsigned i = 0; i < c->nbuffers; i++)
        if (c->buffers[i].start && c->buffers[i].start != MAP_FAILED)
            munmap(c->buffers[i].start, c->buffers[i].length);
    c->nbuffers = 0;
}

struct any_camera {
    int test;
};

static void *camera_start(const char *path, uint32_t fourcc, int32_t width, int32_t height,
                          struct ferry_camera_rate rate, struct ferry_camera_started *got)
{
    if (!path || !got)
        return NULL;
    if (!strcmp(path, "test")) {
        struct test_camera *t = test_start(fourcc, width, height, rate, got);
        if (!t)
            return NULL;
        struct any_camera *a = malloc(sizeof *a + sizeof(struct test_camera *));
        if (!a) {
            free(t->pixels), free(t);
            return NULL;
        }
        a->test = 1;
        memcpy(a + 1, &t, sizeof t);
        return a;
    }
    struct v4l2_camera *c = calloc(1, sizeof *c);
    if (!c)
        return NULL;
    c->held = -1;
    c->fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (c->fd < 0) {
        free(c);
        return NULL;
    }
    struct v4l2_format f = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
    f.fmt.pix.width = (uint32_t)width;
    f.fmt.pix.height = (uint32_t)height;
    f.fmt.pix.pixelformat = fourcc;
    f.fmt.pix.field = V4L2_FIELD_ANY;
    if (xioctl(c->fd, VIDIOC_S_FMT, &f) < 0 || !known_format(f.fmt.pix.pixelformat))
        goto fail;
    c->got.fourcc = f.fmt.pix.pixelformat;
    c->got.width = (int32_t)f.fmt.pix.width;
    c->got.height = (int32_t)f.fmt.pix.height;
    c->got.stride = (int32_t)f.fmt.pix.bytesperline;
    if (!c->got.stride)
        c->got.stride = c->got.fourcc == FERRY_CAMERA_YUYV || c->got.fourcc == FERRY_CAMERA_UYVY ? c->got.width * 2
                                                                                                 : c->got.width;
    struct v4l2_streamparm parm = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
    if (rate.num && rate.den) {
        parm.parm.capture.timeperframe.numerator = rate.num;
        parm.parm.capture.timeperframe.denominator = rate.den;
        xioctl(c->fd, VIDIOC_S_PARM, &parm); /* a camera with one rate may refuse; it keeps its own */
    }
    struct v4l2_streamparm now = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
    if (xioctl(c->fd, VIDIOC_G_PARM, &now) == 0 && now.parm.capture.timeperframe.denominator)
        c->got.rate = (struct ferry_camera_rate){now.parm.capture.timeperframe.numerator,
                                                 now.parm.capture.timeperframe.denominator};
    else
        c->got.rate = rate.den ? rate : (struct ferry_camera_rate){1, 30};

    struct v4l2_requestbuffers req = {.count = 4, .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP};
    if (xioctl(c->fd, VIDIOC_REQBUFS, &req) < 0 || req.count < 2)
        goto fail;
    if (req.count > 4)
        req.count = 4;
    for (unsigned i = 0; i < req.count; i++) {
        struct v4l2_buffer b = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP, .index = i};
        if (xioctl(c->fd, VIDIOC_QUERYBUF, &b) < 0)
            goto fail;
        c->buffers[i].length = b.length;
        c->buffers[i].start = mmap(NULL, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, c->fd, b.m.offset);
        c->nbuffers = i + 1;
        if (c->buffers[i].start == MAP_FAILED || xioctl(c->fd, VIDIOC_QBUF, &b) < 0)
            goto fail;
    }
    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(c->fd, VIDIOC_STREAMON, &type) < 0)
        goto fail;
    *got = c->got;
    return c;
fail:
    unmap_all(c);
    close(c->fd);
    free(c);
    return NULL;
}

static void camera_release(void *camera)
{
    struct any_camera *a = camera;
    if (!a || a->test)
        return;
    struct v4l2_camera *c = camera;
    if (c->held < 0)
        return;
    struct v4l2_buffer b = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP, .index = (uint32_t)c->held};
    xioctl(c->fd, VIDIOC_QBUF, &b);
    c->held = -1;
}

static int camera_next(void *camera, int timeout_ms, struct ferry_camera_frame *frame)
{
    struct any_camera *a = camera;
    if (!a || !frame)
        return -1;
    if (a->test) {
        struct test_camera *t;
        memcpy(&t, a + 1, sizeof t);
        return test_next(t, timeout_ms, frame);
    }
    struct v4l2_camera *c = camera;
    camera_release(c);
    for (;;) {
        struct pollfd p = {c->fd, POLLIN, 0};
        int r = poll(&p, 1, timeout_ms);
        if (r < 0 && errno == EINTR)
            continue;
        if (r < 0 || (p.revents & (POLLERR | POLLHUP | POLLNVAL)))
            return -1;
        if (r == 0)
            return 0;
        struct v4l2_buffer b = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP};
        if (xioctl(c->fd, VIDIOC_DQBUF, &b) < 0) {
            if (errno == EAGAIN)
                continue;
            return -1;
        }
        if (b.index >= c->nbuffers)
            return -1;
        if (b.flags & V4L2_BUF_FLAG_ERROR || !b.bytesused) { /* a spoiled picture: the next one */
            xioctl(c->fd, VIDIOC_QBUF, &b);
            continue;
        }
        c->held = (int)b.index;
        frame->data = c->buffers[b.index].start;
        frame->size = b.bytesused;
        frame->sequence = b.sequence;
        if ((b.flags & V4L2_BUF_FLAG_TIMESTAMP_MASK) == V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC &&
            (b.timestamp.tv_sec || b.timestamp.tv_usec))
            frame->time_ns = (uint64_t)b.timestamp.tv_sec * 1000000000ull + (uint64_t)b.timestamp.tv_usec * 1000ull;
        else
            frame->time_ns = now_ns();
        return 1;
    }
}

static void camera_stop(void *camera)
{
    struct any_camera *a = camera;
    if (!a)
        return;
    if (a->test) {
        struct test_camera *t;
        memcpy(&t, a + 1, sizeof t);
        free(t->pixels);
        free(t);
        free(a);
        return;
    }
    struct v4l2_camera *c = camera;
    camera_release(c);
    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    xioctl(c->fd, VIDIOC_STREAMOFF, &type);
    unmap_all(c);
    close(c->fd);
    free(c);
}

void *ferry_camera_symbol(const char *name)
{
    static const struct { const char *name; void *fn; } calls[] = {
        {"list", (void *)camera_list},       {"modes", (void *)camera_modes}, {"start", (void *)camera_start},
        {"next", (void *)camera_next},       {"release", (void *)camera_release},
        {"stop", (void *)camera_stop},       {"jpeg", (void *)camera_jpeg},
    };
    for (size_t i = 0; name && i < sizeof calls / sizeof *calls; i++)
        if (!strcmp(calls[i].name, name))
            return calls[i].fn;
    return NULL;
}
