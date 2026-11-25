/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Audio on a sound server (freemac 1.234, Ferry 0.58.0): run.sh
 * starts a PulseAudio of its own with two null sinks, ferry_test_sink and
 * ferry_other_sink. Each is an output device, and its monitor an input
 * device that isn't a default; setting the default output is heard by a
 * listener and by the server; a HALOutput unit plays a 440 Hz sine to
 * ferry_test_sink while another records it from the monitor; and a sink
 * loaded while the program runs (with FERRY_TEST_PACTL) appears in the
 * device list, which a listener hears. */
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static AudioObjectPropertyAddress addr(AudioObjectPropertySelector s, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = {s, scope, kAudioObjectPropertyElementMain};
    return a;
}

static AudioDeviceID device_for(const char *uid)
{
    CFStringRef s = CFStringCreateWithCString(NULL, uid, kCFStringEncodingUTF8);
    AudioDeviceID d = kAudioObjectUnknown;
    AudioValueTranslation t = {&s, sizeof s, &d, sizeof d};
    AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDeviceForUID, kAudioObjectPropertyScopeGlobal);
    UInt32 size = sizeof t;
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &t);
    CFRelease(s);
    return d;
}

static UInt32 get_u32(AudioObjectID obj, AudioObjectPropertySelector sel, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = addr(sel, scope);
    UInt32 v = 0, size = sizeof v;
    return AudioObjectGetPropertyData(obj, &a, 0, NULL, &size, &v) ? 0xdeadbeef : v;
}

static UInt32 device_count(void)
{
    AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size);
    return size / sizeof(AudioDeviceID);
}

static int has_name(AudioObjectID d)
{
    AudioObjectPropertyAddress a = addr(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal);
    CFStringRef s = NULL;
    UInt32 size = sizeof s;
    if (AudioObjectGetPropertyData(d, &a, 0, NULL, &size, &s) || !s)
        return 0;
    int ok = CFStringGetLength(s) > 0;
    CFRelease(s);
    return ok;
}

static UInt32 stream_count(AudioObjectID d, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = addr(kAudioDevicePropertyStreams, scope);
    UInt32 size = 0;
    AudioObjectGetPropertyDataSize(d, &a, 0, NULL, &size);
    return size / sizeof(AudioStreamID);
}

static dispatch_semaphore_t heard;
static OSStatus listener(AudioObjectID obj, UInt32 n, const AudioObjectPropertyAddress *a, void *data)
{
    for (UInt32 i = 0; i < n; i++)
        if (a[i].mSelector == *(AudioObjectPropertySelector *)data)
            dispatch_semaphore_signal(heard);
    return noErr;
}

static AudioUnit hal_unit(AudioDeviceID dev, int input)
{
    AudioComponentDescription desc = {kAudioUnitType_Output, kAudioUnitSubType_HALOutput, kAudioUnitManufacturer_Apple,
                                      0, 0};
    AudioUnit u = NULL;
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &desc), &u);
    if (input) {
        UInt32 on = 1, off = 0;
        AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, sizeof on);
        AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, sizeof off);
    }
    AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, sizeof dev);
    AudioStreamBasicDescription f = {48000, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked, 8, 1, 8, 2, 32, 0};
    AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, input ? kAudioUnitScope_Output : kAudioUnitScope_Input,
                         input ? 1 : 0, &f, sizeof f);
    return u;
}

static double phase;
static OSStatus render(void *data, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus,
                       UInt32 frames, AudioBufferList *io)
{
    float *s = io->mBuffers[0].mData;
    for (UInt32 i = 0; i < frames; i++) {
        s[i * 2] = s[i * 2 + 1] = (float)(0.5 * sin(phase));
        phase += 2 * M_PI * 440 / 48000;
    }
    return noErr;
}

enum { WANTED = 48000 };
static float recorded[WANTED];
static UInt32 got;
static AudioUnit recorder;
static AudioBufferList *capture_list;
static OSStatus input(void *data, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus,
                      UInt32 frames, AudioBufferList *unused)
{
    capture_list->mBuffers[0].mData = NULL;
    capture_list->mBuffers[0].mDataByteSize = frames * 8;
    if (AudioUnitRender(recorder, flags, ts, bus, frames, capture_list))
        return noErr;
    const float *s = capture_list->mBuffers[0].mData;
    for (UInt32 i = 0; i < frames && got < WANTED; i++)
        recorded[got++] = s[i * 2];
    if (got == WANTED)
        dispatch_semaphore_signal(heard);
    return noErr;
}

