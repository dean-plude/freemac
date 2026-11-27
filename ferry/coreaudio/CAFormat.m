/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Linear PCM to and from 32-bit floats, channel layouts, and Audio Format
 * Services' channel layout properties (freemac 1.234, Ferry 0.58.0).
 * Written from Apple's public documentation of CoreAudioTypes and
 * AudioFormat.
 */
#import "CAInternal.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ---- linear PCM ----------------------------------------------------------------- */

int ca_pcm_parse(const AudioStreamBasicDescription *f, ca_pcm *p)
{
    memset(p, 0, sizeof *p);
    if (!f || f->mFormatID != kAudioFormatLinearPCM || !f->mChannelsPerFrame || f->mChannelsPerFrame > 64 ||
        f->mFramesPerPacket > 1)
        return -1;
    UInt32 flags = f->mFormatFlags;
    p->is_float = (flags & kAudioFormatFlagIsFloat) != 0;
    p->is_signed = (flags & kAudioFormatFlagIsSignedInteger) != 0;
    p->big_endian = (flags & kAudioFormatFlagIsBigEndian) != 0;
    p->non_interleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0;
    p->aligned_high = (flags & kAudioFormatFlagIsAlignedHigh) != 0;
    p->bits = f->mBitsPerChannel;
    p->channels = f->mChannelsPerFrame;
    UInt32 per_buffer = p->non_interleaved ? 1 : p->channels;
    p->bytes_per_frame = f->mBytesPerFrame ? f->mBytesPerFrame : per_buffer * ((p->bits + 7) / 8);
    if (!p->bytes_per_frame || p->bytes_per_frame % per_buffer)
        return -1;
    p->container = p->bytes_per_frame / per_buffer;
    if (p->is_float) {
        if (!((p->bits == 32 && p->container == 4) || (p->bits == 64 && p->container == 8)))
            return -1;
    } else if (!p->bits || p->bits > 32 || p->container < (p->bits + 7) / 8 || p->container > 4)
        return -1;
    return 0;
}

void ca_float_format(AudioStreamBasicDescription *f, Float64 rate, UInt32 channels, int non_interleaved)
{
    memset(f, 0, sizeof *f);
    f->mSampleRate = rate;
    f->mFormatID = kAudioFormatLinearPCM;
    f->mFormatFlags = kAudioFormatFlagsNativeFloatPacked | (non_interleaved ? kAudioFormatFlagIsNonInterleaved : 0);
    f->mBitsPerChannel = 32;
    f->mChannelsPerFrame = channels;
    f->mFramesPerPacket = 1;
    f->mBytesPerFrame = non_interleaved ? 4 : 4 * channels;
    f->mBytesPerPacket = f->mBytesPerFrame;
}

static float read_sample(const ca_pcm *p, const unsigned char *s)
{
    unsigned char b[8];
    UInt32 n = p->container;
    /* to little-endian */
    for (UInt32 i = 0; i < n; i++)
        b[i] = p->big_endian ? s[n - 1 - i] : s[i];
    if (p->is_float) {
        if (n == 4) {
            float v;
            memcpy(&v, b, 4);
            return v;
        }
        double v;
        memcpy(&v, b, 8);
        return (float)v;
    }
    uint32_t u = 0;
    for (UInt32 i = 0; i < n; i++)
        u |= (uint32_t)b[i] << (8 * i);
    UInt32 shift = p->aligned_high ? (8 * n - p->bits) : 0;
    u >>= shift;
    uint32_t mask = p->bits >= 32 ? 0xFFFFFFFFu : ((1u << p->bits) - 1);
    u &= mask;
    double scale = ldexp(1.0, (int)p->bits - 1);
    if (p->is_signed) {
        int64_t v = (u & (1u << (p->bits - 1))) ? (int64_t)u - ((int64_t)1 << p->bits) : (int64_t)u;
        return (float)(v / scale);
    }
    return (float)(((double)u - scale) / scale);
}

