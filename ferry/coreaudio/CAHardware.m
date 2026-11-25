/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The audio HAL's object model (freemac 1.234, Ferry 0.58.0): the system
 * object, its devices and their streams, their properties and the
 * listeners that hear them change; IO procs, which a device calls each IO
 * cycle; host time; and the older AudioHardware and AudioDevice property
 * calls. Written from Apple's public documentation of AudioHardware.h and
 * AudioHardwareBase.h.
 *
 * Listeners hear changes asynchronously, as on a Mac: on a queue of the
 * HAL's own, or on the run loop that kAudioHardwarePropertyRunLoop names,
 * or, for listener blocks, on the queue they were added with.
 */
#import "CAInternal.h"
#include <Block.h>
#include <math.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* ---- host time: Ferry's host clock counts nanoseconds ------------------------------- */

UInt64 ca_now(void)
{
    return mach_absolute_time();
}

void ca_sleep_ns(UInt64 ns)
{
    struct timespec t = {(time_t)(ns / 1000000000ull), (long)(ns % 1000000000ull)};
    while (nanosleep(&t, &t) < 0)
        ;
}

UInt64 AudioGetCurrentHostTime(void)
{
    return mach_absolute_time();
}

Float64 AudioGetHostClockFrequency(void)
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    return 1e9 * tb.denom / tb.numer;
}

UInt32 AudioGetHostClockMinimumTimeDelta(void)
{
    return 1;
}

UInt64 AudioConvertHostTimeToNanos(UInt64 t)
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    return tb.numer == tb.denom ? t : (UInt64)((double)t * tb.numer / tb.denom);
}

UInt64 AudioConvertNanosToHostTime(UInt64 ns)
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    return tb.numer == tb.denom ? ns : (UInt64)((double)ns * tb.denom / tb.numer);
}

/* ---- the system object's own settings ------------------------------------------------- */

static CFRunLoopRef notify_run_loop;
static UInt32 sleeping_allowed = 1, unloading_allowed = 1, process_audible = 1, input_muted, power_hint;

static const Float64 rates[] = {8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000};
enum { RATE_COUNT = sizeof rates / sizeof rates[0] };
enum { MIN_BUFFER_FRAMES = 32, MAX_BUFFER_FRAMES = 8192 };

/* ---- values ------------------------------------------------------------------------------ */

typedef struct value {
    UInt32 size;
    UInt32 item;   /* the size of one item of an array, which may be cut short; 0 for a whole value */
    union {
        unsigned char bytes[4096];
        UInt32 u32[1024];
        AudioObjectID ids[1024];
    };
} value;

static void put(value *v, const void *p, UInt32 n)
{
    memcpy(v->bytes, p, n);
    v->size = n;
    v->item = 0;
}

static void put_u32(value *v, UInt32 x)
{
    put(v, &x, 4);
}

static void put_f64(value *v, Float64 x)
{
    put(v, &x, 8);
}

static void put_f32(value *v, Float32 x)
{
    put(v, &x, 4);
}

static void put_cfstring(value *v, const char *s, int sizing)
{
    CFStringRef r = sizing ? NULL : CFStringCreateWithCString(NULL, s, kCFStringEncodingUTF8);
    put(v, &r, sizeof r);
}

static void put_cstring(value *v, const char *s)
{
    size_t n = strlen(s) + 1;
    if (n > sizeof v->bytes)
        n = sizeof v->bytes;
    memcpy(v->bytes, s, n);
    v->bytes[n - 1] = 0;
    v->size = (UInt32)n;
    v->item = 0;
}

static void put_ids(value *v, const AudioObjectID *ids, UInt32 n)
{
    memcpy(v->ids, ids, n * sizeof *ids);
    v->size = n * 4;
    v->item = 4;
}

static int scope_dir(AudioObjectPropertyScope scope)
{
    if (scope == kAudioObjectPropertyScopeInput)
        return CA_IN;
    if (scope == kAudioObjectPropertyScopeOutput)
        return CA_OUT;
    return -1;
}

/* a scope's direction on a device: global means output, or input when
 * there is no output */
static int device_dir(const ca_device *d, AudioObjectPropertyScope scope)
{
    int dir = scope_dir(scope);
    if (dir < 0)
        dir = d->stream[CA_OUT] ? CA_OUT : CA_IN;
    return dir;
}

static void stream_format(const ca_device *d, int dir, AudioStreamBasicDescription *f)
{
    ca_float_format(f, d->rate, d->channels[dir], 0);
}

static int find_cfstring(CFStringRef s, char *out, size_t size)
{
    return s && CFStringGetCString(s, out, (CFIndex)size, kCFStringEncodingUTF8);
}

static AudioObjectID device_for_uid(CFStringRef uid)
{
    char want[256];
    if (!find_cfstring(uid, want, sizeof want))
        return kAudioObjectUnknown;
    AudioObjectID ids[128], found = kAudioObjectUnknown;
    UInt32 n = ca_device_list(ids, 128);
    pthread_mutex_lock(ca_lock());
    for (UInt32 i = 0; i < n && !found; i++) {
        ca_device *d = ca_device_for(ids[i]);
        if (d && !strcmp(d->uid, want))
            found = d->id;
    }
    pthread_mutex_unlock(ca_lock());
    return found;
}

static UInt32 data_source(const ca_device *d, int dir)
{
    if (dir == CA_IN)
        return d->monitor ? 'line' : 'imic';
    return d->terminal[CA_OUT] == kAudioStreamTerminalTypeHeadphones ? 'hdpn' : 'ispk';
}

static const char *data_source_name(UInt32 id)
{
    switch (id) {
    case 'hdpn': return "Headphones";
    case 'ispk': return "Internal Speakers";
    case 'imic': return "Internal Microphone";
    case 'line': return "Line In";
    default: return NULL;
    }
}

/* ---- the system object's properties -------------------------------------------------------- */

