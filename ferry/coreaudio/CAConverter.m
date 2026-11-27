/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Audio converters (freemac 1.234, Ferry 0.58.0), written from Apple's
 * public documentation of AudioConverter.h. Ferry's converters take linear
 * PCM to linear PCM: any integer or float sample format either way round,
 * interleaved or not, to any channel count (through a channel map, or by
 * default channel for channel, with mono spread to left and right and
 * stereo mixed down to mono), and any sample rate, by linear
 * interpolation. Since freemac 1.264 (Ferry 0.87.0) a converter also
 * encodes linear PCM to AAC, Apple Lossless, FLAC or Opus, and decodes
 * those, MP3 and AC-3 to linear PCM, with this system's FFmpeg (through
 * src/codec.c), as HandBrake and OBS ask AudioToolbox to. Other
 * compressed formats, and all of them on a system without FFmpeg, are
 * refused with kAudioConverterErr_FormatNotSupported.
 */
#import "CAInternal.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

struct OpaqueAudioConverter {
    AudioStreamBasicDescription in, out;
    ca_pcm pi, po;
    SInt32 map[CA_MAX_CHANNELS]; /* for each output channel, its input channel or -1 */
    int has_map;
    UInt32 quality, complexity, prime_method;
    AudioChannelLayout *layout[2]; /* the input's, the output's */
    UInt32 layout_size[2];
    double step; /* input frames for each output frame */
    double pos;  /* where the next output frame falls in the queue */
    float *queue; /* input frames, in the output's channels */
    UInt32 queued, cap;
    /* AudioConverterFillBuffer's input */
    AudioConverterInputDataProc simple_proc;
    void *simple_user;
    /* a codec's converter: it encodes (out is compressed) or decodes (in
     * is), with a PCM converter between the program's PCM and the codec's
     * interleaved floats */
    struct ferry_acodec *codec;
    int encoding, decoding, started, ended;
    AudioConverterRef pcm;
    UInt32 bit_rate, rate_mode, vbr_quality, frames_per_packet, padding;
    UInt8 *cookie;
    UInt32 cookie_size;
    AudioConverterComplexInputDataProc user_proc;
    void *user_data;
    OSStatus user_err;
};

struct ferry_acodec;
int ferry_acodec_available(int encode, uint32_t id);
struct ferry_acodec *ferry_acodec_open(int encode, uint32_t id, int rate, int channels, int bit_rate,
                                       const uint8_t *cookie, int cookie_len);
int ferry_acodec_info(struct ferry_acodec *h, int *frame_size, int *padding, uint8_t *config, int *config_len);
int ferry_acodec_send(struct ferry_acodec *h, const void *data, int count);
int ferry_acodec_receive(struct ferry_acodec *h, void *out, int cap, int *channels);
void ferry_acodec_close(struct ferry_acodec *h);
static OSStatus codec_new(const AudioStreamBasicDescription *from, const AudioStreamBasicDescription *to,
                          AudioConverterRef *out);
static OSStatus codec_fill(AudioConverterRef c, AudioConverterComplexInputDataProc proc, void *user,
                           UInt32 *io_packets, AudioBufferList *out_list, AudioStreamPacketDescription *out_packets);
static OSStatus codec_property(AudioConverterRef c, AudioConverterPropertyID id, UInt32 *size, void *data,
                               Boolean *w, int *handled);
static OSStatus codec_set_property(AudioConverterRef c, AudioConverterPropertyID id, UInt32 size, const void *data,
                                   int *handled);

static int pcm_ok(const AudioStreamBasicDescription *f, ca_pcm *p)
{
    return f && f->mFormatID == kAudioFormatLinearPCM && !ca_pcm_parse(f, p) && f->mSampleRate > 0 &&
           f->mSampleRate <= 768000;
}

OSStatus AudioConverterNew(const AudioStreamBasicDescription *from, const AudioStreamBasicDescription *to,
                           AudioConverterRef *out)
{
    if (!from || !to || !out)
        return kAudio_ParamError;
    *out = NULL;
    ca_pcm pi, po;
    if (from->mFormatID != kAudioFormatLinearPCM || to->mFormatID != kAudioFormatLinearPCM)
        return codec_new(from, to, out);
    if (!pcm_ok(from, &pi) || !pcm_ok(to, &po))
        return kAudioConverterErr_FormatNotSupported;
    if (pi.channels > CA_MAX_CHANNELS || po.channels > CA_MAX_CHANNELS)
        return kAudioConverterErr_FormatNotSupported;
    AudioConverterRef c = calloc(1, sizeof *c);
    if (!c)
        return kAudio_MemFullError;
    c->in = *from;
    c->out = *to;
    c->pi = pi;
    c->po = po;
    c->quality = kAudioConverterQuality_High;
    c->complexity = kAudioConverterSampleRateConverterComplexity_Linear;
    c->prime_method = kConverterPrimeMethod_Normal;
    c->step = from->mSampleRate / to->mSampleRate;
    *out = c;
    return noErr;
}

OSStatus AudioConverterNewSpecific(const AudioStreamBasicDescription *from, const AudioStreamBasicDescription *to,
                                   UInt32 n, const AudioClassDescription *classes, AudioConverterRef *out)
{
    return AudioConverterNew(from, to, out);
}

OSStatus AudioConverterDispose(AudioConverterRef c)
{
    if (!c)
        return kAudio_ParamError;
    if (c->codec)
        ferry_acodec_close(c->codec);
    if (c->pcm)
        AudioConverterDispose(c->pcm);
    free(c->cookie);
    free(c->queue);
    free(c->layout[0]);
    free(c->layout[1]);
    free(c);
    return noErr;
}

OSStatus AudioConverterReset(AudioConverterRef c)
{
    if (!c)
        return kAudio_ParamError;
    c->queued = 0;
    c->pos = 0;
    if (c->pcm)
        AudioConverterReset(c->pcm);
    if (c->codec && c->started) {
        /* a codec starts over */
        ferry_acodec_close(c->codec);
        c->codec = NULL;
        c->started = c->ended = 0;
    }
    return noErr;
}

