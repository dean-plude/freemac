/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Audio components and the output audio units (freemac 1.234, Ferry
 * 0.58.0), written from Apple's public documentation of AudioComponent.h,
 * AUComponent.h, AudioOutputUnit.h and AudioUnitProperties.h.
 *
 * Ferry has Apple's four output units: HAL output ("AUHAL"), which plays to
 * and records from one device; default and system output, which play to the
 * default output device and follow it when it changes; and generic output,
 * which has no device and renders only when the program pulls on it with
 * AudioUnitRender. Components that a program registers with
 * AudioComponentRegister are found and called through their factory.
 *
 * Bus 0 is the output bus: the program gives it samples through a render
 * callback, in the input scope's format, and it plays them. Bus 1 is the
 * input bus (HAL output only, when input is enabled): it records, calls the
 * input callback, and the program takes the samples with AudioUnitRender,
 * in the output scope's format.
 */
#import "CAInternal.h"
#include <Block.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { KIND_HAL, KIND_DEFAULT, KIND_SYSTEM, KIND_GENERIC, KIND_PLUGIN };

struct OpaqueAudioComponent {
    AudioComponentDescription desc;
    char name[128];
    UInt32 version;
    int kind;
    AudioComponentFactoryFunction factory;
    struct OpaqueAudioComponent *next;
};

static struct OpaqueAudioComponent builtin[] = {
    {{kAudioUnitType_Output, kAudioUnitSubType_HALOutput, kAudioUnitManufacturer_Apple, 0, 0},
     "Apple: AudioDeviceOutput", 0x10000, KIND_HAL, NULL, NULL},
    {{kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0},
     "Apple: DefaultOutputUnit", 0x10000, KIND_DEFAULT, NULL, NULL},
    {{kAudioUnitType_Output, kAudioUnitSubType_SystemOutput, kAudioUnitManufacturer_Apple, 0, 0},
     "Apple: SystemOutputUnit", 0x10000, KIND_SYSTEM, NULL, NULL},
    {{kAudioUnitType_Output, kAudioUnitSubType_GenericOutput, kAudioUnitManufacturer_Apple, 0, 0},
     "Apple: GenericOutput", 0x10000, KIND_GENERIC, NULL, NULL},
};
enum { BUILTIN_COUNT = sizeof builtin / sizeof builtin[0] };

static pthread_mutex_t registry_lock = PTHREAD_MUTEX_INITIALIZER;
static struct OpaqueAudioComponent *registered, **registered_tail = &registered;

/* the selectors of the calls on an audio unit, as plug-ins look them up */
enum {
    SEL_INITIALIZE = 0x0001,
    SEL_UNINITIALIZE = 0x0002,
    SEL_GET_PROPERTY_INFO = 0x0003,
    SEL_GET_PROPERTY = 0x0004,
    SEL_SET_PROPERTY = 0x0005,
    SEL_GET_PARAMETER = 0x0006,
    SEL_SET_PARAMETER = 0x0007,
    SEL_RESET = 0x0009,
    SEL_ADD_PROPERTY_LISTENER = 0x000A,
    SEL_REMOVE_PROPERTY_LISTENER = 0x000B,
    SEL_RENDER = 0x000E,
    SEL_ADD_RENDER_NOTIFY = 0x000F,
    SEL_REMOVE_RENDER_NOTIFY = 0x0010,
    SEL_SCHEDULE_PARAMETERS = 0x0011,
    SEL_REMOVE_PROPERTY_LISTENER_WITH_USER_DATA = 0x0012,
    SEL_PROCESS = 0x0014,
};

/* ---- components ---------------------------------------------------------------------------- */

static int describes(const AudioComponentDescription *want, const AudioComponentDescription *have)
{
    if (!want)
        return 1;
    return (!want->componentType || want->componentType == have->componentType) &&
           (!want->componentSubType || want->componentSubType == have->componentSubType) &&
           (!want->componentManufacturer || want->componentManufacturer == have->componentManufacturer) &&
           ((have->componentFlags & want->componentFlagsMask) == (want->componentFlags & want->componentFlagsMask));
}

static AudioComponent component_after(AudioComponent c)
{
    if (!c)
        return &builtin[0];
    if (c >= &builtin[0] && c < &builtin[BUILTIN_COUNT - 1])
        return c + 1;
    if (c == &builtin[BUILTIN_COUNT - 1])
        return registered;
    return c->next;
}

AudioComponent AudioComponentFindNext(AudioComponent after, const AudioComponentDescription *desc)
{
    pthread_mutex_lock(&registry_lock);
    AudioComponent c = component_after(after);
    while (c && (!describes(desc, &c->desc) || (c->desc.componentFlags & kAudioComponentFlag_Unsearchable)))
        c = component_after(c);
    pthread_mutex_unlock(&registry_lock);
    return c;
}

UInt32 AudioComponentCount(const AudioComponentDescription *desc)
{
    UInt32 n = 0;
    for (AudioComponent c = AudioComponentFindNext(NULL, desc); c; c = AudioComponentFindNext(c, desc))
        n++;
    return n;
}

OSStatus AudioComponentCopyName(AudioComponent c, CFStringRef *out)
{
    if (!c || !out)
        return kAudio_ParamError;
    *out = CFStringCreateWithCString(NULL, c->name, kCFStringEncodingUTF8);
    return noErr;
}

OSStatus AudioComponentGetDescription(AudioComponent c, AudioComponentDescription *out)
{
    if (!c || !out)
        return kAudio_ParamError;
    *out = c->desc;
    return noErr;
}

OSStatus AudioComponentGetVersion(AudioComponent c, UInt32 *out)
{
    if (!c || !out)
        return kAudio_ParamError;
    *out = c->version;
    return noErr;
}

AudioComponent AudioComponentRegister(const AudioComponentDescription *desc, CFStringRef name, UInt32 version,
                                      AudioComponentFactoryFunction factory)
{
    if (!desc || !factory)
        return NULL;
    struct OpaqueAudioComponent *c = calloc(1, sizeof *c);
    if (!c)
        return NULL;
    c->desc = *desc;
    if (!name || !CFStringGetCString(name, c->name, sizeof c->name, kCFStringEncodingUTF8))
        snprintf(c->name, sizeof c->name, "Audio Unit");
    c->version = version;
    c->kind = KIND_PLUGIN;
    c->factory = factory;
    pthread_mutex_lock(&registry_lock);
    *registered_tail = c;
    registered_tail = &c->next;
    pthread_mutex_unlock(&registry_lock);
    return c;
}

/* ---- the units ---------------------------------------------------------------------------- */

typedef struct unit_listener {
    struct unit_listener *next;
    AudioUnitPropertyID id;
    AudioUnitPropertyListenerProc proc;
    void *ref;
} unit_listener;

typedef struct render_notify {
    struct render_notify *next;
    AURenderCallback proc;
    void *ref;
} render_notify;

struct ComponentInstanceRecord {
    AudioComponent component;
    AudioComponentPlugInInterface *plugin;
    int kind;
    pthread_mutex_t lock;
    int initialized, running;
    AudioObjectID device; /* 0: the default device */
    UInt32 enable[2];     /* [CA_OUT]: bus 0 plays; [CA_IN]: bus 1 records */
    AudioStreamBasicDescription client[2]; /* the input scope of bus 0, the output scope of bus 1 */
    int client_set[2];
    AudioStreamBasicDescription generic_out; /* generic output's output scope */
    int generic_out_set;
    AURenderCallbackStruct render, input;
    UInt32 max_frames;
    SInt32 *map[2];
    UInt32 map_count[2];
    AudioChannelLayout *layout[2];
    UInt32 layout_size[2];
    Float32 volume;
    UInt32 should_allocate, start_at_zero;
    UInt32 render_quality; /* kept for the program; samples move unchanged */
    OSStatus last_error;
    unit_listener *listeners;
    render_notify *notifies;
    pthread_t thread;
    int stop, thread_bare, watching;
    volatile int reopen;
    /* what bus 1 last recorded, interleaved: the device's channels when
     * there's a channel map, else the client's */
    float *capture;
    UInt32 capture_frames, capture_cap, capture_channels;
    AudioTimeStamp capture_time;
    void *own[CA_MAX_CHANNELS]; /* bus 1's buffers, for a program that gives none */
    UInt32 own_bytes;
};

