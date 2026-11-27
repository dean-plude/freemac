/* SPDX-License-Identifier: GPL-3.0-or-later
 * Audio converters that encode and decode (freemac 1.264, Ferry 0.87.0),
 * through this system's FFmpeg: PCM to AAC the way HandBrake asks for it
 * (its bit rates, its magic cookie as an ES descriptor, its priming), AAC
 * back to PCM with that cookie, and Apple Lossless both ways, which must
 * give back exactly what went in. */
#include <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { RATE = 48000, CH = 2, SECONDS = 1, FRAMES = RATE * SECONDS };

typedef struct source {
    const void *data;
    UInt32 frame_bytes, frames, pos, chunk;
    int short_once; /* says "not yet" once, as HandBrake's input does */
} source;

static OSStatus pcm_in(AudioConverterRef c, UInt32 *n, AudioBufferList *io, AudioStreamPacketDescription **d, void *u)
{
    source *s = u;
    if (s->short_once && s->pos >= s->frames / 2) {
        s->short_once = 0;
        *n = 0;
        return 1;
    }
    UInt32 left = s->frames - s->pos, give = *n < left ? *n : left;
    if (s->chunk && give > s->chunk)
        give = s->chunk;
    io->mBuffers[0].mData = (char *)s->data + (size_t)s->pos * s->frame_bytes;
    io->mBuffers[0].mDataByteSize = give * s->frame_bytes;
    s->pos += give;
    *n = give;
    return noErr;
}

typedef struct packets {
    UInt8 *bytes;
    AudioStreamPacketDescription *descs;
    UInt32 count, next, size;
} packets;

static OSStatus packet_in(AudioConverterRef c, UInt32 *n, AudioBufferList *io, AudioStreamPacketDescription **d,
                          void *u)
{
    packets *p = u;
    static AudioStreamPacketDescription one;
    if (p->next >= p->count) {
        *n = 0;
        return noErr;
    }
    one = p->descs[p->next];
    io->mBuffers[0].mData = p->bytes + one.mStartOffset;
    io->mBuffers[0].mDataByteSize = one.mDataByteSize;
    one.mStartOffset = 0;
    if (d)
        *d = &one;
    p->next++;
    *n = 1;
    return noErr;
}

/* encodes all of src into p, a packet at a time as HandBrake does */
static OSStatus encode(AudioConverterRef c, source *src, packets *p, UInt32 max_packet)
{
    UInt8 *buf = malloc(max_packet);
    for (;;) {
        UInt32 n = 1;
        AudioStreamPacketDescription desc;
        AudioBufferList out = {1, {{CH, max_packet, buf}}};
        OSStatus err = AudioConverterFillComplexBuffer(c, pcm_in, src, &n, &out, &desc);
        if (err && err != 1) {
            free(buf);
            return err;
        }
        if (!n && !err)
            break;
        if (!n)
            continue;
        p->bytes = realloc(p->bytes, p->size + desc.mDataByteSize);
        memcpy(p->bytes + p->size, buf, desc.mDataByteSize);
        p->descs = realloc(p->descs, (p->count + 1) * sizeof *p->descs);
        p->descs[p->count] = desc;
        p->descs[p->count].mStartOffset = p->size;
        p->size += desc.mDataByteSize;
        p->count++;
    }
    free(buf);
    return noErr;
}

static UInt32 decode(AudioConverterRef c, packets *p, void *out, UInt32 frame_bytes, UInt32 cap)
{
    UInt32 got = 0;
    for (;;) {
        UInt32 n = 1000;
        if (got + n > cap)
            n = cap - got;
        if (!n)
            break;
        AudioBufferList list = {1, {{CH, n * frame_bytes, (char *)out + (size_t)got * frame_bytes}}};
        OSStatus err = AudioConverterFillComplexBuffer(c, packet_in, p, &n, &list, NULL);
        if (err) {
            printf("decode error %d\n", (int)err);
            break;
        }
        if (!n)
            break;
        got += n;
    }
    return got;
}

