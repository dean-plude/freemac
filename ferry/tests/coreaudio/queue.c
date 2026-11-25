/* SPDX-License-Identifier: GPL-3.0-or-later
 * Audio queues on the null device (freemac 1.234, Ferry 0.58.0): an input
 * queue recording, with its callbacks on its own thread, what an output
 * queue plays through the null device's loopback, with the output's
 * callbacks on this program's run loop; the queues' properties and
 * listeners; and an output queue with its callbacks on a dispatch queue,
 * stopped once it has played what it was given. */
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { RATE = 48000, BUFFERS = 3, FRAMES = 2400 /* 50 ms */ };

static const AudioStreamBasicDescription s16 = {
    RATE, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};

/* ---- the output: half a second of 600 Hz, from the run loop ----------------------------- */

typedef struct {
    double phase;
    UInt32 left;   /* frames still to play */
    int callbacks, wrong_thread;
    pthread_t main_thread;
} player;

static void fill(player *p, AudioQueueRef q, AudioQueueBufferRef b)
{
    SInt16 *s = b->mAudioData;
    UInt32 n = p->left < FRAMES ? p->left : FRAMES;
    for (UInt32 i = 0; i < n; i++) {
        s[i * 2] = (SInt16)lrint(12000 * sin(p->phase));
        s[i * 2 + 1] = -s[i * 2];
        p->phase += 2 * M_PI * 600 / RATE;
    }
    p->left -= n;
    b->mAudioDataByteSize = n * 4;
    if (n)
        AudioQueueEnqueueBuffer(q, b, 0, NULL);
}

static void output_callback(void *data, AudioQueueRef q, AudioQueueBufferRef b)
{
    player *p = data;
    p->callbacks++;
    if (!pthread_equal(pthread_self(), p->main_thread))
        p->wrong_thread++;
    fill(p, q, b);
}

/* ---- the input: a second of what the null device hears ---------------------------------- */

typedef struct {
    SInt16 *samples;
    UInt32 got, wanted;
    int callbacks, on_main_thread, bad_times;
    pthread_t main_thread;
    Float64 last_time;
    dispatch_semaphore_t done, recording;
} recorder;

static void input_callback(void *data, AudioQueueRef q, AudioQueueBufferRef b, const AudioTimeStamp *start,
                           UInt32 packets, const AudioStreamPacketDescription *descs)
{
    recorder *r = data;
    if (!r->callbacks++)
        dispatch_semaphore_signal(r->recording);
    if (pthread_equal(pthread_self(), r->main_thread))
        r->on_main_thread++;
    if (start->mSampleTime < r->last_time || packets != b->mAudioDataByteSize / 4)
        r->bad_times++;
    r->last_time = start->mSampleTime;
    UInt32 frames = b->mAudioDataByteSize / 4;
    for (UInt32 i = 0; i < frames && r->got < r->wanted; i++, r->got++) {
        r->samples[r->got * 2] = ((SInt16 *)b->mAudioData)[i * 2];
        r->samples[r->got * 2 + 1] = ((SInt16 *)b->mAudioData)[i * 2 + 1];
    }
    if (r->got >= r->wanted)
        dispatch_semaphore_signal(r->done);
    else
        AudioQueueEnqueueBuffer(q, b, 0, NULL);
}

static int running_heard;
static void running_listener(void *data, AudioQueueRef q, AudioQueuePropertyID id)
{
    UInt32 running = 0, size = sizeof running;
    AudioQueueGetProperty(q, kAudioQueueProperty_IsRunning, &running, &size);
    running_heard += running ? 1 : 100;
}