static int has_device(AudioUnit u)
{
    return u->kind == KIND_HAL || u->kind == KIND_DEFAULT || u->kind == KIND_SYSTEM;
}

static AudioObjectID unit_device(AudioUnit u)
{
    if (u->kind == KIND_HAL && u->device)
        return u->device;
    if (u->kind == KIND_HAL && u->enable[CA_IN] && !u->enable[CA_OUT])
        return ca_default_device(CA_IN);
    return has_device(u) ? ca_default_device(CA_OUT) : 0;
}

/* the format a bus has on its device's side */
static void device_side(AudioUnit u, int dir, AudioStreamBasicDescription *f)
{
    ca_device *d = ca_device_for(unit_device(u));
    pthread_mutex_lock(ca_lock());
    Float64 rate = d ? d->rate : 48000;
    UInt32 channels = d && d->stream[dir] ? d->channels[dir] : 0;
    pthread_mutex_unlock(ca_lock());
    if (!has_device(u)) /* generic output: as its client side */
        channels = 2;
    ca_float_format(f, rate, channels, 0);
}

static void client_side(AudioUnit u, int dir, AudioStreamBasicDescription *f)
{
    if (u->client_set[dir]) {
        *f = u->client[dir];
        return;
    }
    AudioStreamBasicDescription dev;
    device_side(u, dir, &dev);
    UInt32 channels = dev.mChannelsPerFrame ? dev.mChannelsPerFrame : 2;
    ca_float_format(f, dev.mSampleRate, channels, 1);
}

static void listen_unit(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el)
{
    unit_listener *ls[32];
    int n = 0;
    pthread_mutex_lock(&u->lock);
    for (unit_listener *l = u->listeners; l && n < 32; l = l->next)
        if (l->id == id)
            ls[n++] = l;
    pthread_mutex_unlock(&u->lock);
    for (int i = 0; i < n; i++)
        ls[i]->proc(ls[i]->ref, u, id, scope, el);
}

static OSStatus default_changed(AudioObjectID obj, UInt32 n, const AudioObjectPropertyAddress *a, void *client)
{
    AudioUnit u = client;
    pthread_mutex_lock(&u->lock);
    int follows = has_device(u) && !(u->kind == KIND_HAL && u->device);
    if (follows)
        u->reopen = 1;
    pthread_mutex_unlock(&u->lock);
    if (follows) {
        listen_unit(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0);
        listen_unit(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0);
        listen_unit(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1);
    }
    return noErr;
}

static const AudioObjectPropertyAddress default_addresses[2] = {
    {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    {kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
};

OSStatus AudioComponentInstanceNew(AudioComponent c, AudioComponentInstance *out)
{
    if (!c || !out)
        return kAudio_ParamError;
    *out = NULL;
    AudioUnit u = calloc(1, sizeof *u);
    if (!u)
        return kAudio_MemFullError;
    u->component = c;
    u->kind = c->kind;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&u->lock, &attr);
    pthread_mutexattr_destroy(&attr);
    if (c->kind == KIND_PLUGIN) {
        u->plugin = c->factory(&c->desc);
        if (!u->plugin || (u->plugin->Open && u->plugin->Open(u->plugin, u))) {
            pthread_mutex_destroy(&u->lock);
            free(u);
            return kAudioComponentErr_InstanceInvalidated;
        }
        *out = u;
        return noErr;
    }
    ca_init();
    u->enable[CA_OUT] = 1;
    u->enable[CA_IN] = 0;
    u->max_frames = 4096;
    u->volume = 1.0f;
    u->should_allocate = 1;
    u->start_at_zero = 1;
    u->render_quality = 0x7F; /* kRenderQuality_Max */
    if (has_device(u)) {
        for (int i = 0; i < 2; i++)
            AudioObjectAddPropertyListener(kAudioObjectSystemObject, &default_addresses[i], default_changed, u);
        u->watching = 1;
    }
    *out = u;
    return noErr;
}

void AudioComponentInstantiate(AudioComponent c, AudioComponentInstantiationOptions options,
                               void (^done)(AudioComponentInstance, OSStatus))
{
    if (!done)
        return;
    void (^handler)(AudioComponentInstance, OSStatus) = Block_copy(done);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
      AudioComponentInstance u = NULL;
      OSStatus err = AudioComponentInstanceNew(c, &u);
      handler(u, err);
      Block_release(handler);
    });
}

AudioComponent AudioComponentInstanceGetComponent(AudioComponentInstance u)
{
    return u ? u->component : NULL;
}

static AudioComponentMethod plugin_method(AudioUnit u, SInt16 selector)
{
    return u->plugin && u->plugin->Lookup ? u->plugin->Lookup(selector) : NULL;
}

/* a plug-in unit's own method for a call that only plug-ins have, such as a
 * music device's (CAMusicDevice.m), and the plug-in to call it on; NULL for
 * Ferry's own output units */
AudioComponentMethod ca_unit_method(AudioUnit u, SInt16 selector, void **plugin)
{
    if (!u || !u->plugin)
        return NULL;
    *plugin = u->plugin;
    return plugin_method(u, selector);
}

Boolean AudioComponentInstanceCanDo(AudioComponentInstance u, SInt16 selector)
{
    if (!u)
        return 0;
    if (u->plugin)
        return plugin_method(u, selector) != NULL;
    switch (selector) {
    case SEL_INITIALIZE:
    case SEL_UNINITIALIZE:
    case SEL_GET_PROPERTY_INFO:
    case SEL_GET_PROPERTY:
    case SEL_SET_PROPERTY:
    case SEL_GET_PARAMETER:
    case SEL_SET_PARAMETER:
    case SEL_RESET:
    case SEL_ADD_PROPERTY_LISTENER:
    case SEL_REMOVE_PROPERTY_LISTENER:
    case SEL_RENDER:
    case SEL_ADD_RENDER_NOTIFY:
    case SEL_REMOVE_RENDER_NOTIFY:
    case SEL_SCHEDULE_PARAMETERS:
    case SEL_REMOVE_PROPERTY_LISTENER_WITH_USER_DATA:
    case kAudioOutputUnitStartSelect:
    case kAudioOutputUnitStopSelect: return 1;
    default: return 0;
    }
}