int main(void)
{
    float *tone = malloc(sizeof(float) * FRAMES * CH);
    for (int i = 0; i < FRAMES; i++) {
        tone[i * CH] = 0.5f * sinf(2 * (float)M_PI * 440 * i / RATE);
        tone[i * CH + 1] = 0.5f * sinf(2 * (float)M_PI * 660 * i / RATE);
    }
    AudioStreamBasicDescription fl = {RATE, kAudioFormatLinearPCM,
                                      kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, CH, 32, 0};
    AudioStreamBasicDescription aac = {0};
    aac.mFormatID = kAudioFormatMPEG4AAC;
    aac.mSampleRate = RATE;
    aac.mChannelsPerFrame = CH;

    /* ---- AAC, as HandBrake asks ---- */
    AudioConverterRef enc = NULL;
    OSStatus err = AudioConverterNew(&fl, &aac, &enc);
    printf("AAC encoder: %s\n", err ? "refused" : "made");
    if (err)
        return 1;
    UInt32 q = kAudioConverterQuality_Max;
    AudioConverterSetProperty(enc, kAudioConverterCodecQuality, 4, &q);
    UInt32 mode = kAudioCodecBitRateControlMode_Constant;
    printf("rate control mode set: %s\n",
           AudioConverterSetProperty(enc, kAudioCodecPropertyBitRateControlMode, 4, &mode) ? "no" : "yes");
    UInt32 size = 0;
    AudioConverterGetPropertyInfo(enc, kAudioConverterApplicableEncodeBitRates, &size, NULL);
    AudioValueRange *rates = malloc(size);
    AudioConverterGetProperty(enc, kAudioConverterApplicableEncodeBitRates, &size, rates);
    UInt32 nrates = size / sizeof *rates;
    printf("bit rates: %u, from %.0f to %.0f\n", nrates, rates[0].mMinimum, rates[nrates - 1].mMinimum);
    UInt32 br = 160000;
    printf("bit rate set: %s\n", AudioConverterSetProperty(enc, kAudioConverterEncodeBitRate, 4, &br) ? "no" : "yes");
    br = 0;
    size = 4;
    AudioConverterGetProperty(enc, kAudioConverterEncodeBitRate, &size, &br);
    printf("bit rate: %u\n", br);
    AudioStreamBasicDescription od;
    size = sizeof od;
    AudioConverterGetProperty(enc, kAudioConverterCurrentOutputStreamDescription, &size, &od);
    printf("frames per packet: %u, bytes per packet: %u\n", od.mFramesPerPacket, od.mBytesPerPacket);
    UInt32 max_packet = 0;
    size = 4;
    AudioConverterGetProperty(enc, kAudioConverterPropertyMaximumOutputPacketSize, &size, &max_packet);
    printf("largest packet: %u\n", max_packet);
    AudioConverterPrimeInfo prime = {0, 0};
    size = sizeof prime;
    AudioConverterGetProperty(enc, kAudioConverterPrimeInfo, &size, &prime);
    printf("priming frames: %s\n", prime.leadingFrames > 0 ? "some" : "none");
    UInt8 cookie[256];
    UInt32 cookie_size = sizeof cookie;
    err = AudioConverterGetProperty(enc, kAudioConverterCompressionMagicCookie, &cookie_size, cookie);
    printf("cookie: %s, ES descriptor: %s, decoder info inside: %s\n", err ? "none" : "given",
           cookie[0] == 0x03 ? "yes" : "no", memchr(cookie, 0x05, cookie_size) ? "yes" : "no");

    source src = {tone, 8, FRAMES, 0, 700, 1};
    packets aacp = {0};
    err = encode(enc, &src, &aacp, max_packet);
    printf("encoded: %s, packets: %s\n", err ? "failed" : "yes",
           aacp.count >= FRAMES / 1024 && aacp.count <= FRAMES / 1024 + 4 ? "a second's worth" : "wrong");
    double kbit = aacp.size * 8.0 / SECONDS / 1000;
    printf("size near the bit rate: %s\n", kbit > 100 && kbit < 220 ? "yes" : "no");
    AudioConverterDispose(enc);

    AudioConverterRef dec = NULL;
    err = AudioConverterNew(&aac, &fl, &dec);
    printf("AAC decoder: %s\n", err ? "refused" : "made");
    printf("cookie taken: %s\n",
           AudioConverterSetProperty(dec, kAudioConverterDecompressionMagicCookie, cookie_size, cookie) ? "no" : "yes");
    UInt32 cap = FRAMES + 8192;
    float *back = calloc(cap * CH, sizeof(float));
    UInt32 got = decode(dec, &aacp, back, 8, cap);
    printf("decoded: %s\n", got >= FRAMES && got <= FRAMES + 4096 ? "all of it" : "wrong");
    /* the tone is there, after the priming: compare energy and correlation */
    UInt32 lead = prime.leadingFrames;
    double e = 0, dot = 0, e2 = 0;
    for (UInt32 i = 4096; i < FRAMES - 4096; i++) {
        float a = tone[i * CH], b = back[(i + lead) * CH];
        e += a * a;
        e2 += b * b;
        dot += a * b;
    }
    printf("the tone comes back: %s\n", dot / sqrt(e * e2) > 0.95 ? "yes" : "no");
    AudioConverterDispose(dec);

    /* ---- Apple Lossless, both ways: exactly what went in ---- */
    SInt16 *s16 = malloc(sizeof(SInt16) * FRAMES * CH);
    for (int i = 0; i < FRAMES * CH; i++)
        s16[i] = (SInt16)(tone[i] * 32767);
    AudioStreamBasicDescription pcm16 = {RATE, kAudioFormatLinearPCM,
                                         kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, CH, 16, 0};
    AudioStreamBasicDescription alac = {0};
    alac.mFormatID = kAudioFormatAppleLossless;
    alac.mSampleRate = RATE;
    alac.mChannelsPerFrame = CH;
    alac.mFormatFlags = 1; /* 16-bit source */
    err = AudioConverterNew(&pcm16, &alac, &enc);
    printf("Apple Lossless encoder: %s\n", err ? "refused" : "made");
    if (err)
        return 1;
    size = sizeof od;
    AudioConverterGetProperty(enc, kAudioConverterCurrentOutputStreamDescription, &size, &od);
    printf("lossless frames per packet: %u\n", od.mFramesPerPacket);
    printf("bit rate offered: %s\n",
           AudioConverterGetPropertyInfo(enc, kAudioConverterEncodeBitRate, &size, NULL) ? "no" : "yes");
    size = 4;
    AudioConverterGetProperty(enc, kAudioConverterPropertyMaximumOutputPacketSize, &size, &max_packet);
    cookie_size = sizeof cookie;
    err = AudioConverterGetProperty(enc, kAudioConverterCompressionMagicCookie, &cookie_size, cookie);
    printf("lossless cookie: %u bytes\n", err ? 0 : cookie_size);
    source src2 = {s16, 4, FRAMES, 0, 0, 0};
    packets ap = {0};
    err = encode(enc, &src2, &ap, max_packet);
    printf("lossless encoded: %s, smaller: %s\n", err ? "failed" : "yes", ap.size < FRAMES * 4 ? "yes" : "no");
    AudioConverterDispose(enc);
    err = AudioConverterNew(&alac, &pcm16, &dec);
    AudioConverterSetProperty(dec, kAudioConverterDecompressionMagicCookie, cookie_size, cookie);
    SInt16 *b16 = calloc(cap * CH, sizeof(SInt16));
    got = decode(dec, &ap, b16, 4, cap);
    printf("lossless decoded: %u frames, the same: %s\n", got,
           got == FRAMES && !memcmp(b16, s16, FRAMES * 4) ? "yes" : "no");
    AudioConverterDispose(dec);

    /* a format nothing here makes */
    AudioStreamBasicDescription other = aac;
    other.mFormatID = 'qdm2';
    printf("QDesign: %s\n", AudioConverterNew(&fl, &other, &enc) == kAudioConverterErr_FormatNotSupported
                                ? "not supported"
                                : "wrong");
    return 0;
}