/* one frame of input channels to the output's */
static void map_frame(AudioConverterRef c, const float *in, float *out)
{
    UInt32 ic = c->pi.channels, oc = c->po.channels;
    if (c->has_map) {
        for (UInt32 k = 0; k < oc; k++)
            out[k] = c->map[k] >= 0 && (UInt32)c->map[k] < ic ? in[c->map[k]] : 0.0f;
        return;
    }
    if (ic == 1 && oc >= 2) {
        out[0] = out[1] = in[0];
        for (UInt32 k = 2; k < oc; k++)
            out[k] = 0;
        return;
    }
    if (ic == 2 && oc == 1) {
        out[0] = (in[0] + in[1]) * 0.5f;
        return;
    }
    for (UInt32 k = 0; k < oc; k++)
        out[k] = k < ic ? in[k] : 0.0f;
}

static OSStatus convert_frames(AudioConverterRef c, const float *in, UInt32 frames, float *out)
{
    for (UInt32 i = 0; i < frames; i++)
        map_frame(c, in + (size_t)i * c->pi.channels, out + (size_t)i * c->po.channels);
    return noErr;
}

static int append(AudioConverterRef c, const float *mapped, UInt32 frames)
{
    UInt32 oc = c->po.channels;
    if (c->queued + frames > c->cap) {
        UInt32 cap = (c->queued + frames) * 2;
        float *q = realloc(c->queue, (size_t)cap * oc * sizeof(float));
        if (!q)
            return 0;
        c->queue = q;
        c->cap = cap;
    }
    memcpy(c->queue + (size_t)c->queued * oc, mapped, (size_t)frames * oc * sizeof(float));
    c->queued += frames;
    return 1;
}

/* makes up to want output frames from the queue; at the end of the input,
 * the last frame stands in for the one after it */
static UInt32 produce(AudioConverterRef c, float *out, UInt32 want, int ending)
{
    UInt32 oc = c->po.channels, made = 0;
    while (made < want) {
        UInt32 i = (UInt32)c->pos;
        double frac = c->pos - i;
        int exact = frac < 1e-9;
        if (i >= c->queued || (!exact && i + 1 >= c->queued && !ending))
            break;
        const float *a = c->queue + (size_t)i * oc;
        const float *b = i + 1 < c->queued ? a + oc : a;
        float *o = out + (size_t)made * oc;
        for (UInt32 k = 0; k < oc; k++)
            o[k] = exact ? a[k] : (float)(a[k] + (b[k] - a[k]) * frac);
        made++;
        c->pos += c->step;
    }
    /* drop what no later frame needs */
    UInt32 used = (UInt32)c->pos;
    if (used > c->queued)
        used = c->queued;
    if (used) {
        memmove(c->queue, c->queue + (size_t)used * oc, (size_t)(c->queued - used) * oc * sizeof(float));
        c->queued -= used;
        c->pos -= used;
    }
    return made;
}

OSStatus AudioConverterFillComplexBuffer(AudioConverterRef c, AudioConverterComplexInputDataProc proc, void *user,
                                         UInt32 *io_packets, AudioBufferList *out_list,
                                         AudioStreamPacketDescription *out_packets)
{
    if (!c || !proc || !io_packets || !out_list)
        return kAudio_ParamError;
    if (c->encoding || c->decoding)
        return codec_fill(c, proc, user, io_packets, out_list, out_packets);
    UInt32 want = *io_packets, oc = c->po.channels, ic = c->pi.channels;
    /* no more than the output buffers hold */
    UInt32 room = want;
    UInt32 nbuf = c->po.non_interleaved ? oc : 1;
    if (out_list->mNumberBuffers < nbuf)
        return kAudio_ParamError;
    for (UInt32 b = 0; b < nbuf; b++) {
        UInt32 fits = out_list->mBuffers[b].mDataByteSize / c->po.bytes_per_frame;
        if (fits < room)
            room = fits;
    }
    want = room;
    *io_packets = 0;
    if (!want)
        return noErr;
    float *made = malloc((size_t)want * oc * sizeof(float));
    if (!made)
        return kAudio_MemFullError;
    UInt32 total = 0;
    OSStatus status = noErr;
    int ending = 0;
    UInt32 in_bufs = c->pi.non_interleaved ? ic : 1;
    AudioBufferList *in_list = calloc(1, offsetof(AudioBufferList, mBuffers) + in_bufs * sizeof(AudioBuffer));
    while (total < want) {
        total += produce(c, made + (size_t)total * oc, want - total, ending);
        if (total >= want || ending || status)
            break;
        UInt32 n = (UInt32)ceil((want - total) * c->step) + 2;
        in_list->mNumberBuffers = in_bufs;
        for (UInt32 b = 0; b < in_bufs; b++) {
            in_list->mBuffers[b].mNumberChannels = c->pi.non_interleaved ? 1 : ic;
            in_list->mBuffers[b].mDataByteSize = 0;
            in_list->mBuffers[b].mData = NULL;
        }
        AudioStreamPacketDescription *descs = NULL;
        OSStatus err = proc(c, &n, in_list, &descs, user);
        if (n) {
            /* the buffers say how much they really hold */
            UInt32 have = n;
            for (UInt32 b = 0; b < in_list->mNumberBuffers && b < in_bufs; b++) {
                UInt32 h = in_list->mBuffers[b].mDataByteSize / c->pi.bytes_per_frame;
                if (h < have)
                    have = h;
            }
            if (have) {
                float *raw = malloc((size_t)have * ic * sizeof(float));
                float *mapped = malloc((size_t)have * oc * sizeof(float));
                if (raw && mapped) {
                    ca_pcm_to_float(&c->pi, in_list, have, raw);
                    convert_frames(c, raw, have, mapped);
                    append(c, mapped, have);
                }
                free(raw);
                free(mapped);
            }
        }
        if (err)
            status = err; /* what is made so far comes back, with the input's error */
        else if (!n)
            ending = 1;
    }
    free(in_list);
    ca_pcm_from_float(&c->po, made, total, out_list);
    free(made);
    *io_packets = total;
    if (out_packets && total) {
        out_packets[0].mStartOffset = 0;
        out_packets[0].mVariableFramesInPacket = 0;
        out_packets[0].mDataByteSize = total * c->po.bytes_per_frame;
    }
    return status;
}

typedef struct list_source {
    const AudioBufferList *list;
    UInt32 frames;
    int given;
} list_source;