/* calls a plug-in's method, as its own type */
#define PLUGIN_CALL(u, sel, type, ...)                                                                                \
    do {                                                                                                              \
        AudioComponentMethod m_ = plugin_method(u, sel);                                                              \
        if (!m_)                                                                                                      \
            return kAudio_UnimplementedError;                                                                         \
        return ((type)(void *)m_)(u->plugin, ##__VA_ARGS__);                                                          \
    } while (0)

/* ---- running ----------------------------------------------------------------------------------- */

static void labels_for(AudioUnit u, int dir, UInt32 channels, UInt32 *labels)
{
    UInt32 n = u->layout[dir] ? ca_layout_labels(u->layout[dir], u->layout_size[dir], labels, CA_MAX_CHANNELS) : 0;
    if (n != channels)
        ca_default_labels(channels, labels);
}

static AudioBufferList *new_list(const ca_pcm *p, UInt32 frames)
{
    UInt32 buffers = p->non_interleaved ? p->channels : 1;
    AudioBufferList *l = calloc(1, offsetof(AudioBufferList, mBuffers) + buffers * sizeof(AudioBuffer));
    l->mNumberBuffers = buffers;
    for (UInt32 i = 0; i < buffers; i++) {
        l->mBuffers[i].mNumberChannels = p->non_interleaved ? 1 : p->channels;
        l->mBuffers[i].mDataByteSize = frames * p->bytes_per_frame;
        l->mBuffers[i].mData = calloc(frames, p->bytes_per_frame);
    }
    return l;
}

static void free_list(AudioBufferList *l)
{
    if (!l)
        return;
    for (UInt32 i = 0; i < l->mNumberBuffers; i++)
        free(l->mBuffers[i].mData);
    free(l);
}

static void reset_list(AudioBufferList *l, const ca_pcm *p, UInt32 frames, void **data)
{
    for (UInt32 i = 0; i < l->mNumberBuffers; i++) {
        l->mBuffers[i].mDataByteSize = frames * p->bytes_per_frame;
        l->mBuffers[i].mData = data[i];
        l->mBuffers[i].mNumberChannels = p->non_interleaved ? 1 : p->channels;
    }
}

static void call_notifies(AudioUnit u, AudioUnitRenderActionFlags flags, const AudioTimeStamp *t, UInt32 bus,
                          UInt32 frames, AudioBufferList *l)
{
    render_notify *ns[16];
    int n = 0;
    pthread_mutex_lock(&u->lock);
    for (render_notify *r = u->notifies; r && n < 16; r = r->next)
        ns[n++] = r;
    pthread_mutex_unlock(&u->lock);
    for (int i = 0; i < n; i++) {
        AudioUnitRenderActionFlags f = flags;
        ns[i]->proc(ns[i]->ref, &f, t, bus, frames, l);
    }
}

static void fill_time(AudioTimeStamp *t, Float64 sample, UInt64 host)
{
    memset(t, 0, sizeof *t);
    t->mSampleTime = sample;
    t->mHostTime = host;
    t->mRateScalar = 1.0;
    t->mFlags = kAudioTimeStampSampleHostTimeValid | kAudioTimeStampRateScalarValid;
}

typedef struct running {
    ca_device *device;
    ca_stream *out, *in;
    UInt32 out_frames, in_frames;
    UInt32 out_channels, in_channels; /* the streams' */
    ca_pcm out_pcm;
    AudioStreamBasicDescription out_format;
    AudioBufferList *out_list;
    void *out_data[CA_MAX_CHANNELS];
    float *client, *device_frames, *in_buf;
    SInt32 out_map[CA_MAX_CHANNELS];
    UInt32 out_map_count;
} running;

static void close_running(running *r)
{
    ca_stream_close(r->out, 0);
    ca_stream_close(r->in, 0);
    if (r->out_list) {
        reset_list(r->out_list, &r->out_pcm, 0, r->out_data);
        free_list(r->out_list);
    }
    free(r->client);
    free(r->device_frames);
    free(r->in_buf);
    memset(r, 0, sizeof *r);
}

static void open_running(AudioUnit u, running *r)
{
    memset(r, 0, sizeof *r);
    pthread_mutex_lock(&u->lock);
    AudioObjectID id = unit_device(u);
    ca_device *d = ca_device_for(id);
    r->device = d;
    if (!d) {
        pthread_mutex_unlock(&u->lock);
        return;
    }
    pthread_mutex_lock(ca_lock());
    int alive = d->alive;
    Float64 drate = d->rate;
    UInt32 dframes = d->buffer_frames, dch[2] = {d->stream[CA_OUT] ? d->channels[CA_OUT] : 0,
                                                 d->stream[CA_IN] ? d->channels[CA_IN] : 0};
    UInt32 dlabels[2][CA_MAX_CHANNELS];
    memcpy(dlabels, d->labels, sizeof dlabels);
    pthread_mutex_unlock(ca_lock());
    int play = alive && u->enable[CA_OUT] && dch[CA_OUT];
    int record = alive && u->kind == KIND_HAL && u->enable[CA_IN] && dch[CA_IN];
    AudioStreamBasicDescription fo, fi;
    client_side(u, CA_OUT, &fo);
    client_side(u, CA_IN, &fi);
    UInt32 out_labels[CA_MAX_CHANNELS], in_labels[CA_MAX_CHANNELS];
    if (play) {
        ca_pcm_parse(&fo, &r->out_pcm);
        r->out_format = fo;
        Float64 rate = fo.mSampleRate > 0 ? fo.mSampleRate : drate;
        r->out_frames = (UInt32)lround(dframes * rate / drate);
        if (r->out_frames < 16)
            r->out_frames = 16;
        if (r->out_frames > u->max_frames)
            r->out_frames = u->max_frames;
        if (u->map[CA_OUT]) {
            r->out_channels = dch[CA_OUT];
            memcpy(out_labels, dlabels[CA_OUT], sizeof out_labels);
            r->out_map_count = u->map_count[CA_OUT] < CA_MAX_CHANNELS ? u->map_count[CA_OUT] : CA_MAX_CHANNELS;
            memcpy(r->out_map, u->map[CA_OUT], r->out_map_count * sizeof(SInt32));
        } else {
            r->out_channels = fo.mChannelsPerFrame;
            labels_for(u, CA_OUT, r->out_channels, out_labels);
        }
        r->out_list = new_list(&r->out_pcm, r->out_frames);
        for (UInt32 i = 0; i < r->out_list->mNumberBuffers; i++)
            r->out_data[i] = r->out_list->mBuffers[i].mData;
        r->client = calloc((size_t)r->out_frames * fo.mChannelsPerFrame, sizeof(float));
        r->device_frames = calloc((size_t)r->out_frames * r->out_channels, sizeof(float));
        r->out = ca_stream_open(d, CA_OUT, rate, r->out_channels, out_labels, r->out_frames);
    }
    if (record) {
        Float64 rate = fi.mSampleRate > 0 ? fi.mSampleRate : drate;
        r->in_frames = (UInt32)lround(dframes * rate / drate);
        if (r->in_frames < 16)
            r->in_frames = 16;
        if (r->in_frames > u->max_frames)
            r->in_frames = u->max_frames;
        if (u->map[CA_IN]) {
            r->in_channels = dch[CA_IN];
            memcpy(in_labels, dlabels[CA_IN], sizeof in_labels);
        } else {
            r->in_channels = fi.mChannelsPerFrame;
            labels_for(u, CA_IN, r->in_channels, in_labels);
        }
        r->in_buf = calloc((size_t)r->in_frames * r->in_channels, sizeof(float));
        r->in = ca_stream_open(d, CA_IN, rate, r->in_channels, in_labels, r->in_frames);
    }
    u->reopen = 0;
    pthread_mutex_unlock(&u->lock);
}

static void *render_thread(void *arg)
{
    AudioUnit u = arg;
    running r;
    open_running(u, &r);
    Float64 sample[2] = {0, 0};
    for (;;) {
        pthread_mutex_lock(&u->lock);
        int stop = u->stop, reopen = u->reopen;
        AURenderCallbackStruct render = u->render, input = u->input;
        Float32 volume = u->volume;
        pthread_mutex_unlock(&u->lock);
        if (stop)
            break;
        if (reopen || (!r.out && !r.in)) {
            if (!reopen)
                ca_sleep_ns(200000000); /* nothing to play or record: wait for a device */
            close_running(&r);
            open_running(u, &r);
            continue;
        }
        if (r.in) {
            if (ca_stream_read(r.in, r.in_buf, r.in_frames) < 0) {
                u->reopen = 1;
                ca_sleep_ns(100000000);
                continue;
            }
            UInt64 now = ca_now();
            AudioTimeStamp t;
            fill_time(&t, sample[CA_IN], now - ca_stream_latency_ns(r.in));
            pthread_mutex_lock(&u->lock);
            if (u->capture_cap < r.in_frames * r.in_channels) {
                free(u->capture);
                u->capture = calloc((size_t)r.in_frames * r.in_channels, sizeof(float));
                u->capture_cap = u->capture ? r.in_frames * r.in_channels : 0;
            }
            if (u->capture) {
                memcpy(u->capture, r.in_buf, (size_t)r.in_frames * r.in_channels * sizeof(float));
                u->capture_frames = r.in_frames;
                u->capture_channels = r.in_channels;
                u->capture_time = t;
            }
            pthread_mutex_unlock(&u->lock);
            if (input.inputProc) {
                AudioUnitRenderActionFlags flags = 0;
                input.inputProc(input.inputProcRefCon, &flags, &t, 1, r.in_frames, NULL);
            }
            sample[CA_IN] += r.in_frames;
        }
        if (r.out) {
            UInt32 n = r.out_frames, cch = r.out_format.mChannelsPerFrame;
            AudioTimeStamp t;
            fill_time(&t, sample[CA_OUT], ca_now() + ca_stream_latency_ns(r.out));
            reset_list(r.out_list, &r.out_pcm, n, r.out_data);
            call_notifies(u, kAudioUnitRenderAction_PreRender, &t, 0, n, r.out_list);
            AudioUnitRenderActionFlags flags = 0;
            OSStatus err = noErr;
            if (render.inputProc)
                err = render.inputProc(render.inputProcRefCon, &flags, &t, 0, n, r.out_list);
            else
                flags |= kAudioUnitRenderAction_OutputIsSilence;
            call_notifies(u, kAudioUnitRenderAction_PostRender | (err ? kAudioUnitRenderAction_PostRenderError : 0),
                          &t, 0, n, r.out_list);
            if (err) {
                pthread_mutex_lock(&u->lock);
                u->last_error = err;
                pthread_mutex_unlock(&u->lock);
            }
            if (err || (flags & kAudioUnitRenderAction_OutputIsSilence))
                memset(r.client, 0, (size_t)n * cch * sizeof(float));
            else
                ca_pcm_to_float(&r.out_pcm, r.out_list, n, r.client);
            const float *play = r.client;
            if (volume != 1.0f)
                for (UInt32 i = 0; i < n * cch; i++)
                    r.client[i] *= volume;
            if (r.out_map_count || r.out_channels != cch) {
                for (UInt32 f = 0; f < n; f++)
                    for (UInt32 c = 0; c < r.out_channels; c++) {
                        SInt32 from = r.out_map_count ? (c < r.out_map_count ? r.out_map[c] : -1) : (SInt32)c;
                        r.device_frames[(size_t)f * r.out_channels + c] =
                            from >= 0 && (UInt32)from < cch ? r.client[(size_t)f * cch + (UInt32)from] : 0.0f;
                    }
                play = r.device_frames;
            }
            if (ca_stream_write(r.out, play, n) < 0) {
                u->reopen = 1;
                ca_sleep_ns(100000000);
                continue;
            }
            sample[CA_OUT] += n;
        }
    }
    close_running(&r);
    pthread_mutex_lock(&u->lock);
    int bare = u->thread_bare;
    u->running = 0;
    pthread_mutex_unlock(&u->lock);
    if (bare)
        pthread_detach(pthread_self());
    return NULL;
}

/* ---- calls on a unit ------------------------------------------------------------------------- */

OSStatus AudioUnitInitialize(AudioUnit u)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_INITIALIZE, OSStatus (*)(void *));
    pthread_mutex_lock(&u->lock);
    OSStatus err = noErr;
    if (u->kind == KIND_HAL && !u->enable[CA_OUT] && !u->enable[CA_IN])
        err = kAudioUnitErr_FailedInitialization;
    else if (u->kind == KIND_HAL && u->device && !ca_device_for(u->device))
        err = kAudioUnitErr_FailedInitialization;
    else
        u->initialized = 1;
    pthread_mutex_unlock(&u->lock);
    return err;
}