static void write_sample(const ca_pcm *p, unsigned char *d, float x)
{
    unsigned char b[8] = {0};
    UInt32 n = p->container;
    if (p->is_float) {
        if (n == 4)
            memcpy(b, &x, 4);
        else {
            double v = x;
            memcpy(b, &v, 8);
        }
    } else {
        double scale = ldexp(1.0, (int)p->bits - 1);
        double v = x < -1.0f ? -1.0 : x > 1.0f ? 1.0 : x;
        int64_t i = (int64_t)lrint(v * scale);
        int64_t top = (int64_t)scale - 1;
        if (i > top)
            i = top;
        if (i < -(int64_t)scale)
            i = -(int64_t)scale;
        uint32_t u = p->is_signed ? (uint32_t)(i & (p->bits >= 32 ? 0xFFFFFFFFll : ((1ll << p->bits) - 1)))
                                  : (uint32_t)(i + (int64_t)scale);
        UInt32 shift = p->aligned_high ? (8 * n - p->bits) : 0;
        u <<= shift;
        for (UInt32 k = 0; k < n; k++)
            b[k] = (unsigned char)(u >> (8 * k));
    }
    for (UInt32 i = 0; i < n; i++)
        d[i] = p->big_endian ? b[n - 1 - i] : b[i];
}

void ca_bytes_to_float(const ca_pcm *p, const void *bytes, UInt32 frames, float *out)
{
    const unsigned char *s = bytes;
    if (p->is_float && p->container == 4 && !p->big_endian) {
        memcpy(out, s, (size_t)frames * p->channels * 4);
        return;
    }
    for (UInt32 i = 0; i < frames * p->channels; i++)
        out[i] = read_sample(p, s + (size_t)i * p->container);
}

void ca_bytes_from_float(const ca_pcm *p, const float *in, UInt32 frames, void *bytes)
{
    unsigned char *d = bytes;
    if (p->is_float && p->container == 4 && !p->big_endian) {
        memcpy(d, in, (size_t)frames * p->channels * 4);
        return;
    }
    for (UInt32 i = 0; i < frames * p->channels; i++)
        write_sample(p, d + (size_t)i * p->container, in[i]);
}

void ca_pcm_to_float(const ca_pcm *p, const AudioBufferList *list, UInt32 frames, float *out)
{
    if (!list || !list->mNumberBuffers) {
        memset(out, 0, (size_t)frames * p->channels * sizeof(float));
        return;
    }
    if (!p->non_interleaved) {
        const AudioBuffer *b = &list->mBuffers[0];
        UInt32 have = b->mData ? b->mDataByteSize / p->bytes_per_frame : 0;
        if (have > frames)
            have = frames;
        if (have)
            ca_bytes_to_float(p, b->mData, have, out);
        memset(out + (size_t)have * p->channels, 0, (size_t)(frames - have) * p->channels * sizeof(float));
        return;
    }
    for (UInt32 c = 0; c < p->channels; c++) {
        const AudioBuffer *b = c < list->mNumberBuffers ? &list->mBuffers[c] : NULL;
        const unsigned char *s = b ? b->mData : NULL;
        UInt32 have = s ? b->mDataByteSize / p->container : 0;
        for (UInt32 i = 0; i < frames; i++)
            out[(size_t)i * p->channels + c] = i < have ? read_sample(p, s + (size_t)i * p->container) : 0.0f;
    }
}

