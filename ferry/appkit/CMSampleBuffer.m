/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * CoreMedia's sample buffers, block buffers, format descriptions,
 * attachments and host time clock (freemac 1.238, Ferry 0.62.0), written
 * from Apple's public CoreMedia reference: see CoreMedia/CMSampleBuffer.h
 * and the headers beside it. They are what ScreenCaptureKit hands an app
 * (a frame's pixel buffer with its SCStreamFrameInfo attachments, or a
 * run of audio samples), and CoreMedia is served from AppKit's file.
 *
 * Each is an Objective-C object, so CFRetain, CFRelease and CFGetTypeID
 * work on them as on a Mac. A block buffer is a list of pieces, each a run
 * of a memory block of its own or of another block buffer; memory a block
 * buffer allocated itself (when given no block) is freed with it, while a
 * block the caller gave is freed only through its custom block source:
 * Ferry can't tell kCFAllocatorNull from the default allocator, so it
 * never frees what may not be its to free. Built without ARC. */
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* ---- more of a time's arithmetic -------------------------------------------------------- */

CMTime CMTimeMakeWithEpoch(int64_t value, int32_t timescale, int64_t epoch)
{
    CMTime t = CMTimeMake(value, timescale);
    if (CMTIME_IS_VALID(t))
        t.epoch = epoch;
    return t;
}
CMTime CMTimeMultiply(CMTime t, int32_t m)
{
    if (!CMTIME_IS_NUMERIC(t))
        return t;
    CMTime r = t;
    r.value = t.value * m;
    return r;
}
CMTime CMTimeMultiplyByFloat64(CMTime t, double m)
{
    if (!CMTIME_IS_NUMERIC(t))
        return t;
    return CMTimeMakeWithSeconds(CMTimeGetSeconds(t) * m, t.timescale);
}
CMTime CMTimeMultiplyByRatio(CMTime t, int32_t m, int32_t d)
{
    if (!CMTIME_IS_NUMERIC(t) || d == 0)
        return d == 0 ? kCMTimeInvalid : t;
    CMTime r = t;
    r.value = (int64_t)((__int128)t.value * m / d);
    if ((__int128)r.value * d != (__int128)t.value * m)
        r.flags |= kCMTimeFlags_HasBeenRounded;
    return r;
}
CMTime CMTimeMinimum(CMTime a, CMTime b)
{
    if (CMTIME_IS_INVALID(a) || CMTIME_IS_INVALID(b))
        return kCMTimeInvalid;
    return CMTimeCompare(a, b) <= 0 ? a : b;
}
CMTime CMTimeMaximum(CMTime a, CMTime b)
{
    if (CMTIME_IS_INVALID(a) || CMTIME_IS_INVALID(b))
        return kCMTimeInvalid;
    return CMTimeCompare(a, b) >= 0 ? a : b;
}
CMTime CMTimeAbsoluteValue(CMTime t)
{
    if (t.flags & kCMTimeFlags_NegativeInfinity)
        return kCMTimePositiveInfinity;
    if (CMTIME_IS_NUMERIC(t) && t.value < 0)
        t.value = -t.value;
    return t;
}

/* ---- the host time clock ---------------------------------------------------------------- */

@interface FerryCMClock : NSObject
@end
@implementation FerryCMClock
@end

CFTypeID CMClockGetTypeID(void) { return (CFTypeID)[FerryCMClock class]; }
CMClockRef CMClockGetHostTimeClock(void)
{
    static FerryCMClock *clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        clock = [[FerryCMClock alloc] init];
    });
    return (CMClockRef)clock;
}
CMTime CMClockMakeHostTimeFromSystemUnits(uint64_t hostTime)
{
    /* mach_absolute_time counts nanoseconds here */
    return CMTimeMake((int64_t)hostTime, 1000000000);
}
uint64_t CMClockConvertHostTimeToSystemUnits(CMTime hostTime)
{
    if (!CMTIME_IS_NUMERIC(hostTime))
        return 0;
    if (hostTime.timescale == 1000000000)
        return (uint64_t)hostTime.value;
    return (uint64_t)llround(CMTimeGetSeconds(hostTime) * 1e9);
}
CMTime CMClockGetTime(CMClockRef clock)
{
    if (!clock)
        return kCMTimeInvalid;
    return CMClockMakeHostTimeFromSystemUnits(mach_absolute_time());
}

/* ---- format descriptions ---------------------------------------------------------------- */

#define FKEY(name, value) const CFStringRef name = (CFStringRef)@value;
FKEY(kCMFormatDescriptionExtension_FormatName, "FormatName")
FKEY(kCMFormatDescriptionExtension_Depth, "Depth")
FKEY(kCMFormatDescriptionExtension_CleanAperture, "CVCleanAperture")
FKEY(kCMFormatDescriptionExtension_FieldCount, "CVFieldCount")
FKEY(kCMFormatDescriptionExtension_PixelAspectRatio, "CVPixelAspectRatio")
FKEY(kCMFormatDescriptionExtension_ColorPrimaries, "CVImageBufferColorPrimaries")
FKEY(kCMFormatDescriptionExtension_TransferFunction, "CVImageBufferTransferFunction")
FKEY(kCMFormatDescriptionExtension_YCbCrMatrix, "CVImageBufferYCbCrMatrix")
FKEY(kCMFormatDescriptionExtension_FullRangeVideo, "FullRangeVideo")
FKEY(kCMFormatDescriptionExtension_BytesPerRow, "CVBytesPerRow")
FKEY(kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms, "SampleDescriptionExtensionAtoms")
FKEY(kCMFormatDescriptionColorPrimaries_ITU_R_709_2, "ITU_R_709_2")
FKEY(kCMFormatDescriptionColorPrimaries_EBU_3213, "EBU_3213")
FKEY(kCMFormatDescriptionColorPrimaries_SMPTE_C, "SMPTE_C")
FKEY(kCMFormatDescriptionColorPrimaries_DCI_P3, "DCI_P3")
FKEY(kCMFormatDescriptionColorPrimaries_P3_D65, "P3_D65")
FKEY(kCMFormatDescriptionColorPrimaries_ITU_R_2020, "ITU_R_2020")
FKEY(kCMFormatDescriptionColorPrimaries_P22, "P22")
FKEY(kCMFormatDescriptionTransferFunction_ITU_R_709_2, "ITU_R_709_2")
FKEY(kCMFormatDescriptionTransferFunction_SMPTE_240M_1995, "SMPTE_240M_1995")
FKEY(kCMFormatDescriptionTransferFunction_UseGamma, "UseGamma")
FKEY(kCMFormatDescriptionTransferFunction_ITU_R_2020, "ITU_R_2020")
FKEY(kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1, "SMPTE_ST_428_1")
FKEY(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ, "SMPTE_ST_2084_PQ")
FKEY(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG, "ITU_R_2100_HLG")
FKEY(kCMFormatDescriptionTransferFunction_Linear, "Linear")
FKEY(kCMFormatDescriptionTransferFunction_sRGB, "IEC_sRGB")
FKEY(kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2, "ITU_R_709_2")
FKEY(kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4, "ITU_R_601_4")
FKEY(kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995, "SMPTE_240M_1995")
FKEY(kCMFormatDescriptionYCbCrMatrix_ITU_R_2020, "ITU_R_2020")

@interface FerryCMFormatDescription : NSObject {
  @public
    CMMediaType _mediaType;
    FourCharCode _subType;
    NSDictionary *_extensions;
    CMVideoDimensions _dimensions;
    AudioStreamBasicDescription _asbd;
    NSData *_layout, *_cookie;
}
@end
@implementation FerryCMFormatDescription
- (void)dealloc
{
    [_extensions release];
    [_layout release];
    [_cookie release];
    [super dealloc];
}
- (BOOL)isEqual:(id)o
{
    if (o == self)
        return YES;
    if (![o isKindOfClass:[FerryCMFormatDescription class]])
        return NO;
    FerryCMFormatDescription *d = o;
    if (d->_mediaType != _mediaType || d->_subType != _subType)
        return NO;
    if ((_extensions || d->_extensions) && ![(_extensions ?: @{}) isEqual:(d->_extensions ?: @{})])
        return NO;
    if (_mediaType == kCMMediaType_Video)
        return _dimensions.width == d->_dimensions.width && _dimensions.height == d->_dimensions.height;
    if (_mediaType == kCMMediaType_Audio)
        return !memcmp(&_asbd, &d->_asbd, sizeof _asbd) && (_layout == d->_layout || [_layout isEqual:d->_layout]) &&
               (_cookie == d->_cookie || [_cookie isEqual:d->_cookie]);
    return YES;
}
- (NSUInteger)hash { return _mediaType ^ _subType; }
- (NSString *)description
{
    char m[5] = {(char)(_mediaType >> 24), (char)(_mediaType >> 16), (char)(_mediaType >> 8), (char)_mediaType, 0};
    char s[5] = {(char)(_subType >> 24), (char)(_subType >> 16), (char)(_subType >> 8), (char)_subType, 0};
    return [NSString stringWithFormat:@"<CMFormatDescription %s '%s' %dx%d>", m, s, _dimensions.width,
                                      _dimensions.height];
}
@end

#define FD(ref) ((FerryCMFormatDescription *)(ref))
static BOOL is_format(CMFormatDescriptionRef d) { return d && [(id)d isKindOfClass:[FerryCMFormatDescription class]]; }

static FerryCMFormatDescription *new_format(CMMediaType type, FourCharCode subType, CFDictionaryRef extensions)
{
    FerryCMFormatDescription *d = [[FerryCMFormatDescription alloc] init];
    d->_mediaType = type;
    d->_subType = subType;
    if (extensions && [(id)extensions isKindOfClass:[NSDictionary class]] && [(NSDictionary *)extensions count])
        d->_extensions = [(NSDictionary *)extensions copy];
    return d;
}