static OSStatus from_list(AudioConverterRef c, UInt32 *n, AudioBufferList *io, AudioStreamPacketDescription **d,
                          void *user)
{
    list_source *s = user;
    if (s->given) {
        *n = 0;
        return noErr;
    }
    s->given = 1;
    for (UInt32 b = 0; b < io->mNumberBuffers && b < s->list->mNumberBuffers; b++)
        io->mBuffers[b] = s->list->mBuffers[b];
    *n = s->frames;
    return noErr;
}

OSStatus AudioConverterConvertComplexBuffer(AudioConverterRef c, UInt32 frames, const AudioBufferList *in,
                                            AudioBufferList *out)
{
    if (!c || !in || !out)
        return kAudio_ParamError;
    if (c->encoding || c->decoding)
        return kAudioConverterErr_OperationNotSupported;
    if (c->in.mSampleRate != c->out.mSampleRate)
        return kAudioConverterErr_InvalidInputSize; /* only FillComplexBuffer converts rates */
    UInt32 bufs = c->pi.non_interleaved ? c->pi.channels : 1;
    if (in->mNumberBuffers < bufs)
        return kAudio_ParamError;
    list_source s = {in, frames, 0};
    UInt32 n = frames;
    OSStatus err = AudioConverterFillComplexBuffer(c, from_list, &s, &n, out, NULL);
    c->queued = 0;
    c->pos = 0;
    return err;
}

OSStatus AudioConverterConvertBuffer(AudioConverterRef c, UInt32 in_size, const void *in, UInt32 *out_size, void *out)
{
    if (!c || !in || !out_size || !out)
        return kAudio_ParamError;
    if (c->encoding || c->decoding)
        return kAudioConverterErr_OperationNotSupported;
    if (c->pi.non_interleaved || c->po.non_interleaved)
        return kAudioConverterErr_FormatNotSupported;
    if (c->in.mSampleRate != c->out.mSampleRate)
        return kAudioConverterErr_InvalidInputSize;
    UInt32 frames = in_size / c->pi.bytes_per_frame;
    if (frames * c->po.bytes_per_frame > *out_size)
        return kAudioConverterErr_InvalidOutputSize;
    float *raw = malloc((size_t)frames * c->pi.channels * sizeof(float) + 1);
    float *mapped = malloc((size_t)frames * c->po.channels * sizeof(float) + 1);
    if (!raw || !mapped) {
        free(raw);
        free(mapped);
        return kAudio_MemFullError;
    }
    ca_bytes_to_float(&c->pi, in, frames, raw);
    convert_frames(c, raw, frames, mapped);
    ca_bytes_from_float(&c->po, mapped, frames, out);
    free(raw);
    free(mapped);
    *out_size = frames * c->po.bytes_per_frame;
    return noErr;
}

static OSStatus from_simple(AudioConverterRef c, UInt32 *n, AudioBufferList *io, AudioStreamPacketDescription **d,
                            void *user)
{
    UInt32 size = *n * c->pi.bytes_per_frame;
    void *data = NULL;
    OSStatus err = c->simple_proc(c, &size, &data, c->simple_user);
    io->mBuffers[0].mData = data;
    io->mBuffers[0].mDataByteSize = data ? size : 0;
    *n = data ? size / c->pi.bytes_per_frame : 0;
    return err;
}

OSStatus AudioConverterFillBuffer(AudioConverterRef c, AudioConverterInputDataProc proc, void *user,
                                  UInt32 *io_size, void *out)
{
    if (!c || !proc || !io_size || !out)
        return kAudio_ParamError;
    if (c->encoding || c->decoding)
        return kAudioConverterErr_OperationNotSupported;
    if (c->pi.non_interleaved || c->po.non_interleaved)
        return kAudioConverterErr_FormatNotSupported;
    c->simple_proc = proc;
    c->simple_user = user;
    AudioBufferList l = {1, {{c->po.channels, *io_size, out}}};
    UInt32 n = *io_size / c->po.bytes_per_frame;
    OSStatus err = AudioConverterFillComplexBuffer(c, from_simple, NULL, &n, &l, NULL);
    *io_size = n * c->po.bytes_per_frame;
    return err;
}

/* ---- properties ---------------------------------------------------------------------------- */

static OSStatus property(AudioConverterRef c, AudioConverterPropertyID id, UInt32 *size, void *data, Boolean *w)
{
    if (c->encoding || c->decoding) {
        int handled = 0;
        OSStatus err = codec_property(c, id, size, data, w, &handled);
        if (handled)
            return err;
    }
    UInt32 v32 = 0;
    const void *from = &v32;
    UInt32 need = 4;
    Boolean writable = 0;
    AudioConverterPrimeInfo prime = {0, 0};
    switch (id) {
    case kAudioConverterCurrentInputStreamDescription:
        from = &c->in;
        need = sizeof c->in;
        break;
    case kAudioConverterCurrentOutputStreamDescription:
        from = &c->out;
        need = sizeof c->out;
        break;
    case kAudioConverterPropertyMinimumInputBufferSize:
    case kAudioConverterPropertyMaximumInputPacketSize: v32 = c->pi.bytes_per_frame; break;
    case kAudioConverterPropertyMinimumOutputBufferSize:
    case kAudioConverterPropertyMaximumOutputPacketSize: v32 = c->po.bytes_per_frame; break;
    case kAudioConverterPropertyMaximumInputBufferSize: v32 = 0xFFFFFFFF; break;
    case kAudioConverterPropertyCalculateInputBufferSize:
    case kAudioConverterPropertyCalculateOutputBufferSize: {
        /* in and out: the size given becomes the size on the other side */
        if (!data) {
            need = 4;
            writable = 0;
            break;
        }
        if (*size < 4)
            return kAudioConverterErr_BadPropertySizeError;
        UInt32 given = *(UInt32 *)data;
        if (id == kAudioConverterPropertyCalculateInputBufferSize)
            v32 = (UInt32)ceil((double)(given / c->po.bytes_per_frame) * c->step) * c->pi.bytes_per_frame;
        else
            v32 = (UInt32)floor((double)(given / c->pi.bytes_per_frame) / c->step) * c->po.bytes_per_frame;
        break;
    }
    case kAudioConverterSampleRateConverterComplexity:
        v32 = c->complexity;
        writable = 1;
        break;
    case kAudioConverterSampleRateConverterQuality:
    case kAudioConverterCodecQuality:
        v32 = c->quality;
        writable = 1;
        break;
    case kAudioConverterPrimeMethod:
        v32 = c->prime_method;
        writable = 1;
        break;
    case kAudioConverterPrimeInfo:
        from = &prime;
        need = sizeof prime;
        writable = 1;
        break;
    case kAudioConverterChannelMap: {
        static SInt32 identity[CA_MAX_CHANNELS];
        for (int i = 0; i < CA_MAX_CHANNELS; i++)
            identity[i] = i < (int)c->pi.channels ? i : -1;
        from = c->has_map ? c->map : identity;
        need = c->po.channels * sizeof(SInt32);
        writable = 1;
        break;
    }
    case kAudioConverterInputChannelLayout:
    case kAudioConverterOutputChannelLayout: {
        int k = id == kAudioConverterOutputChannelLayout;
        if (!c->layout[k])
            return kAudioConverterErr_PropertyNotSupported;
        from = c->layout[k];
        need = c->layout_size[k];
        writable = 1;
        break;
    }
    case kAudioConverterPropertyDithering:
    case kAudioConverterPropertyDitherBitDepth:
    case kAudioConverterPropertyBitDepthHint: writable = 1; break;
    default: return kAudioConverterErr_PropertyNotSupported;
    }
    if (w)
        *w = writable;
    if (data) {
        if (*size < need)
            return kAudioConverterErr_BadPropertySizeError;
        memcpy(data, from, need);
    }
    *size = need;
    return noErr;
}

