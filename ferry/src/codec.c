/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Sound codecs for Ferry's Core Audio (freemac 1.264): AAC, ALAC, FLAC
 * and Opus encoding, and those and MP3, AC-3 and E-AC-3 decoding, done by
 * this system's FFmpeg (libavcodec, which freemac carries for GStreamer).
 * A Mac encodes AAC in AudioToolbox; HandBrake, OBS and many others ask
 * an AudioConverter for it. Core Audio (coreaudio/CACodec.m) calls the
 * small interface here, which hides FFmpeg's versions from it.
 *
 * FFmpeg's headers aren't part of the build, so the few structure fields
 * used are reached by their offsets, which differ between FFmpeg 5.1, 6,
 * 7 and 8 (libavcodec 59 to 62); they were read from each release's
 * public headers. Everything else goes through FFmpeg's calls. A system
 * without libavcodec, or with another version, has no codecs: Core Audio
 * then refuses compressed formats, as it did before.
 */
#include "ferry.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

struct ffoff {
    int codec_major;
    /* AVFrame */
    size_t fr_ch_layout;
    /* AVCodecContext */
    size_t cx_time_base, cx_extradata, cx_extradata_size, cx_sample_rate, cx_sample_fmt, cx_frame_size, cx_ch_layout,
        cx_initial_padding, cx_bit_rate;
};

static const struct ffoff offsets[] = {
    {59, 448, 100, 88, 96, 352, 360, 364, 920, 708, 56},
    {60, 448, 100, 88, 96, 352, 360, 364, 912, 700, 56},
    {61, 408, 84, 72, 80, 344, 348, 376, 352, 396, 56},
    {62, 384, 84, 72, 80, 344, 348, 376, 352, 396, 56},
};

/* AVFrame's and AVPacket's leading fields are the same in all of them */
enum { FR_DATA = 0, FR_LINESIZE = 64, FR_EXTENDED = 96, FR_NB_SAMPLES = 112, FR_FORMAT = 116, FR_PTS = 136 };
enum { PK_PTS = 8, PK_DATA = 24, PK_SIZE = 32 };
enum { S_U8 = 0, S_S16, S_S32, S_FLT, S_DBL, S_U8P, S_S16P, S_S32P, S_FLTP, S_DBLP };
#define AVERROR_EAGAIN (-11)
#define AVERROR_EOF (-0x20464F45) /* FFERRTAG('E','O','F',' ') */

static struct {
    const struct ffoff *off;
    void *(*find_encoder)(const char *);
    void *(*find_decoder)(const char *);
    void *(*alloc_context)(const void *);
    int (*open)(void *, const void *, void *);
    void (*free_context)(void **);
    int (*send_frame)(void *, const void *);
    int (*receive_packet)(void *, void *);
    int (*send_packet)(void *, const void *);
    int (*receive_frame)(void *, void *);
    void *(*packet_alloc)(void);
    void (*packet_free)(void **);
    void (*packet_unref)(void *);
    void *(*frame_alloc)(void);
    void (*frame_free)(void **);
    int (*frame_get_buffer)(void *, int);
    void (*frame_unref)(void *);
    void (*layout_default)(void *, int);
    void *(*mallocz)(size_t);
    void (*log_set_level)(int);
    int (*opt_set_int)(void *, const char *, int64_t, int);
} ff;

static void open_ffmpeg(void)
{
    static const char *const codecs[] = {"libavcodec.so.62", "libavcodec.so.61", "libavcodec.so.60",
                                         "libavcodec.so.59"};
    static const char *const utils[] = {"libavutil.so.60", "libavutil.so.59", "libavutil.so.58", "libavutil.so.57"};
    const char *off = getenv("FERRY_NO_FFMPEG");
    if (off && *off)
        return;
    for (int i = 0; i < 4; i++) {
        void *u = dlopen(utils[i], RTLD_NOW | RTLD_LOCAL);
        if (!u)
            continue;
        void *c = dlopen(codecs[i], RTLD_NOW | RTLD_LOCAL);
        if (!c) {
            dlclose(u);
            continue;
        }
        unsigned (*version)(void) = (unsigned (*)(void))dlsym(c, "avcodec_version");
        int major = version ? (int)(version() >> 16) : 0;
        const struct ffoff *o = NULL;
        for (size_t k = 0; k < sizeof offsets / sizeof *offsets; k++)
            if (offsets[k].codec_major == major)
                o = &offsets[k];
        if (!o)
            return;
#define C(field, lib, name) *(void **)&ff.field = dlsym(lib, name)
        C(find_encoder, c, "avcodec_find_encoder_by_name");
        C(find_decoder, c, "avcodec_find_decoder_by_name");
        C(alloc_context, c, "avcodec_alloc_context3");
        C(open, c, "avcodec_open2");
        C(free_context, c, "avcodec_free_context");
        C(send_frame, c, "avcodec_send_frame");
        C(receive_packet, c, "avcodec_receive_packet");
        C(send_packet, c, "avcodec_send_packet");
        C(receive_frame, c, "avcodec_receive_frame");
        C(packet_alloc, c, "av_packet_alloc");
        C(packet_free, c, "av_packet_free");
        C(packet_unref, c, "av_packet_unref");
        C(frame_alloc, u, "av_frame_alloc");
        C(frame_free, u, "av_frame_free");
        C(frame_get_buffer, u, "av_frame_get_buffer");
        C(frame_unref, u, "av_frame_unref");
        C(layout_default, u, "av_channel_layout_default");
        C(mallocz, u, "av_mallocz");
        C(log_set_level, u, "av_log_set_level");
        C(opt_set_int, u, "av_opt_set_int");
#undef C
        void **all = (void **)&ff.find_encoder;
        for (size_t k = 0; k < (sizeof ff - sizeof ff.off) / sizeof(void *); k++)
            if (!all[k])
                return;
        if (!getenv("FERRY_VERBOSE"))
            ff.log_set_level(16); /* AV_LOG_ERROR */
        ff.off = o;
        return;
    }
}

