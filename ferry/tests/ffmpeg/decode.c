/* SPDX-License-Identifier: GPL-3.0-or-later
 * A small player's decoding, as VLC's avcodec module and OBS's media
 * source use FFmpeg (freemac 1.233, Ferry 0.57.0): FFmpeg's libraries,
 * built as Mac dylibs by ferry/recipes/ffmpeg/build.sh, open each file
 * named, decode every stream on four threads, turn each picture into RGB
 * with swscale and each sound into 16-bit samples with swresample, and
 * print each stream's frame count and an MD5 of what came out. run.sh
 * makes the files with the same FFmpeg's own ffmpeg, from its test
 * sources, in codecs whose output is the same on every computer. */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/md5.h>
#include <libavutil/imgutils.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <stdio.h>
#include <string.h>

struct stream {
    AVCodecContext *dec;
    struct SwsContext *sws;
    SwrContext *swr;
    struct AVMD5 *md5;
    int frames;
    long samples;
};

static void take(struct stream *s, AVFrame *f)
{
    s->frames++;
    if (s->dec->codec_type == AVMEDIA_TYPE_VIDEO) {
        if (!s->sws)
            s->sws = sws_getContext(f->width, f->height, f->format, f->width, f->height, AV_PIX_FMT_RGB24,
                                    SWS_BILINEAR | SWS_BITEXACT | SWS_ACCURATE_RND, NULL, NULL, NULL);
        uint8_t *rgb[4];
        int pitch[4];
        av_image_alloc(rgb, pitch, f->width, f->height, AV_PIX_FMT_RGB24, 1);
        sws_scale(s->sws, (const uint8_t *const *)f->data, f->linesize, 0, f->height, rgb, pitch);
        av_md5_update(s->md5, rgb[0], pitch[0] * f->height);
        av_freep(&rgb[0]);
    } else {
        if (!s->swr) {
            AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
            swr_alloc_set_opts2(&s->swr, &stereo, AV_SAMPLE_FMT_S16, f->sample_rate, &f->ch_layout, f->format,
                                f->sample_rate, 0, NULL);
            swr_init(s->swr);
        }
        uint8_t buf[2 * 2 * 8192];
        uint8_t *out[1] = {buf};
        int got = swr_convert(s->swr, out, 8192, (const uint8_t **)f->extended_data, f->nb_samples);
        if (got > 0) {
            av_md5_update(s->md5, buf, got * 4);
            s->samples += got;
        }
    }
}

static void drain(struct stream *s, AVPacket *pkt, AVFrame *f)
{
    if (avcodec_send_packet(s->dec, pkt) < 0)
        return;
    while (avcodec_receive_frame(s->dec, f) == 0) {
        take(s, f);
        av_frame_unref(f);
    }
}

static int play(const char *path)
{
    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, path, NULL, NULL) < 0 || avformat_find_stream_info(fmt, NULL) < 0) {
        printf("%s: can't be opened\n", strrchr(path, '/') ? strrchr(path, '/') + 1 : path);
        return 1;
    }
    printf("%s: %s, %u streams, %.2f s\n", strrchr(path, '/') ? strrchr(path, '/') + 1 : path, fmt->iformat->name,
           fmt->nb_streams, fmt->duration / (double)AV_TIME_BASE);
    struct stream st[8];
    memset(st, 0, sizeof st);
    for (unsigned i = 0; i < fmt->nb_streams && i < 8; i++) {
        const AVCodec *c = avcodec_find_decoder(fmt->streams[i]->codecpar->codec_id);
        st[i].dec = avcodec_alloc_context3(c);
        avcodec_parameters_to_context(st[i].dec, fmt->streams[i]->codecpar);
        st[i].dec->thread_count = 4;
        st[i].dec->flags |= AV_CODEC_FLAG_BITEXACT;
        if (avcodec_open2(st[i].dec, c, NULL) < 0)
            printf("  stream %u: no decoder\n", i);
        st[i].md5 = av_md5_alloc();
        av_md5_init(st[i].md5);
    }
    AVPacket *pkt = av_packet_alloc();
    AVFrame *f = av_frame_alloc();
    while (av_read_frame(fmt, pkt) >= 0) {
        if (pkt->stream_index < 8)
            drain(&st[pkt->stream_index], pkt, f);
        av_packet_unref(pkt);
    }
    for (unsigned i = 0; i < fmt->nb_streams && i < 8; i++) {
        drain(&st[i], NULL, f);
        uint8_t sum[16];
        char hex[33];
        av_md5_final(st[i].md5, sum);
        for (int k = 0; k < 16; k++)
            snprintf(hex + 2 * k, 3, "%02x", sum[k]);
        if (st[i].dec->codec_type == AVMEDIA_TYPE_VIDEO)
            printf("  stream %u: %s video %dx%d, %d frames, RGB MD5 %s\n", i, st[i].dec->codec->name,
                   st[i].dec->width, st[i].dec->height, st[i].frames, hex);
        else
            printf("  stream %u: %s audio %d Hz, %d frames, %ld samples, PCM MD5 %s\n", i, st[i].dec->codec->name,
                   st[i].dec->sample_rate, st[i].frames, st[i].samples, hex);
        sws_freeContext(st[i].sws);
        swr_free(&st[i].swr);
        av_free(st[i].md5);
        avcodec_free_context(&st[i].dec);
    }
    av_frame_free(&f);
    av_packet_free(&pkt);
    avformat_close_input(&fmt);
    return 0;
}

int main(int argc, char **argv)
{
    printf("libavcodec %s, libavformat %s\n", AV_STRINGIFY(LIBAVCODEC_VERSION), AV_STRINGIFY(LIBAVFORMAT_VERSION));
    printf("the libraries' versions match the headers: %s\n",
           avcodec_version() == LIBAVCODEC_VERSION_INT && avformat_version() == LIBAVFORMAT_VERSION_INT ? "yes" : "NO");
    int rc = 0;
    for (int i = 1; i < argc; i++)
        rc |= play(argv[i]);
    return rc;
}
