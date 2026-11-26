/* SPDX-License-Identifier: GPL-3.0-or-later
 * A stand-in for what a compositor's screen cast puts on PipeWire, for
 * Ferry's Wayland capture test (freemac 1.240, Ferry 0.64.0; portal_test.sh).
 * A native Linux program, built against this system's libpipewire:
 *
 *   pw_producer NAME FORMAT WIDTH HEIGHT PATTERN
 *
 * FORMAT is BGRx or RGBx; PATTERN is "quarters" (red, green, blue and
 * yellow quarters, as the X11 test's window) or "cyan". It makes a video
 * source node, offers that one format at that size in shared memory (memfd), and
 * sends a frame 30 times a second. Where the consumer took the cursor
 * metadata, each frame carries a 16x16 white pointer at 100,60 (the stream's
 * pixels), hotspot 0,0. It prints "node ID" once PipeWire has numbered it. */
#include <pipewire/pipewire.h>
#include <spa/buffer/meta.h>
#include <spa/param/buffers.h>
#include <spa/param/video/format-utils.h>
#include <spa/pod/builder.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct data {
    struct pw_main_loop *loop;
    struct pw_stream *stream;
    struct spa_source *timer;
    uint32_t format, width, height;
    const char *pattern;
    int printed;
    uint64_t seq;
};

static uint32_t colour(struct data *d, uint32_t x, uint32_t y)
{
    /* 0xRRGGBB */
    if (!strcmp(d->pattern, "cyan"))
        return 0x00ffff;
    int right = x >= d->width / 2, bottom = y >= d->height / 2;
    return bottom ? (right ? 0xffff00 : 0x0000ff) : (right ? 0x00ff00 : 0xff0000);
}

static void fill(struct data *d, uint8_t *p, int32_t stride)
{
    for (uint32_t y = 0; y < d->height; y++)
        for (uint32_t x = 0; x < d->width; x++) {
            uint32_t c = colour(d, x, y);
            uint8_t r = c >> 16, g = c >> 8, b = c;
            uint8_t *px = p + y * stride + x * 4;
            if (d->format == SPA_VIDEO_FORMAT_RGBx)
                px[0] = r, px[1] = g, px[2] = b;
            else
                px[0] = b, px[1] = g, px[2] = r;
            px[3] = 0xff;
        }
}

static void on_timeout(void *userdata, uint64_t expirations)
{
    struct data *d = userdata;
    struct pw_buffer *b = pw_stream_dequeue_buffer(d->stream);
    if (!b)
        return;
    struct spa_buffer *buf = b->buffer;
    uint8_t *p = buf->datas[0].data;
    if (!p) {
        pw_stream_queue_buffer(d->stream, b);
        return;
    }
    int32_t stride = d->width * 4;
    fill(d, p, stride);
    struct spa_meta_header *h = spa_buffer_find_meta_data(buf, SPA_META_Header, sizeof *h);
    if (h) {
        h->flags = 0;
        h->seq = d->seq++;
        h->pts = -1;
        h->dts_offset = 0;
    }
    struct spa_meta_cursor *mc = spa_buffer_find_meta_data(buf, SPA_META_Cursor, sizeof *mc);
    if (mc) {
        mc->id = 1;
        mc->flags = 0;
        mc->position.x = 100;
        mc->position.y = 60;
        mc->hotspot.x = 0;
        mc->hotspot.y = 0;
        mc->bitmap_offset = sizeof *mc;
        struct spa_meta_bitmap *bm = SPA_PTROFF(mc, mc->bitmap_offset, struct spa_meta_bitmap);
        bm->format = SPA_VIDEO_FORMAT_RGBA;
        bm->size.width = 16;
        bm->size.height = 16;
        bm->stride = 16 * 4;
        bm->offset = sizeof *bm;
        memset(SPA_PTROFF(bm, bm->offset, uint8_t), 0xff, 16 * 16 * 4);
    }
    buf->datas[0].chunk->offset = 0;
    buf->datas[0].chunk->size = d->height * stride;
    buf->datas[0].chunk->stride = stride;
    pw_stream_queue_buffer(d->stream, b);
}