CFTypeID CMFormatDescriptionGetTypeID(void) { return (CFTypeID)[FerryCMFormatDescription class]; }
OSStatus CMFormatDescriptionCreate(CFAllocatorRef allocator, CMMediaType mediaType, FourCharCode mediaSubType,
                                   CFDictionaryRef extensions, CMFormatDescriptionRef *out)
{
    if (!out)
        return kCMFormatDescriptionError_InvalidParameter;
    *out = (CMFormatDescriptionRef)new_format(mediaType, mediaSubType, extensions);
    return noErr;
}
CMMediaType CMFormatDescriptionGetMediaType(CMFormatDescriptionRef d) { return is_format(d) ? FD(d)->_mediaType : 0; }
FourCharCode CMFormatDescriptionGetMediaSubType(CMFormatDescriptionRef d) { return is_format(d) ? FD(d)->_subType : 0; }
CFDictionaryRef CMFormatDescriptionGetExtensions(CMFormatDescriptionRef d)
{
    return is_format(d) ? (CFDictionaryRef)FD(d)->_extensions : NULL;
}
CFPropertyListRef CMFormatDescriptionGetExtension(CMFormatDescriptionRef d, CFStringRef key)
{
    return is_format(d) && key ? (CFPropertyListRef)[FD(d)->_extensions objectForKey:(id)key] : NULL;
}
Boolean CMFormatDescriptionEqual(CMFormatDescriptionRef a, CMFormatDescriptionRef b)
{
    if (!a || !b)
        return a == b;
    return [(id)a isEqual:(id)b];
}

OSStatus CMVideoFormatDescriptionCreate(CFAllocatorRef allocator, CMVideoCodecType codecType, int32_t width,
                                        int32_t height, CFDictionaryRef extensions, CMVideoFormatDescriptionRef *out)
{
    if (!out || width < 0 || height < 0)
        return kCMFormatDescriptionError_InvalidParameter;
    FerryCMFormatDescription *d = new_format(kCMMediaType_Video, codecType, extensions);
    d->_dimensions = (CMVideoDimensions){width, height};
    *out = (CMVideoFormatDescriptionRef)d;
    return noErr;
}

/* the attachments of an image buffer that a format description carries */
static NSDictionary *image_extensions(CVImageBufferRef b)
{
    NSMutableDictionary *ext = [NSMutableDictionary dictionary];
    CFStringRef keys[] = {kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey, kCVImageBufferYCbCrMatrixKey,
                          kCVImageBufferPixelAspectRatioKey, kCVImageBufferCleanApertureKey, kCVImageBufferFieldCountKey};
    for (size_t i = 0; i < sizeof keys / sizeof *keys; i++) {
        CFTypeRef v = CVBufferGetAttachment(b, keys[i], NULL);
        if (v)
            ext[(id)keys[i]] = (id)v;
    }
    OSType f = CVPixelBufferGetPixelFormatType(b);
    if (f == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || f == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange)
        ext[(id)kCMFormatDescriptionExtension_FullRangeVideo] = @YES;
    if (!CVPixelBufferIsPlanar(b))
        ext[(id)kCMFormatDescriptionExtension_BytesPerRow] = @(CVPixelBufferGetBytesPerRow(b));
    return ext;
}

OSStatus CMVideoFormatDescriptionCreateForImageBuffer(CFAllocatorRef allocator, CVImageBufferRef b,
                                                      CMVideoFormatDescriptionRef *out)
{
    if (!out || !b)
        return kCMFormatDescriptionError_InvalidParameter;
    @autoreleasepool {
        FerryCMFormatDescription *d =
            new_format(kCMMediaType_Video, CVPixelBufferGetPixelFormatType(b), (CFDictionaryRef)image_extensions(b));
        d->_dimensions = (CMVideoDimensions){(int32_t)CVPixelBufferGetWidth(b), (int32_t)CVPixelBufferGetHeight(b)};
        *out = (CMVideoFormatDescriptionRef)d;
    }
    return noErr;
}
CMVideoDimensions CMVideoFormatDescriptionGetDimensions(CMVideoFormatDescriptionRef d)
{
    return is_format(d) ? FD(d)->_dimensions : (CMVideoDimensions){0, 0};
}
/* ---- H.264 and HEVC parameter sets ------------------------------------------------------
 * Kept as an MP4 file keeps them, in an avcC or hvcC atom under the
 * description's SampleDescriptionExtensionAtoms (ISO/IEC 14496-15), so a
 * description read from a file and one made from parameter sets match. */

static NSData *config_atom(CMFormatDescriptionRef d, NSString *name)
{
    if (!is_format(d))
        return nil;
    NSDictionary *atoms = FD(d)->_extensions[(id)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms];
    if (![atoms isKindOfClass:[NSDictionary class]])
        return nil;
    id v = atoms[name];
    if ([v isKindOfClass:[NSArray class]])
        v = [v firstObject];
    return [v isKindOfClass:[NSData class]] ? v : nil;
}

/* The index-th parameter set in a list of [16-bit length, bytes] entries. */
static BOOL take_set(const uint8_t **p, const uint8_t *end, const uint8_t **set, size_t *size)
{
    if (end - *p < 2)
        return NO;
    size_t n = (size_t)((*p)[0] << 8 | (*p)[1]);
    if ((size_t)(end - *p - 2) < n)
        return NO;
    *set = *p + 2;
    *size = n;
    *p += 2 + n;
    return YES;
}

static OSStatus answer_set(size_t index, size_t count, const uint8_t *found, size_t foundSize, int lengthSize,
                           const uint8_t **ptr, size_t *size, size_t *countOut, int *lengthOut)
{
    if (countOut)
        *countOut = count;
    if (lengthOut)
        *lengthOut = lengthSize;
    if ((ptr || size) && index >= count)
        return kCMFormatDescriptionError_InvalidParameter;
    if (ptr)
        *ptr = index < count ? found : NULL;
    if (size)
        *size = index < count ? foundSize : 0;
    return noErr;
}

OSStatus CMVideoFormatDescriptionGetH264ParameterSetAtIndex(CMFormatDescriptionRef d, size_t index,
                                                            const uint8_t **ptr, size_t *size, size_t *countOut,
                                                            int *lengthOut)
{
    if (!is_format(d))
        return kCMFormatDescriptionError_InvalidParameter;
    NSData *avcC = config_atom(d, @"avcC");
    if ([avcC length] < 7)
        return kCMFormatDescriptionError_ValueNotAvailable;
    const uint8_t *b = [avcC bytes], *end = b + [avcC length], *p = b + 6;
    int lengthSize = (b[4] & 3) + 1;
    size_t count = 0, foundSize = 0;
    const uint8_t *found = NULL, *set;
    size_t n;
    for (int kind = 0; kind < 2; kind++) {
        if (p >= end)
            break;
        unsigned sets = kind == 0 ? (b[5] & 0x1F) : *p;
        if (kind == 1)
            p++;
        for (unsigned i = 0; i < sets && take_set(&p, end, &set, &n); i++, count++)
            if (count == index)
                found = set, foundSize = n;
    }
    return answer_set(index, count, found, foundSize, lengthSize, ptr, size, countOut, lengthOut);
}

OSStatus CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(CMFormatDescriptionRef d, size_t index,
                                                            const uint8_t **ptr, size_t *size, size_t *countOut,
                                                            int *lengthOut)
{
    if (!is_format(d))
        return kCMFormatDescriptionError_InvalidParameter;
    NSData *hvcC = config_atom(d, @"hvcC");
    if ([hvcC length] < 23)
        return kCMFormatDescriptionError_ValueNotAvailable;
    const uint8_t *b = [hvcC bytes], *end = b + [hvcC length], *p = b + 23;
    int lengthSize = (b[21] & 3) + 1;
    size_t count = 0, foundSize = 0;
    const uint8_t *found = NULL, *set;
    size_t n;
    for (unsigned a = 0; a < b[22] && end - p >= 3; a++) {
        unsigned sets = (unsigned)(p[1] << 8 | p[2]);
        p += 3;
        for (unsigned i = 0; i < sets && take_set(&p, end, &set, &n); i++, count++)
            if (count == index)
                found = set, foundSize = n;
    }
    return answer_set(index, count, found, foundSize, lengthSize, ptr, size, countOut, lengthOut);
}

static void put_set(NSMutableData *m, const uint8_t *set, size_t n)
{
    uint8_t len[2] = {(uint8_t)(n >> 8), (uint8_t)n};
    [m appendBytes:len length:2];
    [m appendBytes:set length:n];
}