OSStatus AudioUnitUninitialize(AudioUnit u)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_UNINITIALIZE, OSStatus (*)(void *));
    AudioOutputUnitStop(u);
    pthread_mutex_lock(&u->lock);
    u->initialized = 0;
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

OSStatus AudioOutputUnitStart(AudioUnit u)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, kAudioOutputUnitStartSelect, OSStatus (*)(void *));
    if (!u->initialized) {
        OSStatus err = AudioUnitInitialize(u);
        if (err)
            return err;
    }
    if (u->kind == KIND_GENERIC)
        return noErr; /* it renders when the program pulls */
    pthread_mutex_lock(&u->lock);
    if (u->running) {
        pthread_mutex_unlock(&u->lock);
        return noErr;
    }
    u->stop = u->thread_bare = 0;
    u->running = 1;
    u->capture_frames = 0;
    int err = pthread_create(&u->thread, NULL, render_thread, u);
    if (err)
        u->running = 0;
    pthread_mutex_unlock(&u->lock);
    if (err)
        return kAudioUnitErr_FailedInitialization;
    listen_unit(u, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0);
    return noErr;
}

OSStatus AudioOutputUnitStop(AudioUnit u)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, kAudioOutputUnitStopSelect, OSStatus (*)(void *));
    pthread_mutex_lock(&u->lock);
    if (!u->running || u->stop) {
        pthread_mutex_unlock(&u->lock);
        return noErr;
    }
    u->stop = 1;
    pthread_t t = u->thread;
    int inside = pthread_equal(t, pthread_self());
    if (inside)
        u->thread_bare = 1;
    pthread_mutex_unlock(&u->lock);
    if (!inside)
        pthread_join(t, NULL);
    listen_unit(u, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0);
    return noErr;
}

OSStatus AudioComponentInstanceDispose(AudioComponentInstance u)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin) {
        if (u->plugin->Close)
            u->plugin->Close(u->plugin);
    } else {
        AudioOutputUnitStop(u);
        if (u->watching)
            for (int i = 0; i < 2; i++)
                AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &default_addresses[i], default_changed, u);
        /* a stop from inside the unit's own thread leaves it finishing */
        for (int tries = 0; tries < 500; tries++) {
            pthread_mutex_lock(&u->lock);
            int busy = u->running;
            pthread_mutex_unlock(&u->lock);
            if (!busy)
                break;
            ca_sleep_ns(2000000);
        }
    }
    while (u->listeners) {
        unit_listener *l = u->listeners;
        u->listeners = l->next;
        free(l);
    }
    while (u->notifies) {
        render_notify *r = u->notifies;
        u->notifies = r->next;
        free(r);
    }
    for (int i = 0; i < 2; i++) {
        free(u->map[i]);
        free(u->layout[i]);
    }
    for (int i = 0; i < CA_MAX_CHANNELS; i++)
        free(u->own[i]);
    free(u->capture);
    pthread_mutex_destroy(&u->lock);
    free(u);
    return noErr;
}

/* ---- properties ---------------------------------------------------------------------------------- */

typedef struct uvalue {
    UInt32 size;
    union {
        unsigned char bytes[1024];
        UInt32 u32;
        Float64 f64;
        AudioStreamBasicDescription asbd;
    };
    void *heap; /* a value too big for bytes */
} uvalue;

static void uput(uvalue *v, const void *p, UInt32 n)
{
    if (n <= sizeof v->bytes) {
        memcpy(v->bytes, p, n);
        v->heap = NULL;
    } else {
        v->heap = malloc(n);
        memcpy(v->heap, p, n);
    }
    v->size = n;
}

static const void *ubytes(const uvalue *v)
{
    return v->heap ? v->heap : v->bytes;
}