static OSStatus system_value(const AudioObjectPropertyAddress *a, UInt32 qsize, const void *q, int sizing, value *v)
{
    switch (a->mSelector) {
    case kAudioObjectPropertyBaseClass: put_u32(v, kAudioObjectClassID); return noErr;
    case kAudioObjectPropertyClass: put_u32(v, kAudioSystemObjectClassID); return noErr;
    case kAudioObjectPropertyOwner: put_u32(v, kAudioObjectUnknown); return noErr;
    case kAudioObjectPropertyName: put_cfstring(v, "Core Audio", sizing); return noErr;
    case kAudioObjectPropertyManufacturer: put_cfstring(v, "Ferry", sizing); return noErr;
    case kAudioObjectPropertyOwnedObjects:
    case kAudioHardwarePropertyDevices: {
        AudioObjectID ids[128];
        put_ids(v, ids, ca_device_list(ids, 128));
        return noErr;
    }
    case kAudioHardwarePropertyDefaultInputDevice: put_u32(v, ca_default_device(CA_IN)); return noErr;
    case kAudioHardwarePropertyDefaultOutputDevice:
    case kAudioHardwarePropertyDefaultSystemOutputDevice: put_u32(v, ca_default_device(CA_OUT)); return noErr;
    case kAudioHardwarePropertyTranslateUIDToDevice:
        if (!sizing && (qsize < sizeof(CFStringRef) || !q))
            return kAudioHardwareBadPropertySizeError;
        put_u32(v, sizing ? 0 : device_for_uid(*(CFStringRef const *)q));
        return noErr;
    case kAudioHardwarePropertyTranslateUIDToBox:
    case kAudioHardwarePropertyTranslateUIDToClockDevice:
    case kAudioHardwarePropertyTranslateUIDToTap:
    case kAudioHardwarePropertyTranslateBundleIDToPlugIn:
    case kAudioHardwarePropertyTranslateBundleIDToTransportManager:
    case kAudioHardwarePropertyTranslatePIDToProcessObject: put_u32(v, kAudioObjectUnknown); return noErr;
    case kAudioHardwarePropertyPlugInList:
    case kAudioHardwarePropertyTransportManagerList:
    case kAudioHardwarePropertyBoxList:
    case kAudioHardwarePropertyClockDeviceList:
    case kAudioHardwarePropertyProcessObjectList:
    case kAudioHardwarePropertyTapList: put_ids(v, NULL, 0); return noErr;
    case kAudioHardwarePropertyMixStereoToMono: put_u32(v, 0); return noErr;
    case kAudioHardwarePropertyProcessIsMain:
    case kAudioHardwarePropertyProcessIsMaster: put_u32(v, 1); return noErr;
    case kAudioHardwarePropertyIsInitingOrExiting: put_u32(v, 0); return noErr;
    case kAudioHardwarePropertyUserIDChanged: put_u32(v, 0); return noErr;
    case kAudioHardwarePropertyProcessIsAudible: put_u32(v, process_audible); return noErr;
    case kAudioHardwarePropertyProcessInputMute: put_u32(v, input_muted); return noErr;
    case kAudioHardwarePropertySleepingIsAllowed: put_u32(v, sleeping_allowed); return noErr;
    case kAudioHardwarePropertyUnloadingIsAllowed: put_u32(v, unloading_allowed); return noErr;
    case kAudioHardwarePropertyHogModeIsAllowed: put_u32(v, 1); return noErr;
    case kAudioHardwarePropertyUserSessionIsActiveOrHeadless: put_u32(v, 1); return noErr;
    case kAudioHardwarePropertyServiceRestarted: put_u32(v, 0); return noErr;
    case kAudioHardwarePropertyPowerHint: put_u32(v, power_hint); return noErr;
    case kAudioHardwarePropertyRunLoop: put(v, &notify_run_loop, sizeof notify_run_loop); return noErr;
    case kAudioHardwarePropertyDeviceForUID:
    case kAudioHardwarePropertyPlugInForBundleID: {
        AudioValueTranslation t = {0};
        put(v, &t, sizeof t);
        return noErr;
    }
    default: return kAudioHardwareUnknownPropertyError;
    }
}

/* ---- a device's properties ------------------------------------------------------------------- */

/* a volume or mute control: on a sound server's device, for its main
 * element or one of its channels */
static int level_control(const ca_device *d, int dir, const AudioObjectPropertyAddress *a)
{
    if (ca_backend_is_null() || !d->stream[dir])
        return 0;
    return a->mElement == kAudioObjectPropertyElementMain || a->mElement == kAudioObjectPropertyElementWildcard ||
           a->mElement <= d->channels[dir];
}