static NSDictionary *with_atom(CFDictionaryRef extensions, NSString *name, NSData *atom)
{
    NSMutableDictionary *ext =
        extensions ? [[(NSDictionary *)extensions mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    NSMutableDictionary *atoms = [[ext[(id)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] mutableCopy]
                                     autorelease] ?: [NSMutableDictionary dictionary];
    atoms[name] = atom;
    ext[(id)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] = atoms;
    return ext;
}

/* A sequence parameter set's picture size, read from its first fields
 * (H.264 7.3.2.1.1) with emulation-prevention bytes taken out. */
struct bits {
    const uint8_t *b;
    size_t n, at;
};
static unsigned bit(struct bits *r)
{
    if (r->at >= r->n * 8)
        return 0;
    unsigned v = (r->b[r->at / 8] >> (7 - r->at % 8)) & 1;
    r->at++;
    return v;
}
static unsigned bits_u(struct bits *r, int k)
{
    unsigned v = 0;
    while (k-- > 0)
        v = v << 1 | bit(r);
    return v;
}
static unsigned bits_ue(struct bits *r)
{
    int zeros = 0;
    while (!bit(r) && zeros < 32 && r->at < r->n * 8)
        zeros++;
    return ((1u << zeros) - 1) + bits_u(r, zeros);
}
static int bits_se(struct bits *r)
{
    unsigned k = bits_ue(r);
    return k & 1 ? (int)((k + 1) / 2) : -(int)(k / 2);
}
static NSData *unescaped(const uint8_t *p, size_t n)
{
    NSMutableData *m = [NSMutableData dataWithCapacity:n];
    int zeros = 0;
    for (size_t i = 0; i < n; i++) {
        if (zeros >= 2 && p[i] == 3) {
            zeros = 0;
            continue;
        }
        zeros = p[i] == 0 ? zeros + 1 : 0;
        [m appendBytes:&p[i] length:1];
    }
    return m;
}

static CMVideoDimensions h264_size(const uint8_t *sps, size_t n)
{
    NSData *raw = unescaped(sps, n);
    struct bits r = {[raw bytes], [raw length], 8};
    unsigned profile = bits_u(&r, 8);
    bits_u(&r, 16); /* constraint flags, level */
    bits_ue(&r);    /* seq_parameter_set_id */
    unsigned chroma = 1;
    if (profile == 100 || profile == 110 || profile == 122 || profile == 244 || profile == 44 || profile == 83 ||
        profile == 86 || profile == 118 || profile == 128 || profile == 138 || profile == 139 || profile == 134) {
        chroma = bits_ue(&r);
        if (chroma == 3)
            bit(&r);
        bits_ue(&r);
        bits_ue(&r);
        bit(&r);
        if (bit(&r)) /* scaling matrices */
            for (int i = 0; i < (chroma == 3 ? 12 : 8); i++)
                if (bit(&r)) {
                    int size = i < 6 ? 16 : 64, last = 8, next = 8;
                    for (int j = 0; j < size; j++) {
                        if (next)
                            next = (last + bits_se(&r) + 256) % 256;
                        last = next ? next : last;
                    }
                }
    }
    bits_ue(&r); /* log2_max_frame_num */
    unsigned poc = bits_ue(&r);
    if (poc == 0)
        bits_ue(&r);
    else if (poc == 1) {
        bit(&r);
        bits_se(&r);
        bits_se(&r);
        unsigned cycle = bits_ue(&r);
        for (unsigned i = 0; i < cycle && i < 256; i++)
            bits_se(&r);
    }
    bits_ue(&r); /* max_num_ref_frames */
    bit(&r);
    unsigned w = bits_ue(&r) + 1, h = bits_ue(&r) + 1;
    unsigned frames_only = bit(&r);
    if (!frames_only)
        bit(&r);
    bit(&r);
    int width = (int)(w * 16), height = (int)(h * 16 * (2 - frames_only));
    if (bit(&r)) { /* cropping */
        unsigned l = bits_ue(&r), rt = bits_ue(&r), t = bits_ue(&r), b = bits_ue(&r);
        int cx = chroma == 0 || chroma == 3 ? 1 : 2, cy = (chroma == 1 ? 2 : 1) * (2 - (int)frames_only);
        width -= (int)(l + rt) * cx;
        height -= (int)(t + b) * cy;
    }
    return (CMVideoDimensions){width > 0 ? width : 0, height > 0 ? height : 0};
}

OSStatus CMVideoFormatDescriptionCreateFromH264ParameterSets(CFAllocatorRef allocator, size_t count,
                                                             const uint8_t *const *sets, const size_t *sizes,
                                                             int lengthSize, CMFormatDescriptionRef *out)
{
    (void)allocator;
    if (!out || count < 2 || !sets || !sizes || (lengthSize != 1 && lengthSize != 2 && lengthSize != 4))
        return kCMFormatDescriptionError_InvalidParameter;
    *out = NULL;
    const uint8_t *sps = NULL;
    size_t spsSize = 0, nsps = 0, npps = 0;
    for (size_t i = 0; i < count; i++) {
        if (!sets[i] || !sizes[i] || sizes[i] > 0xFFFF)
            return kCMFormatDescriptionError_InvalidParameter;
        int type = sets[i][0] & 0x1F;
        if (type == 7) {
            if (!sps)
                sps = sets[i], spsSize = sizes[i];
            nsps++;
        } else if (type == 8)
            npps++;
        else
            return kCMFormatDescriptionError_InvalidParameter;
    }
    if (!nsps || !npps || spsSize < 4 || nsps > 31 || npps > 255)
        return kCMFormatDescriptionError_InvalidParameter;
    @autoreleasepool {
        NSMutableData *m = [NSMutableData data];
        uint8_t head[6] = {1, sps[1], sps[2], sps[3], (uint8_t)(0xFC | (lengthSize - 1)), (uint8_t)(0xE0 | nsps)};
        [m appendBytes:head length:6];
        for (size_t i = 0; i < count; i++)
            if ((sets[i][0] & 0x1F) == 7)
                put_set(m, sets[i], sizes[i]);
        uint8_t np = (uint8_t)npps;
        [m appendBytes:&np length:1];
        for (size_t i = 0; i < count; i++)
            if ((sets[i][0] & 0x1F) == 8)
                put_set(m, sets[i], sizes[i]);
        FerryCMFormatDescription *d =
            new_format(kCMMediaType_Video, kCMVideoCodecType_H264, (CFDictionaryRef)with_atom(NULL, @"avcC", m));
        d->_dimensions = h264_size(sps, spsSize);
        *out = (CMFormatDescriptionRef)d;
    }
    return noErr;
}

/* HEVC's sequence parameter set: its profile, tier and level (copied into
 * the hvcC atom) and its picture size (H.265 7.3.2.2). */
static CMVideoDimensions hevc_size(NSData *raw, uint8_t ptl[12], unsigned *chromaOut)
{
    struct bits r = {[raw bytes], [raw length], 16};
    bits_u(&r, 4);
    unsigned sub_layers = bits_u(&r, 3);
    bit(&r);
    for (int i = 0; i < 12; i++)
        ptl[i] = (uint8_t)bits_u(&r, 8);
    unsigned present[8] = {0};
    for (unsigned i = 0; i < sub_layers; i++)
        present[i] = bits_u(&r, 2);
    if (sub_layers)
        for (unsigned i = sub_layers; i < 8; i++)
            bits_u(&r, 2);
    for (unsigned i = 0; i < sub_layers; i++) {
        if (present[i] & 2)
            bits_u(&r, 32), bits_u(&r, 32), bits_u(&r, 24);
        if (present[i] & 1)
            bits_u(&r, 8);
    }
    bits_ue(&r); /* sps id */
    unsigned chroma = bits_ue(&r);
    if (chroma == 3)
        bit(&r);
    *chromaOut = chroma;
    int width = (int)bits_ue(&r), height = (int)bits_ue(&r);
    if (bit(&r)) {
        unsigned l = bits_ue(&r), rt = bits_ue(&r), t = bits_ue(&r), b = bits_ue(&r);
        int cx = chroma == 1 || chroma == 2 ? 2 : 1, cy = chroma == 1 ? 2 : 1;
        width -= (int)(l + rt) * cx;
        height -= (int)(t + b) * cy;
    }
    return (CMVideoDimensions){width > 0 ? width : 0, height > 0 ? height : 0};
}

OSStatus CMVideoFormatDescriptionCreateFromHEVCParameterSets(CFAllocatorRef allocator, size_t count,
                                                             const uint8_t *const *sets, const size_t *sizes,
                                                             int lengthSize, CFDictionaryRef extensions,
                                                             CMFormatDescriptionRef *out)
{
    (void)allocator;
    if (!out || count < 3 || !sets || !sizes || (lengthSize != 1 && lengthSize != 2 && lengthSize != 4))
        return kCMFormatDescriptionError_InvalidParameter;
    *out = NULL;
    /* the arrays an hvcC holds, in the usual order: VPS, SPS, PPS, then SEI */
    static const int kinds[] = {32, 33, 34, 39, 40};
    size_t per[5] = {0};
    const uint8_t *sps = NULL;
    size_t spsSize = 0;
    for (size_t i = 0; i < count; i++) {
        if (!sets[i] || sizes[i] < 2 || sizes[i] > 0xFFFF)
            return kCMFormatDescriptionError_InvalidParameter;
        int type = (sets[i][0] >> 1) & 0x3F, k;
        for (k = 0; k < 5 && kinds[k] != type; k++)
            ;
        if (k == 5)
            return kCMFormatDescriptionError_InvalidParameter;
        per[k]++;
        if (type == 33 && !sps)
            sps = sets[i], spsSize = sizes[i];
    }
    if (!per[0] || !per[1] || !per[2])
        return kCMFormatDescriptionError_InvalidParameter;
    @autoreleasepool {
        uint8_t ptl[12] = {0};
        unsigned chroma = 1;
        CMVideoDimensions dims = hevc_size(unescaped(sps, spsSize), ptl, &chroma);
        NSMutableData *m = [NSMutableData data];
        uint8_t head[23] = {1};
        memcpy(head + 1, ptl, 12);
        head[13] = 0xF0; /* min_spatial_segmentation 0 */
        head[15] = 0xFC; /* parallelism unknown */
        head[16] = (uint8_t)(0xFC | (chroma & 3));
        head[17] = 0xF8; /* bit depths: not read here, left as 8 */
        head[18] = 0xF8;
        head[21] = (uint8_t)(lengthSize - 1);
        uint8_t arrays = 0;
        for (int k = 0; k < 5; k++)
            arrays += per[k] ? 1 : 0;
        head[22] = arrays;
        [m appendBytes:head length:23];
        for (int k = 0; k < 5; k++) {
            if (!per[k])
                continue;
            uint8_t a[3] = {(uint8_t)(0x80 | kinds[k]), (uint8_t)(per[k] >> 8), (uint8_t)per[k]};
            [m appendBytes:a length:3];
            for (size_t i = 0; i < count; i++)
                if (((sets[i][0] >> 1) & 0x3F) == kinds[k])
                    put_set(m, sets[i], sizes[i]);
        }
        FerryCMFormatDescription *d =
            new_format(kCMMediaType_Video, kCMVideoCodecType_HEVC, (CFDictionaryRef)with_atom(extensions, @"hvcC", m));
        d->_dimensions = dims;
        *out = (CMFormatDescriptionRef)d;
    }
    return noErr;
}

CGSize CMVideoFormatDescriptionGetPresentationDimensions(CMVideoFormatDescriptionRef d, Boolean usePixelAspectRatio,
                                                         Boolean useCleanAperture)
{
    if (!is_format(d))
        return CGSizeZero;
    CGSize s = CGSizeMake(FD(d)->_dimensions.width, FD(d)->_dimensions.height);
    NSDictionary *ap = FD(d)->_extensions[(id)kCMFormatDescriptionExtension_CleanAperture];
    if (useCleanAperture && [ap isKindOfClass:[NSDictionary class]]) {
        id w = ap[@"Width"], h = ap[@"Height"];
        if ([w respondsToSelector:@selector(doubleValue)] && [h respondsToSelector:@selector(doubleValue)])
            s = CGSizeMake([w doubleValue], [h doubleValue]);
    }
    NSDictionary *par = FD(d)->_extensions[(id)kCMFormatDescriptionExtension_PixelAspectRatio];
    if (usePixelAspectRatio && [par isKindOfClass:[NSDictionary class]]) {
        double hs = [par[@"HorizontalSpacing"] doubleValue], vs = [par[@"VerticalSpacing"] doubleValue];
        if (hs > 0 && vs > 0)
            s.width = s.width * hs / vs;
    }
    return s;
}
/* The clean aperture as a rectangle in the encoded picture (freemac 1.NEXT,
 * for Qt Multimedia): the CleanAperture extension's size, centred in the
 * picture and moved by its offsets, which are from the picture's centre;
 * the whole picture when there's no extension. Qt asks with the origin at
 * the top left, where a positive vertical offset is downwards. */
CGRect CMVideoFormatDescriptionGetCleanAperture(CMVideoFormatDescriptionRef d, Boolean originIsAtTopLeft)
{
    if (!is_format(d))
        return CGRectZero;
    double W = FD(d)->_dimensions.width, H = FD(d)->_dimensions.height;
    NSDictionary *ap = FD(d)->_extensions[(id)kCMFormatDescriptionExtension_CleanAperture];
    if (![ap isKindOfClass:[NSDictionary class]])
        return CGRectMake(0, 0, W, H);
    double w = [ap[@"Width"] respondsToSelector:@selector(doubleValue)] ? [ap[@"Width"] doubleValue] : W;
    double h = [ap[@"Height"] respondsToSelector:@selector(doubleValue)] ? [ap[@"Height"] doubleValue] : H;
    double dx = [ap[@"HorizontalOffset"] respondsToSelector:@selector(doubleValue)] ? [ap[@"HorizontalOffset"] doubleValue] : 0;
    double dy = [ap[@"VerticalOffset"] respondsToSelector:@selector(doubleValue)] ? [ap[@"VerticalOffset"] doubleValue] : 0;
    return CGRectMake((W - w) / 2 + dx, (H - h) / 2 + (originIsAtTopLeft ? dy : -dy), w, h);
}
Boolean CMVideoFormatDescriptionMatchesImageBuffer(CMVideoFormatDescriptionRef d, CVImageBufferRef b)
{
    if (!is_format(d) || !b)
        return false;
    return FD(d)->_mediaType == kCMMediaType_Video && FD(d)->_subType == CVPixelBufferGetPixelFormatType(b) &&
           (size_t)FD(d)->_dimensions.width == CVPixelBufferGetWidth(b) &&
           (size_t)FD(d)->_dimensions.height == CVPixelBufferGetHeight(b);
}

OSStatus CMAudioFormatDescriptionCreate(CFAllocatorRef allocator, const AudioStreamBasicDescription *asbd,
                                        size_t layoutSize, const AudioChannelLayout *layout, size_t cookieSize,
                                        const void *cookie, CFDictionaryRef extensions,
                                        CMAudioFormatDescriptionRef *out)
{
    if (!out || !asbd || (layoutSize && !layout) || (cookieSize && !cookie))
        return kCMFormatDescriptionError_InvalidParameter;
    FerryCMFormatDescription *d = new_format(kCMMediaType_Audio, asbd->mFormatID, extensions);
    d->_asbd = *asbd;
    if (layoutSize)
        d->_layout = [[NSData alloc] initWithBytes:layout length:layoutSize];
    if (cookieSize)
        d->_cookie = [[NSData alloc] initWithBytes:cookie length:cookieSize];
    *out = (CMAudioFormatDescriptionRef)d;
    return noErr;
}
const AudioStreamBasicDescription *CMAudioFormatDescriptionGetStreamBasicDescription(CMAudioFormatDescriptionRef d)
{
    return is_format(d) && FD(d)->_mediaType == kCMMediaType_Audio ? &FD(d)->_asbd : NULL;
}
const AudioChannelLayout *CMAudioFormatDescriptionGetChannelLayout(CMAudioFormatDescriptionRef d, size_t *size)
{
    NSData *l = is_format(d) ? FD(d)->_layout : nil;
    if (size)
        *size = [l length];
    return l ? [l bytes] : NULL;
}
const void *CMAudioFormatDescriptionGetMagicCookie(CMAudioFormatDescriptionRef d, size_t *size)
{
    NSData *c = is_format(d) ? FD(d)->_cookie : nil;
    if (size)
        *size = [c length];
    return c ? [c bytes] : NULL;
}

/* ---- block buffers ---------------------------------------------------------------------- */

struct piece {
    char *block;                         /* a memory block, NULL until allocated (or a reference's) */
    size_t blockLength;
    BOOL ours;                           /* allocated here, freed with free() */
    BOOL hasSource;
    CMBlockBufferCustomBlockSource source;
    id reference;                        /* a block buffer referred to, retained */
    size_t offset, length;               /* the run of the block or reference */
};

@interface FerryCMBlockBuffer : NSObject {
  @public
    struct piece *_pieces;
    size_t _count, _capacity;
    size_t _length;
}
@end

#define BB(ref) ((FerryCMBlockBuffer *)(ref))
static BOOL is_block_buffer(CMBlockBufferRef b) { return b && [(id)b isKindOfClass:[FerryCMBlockBuffer class]]; }

@implementation FerryCMBlockBuffer
- (void)dealloc
{
    for (size_t i = 0; i < _count; i++) {
        struct piece *p = &_pieces[i];
        if (p->reference)
            [p->reference release];
        else if (p->block && p->hasSource && p->source.FreeBlock)
            p->source.FreeBlock(p->source.refCon, p->block, p->blockLength);
        else if (p->block && p->ours)
            free(p->block);
    }
    free(_pieces);
    [super dealloc];
}
- (struct piece *)_newPiece
{
    if (_count == _capacity) {
        _capacity = _capacity ? _capacity * 2 : 4;
        _pieces = realloc(_pieces, _capacity * sizeof *_pieces);
    }
    struct piece *p = &_pieces[_count++];
    memset(p, 0, sizeof *p);
    return p;
}
@end

static OSStatus allocate_piece(struct piece *p)
{
    if (p->block || p->reference)
        return noErr;
    if (p->hasSource && p->source.AllocateBlock)
        p->block = p->source.AllocateBlock(p->source.refCon, p->blockLength);
    else {
        p->block = calloc(1, p->blockLength ? p->blockLength : 1);
        p->ours = YES;
    }
    return p->block ? noErr : kCMBlockBufferBlockAllocationFailedErr;
}

/* Where byte offset of the buffer is: the piece's index and the offset in it. */
static BOOL find_offset(FerryCMBlockBuffer *b, size_t offset, size_t *index, size_t *within)
{
    for (size_t i = 0; i < b->_count; i++) {
        if (offset < b->_pieces[i].length) {
            *index = i;
            *within = offset;
            return YES;
        }
        offset -= b->_pieces[i].length;
    }
    return NO;
}

/* A pointer to the bytes at offset and how many follow contiguously, allocating as it goes. */
static char *bytes_at(FerryCMBlockBuffer *b, size_t offset, size_t *runOut)
{
    size_t i, within;
    if (!find_offset(b, offset, &i, &within))
        return NULL;
    struct piece *p = &b->_pieces[i];
    if (p->reference) {
        size_t run = 0;
        char *ptr = bytes_at(p->reference, p->offset + within, &run);
        if (runOut)
            *runOut = MIN(run, p->length - within);
        return ptr;
    }
    if (allocate_piece(p) != noErr)
        return NULL;
    if (runOut)
        *runOut = p->length - within;
    return p->block + p->offset + within;
}

CFTypeID CMBlockBufferGetTypeID(void) { return (CFTypeID)[FerryCMBlockBuffer class]; }

OSStatus CMBlockBufferCreateEmpty(CFAllocatorRef structureAllocator, uint32_t capacity, CMBlockBufferFlags flags,
                                  CMBlockBufferRef *out)
{
    if (!out)
        return kCMBlockBufferBadPointerParameterErr;
    FerryCMBlockBuffer *b = [[FerryCMBlockBuffer alloc] init];
    if (capacity) {
        b->_capacity = capacity;
        b->_pieces = calloc(capacity, sizeof *b->_pieces);
    }
    *out = (CMBlockBufferRef)b;
    return noErr;
}

OSStatus CMBlockBufferAppendMemoryBlock(CMBlockBufferRef buf, void *memoryBlock, size_t blockLength,
                                        CFAllocatorRef blockAllocator, const CMBlockBufferCustomBlockSource *source,
                                        size_t offsetToData, size_t dataLength, CMBlockBufferFlags flags)
{
    if (!is_block_buffer(buf))
        return kCMBlockBufferBadPointerParameterErr;
    if (!blockLength && !memoryBlock)
        return kCMBlockBufferBadLengthParameterErr;
    if (offsetToData > blockLength || dataLength > blockLength - offsetToData)
        return kCMBlockBufferBadOffsetParameterErr;
    struct piece *p = [BB(buf) _newPiece];
    p->block = memoryBlock;
    p->blockLength = blockLength;
    if (source) {
        p->hasSource = YES;
        p->source = *source;
    }
    p->offset = offsetToData;
    p->length = dataLength;
    BB(buf)->_length += dataLength;
    if (flags & kCMBlockBufferAssureMemoryNowFlag) {
        OSStatus s = allocate_piece(p);
        if (s != noErr)
            return s;
    }
    return noErr;
}

OSStatus CMBlockBufferCreateWithMemoryBlock(CFAllocatorRef structureAllocator, void *memoryBlock, size_t blockLength,
                                            CFAllocatorRef blockAllocator,
                                            const CMBlockBufferCustomBlockSource *source, size_t offsetToData,
                                            size_t dataLength, CMBlockBufferFlags flags, CMBlockBufferRef *out)
{
    if (!out)
        return kCMBlockBufferBadPointerParameterErr;
    *out = NULL;
    CMBlockBufferRef b = NULL;
    CMBlockBufferCreateEmpty(structureAllocator, 1, 0, &b);
    OSStatus s = CMBlockBufferAppendMemoryBlock(b, memoryBlock, blockLength, blockAllocator, source, offsetToData,
                                                dataLength, flags);
    if (s != noErr) {
        CFRelease(b);
        return s;
    }
    *out = b;
    return noErr;
}

OSStatus CMBlockBufferAppendBufferReference(CMBlockBufferRef buf, CMBlockBufferRef target, size_t offsetToData,
                                            size_t dataLength, CMBlockBufferFlags flags)
{
    if (!is_block_buffer(buf) || !is_block_buffer(target))
        return kCMBlockBufferBadPointerParameterErr;
    size_t total = BB(target)->_length;
    if (offsetToData > total)
        return kCMBlockBufferBadOffsetParameterErr;
    if (!dataLength && !(flags & kCMBlockBufferPermitEmptyReferenceFlag))
        dataLength = total - offsetToData;
    if (dataLength > total - offsetToData)
        return kCMBlockBufferBadLengthParameterErr;
    struct piece *p = [BB(buf) _newPiece];
    p->reference = [(id)target retain];
    p->offset = offsetToData;
    p->length = dataLength;
    BB(buf)->_length += dataLength;
    return noErr;
}

OSStatus CMBlockBufferCreateWithBufferReference(CFAllocatorRef structureAllocator, CMBlockBufferRef reference,
                                                size_t offsetToData, size_t dataLength, CMBlockBufferFlags flags,
                                                CMBlockBufferRef *out)
{
    if (!out)
        return kCMBlockBufferBadPointerParameterErr;
    *out = NULL;
    CMBlockBufferRef b = NULL;
    CMBlockBufferCreateEmpty(structureAllocator, 1, 0, &b);
    OSStatus s = CMBlockBufferAppendBufferReference(b, reference, offsetToData, dataLength, flags);
    if (s != noErr) {
        CFRelease(b);
        return s;
    }
    *out = b;
    return noErr;
}

OSStatus CMBlockBufferCopyDataBytes(CMBlockBufferRef src, size_t offset, size_t length, void *dest)
{
    if (!is_block_buffer(src) || (!dest && length))
        return kCMBlockBufferBadPointerParameterErr;
    if (offset > BB(src)->_length || length > BB(src)->_length - offset)
        return kCMBlockBufferBadOffsetParameterErr;
    char *to = dest;
    while (length) {
        size_t run = 0;
        char *from = bytes_at(BB(src), offset, &run);
        if (!from)
            return kCMBlockBufferBlockAllocationFailedErr;
        size_t n = MIN(run, length);
        memcpy(to, from, n);
        to += n;
        offset += n;
        length -= n;
    }
    return noErr;
}

OSStatus CMBlockBufferReplaceDataBytes(const void *source, CMBlockBufferRef dest, size_t offset, size_t length)
{
    if (!is_block_buffer(dest) || (!source && length))
        return kCMBlockBufferBadPointerParameterErr;
    if (offset > BB(dest)->_length || length > BB(dest)->_length - offset)
        return kCMBlockBufferBadOffsetParameterErr;
    const char *from = source;
    while (length) {
        size_t run = 0;
        char *to = bytes_at(BB(dest), offset, &run);
        if (!to)
            return kCMBlockBufferBlockAllocationFailedErr;
        size_t n = MIN(run, length);
        memcpy(to, from, n);
        from += n;
        offset += n;
        length -= n;
    }
    return noErr;
}

OSStatus CMBlockBufferFillDataBytes(char fill, CMBlockBufferRef dest, size_t offset, size_t length)
{
    if (!is_block_buffer(dest))
        return kCMBlockBufferBadPointerParameterErr;
    if (offset > BB(dest)->_length || length > BB(dest)->_length - offset)
        return kCMBlockBufferBadOffsetParameterErr;
    while (length) {
        size_t run = 0;
        char *to = bytes_at(BB(dest), offset, &run);
        if (!to)
            return kCMBlockBufferBlockAllocationFailedErr;
        size_t n = MIN(run, length);
        memset(to, fill, n);
        offset += n;
        length -= n;
    }
    return noErr;
}

OSStatus CMBlockBufferCreateContiguous(CFAllocatorRef structureAllocator, CMBlockBufferRef src,
                                       CFAllocatorRef blockAllocator, const CMBlockBufferCustomBlockSource *source,
                                       size_t offsetToData, size_t dataLength, CMBlockBufferFlags flags,
                                       CMBlockBufferRef *out)
{
    if (!out || !is_block_buffer(src))
        return kCMBlockBufferBadPointerParameterErr;
    *out = NULL;
    size_t total = BB(src)->_length;
    if (offsetToData > total)
        return kCMBlockBufferBadOffsetParameterErr;
    if (!dataLength)
        dataLength = total - offsetToData;
    if (dataLength > total - offsetToData)
        return kCMBlockBufferBadLengthParameterErr;
    if (!(flags & kCMBlockBufferAlwaysCopyDataFlag) && CMBlockBufferIsRangeContiguous(src, offsetToData, dataLength) &&
        dataLength)
        return CMBlockBufferCreateWithBufferReference(structureAllocator, src, offsetToData, dataLength, 0, out);
    CMBlockBufferRef b = NULL;
    OSStatus s = CMBlockBufferCreateWithMemoryBlock(structureAllocator, NULL, dataLength ? dataLength : 1, blockAllocator,
                                                    source, 0, dataLength, kCMBlockBufferAssureMemoryNowFlag, &b);
    if (s != noErr)
        return s;
    s = CMBlockBufferCopyDataBytes(src, offsetToData, dataLength, BB(b)->_pieces[0].block);
    if (s != noErr) {
        CFRelease(b);
        return s;
    }
    *out = b;
    return noErr;
}

OSStatus CMBlockBufferAssureBlockMemory(CMBlockBufferRef buf)
{
    if (!is_block_buffer(buf))
        return kCMBlockBufferBadPointerParameterErr;
    for (size_t i = 0; i < BB(buf)->_count; i++) {
        struct piece *p = &BB(buf)->_pieces[i];
        OSStatus s = p->reference ? CMBlockBufferAssureBlockMemory((CMBlockBufferRef)p->reference) : allocate_piece(p);
        if (s != noErr)
            return s;
    }
    return noErr;
}

OSStatus CMBlockBufferAccessDataBytes(CMBlockBufferRef buf, size_t offset, size_t length, void *temporaryBlock,
                                      char **out)
{
    if (!is_block_buffer(buf) || !out)
        return kCMBlockBufferBadPointerParameterErr;
    if (offset > BB(buf)->_length || length > BB(buf)->_length - offset)
        return kCMBlockBufferBadOffsetParameterErr;
    size_t run = 0;
    char *p = bytes_at(BB(buf), offset, &run);
    if (p && run >= length) {
        *out = p;
        return noErr;
    }
    if (!temporaryBlock)
        return kCMBlockBufferBadPointerParameterErr;
    OSStatus s = CMBlockBufferCopyDataBytes(buf, offset, length, temporaryBlock);
    *out = s == noErr ? temporaryBlock : NULL;
    return s;
}

OSStatus CMBlockBufferGetDataPointer(CMBlockBufferRef buf, size_t offset, size_t *lengthAtOffset, size_t *totalLength,
                                     char **dataPointer)
{
    if (!is_block_buffer(buf))
        return kCMBlockBufferBadPointerParameterErr;
    if (offset >= BB(buf)->_length && !(offset == 0 && BB(buf)->_length == 0))
        return kCMBlockBufferBadOffsetParameterErr;
    size_t run = 0;
    char *p = BB(buf)->_length ? bytes_at(BB(buf), offset, &run) : NULL;
    if (BB(buf)->_length && !p)
        return kCMBlockBufferBlockAllocationFailedErr;
    if (lengthAtOffset)
        *lengthAtOffset = run;
    if (totalLength)
        *totalLength = BB(buf)->_length;
    if (dataPointer)
        *dataPointer = p;
    return BB(buf)->_length ? noErr : kCMBlockBufferEmptyBBufErr;
}

size_t CMBlockBufferGetDataLength(CMBlockBufferRef buf) { return is_block_buffer(buf) ? BB(buf)->_length : 0; }
Boolean CMBlockBufferIsEmpty(CMBlockBufferRef buf) { return !is_block_buffer(buf) || BB(buf)->_length == 0; }
Boolean CMBlockBufferIsRangeContiguous(CMBlockBufferRef buf, size_t offset, size_t length)
{
    if (!is_block_buffer(buf))
        return false;
    if (!length)
        length = BB(buf)->_length - MIN(offset, BB(buf)->_length);
    if (offset > BB(buf)->_length || length > BB(buf)->_length - offset)
        return false;
    size_t i, within;
    if (!find_offset(BB(buf), offset, &i, &within))
        return length == 0;
    struct piece *p = &BB(buf)->_pieces[i];
    if (p->reference)
        return p->length - within >= length &&
               CMBlockBufferIsRangeContiguous((CMBlockBufferRef)p->reference, p->offset + within, length);
    return p->length - within >= length;
}

/* ---- sample buffers --------------------------------------------------------------------- */

#define SKEY(name, value) const CFStringRef name = (CFStringRef)@value;
SKEY(kCMSampleAttachmentKey_NotSync, "NotSync")
SKEY(kCMSampleAttachmentKey_PartialSync, "PartialSync")
SKEY(kCMSampleAttachmentKey_HasRedundantCoding, "HasRedundantCoding")
SKEY(kCMSampleAttachmentKey_IsDependedOnByOthers, "IsDependedOnByOthers")
SKEY(kCMSampleAttachmentKey_DependsOnOthers, "DependsOnOthers")
SKEY(kCMSampleAttachmentKey_EarlierDisplayTimesAllowed, "EarlierDisplayTimesAllowed")
SKEY(kCMSampleAttachmentKey_DisplayImmediately, "DisplayImmediately")
SKEY(kCMSampleAttachmentKey_DoNotDisplay, "DoNotDisplay")
SKEY(kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding, "ResetDecoderBeforeDecoding")
SKEY(kCMSampleBufferAttachmentKey_DrainAfterDecoding, "DrainAfterDecoding")
SKEY(kCMSampleBufferAttachmentKey_EmptyMedia, "EmptyMedia")
SKEY(kCMSampleBufferAttachmentKey_DisplayEmptyMediaImmediately, "DisplayEmptyMediaImmediately")

const CMSampleTimingInfo kCMTimingInfoInvalid = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}};