static void uput32(uvalue *v, UInt32 x)
{
    uput(v, &x, 4);
}

/* a property the HAL's device answers for the unit: device properties,
 * whose IDs are four-character codes */
static int is_device_property(AudioUnitPropertyID id)
{
    return id >= 0x20202020;
}

static AudioObjectPropertyAddress device_address(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope scope)
{
    /* the input scope is the device's input, and the global and output
     * scopes its output, or its input for a unit that only records */
    int input = scope == kAudioUnitScope_Input ||
                (scope == kAudioUnitScope_Global && u->kind == KIND_HAL && u->enable[CA_IN] && !u->enable[CA_OUT]);
    AudioObjectPropertyAddress a = {id, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
                                    kAudioObjectPropertyElementMain};
    return a;
}

static int scope_ok(AudioUnitScope s)
{
    return s == kAudioUnitScope_Global || s == kAudioUnitScope_Input || s == kAudioUnitScope_Output;
}

/* which bus side a stream format names: [CA_OUT] client, device, ... */
enum { SIDE_CLIENT_OUT, SIDE_DEVICE_OUT, SIDE_DEVICE_IN, SIDE_CLIENT_IN, SIDE_NONE };

static int format_side(AudioUnit u, AudioUnitScope scope, AudioUnitElement el)
{
    if (u->kind == KIND_GENERIC) {
        if (el != 0)
            return SIDE_NONE;
        return scope == kAudioUnitScope_Input ? SIDE_CLIENT_OUT : scope == kAudioUnitScope_Output ? SIDE_DEVICE_OUT
                                                                                                    : SIDE_NONE;
    }
    if (el == 0)
        return scope == kAudioUnitScope_Input ? SIDE_CLIENT_OUT : scope == kAudioUnitScope_Output ? SIDE_DEVICE_OUT
                                                                                                    : SIDE_NONE;
    if (el == 1 && u->kind == KIND_HAL)
        return scope == kAudioUnitScope_Input ? SIDE_DEVICE_IN : scope == kAudioUnitScope_Output ? SIDE_CLIENT_IN
                                                                                                   : SIDE_NONE;
    return SIDE_NONE;
}

static void side_format(AudioUnit u, int side, AudioStreamBasicDescription *f)
{
    switch (side) {
    case SIDE_CLIENT_OUT: client_side(u, CA_OUT, f); break;
    case SIDE_CLIENT_IN: client_side(u, CA_IN, f); break;
    case SIDE_DEVICE_IN: device_side(u, CA_IN, f); break;
    default:
        if (u->kind == KIND_GENERIC) {
            if (u->generic_out_set)
                *f = u->generic_out;
            else
                client_side(u, CA_OUT, f);
        } else
            device_side(u, CA_OUT, f);
    }
}

static OSStatus unit_get(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el,
                         uvalue *v, Boolean *writable)
{
    Boolean w = 0;
    OSStatus err = noErr;
    v->heap = NULL;
    if (!scope_ok(scope))
        return kAudioUnitErr_InvalidScope;
    switch (id) {
    case kAudioUnitProperty_StreamFormat:
    case kAudioUnitProperty_SampleRate: {
        int side = format_side(u, scope, el);
        if (side == SIDE_NONE)
            return scope == kAudioUnitScope_Global ? kAudioUnitErr_InvalidScope : kAudioUnitErr_InvalidElement;
        AudioStreamBasicDescription f;
        side_format(u, side, &f);
        if (id == kAudioUnitProperty_SampleRate)
            uput(v, &f.mSampleRate, sizeof f.mSampleRate);
        else
            uput(v, &f, sizeof f);
        w = 1;
        break;
    }
    case kAudioUnitProperty_ElementCount:
        uput32(v, scope == kAudioUnitScope_Global ? 1 : (u->kind == KIND_HAL ? 2 : 1));
        w = 0;
        break;
    case kAudioUnitProperty_MaximumFramesPerSlice:
        uput32(v, u->max_frames);
        w = 1;
        break;
    case kAudioUnitProperty_Latency: {
        Float64 s = 0;
        ca_device *d = ca_device_for(unit_device(u));
        if (d) {
            pthread_mutex_lock(ca_lock());
            s = d->rate > 0 ? d->latency[CA_OUT] / d->rate : 0;
            pthread_mutex_unlock(ca_lock());
        }
        uput(v, &s, sizeof s);
        break;
    }
    case kAudioUnitProperty_TailTime: {
        Float64 s = 0;
        uput(v, &s, sizeof s);
        break;
    }
    case kAudioUnitProperty_CPULoad: {
        Float32 load = 0;
        uput(v, &load, sizeof load);
        w = 1;
        break;
    }
    case kAudioUnitProperty_LastRenderError:
        uput32(v, (UInt32)u->last_error);
        u->last_error = noErr;
        break;
    case kAudioUnitProperty_SetRenderCallback:
        uput(v, &u->render, sizeof u->render);
        w = 1;
        break;
    case kAudioUnitProperty_ShouldAllocateBuffer:
        uput32(v, u->should_allocate);
        w = 1;
        break;
    case kAudioUnitProperty_ParameterList: {
        if (u->kind == KIND_GENERIC || scope != kAudioUnitScope_Global) {
            uput(v, NULL, 0);
            break;
        }
        uput32(v, kHALOutputParam_Volume);
        break;
    }
    case kAudioUnitProperty_ParameterInfo: {
        if (u->kind == KIND_GENERIC || el != kHALOutputParam_Volume)
            return kAudioUnitErr_InvalidParameter;
        AudioUnitParameterInfo info;
        memset(&info, 0, sizeof info);
        snprintf(info.name, sizeof info.name, "Volume");
        info.unit = kAudioUnitParameterUnit_LinearGain;
        info.minValue = 0;
        info.maxValue = 1;
        info.defaultValue = 1;
        info.flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
        uput(v, &info, sizeof info);
        break;
    }
    case kAudioUnitProperty_AudioChannelLayout: {
        int dir = scope == kAudioUnitScope_Input && el == 0 ? CA_OUT
                  : scope == kAudioUnitScope_Output && el == 1 ? CA_IN
                                                               : -1;
        if (dir < 0)
            return kAudioUnitErr_InvalidPropertyValue;
        if (u->layout[dir])
            uput(v, u->layout[dir], u->layout_size[dir]);
        else {
            AudioStreamBasicDescription f;
            client_side(u, dir, &f);
            UInt32 labels[CA_MAX_CHANNELS], size;
            UInt32 n = f.mChannelsPerFrame < CA_MAX_CHANNELS ? f.mChannelsPerFrame : CA_MAX_CHANNELS;
            ca_default_labels(n, labels);
            AudioChannelLayout *l = ca_layout_with_labels(labels, n, &size);
            uput(v, l, size);
            free(l);
        }
        w = 1;
        break;
    }
    case kAudioOutputUnitProperty_CurrentDevice:
        if (!has_device(u))
            return kAudioUnitErr_InvalidProperty;
        uput32(v, unit_device(u));
        w = u->kind == KIND_HAL;
        break;
    case kAudioOutputUnitProperty_IsRunning:
        uput32(v, (UInt32)u->running);
        break;
    case kAudioOutputUnitProperty_EnableIO:
        if (u->kind != KIND_HAL)
            return kAudioUnitErr_InvalidProperty;
        if (el > 1)
            return kAudioUnitErr_InvalidElement;
        uput32(v, u->enable[el == 1 ? CA_IN : CA_OUT]);
        w = 1;
        break;
    case kAudioOutputUnitProperty_HasIO: {
        if (!has_device(u))
            return kAudioUnitErr_InvalidProperty;
        if (el > 1 || (el == 1 && u->kind != KIND_HAL))
            return kAudioUnitErr_InvalidElement;
        ca_device *d = ca_device_for(unit_device(u));
        uput32(v, d && d->stream[el == 1 ? CA_IN : CA_OUT] ? 1 : 0);
        break;
    }
    case kAudioOutputUnitProperty_ChannelMap: {
        if (u->kind != KIND_HAL || scope != kAudioUnitScope_Output || el > 1)
            return kAudioUnitErr_InvalidProperty;
        int dir = el == 1 ? CA_IN : CA_OUT;
        if (u->map[dir])
            uput(v, u->map[dir], u->map_count[dir] * sizeof(SInt32));
        else {
            /* the identity: each device or client channel to its own */
            AudioStreamBasicDescription f;
            if (dir == CA_IN)
                client_side(u, CA_IN, &f);
            else
                device_side(u, CA_OUT, &f);
            SInt32 m[CA_MAX_CHANNELS];
            UInt32 n = f.mChannelsPerFrame < CA_MAX_CHANNELS ? f.mChannelsPerFrame : CA_MAX_CHANNELS;
            for (UInt32 i = 0; i < n; i++)
                m[i] = (SInt32)i;
            uput(v, m, n * sizeof(SInt32));
        }
        w = 1;
        break;
    }
    case kAudioOutputUnitProperty_SetInputCallback:
        if (u->kind != KIND_HAL)
            return kAudioUnitErr_InvalidProperty;
        uput(v, &u->input, sizeof u->input);
        w = 1;
        break;
    case kAudioUnitProperty_RenderQuality:
        uput32(v, u->render_quality);
        w = 1;
        break;
    case kAudioOutputUnitProperty_StartTimestampsAtZero:
        uput32(v, u->start_at_zero);
        w = 1;
        break;
    default:
        if (has_device(u) && is_device_property(id)) {
            AudioObjectPropertyAddress a = device_address(u, id, scope);
            AudioObjectID dev = unit_device(u);
            UInt32 size = 0;
            err = AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &size);
            if (err)
                return kAudioUnitErr_InvalidProperty;
            void *data = calloc(1, size ? size : 1);
            err = AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, data);
            if (!err) {
                uput(v, data, size);
                AudioObjectIsPropertySettable(dev, &a, &w);
            }
            free(data);
            if (err)
                return kAudioUnitErr_InvalidProperty;
            break;
        }
        return kAudioUnitErr_InvalidProperty;
    }
    if (writable)
        *writable = w;
    return err;
}