static void on_state(void *userdata, enum pw_stream_state old, enum pw_stream_state state, const char *error)
{
    struct data *d = userdata;
    if (state == PW_STREAM_STATE_PAUSED && !d->printed) {
        printf("node %u\n", pw_stream_get_node_id(d->stream));
        fflush(stdout);
        d->printed = 1;
    }
    if (state == PW_STREAM_STATE_STREAMING) {
        struct timespec value = {0, 1}, interval = {0, 1000000000 / 30};
        pw_loop_update_timer(pw_main_loop_get_loop(d->loop), d->timer, &value, &interval, false);
    } else if (state == PW_STREAM_STATE_PAUSED) {
        pw_loop_update_timer(pw_main_loop_get_loop(d->loop), d->timer, NULL, NULL, false);
    } else if (state == PW_STREAM_STATE_ERROR) {
        fprintf(stderr, "pw_producer: %s\n", error ? error : "error");
    }
}

#define CURSOR_META_SIZE(w, h) (sizeof(struct spa_meta_cursor) + sizeof(struct spa_meta_bitmap) + (w) * (h) * 4)

static void on_param(void *userdata, uint32_t id, const struct spa_pod *param)
{
    struct data *d = userdata;
    if (!param || id != SPA_PARAM_Format)
        return;
    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof buffer);
    const struct spa_pod *params[3];
    params[0] = spa_pod_builder_add_object(
        &b, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers, SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(4, 2, 8),
        SPA_PARAM_BUFFERS_blocks, SPA_POD_Int(1), SPA_PARAM_BUFFERS_size, SPA_POD_Int(d->width * d->height * 4),
        SPA_PARAM_BUFFERS_stride, SPA_POD_Int(d->width * 4), SPA_PARAM_BUFFERS_dataType,
        SPA_POD_CHOICE_FLAGS_Int(1 << SPA_DATA_MemFd));
    params[1] = spa_pod_builder_add_object(&b, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta, SPA_PARAM_META_type,
                                           SPA_POD_Id(SPA_META_Header), SPA_PARAM_META_size,
                                           SPA_POD_Int(sizeof(struct spa_meta_header)));
    params[2] = spa_pod_builder_add_object(&b, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta, SPA_PARAM_META_type,
                                           SPA_POD_Id(SPA_META_Cursor), SPA_PARAM_META_size,
                                           SPA_POD_CHOICE_RANGE_Int(CURSOR_META_SIZE(16, 16), CURSOR_META_SIZE(1, 1),
                                                                    CURSOR_META_SIZE(64, 64)));
    pw_stream_update_params(d->stream, params, 3);
}

static const struct pw_stream_events events = {
    PW_VERSION_STREAM_EVENTS,
    .state_changed = on_state,
    .param_changed = on_param,
};

int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr, "usage: pw_producer NAME BGRx|RGBx WIDTH HEIGHT quarters|cyan\n");
        return 2;
    }
    struct data d = {0};
    d.format = !strcmp(argv[2], "RGBx") ? SPA_VIDEO_FORMAT_RGBx : SPA_VIDEO_FORMAT_BGRx;
    d.width = (uint32_t)atoi(argv[3]);
    d.height = (uint32_t)atoi(argv[4]);
    d.pattern = argv[5];
    pw_init(&argc, &argv);
    d.loop = pw_main_loop_new(NULL);
    d.timer = pw_loop_add_timer(pw_main_loop_get_loop(d.loop), on_timeout, &d);
    d.stream = pw_stream_new_simple(pw_main_loop_get_loop(d.loop), argv[1],
                                    pw_properties_new(PW_KEY_MEDIA_CLASS, "Video/Source", PW_KEY_NODE_NAME, argv[1],
                                                      NULL),
                                    &events, &d);
    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof buffer);
    struct spa_rectangle size = SPA_RECTANGLE(d.width, d.height);
    struct spa_fraction rate = SPA_FRACTION(30, 1);
    const struct spa_pod *params[1];
    params[0] = spa_pod_builder_add_object(
        &b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat, SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw), SPA_FORMAT_VIDEO_format, SPA_POD_Id(d.format),
        SPA_FORMAT_VIDEO_size, SPA_POD_Rectangle(&size), SPA_FORMAT_VIDEO_framerate, SPA_POD_Fraction(&rate));
    if (pw_stream_connect(d.stream, PW_DIRECTION_OUTPUT, PW_ID_ANY,
                          PW_STREAM_FLAG_DRIVER | PW_STREAM_FLAG_MAP_BUFFERS, params, 1) < 0) {
        fprintf(stderr, "pw_producer: can't connect\n");
        return 1;
    }
    pw_main_loop_run(d.loop);
    pw_stream_destroy(d.stream);
    pw_main_loop_destroy(d.loop);
    pw_deinit();
    return 0;
}