OSStatus AudioConverterGetPropertyInfo(AudioConverterRef c, AudioConverterPropertyID id, UInt32 *size,
                                       Boolean *writable)
{
    if (!c)
        return kAudio_ParamError;
    UInt32 n = 0;
    OSStatus err = property(c, id, &n, NULL, writable);
    if (!err && size)
        *size = n;
    return err;
}

OSStatus AudioConverterGetProperty(AudioConverterRef c, AudioConverterPropertyID id, UInt32 *size, void *data)
{
    if (!c || !size || !data)
        return kAudio_ParamError;
    return property(c, id, size, data, NULL);
}

OSStatus AudioConverterSetProperty(AudioConverterRef c, AudioConverterPropertyID id, UInt32 size, const void *data)
{
    if (!c || (!data && size))
        return kAudio_ParamError;
    if (c->encoding || c->decoding) {
        int handled = 0;
        OSStatus err = codec_set_property(c, id, size, data, &handled);
        if (handled)
            return err;
    }
    switch (id) {
    case kAudioConverterSampleRateConverterComplexity:
    case kAudioConverterSampleRateConverterQuality:
    case kAudioConverterCodecQuality:
    case kAudioConverterPrimeMethod: {
        if (size < 4)
            return kAudioConverterErr_BadPropertySizeError;
        UInt32 v = *(const UInt32 *)data;
        if (id == kAudioConverterSampleRateConverterComplexity)
            c->complexity = v;
        else if (id == kAudioConverterPrimeMethod)
            c->prime_method = v;
        else
            c->quality = v;
        return noErr;
    }
    case kAudioConverterPrimeInfo:
        return size < sizeof(AudioConverterPrimeInfo) ? kAudioConverterErr_BadPropertySizeError : noErr;
    case kAudioConverterChannelMap: {
        UInt32 n = size / sizeof(SInt32);
        if (n < c->po.channels)
            return kAudioConverterErr_BadPropertySizeError;
        for (UInt32 k = 0; k < c->po.channels; k++)
            c->map[k] = ((const SInt32 *)data)[k];
        c->has_map = 1;
        return noErr;
    }
    case kAudioConverterInputChannelLayout:
    case kAudioConverterOutputChannelLayout: {
        int k = id == kAudioConverterOutputChannelLayout;
        if (size < offsetof(AudioChannelLayout, mChannelDescriptions))
            return kAudioConverterErr_BadPropertySizeError;
        free(c->layout[k]);
        c->layout[k] = malloc(size);
        memcpy(c->layout[k], data, size);
        c->layout_size[k] = size;
        return noErr;
    }
    case kAudioConverterPropertyDithering:
    case kAudioConverterPropertyDitherBitDepth:
    case kAudioConverterPropertyBitDepthHint: return noErr;
    default: return kAudioConverterErr_PropertyNotSupported;
    }
}

/* ---- codecs ---------------------------------------------------------------------------------
 * Encoding: the program's PCM goes through the PCM converter `pcm` to the
 * codec's interleaved floats, a packet's worth at a time, and the codec's
 * packets come back. Decoding: packets the program gives go to the codec,
 * and its floats go through `pcm` to the program's PCM. The codecs are the
 * system's FFmpeg (src/codec.c). */

static int codec_id_ok(UInt32 id)
{
    switch (id) {
    case kAudioFormatMPEG4AAC:
    case kAudioFormatAppleLossless:
    case kAudioFormatFLAC:
    case kAudioFormatOpus:
    case kAudioFormatMPEGLayer3:
    case kAudioFormatMPEGLayer2:
    case kAudioFormatAC3:
    case kAudioFormatEnhancedAC3: return 1;
    default: return 0;
    }
}

static const int aac_rates[] = {96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
                                16000, 12000, 11025, 8000,  7350};

/* an AAC-LC AudioSpecificConfig for a rate and channels */
static UInt32 make_asc(UInt8 *asc, double rate, UInt32 channels)
{
    int idx = 4;
    for (int i = 0; i < 13; i++)
        if ((int)rate == aac_rates[i])
            idx = i;
    UInt16 v = (UInt16)((2 << 11) | (idx << 7) | ((channels > 7 ? 7 : channels) << 3));
    asc[0] = v >> 8;
    asc[1] = v & 0xff;
    return 2;
}

static UInt32 default_bit_rate(UInt32 id, UInt32 channels)
{
    if (id == kAudioFormatOpus)
        return channels > 1 ? 96000 : 64000;
    return channels > 1 ? 64000 * (channels > 2 ? channels : 2) : 64000;
}