void ca_pcm_from_float(const ca_pcm *p, const float *in, UInt32 frames, AudioBufferList *list)
{
    if (!list)
        return;
    if (!p->non_interleaved) {
        if (!list->mNumberBuffers || !list->mBuffers[0].mData)
            return;
        AudioBuffer *b = &list->mBuffers[0];
        UInt32 room = b->mDataByteSize / p->bytes_per_frame;
        if (room > frames)
            room = frames;
        ca_bytes_from_float(p, in, room, b->mData);
        b->mDataByteSize = room * p->bytes_per_frame;
        b->mNumberChannels = p->channels;
        return;
    }
    for (UInt32 c = 0; c < p->channels && c < list->mNumberBuffers; c++) {
        AudioBuffer *b = &list->mBuffers[c];
        if (!b->mData)
            continue;
        UInt32 room = b->mDataByteSize / p->container;
        if (room > frames)
            room = frames;
        for (UInt32 i = 0; i < room; i++)
            write_sample(p, (unsigned char *)b->mData + (size_t)i * p->container, in[(size_t)i * p->channels + c]);
        b->mDataByteSize = room * p->container;
        b->mNumberChannels = 1;
    }
}

/* ---- channel layouts -------------------------------------------------------------- */

/* The labels of the server's own order for 1 to 8 channels (PulseAudio's
 * and PipeWire's defaults, which follow ALSA's), as Core Audio names them. */
void ca_default_labels(UInt32 n, UInt32 *labels)
{
    static const UInt32 orders[9][8] = {
        {0},
        {kAudioChannelLabel_Center},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LFEScreen},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
         kAudioChannelLabel_RightSurround},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
         kAudioChannelLabel_RightSurround, kAudioChannelLabel_Center},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
         kAudioChannelLabel_RightSurround, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
         kAudioChannelLabel_RightSurround, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
         kAudioChannelLabel_CenterSurround},
        {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_RearSurroundLeft,
         kAudioChannelLabel_RearSurroundRight, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
         kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround},
    };
    for (UInt32 i = 0; i < n; i++)
        labels[i] = n <= 8 ? orders[n][i] : (kAudioChannelLabel_Discrete_0 + i);
}

/* The layouts Ferry knows by tag, in their documented channel order. */
static const struct {
    AudioChannelLayoutTag tag;
    UInt32 labels[8];
} tagged[] = {
    {kAudioChannelLayoutTag_Mono, {kAudioChannelLabel_Mono}},
    {kAudioChannelLayoutTag_Stereo, {kAudioChannelLabel_Left, kAudioChannelLabel_Right}},
    {kAudioChannelLayoutTag_StereoHeadphones, {kAudioChannelLabel_HeadphonesLeft, kAudioChannelLabel_HeadphonesRight}},
    {kAudioChannelLayoutTag_MatrixStereo, {kAudioChannelLabel_LeftTotal, kAudioChannelLabel_RightTotal}},
    {kAudioChannelLayoutTag_Quadraphonic,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround}},
    {kAudioChannelLayoutTag_MPEG_3_0_A, {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center}},
    {kAudioChannelLayoutTag_MPEG_3_0_B, {kAudioChannelLabel_Center, kAudioChannelLabel_Left, kAudioChannelLabel_Right}},
    {kAudioChannelLayoutTag_MPEG_4_0_A,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center,
      kAudioChannelLabel_CenterSurround}},
    {kAudioChannelLayoutTag_MPEG_4_0_B,
     {kAudioChannelLabel_Center, kAudioChannelLabel_Left, kAudioChannelLabel_Right,
      kAudioChannelLabel_CenterSurround}},
    {kAudioChannelLayoutTag_MPEG_5_0_A,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround}},
    {kAudioChannelLayoutTag_MPEG_5_0_B,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround, kAudioChannelLabel_Center}},
    {kAudioChannelLayoutTag_MPEG_5_0_C,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Center, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround}},
    {kAudioChannelLayoutTag_MPEG_5_0_D,
     {kAudioChannelLabel_Center, kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround}},
    {kAudioChannelLayoutTag_MPEG_5_1_A,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
      kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround}},
    {kAudioChannelLayoutTag_MPEG_5_1_B,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen}},
    {kAudioChannelLayoutTag_MPEG_5_1_C,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Center, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround, kAudioChannelLabel_LFEScreen}},
    {kAudioChannelLayoutTag_MPEG_5_1_D,
     {kAudioChannelLabel_Center, kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround, kAudioChannelLabel_LFEScreen}},
    {kAudioChannelLayoutTag_MPEG_6_1_A,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
      kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround, kAudioChannelLabel_CenterSurround}},
    {kAudioChannelLayoutTag_MPEG_7_1_A,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
      kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround, kAudioChannelLabel_LeftCenter,
      kAudioChannelLabel_RightCenter}},
    {kAudioChannelLayoutTag_MPEG_7_1_B,
     {kAudioChannelLabel_Center, kAudioChannelLabel_LeftCenter, kAudioChannelLabel_RightCenter,
      kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround, kAudioChannelLabel_LFEScreen}},
    {kAudioChannelLayoutTag_MPEG_7_1_C,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
      kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround, kAudioChannelLabel_RearSurroundLeft,
      kAudioChannelLabel_RearSurroundRight}},
    {kAudioChannelLayoutTag_ITU_2_1, {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_CenterSurround}},
    {kAudioChannelLayoutTag_ITU_2_2,
     {kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
      kAudioChannelLabel_RightSurround}},
};

