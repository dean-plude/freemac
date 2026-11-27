/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Audio's HAL on the null device (freemac 1.234, Ferry 0.58.0): the
 * system object and its devices, as VLC's auhal module and OBS's
 * mac-capture plugin read them; setting a format and a buffer size, with a
 * listener hearing it; an IO proc running; Audio Format Services' channel
 * layouts; and audio converters between linear PCM formats. */
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static AudioObjectPropertyAddress addr(AudioObjectPropertySelector s, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = {s, scope, kAudioObjectPropertyElementMain};
    return a;
}

static void print_cf(const char *label, CFStringRef s)
{
    char buf[256] = "";
    if (s)
        CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
    printf("%s: %s\n", label, buf);
    if (s)
        CFRelease(s);
}

static CFStringRef get_string(AudioObjectID obj, AudioObjectPropertySelector sel)
{
    AudioObjectPropertyAddress a = addr(sel, kAudioObjectPropertyScopeGlobal);
    CFStringRef s = NULL;
    UInt32 size = sizeof s;
    OSStatus err = AudioObjectGetPropertyData(obj, &a, 0, NULL, &size, &s);
    return err ? NULL : s;
}

static UInt32 get_u32(AudioObjectID obj, AudioObjectPropertySelector sel, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = addr(sel, scope);
    UInt32 v = 0xdeadbeef, size = sizeof v;
    OSStatus err = AudioObjectGetPropertyData(obj, &a, 0, NULL, &size, &v);
    return err ? 0xdeadbeef : v;
}

static UInt32 size_of(AudioObjectID obj, AudioObjectPropertySelector sel, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = addr(sel, scope);
    UInt32 size = 0xdeadbeef;
    OSStatus err = AudioObjectGetPropertyDataSize(obj, &a, 0, NULL, &size);
    return err ? 0xdeadbeef : size;
}

static int cycles;
static Float64 last_sample = -1;
static OSStatus ioproc(AudioObjectID dev, const AudioTimeStamp *now, const AudioBufferList *in,
                       const AudioTimeStamp *in_time, AudioBufferList *out, const AudioTimeStamp *out_time, void *data)
{
    if (out && out->mNumberBuffers && out->mBuffers[0].mData)
        memset(out->mBuffers[0].mData, 0, out->mBuffers[0].mDataByteSize);
    if (out_time->mSampleTime > last_sample)
        last_sample = out_time->mSampleTime;
    cycles++;
    return noErr;
}

static int heard_rate;
static OSStatus rate_listener(AudioObjectID obj, UInt32 n, const AudioObjectPropertyAddress *a, void *data)
{
    for (UInt32 i = 0; i < n; i++)
        if (a[i].mSelector == kAudioDevicePropertyNominalSampleRate)
            heard_rate++;
    dispatch_semaphore_signal((dispatch_semaphore_t)data);
    return noErr;
}

static void print_layout(const char *label, const AudioChannelLayout *l)
{
    printf("%s: tag %u, %u descriptions:", label, (unsigned)l->mChannelLayoutTag,
           (unsigned)l->mNumberChannelDescriptions);
    for (UInt32 i = 0; i < l->mNumberChannelDescriptions; i++)
        printf(" %u", (unsigned)l->mChannelDescriptions[i].mChannelLabel);
    printf("\n");
}

/* the converter test's input: four frames of 16-bit stereo, then nothing */
typedef struct {
    const SInt16 *samples;
    UInt32 frames, given;
} feed;

static OSStatus feed_proc(AudioConverterRef c, UInt32 *n, AudioBufferList *io, AudioStreamPacketDescription **d,
                          void *user)
{
    feed *f = user;
    UInt32 left = f->frames - f->given;
    if (*n > left)
        *n = left;
    io->mBuffers[0].mData = (void *)(f->samples + f->given * 2);
    io->mBuffers[0].mDataByteSize = *n * 4;
    io->mBuffers[0].mNumberChannels = 2;
    f->given += *n;
    return noErr;
}