static void codec_close(AudioConverterRef c)
{
    if (c->codec)
        ferry_acodec_close(c->codec);
    c->codec = NULL;
    c->started = c->ended = 0;
}

static int codec_open(AudioConverterRef c)
{
    if (c->codec)
        return 1;
    const AudioStreamBasicDescription *f = c->encoding ? &c->out : &c->in;
    UInt8 *cookie = NULL;
    UInt32 cookie_size = 0;
    UInt8 asc[2], alac[36];
    if (c->decoding) {
        cookie = c->cookie;
        cookie_size = c->cookie_size;
        if (f->mFormatID == kAudioFormatMPEG4AAC && !cookie_size) {
            cookie = asc;
            cookie_size = make_asc(asc, f->mSampleRate, f->mChannelsPerFrame);
        }
        if (f->mFormatID == kAudioFormatAppleLossless && cookie_size == 24) {
            /* the configuration alone: FFmpeg wants it in its 'alac' atom */
            memset(alac, 0, 12);
            alac[3] = 36;
            memcpy(alac + 4, "alac", 4);
            memcpy(alac + 12, cookie, 24);
            cookie = alac;
            cookie_size = 36;
        }
    }
    c->codec = ferry_acodec_open(c->encoding, f->mFormatID, (int)f->mSampleRate, (int)f->mChannelsPerFrame,
                                 (int)c->bit_rate, cookie, (int)cookie_size);
    if (!c->codec)
        return 0;
    if (c->encoding) {
        int fs = 0, pad = 0;
        ferry_acodec_info(c->codec, &fs, &pad, NULL, NULL);
        c->frames_per_packet = fs > 0 ? (UInt32)fs : 1024;
        c->padding = pad > 0 ? (UInt32)pad : 0;
    }
    return 1;
}

/* finds an ES descriptor's DecoderSpecificInfo (tag 5) in an ESDS */
static int esds_len(const UInt8 **p, const UInt8 *end)
{
    int n = 0;
    for (int i = 0; i < 4 && *p < end; i++) {
        UInt8 b = *(*p)++;
        n = (n << 7) | (b & 0x7f);
        if (!(b & 0x80))
            break;
    }
    return n;
}

static UInt32 esds_asc(const UInt8 *d, UInt32 size, const UInt8 **asc)
{
    const UInt8 *p = d, *end = d + size;
    /* an 'esds' atom: skip its header and version */
    if (size >= 12 && !memcmp(d + 4, "esds", 4))
        p = d + 12;
    while (p < end) {
        UInt8 tag = *p++;
        int n = esds_len(&p, end);
        if (tag == 3) {
            if (p + 3 > end)
                return 0;
            UInt8 flags = p[2];
            p += 3;
            if (flags & 0x80)
                p += 2;
            if (flags & 0x40 && p < end)
                p += 1 + *p;
            if (flags & 0x20)
                p += 2;
            continue;
        }
        if (tag == 4) {
            p += 13;
            continue;
        }
        if (tag == 5) {
            if (p + n > end)
                return 0;
            *asc = p;
            return (UInt32)n;
        }
        p += n;
    }
    return 0;
}

static OSStatus codec_new(const AudioStreamBasicDescription *from, const AudioStreamBasicDescription *to,
                          AudioConverterRef *out)
{
    int enc = from->mFormatID == kAudioFormatLinearPCM && to->mFormatID != kAudioFormatLinearPCM;
    int dec = from->mFormatID != kAudioFormatLinearPCM && to->mFormatID == kAudioFormatLinearPCM;
    const AudioStreamBasicDescription *pcmf = enc ? from : to, *cf = enc ? to : from;
    ca_pcm p;
    if ((!enc && !dec) || !codec_id_ok(cf->mFormatID) || !pcm_ok(pcmf, &p) || p.channels > CA_MAX_CHANNELS)
        return kAudioConverterErr_FormatNotSupported;
    if (!ferry_acodec_available(enc, cf->mFormatID))
        return kAudioConverterErr_FormatNotSupported;
    AudioStreamBasicDescription c_desc = *cf;
    if (c_desc.mSampleRate <= 0)
        c_desc.mSampleRate = pcmf->mSampleRate;
    if (!c_desc.mChannelsPerFrame)
        c_desc.mChannelsPerFrame = p.channels;
    if (c_desc.mChannelsPerFrame > 8)
        return kAudioConverterErr_FormatNotSupported;
    /* the codec's side of the PCM converter: interleaved floats */
    AudioStreamBasicDescription fl;
    ca_float_format(&fl, c_desc.mSampleRate, c_desc.mChannelsPerFrame, 0);
    AudioConverterRef pcm = NULL;
    OSStatus err = enc ? AudioConverterNew(from, &fl, &pcm) : AudioConverterNew(&fl, to, &pcm);
    if (err)
        return err;
    AudioConverterRef c = calloc(1, sizeof *c);
    if (!c) {
        AudioConverterDispose(pcm);
        return kAudio_MemFullError;
    }
    c->pcm = pcm;
    c->encoding = enc;
    c->decoding = dec;
    c->quality = kAudioConverterQuality_High;
    c->prime_method = kConverterPrimeMethod_Normal;
    c->in = enc ? *from : c_desc;
    c->out = enc ? c_desc : *to;
    c->pi = enc ? p : c->pi;
    c->po = enc ? c->po : p;
    c->rate_mode = kAudioCodecBitRateControlMode_Constant;
    if (enc) {
        c->bit_rate = default_bit_rate(c_desc.mFormatID, c_desc.mChannelsPerFrame);
        if (!codec_open(c)) {
            AudioConverterDispose(c);
            return kAudioConverterErr_FormatNotSupported;
        }
        c->out.mFramesPerPacket = c->frames_per_packet;
        c->out.mBytesPerPacket = 0;
        c->out.mBytesPerFrame = 0;
        c->out.mBitsPerChannel = 0;
    } else {
        if (!c->in.mFramesPerPacket)
            c->in.mFramesPerPacket = cf->mFormatID == kAudioFormatMPEG4AAC   ? 1024
                                     : cf->mFormatID == kAudioFormatAC3 ||
                                             cf->mFormatID == kAudioFormatEnhancedAC3 ? 1536
                                     : cf->mFormatID == kAudioFormatMPEGLayer3 ||
                                             cf->mFormatID == kAudioFormatMPEGLayer2 ? 1152
                                     : cf->mFormatID == kAudioFormatAppleLossless ? 4096
                                     : cf->mFormatID == kAudioFormatOpus ? 960 : 0;
    }
    *out = c;
    return noErr;
}