OSStatus AudioUnitGetPropertyInfo(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el,
                                  UInt32 *size, Boolean *writable)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_GET_PROPERTY_INFO, OSStatus (*)(void *, UInt32, UInt32, UInt32, UInt32 *, Boolean *), id,
                    scope, el, size, writable);
    uvalue v;
    pthread_mutex_lock(&u->lock);
    OSStatus err = unit_get(u, id, scope, el, &v, writable);
    pthread_mutex_unlock(&u->lock);
    if (!err && size)
        *size = v.size;
    free(v.heap);
    return err;
}

OSStatus AudioUnitGetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el,
                              void *data, UInt32 *size)
{
    if (!u || !size)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_GET_PROPERTY, OSStatus (*)(void *, UInt32, UInt32, UInt32, void *, UInt32 *), id, scope,
                    el, data, size);
    uvalue v;
    pthread_mutex_lock(&u->lock);
    OSStatus err = unit_get(u, id, scope, el, &v, NULL);
    pthread_mutex_unlock(&u->lock);
    if (!err) {
        if (!data)
            *size = v.size;
        else {
            /* a short buffer gets what fits, as a Mac's units copy it:
             * PortAudio reads IsRunning into a 1-byte Boolean */
            UInt32 n = *size >= v.size                            ? v.size
                       : id == kAudioOutputUnitProperty_ChannelMap ? *size / 4 * 4
                                                                   : *size;
            memcpy(data, ubytes(&v), n);
            *size = n;
        }
    }
    free(v.heap);
    return err;
}

static OSStatus need(UInt32 size, UInt32 want)
{
    return size < want ? kAudio_ParamError : noErr;
}