static OSStatus device_value(ca_device *d, const AudioObjectPropertyAddress *a, UInt32 qsize, const void *q,
                             int sizing, value *v)
{
    int scoped = scope_dir(a->mScope);
    int dir = device_dir(d, a->mScope);
    int has = d->stream[dir] != 0;
    switch (a->mSelector) {
    case kAudioObjectPropertyBaseClass: put_u32(v, kAudioObjectClassID); return noErr;
    case kAudioObjectPropertyClass: put_u32(v, kAudioDeviceClassID); return noErr;
    case kAudioObjectPropertyOwner: put_u32(v, kAudioObjectSystemObject); return noErr;
    case kAudioObjectPropertyName:
    case kAudioObjectPropertyModelName: put_cfstring(v, d->name, sizing); return noErr;
    case kAudioObjectPropertyManufacturer: put_cfstring(v, d->manufacturer, sizing); return noErr;
    case kAudioDevicePropertyDeviceName: put_cstring(v, d->name); return noErr;
    case kAudioDevicePropertyDeviceManufacturer: put_cstring(v, d->manufacturer); return noErr;
    case kAudioDevicePropertyDeviceUID:
    case kAudioDevicePropertyModelUID: put_cfstring(v, d->uid, sizing); return noErr;
    case kAudioObjectPropertyElementName:
    case kAudioObjectPropertyElementCategoryName:
    case kAudioObjectPropertyElementNumberName:
    case kAudioDevicePropertyChannelName: {
        if (!has || (a->mElement > d->channels[dir] && a->mElement != kAudioObjectPropertyElementWildcard))
            return kAudioHardwareUnknownPropertyError;
        char text[64] = "";
        UInt32 e = a->mElement;
        if (a->mSelector == kAudioObjectPropertyElementNumberName)
            snprintf(text, sizeof text, "%u", (unsigned)e);
        else if (a->mSelector != kAudioObjectPropertyElementCategoryName && e >= 1 && e <= d->channels[dir]) {
            const char *n = ca_label_name(d->labels[dir][e - 1]);
            if (n)
                snprintf(text, sizeof text, "%s", n);
        }
        if (a->mSelector == kAudioDevicePropertyChannelName)
            put_cstring(v, text);
        else
            put_cfstring(v, text, sizing);
        return noErr;
    }
    case kAudioObjectPropertyOwnedObjects:
    case kAudioDevicePropertyStreams: {
        AudioObjectID ids[2];
        UInt32 n = 0;
        for (int k = 0; k < 2; k++)
            if (d->stream[k] && (scoped < 0 || scoped == k))
                ids[n++] = d->stream[k];
        put_ids(v, ids, n);
        return noErr;
    }
    case kAudioObjectPropertyControlList: put_ids(v, NULL, 0); return noErr;
    case kAudioDevicePropertyTransportType: put_u32(v, d->transport); return noErr;
    case kAudioDevicePropertyClockDomain: put_u32(v, 0); return noErr;
    case kAudioDevicePropertyRelatedDevices: put_ids(v, &d->id, 1); return noErr;
    case kAudioDevicePropertyDeviceIsAlive: put_u32(v, (UInt32)d->alive); return noErr;
    case kAudioDevicePropertyDeviceIsRunning:
    case kAudioDevicePropertyDeviceIsRunningSomewhere: put_u32(v, d->running > 0); return noErr;
    case kAudioDevicePropertyDeviceCanBeDefaultDevice: put_u32(v, has && !d->monitor); return noErr;
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        put_u32(v, d->stream[CA_OUT] && dir == CA_OUT && !d->monitor);
        return noErr;
    case kAudioDevicePropertyIsHidden: put_u32(v, 0); return noErr;
    case kAudioDevicePropertyHogMode: put(v, &d->hog, 4); return noErr;
    case kAudioDevicePropertySupportsMixing: put_u32(v, 1); return noErr;
    case kAudioDevicePropertyNominalSampleRate:
    case kAudioDevicePropertyActualSampleRate: put_f64(v, d->rate); return noErr;
    case kAudioDevicePropertyAvailableNominalSampleRates: {
        AudioValueRange r[RATE_COUNT];
        for (int i = 0; i < RATE_COUNT; i++)
            r[i].mMinimum = r[i].mMaximum = rates[i];
        put(v, r, sizeof r);
        v->item = sizeof r[0];
        return noErr;
    }
    case kAudioDevicePropertyBufferFrameSize: put_u32(v, d->buffer_frames); return noErr;
    case kAudioDevicePropertyBufferFrameSizeRange: {
        AudioValueRange r = {MIN_BUFFER_FRAMES, MAX_BUFFER_FRAMES};
        put(v, &r, sizeof r);
        return noErr;
    }
    case kAudioDevicePropertyBufferSize:
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        put_u32(v, d->buffer_frames * 4 * d->channels[dir]);
        return noErr;
    case kAudioDevicePropertyBufferSizeRange: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        AudioValueRange r = {MIN_BUFFER_FRAMES * 4.0 * d->channels[dir], MAX_BUFFER_FRAMES * 4.0 * d->channels[dir]};
        put(v, &r, sizeof r);
        return noErr;
    }
    case kAudioDevicePropertyIOCycleUsage: put_f32(v, 1.0f); return noErr;
    case kAudioDevicePropertyLatency:
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        put_u32(v, d->latency[dir]);
        return noErr;
    case kAudioDevicePropertySafetyOffset:
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        put_u32(v, 0);
        return noErr;
    case kAudioDevicePropertyStreamConfiguration: {
        UInt32 n = scoped >= 0 ? (d->stream[scoped] ? 1 : 0) : (d->stream[dir] ? 1 : 0);
        unsigned char b[sizeof(AudioBufferList)] = {0};
        AudioBufferList *l = (AudioBufferList *)b;
        l->mNumberBuffers = n;
        if (n)
            l->mBuffers[0].mNumberChannels = d->channels[dir];
        UInt32 size = (UInt32)(offsetof(AudioBufferList, mBuffers) + n * sizeof(AudioBuffer));
        put(v, b, size);
        return noErr;
    }
    case kAudioDevicePropertyPreferredChannelsForStereo: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        UInt32 pair[2] = {1, d->channels[dir] > 1 ? 2 : 1};
        put(v, pair, sizeof pair);
        return noErr;
    }
    case kAudioDevicePropertyPreferredChannelLayout: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        UInt32 size;
        AudioChannelLayout *l = ca_layout_with_labels(d->labels[dir], d->channels[dir], &size);
        put(v, l, size);
        free(l);
        return noErr;
    }
    case kAudioDevicePropertyDataSource:
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        put_u32(v, data_source(d, dir));
        return noErr;
    case kAudioDevicePropertyDataSources: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        UInt32 id = data_source(d, dir);
        put_ids(v, &id, 1);
        return noErr;
    }
    case kAudioDevicePropertyDataSourceNameForIDCFString:
    case kAudioDevicePropertyDataSourceNameForID: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        AudioValueTranslation t = {0};
        put(v, &t, sizeof t);
        return noErr;
    }
    /* the server's volume and mute, for the whole device (the main
     * element) and each channel alike; the null device has neither */
    case kAudioDevicePropertyVolumeScalar:
    case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
        if (!level_control(d, dir, a))
            return kAudioHardwareUnknownPropertyError;
        put_f32(v, d->volume[dir]);
        return noErr;
    case kAudioHardwareServiceDeviceProperty_VirtualMainBalance:
        if (!level_control(d, dir, a) || a->mElement != kAudioObjectPropertyElementMain)
            return kAudioHardwareUnknownPropertyError;
        put_f32(v, 0.5f);
        return noErr;
    case kAudioDevicePropertyVolumeDecibels:
        if (!level_control(d, dir, a))
            return kAudioHardwareUnknownPropertyError;
        put_f32(v, d->volume[dir] > 0 ? 20.0f * log10f(d->volume[dir]) : -96.0f);
        return noErr;
    case kAudioDevicePropertyVolumeRangeDecibels: {
        if (!level_control(d, dir, a))
            return kAudioHardwareUnknownPropertyError;
        AudioValueRange r = {-96, 0};
        put(v, &r, sizeof r);
        return noErr;
    }
    case kAudioDevicePropertyMute:
        if (!level_control(d, dir, a))
            return kAudioHardwareUnknownPropertyError;
        put_u32(v, d->mute[dir]);
        return noErr;
    case kAudioDevicePropertyStreamFormat: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        AudioStreamBasicDescription f;
        stream_format(d, dir, &f);
        put(v, &f, sizeof f);
        return noErr;
    }
    case kAudioDevicePropertyStreamFormats: {
        if (!has)
            return kAudioHardwareUnknownPropertyError;
        AudioStreamBasicDescription f[RATE_COUNT];
        for (int i = 0; i < RATE_COUNT; i++)
            ca_float_format(&f[i], rates[i], d->channels[dir], 0);
        put(v, f, sizeof f);
        v->item = sizeof f[0];
        return noErr;
    }
    default: return kAudioHardwareUnknownPropertyError;
    }
}

/* ---- a stream's properties -------------------------------------------------------------------- */