@interface FerryCMSampleBuffer : NSObject {
  @public
    id _data;                    /* a block buffer */
    id _image;                   /* or an image buffer */
    id _format;
    CMItemCount _numSamples;
    CMSampleTimingInfo *_timing;
    CMItemCount _timingCount;
    size_t *_sizes;
    CMItemCount _sizeCount;
    NSMutableArray *_sampleAttachments;
    NSMutableDictionary *_attachments[2]; /* not propagated, propagated */
    BOOL _invalid, _ready, _hasOutputPTS;
    CMTime _outputPTS;
    CMSampleBufferMakeDataReadyCallback _makeReady;
    void *_makeReadyRefcon;
    pthread_mutex_t _lock;
}
@end

#define SB(ref) ((FerryCMSampleBuffer *)(ref))
static BOOL is_sample_buffer(CFTypeRef b) { return b && [(id)b isKindOfClass:[FerryCMSampleBuffer class]]; }

@implementation FerryCMSampleBuffer
- (instancetype)init
{
    if ((self = [super init])) {
        _attachments[0] = [[NSMutableDictionary alloc] init];
        _attachments[1] = [[NSMutableDictionary alloc] init];
        pthread_mutex_init(&_lock, NULL);
    }
    return self;
}
- (void)dealloc
{
    [_data release];
    [_image release];
    [_format release];
    [_sampleAttachments release];
    [_attachments[0] release];
    [_attachments[1] release];
    free(_timing);
    free(_sizes);
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CMSampleBuffer %p samples %ld %@>", self, (long)_numSamples,
                                      _image ? @"image" : @"data"];
}
@end

