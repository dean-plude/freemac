/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Media's sample buffers (freemac 1.238, Ferry 0.62.0), as
 * ScreenCaptureKit hands them to OBS Studio: a pixel buffer's sample with
 * its timing, format and attachments; a block buffer of pieces; an audio
 * sample buffer as an AudioBufferList; then ScreenCaptureKit with no
 * display, before and after the user's say (kept in a folder of the
 * test's own). */
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <CoreGraphics/CGDisplayStream.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>

static NSString *four(OSType t)
{
    return [NSString stringWithFormat:@"%c%c%c%c", (char)(t >> 24), (char)(t >> 16), (char)(t >> 8), (char)t];
}

static void time_text(const char *what, CMTime t)
{
    if (!CMTIME_IS_VALID(t))
        printf("%s: invalid\n", what);
    else
        printf("%s: %lld/%d\n", what, (long long)t.value, t.timescale);
}

/* CMTimeConvertScale's rounding methods (freemac 1.258), as OBS's camera
 * source converts frame durations */
static void rounding(void)
{
    CMTime t = CMTimeMake(1001, 30000), n = CMTimeMake(-25, 10);
    time_text("1001/30000 at 1000, default", CMTimeConvertScale(t, 1000, kCMTimeRoundingMethod_Default));
    time_text("toward zero", CMTimeConvertScale(t, 1000, kCMTimeRoundingMethod_RoundTowardZero));
    time_text("away from zero", CMTimeConvertScale(t, 1000, kCMTimeRoundingMethod_RoundAwayFromZero));
    time_text("-25/10 at 1, half away", CMTimeConvertScale(n, 1, kCMTimeRoundingMethod_RoundHalfAwayFromZero));
    time_text("toward +infinity", CMTimeConvertScale(n, 1, kCMTimeRoundingMethod_RoundTowardPositiveInfinity));
    time_text("toward -infinity", CMTimeConvertScale(n, 1, kCMTimeRoundingMethod_RoundTowardNegativeInfinity));
    CMTime exact = CMTimeConvertScale(CMTimeMake(3, 10), 1000, kCMTimeRoundingMethod_Default);
    printf("exact: %lld/%d, rounded %d; rounded one marked %d\n", (long long)exact.value, exact.timescale,
           (exact.flags & kCMTimeFlags_HasBeenRounded) != 0,
           (CMTimeConvertScale(t, 1000, kCMTimeRoundingMethod_Default).flags & kCMTimeFlags_HasBeenRounded) != 0);
    printf("codec types: %s %s %s\n", [four(kCMVideoCodecType_AppleProRes4444) UTF8String],
           [four(kCMVideoCodecType_DVCPROHD1080i60) UTF8String], [four(kCMVideoCodecType_Animation) UTF8String]);
}