static OSStatus stream_value(ca_device *d, int dir, const AudioObjectPropertyAddress *a, int sizing, value *v)
{
    switch (a->mSelector) {
    case kAudioObjectPropertyBaseClass: put_u32(v, kAudioObjectClassID); return noErr;
    case kAudioObjectPropertyClass: put_u32(v, kAudioStreamClassID); return noErr;
    case kAudioObjectPropertyOwner: put_u32(v, d->id); return noErr;
    case kAudioObjectPropertyName: put_cfstring(v, d->name, sizing); return noErr;
    case kAudioObjectPropertyOwnedObjects: put_ids(v, NULL, 0); return noErr;
    case kAudioStreamPropertyIsActive: put_u32(v, 1); return noErr;
    case kAudioStreamPropertyDirection: put_u32(v, dir == CA_IN); return noErr;
    case kAudioStreamPropertyTerminalType: put_u32(v, d->terminal[dir]); return noErr;
    case kAudioStreamPropertyStartingChannel: put_u32(v, 1); return noErr;
    case kAudioStreamPropertyLatency: put_u32(v, 0); return noErr;
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat: {
        AudioStreamBasicDescription f;
        stream_format(d, dir, &f);
        put(v, &f, sizeof f);
        return noErr;
    }
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats: {
        AudioStreamRangedDescription r[RATE_COUNT];
        for (int i = 0; i < RATE_COUNT; i++) {
            ca_float_format(&r[i].mFormat, rates[i], d->channels[dir], 0);
            r[i].mSampleRateRange.mMinimum = r[i].mSampleRateRange.mMaximum = rates[i];
        }
        put(v, r, sizeof r);
        v->item = sizeof r[0];
        return noErr;
    }
    case kAudioStreamPropertyPhysicalFormats: {
        AudioStreamBasicDescription f[RATE_COUNT];
        for (int i = 0; i < RATE_COUNT; i++)
            ca_float_format(&f[i], rates[i], d->channels[dir], 0);
        put(v, f, sizeof f);
        v->item = sizeof f[0];
        return noErr;
    }
    default: return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus get_value(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize, const void *q,
                          int sizing, value *v)
{
    if (!a)
        return kAudio_ParamError;
    ca_init();
    if (obj == kAudioObjectSystemObject)
        return system_value(a, qsize, q, sizing, v);
    OSStatus err = kAudioHardwareBadObjectError;
    pthread_mutex_lock(ca_lock());
    int dir;
    ca_device *d = ca_device_for(obj);
    if (d)
        err = device_value(d, a, qsize, q, sizing, v);
    else if ((d = ca_device_for_stream(obj, &dir)))
        err = stream_value(d, dir, a, sizing, v);
    pthread_mutex_unlock(ca_lock());
    return err;
}

/* the translations that read their input from the data itself */
static OSStatus translate(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 *size, void *data,
                          int *handled)
{
    *handled = 0;
    int names = obj != kAudioObjectSystemObject && (a->mSelector == kAudioDevicePropertyDataSourceNameForIDCFString ||
                                                    a->mSelector == kAudioDevicePropertyDataSourceNameForID);
    int uid = obj == kAudioObjectSystemObject && a->mSelector == kAudioHardwarePropertyDeviceForUID;
    int bundle = obj == kAudioObjectSystemObject && a->mSelector == kAudioHardwarePropertyPlugInForBundleID;
    if (!names && !uid && !bundle)
        return noErr;
    *handled = 1;
    if (*size < sizeof(AudioValueTranslation))
        return kAudioHardwareBadPropertySizeError;
    AudioValueTranslation *t = data;
    *size = sizeof *t;
    if (uid || bundle) {
        if (t->mOutputDataSize < sizeof(AudioObjectID) || !t->mOutputData)
            return kAudioHardwareBadPropertySizeError;
        AudioObjectID id = kAudioObjectUnknown;
        if (uid && t->mInputDataSize >= sizeof(CFStringRef) && t->mInputData)
            id = device_for_uid(*(CFStringRef *)t->mInputData);
        *(AudioObjectID *)t->mOutputData = id;
        t->mOutputDataSize = sizeof id;
        return noErr;
    }
    if (t->mInputDataSize < 4 || !t->mInputData)
        return kAudioHardwareBadPropertySizeError;
    const char *name = data_source_name(*(UInt32 *)t->mInputData);
    if (!name)
        return kAudioHardwareIllegalOperationError;
    if (a->mSelector == kAudioDevicePropertyDataSourceNameForIDCFString) {
        if (t->mOutputDataSize < sizeof(CFStringRef) || !t->mOutputData)
            return kAudioHardwareBadPropertySizeError;
        *(CFStringRef *)t->mOutputData = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
        t->mOutputDataSize = sizeof(CFStringRef);
    } else {
        if (!t->mOutputData || !t->mOutputDataSize)
            return kAudioHardwareBadPropertySizeError;
        snprintf(t->mOutputData, t->mOutputDataSize, "%s", name);
        t->mOutputDataSize = (UInt32)strlen(t->mOutputData) + 1;
    }
    return noErr;
}

/* ---- AudioObject ------------------------------------------------------------------------------- */

void AudioObjectShow(AudioObjectID obj)
{
    AudioObjectPropertyAddress a = {kAudioObjectPropertyClass, kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain};
    value v;
    if (get_value(obj, &a, 0, NULL, 1, &v)) {
        fprintf(stderr, "AudioObject %u: no such object\n", (unsigned)obj);
        return;
    }
    UInt32 c = v.u32[0];
    char name[260] = "";
    ca_device *d = ca_device_for(obj);
    if (d)
        snprintf(name, sizeof name, " \"%s\"", d->name);
    fprintf(stderr, "AudioObject %u: class '%c%c%c%c'%s\n", (unsigned)obj, (char)(c >> 24), (char)(c >> 16),
            (char)(c >> 8), (char)c, name);
}

Boolean AudioObjectHasProperty(AudioObjectID obj, const AudioObjectPropertyAddress *a)
{
    value v;
    return get_value(obj, a, 0, NULL, 1, &v) == noErr;
}

OSStatus AudioObjectGetPropertyDataSize(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                        const void *q, UInt32 *size)
{
    if (!size)
        return kAudio_ParamError;
    value v;
    OSStatus err = get_value(obj, a, qsize, q, 1, &v);
    if (err == kAudioHardwareBadPropertySizeError) /* a translation sized without its qualifier */
        v.size = 4, err = noErr;
    if (!err)
        *size = v.size;
    return err;
}

OSStatus AudioObjectGetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                    const void *q, UInt32 *size, void *data)
{
    if (!size || !data || !a)
        return kAudio_ParamError;
    int handled;
    {
        value probe;
        OSStatus err = get_value(obj, a, 0, NULL, 1, &probe);
        if (err && err != kAudioHardwareBadPropertySizeError)
            return err;
    }
    OSStatus err = translate(obj, a, size, data, &handled);
    if (handled)
        return err;
    value *v = malloc(sizeof *v);
    if (!v)
        return kAudio_MemFullError;
    /* size first, so a value too big to take creates no objects */
    err = get_value(obj, a, qsize, q, 1, v);
    if (!err && !v->item && *size < v->size)
        err = kAudioHardwareBadPropertySizeError;
    if (!err)
        err = get_value(obj, a, qsize, q, 0, v);
    if (!err) {
        UInt32 n = v->size;
        if (v->item && *size < n)
            n = *size / v->item * v->item;
        memcpy(data, v->bytes, n);
        *size = n;
    }
    free(v);
    return err;
}

static OSStatus settable(AudioObjectID obj, const AudioObjectPropertyAddress *a, Boolean *out)
{
    value v;
    OSStatus err = get_value(obj, a, 0, NULL, 1, &v);
    if (err && err != kAudioHardwareBadPropertySizeError)
        return err;
    Boolean yes = 0;
    if (obj == kAudioObjectSystemObject) {
        switch (a->mSelector) {
        case kAudioHardwarePropertyDefaultInputDevice:
        case kAudioHardwarePropertyDefaultOutputDevice:
        case kAudioHardwarePropertyDefaultSystemOutputDevice:
        case kAudioHardwarePropertyRunLoop:
        case kAudioHardwarePropertySleepingIsAllowed:
        case kAudioHardwarePropertyUnloadingIsAllowed:
        case kAudioHardwarePropertyProcessIsAudible:
        case kAudioHardwarePropertyProcessInputMute:
        case kAudioHardwarePropertyPowerHint: yes = 1; break;
        }
    } else if (ca_device_for(obj)) {
        switch (a->mSelector) {
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferSize:
        case kAudioDevicePropertyHogMode:
        case kAudioDevicePropertyIOCycleUsage:
        case kAudioDevicePropertyStreamFormat:
        case kAudioDevicePropertyDataSource:
        case kAudioDevicePropertyVolumeScalar:
        case kAudioDevicePropertyVolumeDecibels:
        case kAudioDevicePropertyMute:
        case kAudioHardwareServiceDeviceProperty_VirtualMainVolume: yes = 1; break;
        }
    } else {
        switch (a->mSelector) {
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: yes = 1; break;
        }
    }
    if (out)
        *out = yes;
    return noErr;
}

OSStatus AudioObjectIsPropertySettable(AudioObjectID obj, const AudioObjectPropertyAddress *a, Boolean *out)
{
    if (!out)
        return kAudio_ParamError;
    return settable(obj, a, out);
}

static OSStatus set_rate(ca_device *d, Float64 rate)
{
    int ok = 0;
    for (int i = 0; i < RATE_COUNT; i++)
        if (fabs(rates[i] - rate) < 0.5)
            ok = 1;
    if (!ok)
        return kAudioDeviceUnsupportedFormatError;
    pthread_mutex_lock(ca_lock());
    int changed = d->rate != rate;
    d->rate = rate;
    AudioObjectID id = d->id, streams[2] = {d->stream[0], d->stream[1]};
    pthread_mutex_unlock(ca_lock());
    /* the sound server converts each program's rate to its device's own,
     * so the rate is the program's to choose */
    if (changed) {
        AudioObjectPropertyAddress a[2] = {
            {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
            {kAudioDevicePropertyActualSampleRate, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
        };
        ca_notify(id, 2, a);
        for (int k = 0; k < 2; k++)
            if (streams[k]) {
                AudioObjectPropertyAddress f[2] = {
                    {kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal,
                     kAudioObjectPropertyElementMain},
                    {kAudioStreamPropertyPhysicalFormat, kAudioObjectPropertyScopeGlobal,
                     kAudioObjectPropertyElementMain},
                };
                ca_notify(streams[k], 2, f);
            }
    }
    return noErr;
}

static OSStatus set_format(ca_device *d, int dir, UInt32 size, const void *data)
{
    if (size < sizeof(AudioStreamBasicDescription))
        return kAudioHardwareBadPropertySizeError;
    const AudioStreamBasicDescription *f = data;
    ca_pcm p;
    if (ca_pcm_parse(f, &p) || f->mChannelsPerFrame != d->channels[dir])
        return kAudioDeviceUnsupportedFormatError;
    return set_rate(d, f->mSampleRate);
}

static OSStatus set_u32(UInt32 size, const void *data, UInt32 *to)
{
    if (size < 4)
        return kAudioHardwareBadPropertySizeError;
    *to = *(const UInt32 *)data;
    return noErr;
}

OSStatus AudioObjectSetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                    const void *q, UInt32 size, const void *data)
{
    if (!a || (!data && size))
        return kAudio_ParamError;
    Boolean can = 0;
    OSStatus err = settable(obj, a, &can);
    if (err)
        return err;
    if (!can)
        return kAudioHardwareIllegalOperationError;
    if (obj == kAudioObjectSystemObject) {
        switch (a->mSelector) {
        case kAudioHardwarePropertyDefaultInputDevice:
        case kAudioHardwarePropertyDefaultOutputDevice:
        case kAudioHardwarePropertyDefaultSystemOutputDevice: {
            if (size < 4)
                return kAudioHardwareBadPropertySizeError;
            int dir = a->mSelector == kAudioHardwarePropertyDefaultInputDevice ? CA_IN : CA_OUT;
            AudioObjectID id = *(const AudioObjectID *)data;
            if (id == ca_default_device(dir))
                return noErr;
            return ca_set_default_device(dir, id);
        }
        case kAudioHardwarePropertyRunLoop:
            if (size < sizeof(CFRunLoopRef))
                return kAudioHardwareBadPropertySizeError;
            pthread_mutex_lock(ca_lock());
            notify_run_loop = *(CFRunLoopRef const *)data;
            pthread_mutex_unlock(ca_lock());
            return noErr;
        case kAudioHardwarePropertySleepingIsAllowed: err = set_u32(size, data, &sleeping_allowed); break;
        case kAudioHardwarePropertyUnloadingIsAllowed: err = set_u32(size, data, &unloading_allowed); break;
        case kAudioHardwarePropertyProcessIsAudible: err = set_u32(size, data, &process_audible); break;
        case kAudioHardwarePropertyProcessInputMute: err = set_u32(size, data, &input_muted); break;
        case kAudioHardwarePropertyPowerHint: err = set_u32(size, data, &power_hint); break;
        }
        if (!err)
            ca_notify1(obj, a->mSelector, kAudioObjectPropertyScopeGlobal);
        return err;
    }
    int dir;
    ca_device *d = ca_device_for(obj);
    if (!d) {
        d = ca_device_for_stream(obj, &dir);
        if (!d)
            return kAudioHardwareBadObjectError;
        return set_format(d, dir, size, data);
    }
    dir = device_dir(d, a->mScope);
    switch (a->mSelector) {
    case kAudioDevicePropertyNominalSampleRate:
        if (size < sizeof(Float64))
            return kAudioHardwareBadPropertySizeError;
        return set_rate(d, *(const Float64 *)data);
    case kAudioDevicePropertyStreamFormat: return set_format(d, dir, size, data);
    case kAudioDevicePropertyBufferFrameSize:
    case kAudioDevicePropertyBufferSize: {
        if (size < 4)
            return kAudioHardwareBadPropertySizeError;
        UInt32 frames = *(const UInt32 *)data;
        if (a->mSelector == kAudioDevicePropertyBufferSize)
            frames /= 4 * (d->channels[dir] ? d->channels[dir] : 1);
        if (frames < MIN_BUFFER_FRAMES || frames > MAX_BUFFER_FRAMES)
            return kAudioHardwareIllegalOperationError;
        pthread_mutex_lock(ca_lock());
        int changed = d->buffer_frames != frames;
        d->buffer_frames = frames;
        pthread_mutex_unlock(ca_lock());
        if (changed) {
            AudioObjectPropertyAddress n[2] = {
                {kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal,
                 kAudioObjectPropertyElementMain},
                {kAudioDevicePropertyBufferSize, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
            };
            ca_notify(d->id, 2, n);
        }
        return noErr;
    }
    case kAudioDevicePropertyHogMode: {
        if (size < 4)
            return kAudioHardwareBadPropertySizeError;
        /* the device is shared through the sound server whatever is
         * asked: taking it only marks it as this process's */
        SInt32 want = *(const SInt32 *)data;
        pthread_mutex_lock(ca_lock());
        d->hog = d->hog == -1 && want != -1 ? getpid() : -1;
        pthread_mutex_unlock(ca_lock());
        ca_notify1(d->id, kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal);
        return noErr;
    }
    case kAudioDevicePropertyVolumeScalar:
    case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
    case kAudioDevicePropertyVolumeDecibels: {
        if (size < sizeof(Float32))
            return kAudioHardwareBadPropertySizeError;
        Float32 x = *(const Float32 *)data;
        if (a->mSelector == kAudioDevicePropertyVolumeDecibels)
            x = x <= -96 ? 0 : powf(10, x / 20);
        return ca_set_device_level(d->id, dir, 0, x);
    }
    case kAudioDevicePropertyMute:
        if (size < 4)
            return kAudioHardwareBadPropertySizeError;
        return ca_set_device_level(d->id, dir, 1, *(const UInt32 *)data ? 1 : 0);
    case kAudioDevicePropertyIOCycleUsage: return size < 4 ? kAudioHardwareBadPropertySizeError : noErr;
    case kAudioDevicePropertyDataSource:
        if (size < 4)
            return kAudioHardwareBadPropertySizeError;
        return *(const UInt32 *)data == data_source(d, dir) ? noErr : kAudioHardwareIllegalOperationError;
    }
    return kAudioHardwareIllegalOperationError;
}

/* ---- listeners ------------------------------------------------------------------------------------ */

typedef struct listener {
    struct listener *next;
    UInt64 serial;
    AudioObjectID object;
    AudioObjectPropertyAddress address;
    AudioObjectPropertyListenerProc proc;
    void *client;
    const void *block_key; /* the block as it was added */
    AudioObjectPropertyListenerBlock block;
    dispatch_queue_t queue;
} listener;

static listener *listeners;
static UInt64 next_serial = 1;

static dispatch_queue_t notification_queue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      q = dispatch_queue_create("org.freemac.ferry.coreaudio.notifications", NULL);
    });
    return q;
}