int main(void)
{
    /* the system object */
    AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size);
    AudioDeviceID devices[16];
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, devices);
    UInt32 count = size / sizeof(AudioDeviceID);
    printf("devices: %u\n", (unsigned)count);
    AudioDeviceID out = get_u32(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice,
                                kAudioObjectPropertyScopeOutput);
    AudioDeviceID in = get_u32(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultInputDevice,
                               kAudioObjectPropertyScopeGlobal);
    AudioDeviceID sys = get_u32(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultSystemOutputDevice,
                                kAudioObjectPropertyScopeGlobal);
    printf("default output is the listed device: %d, input too: %d, system output too: %d\n", out == devices[0],
           in == devices[0], sys == devices[0]);
    printf("system class: %s\n", get_u32(kAudioObjectSystemObject, kAudioObjectPropertyClass,
                                          kAudioObjectPropertyScopeGlobal) == kAudioSystemObjectClassID ? "system" : "?");

    /* a device, as VLC and OBS read it */
    print_cf("name", get_string(out, kAudioObjectPropertyName));
    print_cf("uid", get_string(out, kAudioDevicePropertyDeviceUID));
    print_cf("manufacturer", get_string(out, kAudioObjectPropertyManufacturer));
    char cname[64] = "";
    UInt32 cs = sizeof cname;
    a = addr(kAudioDevicePropertyDeviceName, kAudioObjectPropertyScopeGlobal);
    AudioObjectGetPropertyData(out, &a, 0, NULL, &cs, cname);
    printf("old name: %s (%u bytes)\n", cname, (unsigned)cs);
    printf("class: %s\n", get_u32(out, kAudioObjectPropertyClass, kAudioObjectPropertyScopeGlobal) ==
                                  kAudioDeviceClassID ? "device" : "?");
    printf("alive: %u, running: %u\n", (unsigned)get_u32(out, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
           (unsigned)get_u32(out, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal));
    printf("transport: %s\n", get_u32(out, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal) ==
                                      kAudioDeviceTransportTypeVirtual ? "virtual" : "?");
    printf("stream bytes: output %u, input %u, global %u\n",
           (unsigned)size_of(out, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput),
           (unsigned)size_of(out, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput),
           (unsigned)size_of(out, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeGlobal));
    printf("latency: %u, safety offset: %u\n",
           (unsigned)get_u32(out, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput),
           (unsigned)get_u32(out, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput));
    UInt32 ds = get_u32(out, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput);
    printf("data source: '%c%c%c%c'\n", (char)(ds >> 24), (char)(ds >> 16), (char)(ds >> 8), (char)ds);
    printf("hog mode: %d\n", (int)get_u32(out, kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal));
    printf("supports mixing: %u\n", (unsigned)get_u32(out, kAudioDevicePropertySupportsMixing, kAudioObjectPropertyScopeGlobal));
    printf("buffer frames: %u\n", (unsigned)get_u32(out, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal));
    a = addr(kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal);
    printf("has hog mode: %d, has 'zzzz': %d\n", AudioObjectHasProperty(out, &a),
           AudioObjectHasProperty(out, &(AudioObjectPropertyAddress){'zzzz', kAudioObjectPropertyScopeGlobal, 0}));

    /* the channels: a stream configuration and a layout */
    a = addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput);
    unsigned char config[64];
    size = sizeof config;
    AudioObjectGetPropertyData(in, &a, 0, NULL, &size, config);
    AudioBufferList *bl = (AudioBufferList *)config;
    printf("input configuration: %u buffer(s), %u channels\n", (unsigned)bl->mNumberBuffers,
           (unsigned)bl->mBuffers[0].mNumberChannels);
    a = addr(kAudioDevicePropertyPreferredChannelLayout, kAudioObjectPropertyScopeOutput);
    AudioObjectGetPropertyDataSize(out, &a, 0, NULL, &size);
    unsigned char lbuf[512];
    AudioObjectGetPropertyData(out, &a, 0, NULL, &size, lbuf);
    print_layout("preferred layout", (AudioChannelLayout *)lbuf);
    a = (AudioObjectPropertyAddress){kAudioObjectPropertyElementName, kAudioObjectPropertyScopeInput, 2};
    CFStringRef cn = NULL;
    size = sizeof cn;
    AudioObjectGetPropertyData(in, &a, 0, NULL, &size, &cn);
    print_cf("input channel 2", cn);

    /* the streams and their formats */
    a = addr(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput);
    AudioStreamID stream = 0;
    size = sizeof stream;
    AudioObjectGetPropertyData(out, &a, 0, NULL, &size, &stream);
    AudioStreamBasicDescription f;
    a = addr(kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal);
    size = sizeof f;
    AudioObjectGetPropertyData(stream, &a, 0, NULL, &size, &f);
    printf("stream format: %.0f Hz, %u channels, %u bits, float %d, interleaved %d\n", f.mSampleRate,
           (unsigned)f.mChannelsPerFrame, (unsigned)f.mBitsPerChannel, (f.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
           !(f.mFormatFlags & kAudioFormatFlagIsNonInterleaved));
    printf("stream direction: %u, terminal speaker: %d, owner is the device: %d\n",
           (unsigned)get_u32(stream, kAudioStreamPropertyDirection, kAudioObjectPropertyScopeGlobal),
           get_u32(stream, kAudioStreamPropertyTerminalType, kAudioObjectPropertyScopeGlobal) ==
               kAudioStreamTerminalTypeSpeaker,
           get_u32(stream, kAudioObjectPropertyOwner, kAudioObjectPropertyScopeGlobal) == out);
    printf("available physical formats: %u\n",
           (unsigned)(size_of(stream, kAudioStreamPropertyAvailablePhysicalFormats, kAudioObjectPropertyScopeGlobal) /
                      sizeof(AudioStreamRangedDescription)));
    printf("available rates: %u\n",
           (unsigned)(size_of(out, kAudioDevicePropertyAvailableNominalSampleRates, kAudioObjectPropertyScopeGlobal) /
                      sizeof(AudioValueRange)));

    /* a device found by its UID, both ways */
    CFStringRef uid = CFStringCreateWithCString(NULL, "FerryNullAudioDevice", kCFStringEncodingUTF8);
    AudioDeviceID found = 0;
    AudioValueTranslation t = {&uid, sizeof uid, &found, sizeof found};
    a = addr(kAudioHardwarePropertyDeviceForUID, kAudioObjectPropertyScopeGlobal);
    size = sizeof t;
    OSStatus err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &t);
    printf("device for UID: %d %d\n", (int)err, found == out);
    a = addr(kAudioHardwarePropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal);
    found = 0;
    size = sizeof found;
    err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof uid, &uid, &size, &found);
    printf("translate UID: %d %d\n", (int)err, found == out);
    CFRelease(uid);

    /* setting a rate, which a listener hears, and a buffer size */
    dispatch_semaphore_t heard = dispatch_semaphore_create(0);
    a = addr(kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal);
    AudioObjectAddPropertyListener(out, &a, rate_listener, (void *)heard);
    Boolean settable = 0;
    AudioObjectIsPropertySettable(out, &a, &settable);
    Float64 rate = 44100;
    err = AudioObjectSetPropertyData(out, &a, 0, NULL, sizeof rate, &rate);
    long waited = dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    rate = 0;
    size = sizeof rate;
    AudioObjectGetPropertyData(out, &a, 0, NULL, &size, &rate);
    printf("rate settable %d, set %d, now %.0f, listener heard %d (%s)\n", settable, (int)err, rate, heard_rate,
           waited ? "timed out" : "in time");
    AudioObjectRemovePropertyListener(out, &a, rate_listener, (void *)heard);
    rate = 12345;
    printf("unsupported rate: %d\n", AudioObjectSetPropertyData(out, &a, 0, NULL, sizeof rate, &rate) ==
                                         kAudioDeviceUnsupportedFormatError);
    rate = 48000;
    AudioObjectSetPropertyData(out, &a, 0, NULL, sizeof rate, &rate);
    a = addr(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal);
    UInt32 frames = 256;
    err = AudioObjectSetPropertyData(out, &a, 0, NULL, sizeof frames, &frames);
    printf("buffer frames set %d, now %u\n", (int)err,
           (unsigned)get_u32(out, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal));
    a = addr(kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal);
    settable = 1;
    AudioObjectIsPropertySettable(out, &a, &settable);
    printf("uid settable: %d\n", settable);

    /* a listener block, on a queue of the program's */
    __block int block_heard = 0;
    dispatch_queue_t q = dispatch_queue_create("test.listener", NULL);
    a = addr(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal);
    AudioObjectPropertyListenerBlock lb = ^(UInt32 n, const AudioObjectPropertyAddress *addrs) {
      block_heard += (int)n;
      dispatch_semaphore_signal(heard);
    };
    AudioObjectAddPropertyListenerBlock(out, &a, q, lb);
    frames = 512;
    AudioObjectSetPropertyData(out, &a, 0, NULL, sizeof frames, &frames);
    waited = dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    printf("listener block heard %d (%s), removed: %d\n", block_heard, waited ? "timed out" : "in time",
           (int)AudioObjectRemovePropertyListenerBlock(out, &a, q, lb));

    /* an IO proc on the device for a quarter of a second */
    AudioDeviceIOProcID pid = NULL;
    err = AudioDeviceCreateIOProcID(out, ioproc, NULL, &pid);
    printf("io proc: %d\n", (int)err);
    AudioDeviceStart(out, pid);
    usleep(250000);
    printf("running while started: %u\n",
           (unsigned)get_u32(out, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal));
    AudioDeviceStop(out, pid);
    int c = cycles;
    printf("cycles in 250 ms of 512 frames at 48 kHz: %s, sample time grew: %d\n",
           c >= 12 && c <= 40 ? "about 23" : "wrong", last_sample >= 512 * 10);
    usleep(50000);
    printf("still after stop: %d, running: %u\n", cycles == c,
           (unsigned)get_u32(out, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal));
    printf("destroy: %d\n", (int)AudioDeviceDestroyIOProcID(out, pid));

    /* the older calls */
    AudioDeviceID old = 0;
    size = sizeof old;
    AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &size, &old);
    Boolean writable = 0;
    AudioDeviceGetPropertyInfo(out, 0, 0, kAudioDevicePropertyNominalSampleRate, &size, &writable);
    printf("older calls: %d, rate %u bytes, writable %d\n", old == out, (unsigned)size, writable);

    /* Audio Format Services' channel layouts */
    AudioChannelLayoutTag tag = kAudioChannelLayoutTag_MPEG_5_1_A;
    err = AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag, sizeof tag, &tag, &size);
    AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag, sizeof tag, &tag, &size, lbuf);
    print_layout("5.1 (A)", (AudioChannelLayout *)lbuf);
    AudioChannelBitmap bitmap = kAudioChannelBit_Left | kAudioChannelBit_Right | kAudioChannelBit_LFEScreen;
    size = sizeof lbuf;
    AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForBitmap, sizeof bitmap, &bitmap, &size, lbuf);
    print_layout("bitmap L R LFE", (AudioChannelLayout *)lbuf);
    UInt32 n = 0;
    size = sizeof n;
    AudioChannelLayout stereo = {kAudioChannelLayoutTag_Stereo, 0, 0};
    AudioFormatGetProperty(kAudioFormatProperty_NumberOfChannelsForLayout, sizeof stereo, &stereo, &size, &n);
    printf("channels in stereo: %u\n", (unsigned)n);

    /* converters: 16-bit stereo to float mono, then 44.1 kHz to 48 kHz */
    AudioStreamBasicDescription s16 = {44100, kAudioFormatLinearPCM,
                                       kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
    AudioStreamBasicDescription fmono = {44100, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked, 4, 1, 4, 1,
                                         32, 0};
    AudioConverterRef conv = NULL;
    err = AudioConverterNew(&s16, &fmono, &conv);
    SInt16 pcm[8] = {16384, 0, -32768, -32768, 0, 32767, 8192, 8192};
    float mono[4];
    UInt32 osize = sizeof mono;
    OSStatus cerr = AudioConverterConvertBuffer(conv, sizeof pcm, pcm, &osize, mono);
    printf("convert: %d %d, %u bytes: %.3f %.3f %.3f %.3f\n", (int)err, (int)cerr, (unsigned)osize, mono[0], mono[1],
           mono[2], mono[3]);
    AudioConverterDispose(conv);
    AudioStreamBasicDescription f48 = fmono;
    f48.mSampleRate = 48000;
    f48.mChannelsPerFrame = 2;
    f48.mBytesPerFrame = f48.mBytesPerPacket = 8;
    err = AudioConverterNew(&s16, &f48, &conv);
    enum { IN_FRAMES = 4410 };
    static SInt16 tone[IN_FRAMES * 2];
    for (int i = 0; i < IN_FRAMES; i++)
        tone[i * 2] = tone[i * 2 + 1] = (SInt16)(16000 * sin(2 * M_PI * 441 * i / 44100.0));
    feed fd = {tone, IN_FRAMES, 0};
    static float resampled[6000 * 2];
    UInt32 total = 0;
    for (;;) {
        UInt32 packets = 1000;
        AudioBufferList ol = {1, {{2, packets * 8, resampled + total * 2}}};
        cerr = AudioConverterFillComplexBuffer(conv, feed_proc, &fd, &packets, &ol, NULL);
        if (cerr || !packets)
            break;
        total += packets;
    }
    int crossings = 0;
    for (UInt32 i = 1; i < total; i++)
        if ((resampled[(i - 1) * 2] < 0) != (resampled[i * 2] < 0))
            crossings++;
    printf("resample: %d %d, %u frames (about 4800), %d zero crossings (about 88)\n", (int)err, (int)cerr,
           (unsigned)total, crossings);
    /* a codec Ferry has no encoder for (AAC and others are in codec.c's test) */
    AudioStreamBasicDescription qdm = {44100, 'QDM2', 0, 0, 2048, 0, 2, 0, 0};
    printf("to QDesign: %d\n", AudioConverterNew(&s16, &qdm, &conv) == kAudioConverterErr_FormatNotSupported);
    return 0;
}
