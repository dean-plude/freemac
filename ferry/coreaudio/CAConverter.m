/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Audio converters (freemac 1.234, Ferry 0.58.0), written from Apple's
 * public documentation of AudioConverter.h. Ferry's converters take linear
 * PCM to linear PCM: any integer or float sample format either way round,
 * interleaved or not, to any channel count (through a channel map, or by
 * default channel for channel, with mono spread to left and right and
 * stereo mixed down to mono), and any sample rate, by linear
 * interpolation. Compressed formats are refused with
 * kAudioConverterErr_FormatNotSupported.
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
};

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