static int matches(const AudioObjectPropertyAddress *want, const AudioObjectPropertyAddress *got)
{
    return (want->mSelector == kAudioObjectPropertySelectorWildcard ||
            got->mSelector == kAudioObjectPropertySelectorWildcard || want->mSelector == got->mSelector) &&
           (want->mScope == kAudioObjectPropertyScopeWildcard || got->mScope == kAudioObjectPropertyScopeWildcard ||
            want->mScope == got->mScope || got->mScope == kAudioObjectPropertyScopeGlobal) &&
           (want->mElement == kAudioObjectPropertyElementWildcard ||
            got->mElement == kAudioObjectPropertyElementWildcard || want->mElement == got->mElement);
}

static void deliver(UInt64 serial, AudioObjectID object, UInt32 n, AudioObjectPropertyAddress *addresses)
{
    pthread_mutex_lock(ca_lock());
    listener *l = listeners;
    while (l && l->serial != serial)
        l = l->next;
    AudioObjectPropertyListenerProc proc = l ? l->proc : NULL;
    void *client = l ? l->client : NULL;
    AudioObjectPropertyListenerBlock block = l && l->block ? Block_copy(l->block) : NULL;
    pthread_mutex_unlock(ca_lock());
    if (proc)
        proc(object, n, addresses, client);
    if (block) {
        block(n, addresses);
        Block_release(block);
    }
    free(addresses);
}