static OSStatus fill_sample_buffer(FerryCMSampleBuffer *b, CMItemCount numSamples, CMItemCount timingCount,
                                   const CMSampleTimingInfo *timing, CMItemCount sizeCount, const size_t *sizes)
{
    if (numSamples < 0 || timingCount < 0 || sizeCount < 0)
        return kCMSampleBufferError_InvalidEntryCount;
    if ((timingCount && !timing) || (sizeCount && !sizes))
        return kCMSampleBufferError_RequiredParameterMissing;
    if (timingCount > 1 && timingCount != numSamples)
        return kCMSampleBufferError_InvalidEntryCount;
    if (sizeCount > 1 && sizeCount != numSamples)
        return kCMSampleBufferError_InvalidEntryCount;
    b->_numSamples = numSamples;
    if (timingCount) {
        b->_timing = malloc((size_t)timingCount * sizeof *timing);
        memcpy(b->_timing, timing, (size_t)timingCount * sizeof *timing);
        b->_timingCount = timingCount;
    }
    if (sizeCount) {
        b->_sizes = malloc((size_t)sizeCount * sizeof *sizes);
        memcpy(b->_sizes, sizes, (size_t)sizeCount * sizeof *sizes);
        b->_sizeCount = sizeCount;
    }
    return noErr;
}

