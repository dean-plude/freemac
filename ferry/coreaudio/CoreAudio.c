/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Audio's audio objects on this system's sound server (sdk/include/
 * CoreAudio/CoreAudio.h; freemac 1.232, Ferry 0.56.0), written from
 * Apple's public documentation. The system object (1) names the default
 * output device (2) and input device (3); a device answers its name, its
 * volume as a scalar from 0 to 1 (the main element and channels 1 and 2
 * alike) and its mute, read and set with pactl, or wpctl where PipeWire has
 * no pactl. With neither, the devices are there and answer "not running". */
#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { OUTPUT = 2, INPUT = 3 };

/* The first line a command prints (with its error output dropped), or "". */
static int run(const char *command, char *out, size_t size)
{
    out[0] = 0;
    FILE *p = popen(command, "r");
    if (!p)
        return -1;
    size_t n = fread(out, 1, size - 1, p);
    out[n] = 0;
    int status = pclose(p);
    return status == 0 ? 0 : -1;
}

static int have(const char *tool)
{
    char cmd[128], out[256];
    snprintf(cmd, sizeof cmd, "command -v %s 2>/dev/null", tool);
    return run(cmd, out, sizeof out) == 0 && out[0];
}

static const char *pa_name(AudioObjectID dev) { return dev == INPUT ? "@DEFAULT_SOURCE@" : "@DEFAULT_SINK@"; }
static const char *pa_kind(AudioObjectID dev) { return dev == INPUT ? "source" : "sink"; }
static const char *wp_name(AudioObjectID dev) { return dev == INPUT ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@"; }

/* the volume from 0 to 1, or -1 */
static double get_volume(AudioObjectID dev, int *muted)
{
    char cmd[256], out[4096];
    if (have("pactl")) {
        snprintf(cmd, sizeof cmd, "pactl get-%s-volume %s 2>/dev/null", pa_kind(dev), pa_name(dev));
        if (run(cmd, out, sizeof out) == 0) {
            /* "Volume: front-left: 26214 /  40% / -23.88 dB, ..." */
            char *pct = strchr(out, '%');
            double v = -1;
            if (pct) {
                char *s = pct;
                while (s > out && (s[-1] == ' ' || (s[-1] >= '0' && s[-1] <= '9')))
                    s--;
                v = atof(s) / 100.0;
            }
            if (muted) {
                snprintf(cmd, sizeof cmd, "pactl get-%s-mute %s 2>/dev/null", pa_kind(dev), pa_name(dev));
                *muted = run(cmd, out, sizeof out) == 0 && strstr(out, "yes") != NULL;
            }
            return v;
        }
    }
    if (have("wpctl")) {
        snprintf(cmd, sizeof cmd, "wpctl get-volume %s 2>/dev/null", wp_name(dev));
        if (run(cmd, out, sizeof out) == 0) {
            /* "Volume: 0.40 [MUTED]" */
            char *v = strstr(out, "Volume:");
            if (muted)
                *muted = strstr(out, "MUTED") != NULL;
            return v ? atof(v + 7) : -1;
        }
    }
    return -1;
}

static int set_volume(AudioObjectID dev, double v)
{
    char cmd[256], out[256];
    if (v < 0)
        v = 0;
    if (v > 1)
        v = 1;
    if (have("pactl")) {
        snprintf(cmd, sizeof cmd, "pactl set-%s-volume %s %d%% 2>/dev/null", pa_kind(dev), pa_name(dev), (int)(v * 100 + 0.5));
        return run(cmd, out, sizeof out);
    }
    if (have("wpctl")) {
        snprintf(cmd, sizeof cmd, "wpctl set-volume %s %.2f 2>/dev/null", wp_name(dev), v);
        return run(cmd, out, sizeof out);
    }
    return -1;
}

static int set_mute(AudioObjectID dev, int mute)
{
    char cmd[256], out[256];
    if (have("pactl")) {
        snprintf(cmd, sizeof cmd, "pactl set-%s-mute %s %d 2>/dev/null", pa_kind(dev), pa_name(dev), mute ? 1 : 0);
        return run(cmd, out, sizeof out);
    }
    if (have("wpctl")) {
        snprintf(cmd, sizeof cmd, "wpctl set-mute %s %d 2>/dev/null", wp_name(dev), mute ? 1 : 0);
        return run(cmd, out, sizeof out);
    }
    return -1;
}

static CFStringRef device_name(AudioObjectID dev)
{
    return CFStringCreateWithCString(NULL, dev == INPUT ? "Default Input" : "Default Output", kCFStringEncodingUTF8);
}

/* What the property is: 0 none, or its size. */
static UInt32 property_size(AudioObjectID obj, const AudioObjectPropertyAddress *a)
{
    if (!a)
        return 0;
    if (obj == kAudioObjectSystemObject) {
        switch (a->mSelector) {
        case kAudioHardwarePropertyDefaultOutputDevice:
        case kAudioHardwarePropertyDefaultSystemOutputDevice:
        case kAudioHardwarePropertyDefaultInputDevice:
            return sizeof(AudioObjectID);
        case kAudioHardwarePropertyDevices:
            return 2 * sizeof(AudioObjectID);
        }
        return 0;
    }
    if (obj != OUTPUT && obj != INPUT)
        return 0;
    switch (a->mSelector) {
    case kAudioObjectPropertyName:
    case kAudioObjectPropertyManufacturer:
    case kAudioDevicePropertyDeviceUID:
        return sizeof(CFStringRef);
    case kAudioDevicePropertyVolumeScalar:
    case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
        if (a->mElement > 2 && a->mElement != kAudioObjectPropertyElementWildcard)
            return 0;
        return sizeof(Float32);
    case kAudioDevicePropertyMute:
        return sizeof(UInt32);
    }
    return 0;
}

Boolean AudioObjectHasProperty(AudioObjectID obj, const AudioObjectPropertyAddress *a)
{
    return property_size(obj, a) != 0;
}

OSStatus AudioObjectIsPropertySettable(AudioObjectID obj, const AudioObjectPropertyAddress *a, Boolean *settable)
{
    if (!property_size(obj, a))
        return obj == kAudioObjectSystemObject || obj == OUTPUT || obj == INPUT ? kAudioHardwareUnknownPropertyError
                                                                                 : kAudioHardwareBadObjectError;
    if (settable)
        *settable = obj != kAudioObjectSystemObject &&
                    (a->mSelector == kAudioDevicePropertyVolumeScalar || a->mSelector == kAudioDevicePropertyMute ||
                     a->mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume);
    return kAudioHardwareNoError;
}

OSStatus AudioObjectGetPropertyDataSize(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                        const void *q, UInt32 *size)
{
    UInt32 n = property_size(obj, a);
    if (!n)
        return obj == kAudioObjectSystemObject || obj == OUTPUT || obj == INPUT ? kAudioHardwareUnknownPropertyError
                                                                                 : kAudioHardwareBadObjectError;
    if (size)
        *size = n;
    return kAudioHardwareNoError;
}

OSStatus AudioObjectGetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                    const void *q, UInt32 *ioSize, void *out)
{
    UInt32 n = property_size(obj, a);
    if (!n)
        return obj == kAudioObjectSystemObject || obj == OUTPUT || obj == INPUT ? kAudioHardwareUnknownPropertyError
                                                                                 : kAudioHardwareBadObjectError;
    if (!ioSize || !out || *ioSize < n)
        return kAudioHardwareBadPropertySizeError;
    *ioSize = n;
    if (obj == kAudioObjectSystemObject) {
        AudioObjectID *ids = out;
        if (a->mSelector == kAudioHardwarePropertyDevices) {
            ids[0] = OUTPUT;
            ids[1] = INPUT;
        } else
            ids[0] = a->mSelector == kAudioHardwarePropertyDefaultInputDevice ? INPUT : OUTPUT;
        return kAudioHardwareNoError;
    }
    switch (a->mSelector) {
    case kAudioObjectPropertyName:
        *(CFStringRef *)out = device_name(obj);
        return kAudioHardwareNoError;
    case kAudioObjectPropertyManufacturer:
        *(CFStringRef *)out = CFStringCreateWithCString(NULL, "freemac", kCFStringEncodingUTF8);
        return kAudioHardwareNoError;
    case kAudioDevicePropertyDeviceUID:
        *(CFStringRef *)out = CFStringCreateWithCString(NULL, obj == INPUT ? "freemac-default-input" : "freemac-default-output",
                                                        kCFStringEncodingUTF8);
        return kAudioHardwareNoError;
    case kAudioDevicePropertyMute: {
        int muted = 0;
        if (get_volume(obj, &muted) < 0)
            return kAudioHardwareNotRunningError;
        *(UInt32 *)out = muted;
        return kAudioHardwareNoError;
    }
    default: {
        double v = get_volume(obj, NULL);
        if (v < 0)
            return kAudioHardwareNotRunningError;
        *(Float32 *)out = (Float32)(v > 1 ? 1 : v);
        return kAudioHardwareNoError;
    }
    }
}

OSStatus AudioObjectSetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                    const void *q, UInt32 size, const void *data)
{
    Boolean settable = 0;
    OSStatus s = AudioObjectIsPropertySettable(obj, a, &settable);
    if (s)
        return s;
    if (!settable)
        return kAudioHardwareIllegalOperationError;
    if (!data || size < property_size(obj, a))
        return kAudioHardwareBadPropertySizeError;
    int r = a->mSelector == kAudioDevicePropertyMute ? set_mute(obj, *(const UInt32 *)data != 0)
                                                     : set_volume(obj, *(const Float32 *)data);
    return r == 0 ? kAudioHardwareNoError : kAudioHardwareNotRunningError;
}