int main(void)
{
    recorder r = {calloc(RATE * 2, 2), 0, RATE, 0, 0, 0, pthread_self(), -1, dispatch_semaphore_create(0),
                  dispatch_semaphore_create(0)};
    AudioQueueRef in = NULL, out = NULL;
    OSStatus err = AudioQueueNewInput(&s16, input_callback, &r, NULL, NULL, 0, &in);
    printf("new input: %d\n", (int)err);
    for (int i = 0; i < BUFFERS; i++) {
        AudioQueueBufferRef b;
        AudioQueueAllocateBuffer(in, FRAMES * 4, &b);
        AudioQueueEnqueueBuffer(in, b, 0, NULL);
    }
    AudioStreamBasicDescription f;
    UInt32 size = sizeof f;
    AudioQueueGetProperty(in, kAudioQueueProperty_StreamDescription, &f, &size);
    printf("input format: %.0f Hz, %u channels, %u bits\n", f.mSampleRate, (unsigned)f.mChannelsPerFrame,
           (unsigned)f.mBitsPerChannel);
    CFStringRef device = (CFStringRef)1;
    size = sizeof device;
    AudioQueueGetProperty(in, kAudioQueueProperty_CurrentDevice, &device, &size);
    printf("input device: %s\n", device ? "named" : "the default");
    Float64 drate = 0;
    AudioQueueGetProperty(in, kAudioQueueDeviceProperty_SampleRate, &drate, &(UInt32){sizeof drate});
    printf("device rate: %.0f\n", drate);

    player p = {0, RATE / 2, 0, 0, pthread_self()};
    err = AudioQueueNewOutput(&s16, output_callback, &p, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &out);
    printf("new output: %d\n", (int)err);
    AudioQueueAddPropertyListener(out, kAudioQueueProperty_IsRunning, running_listener, NULL);
    for (int i = 0; i < BUFFERS; i++) {
        AudioQueueBufferRef b;
        AudioQueueAllocateBuffer(out, FRAMES * 4, &b);
        printf("%s", i ? "" : "buffer: ");
        if (!i)
            printf("%u bytes of room, %u used\n", (unsigned)b->mAudioDataBytesCapacity, (unsigned)b->mAudioDataByteSize);
        fill(&p, out, b);
    }
    AudioQueueSetParameter(out, kAudioQueueParam_Volume, 1.0);

    /* the loopback hears what is played once a recording has begun */
    printf("start input: %d\n", (int)AudioQueueStart(in, NULL));
    long waited = dispatch_semaphore_wait(r.recording, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    printf("recording: %s\n", waited ? "timed out" : "yes");
    printf("start output: %d\n", (int)AudioQueueStart(out, NULL));
    /* the output's callbacks come on this run loop, until the input has its
     * second; a source that never fires keeps the run loop waiting rather
     * than spinning */
    CFRunLoopSourceContext ctx = {0};
    CFRunLoopSourceRef keep = CFRunLoopSourceCreate(NULL, 0, &ctx);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), keep, kCFRunLoopDefaultMode);
    while (dispatch_semaphore_wait(r.done, DISPATCH_TIME_NOW))
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    CFRunLoopSourceInvalidate(keep);
    CFRelease(keep);
    /* a stop once played out, which listeners hear when it has */
    AudioQueueStop(out, false);
    AudioQueueStop(in, true);
    for (int i = 0; i < 200 && running_heard < 100; i++)
        usleep(10000);
    printf("output: %s callbacks on the run loop, none elsewhere: %d, all played: %d\n",
           p.callbacks >= 7 && p.callbacks <= 10 ? "about 8" : "the wrong number of", !p.wrong_thread, p.left == 0);
    printf("running heard: %s\n", running_heard == 101 ? "started, then stopped" : "wrong");
    printf("input: %s callbacks off the main thread: %d, times rising: %d\n",
           r.callbacks == RATE / FRAMES ? "20" : "the wrong number of", !r.on_main_thread, !r.bad_times);

    /* what came back: 600 Hz for about half a second, right the left negated */
    UInt32 first = 0, last = 0, crossings = 0, negated = 1, peak = 0;
    for (UInt32 i = 0; i < r.got; i++) {
        SInt16 l = r.samples[i * 2], rr = r.samples[i * 2 + 1];
        if (l && !first)
            first = i;
        if (l)
            last = i;
        if (l != -rr)
            negated = 0;
        if ((UInt32)abs(l) > peak)
            peak = abs(l);
    }
    for (UInt32 i = first + 1; i <= last; i++)
        if ((r.samples[(i - 1) * 2] < 0) != (r.samples[i * 2] < 0))
            crossings++;
    double secs = (last - first + 1) / (double)RATE;
    printf("heard: %s of sound, about %.0f Hz, peak %u, right the left negated: %d\n",
           fabs(secs - 0.5) < 0.002 ? "half a second" : "the wrong amount", 10 * round(crossings / 2.0 / secs / 10),
           (unsigned)peak, negated);
    AudioQueueDispose(out, true);
    AudioQueueDispose(in, true);

    /* an output queue on a dispatch queue, stopped when its buffers have played */
    dispatch_queue_t dq = dispatch_queue_create("test.audioqueue", NULL);
    __block int played = 0;
    dispatch_semaphore_t all = dispatch_semaphore_create(0);
    err = AudioQueueNewOutputWithDispatchQueue(&out, &s16, 0, dq, ^(AudioQueueRef q, AudioQueueBufferRef b) {
      if (++played == 2)
          dispatch_semaphore_signal(all);
    });
    printf("new output on a dispatch queue: %d\n", (int)err);
    for (int i = 0; i < 2; i++) {
        AudioQueueBufferRef b;
        AudioQueueAllocateBuffer(out, FRAMES * 4, &b);
        memset(b->mAudioData, 0, FRAMES * 4);
        b->mAudioDataByteSize = FRAMES * 4;
        AudioQueueEnqueueBuffer(out, b, 0, NULL);
    }
    UInt32 prepared = 0;
    AudioQueuePrime(out, 0, &prepared);
    AudioQueueStart(out, NULL);
    waited = dispatch_semaphore_wait(all, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    AudioTimeStamp now;
    Boolean discontinuity = 1;
    err = AudioQueueGetCurrentTime(out, NULL, &now, &discontinuity);
    printf("both played: %s, current time %d at %s\n", waited ? "timed out" : "yes", (int)err,
           now.mSampleTime >= FRAMES ? "two buffers or more" : "too few frames");
    AudioQueueStop(out, true);
    AudioQueueDispose(out, true);
    AudioStreamBasicDescription aac = {RATE, kAudioFormatMPEG4AAC, 0, 0, 1024, 0, 2, 0, 0};
    err = AudioQueueNewOutput(&aac, output_callback, &p, NULL, NULL, 0, &out);
    printf("AAC: %s\n", err == kAudioFormatUnsupportedDataFormatError ? "unsupported" : "?");
    return 0;
}