OSStatus AudioUnitSetProperty(AudioUnit u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el,
                              const void *data, UInt32 size)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_SET_PROPERTY, OSStatus (*)(void *, UInt32, UInt32, UInt32, const void *, UInt32), id,
                    scope, el, data, size);
    if (!scope_ok(scope))
        return kAudioUnitErr_InvalidScope;
    OSStatus err = noErr;
    int notify_formats = 0;
    pthread_mutex_lock(&u->lock);
    switch (id) {
    case kAudioUnitProperty_StreamFormat:
    case kAudioUnitProperty_SampleRate: {
        int side = format_side(u, scope, el);
        if (side == SIDE_NONE) {
            err = scope == kAudioUnitScope_Global ? kAudioUnitErr_InvalidScope : kAudioUnitErr_InvalidElement;
            break;
        }
        AudioStreamBasicDescription f;
        if (id == kAudioUnitProperty_SampleRate) {
            if ((err = need(size, sizeof(Float64))) || !data)
                break;
            side_format(u, side, &f);
            f.mSampleRate = *(const Float64 *)data;
        } else {
            if (!data || (err = need(size, sizeof f)))
                break;
            f = *(const AudioStreamBasicDescription *)data;
        }
        ca_pcm p;
        if (ca_pcm_parse(&f, &p) || f.mSampleRate <= 0 || f.mSampleRate > 384000) {
            err = kAudioUnitErr_FormatNotSupported;
            break;
        }
        if (u->running) {
            err = kAudioUnitErr_CannotDoInCurrentContext;
            break;
        }
        if (side == SIDE_CLIENT_OUT || side == SIDE_CLIENT_IN) {
            int dir = side == SIDE_CLIENT_OUT ? CA_OUT : CA_IN;
            u->client[dir] = f;
            u->client_set[dir] = 1;
        } else if (u->kind == KIND_GENERIC) {
            u->generic_out = f;
            u->generic_out_set = 1;
        } else {
            /* the device's side: the device keeps its channels, and the
             * server converts any rate, so only a matching format is taken */
            AudioStreamBasicDescription d;
            side_format(u, side, &d);
            if (f.mChannelsPerFrame != d.mChannelsPerFrame)
                err = kAudioUnitErr_FormatNotSupported;
        }
        notify_formats = !err;
        break;
    }
    case kAudioUnitProperty_MaximumFramesPerSlice:
        if (!data || (err = need(size, 4)))
            break;
        if (*(const UInt32 *)data < 16 || *(const UInt32 *)data > 65536)
            err = kAudioUnitErr_InvalidPropertyValue;
        else if (u->running)
            err = kAudioUnitErr_Initialized;
        else
            u->max_frames = *(const UInt32 *)data;
        break;
    case kAudioUnitProperty_SetRenderCallback:
        /* any scope: PortAudio, which Audacity plays through, sets it on
         * the output scope, and a Mac's output units take it there too */
        if (!data || size == 0)
            memset(&u->render, 0, sizeof u->render);
        else if (!(err = need(size, sizeof u->render)))
            u->render = *(const AURenderCallbackStruct *)data;
        break;
    case kAudioUnitProperty_ShouldAllocateBuffer:
        if (!data || (err = need(size, 4)))
            break;
        u->should_allocate = *(const UInt32 *)data;
        break;
    case kAudioUnitProperty_CPULoad: break;
    case kAudioUnitProperty_AudioChannelLayout: {
        int dir = scope == kAudioUnitScope_Input && el == 0 ? CA_OUT
                  : scope == kAudioUnitScope_Output && el == 1 ? CA_IN
                                                               : -1;
        if (dir < 0) {
            err = kAudioUnitErr_InvalidScope;
            break;
        }
        if (!data || !size) {
            free(u->layout[dir]);
            u->layout[dir] = NULL;
            break;
        }
        if ((err = need(size, offsetof(AudioChannelLayout, mChannelDescriptions))))
            break;
        free(u->layout[dir]);
        u->layout[dir] = malloc(size);
        memcpy(u->layout[dir], data, size);
        u->layout_size[dir] = size;
        break;
    }
    case kAudioOutputUnitProperty_CurrentDevice: {
        if (!has_device(u)) {
            err = kAudioUnitErr_InvalidProperty;
            break;
        }
        if (!data || (err = need(size, 4)))
            break;
        AudioObjectID dev = *(const AudioObjectID *)data;
        if (u->kind != KIND_HAL) {
            err = dev == unit_device(u) ? noErr : kAudioUnitErr_InvalidPropertyValue;
            break;
        }
        ca_device *d = dev ? ca_device_for(dev) : NULL;
        if (dev && (!d || !d->alive)) {
            err = kAudioUnitErr_InvalidPropertyValue;
            break;
        }
        u->device = dev;
        u->reopen = 1;
        notify_formats = 1;
        break;
    }
    case kAudioOutputUnitProperty_EnableIO:
        if (u->kind != KIND_HAL) {
            err = kAudioUnitErr_InvalidProperty;
            break;
        }
        if (el > 1) {
            err = kAudioUnitErr_InvalidElement;
            break;
        }
        if (!data || (err = need(size, 4)))
            break;
        if (u->initialized) {
            err = kAudioUnitErr_Initialized;
            break;
        }
        u->enable[el == 1 ? CA_IN : CA_OUT] = *(const UInt32 *)data ? 1 : 0;
        break;
    case kAudioOutputUnitProperty_ChannelMap: {
        if (u->kind != KIND_HAL || scope != kAudioUnitScope_Output || el > 1) {
            err = kAudioUnitErr_InvalidProperty;
            break;
        }
        int dir = el == 1 ? CA_IN : CA_OUT;
        free(u->map[dir]);
        u->map[dir] = NULL;
        u->map_count[dir] = 0;
        if (data && size >= 4) {
            u->map_count[dir] = size / 4;
            u->map[dir] = malloc(size);
            memcpy(u->map[dir], data, u->map_count[dir] * 4);
        }
        u->reopen = 1;
        break;
    }
    case kAudioOutputUnitProperty_SetInputCallback:
        if (u->kind != KIND_HAL) {
            err = kAudioUnitErr_InvalidProperty;
            break;
        }
        if (!data || size == 0)
            memset(&u->input, 0, sizeof u->input);
        else if (!(err = need(size, sizeof u->input)))
            u->input = *(const AURenderCallbackStruct *)data;
        break;
    case kAudioUnitProperty_RenderQuality:
        if (!data || (err = need(size, 4)))
            break;
        u->render_quality = *(const UInt32 *)data;
        break;
    case kAudioOutputUnitProperty_StartTimestampsAtZero:
        if (!data || (err = need(size, 4)))
            break;
        u->start_at_zero = *(const UInt32 *)data;
        break;
    default:
        if (has_device(u) && is_device_property(id)) {
            AudioObjectPropertyAddress a = device_address(u, id, scope);
            AudioObjectID dev = unit_device(u);
            pthread_mutex_unlock(&u->lock);
            err = AudioObjectSetPropertyData(dev, &a, 0, NULL, size, data);
            if (err == kAudioHardwareUnknownPropertyError)
                err = kAudioUnitErr_InvalidProperty;
            if (!err)
                listen_unit(u, id, scope, el);
            return err;
        }
        err = kAudioUnitErr_InvalidProperty;
    }
    pthread_mutex_unlock(&u->lock);
    if (!err) {
        listen_unit(u, id, scope, el);
        if (notify_formats && id != kAudioUnitProperty_StreamFormat)
            listen_unit(u, kAudioUnitProperty_StreamFormat, scope, el);
    }
    return err;
}

OSStatus AudioUnitAddPropertyListener(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc,
                                      void *ref)
{
    if (!u || !proc)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_ADD_PROPERTY_LISTENER, OSStatus (*)(void *, UInt32, AudioUnitPropertyListenerProc, void *),
                    id, proc, ref);
    unit_listener *l = calloc(1, sizeof *l);
    if (!l)
        return kAudio_MemFullError;
    l->id = id;
    l->proc = proc;
    l->ref = ref;
    pthread_mutex_lock(&u->lock);
    l->next = u->listeners;
    u->listeners = l;
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

static OSStatus remove_listeners(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc, void *ref,
                                 int any_ref)
{
    pthread_mutex_lock(&u->lock);
    for (unit_listener **p = &u->listeners; *p;) {
        unit_listener *l = *p;
        if (l->id == id && l->proc == proc && (any_ref || l->ref == ref)) {
            *p = l->next;
            free(l);
        } else
            p = &l->next;
    }
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

OSStatus AudioUnitRemovePropertyListenerWithUserData(AudioUnit u, AudioUnitPropertyID id,
                                                     AudioUnitPropertyListenerProc proc, void *ref)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_REMOVE_PROPERTY_LISTENER_WITH_USER_DATA,
                    OSStatus (*)(void *, UInt32, AudioUnitPropertyListenerProc, void *), id, proc, ref);
    return remove_listeners(u, id, proc, ref, 0);
}

OSStatus AudioUnitRemovePropertyListener(AudioUnit u, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_REMOVE_PROPERTY_LISTENER, OSStatus (*)(void *, UInt32, AudioUnitPropertyListenerProc), id,
                    proc);
    return remove_listeners(u, id, proc, NULL, 1);
}

OSStatus AudioUnitAddRenderNotify(AudioUnit u, AURenderCallback proc, void *ref)
{
    if (!u || !proc)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_ADD_RENDER_NOTIFY, OSStatus (*)(void *, AURenderCallback, void *), proc, ref);
    render_notify *r = calloc(1, sizeof *r);
    if (!r)
        return kAudio_MemFullError;
    r->proc = proc;
    r->ref = ref;
    pthread_mutex_lock(&u->lock);
    r->next = u->notifies;
    u->notifies = r;
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

OSStatus AudioUnitRemoveRenderNotify(AudioUnit u, AURenderCallback proc, void *ref)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_REMOVE_RENDER_NOTIFY, OSStatus (*)(void *, AURenderCallback, void *), proc, ref);
    pthread_mutex_lock(&u->lock);
    for (render_notify **p = &u->notifies; *p; p = &(*p)->next)
        if ((*p)->proc == proc && (*p)->ref == ref) {
            /* a render cycle may still hold it, so it's kept */
            *p = (*p)->next;
            break;
        }
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

/* ---- parameters ------------------------------------------------------------------------------------ */

OSStatus AudioUnitGetParameter(AudioUnit u, AudioUnitParameterID id, AudioUnitScope scope, AudioUnitElement el,
                               AudioUnitParameterValue *out)
{
    if (!u || !out)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_GET_PARAMETER, OSStatus (*)(void *, UInt32, UInt32, UInt32, Float32 *), id, scope, el,
                    out);
    if (u->kind == KIND_GENERIC || id != kHALOutputParam_Volume)
        return kAudioUnitErr_InvalidParameter;
    pthread_mutex_lock(&u->lock);
    *out = u->volume;
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

OSStatus AudioUnitSetParameter(AudioUnit u, AudioUnitParameterID id, AudioUnitScope scope, AudioUnitElement el,
                               AudioUnitParameterValue value, UInt32 offset)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_SET_PARAMETER, OSStatus (*)(void *, UInt32, UInt32, UInt32, Float32, UInt32), id, scope,
                    el, value, offset);
    if (u->kind == KIND_GENERIC || id != kHALOutputParam_Volume)
        return kAudioUnitErr_InvalidParameter;
    if (!(value >= 0.0f))
        value = 0.0f;
    if (value > 1.0f)
        value = 1.0f;
    pthread_mutex_lock(&u->lock);
    u->volume = value;
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