int main(void)
{
    heard = dispatch_semaphore_create(0);
    AudioDeviceID sink = device_for("ferry_test_sink"), other = device_for("ferry_other_sink"),
                  monitor = device_for("ferry_test_sink.monitor");
    printf("found: sink %d, other %d, monitor %d\n", sink != kAudioObjectUnknown, other != kAudioObjectUnknown,
           monitor != kAudioObjectUnknown);
    printf("named: %d %d %d\n", has_name(sink), has_name(other), has_name(monitor));
    printf("sink streams: %u out, %u in; monitor streams: %u out, %u in\n",
           (unsigned)stream_count(sink, kAudioObjectPropertyScopeOutput),
           (unsigned)stream_count(sink, kAudioObjectPropertyScopeInput),
           (unsigned)stream_count(monitor, kAudioObjectPropertyScopeOutput),
           (unsigned)stream_count(monitor, kAudioObjectPropertyScopeInput));
    AudioDeviceID def_in = get_u32(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultInputDevice,
                                   kAudioObjectPropertyScopeGlobal);
    printf("default input is the monitor: %d\n", def_in == monitor);
    printf("alive: %u\n", (unsigned)get_u32(sink, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal));

    /* the default output, set */
    AudioObjectPropertySelector which = kAudioHardwarePropertyDefaultOutputDevice;
    AudioObjectPropertyAddress a = addr(which, kAudioObjectPropertyScopeGlobal);
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &a, listener, &which);
    OSStatus err = AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, sizeof other, &other);
    long waited = dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    printf("default output set to the other sink: %d, heard %s, now %d\n", (int)err, waited ? "no" : "yes",
           get_u32(kAudioObjectSystemObject, which, kAudioObjectPropertyScopeGlobal) == other);
    AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, sizeof sink, &sink);
    dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &a, listener, &which);
    printf("and back: %d\n", get_u32(kAudioObjectSystemObject, which, kAudioObjectPropertyScopeGlobal) == sink);

    /* the sink's volume and mute, set on the server and heard by a listener */
    heard = dispatch_semaphore_create(0);
    which = kAudioDevicePropertyVolumeScalar;
    a = addr(which, kAudioObjectPropertyScopeOutput);
    Boolean settable = 0;
    AudioObjectIsPropertySettable(sink, &a, &settable);
    AudioObjectAddPropertyListener(sink, &a, listener, &which);
    Float32 volume = 0.25f;
    err = AudioObjectSetPropertyData(sink, &a, 0, NULL, sizeof volume, &volume);
    waited = dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    volume = 0;
    UInt32 size = sizeof volume;
    AudioObjectGetPropertyData(sink, &a, 0, NULL, &size, &volume);
    printf("volume settable %d, set to a quarter: %d, heard %s, now %.2f\n", settable, (int)err, waited ? "no" : "yes",
           volume);
    AudioObjectRemovePropertyListener(sink, &a, listener, &which);
    a.mElement = 1;
    volume = 1;
    err = AudioObjectSetPropertyData(sink, &a, 0, NULL, sizeof volume, &volume);
    a.mElement = 0;
    AudioObjectGetPropertyData(sink, &a, 0, NULL, &size, &volume);
    printf("set through channel 1: %d, now %.2f\n", (int)err, volume);
    a = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput);
    UInt32 mute = 1;
    err = AudioObjectSetPropertyData(sink, &a, 0, NULL, sizeof mute, &mute);
    printf("muted: %d %u", (int)err, (unsigned)get_u32(sink, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput));
    mute = 0;
    AudioObjectSetPropertyData(sink, &a, 0, NULL, sizeof mute, &mute);
    printf(", and not: %u\n", (unsigned)get_u32(sink, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput));

    /* a sine played to the sink, recorded from its monitor */
    recorder = hal_unit(monitor, 1);
    capture_list = calloc(1, sizeof(AudioBufferList));
    capture_list->mNumberBuffers = 1;
    capture_list->mBuffers[0].mNumberChannels = 2;
    AURenderCallbackStruct cb = {input, NULL};
    AudioUnitSetProperty(recorder, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, sizeof cb);
    AudioUnit player = hal_unit(sink, 0);
    cb = (AURenderCallbackStruct){render, NULL};
    AudioUnitSetProperty(player, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof cb);
    AudioUnitInitialize(recorder);
    AudioUnitInitialize(player);
    err = AudioOutputUnitStart(recorder);
    OSStatus err2 = AudioOutputUnitStart(player);
    printf("started: %d %d\n", (int)err, (int)err2);
    waited = dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    AudioOutputUnitStop(player);
    AudioOutputUnitStop(recorder);
    UInt32 first = WANTED, crossings = 0;
    float peak = 0;
    for (UInt32 i = 0; i < got; i++)
        if (fabsf(recorded[i]) > 0.01f) {
            first = i;
            break;
        }
    for (UInt32 i = first + 1; i < got; i++) {
        if ((recorded[i - 1] < 0) != (recorded[i] < 0))
            crossings++;
        if (fabsf(recorded[i]) > peak)
            peak = fabsf(recorded[i]);
    }
    double secs = got > first ? (got - first) / 48000.0 : 0;
    double hz = secs > 0.2 ? crossings / 2.0 / secs : 0;
    printf("recorded a second: %s; heard the sine: %s (%s)\n", waited ? "no" : "yes",
           fabs(hz - 440) < 10 && peak > 0.45 && peak < 0.55 ? "yes" : "no",
           secs > 0.2 ? "after the server's latency" : "nothing came back");
    fprintf(stderr, "recorded: first sound at %u, %.1f Hz, peak %.3f\n", (unsigned)first, hz, peak);
    AudioComponentInstanceDispose(player);
    AudioComponentInstanceDispose(recorder);

    /* a DefaultOutput unit follows the default output to the other sink,
     * heard from that sink's monitor */
    AudioDeviceID other_monitor = device_for("ferry_other_sink.monitor");
    got = 0;
    heard = dispatch_semaphore_create(0);
    recorder = hal_unit(other_monitor, 1);
    cb = (AURenderCallbackStruct){input, NULL};
    AudioUnitSetProperty(recorder, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, sizeof cb);
    AudioComponentDescription dd = {kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple,
                                    0, 0};
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &dd), &player);
    AudioStreamBasicDescription f = {48000, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked, 8, 1, 8, 2, 32, 0};
    AudioUnitSetProperty(player, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sizeof f);
    cb = (AURenderCallbackStruct){render, NULL};
    AudioUnitSetProperty(player, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof cb);
    AudioUnitInitialize(recorder);
    AudioUnitInitialize(player);
    AudioOutputUnitStart(recorder);
    AudioOutputUnitStart(player);
    usleep(300000);
    float before_switch = 0;
    for (UInt32 i = 0; i < got; i++)
        if (fabsf(recorded[i]) > before_switch)
            before_switch = fabsf(recorded[i]);
    a = addr(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
    AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, sizeof other, &other);
    waited = dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    AudioOutputUnitStop(player);
    AudioOutputUnitStop(recorder);
    AudioDeviceID current = 0;
    size = sizeof current;
    AudioUnitGetProperty(player, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size);
    peak = 0;
    for (UInt32 i = 0; i < got; i++)
        if (fabsf(recorded[i]) > peak)
            peak = fabsf(recorded[i]);
    printf("DefaultOutput on the other sink before the switch: %s, after: %s, its device now the other sink: %d\n",
           before_switch < 0.01f ? "silent" : "heard", waited ? "nothing recorded" : peak > 0.45f ? "heard" : "silent",
           current == other);
    AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, sizeof sink, &sink);
    AudioComponentInstanceDispose(player);
    AudioComponentInstanceDispose(recorder);

    /* a sink loaded meanwhile */
    const char *pactl = getenv("FERRY_TEST_PACTL");
    if (pactl) {
        UInt32 before = device_count();
        which = kAudioHardwarePropertyDevices;
        a = addr(which, kAudioObjectPropertyScopeGlobal);
        AudioObjectAddPropertyListener(kAudioObjectSystemObject, &a, listener, &which);
        char cmd[1024];
        snprintf(cmd, sizeof cmd, "%s load-module module-null-sink sink_name=ferry_hotplug_sink >/dev/null", pactl);
        int r = system(cmd);
        AudioDeviceID added = kAudioObjectUnknown;
        for (int i = 0; i < 50 && added == kAudioObjectUnknown; i++) {
            dispatch_semaphore_wait(heard, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
            added = device_for("ferry_hotplug_sink");
        }
        printf("loaded a sink: %d, listed: %d, two more devices (it and its monitor): %d\n", r,
               added != kAudioObjectUnknown, device_count() == before + 2);
    }
    return 0;
}