static void video(void)
{
    CVPixelBufferRef pb = NULL;
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferCreate(NULL, 64, 48, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &pb);
    CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
                          kCVAttachmentMode_ShouldPropagate);
    CMVideoFormatDescriptionRef fmt = NULL;
    OSStatus err = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pb, &fmt);
    CMVideoDimensions d = CMVideoFormatDescriptionGetDimensions(fmt);
    printf("format: %d, %s %s %dx%d, primaries %s, matches %d\n", (int)err,
           [four(CMFormatDescriptionGetMediaType(fmt)) UTF8String],
           [four(CMFormatDescriptionGetMediaSubType(fmt)) UTF8String], d.width, d.height,
           [(__bridge NSString *)CMFormatDescriptionGetExtension(fmt, kCVImageBufferColorPrimariesKey) UTF8String],
           CMVideoFormatDescriptionMatchesImageBuffer(fmt, pb));
    CMSampleTimingInfo t = {CMTimeMake(1, 30), CMTimeMake(900, 30), kCMTimeInvalid};
    CMSampleBufferRef s = NULL;
    err = CMSampleBufferCreateReadyWithImageBuffer(NULL, pb, fmt, &t, &s);
    printf("sample: %d, the pixel buffer %d, the format %d, samples %ld, valid %d, ready %d, no data buffer %d\n",
           (int)err, CMSampleBufferGetImageBuffer(s) == pb, CMFormatDescriptionEqual(CMSampleBufferGetFormatDescription(s), fmt),
           (long)CMSampleBufferGetNumSamples(s), CMSampleBufferIsValid(s), CMSampleBufferDataIsReady(s),
           CMSampleBufferGetDataBuffer(s) == NULL);
    time_text("  presented", CMSampleBufferGetPresentationTimeStamp(s));
    time_text("  for", CMSampleBufferGetDuration(s));
    time_text("  decoded", CMSampleBufferGetDecodeTimeStamp(s));
    time_text("  output at", CMSampleBufferGetOutputPresentationTimeStamp(s));
    printf("  the type is a sample buffer's %d\n", CFGetTypeID(s) == CMSampleBufferGetTypeID());

    printf("  attachments before asking: %d\n", CMSampleBufferGetSampleAttachmentsArray(s, false) == NULL);
    CFArrayRef a = CMSampleBufferGetSampleAttachmentsArray(s, true);
    NSMutableDictionary *first = (__bridge NSMutableDictionary *)CFArrayGetValueAtIndex(a, 0);
    first[@"Status"] = @0;
    first[(__bridge id)kCMSampleAttachmentKey_DisplayImmediately] = @YES;
    CFArrayRef again = CMSampleBufferGetSampleAttachmentsArray(s, false);
    NSDictionary *seen = (__bridge NSDictionary *)CFArrayGetValueAtIndex(again, 0);
    printf("  attachments: %ld, the same array %d, kept %lu\n", (long)CFArrayGetCount(a), a == again,
           (unsigned long)[seen count]);

    CMSetAttachment(s, CFSTR("Mine"), (__bridge CFTypeRef)@"value", kCMAttachmentMode_ShouldPropagate);
    CMAttachmentMode mode = 9;
    CFTypeRef got = CMGetAttachment(s, CFSTR("Mine"), &mode);
    printf("  its own attachment: %s, propagated %d\n", [(__bridge NSString *)got UTF8String],
           mode == kCMAttachmentMode_ShouldPropagate);
    CMSetAttachment(pb, CFSTR("OnThePixels"), kCFBooleanTrue, kCMAttachmentMode_ShouldNotPropagate);
    printf("  on the pixel buffer: %d, in CoreVideo's too %d\n", CMGetAttachment(pb, CFSTR("OnThePixels"), NULL) == kCFBooleanTrue,
           CVBufferGetAttachment(pb, CFSTR("OnThePixels"), NULL) == kCFBooleanTrue);
    CFDictionaryRef all = CMCopyDictionaryOfAttachments(NULL, s, kCMAttachmentMode_ShouldPropagate);
    printf("  propagated ones: %ld\n", (long)CFDictionaryGetCount(all));
    CFRelease(all);
    CMRemoveAttachment(s, CFSTR("Mine"));
    printf("  removed: %d\n", CMGetAttachment(s, CFSTR("Mine"), NULL) == NULL);

    CMSampleBufferRef copy = NULL;
    CMSampleTimingInfo later = {CMTimeMake(1, 30), CMTimeMake(930, 30), kCMTimeInvalid};
    CMSampleBufferCreateCopyWithNewTiming(NULL, s, 1, &later, &copy);
    time_text("  a copy presented", CMSampleBufferGetPresentationTimeStamp(copy));
    printf("  the copy's pixels the same %d\n", CMSampleBufferGetImageBuffer(copy) == pb);
    CMSampleBufferInvalidate(s);
    printf("  invalidated: valid %d\n", CMSampleBufferIsValid(s));
    CFRelease(copy);
    CFRelease(s);
    CFRelease(fmt);
    CVPixelBufferRelease(pb);
}

static void blocks(void)
{
    CMBlockBufferRef b = NULL;
    OSStatus err = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, 8, NULL, NULL, 0, 8, kCMBlockBufferAssureMemoryNowFlag, &b);
    CMBlockBufferReplaceDataBytes("abcdefgh", b, 0, 8);
    static char more[] = "ijkl";
    CMBlockBufferAppendMemoryBlock(b, more, 4, kCFAllocatorNull, NULL, 0, 4, 0);
    char out[13] = {0};
    CMBlockBufferCopyDataBytes(b, 0, 12, out);
    size_t atOffset = 0, total = 0;
    char *p = NULL;
    CMBlockBufferGetDataPointer(b, 9, &atOffset, &total, &p);
    printf("block buffer: %d, %zu bytes \"%s\", at 9 \"%.*s\" (%zu of %zu), contiguous %d, over the join %d\n", (int)err,
           CMBlockBufferGetDataLength(b), out, (int)atOffset, p, atOffset, total, CMBlockBufferIsRangeContiguous(b, 0, 8),
           CMBlockBufferIsRangeContiguous(b, 6, 4));
    CMBlockBufferRef flat = NULL;
    CMBlockBufferCreateContiguous(NULL, b, NULL, NULL, 2, 8, 0, &flat);
    CMBlockBufferGetDataPointer(flat, 0, &atOffset, &total, &p);
    printf("  made contiguous: \"%.*s\"\n", (int)total, p);
    printf("  past the end: %d\n", (int)CMBlockBufferCopyDataBytes(b, 10, 8, out));
    CFRelease(flat);
    CFRelease(b);
}