static int ready(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, open_ffmpeg);
    return ff.off != NULL;
}

#define AT(p, off, type) (*(type *)((char *)(p) + (off)))

struct ferry_acodec {
    int encode;
    void *ctx, *frame, *packet;
    int rate, channels, sample_fmt, frame_size;
    int64_t pts;
    float *pending; /* encoding: input frames not yet sent */
    int npending, cap;
    int flushed, ended;
    /* decoding: frames received and not yet taken */
    float *out;
    int nout, outpos, outcap;
};

/* Mac format IDs */
#define FOURCC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

static const char *encoder_for(uint32_t id, int *fmt)
{
    switch (id) {
    case FOURCC('a', 'a', 'c', ' '): *fmt = S_FLTP; return "aac";
    case FOURCC('a', 'l', 'a', 'c'): *fmt = S_S16P; return "alac";
    case FOURCC('f', 'l', 'a', 'c'): *fmt = S_S16; return "flac";
    case FOURCC('o', 'p', 'u', 's'): *fmt = S_FLT; return "libopus";
    }
    return NULL;
}

static const char *decoder_for(uint32_t id)
{
    switch (id) {
    case FOURCC('a', 'a', 'c', ' '): return "aac";
    case FOURCC('.', 'm', 'p', '3'): return "mp3float";
    case FOURCC('.', 'm', 'p', '2'): return "mp2float";
    case FOURCC('a', 'l', 'a', 'c'): return "alac";
    case FOURCC('f', 'l', 'a', 'c'): return "flac";
    case FOURCC('o', 'p', 'u', 's'): return "libopus";
    case FOURCC('a', 'c', '-', '3'): return "ac3";
    case FOURCC('e', 'c', '-', '3'): return "eac3";
    }
    return NULL;
}

int ferry_acodec_available(int encode, uint32_t id)
{
    if (!ready())
        return 0;
    int fmt;
    const char *name = encode ? encoder_for(id, &fmt) : decoder_for(id);
    if (!name)
        return 0;
    void *codec = encode ? ff.find_encoder(name) : ff.find_decoder(name);
    if (!codec && id == FOURCC('o', 'p', 'u', 's'))
        codec = encode ? NULL : ff.find_decoder("opus");
    return codec != NULL;
}

void ferry_acodec_close(struct ferry_acodec *h)
{
    if (!h)
        return;
    if (h->ctx)
        ff.free_context(&h->ctx);
    if (h->frame)
        ff.frame_free(&h->frame);
    if (h->packet)
        ff.packet_free(&h->packet);
    free(h->pending);
    free(h->out);
    free(h);
}

/* encode: 1 to encode float frames into id, 0 to decode id into float
 * frames. cookie: a decoder's codec configuration (AAC's
 * AudioSpecificConfig, ALAC's or FLAC's), if any. */
