/* SPDX-License-Identifier: GPL-3.0-or-later
 * Audio units on the null device (freemac 1.234, Ferry 0.58.0): a
 * HALOutput unit playing a 440 Hz sine from a render callback, set up as
 * VLC's auhal module sets one up, and a DefaultOutput unit in its own
 * format, both read back from the file the null device plays into
 * (FERRY_AUDIO_OUTPUT_FILE); then a HALOutput unit recording, as OBS's
 * mac-capture plugin records, a 1 kHz sine that this program writes to the
 * file the null device records from (FERRY_AUDIO_INPUT_FILE), through an
 * input callback and AudioUnitRender. */
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(what, call)                                                                                              \
    do {                                                                                                               \
        OSStatus err_ = (call);                                                                                        \
        if (err_)                                                                                                      \
            printf("%s failed: %d\n", what, (int)err_);                                                                \
    } while (0)

static AudioDeviceID default_device(AudioObjectPropertySelector which)
{
    AudioObjectPropertyAddress a = {which, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID d = 0;
    UInt32 size = sizeof d;
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &d);
    return d;
}

static AudioUnit new_unit(OSType subtype)
{
    AudioComponentDescription desc = {kAudioUnitType_Output, subtype, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent c = AudioComponentFindNext(NULL, &desc);
    AudioUnit u = NULL;
    if (!c || AudioComponentInstanceNew(c, &u))
        return NULL;
    return u;
}

/* ---- playing ------------------------------------------------------------------------- */

typedef struct {
    double phase, freq, rate;
    UInt32 rendered, wanted, calls;
    int bad_timestamps;
    Float64 last_sample;
    dispatch_semaphore_t done;
} tone;

/* 16-bit interleaved stereo, as VLC asks for it */
static OSStatus render_s16(void *data, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus,
                           UInt32 frames, AudioBufferList *io)
{
    tone *t = data;
    SInt16 *s = io->mBuffers[0].mData;
    for (UInt32 i = 0; i < frames; i++) {
        SInt16 v = t->rendered < t->wanted ? (SInt16)lrint(16384 * sin(t->phase)) : 0;
        s[i * 2] = s[i * 2 + 1] = v;
        t->phase += 2 * M_PI * t->freq / t->rate;
        if (t->rendered < t->wanted && ++t->rendered == t->wanted)
            dispatch_semaphore_signal(t->done);
    }
    if (!(ts->mFlags & kAudioTimeStampSampleTimeValid) || ts->mSampleTime < t->last_sample)
        t->bad_timestamps++;
    t->last_sample = ts->mSampleTime;
    t->calls++;
    return noErr;
}

/* the default format: 32-bit float, one buffer a channel */
static OSStatus render_planar(void *data, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus,
                              UInt32 frames, AudioBufferList *io)
{
    tone *t = data;
    for (UInt32 i = 0; i < frames; i++) {
        float v = t->rendered < t->wanted ? (float)(0.25 * sin(t->phase)) : 0;
        for (UInt32 b = 0; b < io->mNumberBuffers; b++)
            ((float *)io->mBuffers[b].mData)[i] = b == 0 ? v : -v;
        t->phase += 2 * M_PI * t->freq / t->rate;
        if (t->rendered < t->wanted && ++t->rendered == t->wanted)
            dispatch_semaphore_signal(t->done);
    }
    t->calls++;
    return noErr;
}

/* what the null device played: frames, zero crossings of the left channel,
 * its peak, and whether the right is the left (or its negation) */
static void analyse(const float *s, long from, long to, double rate, const char *label, int negated)
{
    int crossings = 0, same = 1;
    float peak = 0;
    long first = -1, last = -1;
    for (long i = from; i < to; i++) {
        float l = s[i * 2], r = s[i * 2 + 1];
        if (fabsf(l) > peak)
            peak = fabsf(l);
        if (fabsf((negated ? -l : l) - r) > 1e-6f)
            same = 0;
        if (l != 0) {
            if (first < 0)
                first = i;
            last = i;
        }
    }
    for (long i = first + 1; first >= 0 && i <= last; i++)
        if ((s[(i - 1) * 2] < 0) != (s[i * 2] < 0))
            crossings++;
    double secs = first >= 0 ? (last - first + 1) / rate : 0;
    printf("%s: %ld sounding frames, about %.0f Hz, peak %.2f, right %s\n", label, first >= 0 ? last - first + 1 : 0,
           secs > 0 ? 10 * round(crossings / 2.0 / secs / 10) : 0, peak, same ? (negated ? "negates left" : "same as left") : "differs");
}

static void play(void)
{
    const char *path = getenv("FERRY_AUDIO_OUTPUT_FILE");
    if (!path) {
        printf("FERRY_AUDIO_OUTPUT_FILE isn't set\n");
        return;
    }
    unlink(path);

    /* HALOutput, as VLC's auhal module sets it up */
    AudioUnit u = new_unit(kAudioUnitSubType_HALOutput);
    printf("HALOutput: %s\n", u ? "found" : "missing");
    AudioDeviceID dev = default_device(kAudioHardwarePropertyDefaultOutputDevice);
    CHECK("CurrentDevice", AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                &dev, sizeof dev));
    AudioStreamBasicDescription dev_format;
    UInt32 size = sizeof dev_format;
    CHECK("output StreamFormat", AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                                      &dev_format, &size));
    printf("device side: %.0f Hz, %u channels\n", dev_format.mSampleRate, (unsigned)dev_format.mChannelsPerFrame);
    UInt32 io = 0;
    size = sizeof io;
    CHECK("HasIO", AudioUnitGetProperty(u, kAudioOutputUnitProperty_HasIO, kAudioUnitScope_Output, 0, &io, &size));
    printf("has output: %u\n", (unsigned)io);
    AudioStreamBasicDescription f = {48000, kAudioFormatLinearPCM,
                                     kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
    CHECK("input StreamFormat",
          AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sizeof f));
    tone t = {0, 440, 48000, 0, 48000, 0, 0, -1, dispatch_semaphore_create(0)};
    AURenderCallbackStruct cb = {render_s16, &t};
    CHECK("SetRenderCallback", AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                                    &cb, sizeof cb));
    UInt32 frames = 0;
    size = sizeof frames;
    CHECK("BufferFrameSize", AudioUnitGetProperty(u, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                                                  &frames, &size));
    printf("buffer frames through the unit: %u\n", (unsigned)frames);
    CHECK("Initialize", AudioUnitInitialize(u));
    CHECK("Start", AudioOutputUnitStart(u));
    UInt32 running = 0;
    size = sizeof running;
    AudioUnitGetProperty(u, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &running, &size);
    printf("running: %u\n", (unsigned)running);
    long waited = dispatch_semaphore_wait(t.done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    usleep(100000);
    CHECK("Stop", AudioOutputUnitStop(u));
    running = 1;
    AudioUnitGetProperty(u, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &running, &size);
    printf("one second rendered: %s, in %s calls, timestamps %s, running after stop: %u\n",
           waited ? "timed out" : "yes", t.calls >= 90 && t.calls <= 110 ? "about 100" : "the wrong number of",
           t.bad_timestamps ? "wrong" : "rising", (unsigned)running);
    AudioUnitUninitialize(u);
    AudioComponentInstanceDispose(u);
    struct stat st;
    stat(path, &st);
    long hal_frames = st.st_size / 8;

    /* DefaultOutput in its default format, at 24 kHz */
    u = new_unit(kAudioUnitSubType_DefaultOutput);
    printf("DefaultOutput: %s\n", u ? "found" : "missing");
    size = sizeof f;
    AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, &size);
    printf("its format: %.0f Hz, %u channels, float %d, non-interleaved %d\n", f.mSampleRate,
           (unsigned)f.mChannelsPerFrame, (f.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
           (f.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0);
    Float64 rate = 24000;
    CHECK("SampleRate", AudioUnitSetProperty(u, kAudioUnitProperty_SampleRate, kAudioUnitScope_Input, 0, &rate,
                                             sizeof rate));
    tone t2 = {0, 300, 24000, 0, 6000, 0, 0, -1, dispatch_semaphore_create(0)};
    cb = (AURenderCallbackStruct){render_planar, &t2};
    AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof cb);
    AudioUnitInitialize(u);
    AudioOutputUnitStart(u);
    waited = dispatch_semaphore_wait(t2.done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    usleep(100000);
    AudioOutputUnitStop(u);
    printf("a quarter second rendered: %s\n", waited ? "timed out" : "yes");
    AudioUnitUninitialize(u);
    AudioComponentInstanceDispose(u);

    /* what the null device played */
    FILE *file = fopen(path, "rb");
    stat(path, &st);
    long total = st.st_size / 8;
    float *s = malloc(st.st_size);
    fread(s, 8, total, file);
    fclose(file);
    analyse(s, 0, hal_frames, 48000, "HALOutput played", 0);
    analyse(s, hal_frames, total, 24000, "DefaultOutput played", 1);
    free(s);
}

/* ---- recording ----------------------------------------------------------------------- */

typedef struct {
    AudioUnit unit;
    AudioBufferList *list;
    float *left, *right;
    UInt32 got, wanted, calls;
    int errors, bad_bus, bad_host_time;
    dispatch_semaphore_t done;
} capture;

static OSStatus input_callback(void *data, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus,
                               UInt32 frames, AudioBufferList *unused)
{
    capture *c = data;
    if (bus != 1)
        c->bad_bus++;
    if (!(ts->mFlags & kAudioTimeStampHostTimeValid) || !ts->mHostTime)
        c->bad_host_time++;
    for (UInt32 b = 0; b < 2; b++) {
        c->list->mBuffers[b].mDataByteSize = frames * 4;
        c->list->mBuffers[b].mData = NULL; /* the unit's own buffers, as OBS asks */
    }
    OSStatus err = AudioUnitRender(c->unit, flags, ts, bus, frames, c->list);
    if (err) {
        c->errors++;
        return err;
    }
    for (UInt32 i = 0; i < frames && c->got < c->wanted; i++) {
        c->left[c->got] = ((float *)c->list->mBuffers[0].mData)[i];
        c->right[c->got] = ((float *)c->list->mBuffers[1].mData)[i];
        if (++c->got == c->wanted)
            dispatch_semaphore_signal(c->done);
    }
    c->calls++;
    return noErr;
}

static void record(void)
{
    const char *path = getenv("FERRY_AUDIO_INPUT_FILE");
    if (!path) {
        printf("FERRY_AUDIO_INPUT_FILE isn't set\n");
        return;
    }
    /* a second of 1 kHz at 48 kHz on the left, 2 kHz on the right */
    FILE *file = fopen(path, "wb");
    for (int i = 0; i < 48000; i++) {
        float frame[2] = {(float)(0.5 * sin(2 * M_PI * 1000 * i / 48000.0)),
                          (float)(0.25 * sin(2 * M_PI * 2000 * i / 48000.0))};
        fwrite(frame, sizeof frame, 1, file);
    }
    fclose(file);

    AudioUnit u = new_unit(kAudioUnitSubType_HALOutput);
    UInt32 on = 1, off = 0;
    CHECK("EnableIO input", AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on,
                                                 sizeof on));
    CHECK("EnableIO output", AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                                                  &off, sizeof off));
    AudioDeviceID dev = default_device(kAudioHardwarePropertyDefaultInputDevice);
    CHECK("CurrentDevice", AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                &dev, sizeof dev));
    AudioDeviceID current = 0;
    UInt32 size = sizeof current;
    AudioUnitGetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size);
    printf("recording from the default input: %d\n", current == dev);
    AudioStreamBasicDescription f;
    size = sizeof f;
    CHECK("device side", AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &f, &size));
    printf("device side: %.0f Hz, %u channels\n", f.mSampleRate, (unsigned)f.mChannelsPerFrame);
    size = sizeof f;
    AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &f, &size);
    f.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    f.mBitsPerChannel = 32;
    f.mBytesPerFrame = f.mBytesPerPacket = 4;
    f.mFramesPerPacket = 1;
    CHECK("client side", AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &f,
                                              sizeof f));
    capture c = {u, NULL, calloc(24000, 4), calloc(24000, 4), 0, 24000, 0, 0, 0, 0, dispatch_semaphore_create(0)};
    c.list = calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer));
    c.list->mNumberBuffers = 2;
    c.list->mBuffers[0].mNumberChannels = c.list->mBuffers[1].mNumberChannels = 1;
    AURenderCallbackStruct cb = {input_callback, &c};
    CHECK("SetInputCallback", AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback,
                                                   kAudioUnitScope_Global, 0, &cb, sizeof cb));
    CHECK("Initialize", AudioUnitInitialize(u));
    CHECK("Start", AudioOutputUnitStart(u));
    long waited = dispatch_semaphore_wait(c.done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    CHECK("Stop", AudioOutputUnitStop(u));
    printf("half a second recorded: %s, in %s calls, bus 1 always: %d, host times: %d, errors: %d\n",
           waited ? "timed out" : "yes", c.calls >= 40 && c.calls <= 60 ? "about 47" : "the wrong number of",
           !c.bad_bus, !c.bad_host_time, c.errors);
    float peak[2] = {0, 0};
    int crossings[2] = {0, 0};
    for (UInt32 i = 0; i < c.got; i++) {
        if (fabsf(c.left[i]) > peak[0])
            peak[0] = fabsf(c.left[i]);
        if (fabsf(c.right[i]) > peak[1])
            peak[1] = fabsf(c.right[i]);
        if (i && (c.left[i - 1] < 0) != (c.left[i] < 0))
            crossings[0]++;
        if (i && (c.right[i - 1] < 0) != (c.right[i] < 0))
            crossings[1]++;
    }
    double secs = c.got / 48000.0;
    printf("left: about %.0f Hz, peak %.2f; right: about %.0f Hz, peak %.2f\n",
           100 * round(crossings[0] / 2.0 / secs / 100), peak[0], 100 * round(crossings[1] / 2.0 / secs / 100),
           peak[1]);
    AudioUnitUninitialize(u);
    AudioComponentInstanceDispose(u);
}

int main(void)
{
    play();
    record();
    return 0;
}