/* the PCM converter's input while encoding: the program's own */
static OSStatus enc_pull(AudioConverterRef inner, UInt32 *n, AudioBufferList *io,
                         AudioStreamPacketDescription **d, void *user)
{
    AudioConverterRef c = user;
    OSStatus err = c->user_proc(c, n, io, d, c->user_data);
    if (err)
        c->user_err = err;
    return err;
}

#define DEC_FRAMES 4096

/* the PCM converter's input while decoding: what the codec makes from the
 * program's packets */
static OSStatus dec_pull(AudioConverterRef inner, UInt32 *n, AudioBufferList *io,
                         AudioStreamPacketDescription **d, void *user)
{
    AudioConverterRef c = user;
    UInt32 want_ch = c->in.mChannelsPerFrame;
    if (!c->queue) {
        c->queue = malloc((size_t)DEC_FRAMES * 8 * sizeof(float) * 2);
        if (!c->queue) {
            *n = 0;
            return kAudio_MemFullError;
        }
    }
    if (!codec_open(c)) {
        *n = 0;
        return kAudioConverterErr_FormatNotSupported;
    }
    c->started = 1;
    float *raw = c->queue, *mine = c->queue + (size_t)DEC_FRAMES * 8;
    for (;;) {
        int ch = 0;
        int r = ferry_acodec_receive(c->codec, raw, DEC_FRAMES, &ch);
        if (r > 0) {
            float *give = raw;
            if ((UInt32)ch != want_ch) {
                /* the stream's own channels, made to fit the description */
                for (int i = 0; i < r; i++)
                    for (UInt32 k = 0; k < want_ch; k++)
                        mine[(size_t)i * want_ch + k] =
                            (int)k < ch ? raw[(size_t)i * ch + k] : ch == 1 ? raw[i] : 0.0f;
                give = mine;
            }
            io->mNumberBuffers = 1;
            io->mBuffers[0].mNumberChannels = want_ch;
            io->mBuffers[0].mData = give;
            io->mBuffers[0].mDataByteSize = (UInt32)r * want_ch * sizeof(float);
            *n = (UInt32)r;
            return noErr;
        }
        if (r < 0 || c->ended) {
            *n = 0;
            return noErr;
        }
        /* the codec needs another packet */
        UInt32 np = 1;
        struct {
            UInt32 n;
            AudioBuffer b[1];
        } list = {1, {{c->in.mChannelsPerFrame, 0, NULL}}};
        AudioStreamPacketDescription *pd = NULL;
        OSStatus err = c->user_proc(c, &np, (AudioBufferList *)&list, &pd, c->user_data);
        const UInt8 *bytes = list.b[0].mData;
        for (UInt32 i = 0; i < np && bytes; i++) {
            UInt32 off = pd ? (UInt32)pd[i].mStartOffset : 0;
            UInt32 size = pd ? pd[i].mDataByteSize : list.b[0].mDataByteSize;
            if (size && off + size <= list.b[0].mDataByteSize)
                ferry_acodec_send(c->codec, bytes + off, (int)size);
            if (!pd)
                break;
        }
        if (err) {
            c->user_err = err;
            *n = 0;
            return err;
        }
        if (!np) {
            ferry_acodec_send(c->codec, NULL, 0); /* the end: what the codec holds comes out */
            c->ended = 1;
        }
    }
}

static OSStatus codec_fill(AudioConverterRef c, AudioConverterComplexInputDataProc proc, void *user,
                           UInt32 *io_packets, AudioBufferList *out_list, AudioStreamPacketDescription *out_packets)
{
    c->user_proc = proc;
    c->user_data = user;
    c->user_err = noErr;
    if (c->decoding) {
        OSStatus err = AudioConverterFillComplexBuffer(c->pcm, dec_pull, c, io_packets, out_list, out_packets);
        return err ? err : c->user_err;
    }
    /* encoding: one packet after another into the first buffer */
    UInt32 want = *io_packets;
    *io_packets = 0;
    if (!want || !out_list->mNumberBuffers || !out_list->mBuffers[0].mData)
        return want ? kAudio_ParamError : noErr;
    if (!out_packets)
        want = 1;
    if (!codec_open(c))
        return kAudioConverterErr_FormatNotSupported;
    c->started = 1;
    UInt8 *buf = out_list->mBuffers[0].mData;
    UInt32 cap = out_list->mBuffers[0].mDataByteSize, off = 0, made = 0;
    UInt32 ch = c->out.mChannelsPerFrame, fpp = c->frames_per_packet;
    float *frames = malloc((size_t)fpp * ch * sizeof(float));
    if (!frames)
        return kAudio_MemFullError;
    OSStatus status = noErr;
    while (made < want) {
        int r = ferry_acodec_receive(c->codec, buf + off, (int)(cap - off), NULL);
        if (r > 0) {
            if (out_packets) {
                out_packets[made].mStartOffset = off;
                out_packets[made].mVariableFramesInPacket = 0;
                out_packets[made].mDataByteSize = (UInt32)r;
            }
            off += (UInt32)r;
            made++;
            continue;
        }
        if (r == -2) {
            if (!made)
                status = kAudioConverterErr_InvalidOutputSize;
            break;
        }
        if (r < 0)
            break; /* the end */
        if (status || c->ended)
            break;
        UInt32 n = fpp;
        struct {
            UInt32 n;
            AudioBuffer b[1];
        } list = {1, {{ch, (UInt32)(fpp * ch * sizeof(float)), frames}}};
        OSStatus err = AudioConverterFillComplexBuffer(c->pcm, enc_pull, c, &n, (AudioBufferList *)&list, NULL);
        if (n)
            ferry_acodec_send(c->codec, frames, (int)n);
        if (err)
            status = c->user_err ? c->user_err : err;
        else if (n < fpp) {
            ferry_acodec_send(c->codec, NULL, 0); /* the program's input ended */
            c->ended = 1;
        }
    }
    free(frames);
    out_list->mBuffers[0].mDataByteSize = off;
    *io_packets = made;
    return status;
}