void ca_notify(AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress *changed)
{
    pthread_mutex_lock(ca_lock());
    CFRunLoopRef rl = notify_run_loop;
    for (listener *l = listeners; l; l = l->next) {
        if (l->object != object)
            continue;
        AudioObjectPropertyAddress *heard = malloc(count * sizeof *heard);
        UInt32 n = 0;
        for (UInt32 i = 0; heard && i < count; i++)
            if (matches(&l->address, &changed[i]))
                heard[n++] = changed[i];
        if (!n) {
            free(heard);
            continue;
        }
        UInt64 serial = l->serial;
        void (^job)(void) = ^{
          deliver(serial, object, n, heard);
        };
        if (l->block)
            dispatch_async(l->queue ? l->queue : notification_queue(), job);
        else if (rl) {
            CFRunLoopPerformBlock(rl, kCFRunLoopCommonModes, job);
            CFRunLoopWakeUp(rl);
        } else
            dispatch_async(notification_queue(), job);
    }
    pthread_mutex_unlock(ca_lock());
}

void ca_notify1(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = {selector, scope, kAudioObjectPropertyElementMain};
    ca_notify(object, 1, &a);
}

static int object_exists(AudioObjectID obj)
{
    ca_init();
    return obj == kAudioObjectSystemObject || ca_device_for(obj) || ca_device_for_stream(obj, NULL);
}

static OSStatus add_listener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                             AudioObjectPropertyListenerProc proc, void *client, dispatch_queue_t queue,
                             AudioObjectPropertyListenerBlock block)
{
    if (!a || (!proc && !block))
        return kAudio_ParamError;
    if (!object_exists(obj))
        return kAudioHardwareBadObjectError;
    listener *l = calloc(1, sizeof *l);
    if (!l)
        return kAudio_MemFullError;
    l->object = obj;
    l->address = *a;
    l->proc = proc;
    l->client = client;
    if (block) {
        l->block_key = (const void *)block;
        l->block = Block_copy(block);
        l->queue = queue;
        if (queue)
            dispatch_retain(queue);
    }
    pthread_mutex_lock(ca_lock());
    l->serial = next_serial++;
    l->next = listeners;
    listeners = l;
    pthread_mutex_unlock(ca_lock());
    ca_watch_server();
    return noErr;
}

static OSStatus remove_listener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                AudioObjectPropertyListenerProc proc, void *client, dispatch_queue_t queue,
                                const void *block)
{
    if (!a)
        return kAudio_ParamError;
    listener *found = NULL;
    pthread_mutex_lock(ca_lock());
    for (listener **p = &listeners; *p; p = &(*p)->next) {
        listener *l = *p;
        if (l->object == obj && !memcmp(&l->address, a, sizeof *a) &&
            (block ? l->block_key == block && l->queue == queue : (!l->block && l->proc == proc && l->client == client))) {
            *p = l->next;
            found = l;
            break;
        }
    }
    pthread_mutex_unlock(ca_lock());
    if (!found)
        return object_exists(obj) ? kAudioHardwareIllegalOperationError : kAudioHardwareBadObjectError;
    if (found->block)
        Block_release(found->block);
    if (found->queue)
        dispatch_release(found->queue);
    free(found);
    return noErr;
}

OSStatus AudioObjectAddPropertyListener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                        AudioObjectPropertyListenerProc proc, void *client)
{
    return add_listener(obj, a, proc, client, NULL, NULL);
}

OSStatus AudioObjectRemovePropertyListener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                           AudioObjectPropertyListenerProc proc, void *client)
{
    return remove_listener(obj, a, proc, client, NULL, NULL);
}

OSStatus AudioObjectAddPropertyListenerBlock(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                             dispatch_queue_t queue, AudioObjectPropertyListenerBlock block)
{
    if (!block)
        return kAudio_ParamError;
    return add_listener(obj, a, NULL, NULL, queue, block);
}

OSStatus AudioObjectRemovePropertyListenerBlock(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                                dispatch_queue_t queue, AudioObjectPropertyListenerBlock block)
{
    if (!block)
        return kAudio_ParamError;
    return remove_listener(obj, a, NULL, NULL, queue, (const void *)block);
}

OSStatus AudioHardwareUnload(void)
{
    return noErr;
}

/* ---- IO procs -------------------------------------------------------------------------------------- */

struct ca_ioproc {
    ca_ioproc *next;
    AudioDeviceIOProcID key; /* what the program calls it */
    AudioDeviceIOProc proc;
    void *client;
    AudioDeviceIOBlock block;
    dispatch_queue_t queue;
    int started;
};

static ca_ioproc *find_proc(ca_device *d, AudioDeviceIOProcID key)
{
    for (ca_ioproc *p = d->procs; p; p = p->next)
        if (p->key == key)
            return p;
    return NULL;
}

static void fill_time(AudioTimeStamp *t, Float64 sample, UInt64 host)
{
    memset(t, 0, sizeof *t);
    t->mSampleTime = sample;
    t->mHostTime = host;
    t->mRateScalar = 1.0;
    t->mFlags = kAudioTimeStampSampleHostTimeValid | kAudioTimeStampRateScalarValid;
}