OSStatus AudioUnitScheduleParameters(AudioUnit u, const AudioUnitParameterEvent *events, UInt32 n)
{
    if (!u || (n && !events))
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_SCHEDULE_PARAMETERS, OSStatus (*)(void *, const AudioUnitParameterEvent *, UInt32), events,
                    n);
    for (UInt32 i = 0; i < n; i++) {
        const AudioUnitParameterEvent *e = &events[i];
        Float32 v = e->eventType == kParameterEvent_Ramped ? e->eventValues.ramp.endValue
                                                           : e->eventValues.immediate.value;
        OSStatus err = AudioUnitSetParameter(u, e->parameter, e->scope, e->element, v, 0);
        if (err)
            return err;
    }
    return noErr;
}

OSStatus AudioUnitReset(AudioUnit u, AudioUnitScope scope, AudioUnitElement el)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_RESET, OSStatus (*)(void *, UInt32, UInt32), scope, el);
    pthread_mutex_lock(&u->lock);
    u->capture_frames = 0;
    pthread_mutex_unlock(&u->lock);
    return noErr;
}

/* ---- rendering on the program's thread --------------------------------------------------------------- */

/* points a program's empty buffers at the unit's own */
static OSStatus own_buffers(AudioUnit u, const ca_pcm *p, UInt32 frames, AudioBufferList *l)
{
    UInt32 want = p->non_interleaved ? p->channels : 1;
    if (l->mNumberBuffers < want)
        return kAudio_ParamError;
    if (want > CA_MAX_CHANNELS)
        return kAudio_ParamError;
    UInt32 bytes = frames * p->bytes_per_frame;
    if (u->own_bytes < bytes) {
        /* bigger buffers, before any is handed out */
        for (UInt32 k = 0; k < CA_MAX_CHANNELS; k++) {
            free(u->own[k]);
            u->own[k] = NULL;
        }
        u->own_bytes = bytes;
    }
    for (UInt32 i = 0; i < want; i++) {
        if (l->mBuffers[i].mData)
            continue;
        if (!u->own[i])
            u->own[i] = calloc(1, u->own_bytes);
        l->mBuffers[i].mData = u->own[i];
        l->mBuffers[i].mDataByteSize = bytes;
    }
    return noErr;
}

static OSStatus render_capture(AudioUnit u, AudioUnitRenderActionFlags *flags, UInt32 frames, AudioBufferList *l)
{
    AudioStreamBasicDescription f;
    client_side(u, CA_IN, &f);
    ca_pcm p;
    if (ca_pcm_parse(&f, &p))
        return kAudioUnitErr_FormatNotSupported;
    if (!u->enable[CA_IN] || !u->running)
        return kAudioUnitErr_CannotDoInCurrentContext;
    if (frames > u->max_frames)
        return kAudioUnitErr_TooManyFramesToProcess;
    OSStatus err = own_buffers(u, &p, frames, l);
    if (err)
        return err;
    for (UInt32 i = 0; i < l->mNumberBuffers; i++)
        if (l->mBuffers[i].mDataByteSize < frames * p.bytes_per_frame)
            return kAudio_ParamError;
    float *client = calloc((size_t)frames * p.channels, sizeof(float));
    if (!client)
        return kAudio_MemFullError;
    UInt32 have = u->capture_frames < frames ? u->capture_frames : frames;
    UInt32 cch = u->capture_channels;
    for (UInt32 i = 0; i < have; i++)
        for (UInt32 c = 0; c < p.channels; c++) {
            SInt32 from = u->map[CA_IN] ? (c < u->map_count[CA_IN] ? u->map[CA_IN][c] : -1) : (SInt32)c;
            client[(size_t)i * p.channels + c] =
                from >= 0 && (UInt32)from < cch ? u->capture[(size_t)i * cch + (UInt32)from] : 0.0f;
        }
    ca_pcm_from_float(&p, client, frames, l);
    free(client);
    if (!have && flags)
        *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}

static OSStatus render_pull(AudioUnit u, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 frames,
                            AudioBufferList *l)
{
    AURenderCallbackStruct render = u->render;
    if (!render.inputProc)
        return kAudioUnitErr_NoConnection;
    if (frames > u->max_frames)
        return kAudioUnitErr_TooManyFramesToProcess;
    AudioStreamBasicDescription fin, fout;
    side_format(u, SIDE_CLIENT_OUT, &fin);
    side_format(u, SIDE_DEVICE_OUT, &fout);
    AudioUnitRenderActionFlags own = 0;
    if (!flags)
        flags = &own;
    if (u->kind != KIND_GENERIC || !memcmp(&fin, &fout, sizeof fin)) {
        call_notifies(u, kAudioUnitRenderAction_PreRender, t, 0, frames, l);
        OSStatus err = render.inputProc(render.inputProcRefCon, flags, t, 0, frames, l);
        call_notifies(u, kAudioUnitRenderAction_PostRender | (err ? kAudioUnitRenderAction_PostRenderError : 0), t, 0,
                      frames, l);
        return err;
    }
    /* generic output converts its input's format to its output's */
    ca_pcm pi, po;
    if (ca_pcm_parse(&fin, &pi) || ca_pcm_parse(&fout, &po) || fin.mSampleRate != fout.mSampleRate)
        return kAudioUnitErr_FormatNotSupported;
    AudioBufferList *tmp = new_list(&pi, frames);
    float *a = calloc((size_t)frames * pi.channels, sizeof(float));
    float *b = calloc((size_t)frames * po.channels, sizeof(float));
    call_notifies(u, kAudioUnitRenderAction_PreRender, t, 0, frames, l);
    OSStatus err = render.inputProc(render.inputProcRefCon, flags, t, 0, frames, tmp);
    if (!err) {
        ca_pcm_to_float(&pi, tmp, frames, a);
        for (UInt32 i = 0; i < frames; i++)
            for (UInt32 c = 0; c < po.channels; c++)
                b[(size_t)i * po.channels + c] = c < pi.channels ? a[(size_t)i * pi.channels + c] : 0.0f;
        ca_pcm_from_float(&po, b, frames, l);
    }
    call_notifies(u, kAudioUnitRenderAction_PostRender | (err ? kAudioUnitRenderAction_PostRenderError : 0), t, 0,
                  frames, l);
    free(a);
    free(b);
    free_list(tmp);
    return err;
}

OSStatus AudioUnitRender(AudioUnit u, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 bus,
                         UInt32 frames, AudioBufferList *l)
{
    if (!u || !l || !t)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_RENDER,
                    OSStatus (*)(void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32,
                                 AudioBufferList *),
                    flags, t, bus, frames, l);
    if (bus == 1 && u->kind == KIND_HAL) {
        pthread_mutex_lock(&u->lock);
        OSStatus err = render_capture(u, flags, frames, l);
        pthread_mutex_unlock(&u->lock);
        return err;
    }
    if (bus != 0)
        return kAudioUnitErr_InvalidElement;
    if (!u->initialized)
        return kAudioUnitErr_Uninitialized;
    return render_pull(u, flags, t, frames, l);
}

OSStatus AudioUnitProcess(AudioUnit u, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 frames,
                          AudioBufferList *l)
{
    if (!u)
        return kAudio_ParamError;
    if (u->plugin)
        PLUGIN_CALL(u, SEL_PROCESS,
                    OSStatus (*)(void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32,
                                 AudioBufferList *),
                    flags, t, frames, l);
    return kAudio_UnimplementedError; /* output units have no in-place processing */
}