static void audio(void)
{
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = 48000;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    asbd.mBytesPerPacket = 4;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 4;
    asbd.mChannelsPerFrame = 2;
    asbd.mBitsPerChannel = 32;
    CMAudioFormatDescriptionRef fmt = NULL;
    CMAudioFormatDescriptionCreate(NULL, &asbd, 0, NULL, 0, NULL, NULL, &fmt);
    const AudioStreamBasicDescription *back = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
    printf("audio format: %s, %.0f Hz, %u channels\n", [four(CMFormatDescriptionGetMediaType(fmt)) UTF8String],
           back->mSampleRate, back->mChannelsPerFrame);
    /* 4 frames, the left channel then the right */
    float samples[8] = {0.1f, 0.2f, 0.3f, 0.4f, -0.1f, -0.2f, -0.3f, -0.4f};
    CMBlockBufferRef data = NULL;
    CMBlockBufferCreateWithMemoryBlock(NULL, NULL, sizeof samples, NULL, NULL, 0, sizeof samples,
                                       kCMBlockBufferAssureMemoryNowFlag, &data);
    CMBlockBufferReplaceDataBytes(samples, data, 0, sizeof samples);
    CMSampleBufferRef s = NULL;
    OSStatus err = CMAudioSampleBufferCreateWithPacketDescriptions(NULL, data, true, NULL, NULL, fmt, 4,
                                                                   CMTimeMake(480, 48000), NULL, &s);
    printf("audio sample: %d, samples %ld, size %zu, each %zu\n", (int)err, (long)CMSampleBufferGetNumSamples(s),
           CMSampleBufferGetTotalSampleSize(s), CMSampleBufferGetSampleSize(s, 0));
    time_text("  presented", CMSampleBufferGetPresentationTimeStamp(s));
    time_text("  for", CMSampleBufferGetDuration(s));
    size_t needed = 0;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(s, &needed, NULL, 0, NULL, NULL, 0, NULL);
    AudioBufferList *list = malloc(needed);
    CMBlockBufferRef kept = NULL;
    err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        s, NULL, list, needed, NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &kept);
    printf("  as a buffer list: %d, %u buffers", (int)err, list->mNumberBuffers);
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
        const float *f = list->mBuffers[i].mData;
        printf(", %u bytes from %.1f to %.1f", list->mBuffers[i].mDataByteSize, f[0], f[3]);
    }
    printf("\n");
    free(list);
    if (kept)
        CFRelease(kept);
    CFRelease(s);
    CFRelease(data);
    CFRelease(fmt);
}

static void no_display(void)
{
    __block atomic_int done = 0;
    __block long code = 0;
    __block int content = 0;
    void (^ask)(void) = ^{
        atomic_store(&done, 0);
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *c, NSError *e) {
            code = e.code;
            content = c != nil;
            atomic_store(&done, 1);
        }];
        for (int i = 0; i < 500 && !atomic_load(&done); i++)
            usleep(10000);
    };
    ask();
    printf("no display, not allowed: content %d, error %ld, preflight %d\n", content, code,
           CGPreflightScreenCaptureAccess());

    /* the user's say, as freemac-allow-control keeps it */
    NSString *key = [[[NSBundle mainBundle] executablePath] stringByStandardizingPath];
    NSString *dir = [@(getenv("XDG_CONFIG_HOME")) stringByAppendingPathComponent:@"freemac"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *j = [NSJSONSerialization dataWithJSONObject:@{@"apps" : @{key : @{@"allowed" : @YES, @"name" : @"test"}}}
                                                options:0 error:NULL];
    [j writeToFile:[dir stringByAppendingPathComponent:@"screen-recording.json"] atomically:YES];
    ask();
    printf("no display, allowed: content %d, error %ld, preflight %d\n", content, code, CGPreflightScreenCaptureAccess());

    SCStreamConfiguration *config = [SCStreamConfiguration new];
    printf("a configuration's defaults: %zux%zu %s, queue %ld, cursor %d, aspect %d, audio %d at %ld Hz, %ld channels\n",
           config.width, config.height, [four(config.pixelFormat) UTF8String], (long)config.queueDepth,
           config.showsCursor, config.preservesAspectRatio, config.capturesAudio, (long)config.sampleRate,
           (long)config.channelCount);
    SCStream *stream = [[SCStream alloc] initWithFilter:[SCContentFilter new] configuration:config delegate:nil];
    atomic_store(&done, 0);
    [stream startCaptureWithCompletionHandler:^(NSError *e) {
        code = e.code;
        atomic_store(&done, 1);
    }];
    for (int i = 0; i < 500 && !atomic_load(&done); i++)
        usleep(10000);
    printf("a stream with no display: error %ld\n", code);
    CGDisplayStreamRef ds = CGDisplayStreamCreateWithDispatchQueue(
        CGMainDisplayID(), 64, 48, 'BGRA', NULL, dispatch_get_global_queue(0, 0),
        ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
        });
    printf("a display stream with no display: made %d, started %d\n", ds != NULL,
           ds && CGDisplayStreamStart(ds) == kCGErrorSuccess);
    if (ds)
        CFRelease(ds);
}

int main(void)
{
    @autoreleasepool {
        unsetenv("DISPLAY");
        unsetenv("WAYLAND_DISPLAY");
        unsetenv("FERRY_CAPTURE");
        unsetenv("FERRY_ACCESS_ASKER");
        char dir[] = "/tmp/ferry-coremedia.XXXXXX";
        if (!mkdtemp(dir))
            return 1;
        setenv("XDG_CONFIG_HOME", dir, 1);
        video();
        blocks();
        audio();
        no_display();
        rounding();
        [[NSFileManager defaultManager] removeItemAtPath:@(dir) error:NULL];
    }
    return 0;
}