static UInt32 labels_for_tag(AudioChannelLayoutTag tag, UInt32 *labels, UInt32 max)
{
    if ((tag & 0xFFFF0000) == kAudioChannelLayoutTag_DiscreteInOrder) {
        UInt32 n = AudioChannelLayoutTag_GetNumberOfChannels(tag);
        for (UInt32 i = 0; i < n && i < max; i++)
            labels[i] = kAudioChannelLabel_Discrete_0 + i;
        return n < max ? n : max;
    }
    for (size_t i = 0; i < sizeof tagged / sizeof tagged[0]; i++)
        if (tagged[i].tag == tag) {
            UInt32 n = AudioChannelLayoutTag_GetNumberOfChannels(tag);
            for (UInt32 k = 0; k < n && k < max; k++)
                labels[k] = tagged[i].labels[k];
            return n < max ? n : max;
        }
    return 0;
}

static UInt32 labels_for_bitmap(AudioChannelBitmap bitmap, UInt32 *labels, UInt32 max)
{
    UInt32 n = 0;
    for (UInt32 bit = 0; bit < 18 && n < max; bit++)
        if (bitmap & (1u << bit))
            labels[n++] = bit + 1; /* kAudioChannelLabel_Left is 1, and so on */
    return n;
}

UInt32 ca_layout_labels(const AudioChannelLayout *l, UInt32 size, UInt32 *labels, UInt32 max)
{
    if (!l || size < offsetof(AudioChannelLayout, mChannelDescriptions))
        return 0;
    if (l->mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelBitmap)
        return labels_for_bitmap(l->mChannelBitmap, labels, max);
    if (l->mChannelLayoutTag != kAudioChannelLayoutTag_UseChannelDescriptions)
        return labels_for_tag(l->mChannelLayoutTag, labels, max);
    UInt32 n = l->mNumberChannelDescriptions;
    if (size < offsetof(AudioChannelLayout, mChannelDescriptions) + (size_t)n * sizeof(AudioChannelDescription))
        return 0;
    for (UInt32 i = 0; i < n && i < max; i++)
        labels[i] = l->mChannelDescriptions[i].mChannelLabel;
    return n < max ? n : max;
}

AudioChannelLayout *ca_layout_with_labels(const UInt32 *labels, UInt32 n, UInt32 *size)
{
    UInt32 bytes = (UInt32)(offsetof(AudioChannelLayout, mChannelDescriptions) + n * sizeof(AudioChannelDescription));
    if (bytes < sizeof(AudioChannelLayout))
        bytes = sizeof(AudioChannelLayout);
    AudioChannelLayout *l = calloc(1, bytes);
    l->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
    l->mNumberChannelDescriptions = n;
    for (UInt32 i = 0; i < n; i++)
        l->mChannelDescriptions[i].mChannelLabel = labels[i];
    if (size)
        *size = bytes;
    return l;
}