static void *io_thread(void *arg)
{
    ca_device *d = arg;
    pthread_mutex_lock(ca_lock());
    Float64 rate = d->rate;
    UInt32 frames = d->buffer_frames;
    UInt32 ch[2] = {d->stream[CA_OUT] ? d->channels[CA_OUT] : 0, d->stream[CA_IN] ? d->channels[CA_IN] : 0};
    UInt32 labels[2][CA_MAX_CHANNELS];
    memcpy(labels, d->labels, sizeof labels);
    pthread_mutex_unlock(ca_lock());

    ca_stream *out = ch[CA_OUT] ? ca_stream_open(d, CA_OUT, rate, ch[CA_OUT], labels[CA_OUT], frames) : NULL;
    ca_stream *in = ch[CA_IN] ? ca_stream_open(d, CA_IN, rate, ch[CA_IN], labels[CA_IN], frames) : NULL;
    float *in_buf = calloc((size_t)frames * (ch[CA_IN] + 1), sizeof(float));
    float *out_buf = calloc((size_t)frames * (ch[CA_OUT] + 1), sizeof(float));
    float *mix = calloc((size_t)frames * (ch[CA_OUT] + 1), sizeof(float));
    AudioBufferList in_list = {1, {{ch[CA_IN], frames * 4 * ch[CA_IN], in_buf}}};
    AudioBufferList out_list;
    Float64 sample = 0;
    int failed = !out && !in;

    while (!failed) {
        pthread_mutex_lock(ca_lock());
        int stop = d->io_stop;
        ca_ioproc *procs[16];
        int n = 0;
        for (ca_ioproc *p = d->procs; p && n < 16; p = p->next)
            if (p->started)
                procs[n++] = p;
        pthread_mutex_unlock(ca_lock());
        if (stop)
            break;
        if (in && ca_stream_read(in, in_buf, frames) < 0)
            break;
        UInt64 now = ca_now();
        AudioTimeStamp t_now, t_in, t_out;
        fill_time(&t_now, sample, now);
        fill_time(&t_in, sample, now - (in ? ca_stream_latency_ns(in) : 0));
        fill_time(&t_out, sample, now + (out ? ca_stream_latency_ns(out) : 0));
        memset(mix, 0, (size_t)frames * ch[CA_OUT] * sizeof(float));
        for (int i = 0; i < n; i++) {
            ca_ioproc *p = procs[i];
            memset(out_buf, 0, (size_t)frames * ch[CA_OUT] * sizeof(float));
            out_list.mNumberBuffers = out ? 1 : 0;
            out_list.mBuffers[0].mNumberChannels = ch[CA_OUT];
            out_list.mBuffers[0].mDataByteSize = frames * 4 * ch[CA_OUT];
            out_list.mBuffers[0].mData = out ? out_buf : NULL;
            in_list.mBuffers[0].mDataByteSize = frames * 4 * ch[CA_IN];
            const AudioBufferList *il = in ? &in_list : NULL;
            AudioBufferList *ol = &out_list;
            if (p->proc)
                p->proc(d->id, &t_now, il, &t_in, ol, &t_out, p->client);
            else if (p->block) {
                AudioDeviceIOBlock b = p->block;
                if (p->queue)
                    dispatch_sync(p->queue, ^{
                      b(&t_now, il, &t_in, ol, &t_out);
                    });
                else
                    b(&t_now, il, &t_in, ol, &t_out);
            }
            for (UInt32 k = 0; k < frames * ch[CA_OUT]; k++)
                mix[k] += out_buf[k];
        }
        if (out && ca_stream_write(out, mix, frames) < 0)
            break;
        sample += frames;
        pthread_mutex_lock(ca_lock());
        d->io_sample_time = sample;
        pthread_mutex_unlock(ca_lock());
    }
    ca_stream_close(out, 0);
    ca_stream_close(in, 0);
    free(in_buf);
    free(out_buf);
    free(mix);
    pthread_mutex_lock(ca_lock());
    int bare = d->io_bare;
    d->io_started = 0;
    pthread_mutex_unlock(ca_lock());
    if (bare) /* stopped from inside an IO proc: nobody joins this thread */
        pthread_detach(pthread_self());
    return NULL;
}

static int any_started(ca_device *d)
{
    for (ca_ioproc *p = d->procs; p; p = p->next)
        if (p->started)
            return 1;
    return 0;
}

static OSStatus create_proc(AudioObjectID device, AudioDeviceIOProcID key, AudioDeviceIOProc proc, void *client,
                            dispatch_queue_t queue, AudioDeviceIOBlock block, AudioDeviceIOProcID *out)
{
    ca_device *d = ca_device_for(device);
    if (!d)
        return kAudioHardwareBadDeviceError;
    ca_ioproc *p = calloc(1, sizeof *p);
    if (!p)
        return kAudio_MemFullError;
    p->proc = proc;
    p->client = client;
    if (block) {
        p->block = Block_copy(block);
        p->queue = queue;
        if (queue)
            dispatch_retain(queue);
    }
    p->key = key ? key : (AudioDeviceIOProcID)(void *)p;
    pthread_mutex_lock(ca_lock());
    p->next = d->procs;
    d->procs = p;
    pthread_mutex_unlock(ca_lock());
    if (out)
        *out = p->key;
    return noErr;
}

OSStatus AudioDeviceCreateIOProcID(AudioObjectID device, AudioDeviceIOProc proc, void *client,
                                   AudioDeviceIOProcID *out)
{
    if (!proc || !out)
        return kAudio_ParamError;
    return create_proc(device, NULL, proc, client, NULL, NULL, out);
}

OSStatus AudioDeviceCreateIOProcIDWithBlock(AudioDeviceIOProcID *out, AudioObjectID device, dispatch_queue_t queue,
                                            AudioDeviceIOBlock block)
{
    if (!block || !out)
        return kAudio_ParamError;
    return create_proc(device, NULL, NULL, NULL, queue, block, out);
}

OSStatus AudioDeviceAddIOProc(AudioDeviceID device, AudioDeviceIOProc proc, void *client)
{
    if (!proc)
        return kAudio_ParamError;
    return create_proc(device, proc, proc, client, NULL, NULL, NULL);
}

static OSStatus stop_io(ca_device *d)
{
    pthread_mutex_lock(ca_lock());
    if (!d->io_started || any_started(d) || d->io_stop) {
        pthread_mutex_unlock(ca_lock());
        return noErr;
    }
    d->io_stop = 1;
    pthread_t t = d->io_thread;
    int inside = pthread_equal(t, pthread_self());
    if (inside)
        d->io_bare = 1;
    pthread_mutex_unlock(ca_lock());
    if (!inside)
        pthread_join(t, NULL);
    ca_notify1(d->id, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal);
    return noErr;
}

OSStatus AudioDeviceDestroyIOProcID(AudioObjectID device, AudioDeviceIOProcID key)
{
    ca_device *d = ca_device_for(device);
    if (!d)
        return kAudioHardwareBadDeviceError;
    pthread_mutex_lock(ca_lock());
    ca_ioproc *p = find_proc(d, key);
    if (!p) {
        pthread_mutex_unlock(ca_lock());
        return kAudioHardwareIllegalOperationError;
    }
    p->started = 0;
    for (ca_ioproc **q = &d->procs; *q; q = &(*q)->next)
        if (*q == p) {
            *q = p->next;
            break;
        }
    pthread_mutex_unlock(ca_lock());
    stop_io(d);
    /* an IO cycle may still hold it, so it's kept, as a few bytes */
    return noErr;
}

OSStatus AudioDeviceRemoveIOProc(AudioDeviceID device, AudioDeviceIOProc proc)
{
    return AudioDeviceDestroyIOProcID(device, proc);
}