/* AAC's magic cookie as Core Audio gives it: a whole ES descriptor */
static UInt32 make_esds(AudioConverterRef c, UInt8 *out, UInt32 cap)
{
    UInt8 asc[64];
    int asc_len = sizeof asc;
    if (ferry_acodec_info(c->codec, NULL, NULL, asc, &asc_len) || asc_len <= 0)
        asc_len = (int)make_asc(asc, c->out.mSampleRate, c->out.mChannelsPerFrame);
    UInt32 dsi = 2 + (UInt32)asc_len, dcd = 2 + 13 + dsi, es = 2 + 3 + dcd + 3;
    if (es > cap)
        return 0;
    UInt8 *p = out;
    *p++ = 0x03;
    *p++ = (UInt8)(es - 2);
    *p++ = 0;
    *p++ = 0;
    *p++ = 0;
    *p++ = 0x04;
    *p++ = (UInt8)(dcd - 2);
    *p++ = 0x40; /* MPEG-4 audio */
    *p++ = 0x15; /* an audio stream */
    UInt32 buffer = 768 * c->out.mChannelsPerFrame, rate = c->bit_rate;
    *p++ = buffer >> 16;
    *p++ = buffer >> 8;
    *p++ = buffer;
    for (int k = 0; k < 2; k++) {
        *p++ = rate >> 24;
        *p++ = rate >> 16;
        *p++ = rate >> 8;
        *p++ = rate;
    }
    *p++ = 0x05;
    *p++ = (UInt8)asc_len;
    memcpy(p, asc, (size_t)asc_len);
    p += asc_len;
    *p++ = 0x06;
    *p++ = 1;
    *p++ = 2;
    return (UInt32)(p - out);
}

static UInt32 enc_cookie(AudioConverterRef c, UInt8 *out, UInt32 cap)
{
    if (!codec_open(c))
        return 0;
    UInt32 id = c->out.mFormatID;
    if (id == kAudioFormatMPEG4AAC)
        return make_esds(c, out, cap);
    UInt8 extra[512];
    int n = sizeof extra;
    if (ferry_acodec_info(c->codec, NULL, NULL, extra, &n) || n <= 0)
        return 0;
    const UInt8 *from = extra;
    UInt32 len = (UInt32)n;
    UInt8 flac[42];
    if (id == kAudioFormatAppleLossless && n >= 36) {
        /* the ALACSpecificConfig, without FFmpeg's atom around it */
        from = extra + 12;
        len = 24;
    } else if (id == kAudioFormatFLAC && n == 34) {
        /* STREAMINFO as the last metadata block, as in a 'dfLa' box */
        flac[0] = 0x80;
        flac[1] = 0;
        flac[2] = 0;
        flac[3] = 34;
        memcpy(flac + 4, extra, 34);
        from = flac;
        len = 38;
    }
    if (len > cap)
        return 0;
    memcpy(out, from, len);
    return len;
}

/* the bit rates an encoder takes for its rate and channels */
static UInt32 bit_rates(AudioConverterRef c, AudioValueRange *r, UInt32 max)
{
    static const UInt32 aac[] = {32000, 40000, 48000, 56000, 64000, 80000, 96000, 112000, 128000, 160000, 192000,
                                 224000, 256000, 320000};
    static const UInt32 opus[] = {16000, 24000, 32000, 48000, 64000, 96000, 128000, 160000, 192000, 256000};
    const UInt32 *list = c->out.mFormatID == kAudioFormatOpus ? opus : aac;
    UInt32 n = c->out.mFormatID == kAudioFormatOpus ? 10 : 14, ch = c->out.mChannelsPerFrame, k = 0;
    double scale = ch > 1 ? ch / 2.0 : 0.5;
    for (UInt32 i = 0; i < n && k < max; i++) {
        double v = list[i] * scale;
        if (c->out.mFormatID == kAudioFormatMPEG4AAC && v > 6144.0 * c->out.mSampleRate * ch / 1024.0)
            break;
        r[k].mMinimum = r[k].mMaximum = (Float64)(UInt32)v;
        k++;
    }
    return k;
}