CFTypeID CMSampleBufferGetTypeID(void) { return (CFTypeID)[FerryCMSampleBuffer class]; }

OSStatus CMSampleBufferCreate(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, Boolean dataReady,
                              CMSampleBufferMakeDataReadyCallback makeReady, void *refcon,
                              CMFormatDescriptionRef format, CMItemCount numSamples, CMItemCount timingCount,
                              const CMSampleTimingInfo *timing, CMItemCount sizeCount, const size_t *sizes,
                              CMSampleBufferRef *out)
{
    if (!out)
        return kCMSampleBufferError_RequiredParameterMissing;
    *out = NULL;
    if (dataBuffer && !is_block_buffer(dataBuffer))
        return kCMSampleBufferError_RequiredParameterMissing;
    if (numSamples && !dataBuffer && dataReady)
        return kCMSampleBufferError_RequiredParameterMissing;
    FerryCMSampleBuffer *b = [[FerryCMSampleBuffer alloc] init];
    OSStatus s = fill_sample_buffer(b, numSamples, timingCount, timing, sizeCount, sizes);
    if (s != noErr) {
        [b release];
        return s;
    }
    b->_data = [(id)dataBuffer retain];
    b->_format = [(id)format retain];
    b->_ready = dataReady;
    b->_makeReady = makeReady;
    b->_makeReadyRefcon = refcon;
    *out = (CMSampleBufferRef)b;
    return noErr;
}

OSStatus CMSampleBufferCreateReady(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, CMFormatDescriptionRef format,
                                   CMItemCount numSamples, CMItemCount timingCount, const CMSampleTimingInfo *timing,
                                   CMItemCount sizeCount, const size_t *sizes, CMSampleBufferRef *out)
{
    return CMSampleBufferCreate(allocator, dataBuffer, true, NULL, NULL, format, numSamples, timingCount, timing,
                                sizeCount, sizes, out);
}

OSStatus CMSampleBufferCreateForImageBuffer(CFAllocatorRef allocator, CVImageBufferRef image, Boolean dataReady,
                                            CMSampleBufferMakeDataReadyCallback makeReady, void *refcon,
                                            CMVideoFormatDescriptionRef format, const CMSampleTimingInfo *timing,
                                            CMSampleBufferRef *out)
{
    if (!out)
        return kCMSampleBufferError_RequiredParameterMissing;
    *out = NULL;
    if (!image || !format || !timing)
        return kCMSampleBufferError_RequiredParameterMissing;
    if (!CMVideoFormatDescriptionMatchesImageBuffer(format, image))
        return kCMSampleBufferError_InvalidMediaFormat;
    FerryCMSampleBuffer *b = [[FerryCMSampleBuffer alloc] init];
    fill_sample_buffer(b, 1, 1, timing, 0, NULL);
    b->_image = [(id)image retain];
    b->_format = [(id)format retain];
    b->_ready = dataReady;
    b->_makeReady = makeReady;
    b->_makeReadyRefcon = refcon;
    *out = (CMSampleBufferRef)b;
    return noErr;
}

OSStatus CMSampleBufferCreateReadyWithImageBuffer(CFAllocatorRef allocator, CVImageBufferRef image,
                                                  CMVideoFormatDescriptionRef format, const CMSampleTimingInfo *timing,
                                                  CMSampleBufferRef *out)
{
    return CMSampleBufferCreateForImageBuffer(allocator, image, true, NULL, NULL, format, timing, out);
}

static FerryCMSampleBuffer *copy_of(FerryCMSampleBuffer *o, BOOL withTiming)
{
    FerryCMSampleBuffer *b = [[FerryCMSampleBuffer alloc] init];
    pthread_mutex_lock(&o->_lock);
    fill_sample_buffer(b, o->_numSamples, withTiming ? o->_timingCount : 0, o->_timing, o->_sizeCount, o->_sizes);
    b->_data = [o->_data retain];
    b->_image = [o->_image retain];
    b->_format = [o->_format retain];
    b->_ready = o->_ready;
    b->_makeReady = o->_makeReady;
    b->_makeReadyRefcon = o->_makeReadyRefcon;
    b->_invalid = o->_invalid;
    if (o->_sampleAttachments) {
        b->_sampleAttachments = [[NSMutableArray alloc] init];
        for (NSDictionary *d in o->_sampleAttachments)
            [b->_sampleAttachments addObject:[[d mutableCopy] autorelease]];
    }
    [b->_attachments[0] setDictionary:o->_attachments[0]];
    [b->_attachments[1] setDictionary:o->_attachments[1]];
    pthread_mutex_unlock(&o->_lock);
    return b;
}