struct ferry_acodec *ferry_acodec_open(int encode, uint32_t id, int rate, int channels, int bit_rate,
                                       const uint8_t *cookie, int cookie_len)
{
    if (!ready() || rate <= 0 || channels <= 0 || channels > 8)
        return NULL;
    int fmt = S_FLT;
    const char *name = encode ? encoder_for(id, &fmt) : decoder_for(id);
    if (!name)
        return NULL;
    void *codec = encode ? ff.find_encoder(name) : ff.find_decoder(name);
    if (!codec && id == FOURCC('o', 'p', 'u', 's') && !encode)
        codec = ff.find_decoder("opus");
    if (!codec)
        return NULL;
    struct ferry_acodec *h = calloc(1, sizeof *h);
    if (!h)
        return NULL;
    const struct ffoff *o = ff.off;
    h->encode = encode;
    h->rate = rate;
    h->channels = channels;
    h->sample_fmt = fmt;
    h->ctx = ff.alloc_context(codec);
    h->frame = ff.frame_alloc();
    h->packet = ff.packet_alloc();
    if (!h->ctx || !h->frame || !h->packet) {
        ferry_acodec_close(h);
        return NULL;
    }
    AT(h->ctx, o->cx_sample_rate, int) = rate;
    ff.layout_default((char *)h->ctx + o->cx_ch_layout, channels);
    AT(h->ctx, o->cx_time_base, int) = 1;
    AT(h->ctx, o->cx_time_base + 4, int) = rate;
    if (encode) {
        AT(h->ctx, o->cx_sample_fmt, int) = fmt;
        AT(h->ctx, o->cx_bit_rate, int64_t) = bit_rate > 0 ? bit_rate : (channels > 1 ? 128000 : 64000);
    } else if (cookie && cookie_len > 0) {
        uint8_t *extra = ff.mallocz((size_t)cookie_len + 64);
        if (extra) {
            memcpy(extra, cookie, (size_t)cookie_len);
            AT(h->ctx, o->cx_extradata, uint8_t *) = extra;
            AT(h->ctx, o->cx_extradata_size, int) = cookie_len;
        }
    }
    if (ff.open(h->ctx, codec, NULL) < 0) {
        ferry_acodec_close(h);
        return NULL;
    }
    h->frame_size = AT(h->ctx, o->cx_frame_size, int);
    if (encode && h->frame_size <= 0)
        h->frame_size = 4096;
    return h;
}

/* What an encoder makes: its frames per packet, the frames it puts in
 * front (priming), and its configuration (AAC's AudioSpecificConfig). */
int ferry_acodec_info(struct ferry_acodec *h, int *frame_size, int *padding, uint8_t *config, int *config_len)
{
    if (!h)
        return -1;
    const struct ffoff *o = ff.off;
    if (frame_size)
        *frame_size = h->frame_size;
    if (padding)
        *padding = AT(h->ctx, o->cx_initial_padding, int);
    if (config_len) {
        int n = AT(h->ctx, o->cx_extradata_size, int);
        const uint8_t *e = AT(h->ctx, o->cx_extradata, const uint8_t *);
        if (!e || n < 0)
            n = 0;
        if (config && n > *config_len)
            n = *config_len;
        if (config && n)
            memcpy(config, e, (size_t)n);
        *config_len = n;
    }
    return 0;
}

/* as Core Audio's own PCM conversion: 32768 steps, rounded, so 16-bit
 * samples go through floats and back unchanged */
static int16_t to_s16(float v)
{
    long i = lrintf(v * 32768.0f);
    return (int16_t)(i > 32767 ? 32767 : i < -32768 ? -32768 : i);
}

/* Sends n of the waiting input frames as one frame to the encoder. */
static int send_frames(struct ferry_acodec *h, int n)
{
    void *f = h->frame;
    ff.frame_unref(f);
    AT(f, FR_NB_SAMPLES, int) = n;
    AT(f, FR_FORMAT, int) = h->sample_fmt;
    ff.layout_default((char *)f + ff.off->fr_ch_layout, h->channels);
    if (ff.frame_get_buffer(f, 0) < 0)
        return -1;
    AT(f, FR_PTS, int64_t) = h->pts;
    h->pts += n;
    uint8_t **planes = AT(f, FR_EXTENDED, uint8_t **);
    int ch = h->channels;
    for (int i = 0; i < n; i++)
        for (int c = 0; c < ch; c++) {
            float v = h->pending[(size_t)i * ch + c];
            switch (h->sample_fmt) {
            case S_FLTP: ((float *)planes[c])[i] = v; break;
            case S_FLT: ((float *)planes[0])[(size_t)i * ch + c] = v; break;
            case S_S16P: ((int16_t *)planes[c])[i] = to_s16(v); break;
            case S_S16: ((int16_t *)planes[0])[(size_t)i * ch + c] = to_s16(v); break;
            }
        }
    int err = ff.send_frame(h->ctx, f);
    memmove(h->pending, h->pending + (size_t)n * ch, (size_t)(h->npending - n) * ch * sizeof(float));
    h->npending -= n;
    return err < 0 ? -1 : 0;
}

/* Encoding: give frames (interleaved floats); NULL or 0 frames ends the
 * stream. Decoding: give a packet's bytes; NULL or 0 ends the stream. */