const char *ca_label_name(UInt32 label)
{
    switch (label) {
    case kAudioChannelLabel_Left: return "Left";
    case kAudioChannelLabel_Right: return "Right";
    case kAudioChannelLabel_Center: return "Center";
    case kAudioChannelLabel_LFEScreen: return "LFE";
    case kAudioChannelLabel_LeftSurround: return "Left Surround";
    case kAudioChannelLabel_RightSurround: return "Right Surround";
    case kAudioChannelLabel_LeftCenter: return "Left Center";
    case kAudioChannelLabel_RightCenter: return "Right Center";
    case kAudioChannelLabel_CenterSurround: return "Center Surround";
    case kAudioChannelLabel_LeftSurroundDirect: return "Left Surround Direct";
    case kAudioChannelLabel_RightSurroundDirect: return "Right Surround Direct";
    case kAudioChannelLabel_TopCenterSurround: return "Top Center Surround";
    case kAudioChannelLabel_RearSurroundLeft: return "Rear Surround Left";
    case kAudioChannelLabel_RearSurroundRight: return "Rear Surround Right";
    case kAudioChannelLabel_Mono: return "Mono";
    case kAudioChannelLabel_HeadphonesLeft: return "Headphones Left";
    case kAudioChannelLabel_HeadphonesRight: return "Headphones Right";
    default: return NULL;
    }
}

/* ---- Audio Format Services ---------------------------------------------------------- */

static OSStatus layout_property(AudioFormatPropertyID prop, UInt32 spec_size, const void *spec, UInt32 *size,
                                void *out)
{
    UInt32 labels[CA_MAX_CHANNELS], n = 0;
    if (prop == kAudioFormatProperty_ChannelLayoutForTag) {
        if (spec_size < sizeof(AudioChannelLayoutTag))
            return kAudioFormatBadSpecifierSizeError;
        AudioChannelLayoutTag tag = *(const AudioChannelLayoutTag *)spec;
        n = labels_for_tag(tag, labels, CA_MAX_CHANNELS);
        if (!n)
            return kAudioFormatUnsupportedPropertyError;
    } else {
        if (spec_size < sizeof(AudioChannelBitmap))
            return kAudioFormatBadSpecifierSizeError;
        n = labels_for_bitmap(*(const AudioChannelBitmap *)spec, labels, CA_MAX_CHANNELS);
    }
    UInt32 need;
    AudioChannelLayout *l = ca_layout_with_labels(labels, n, &need);
    OSStatus err = noErr;
    if (out) {
        if (*size < need)
            err = kAudioFormatBadPropertySizeError;
        else
            memcpy(out, l, need);
    }
    *size = need;
    free(l);
    return err;
}

/* the frames in one packet of a compressed format the converters handle;
 * 0 for one they don't (HE-AAC among them) */
static UInt32 codec_frames_per_packet(UInt32 id)
{
    switch (id) {
    case kAudioFormatMPEG4AAC: return 1024;
    case kAudioFormatAppleLossless: return 4096;
    case kAudioFormatFLAC: return 4096;
    case kAudioFormatOpus: return 960;
    case kAudioFormatMPEGLayer3:
    case kAudioFormatMPEGLayer2: return 1152;
    case kAudioFormatAC3:
    case kAudioFormatEnhancedAC3: return 1536;
    default: return 0;
    }
}