static OSStatus codec_property(AudioConverterRef c, AudioConverterPropertyID id, UInt32 *size, void *data,
                               Boolean *w, int *handled)
{
    UInt8 buf[512];
    const void *from = buf;
    UInt32 need = 4, v32 = 0;
    Boolean writable = 0;
    AudioValueRange ranges[16];
    AudioConverterPrimeInfo prime = {0, 0};
    *handled = 1;
    switch (id) {
    case kAudioConverterPropertyMinimumInputBufferSize:
    case kAudioConverterPropertyMaximumInputPacketSize:
        v32 = c->encoding ? c->pi.bytes_per_frame : 6144 * c->in.mChannelsPerFrame / 8 + 64;
        from = &v32;
        break;
    case kAudioConverterPropertyMinimumOutputBufferSize:
    case kAudioConverterPropertyMaximumOutputPacketSize:
        if (c->encoding)
            v32 = c->out.mFormatID == kAudioFormatMPEG4AAC ? 768 * c->out.mChannelsPerFrame
                  : c->out.mFormatID == kAudioFormatOpus   ? 1276 * 3
                                                           : c->frames_per_packet * c->out.mChannelsPerFrame * 4 + 64;
        else
            v32 = c->po.bytes_per_frame;
        from = &v32;
        break;
    case kAudioConverterPropertyCalculateInputBufferSize:
    case kAudioConverterPropertyCalculateOutputBufferSize: return kAudioConverterErr_PropertyNotSupported;
    case kAudioConverterCompressionMagicCookie:
        if (!c->encoding)
            return kAudioConverterErr_PropertyNotSupported;
        need = enc_cookie(c, buf, sizeof buf);
        if (!need)
            return kAudioConverterErr_PropertyNotSupported;
        break;
    case kAudioConverterDecompressionMagicCookie:
        if (!c->decoding)
            return kAudioConverterErr_PropertyNotSupported;
        from = c->cookie;
        need = c->cookie_size;
        writable = 1;
        break;
    case kAudioConverterEncodeBitRate:
        if (!c->encoding || c->out.mFormatID == kAudioFormatAppleLossless || c->out.mFormatID == kAudioFormatFLAC)
            return kAudioConverterErr_PropertyNotSupported;
        v32 = c->bit_rate;
        from = &v32;
        writable = 1;
        break;
    case kAudioConverterApplicableEncodeBitRates:
    case kAudioConverterAvailableEncodeBitRates:
        if (!c->encoding || c->out.mFormatID == kAudioFormatAppleLossless || c->out.mFormatID == kAudioFormatFLAC)
            return kAudioConverterErr_PropertyNotSupported;
        need = bit_rates(c, ranges, 16) * sizeof(AudioValueRange);
        from = ranges;
        break;
    case kAudioConverterApplicableEncodeSampleRates:
    case kAudioConverterAvailableEncodeSampleRates: {
        if (!c->encoding)
            return kAudioConverterErr_PropertyNotSupported;
        UInt32 k = 0;
        if (c->out.mFormatID == kAudioFormatOpus) {
            static const int o[] = {48000, 24000, 16000, 12000, 8000};
            for (int i = 0; i < 5; i++, k++)
                ranges[k].mMinimum = ranges[k].mMaximum = o[i];
        } else if (c->out.mFormatID == kAudioFormatMPEG4AAC) {
            for (int i = 0; i < 12; i++, k++)
                ranges[k].mMinimum = ranges[k].mMaximum = aac_rates[i];
        } else {
            ranges[0].mMinimum = 1;
            ranges[0].mMaximum = 384000;
            k = 1;
        }
        need = k * sizeof(AudioValueRange);
        from = ranges;
        break;
    }
    case kAudioCodecPropertyBitRateControlMode:
        v32 = c->rate_mode;
        from = &v32;
        writable = 1;
        break;
    case kAudioCodecPropertySoundQualityForVBR:
        v32 = c->vbr_quality;
        from = &v32;
        writable = 1;
        break;
    case kAudioConverterPrimeInfo:
        prime.leadingFrames = c->encoding ? c->padding : 0;
        from = &prime;
        need = sizeof prime;
        writable = 1;
        break;
    case kAudioConverterChannelMap:
        /* the PCM side's */
        if (!data) {
            OSStatus e = AudioConverterGetPropertyInfo(c->pcm, id, size, w);
            return e;
        }
        return AudioConverterGetProperty(c->pcm, id, size, data);
    default: *handled = 0; return noErr;
    }
    if (w)
        *w = writable;
    if (data) {
        if (*size < need)
            return kAudioConverterErr_BadPropertySizeError;
        if (need)
            memcpy(data, from, need);
    }
    *size = need;
    return noErr;
}

static OSStatus codec_set_property(AudioConverterRef c, AudioConverterPropertyID id, UInt32 size, const void *data,
                                   int *handled)
{
    *handled = 1;
    UInt32 v = size >= 4 && data ? *(const UInt32 *)data : 0;
    switch (id) {
    case kAudioConverterEncodeBitRate:
        if (!c->encoding)
            return kAudioConverterErr_PropertyNotSupported;
        if (size < 4)
            return kAudioConverterErr_BadPropertySizeError;
        if (c->started)
            return kAudioConverterErr_PropertyNotSupported;
        if (v && v != c->bit_rate) {
            c->bit_rate = v;
            codec_close(c); /* opened again with the new rate */
        }
        return noErr;
    case kAudioCodecPropertyBitRateControlMode:
        if (size < 4)
            return kAudioConverterErr_BadPropertySizeError;
        c->rate_mode = v;
        return noErr;
    case kAudioCodecPropertySoundQualityForVBR:
        if (size < 4)
            return kAudioConverterErr_BadPropertySizeError;
        c->vbr_quality = v > 127 ? 127 : v;
        if (c->encoding && !c->started && c->rate_mode == kAudioCodecBitRateControlMode_Variable &&
            c->out.mFormatID != kAudioFormatAppleLossless && c->out.mFormatID != kAudioFormatFLAC) {
            /* a quality becomes a bit rate: about 40 to 160 kbit/s a channel */
            UInt32 per = 40000 + c->vbr_quality * 120000 / 127;
            UInt32 rate = per * (c->out.mChannelsPerFrame ? c->out.mChannelsPerFrame : 2);
            if (rate != c->bit_rate) {
                c->bit_rate = rate;
                codec_close(c);
            }
        }
        return noErr;
    case kAudioConverterDecompressionMagicCookie: {
        if (!c->decoding)
            return kAudioConverterErr_PropertyNotSupported;
        const UInt8 *d = data;
        UInt32 n = size;
        if (c->in.mFormatID == kAudioFormatMPEG4AAC) {
            const UInt8 *asc = NULL;
            UInt32 len = esds_asc(d, size, &asc);
            if (len) {
                d = asc;
                n = len;
            }
        } else if (c->in.mFormatID == kAudioFormatAppleLossless) {
            /* the 'alac' atom, wherever it is in what's given */
            for (UInt32 i = 4; i + 32 <= size; i++)
                if (!memcmp(d + i, "alac", 4) && d[i - 4] == 0 && d[i - 3] == 0 && d[i - 2] == 0 && d[i - 1] == 36) {
                    d = d + i + 8;
                    n = 24;
                    break;
                }
        } else if (c->in.mFormatID == kAudioFormatFLAC) {
            /* FFmpeg wants STREAMINFO */
            for (UInt32 i = 0; i + 38 <= size; i++)
                if ((d[i] & 0x7f) == 0 && d[i + 1] == 0 && d[i + 2] == 0 && d[i + 3] == 34 &&
                    (i == 0 || !memcmp(d + i - 4, "fLaC", 4) || i == 4)) {
                    d = d + i + 4;
                    n = 34;
                    break;
                }
        }
        UInt8 *copy = n ? malloc(n) : NULL;
        if (n && !copy)
            return kAudio_MemFullError;
        if (n)
            memcpy(copy, d, n);
        free(c->cookie);
        c->cookie = copy;
        c->cookie_size = n;
        if (c->codec && !c->started)
            codec_close(c);
        return noErr;
    }
    case kAudioConverterChannelMap: return AudioConverterSetProperty(c->pcm, id, size, data);
    default: *handled = 0; return noErr;
    }
}