int ferry_acodec_send(struct ferry_acodec *h, const void *data, int count)
{
    if (!h || h->flushed)
        return -1;
    if (h->encode) {
        if (data && count > 0) {
            if (h->npending + count > h->cap) {
                int cap = (h->npending + count) * 2;
                float *p = realloc(h->pending, (size_t)cap * h->channels * sizeof(float));
                if (!p)
                    return -1;
                h->pending = p;
                h->cap = cap;
            }
            memcpy(h->pending + (size_t)h->npending * h->channels, data, (size_t)count * h->channels * sizeof(float));
            h->npending += count;
            while (h->npending >= h->frame_size)
                if (send_frames(h, h->frame_size) < 0)
                    return -1;
            return 0;
        }
        if (h->npending > 0 && send_frames(h, h->npending) < 0)
            return -1;
        h->flushed = 1;
        return ff.send_frame(h->ctx, NULL) < 0 ? -1 : 0;
    }
    void *p = h->packet;
    ff.packet_unref(p);
    if (data && count > 0) {
        AT(p, PK_DATA, const void *) = data;
        AT(p, PK_SIZE, int) = count;
        int err = ff.send_packet(h->ctx, p);
        AT(p, PK_DATA, const void *) = NULL;
        AT(p, PK_SIZE, int) = 0;
        return err < 0 && err != AVERROR_EAGAIN ? -1 : 0;
    }
    h->flushed = 1;
    return ff.send_packet(h->ctx, NULL) < 0 ? -1 : 0;
}

/* Encoding: the next packet into out (up to cap bytes): its size, 0 if
 * the encoder needs more input, -1 at the end, -2 if out is too small.
 * Decoding: up to cap frames (interleaved floats, the codec's channels):
 * how many, 0 if it needs another packet, -1 at the end. */
int ferry_acodec_receive(struct ferry_acodec *h, void *out, int cap, int *channels)
{
    if (!h || h->ended)
        return -1;
    if (h->encode) {
        void *p = h->packet;
        int err = ff.receive_packet(h->ctx, p);
        if (err == AVERROR_EAGAIN)
            return 0;
        if (err < 0) {
            h->ended = 1;
            return -1;
        }
        int size = AT(p, PK_SIZE, int);
        if (size > cap) {
            ff.packet_unref(p);
            return -2;
        }
        memcpy(out, AT(p, PK_DATA, const void *), (size_t)size);
        ff.packet_unref(p);
        return size;
    }
    /* decoding: refill from the decoder when what we hold is used up */
    if (h->outpos >= h->nout) {
        void *f = h->frame;
        int err = ff.receive_frame(h->ctx, f);
        if (err == AVERROR_EAGAIN)
            return 0;
        if (err < 0) {
            h->ended = 1;
            return -1;
        }
        int n = AT(f, FR_NB_SAMPLES, int), fmt = AT(f, FR_FORMAT, int);
        int ch = AT(f, ff.off->fr_ch_layout + 4, int);
        if (ch <= 0 || ch > 8)
            ch = h->channels;
        h->channels = ch;
        if (n > h->outcap) {
            float *o = realloc(h->out, (size_t)n * 8 * sizeof(float));
            if (!o)
                return -1;
            h->out = o;
            h->outcap = n;
        }
        uint8_t **planes = AT(f, FR_EXTENDED, uint8_t **);
        for (int i = 0; i < n; i++)
            for (int c = 0; c < ch; c++) {
                size_t k = (size_t)i * ch + c;
                float v = 0;
                switch (fmt) {
                case S_U8: v = (planes[0][k] - 128) / 128.0f; break;
                case S_S16: v = ((int16_t *)planes[0])[k] / 32768.0f; break;
                case S_S32: v = ((int32_t *)planes[0])[k] / 2147483648.0f; break;
                case S_FLT: v = ((float *)planes[0])[k]; break;
                case S_DBL: v = (float)((double *)planes[0])[k]; break;
                case S_U8P: v = (planes[c][i] - 128) / 128.0f; break;
                case S_S16P: v = ((int16_t *)planes[c])[i] / 32768.0f; break;
                case S_S32P: v = ((int32_t *)planes[c])[i] / 2147483648.0f; break;
                case S_FLTP: v = ((float *)planes[c])[i]; break;
                case S_DBLP: v = (float)((double *)planes[c])[i]; break;
                }
                h->out[k] = v;
            }
        ff.frame_unref(f);
        h->nout = n;
        h->outpos = 0;
    }
    int n = h->nout - h->outpos;
    if (n > cap)
        n = cap;
    memcpy(out, h->out + (size_t)h->outpos * h->channels, (size_t)n * h->channels * sizeof(float));
    h->outpos += n;
    if (channels)
        *channels = h->channels;
    return n;
}