OSStatus AudioDeviceStart(AudioObjectID device, AudioDeviceIOProcID key)
{
    ca_device *d = ca_device_for(device);
    if (!d)
        return kAudioHardwareBadDeviceError;
    pthread_mutex_lock(ca_lock());
    if (!d->alive) {
        pthread_mutex_unlock(ca_lock());
        return kAudioHardwareBadDeviceError;
    }
    if (key) {
        ca_ioproc *p = find_proc(d, key);
        if (!p) {
            pthread_mutex_unlock(ca_lock());
            return kAudioHardwareIllegalOperationError;
        }
        p->started = 1;
    }
    OSStatus err = noErr;
    if (!d->io_started) {
        d->io_started = 1;
        d->io_stop = d->io_bare = 0;
        d->io_sample_time = 0;
        if (pthread_create(&d->io_thread, NULL, io_thread, d)) {
            d->io_started = 0;
            err = kAudioHardwareUnspecifiedError;
        }
    }
    pthread_mutex_unlock(ca_lock());
    if (!err)
        ca_notify1(d->id, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal);
    return err;
}

OSStatus AudioDeviceStartAtTime(AudioObjectID device, AudioDeviceIOProcID key, AudioTimeStamp *when, UInt32 flags)
{
    OSStatus err = AudioDeviceStart(device, key);
    if (!err && when)
        fill_time(when, 0, ca_now());
    return err;
}

OSStatus AudioDeviceStop(AudioObjectID device, AudioDeviceIOProcID key)
{
    ca_device *d = ca_device_for(device);
    if (!d)
        return kAudioHardwareBadDeviceError;
    pthread_mutex_lock(ca_lock());
    if (key) {
        ca_ioproc *p = find_proc(d, key);
        if (p)
            p->started = 0;
    }
    pthread_mutex_unlock(ca_lock());
    return stop_io(d);
}

OSStatus AudioDeviceGetCurrentTime(AudioObjectID device, AudioTimeStamp *out)
{
    ca_device *d = ca_device_for(device);
    if (!d)
        return kAudioHardwareBadDeviceError;
    if (!out)
        return kAudio_ParamError;
    pthread_mutex_lock(ca_lock());
    int running = d->io_started;
    Float64 sample = d->io_sample_time;
    pthread_mutex_unlock(ca_lock());
    if (!running)
        return kAudioHardwareNotRunningError;
    fill_time(out, sample, ca_now());
    return noErr;
}

OSStatus AudioDeviceTranslateTime(AudioObjectID device, const AudioTimeStamp *in, AudioTimeStamp *out)
{
    ca_device *d = ca_device_for(device);
    if (!d)
        return kAudioHardwareBadDeviceError;
    if (!in || !out)
        return kAudio_ParamError;
    AudioTimeStamp now;
    OSStatus err = AudioDeviceGetCurrentTime(device, &now);
    if (err)
        return err;
    UInt32 want = out->mFlags ? out->mFlags : kAudioTimeStampSampleHostTimeValid;
    Float64 sample;
    UInt64 host;
    if (in->mFlags & kAudioTimeStampSampleTimeValid) {
        sample = in->mSampleTime;
        host = now.mHostTime + (SInt64)((sample - now.mSampleTime) * 1e9 / d->rate);
    } else if (in->mFlags & kAudioTimeStampHostTimeValid) {
        host = in->mHostTime;
        sample = now.mSampleTime + ((double)host - (double)now.mHostTime) * d->rate / 1e9;
    } else
        return kAudio_ParamError;
    fill_time(out, sample, host);
    out->mFlags &= want | kAudioTimeStampSampleHostTimeValid | kAudioTimeStampRateScalarValid;
    return noErr;
}

OSStatus AudioDeviceGetNearestStartTime(AudioObjectID device, AudioTimeStamp *when, UInt32 flags)
{
    if (!ca_device_for(device))
        return kAudioHardwareBadDeviceError;
    if (!when)
        return kAudio_ParamError;
    AudioTimeStamp now;
    if (AudioDeviceGetCurrentTime(device, &now))
        fill_time(when, 0, ca_now());
    else
        *when = now;
    return noErr;
}

/* ---- the older calls ----------------------------------------------------------------------------- */

static AudioObjectPropertyAddress older(AudioObjectPropertySelector sel, Boolean input, UInt32 channel)
{
    AudioObjectPropertyAddress a = {sel, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
                                    channel};
    return a;
}

OSStatus AudioHardwareGetPropertyInfo(AudioHardwarePropertyID id, UInt32 *size, Boolean *writable)
{
    AudioObjectPropertyAddress a = {id, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    OSStatus err = size ? AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, size) : noErr;
    if (!err && writable)
        err = AudioObjectIsPropertySettable(kAudioObjectSystemObject, &a, writable);
    return err;
}

OSStatus AudioHardwareGetProperty(AudioHardwarePropertyID id, UInt32 *size, void *data)
{
    AudioObjectPropertyAddress a = {id, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, size, data);
}

OSStatus AudioHardwareSetProperty(AudioHardwarePropertyID id, UInt32 size, const void *data)
{
    AudioObjectPropertyAddress a = {id, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, size, data);
}

OSStatus AudioDeviceGetPropertyInfo(AudioDeviceID device, UInt32 channel, Boolean input, AudioDevicePropertyID id,
                                    UInt32 *size, Boolean *writable)
{
    AudioObjectPropertyAddress a = older(id, input, channel);
    OSStatus err = size ? AudioObjectGetPropertyDataSize(device, &a, 0, NULL, size) : noErr;
    if (!err && writable)
        err = AudioObjectIsPropertySettable(device, &a, writable);
    return err;
}

OSStatus AudioDeviceGetProperty(AudioDeviceID device, UInt32 channel, Boolean input, AudioDevicePropertyID id,
                                UInt32 *size, void *data)
{
    AudioObjectPropertyAddress a = older(id, input, channel);
    return AudioObjectGetPropertyData(device, &a, 0, NULL, size, data);
}

OSStatus AudioDeviceSetProperty(AudioDeviceID device, const AudioTimeStamp *when, UInt32 channel, Boolean input,
                                AudioDevicePropertyID id, UInt32 size, const void *data)
{
    AudioObjectPropertyAddress a = older(id, input, channel);
    return AudioObjectSetPropertyData(device, &a, 0, NULL, size, data);
}

/* ---- Audio Hardware Services: the same properties, as AudioToolbox offers them ------------- */

Boolean AudioHardwareServiceHasProperty(AudioObjectID obj, const AudioObjectPropertyAddress *a)
{
    return AudioObjectHasProperty(obj, a);
}

OSStatus AudioHardwareServiceIsPropertySettable(AudioObjectID obj, const AudioObjectPropertyAddress *a, Boolean *out)
{
    return AudioObjectIsPropertySettable(obj, a, out);
}

OSStatus AudioHardwareServiceGetPropertyDataSize(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                                 const void *q, UInt32 *size)
{
    return AudioObjectGetPropertyDataSize(obj, a, qsize, q, size);
}

OSStatus AudioHardwareServiceGetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                             const void *q, UInt32 *size, void *data)
{
    return AudioObjectGetPropertyData(obj, a, qsize, q, size, data);
}

OSStatus AudioHardwareServiceSetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qsize,
                                             const void *q, UInt32 size, const void *data)
{
    return AudioObjectSetPropertyData(obj, a, qsize, q, size, data);
}

OSStatus AudioHardwareServiceAddPropertyListener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                                 AudioObjectPropertyListenerProc proc, void *client)
{
    return AudioObjectAddPropertyListener(obj, a, proc, client);
}

OSStatus AudioHardwareServiceRemovePropertyListener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                                    AudioObjectPropertyListenerProc proc, void *client)
{
    return AudioObjectRemovePropertyListener(obj, a, proc, client);
}