static OSStatus format_property(AudioFormatPropertyID prop, UInt32 spec_size, const void *spec, UInt32 *size,
                                void *out)
{
    switch (prop) {
    case kAudioFormatProperty_ChannelLayoutForTag:
    case kAudioFormatProperty_ChannelLayoutForBitmap:
        return layout_property(prop, spec_size, spec, size, out);
    case kAudioFormatProperty_NumberOfChannelsForLayout:
    case kAudioFormatProperty_BitmapForLayoutTag:
    case kAudioFormatProperty_TagForChannelLayout: {
        UInt32 value = 0;
        if (prop == kAudioFormatProperty_BitmapForLayoutTag) {
            if (spec_size < sizeof(AudioChannelLayoutTag))
                return kAudioFormatBadSpecifierSizeError;
            UInt32 labels[CA_MAX_CHANNELS];
            UInt32 n = labels_for_tag(*(const AudioChannelLayoutTag *)spec, labels, CA_MAX_CHANNELS);
            for (UInt32 i = 0; i < n; i++) {
                if (labels[i] < 1 || labels[i] > 18)
                    return kAudioFormatUnsupportedPropertyError;
                value |= 1u << (labels[i] - 1);
            }
            if (!n)
                return kAudioFormatUnsupportedPropertyError;
        } else {
            const AudioChannelLayout *l = spec;
            if (!l || spec_size < offsetof(AudioChannelLayout, mChannelDescriptions))
                return kAudioFormatBadSpecifierSizeError;
            UInt32 labels[CA_MAX_CHANNELS];
            UInt32 n = ca_layout_labels(l, spec_size, labels, CA_MAX_CHANNELS);
            if (prop == kAudioFormatProperty_NumberOfChannelsForLayout) {
                if (l->mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelDescriptions)
                    n = l->mNumberChannelDescriptions;
                else if (l->mChannelLayoutTag != kAudioChannelLayoutTag_UseChannelBitmap)
                    n = AudioChannelLayoutTag_GetNumberOfChannels(l->mChannelLayoutTag);
                value = n;
            } else {
                value = kAudioChannelLayoutTag_UseChannelDescriptions;
                if (l->mChannelLayoutTag != kAudioChannelLayoutTag_UseChannelDescriptions &&
                    l->mChannelLayoutTag != kAudioChannelLayoutTag_UseChannelBitmap)
                    value = l->mChannelLayoutTag;
                else
                    for (size_t i = 0; i < sizeof tagged / sizeof tagged[0]; i++) {
                        UInt32 tn = AudioChannelLayoutTag_GetNumberOfChannels(tagged[i].tag);
                        if (tn == n && !memcmp(tagged[i].labels, labels, n * sizeof(UInt32))) {
                            value = tagged[i].tag;
                            break;
                        }
                    }
            }
        }
        if (out) {
            if (*size < sizeof(UInt32))
                return kAudioFormatBadPropertySizeError;
            *(UInt32 *)out = value;
        }
        *size = sizeof(UInt32);
        return noErr;
    }
    case kAudioFormatProperty_FormatInfo: {
        /* fills in a linear PCM description's sizes */
        if (!out) {
            *size = sizeof(AudioStreamBasicDescription);
            return noErr;
        }
        if (*size < sizeof(AudioStreamBasicDescription))
            return kAudioFormatBadPropertySizeError;
        AudioStreamBasicDescription *f = out;
        if (f->mFormatID != kAudioFormatLinearPCM) {
            /* A compressed format the audio converters handle: its frames
             * in a packet, and no fixed bytes per packet, as Apple's
             * documentation of the property describes (freemac 1.266) */
            UInt32 fpp = codec_frames_per_packet(f->mFormatID);
            if (!fpp)
                return kAudioFormatUnsupportedDataFormatError;
            if (!f->mFramesPerPacket)
                f->mFramesPerPacket = fpp;
            if (!f->mChannelsPerFrame)
                f->mChannelsPerFrame = 2;
            f->mBytesPerFrame = 0;
            if (f->mFormatID != kAudioFormatAC3)
                f->mBytesPerPacket = 0;
            f->mBitsPerChannel = 0;
            *size = sizeof(AudioStreamBasicDescription);
            return noErr;
        }
        if (!f->mBitsPerChannel)
            f->mBitsPerChannel = (f->mFormatFlags & kAudioFormatFlagIsFloat) ? 32 : 16;
        if (!f->mFramesPerPacket)
            f->mFramesPerPacket = 1;
        if (!f->mBytesPerFrame) {
            UInt32 per = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : f->mChannelsPerFrame;
            f->mBytesPerFrame = per * ((f->mBitsPerChannel + 7) / 8);
        }
        if (!f->mBytesPerPacket)
            f->mBytesPerPacket = f->mBytesPerFrame * f->mFramesPerPacket;
        *size = sizeof(AudioStreamBasicDescription);
        return noErr;
    }
    case kAudioFormatProperty_FormatIsVBR:
    case kAudioFormatProperty_FormatIsExternallyFramed: {
        if (spec_size < sizeof(AudioStreamBasicDescription))
            return kAudioFormatBadSpecifierSizeError;
        const AudioStreamBasicDescription *f = spec;
        UInt32 value = prop == kAudioFormatProperty_FormatIsVBR ? (f->mBytesPerPacket == 0) : 0;
        if (out) {
            if (*size < sizeof(UInt32))
                return kAudioFormatBadPropertySizeError;
            *(UInt32 *)out = value;
        }
        *size = sizeof(UInt32);
        return noErr;
    }
    case kAudioFormatProperty_ChannelName:
    case kAudioFormatProperty_ChannelShortName: {
        if (spec_size < sizeof(AudioChannelDescription))
            return kAudioFormatBadSpecifierSizeError;
        const char *name = ca_label_name(((const AudioChannelDescription *)spec)->mChannelLabel);
        if (!name)
            return kAudioFormatUnsupportedPropertyError;
        if (out) {
            if (*size < sizeof(CFStringRef))
                return kAudioFormatBadPropertySizeError;
            *(CFStringRef *)out = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
        }
        *size = sizeof(CFStringRef);
        return noErr;
    }
    case kAudioFormatProperty_EncodeFormatIDs:
    case kAudioFormatProperty_DecodeFormatIDs: {
        /* linear PCM, and the formats the converters encode or decode
         * through the system's FFmpeg */
        static const UInt32 enc[] = {kAudioFormatLinearPCM, kAudioFormatMPEG4AAC, kAudioFormatAppleLossless,
                                     kAudioFormatFLAC, kAudioFormatOpus};
        static const UInt32 dec[] = {kAudioFormatLinearPCM, kAudioFormatMPEG4AAC, kAudioFormatAppleLossless,
                                     kAudioFormatFLAC, kAudioFormatOpus, kAudioFormatMPEGLayer3,
                                     kAudioFormatMPEGLayer2, kAudioFormatAC3, kAudioFormatEnhancedAC3};
        const UInt32 *ids = prop == kAudioFormatProperty_EncodeFormatIDs ? enc : dec;
        UInt32 n = prop == kAudioFormatProperty_EncodeFormatIDs ? 5 : 9;
        if (out) {
            UInt32 fit = *size / sizeof(UInt32);
            if (!fit)
                return kAudioFormatBadPropertySizeError;
            if (fit < n)
                n = fit;
            memcpy(out, ids, n * sizeof(UInt32));
        }
        *size = n * sizeof(UInt32);
        return noErr;
    }
    default:
        return kAudioFormatUnsupportedPropertyError;
    }
}

OSStatus AudioFormatGetPropertyInfo(AudioFormatPropertyID prop, UInt32 spec_size, const void *spec, UInt32 *size)
{
    if (!size)
        return kAudio_ParamError;
    *size = 0;
    return format_property(prop, spec_size, spec, size, NULL);
}

OSStatus AudioFormatGetProperty(AudioFormatPropertyID prop, UInt32 spec_size, const void *spec, UInt32 *size,
                                void *out)
{
    if (!size)
        return kAudio_ParamError;
    if (!out)
        return format_property(prop, spec_size, spec, size, NULL);
    return format_property(prop, spec_size, spec, size, out);
}