OSStatus CMSampleBufferCreateCopy(CFAllocatorRef allocator, CMSampleBufferRef sbuf, CMSampleBufferRef *out)
{
    if (!out || !is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    *out = (CMSampleBufferRef)copy_of(SB(sbuf), YES);
    return noErr;
}

OSStatus CMSampleBufferCreateCopyWithNewTiming(CFAllocatorRef allocator, CMSampleBufferRef sbuf,
                                               CMItemCount timingCount, const CMSampleTimingInfo *timing,
                                               CMSampleBufferRef *out)
{
    if (!out || !is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    *out = NULL;
    if ((timingCount && !timing) || timingCount < 0 || (timingCount > 1 && timingCount != SB(sbuf)->_numSamples))
        return kCMSampleBufferError_InvalidEntryCount;
    FerryCMSampleBuffer *b = copy_of(SB(sbuf), NO);
    if (timingCount) {
        b->_timing = malloc((size_t)timingCount * sizeof *timing);
        memcpy(b->_timing, timing, (size_t)timingCount * sizeof *timing);
        b->_timingCount = timingCount;
    }
    *out = (CMSampleBufferRef)b;
    return noErr;
}

OSStatus CMSampleBufferSetDataBuffer(CMSampleBufferRef sbuf, CMBlockBufferRef data)
{
    if (!is_sample_buffer(sbuf) || !is_block_buffer(data))
        return kCMSampleBufferError_RequiredParameterMissing;
    if (SB(sbuf)->_data || SB(sbuf)->_image)
        return kCMSampleBufferError_AlreadyHasDataBuffer;
    SB(sbuf)->_data = [(id)data retain];
    return noErr;
}
OSStatus CMSampleBufferSetDataReady(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    SB(sbuf)->_ready = YES;
    return noErr;
}
OSStatus CMSampleBufferMakeDataReady(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    if (SB(sbuf)->_ready)
        return noErr;
    if (!SB(sbuf)->_makeReady)
        return kCMSampleBufferError_BufferNotReady;
    OSStatus s = SB(sbuf)->_makeReady(sbuf, SB(sbuf)->_makeReadyRefcon);
    if (s == noErr)
        SB(sbuf)->_ready = YES;
    return s;
}
Boolean CMSampleBufferDataIsReady(CMSampleBufferRef sbuf) { return is_sample_buffer(sbuf) && SB(sbuf)->_ready; }
Boolean CMSampleBufferIsValid(CMSampleBufferRef sbuf) { return is_sample_buffer(sbuf) && !SB(sbuf)->_invalid; }
OSStatus CMSampleBufferInvalidate(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    SB(sbuf)->_invalid = YES;
    return noErr;
}

CVImageBufferRef CMSampleBufferGetImageBuffer(CMSampleBufferRef sbuf)
{
    return is_sample_buffer(sbuf) ? (CVImageBufferRef)SB(sbuf)->_image : NULL;
}
CMBlockBufferRef CMSampleBufferGetDataBuffer(CMSampleBufferRef sbuf)
{
    return is_sample_buffer(sbuf) ? (CMBlockBufferRef)SB(sbuf)->_data : NULL;
}
CMFormatDescriptionRef CMSampleBufferGetFormatDescription(CMSampleBufferRef sbuf)
{
    return is_sample_buffer(sbuf) ? (CMFormatDescriptionRef)SB(sbuf)->_format : NULL;
}
CMItemCount CMSampleBufferGetNumSamples(CMSampleBufferRef sbuf) { return is_sample_buffer(sbuf) ? SB(sbuf)->_numSamples : 0; }

CMTime CMSampleBufferGetDuration(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf) || !SB(sbuf)->_timingCount)
        return kCMTimeInvalid;
    FerryCMSampleBuffer *b = SB(sbuf);
    if (b->_timingCount == 1)
        return b->_numSamples > 1 ? CMTimeMultiply(b->_timing[0].duration, (int32_t)b->_numSamples) : b->_timing[0].duration;
    CMTime total = b->_timing[0].duration;
    for (CMItemCount i = 1; i < b->_timingCount; i++)
        total = CMTimeAdd(total, b->_timing[i].duration);
    return total;
}
CMTime CMSampleBufferGetPresentationTimeStamp(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf) || !SB(sbuf)->_timingCount)
        return kCMTimeInvalid;
    /* the earliest of the samples' */
    CMTime t = SB(sbuf)->_timing[0].presentationTimeStamp;
    for (CMItemCount i = 1; i < SB(sbuf)->_timingCount; i++)
        if (CMTIME_IS_VALID(SB(sbuf)->_timing[i].presentationTimeStamp) &&
            CMTimeCompare(SB(sbuf)->_timing[i].presentationTimeStamp, t) < 0)
            t = SB(sbuf)->_timing[i].presentationTimeStamp;
    return t;
}
CMTime CMSampleBufferGetDecodeTimeStamp(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf) || !SB(sbuf)->_timingCount)
        return kCMTimeInvalid;
    return SB(sbuf)->_timing[0].decodeTimeStamp;
}
CMTime CMSampleBufferGetOutputDuration(CMSampleBufferRef sbuf) { return CMSampleBufferGetDuration(sbuf); }
CMTime CMSampleBufferGetOutputPresentationTimeStamp(CMSampleBufferRef sbuf)
{
    if (is_sample_buffer(sbuf) && SB(sbuf)->_hasOutputPTS)
        return SB(sbuf)->_outputPTS;
    return CMSampleBufferGetPresentationTimeStamp(sbuf);
}
OSStatus CMSampleBufferSetOutputPresentationTimeStamp(CMSampleBufferRef sbuf, CMTime t)
{
    if (!is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    SB(sbuf)->_outputPTS = t;
    SB(sbuf)->_hasOutputPTS = YES;
    return noErr;
}
CMTime CMSampleBufferGetOutputDecodeTimeStamp(CMSampleBufferRef sbuf)
{
    CMTime d = CMSampleBufferGetDecodeTimeStamp(sbuf);
    return CMTIME_IS_VALID(d) ? d : CMSampleBufferGetOutputPresentationTimeStamp(sbuf);
}
OSStatus CMSampleBufferGetSampleTimingInfo(CMSampleBufferRef sbuf, CMItemIndex i, CMSampleTimingInfo *out)
{
    if (!is_sample_buffer(sbuf) || !out)
        return kCMSampleBufferError_RequiredParameterMissing;
    FerryCMSampleBuffer *b = SB(sbuf);
    if (i < 0 || i >= b->_numSamples)
        return kCMSampleBufferError_SampleIndexOutOfRange;
    if (!b->_timingCount)
        return kCMSampleBufferError_BufferHasNoSampleTimingInfo;
    if (b->_timingCount == 1) {
        *out = b->_timing[0];
        /* one entry for evenly spaced samples: each later by a duration */
        if (i && CMTIME_IS_NUMERIC(b->_timing[0].duration)) {
            CMTime step = CMTimeMultiply(b->_timing[0].duration, (int32_t)i);
            if (CMTIME_IS_NUMERIC(out->presentationTimeStamp))
                out->presentationTimeStamp = CMTimeAdd(out->presentationTimeStamp, step);
            if (CMTIME_IS_NUMERIC(out->decodeTimeStamp))
                out->decodeTimeStamp = CMTimeAdd(out->decodeTimeStamp, step);
        }
    } else
        *out = b->_timing[i];
    return noErr;
}
OSStatus CMSampleBufferGetSampleTimingInfoArray(CMSampleBufferRef sbuf, CMItemCount count, CMSampleTimingInfo *out,
                                                CMItemCount *needed)
{
    if (!is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    FerryCMSampleBuffer *b = SB(sbuf);
    if (needed)
        *needed = b->_timingCount;
    if (!b->_timingCount)
        return kCMSampleBufferError_BufferHasNoSampleTimingInfo;
    if (!out)
        return noErr;
    if (count < b->_timingCount)
        return kCMSampleBufferError_ArrayTooSmall;
    memcpy(out, b->_timing, (size_t)b->_timingCount * sizeof *out);
    return noErr;
}
size_t CMSampleBufferGetSampleSize(CMSampleBufferRef sbuf, CMItemIndex i)
{
    if (!is_sample_buffer(sbuf) || i < 0 || i >= SB(sbuf)->_numSamples || !SB(sbuf)->_sizeCount)
        return 0;
    return SB(sbuf)->_sizeCount == 1 ? SB(sbuf)->_sizes[0] : SB(sbuf)->_sizes[i];
}
size_t CMSampleBufferGetTotalSampleSize(CMSampleBufferRef sbuf)
{
    if (!is_sample_buffer(sbuf) || !SB(sbuf)->_sizeCount)
        return 0;
    if (SB(sbuf)->_sizeCount == 1)
        return SB(sbuf)->_sizes[0] * (size_t)SB(sbuf)->_numSamples;
    size_t total = 0;
    for (CMItemCount i = 0; i < SB(sbuf)->_sizeCount; i++)
        total += SB(sbuf)->_sizes[i];
    return total;
}

CFArrayRef CMSampleBufferGetSampleAttachmentsArray(CMSampleBufferRef sbuf, Boolean create)
{
    if (!is_sample_buffer(sbuf))
        return NULL;
    FerryCMSampleBuffer *b = SB(sbuf);
    pthread_mutex_lock(&b->_lock);
    if (!b->_sampleAttachments && create && b->_numSamples > 0) {
        b->_sampleAttachments = [[NSMutableArray alloc] init];
        for (CMItemCount i = 0; i < b->_numSamples; i++) {
            NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
            [b->_sampleAttachments addObject:d];
            [d release];
        }
    }
    NSMutableArray *a = b->_sampleAttachments;
    pthread_mutex_unlock(&b->_lock);
    return (CFArrayRef)a;
}

/* ---- audio ------------------------------------------------------------------------------ */

static const AudioStreamBasicDescription *pcm_of(FerryCMSampleBuffer *b)
{
    const AudioStreamBasicDescription *a = CMAudioFormatDescriptionGetStreamBasicDescription((CMFormatDescriptionRef)b->_format);
    return a && a->mFormatID == kAudioFormatLinearPCM && a->mBytesPerFrame ? a : NULL;
}

OSStatus CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(CMSampleBufferRef sbuf, size_t *sizeNeeded,
                                                                 AudioBufferList *list, size_t listSize,
                                                                 CFAllocatorRef structureAllocator,
                                                                 CFAllocatorRef blockAllocator, uint32_t flags,
                                                                 CMBlockBufferRef *blockOut)
{
    if (blockOut)
        *blockOut = NULL;
    if (!is_sample_buffer(sbuf))
        return kCMSampleBufferError_RequiredParameterMissing;
    FerryCMSampleBuffer *b = SB(sbuf);
    const AudioStreamBasicDescription *a = pcm_of(b);
    if (!a)
        return kCMSampleBufferError_InvalidMediaTypeForOperation;
    BOOL planar = (a->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 buffers = planar ? (a->mChannelsPerFrame ? a->mChannelsPerFrame : 1) : 1;
    size_t needed = offsetof(AudioBufferList, mBuffers) + buffers * sizeof(AudioBuffer);
    if (sizeNeeded)
        *sizeNeeded = needed;
    if (!list)
        return noErr;
    if (listSize < needed)
        return kCMSampleBufferError_ArrayTooSmall;
    if (!b->_data)
        return kCMSampleBufferError_BufferNotReady;
    CMBlockBufferRef contiguous = NULL;
    OSStatus s = CMBlockBufferCreateContiguous(structureAllocator, (CMBlockBufferRef)b->_data, blockAllocator, NULL, 0, 0,
                                               0, &contiguous);
    if (s != noErr)
        return s;
    char *base = NULL;
    size_t total = 0;
    CMBlockBufferGetDataPointer(contiguous, 0, NULL, &total, &base);
    size_t each = total / buffers;
    list->mNumberBuffers = buffers;
    for (UInt32 i = 0; i < buffers; i++) {
        list->mBuffers[i].mNumberChannels = planar ? 1 : a->mChannelsPerFrame;
        list->mBuffers[i].mDataByteSize = (UInt32)each;
        list->mBuffers[i].mData = base ? base + i * each : NULL;
    }
    if (blockOut)
        *blockOut = contiguous;
    else
        CFRelease(contiguous);
    return noErr;
}

OSStatus CMSampleBufferSetDataBufferFromAudioBufferList(CMSampleBufferRef sbuf, CFAllocatorRef structureAllocator,
                                                        CFAllocatorRef blockAllocator, uint32_t flags,
                                                        const AudioBufferList *list)
{
    if (!is_sample_buffer(sbuf) || !list)
        return kCMSampleBufferError_RequiredParameterMissing;
    if (SB(sbuf)->_data || SB(sbuf)->_image)
        return kCMSampleBufferError_AlreadyHasDataBuffer;
    size_t total = 0;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++)
        total += list->mBuffers[i].mDataByteSize;
    CMBlockBufferRef bb = NULL;
    OSStatus s = CMBlockBufferCreateWithMemoryBlock(structureAllocator, NULL, total ? total : 1, blockAllocator, NULL, 0,
                                                    total, kCMBlockBufferAssureMemoryNowFlag, &bb);
    if (s != noErr)
        return s;
    size_t at = 0;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
        if (list->mBuffers[i].mDataByteSize && list->mBuffers[i].mData)
            CMBlockBufferReplaceDataBytes(list->mBuffers[i].mData, bb, at, list->mBuffers[i].mDataByteSize);
        at += list->mBuffers[i].mDataByteSize;
    }
    SB(sbuf)->_data = (id)bb;
    SB(sbuf)->_ready = YES;
    return noErr;
}

OSStatus CMSampleBufferCopyPCMDataIntoAudioBufferList(CMSampleBufferRef sbuf, int32_t frameOffset, int32_t numFrames,
                                                      AudioBufferList *list)
{
    if (!is_sample_buffer(sbuf) || !list)
        return kCMSampleBufferError_RequiredParameterMissing;
    FerryCMSampleBuffer *b = SB(sbuf);
    const AudioStreamBasicDescription *a = pcm_of(b);
    if (!a)
        return kCMSampleBufferError_InvalidMediaTypeForOperation;
    if (!b->_data)
        return kCMSampleBufferError_BufferNotReady;
    BOOL planar = (a->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 buffers = planar ? (a->mChannelsPerFrame ? a->mChannelsPerFrame : 1) : 1;
    if (list->mNumberBuffers != buffers)
        return kCMSampleBufferError_InvalidEntryCount;
    size_t frames = (size_t)b->_numSamples, perBuffer = CMBlockBufferGetDataLength((CMBlockBufferRef)b->_data) / buffers;
    if (frameOffset < 0 || numFrames < 0 || (size_t)frameOffset + (size_t)numFrames > frames)
        return kCMSampleBufferError_SampleIndexOutOfRange;
    size_t bpf = a->mBytesPerFrame;
    for (UInt32 i = 0; i < buffers; i++) {
        if (list->mBuffers[i].mDataByteSize < (size_t)numFrames * bpf || !list->mBuffers[i].mData)
            return kCMSampleBufferError_ArrayTooSmall;
        OSStatus s = CMBlockBufferCopyDataBytes((CMBlockBufferRef)b->_data, i * perBuffer + (size_t)frameOffset * bpf,
                                                (size_t)numFrames * bpf, list->mBuffers[i].mData);
        if (s != noErr)
            return s;
        list->mBuffers[i].mDataByteSize = (UInt32)((size_t)numFrames * bpf);
    }
    return noErr;
}

OSStatus CMAudioSampleBufferCreateWithPacketDescriptions(CFAllocatorRef allocator, CMBlockBufferRef data,
                                                         Boolean dataReady, CMSampleBufferMakeDataReadyCallback makeReady,
                                                         void *refcon, CMFormatDescriptionRef format,
                                                         CMItemCount numSamples, CMTime pts,
                                                         const AudioStreamPacketDescription *packets,
                                                         CMSampleBufferRef *out)
{
    const AudioStreamBasicDescription *a = CMAudioFormatDescriptionGetStreamBasicDescription(format);
    if (!out || !a)
        return kCMSampleBufferError_RequiredParameterMissing;
    *out = NULL;
    if (packets || a->mFormatID != kAudioFormatLinearPCM || a->mSampleRate <= 0)
        return kCMSampleBufferError_InvalidMediaFormat;    /* compressed audio isn't here */
    CMSampleTimingInfo t = {CMTimeMake(1, (int32_t)llround(a->mSampleRate)), pts, kCMTimeInvalid};
    size_t size = a->mBytesPerFrame;
    return CMSampleBufferCreate(allocator, data, dataReady, makeReady, refcon, format, numSamples, 1, &t, 1, &size, out);
}

/* ---- attachments ------------------------------------------------------------------------ */

void CMSetAttachment(CMAttachmentBearerRef target, CFStringRef key, CFTypeRef value, CMAttachmentMode mode)
{
    if (!target || !key)
        return;
    if (!is_sample_buffer(target)) {
        CVBufferSetAttachment((CVBufferRef)target, key, value, mode);
        return;
    }
    FerryCMSampleBuffer *b = SB(target);
    pthread_mutex_lock(&b->_lock);
    int m = mode == kCMAttachmentMode_ShouldPropagate;
    [b->_attachments[!m] removeObjectForKey:(id)key];
    if (value)
        [b->_attachments[m] setObject:(id)value forKey:(id)key];
    else
        [b->_attachments[m] removeObjectForKey:(id)key];
    pthread_mutex_unlock(&b->_lock);
}
CFTypeRef CMGetAttachment(CMAttachmentBearerRef target, CFStringRef key, CMAttachmentMode *modeOut)
{
    if (!target || !key)
        return NULL;
    if (!is_sample_buffer(target))
        return CVBufferGetAttachment((CVBufferRef)target, key, (CVAttachmentMode *)modeOut);
    FerryCMSampleBuffer *b = SB(target);
    pthread_mutex_lock(&b->_lock);
    id v = nil;
    for (int m = 0; m < 2 && !v; m++)
        if ((v = [b->_attachments[m] objectForKey:(id)key]) && modeOut)
            *modeOut = (CMAttachmentMode)m;
    [[v retain] autorelease];
    pthread_mutex_unlock(&b->_lock);
    return (CFTypeRef)v;
}
void CMRemoveAttachment(CMAttachmentBearerRef target, CFStringRef key)
{
    if (!target || !key)
        return;
    if (!is_sample_buffer(target)) {
        CVBufferRemoveAttachment((CVBufferRef)target, key);
        return;
    }
    pthread_mutex_lock(&SB(target)->_lock);
    [SB(target)->_attachments[0] removeObjectForKey:(id)key];
    [SB(target)->_attachments[1] removeObjectForKey:(id)key];
    pthread_mutex_unlock(&SB(target)->_lock);
}
void CMRemoveAllAttachments(CMAttachmentBearerRef target)
{
    if (!target)
        return;
    if (!is_sample_buffer(target)) {
        CVBufferRemoveAllAttachments((CVBufferRef)target);
        return;
    }
    pthread_mutex_lock(&SB(target)->_lock);
    [SB(target)->_attachments[0] removeAllObjects];
    [SB(target)->_attachments[1] removeAllObjects];
    pthread_mutex_unlock(&SB(target)->_lock);
}
CFDictionaryRef CMCopyDictionaryOfAttachments(CFAllocatorRef allocator, CMAttachmentBearerRef target, CMAttachmentMode mode)
{
    if (!target)
        return NULL;
    if (!is_sample_buffer(target)) {
        CFDictionaryRef d = CVBufferGetAttachments((CVBufferRef)target, mode);
        return d ? (CFDictionaryRef)[(NSDictionary *)d copy] : NULL;
    }
    pthread_mutex_lock(&SB(target)->_lock);
    NSDictionary *d = [SB(target)->_attachments[mode == kCMAttachmentMode_ShouldPropagate] copy];
    pthread_mutex_unlock(&SB(target)->_lock);
    if (![d count]) {
        [d release];
        return NULL;
    }
    return (CFDictionaryRef)d;
}
void CMSetAttachments(CMAttachmentBearerRef target, CFDictionaryRef attachments, CMAttachmentMode mode)
{
    if (!target || !attachments)
        return;
    for (id key in (NSDictionary *)attachments)
        CMSetAttachment(target, (CFStringRef)key, (CFTypeRef)[(NSDictionary *)attachments objectForKey:key], mode);
}
void CMPropagateAttachments(CMAttachmentBearerRef source, CMAttachmentBearerRef destination)
{
    CFDictionaryRef d = CMCopyDictionaryOfAttachments(NULL, source, kCMAttachmentMode_ShouldPropagate);
    if (d) {
        CMSetAttachments(destination, d, kCMAttachmentMode_ShouldPropagate);
        CFRelease(d);
    }
}

/* ---- CMSimpleQueue (freemac 1.264, HandBrake) ---------------------------------------
 * A ring of pointers with a lock, so one thread can fill it while another
 * empties it, as Apple documents. The queue doesn't retain what it holds. */
@interface FerryCMSimpleQueue : NSObject {
  @public
    const void **_slots;
    int32_t _capacity, _head, _count;
    pthread_mutex_t _lock;
}
@end
@implementation FerryCMSimpleQueue
- (void)dealloc
{
    free(_slots);
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}
@end

#define SQ(ref) ((FerryCMSimpleQueue *)(ref))
static BOOL is_queue(CMSimpleQueueRef q) { return q && [(id)q isKindOfClass:[FerryCMSimpleQueue class]]; }

CFTypeID CMSimpleQueueGetTypeID(void) { return (CFTypeID)[FerryCMSimpleQueue class]; }

OSStatus CMSimpleQueueCreate(CFAllocatorRef allocator, int32_t capacity, CMSimpleQueueRef *out)
{
    (void)allocator;
    if (!out)
        return kCMSimpleQueueError_RequiredParameterMissing;
    *out = NULL;
    if (capacity <= 0)
        return kCMSimpleQueueError_ParameterOutOfRange;
    FerryCMSimpleQueue *q = [[FerryCMSimpleQueue alloc] init];
    q->_slots = calloc((size_t)capacity, sizeof(void *));
    if (!q->_slots) {
        [q release];
        return kCMSimpleQueueError_AllocationFailed;
    }
    q->_capacity = capacity;
    pthread_mutex_init(&q->_lock, NULL);
    *out = (CMSimpleQueueRef)q;
    return noErr;
}

OSStatus CMSimpleQueueEnqueue(CMSimpleQueueRef queue, const void *element)
{
    if (!is_queue(queue) || !element)
        return kCMSimpleQueueError_RequiredParameterMissing;
    FerryCMSimpleQueue *q = SQ(queue);
    pthread_mutex_lock(&q->_lock);
    OSStatus r = noErr;
    if (q->_count == q->_capacity)
        r = kCMSimpleQueueError_QueueIsFull;
    else
        q->_slots[(q->_head + q->_count++) % q->_capacity] = element;
    pthread_mutex_unlock(&q->_lock);
    return r;
}

static const void *queue_head(CMSimpleQueueRef queue, BOOL take)
{
    if (!is_queue(queue))
        return NULL;
    FerryCMSimpleQueue *q = SQ(queue);
    pthread_mutex_lock(&q->_lock);
    const void *e = NULL;
    if (q->_count) {
        e = q->_slots[q->_head];
        if (take) {
            q->_head = (q->_head + 1) % q->_capacity;
            q->_count--;
        }
    }
    pthread_mutex_unlock(&q->_lock);
    return e;
}

const void *CMSimpleQueueDequeue(CMSimpleQueueRef queue) { return queue_head(queue, YES); }
const void *CMSimpleQueueGetHead(CMSimpleQueueRef queue) { return queue_head(queue, NO); }

OSStatus CMSimpleQueueReset(CMSimpleQueueRef queue)
{
    if (!is_queue(queue))
        return kCMSimpleQueueError_RequiredParameterMissing;
    pthread_mutex_lock(&SQ(queue)->_lock);
    SQ(queue)->_head = SQ(queue)->_count = 0;
    pthread_mutex_unlock(&SQ(queue)->_lock);
    return noErr;
}

int32_t CMSimpleQueueGetCapacity(CMSimpleQueueRef queue) { return is_queue(queue) ? SQ(queue)->_capacity : 0; }
int32_t CMSimpleQueueGetCount(CMSimpleQueueRef queue)
{
    if (!is_queue(queue))
        return 0;
    pthread_mutex_lock(&SQ(queue)->_lock);
    int32_t n = SQ(queue)->_count;
    pthread_mutex_unlock(&SQ(queue)->_lock);
    return n;
}
